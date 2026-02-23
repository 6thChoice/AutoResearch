#!/usr/bin/env python3
"""
Stop hook for claude code — triggered when claude finishes a task.
Generates a richer report MD in /app/reports/ by summarizing the
task prompt, Claude's jsonl activity, and git changes.
"""

import json
import os
import subprocess
import sys
from datetime import datetime
from pathlib import Path

REPORTS_DIR = Path("/app/reports")
WORKSPACE = Path("/app/workspace")
TASKS_DIR = Path("/app/tasks")
CLAUDE_HOME = Path.home() / ".claude"
PROJECTS_DIR = CLAUDE_HOME / "projects" / "-app-workspace"

REPORT_HOME = Path("/tmp/claude-report")
REPORT_CLAUDE_HOME = REPORT_HOME / ".claude"
REPORT_SETTINGS = {"hooks": {}}

MAX_ACTIVITY_CHARS = 6000
MAX_ITEM_CHARS = 400
MAX_ITEMS = 40


def get_git_summary() -> str:
    """Get a brief git status/diff summary from workspace."""
    lines = []
    try:
        status = subprocess.run(
            ["git", "status", "--short"],
            cwd=str(WORKSPACE),
            capture_output=True, text=True, timeout=5,
        )
        if status.stdout.strip():
            lines.append("### Changed Files")
            lines.append("```")
            lines.append(status.stdout.strip())
            lines.append("```")

        diff_stat = subprocess.run(
            ["git", "diff", "--stat", "HEAD"],
            cwd=str(WORKSPACE),
            capture_output=True, text=True, timeout=5,
        )
        if diff_stat.stdout.strip():
            lines.append("### Diff Summary")
            lines.append("```")
            lines.append(diff_stat.stdout.strip())
            lines.append("```")
    except Exception:
        lines.append("(git info unavailable)")

    return "\n".join(lines)


def read_task_file(task_id: str) -> str:
    """Read the task markdown that was executed (from done/ preferred)."""
    done_path = TASKS_DIR / "done" / f"{task_id}.md"
    live_path = TASKS_DIR / f"{task_id}.md"

    if done_path.exists():
        return done_path.read_text(encoding="utf-8")
    if live_path.exists():
        return live_path.read_text(encoding="utf-8")
    return ""


def find_jsonl_for_task(task_id: str) -> Path | None:
    """Locate the jsonl file that contains the TASK_ID marker."""
    marker = f"<!-- TASK_ID: {task_id} -->"
    if not PROJECTS_DIR.exists():
        return None

    jsonl_files = sorted(
        PROJECTS_DIR.glob("*.jsonl"),
        key=lambda p: p.stat().st_mtime,
        reverse=True,
    )
    for path in jsonl_files:
        try:
            with path.open("r", encoding="utf-8") as f:
                for line in f:
                    if marker in line:
                        return path
        except Exception:
            continue
    return None


def _push_limited(items: list[str], text: str, total_chars: int) -> int:
    if len(items) >= MAX_ITEMS:
        return total_chars
    text = text.strip()
    if not text:
        return total_chars
    if len(text) > MAX_ITEM_CHARS:
        text = text[:MAX_ITEM_CHARS] + " ..."
    if total_chars + len(text) > MAX_ACTIVITY_CHARS:
        return total_chars
    items.append(text)
    return total_chars + len(text)


