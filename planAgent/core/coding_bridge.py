"""与 CodingAgent 的文件交互

codingAgent 协议：
- 任务：纯 Markdown 文件写入 tasks/ 目录，monitor 通过 inotifywait 检测
- 报告：Stop Hook 自动生成 reports/report-<task_id>.md（纯 Markdown，无 frontmatter）
- 上下文：不通过文件注入，而是直接拼入任务 prompt
"""

import time
import uuid
from pathlib import Path

from planAgent.config import (
    TASKS_DIR,
    REPORTS_DIR,
    REPORT_POLL_INTERVAL,
    REPORT_TIMEOUT,
)


def send_task(
    description: str,
    context: str = "",
    constraints: str = "",
    expected_output: str = "",
) -> str:
    """写任务文件到 tasks/，返回 task_id。

    codingAgent 的 monitor.py 会把文件内容整体作为 claude --print -p 的 prompt，
    所以这里直接拼成完整的 prompt 文本。
    """
    task_id = f"task-{uuid.uuid4().hex[:8]}"

    parts = []

    # 上下文（由 ContextManager 生成的项目/任务背景）
    if context:
        parts.append(context.strip())
        parts.append("")  # 空行分隔

    # 核心任务描述
    parts.append("## 任务描述")
    parts.append("")
    parts.append(description.strip())

    if constraints:
        parts.append("")
        parts.append("## 约束条件")
        parts.append("")
        parts.append(constraints.strip())

    if expected_output:
        parts.append("")
        parts.append("## 预期输出")
        parts.append("")
        parts.append(expected_output.strip())

    content = "\n".join(parts) + "\n"

    TASKS_DIR.mkdir(parents=True, exist_ok=True)
    (TASKS_DIR / f"{task_id}.md").write_text(content, encoding="utf-8")
    return task_id


def wait_for_report(task_id: str, timeout: int = REPORT_TIMEOUT) -> dict | None:
    """轮询等待报告文件，返回解析后的 dict，超时返回 None。

    codingAgent 的 on_stop_hook.py 生成 report-<task_id>.md。
    """
    report_path = REPORTS_DIR / f"report-{task_id}.md"
    deadline = time.time() + timeout

    while time.time() < deadline:
        if report_path.exists():
            return parse_report(report_path)
        time.sleep(REPORT_POLL_INTERVAL)

    return None


def parse_report(filepath: Path) -> dict:
    """解析 codingAgent 的报告（纯 Markdown，无 frontmatter）。

    报告格式示例：
        # Task Report: task-abc123
        - Completed: 2026-02-23 12:30:00
        - Status: completed
        ## Git Changes
        ...
    """
    text = filepath.read_text(encoding="utf-8")
    result = {"_raw": text, "_path": str(filepath), "body": text}

    # 提取元数据
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("- Status:"):
            result["status"] = line.split(":", 1)[1].strip()
        elif line.startswith("- Completed:"):
            result["completed"] = line.split(":", 1)[1].strip()

    return result
