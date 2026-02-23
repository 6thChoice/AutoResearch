#!/bin/bash
# Session Management Script
# Handles session state for multi-turn conversations

SESSIONS_DIR="${SESSIONS_DIR:-/app/volumes/sessions}"
CLAUDE_HOME="${CLAUDE_HOME:-/home/node/.claude}"
WORKSPACE_DIR="${WORKSPACE_DIR:-/app/volumes/workspace}"

# Create a new session
session_new() {
    local session_id="$1"
    local workspace="$2"
    local session_file="$SESSIONS_DIR/${session_id}.json"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    cat > "$session_file" << EOF
{
  "session_id": "$session_id",
  "created_at": "$timestamp",
  "last_activity": "$timestamp",
  "turn_count": 0,
  "status": "active",
  "workspace": "$workspace"
}
EOF

    echo "Session created: $session_id"
}

# Continue an existing session
session_continue() {
    local session_id="$1"
    local session_file="$SESSIONS_DIR/${session_id}.json"

    if [ ! -f "$session_file" ]; then
        echo "Warning: Session file not found, creating new session"
        session_new "$session_id" "/app/volumes/workspace"
        return
    fi

    # Update last activity
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local temp_file=$(mktemp)

    jq --arg ts "$timestamp" '.last_activity = $ts' "$session_file" > "$temp_file"
    mv "$temp_file" "$session_file"

    echo "Session continued: $session_id"
}

# End a session
session_end() {
    local session_id="$1"
    local session_file="$SESSIONS_DIR/${session_id}.json"

    if [ ! -f "$session_file" ]; then
        echo "Warning: Session file not found"
        return 1
    fi

    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local temp_file=$(mktemp)

    jq --arg ts "$timestamp" '.last_activity = $ts | .status = "ended"' "$session_file" > "$temp_file"
    mv "$temp_file" "$session_file"

    echo "Session ended: $session_id"
}

# Get session turn count
session_get_turns() {
    local session_id="$1"
    local session_file="$SESSIONS_DIR/${session_id}.json"

    if [ -f "$session_file" ]; then
        jq -r '.turn_count' "$session_file"
    else
        echo "0"
    fi
}

# Increment session turn count
session_increment_turn() {
    local session_id="$1"
    local session_file="$SESSIONS_DIR/${session_id}.json"

    if [ ! -f "$session_file" ]; then
        echo "Warning: Session file not found"
        return 1
    fi

    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local temp_file=$(mktemp)

    jq --arg ts "$timestamp" '.turn_count += 1 | .last_activity = $ts' "$session_file" > "$temp_file"
    mv "$temp_file" "$session_file"
}

# Get session status
session_get_status() {
    local session_id="$1"
    local session_file="$SESSIONS_DIR/${session_id}.json"

    if [ -f "$session_file" ]; then
        jq -r '.status' "$session_file"
    else
        echo "not_found"
    fi
}

# List all active sessions
session_list_active() {
    for session_file in "$SESSIONS_DIR"/*.json; do
        if [ -f "$session_file" ]; then
            local status=$(jq -r '.status' "$session_file")
            if [ "$status" = "active" ]; then
                jq -c '{session_id, created_at, turn_count}' "$session_file"
            fi
        fi
    done
}

# ============================================
# Claude Code Session Log Parsing Functions
# ============================================

# Get the jsonl file path for a session
get_session_jsonl_path() {
    local session_id="$1"
    # Construct project path from workspace
    local project_path=$(echo "$WORKSPACE_DIR" | sed 's/\//-/g' | sed 's/^-//')
    local jsonl_file="$CLAUDE_HOME/projects/-$project_path/${session_id}.jsonl"

    if [ -f "$jsonl_file" ]; then
        echo "$jsonl_file"
        return 0
    fi
    return 1
}

# Extract thinking blocks from session jsonl
extract_thinking() {
    local session_id="$1"
    local jsonl_file=$(get_session_jsonl_path "$session_id")

    if [ -z "$jsonl_file" ] || [ ! -f "$jsonl_file" ]; then
        echo ""
        return 1
    fi

    # Extract thinking content from assistant messages
    jq -r 'select(.type == "assistant") | .message.content[]? | select(.type == "thinking") | .thinking' "$jsonl_file" 2>/dev/null | head -50
}

# Extract tool use records from session jsonl
extract_tool_uses() {
    local session_id="$1"
    local jsonl_file=$(get_session_jsonl_path "$session_id")

    if [ -z "$jsonl_file" ] || [ ! -f "$jsonl_file" ]; then
        echo "[]"
        return 1
    fi

    # Extract tool_use content from assistant messages
    jq -c 'select(.type == "assistant") | .message.content[]? | select(.type == "tool_use") | {name: .name, id: .id, input: .input}' "$jsonl_file" 2>/dev/null
}

# Extract user messages from session jsonl
extract_user_messages() {
    local session_id="$1"
    local jsonl_file=$(get_session_jsonl_path "$session_id")

    if [ -z "$jsonl_file" ] || [ ! -f "$jsonl_file" ]; then
        echo ""
        return 1
    fi

    jq -r 'select(.type == "user") | .message.content' "$jsonl_file" 2>/dev/null
}

# Extract text responses from assistant messages
extract_assistant_text() {
    local session_id="$1"
    local jsonl_file=$(get_session_jsonl_path "$session_id")

    if [ -z "$jsonl_file" ] || [ ! -f "$jsonl_file" ]; then
        echo ""
        return 1
    fi

    # Extract text content from assistant messages
    jq -r 'select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text' "$jsonl_file" 2>/dev/null
}

# Get session statistics
get_session_stats() {
    local session_id="$1"
    local jsonl_file=$(get_session_jsonl_path "$session_id")

    if [ -z "$jsonl_file" ] || [ ! -f "$jsonl_file" ]; then
        echo '{"error": "session file not found"}'
        return 1
    fi

    local total_messages=$(wc -l < "$jsonl_file")
    local user_count=$(jq -c 'select(.type == "user")' "$jsonl_file" 2>/dev/null | wc -l)
    local assistant_count=$(jq -c 'select(.type == "assistant")' "$jsonl_file" 2>/dev/null | wc -l)
    local tool_use_count=$(jq -c 'select(.type == "assistant") | .message.content[]? | select(.type == "tool_use")' "$jsonl_file" 2>/dev/null | wc -l)
    local thinking_count=$(jq -c 'select(.type == "assistant") | .message.content[]? | select(.type == "thinking")' "$jsonl_file" 2>/dev/null | wc -l)

    echo "{\"total_messages\": $total_messages, \"user_count\": $user_count, \"assistant_count\": $assistant_count, \"tool_use_count\": $tool_use_count, \"thinking_count\": $thinking_count}"
}

# Generate comprehensive session summary
generate_session_summary() {
    local session_id="$1"
    local jsonl_file=$(get_session_jsonl_path "$session_id")

    if [ -z "$jsonl_file" ] || [ ! -f "$jsonl_file" ]; then
        echo "无法找到会话日志文件"
        return 1
    fi

    local stats=$(get_session_stats "$session_id")
    local thinking=$(extract_thinking "$session_id" | head -5)
    local tools=$(extract_tool_uses "$session_id" | head -10)

    echo "## 会话统计"
    echo "$stats" | jq '.'
    echo ""
    echo "## 思考过程摘要"
    echo "$thinking" | head -500
    echo ""
    echo "## 工具调用"
    echo "$tools" | jq -c '.' 2>/dev/null | head -10
}
