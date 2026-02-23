#!/bin/bash
# Helper script to create command files

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
COMMANDS_DIR="$PROJECT_ROOT/volumes/commands/pending"

# Generate UUID
generate_uuid() {
    if command -v uuidgen &> /dev/null; then
        uuidgen | tr '[:upper:]' '[:lower:]'
    else
        cat /proc/sys/kernel/random/uuid
    fi
}

# Usage
usage() {
    echo "Usage: $0 [options] <task_description>"
    echo ""
    echo "Options:"
    echo "  -t, --type <type>       Command type: new, continue, end (default: new)"
    echo "  -s, --session <id>      Session ID (for continue/end, or 'auto' for new)"
    echo "  -f, --file <filename>   Output filename (default: auto-generated)"
    echo "  -c, --constraints <c>   Constraints (comma-separated)"
    echo "  -h, --help              Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 -t new 'List files and create hello.txt'"
    echo "  $0 -t continue -s abc123 'Add more features'"
    echo "  $0 -t end -s abc123 'Task completed'"
    exit 1
}

# Parse arguments
COMMAND_TYPE="new"
SESSION_ID="auto"
OUTPUT_FILE=""
CONSTRAINTS=""
TASK_DESCRIPTION=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--type)
            COMMAND_TYPE="$2"
            shift 2
            ;;
        -s|--session)
            SESSION_ID="$2"
            shift 2
            ;;
        -f|--file)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -c|--constraints)
            CONSTRAINTS="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            TASK_DESCRIPTION="$1"
            shift
            ;;
    esac
done

if [ -z "$TASK_DESCRIPTION" ] && [ "$COMMAND_TYPE" != "end" ]; then
    echo "Error: Task description is required"
    usage
fi

# Generate IDs
COMMAND_ID=$(generate_uuid)
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

if [ -z "$OUTPUT_FILE" ]; then
    OUTPUT_FILE="cmd-${COMMAND_ID:0:8}.md"
fi

# Create command file
OUTPUT_PATH="$COMMANDS_DIR/$OUTPUT_FILE"

# Build constraints section
CONSTRAINTS_SECTION=""
if [ -n "$CONSTRAINTS" ]; then
    CONSTRAINTS_SECTION=$'\n## 约束条件\n'
    IFS=',' read -ra CONS <<< "$CONSTRAINTS"
    for con in "${CONS[@]}"; do
        CONSTRAINTS_SECTION+="- ${con}\n"
    done
fi

# Write file
cat > "$OUTPUT_PATH" << EOF
---
id: $COMMAND_ID
created_at: $TIMESTAMP
session_id: $SESSION_ID
command_type: $COMMAND_TYPE
---

# 任务指令

## 任务描述
$TASK_DESCRIPTION
${CONSTRAINTS_SECTION}
## 预期输出
- 完成任务描述中的要求
EOF

echo "Command created: $OUTPUT_PATH"
echo "  ID: $COMMAND_ID"
echo "  Type: $COMMAND_TYPE"
echo "  Session: $SESSION_ID"
