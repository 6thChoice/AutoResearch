#!/bin/bash
# 快速创建任务的辅助脚本
# 用法: ./quick-task.sh "任务描述" [session_id]

PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
COMMANDS_DIR="$PROJECT_ROOT/volumes/commands/pending"

# 生成 ID
TASK_ID=$(cat /proc/sys/kernel/random/uuid | cut -d'-' -f1)
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
SESSION_ID="${2:-auto}"

# 任务描述
TASK_DESC="$1"

if [ -z "$TASK_DESC" ]; then
    echo "用法: $0 \"任务描述\" [session_id]"
    echo ""
    echo "示例:"
    echo "  $0 \"创建一个 hello.py 文件\""
    echo "  $0 \"继续修改文件\" abc123  # 继续会话"
    exit 1
fi

# 创建指令文件
OUTPUT_FILE="$COMMANDS_DIR/task-${TASK_ID}.md"

cat > "$OUTPUT_FILE" << EOF
---
id: task-${TASK_ID}
created_at: ${TIMESTAMP}
session_id: ${SESSION_ID}
command_type: $([ "$SESSION_ID" = "auto" ] && echo "new" || echo "continue")
---

# 任务指令

## 任务描述
${TASK_DESC}
EOF

echo "✅ 任务已创建: $OUTPUT_FILE"
echo "📋 任务 ID: task-${TASK_ID}"
echo "🔄 会话 ID: $SESSION_ID"
echo ""
echo "查看执行进度:"
echo "  docker logs -f claude-code-agent"
