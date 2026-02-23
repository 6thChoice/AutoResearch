#!/usr/bin/env python3
"""
codingAgent monitor — watches /app/tasks/ for new .md files,
runs claude code with the task content, then moves the task to done/.
"""

import json
import os
import subprocess
import sys
import time
import signal
from pathlib import Path

TASKS_DIR = Path("/app/tasks")
DONE_DIR = TASKS_DIR / "done"
WORKSPACE = Path("/app/workspace")
CLAUDE_HOME = Path.home() / ".claude"

SETTINGS_DEFAULT = {
    "hooks": {
        "Stop": [
            {
                "matcher": "*",
                "hooks": [
                    {
                        "type": "command",
                        "command": "python3 /app/scripts/on_stop_hook.py",
                        "timeout": 300,
                    }
                ],
            }
        ]
    }
}

running = True


def log(msg: str):
    print(f"[monitor] {msg}", flush=True)


def handle_signal(signum, _frame):
    global running
    log(f"Received signal {signum}, shutting down")
    running = False


def run_claude(task_file: Path):
    """Read task MD, run claude code, move task to done/."""
    task_id = task_file.stem  # e.g. "task-abc123"
    raw = task_file.read_text(encoding="utf-8").strip()
    # Embed a stable marker so stop hook can map jsonl -> task_id
    marker = f"<!-- TASK_ID: {task_id} -->"
    prompt = f"{marker}\n\n{raw}" if raw else marker

    if not prompt:
        log(f"Empty task file: {task_file.name}, skipping")
        task_file.rename(DONE_DIR / task_file.name)
        return

    log(f"Starting task: {task_id}")
    log(f"Prompt length: {len(prompt)} chars")

    env = os.environ.copy()
    env["TASK_ID"] = task_id

    try:
        result = subprocess.run(
            [
                "claude",
                "--print",
                "--output-format", "text",
                "--verbose",
                "--max-turns", "50",
                "--permission-mode", "bypassPermissions",
                "-p", prompt,
            ],
            cwd=str(WORKSPACE),
            env=env,
            capture_output=True,
            text=True,
            timeout=1800,  # 30 min max
        )

        log(f"Task {task_id} finished with exit code {result.returncode}")

        if result.stdout:
            log(f"Output length: {len(result.stdout)} chars")

        if result.returncode != 0 and result.stderr:
            log(f"Stderr: {result.stderr[:500]}")

    except subprocess.TimeoutExpired:
        log(f"Task {task_id} timed out after 30 minutes")
    except Exception as e:
        log(f"Task {task_id} failed: {e}")

    # Move task to done/
    try:
        task_file.rename(DONE_DIR / task_file.name)
        log(f"Moved {task_file.name} to done/")
    except Exception as e:
        log(f"Failed to move task file: {e}")


def process_existing_tasks():
    """Process any .md files already in tasks/ on startup."""
    for f in sorted(TASKS_DIR.glob("*.md")):
        if not running:
            break
        run_claude(f)


def watch_tasks():
    """Use inotifywait to watch for new .md files."""
    log("Watching for new tasks...")

    while running:
        try:
            result = subprocess.run(
                [
                    "inotifywait",
                    "-q", "-e", "close_write,moved_to",
                    "--format", "%f",
                    str(TASKS_DIR),
                ],
                capture_output=True,
                text=True,
                timeout=60,
            )

            filename = result.stdout.strip()
            if filename.endswith(".md"):
                task_file = TASKS_DIR / filename
                if task_file.exists():
                    # Small delay to ensure file is fully written
                    time.sleep(0.5)
                    run_claude(task_file)

        except subprocess.TimeoutExpired:
            # inotifywait timeout, just loop back
            continue
        except Exception as e:
            if running:
                log(f"Watch error: {e}")
                time.sleep(2)


def main():
    signal.signal(signal.SIGTERM, handle_signal)
    signal.signal(signal.SIGINT, handle_signal)

    log("codingAgent monitor starting")

    # Ensure claude home settings.json exists (volume mount may override image copy)
    CLAUDE_HOME.mkdir(parents=True, exist_ok=True)
    settings_file = CLAUDE_HOME / "settings.json"
    if not settings_file.exists():
        settings_file.write_text(json.dumps(SETTINGS_DEFAULT, indent=2))
        log("Created settings.json with Stop hook")

    # Verify claude is installed
    try:
        ver = subprocess.run(
            ["claude", "--version"],
            capture_output=True, text=True, timeout=10,
        )
        log(f"Claude Code version: {ver.stdout.strip()}")
    except Exception:
        log("ERROR: claude command not found")
        sys.exit(1)

    # Ensure directories exist
    DONE_DIR.mkdir(parents=True, exist_ok=True)

    # Process any tasks already waiting
    process_existing_tasks()

    # Watch for new tasks
    watch_tasks()

    log("Monitor stopped")


if __name__ == "__main__":
    main()