def extract_activity(jsonl_path: Path | None) -> str:
    """Extract a compact activity summary from Claude's jsonl."""
    if jsonl_path is None or not jsonl_path.exists():
        return "(no jsonl activity found)"

    tool_uses: list[str] = []
    tool_results: list[str] = []
    assistant_texts: list[str] = []
    total_chars = 0

    try:
        with jsonl_path.open("r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                except Exception:
                    continue

                message = obj.get("message")
                if not message:
                    continue
                content = message.get("content")
                if not isinstance(content, list):
                    continue

                for entry in content:
                    if not isinstance(entry, dict):
                        continue
                    etype = entry.get("type")
                    if etype == "tool_use":
                        name = entry.get("name", "tool")
                        cmd = ""
                        inp = entry.get("input", {})
                        if isinstance(inp, dict):
                            cmd = inp.get("command") or inp.get("input") or ""
                        text = f"{name}: {cmd}".strip()
                        total_chars = _push_limited(tool_uses, text, total_chars)
                    elif etype == "tool_result":
                        content_text = entry.get("content", "")
                        if isinstance(content_text, (dict, list)):
                            content_text = json.dumps(content_text)
                        total_chars = _push_limited(tool_results, str(content_text), total_chars)
                    elif etype == "text":
                        text = entry.get("text", "")
                        total_chars = _push_limited(assistant_texts, text, total_chars)

                if total_chars >= MAX_ACTIVITY_CHARS:
                    break
    except Exception:
        return "(failed to parse jsonl activity)"

    sections = []
    if tool_uses:
        sections.append("Tool Uses:")
        sections.extend(f"- {t}" for t in tool_uses[-MAX_ITEMS:])
    if tool_results:
        sections.append("Tool Results:")
        sections.extend(f"- {t}" for t in tool_results[-MAX_ITEMS:])
    if assistant_texts:
        sections.append("Assistant Output:")
        sections.extend(f"- {t}" for t in assistant_texts[-MAX_ITEMS:])

    return "\n".join(sections) if sections else "(no activity extracted)"


def ensure_report_claude_home():
    REPORT_CLAUDE_HOME.mkdir(parents=True, exist_ok=True)
    settings_file = REPORT_CLAUDE_HOME / "settings.json"
    if not settings_file.exists():
        settings_file.write_text(json.dumps(REPORT_SETTINGS, indent=2))


def generate_report_body(task_text: str, activity: str, git_summary: str) -> str:
    """Call Claude to generate the report body."""
    ensure_report_claude_home()
    prompt = f"""你是一个执行报告生成器。根据输入生成结构良好但不死板的报告正文（Markdown）。

要求：
- 不要写顶层标题（# Task Report）
- 不要重复 Completed/Status 行
- 重点覆盖：进度、采用的方案、遇到的问题与对策、关键结果
- 结合当前任务内容，避免空泛
- 不要输出大段原始日志，只做摘要

【任务内容】
```markdown
{task_text.strip()}
```

【执行轨迹摘要】
```text
{activity.strip()}
```

【Git 变化摘要】
```text
{git_summary.strip()}
```

请输出报告正文。"""

    env = os.environ.copy()
    env["HOME"] = str(REPORT_HOME)

    try:
        result = subprocess.run(
            [
                "claude",
                "--print",
                "--output-format", "text",
                "--max-turns", "1",
                "--permission-mode", "bypassPermissions",
                "-p", prompt,
            ],
            env=env,
            capture_output=True,
            text=True,
            timeout=180,
        )
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout.strip()
    except Exception:
        pass

    return "(failed to generate report body)"


def main():
    # Read hook JSON from stdin
    try:
        _hook_input = json.loads(sys.stdin.read())
    except Exception:
        _hook_input = {}

    task_id = os.environ.get("TASK_ID", "unknown")
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    task_text = read_task_file(task_id)
    jsonl_path = find_jsonl_for_task(task_id)
    activity = extract_activity(jsonl_path)
    git_summary = get_git_summary()

    report_body = generate_report_body(task_text, activity, git_summary)

    # Build report
    report_lines = [
        f"# Task Report: {task_id}",
        "",
        f"- Completed: {now}",
        f"- Status: completed",
        "",
        report_body,
        "",
        "## Git Changes",
        "",
        git_summary,
        "",
    ]

    report = "\n".join(report_lines)

    # Write report
    REPORTS_DIR.mkdir(parents=True, exist_ok=True)
    report_file = REPORTS_DIR / f"report-{task_id}.md"
    report_file.write_text(report, encoding="utf-8")

    print(f"[hook] Report written: {report_file.name}", file=sys.stderr)


if __name__ == "__main__":
    main()
