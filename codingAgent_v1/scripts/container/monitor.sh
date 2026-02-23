#!/bin/bash
# Monitor Script - Runs inside the container
# Watches for new command files and processes them with Claude Code

set -e

# Configuration
CONFIG_FILE="${CONFIG_FILE:-/app/config/settings.json}"
COMMANDS_DIR="${COMMANDS_DIR:-/app/volumes/commands/pending}"
PROCESSED_DIR="${PROCESSED_DIR:-/app/volumes/commands/processed}"
REPORTS_DIR="${REPORTS_DIR:-/app/volumes/reports/pending}"
WORKSPACE_DIR="${WORKSPACE_DIR:-/app/volumes/workspace}"
SESSIONS_DIR="${SESSIONS_DIR:-/app/volumes/sessions}"
LOG_FILE="${LOG_FILE:-/app/logs/monitor.log}"
CLAUDE_RUNTIME_LOG="${CLAUDE_RUNTIME_LOG:-/app/volumes/logs/claude_runtime.log}"
CLAUDE_DEBUG_LOG="${CLAUDE_DEBUG_LOG:-/app/volumes/logs/claude_debug.log}"
CLAUDE_HOME="${CLAUDE_HOME:-/home/node/.claude}"
TMUX_SESSION="${TMUX_SESSION:-claude_session}"
POLL_INTERVAL="${POLL_INTERVAL:-1000}"

# Logging function - logs to stdout only (docker logs will capture)
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "[$timestamp] [$level] $message"
}

# Parse frontmatter from MD file
parse_frontmatter() {
    local file="$1"
    local field="$2"

    # Extract value between --- markers
    awk -v field="$field" '
        /^---$/ { in_fm++; next }
        in_fm == 1 && /^'"$field"':/ {
            # Remove the field name and colon, get the value
            sub(/^'"$field"':[[:space:]]*/, "")
            print
            exit
        }
    ' "$file"
}

# Parse task description from MD file
parse_task_description() {
    local file="$1"
    awk '
        /^## 任务描述/ { in_task=1; next }
        in_task && /^## / { exit }
        in_task && NF { print }
    ' "$file"
}

# Generate UUID
generate_uuid() {
    if command -v uuidgen &> /dev/null; then
        uuidgen | tr '[:upper:]' '[:lower:]'
    else
        cat /proc/sys/kernel/random/uuid
    fi
}

# Generate report MD file
generate_report() {
    local command_id="$1"
    local session_id="$2"
    local status="$3"
    local summary="$4"
    local details="$5"
    local turn_count="$6"
    local waiting="$7"
    local next_steps="$8"
    local logs="$9"
    local file_changes="${10}"
    local thinking="${11:-无}"
    local tool_uses="${12:-无}"
    local session_stats="${13:-无}"

    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local report_file="$REPORTS_DIR/report-${command_id}.md"
    local detailed_report="$REPORTS_DIR/detailed-report-${command_id}.md"

    # 检查是否存在详细报告
    local has_detailed_report="false"
    if [ -f "$detailed_report" ] && [ -s "$detailed_report" ]; then
        has_detailed_report="true"
    fi

    # 如果有详细报告，优先使用详细报告作为主报告
    if [ "$has_detailed_report" = "true" ]; then
        log "INFO" "使用详细报告作为主报告"
        # 将详细报告复制为主报告
        cp "$detailed_report" "$report_file"

        # 在详细报告后附加原始数据
        cat >> "$report_file" << EOF

---

## 原始执行数据

### 会话状态
- 当前轮次: $turn_count
- 等待继续: $waiting

### AI 思考过程
\`\`\`
$thinking
\`\`\`

### 工具调用记录
\`\`\`json
$tool_uses
\`\`\`

### 会话统计
$session_stats

### 运行日志摘要
\`\`\`
$logs
\`\`\`

### 文件变更
$file_changes
EOF
    else
        # 生成基础报告
        cat > "$report_file" << EOF
---
command_id: $command_id
session_id: $session_id
created_at: $timestamp
status: $status
---

# 执行报告

## 执行摘要
$summary

## 执行详情
$details

## 会话状态
- 当前轮次: $turn_count
- 等待继续: $waiting
- 下一步建议: $next_steps

## AI 思考过程
\`\`\`
$thinking
\`\`\`

## 工具调用记录
\`\`\`json
$tool_uses
\`\`\`

## 会话统计
$session_stats

## 运行日志
\`\`\`
$logs
\`\`\`

## 文件变更
$file_changes
EOF
    fi

    log "INFO" "Report generated: $report_file"
}

# Process a command file
process_command() {
    local command_file="$1"
    local filename=$(basename "$command_file")

    log "INFO" "Processing command file: $filename"

    # Parse frontmatter
    local command_id=$(parse_frontmatter "$command_file" "id")
    local session_id=$(parse_frontmatter "$command_file" "session_id")
    local command_type=$(parse_frontmatter "$command_file" "command_type")
    local created_at=$(parse_frontmatter "$command_file" "created_at")

    log "INFO" "Command ID: $command_id, Type: $command_type, Session: $session_id"

    # Handle session management
    source /app/scripts/session.sh

    case "$command_type" in
        "new")
            if [ "$session_id" = "auto" ] || [ -z "$session_id" ]; then
                session_id=$(generate_uuid)
            fi
            session_new "$session_id" "$WORKSPACE_DIR"
            ;;
        "continue")
            if [ -z "$session_id" ] || [ "$session_id" = "auto" ]; then
                log "ERROR" "continue command requires a valid session_id"
                generate_report "$command_id" "unknown" "failed" \
                    "Invalid session_id for continue command" \
                    "The session_id must be provided for continue commands" \
                    "0" "否" "Provide a valid session_id" "" "无"
                mv "$command_file" "$PROCESSED_DIR/"
                return 1
            fi
            session_continue "$session_id"
            ;;
        "end")
            session_end "$session_id"
            generate_report "$command_id" "$session_id" "success" \
                "会话已结束" \
                "会话 $session_id 已被标记为结束" \
                "$(session_get_turns "$session_id")" "否" "无" "" "无"
            mv "$command_file" "$PROCESSED_DIR/"
            return 0
            ;;
        *)
            log "ERROR" "Unknown command type: $command_type"
            generate_report "$command_id" "$session_id" "failed" \
                "未知指令类型" \
                "不支持的 command_type: $command_type" \
                "0" "否" "使用 new, continue 或 end" "" "无"
            mv "$command_file" "$PROCESSED_DIR/"
            return 1
            ;;
    esac

    # Extract task description
    local task_description=$(parse_task_description "$command_file")

    if [ -z "$task_description" ]; then
        # Fallback: get all content after frontmatter
        task_description=$(awk 'BEGIN{fm=0} /^---$/{fm++; next} fm>=2{print}' "$command_file")
    fi

    log "INFO" "Task description: ${task_description:0:100}..."

    # Execute Claude Code
    local claude_output=""
    local claude_exit_code=0
    local execution_log=""

    cd "$WORKSPACE_DIR"

    log "INFO" "Starting Claude Code execution..."

    # Create a temp file for the prompt
    local prompt_file=$(mktemp)
    echo "$task_description" > "$prompt_file"

    # Run Claude Code with the task
    # Note: Claude Code CLI manages its own context for sessions
    # We use --resume flag for continuing sessions if supported
    local claude_args=""

    if [ "$command_type" = "continue" ]; then
        # For continue, we might need to check if Claude Code supports session resume
        # For now, we pass the task and rely on workspace state
        claude_args=""
    fi

    # Execute Claude Code using Tmux + Script
    # Tmux: 后台稳定运行，支持随时介入
    # Script: 记录完整终端输出到日志文件
    # --debug-file: 输出详细调试日志
    # --session-id: 指定会话ID以便追踪
    set +e

    # 确保日志目录存在
    mkdir -p /app/volumes/logs
    mkdir -p "$CLAUDE_HOME/projects"
    mkdir -p "$CLAUDE_HOME/debug"

    # 创建本次任务的调试日志文件
    local task_debug_log="/app/volumes/logs/debug-${command_id}.log"

    # ========================================
    # 上下文组合 (Context Combination)
    # ========================================
    # 组合层级化上下文并注入到任务描述前
    local combined_context=""
    local context_file="/tmp/context_${command_id}.md"

    if [ -f "/app/templates/context/combine_context.py" ]; then
        log "INFO" "组合层级化上下文..."

        # 运行上下文组合器（--runtime-dir 指向 planAgent 写入的运行时上下文）
        python3 /app/templates/context/combine_context.py \
            --task-id "$command_id" \
            --runtime-dir "/app/volumes/context" \
            --output "$context_file" 2>/dev/null

        if [ -f "$context_file" ] && [ -s "$context_file" ]; then
            # 检查是否有实际内容（不只是空模板）
            local context_lines=$(grep -v "^>" "$context_file" | grep -v "^$" | grep -v "^---" | grep -v "^#" | wc -l)
            if [ "$context_lines" -gt 5 ]; then
                log "INFO" "上下文组合完成，已注入到任务描述"
            else
                log "INFO" "上下文模板为空，跳过注入"
                rm -f "$context_file"
            fi
        fi
    fi

    # 写入任务头信息到日志
    {
        echo ""
        echo "========================================"
        echo "任务开始: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "任务ID: $command_id"
        echo "会话ID: $session_id"
        echo "========================================"
    } >> "$CLAUDE_RUNTIME_LOG"

    log "INFO" "执行中..."
    log "INFO" "  实时监控: docker exec -it claude-code-agent tmux attach -t $TMUX_SESSION"
    log "INFO" "  日志查看: tail -f volumes/logs/claude_runtime.log"
    log "INFO" "  调试日志: tail -f volumes/logs/debug-${command_id}.log"

    # 将任务写入临时文件（处理复杂命令）
    local task_file=$(mktemp)

    # 如果有组合上下文，注入到任务描述前
    if [ -f "$context_file" ] && [ -s "$context_file" ]; then
        {
            cat "$context_file"
            echo ""
            echo "---"
            echo ""
            echo "**以下是您的具体任务：**"
            echo ""
            echo "$task_description"
        } > "$task_file"
    else
        echo "$task_description" > "$task_file"
    fi

    # 杀掉可能存在的旧 tmux 会话
    tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true

    # 在 tmux 中运行 claude，添加调试参数
    # --debug-file: 输出详细调试信息到文件
    # --session-id: 使用我们管理的 session_id
    # --verbose: 启用详细输出
    tmux new-session -d -s "$TMUX_SESSION" -x 200 -y 50 \
        "script -f -q -a '$CLAUDE_RUNTIME_LOG' -c 'claude --print --permission-mode bypassPermissions --debug-file $task_debug_log --session-id $session_id --verbose \"\$(cat $task_file)\"'; echo \"EXIT_CODE:\$?\" > /tmp/claude_exit_${command_id}"

    # 等待任务完成
    local max_wait=600  # 最大等待10分钟
    local waited=0
    local exit_code_file="/tmp/claude_exit_${command_id}"

    while [ $waited -lt $max_wait ]; do
        # 检查 tmux 会话是否还存在
        if ! tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
            # 会话已结束，读取退出码
            sleep 1
            break
        fi
        sleep 1
        waited=$((waited + 1))

        # 每30秒输出一次进度
        if [ $((waited % 30)) -eq 0 ]; then
            log "INFO" "执行中... (${waited}秒)"
        fi
    done

    # 如果超时，强制结束
    if [ $waited -ge $max_wait ]; then
        log "WARN" "任务超时，强制结束"
        tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true
        claude_exit_code=124  # timeout exit code
    else
        # 读取退出码
        if [ -f "$exit_code_file" ]; then
            claude_exit_code=$(cat "$exit_code_file" | grep -oP 'EXIT_CODE:\K\d+' || echo "1")
            rm -f "$exit_code_file"
        else
            claude_exit_code=1
        fi
    fi

    rm -f "$task_file"
    set -e

    # 写入结束标记
    {
        echo "----------------------------------------"
        echo "任务结束: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "退出码: $claude_exit_code"
        echo "========================================"
        echo ""
    } >> "$CLAUDE_RUNTIME_LOG"

    # 从日志文件提取最近输出
    claude_output=$(tail -100 "$CLAUDE_RUNTIME_LOG" | grep -v "^===" | grep -v "^---" | head -50)
    execution_log=$(echo "$claude_output" | head -50)

    log "INFO" "Claude Code exit code: $claude_exit_code"

    # 等待一下让文件系统同步
    sleep 2

    # 从会话 jsonl 文件提取详细信息
    local thinking=""
    local tool_uses=""
    local session_stats=""

    # 尝试从 jsonl 文件提取信息
    thinking=$(extract_thinking "$session_id" 2>/dev/null | head -20)
    tool_uses=$(extract_tool_uses "$session_id" 2>/dev/null | head -10)
    session_stats=$(get_session_stats "$session_id" 2>/dev/null)

    # 如果 jsonl 提取失败，尝试从调试日志提取
    if [ -z "$thinking" ] && [ -f "$task_debug_log" ]; then
        thinking=$(grep -i "thinking" "$task_debug_log" | head -10)
    fi

    # 确保变量不为空
    thinking=${thinking:-"无法提取思考过程"}
    tool_uses=${tool_uses:-"[]"}
    session_stats=${session_stats:-"{}"}

    # ========================================
    # 强制总结阶段 (Agent Memory Management)
    # ========================================
    # 任务完成后，强制执行总结任务，更新 AGENT_MISSION.md 并生成详细报告

    local task_start_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local task_end_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # 确保 AGENT_MISSION.md 存在
    local mission_file="$WORKSPACE_DIR/AGENT_MISSION.md"
    if [ ! -f "$mission_file" ]; then
        log "INFO" "初始化 AGENT_MISSION.md..."
        cp /app/templates/AGENT_MISSION.md "$mission_file"
        sed -i "s/{{DATE}}/$(date -u +"%Y-%m-%d")/g" "$mission_file"
    fi

    # 确保 docs/decisions 目录存在
    mkdir -p "$WORKSPACE_DIR/docs/decisions"

    # 确定执行状态
    local exec_status="SUCCESS"
    [ $claude_exit_code -ne 0 ] && exec_status="FAILED"

    # 获取当前 Mission 阶段
    local current_phase=$(grep -E "^\- \[\/\]" "$mission_file" 2>/dev/null | head -1 || echo "未设置")

    # 获取 Git 信息
    local git_info="非 Git 项目"
    if [ -d "$WORKSPACE_DIR/.git" ]; then
        git_info=$(cd "$WORKSPACE_DIR" && git rev-parse --short HEAD 2>/dev/null || echo "无")
    fi

    # 创建详细报告生成任务
    local summary_task_file=$(mktemp)
    cat > "$summary_task_file" << SUMMARY_PROMPT
请完成以下总结任务，按照指定格式输出：

## 任务信息
- 任务ID: $command_id
- 会话ID: $session_id
- 执行状态: $exec_status
- 原始指令: $task_description

---

请完成以下两件事：

### 第一件事：更新 AGENT_MISSION.md

1. 更新『实施进度追踪』中的进度
2. 如果遇到任何问题或坑，详细记录在『避坑指南』（包括问题描述、失败尝试、最终方案）
3. 更新『下一步指令』，为下一个智能体预留具体任务

### 第二件事：按照以下模板格式，生成详细执行报告

请在 $REPORTS_DIR 目录下创建 detailed-report-${command_id}.md 文件，内容格式如下：

---
session_id: "$session_id"
report_date: "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
status: "$exec_status"
tags: [根据任务内容添加标签]
---

# 执行任务总结报告

## 1. 任务概览 (Task Overview)
- **原始指令**: [引用原始任务描述]
- **关联 Mission 阶段**: $current_phase
- **执行状态**: $exec_status

## 2. 核心成果 (Key Deliverables)
> 详细说明修改了哪些文件，实现了哪些功能
- **文件变更**: [列出具体文件和变更内容]
- **功能实现**: [描述实现的功能]
- **验证结果**: [测试结果、运行结果等]

## 3. ADR & 决策同步 (Architectural Decisions)
> 如果有架构决策或重要技术选择，记录在这里
- **决策内容**: [描述决策]
- **理由**: [为什么做这个决策]

## 4. 填坑记录与风险预警 (Pitfalls & Lessons)
> **最重要**：记录遇到的问题和解决方案
- **遇到的问题**: [描述问题]
- **失败尝试**: [尝试过但失败的方法]
- **最终方案**: [成功的解决方案]
- **残留风险**: [还有什么需要注意的]

## 5. Mission 手册更新说明 (Mission Sync)
- **进度更新**: [更新了哪些进度]
- **下一手建议**: [为下一个智能体建议的具体任务]

## 6. 原始执行指纹 (Artifacts)
- **Git Commit**: $git_info
- **相关日志**: /app/volumes/logs/debug-${command_id}.log

---

请确保报告内容详实、结构清晰，为后续接手的智能体提供完整上下文。
SUMMARY_PROMPT

    # 执行总结任务
    local summary_timeout=180  # 3分钟
    log "INFO" "执行详细报告生成..."

    tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true
    tmux new-session -d -s "$TMUX_SESSION" -x 200 -y 50 \
        "script -f -q -a '$CLAUDE_RUNTIME_LOG' -c 'claude --print --permission-mode bypassPermissions \"\$(cat $summary_task_file)\"'; echo \"SUMMARY_EXIT:\$?\" > /tmp/claude_summary_${command_id}"

    local summary_waited=0
    while [ $summary_waited -lt $summary_timeout ]; do
        if ! tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
            sleep 1
            break
        fi
        sleep 1
        summary_waited=$((summary_waited + 1))
    done

    if [ $summary_waited -ge $summary_timeout ]; then
        log "WARN" "报告生成超时"
        tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true
    fi

    rm -f "$summary_task_file"

    # 运行交接验证
    if [ -f /app/scripts/validate_handover.py ]; then
        log "INFO" "运行交接验证..."
        cd "$WORKSPACE_DIR"
        python3 /app/scripts/validate_handover.py 2>&1 | head -20 >> "$CLAUDE_RUNTIME_LOG" || true
    fi

    log "INFO" "总结阶段完成"

    # Determine status
    local status=""
    local summary=""
    local waiting="否"
    local next_steps="可以继续发送 continue 指令"

    if [ $claude_exit_code -eq 0 ]; then
        status="success"
        summary="任务执行成功"
    else
        status="failed"
        summary="任务执行失败 (exit code: $claude_exit_code)"
        next_steps="检查错误日志，修正问题后重试"
    fi

    # Get file changes
    local file_changes="无"
    if [ -d "$WORKSPACE_DIR/.git" ]; then
        file_changes=$(cd "$WORKSPACE_DIR" && git status --short 2>/dev/null || echo "无法获取")
    else
        # List recently modified files
        file_changes=$(find "$WORKSPACE_DIR" -type f -mmin -5 -not -path "*/\.*" 2>/dev/null | head -20 || echo "无")
    fi

    # Update session turn count
    session_increment_turn "$session_id"
    local turn_count=$(session_get_turns "$session_id")

    # Generate report with enhanced information
    generate_report "$command_id" "$session_id" "$status" \
        "$summary" \
        "$claude_output" \
        "$turn_count" \
        "$waiting" \
        "$next_steps" \
        "$execution_log" \
        "$file_changes" \
        "$thinking" \
        "$tool_uses" \
        "$session_stats"

    # Move processed command
    mv "$command_file" "$PROCESSED_DIR/"
    log "INFO" "Command processed and moved to processed directory"
}

# Main monitoring loop
main() {
    log "INFO" "=== Claude Code Monitor Starting ==="
    log "INFO" "Commands directory: $COMMANDS_DIR"
    log "INFO" "Reports directory: $REPORTS_DIR"
    log "INFO" "Workspace: $WORKSPACE_DIR"
    log "INFO" "Claude home: $CLAUDE_HOME"

    # Ensure directories exist
    mkdir -p "$COMMANDS_DIR" "$PROCESSED_DIR" "$REPORTS_DIR"
    mkdir -p "$WORKSPACE_DIR" "$SESSIONS_DIR"
    mkdir -p /app/volumes/logs
    mkdir -p "$CLAUDE_HOME/projects" "$CLAUDE_HOME/debug"

    # Check Claude Code installation
    if ! command -v claude &> /dev/null; then
        log "ERROR" "Claude Code not found! Please ensure @anthropic-ai/claude-code is installed."
        exit 1
    fi

    log "INFO" "Claude Code version: $(claude --version 2>&1 || echo 'unknown')"

    # Check for ANTHROPIC_AUTH_TOKEN
    if [ -z "$ANTHROPIC_AUTH_TOKEN" ]; then
        log "WARN" "ANTHROPIC_AUTH_TOKEN not set. Claude Code may not work properly."
    fi

    # Process any existing pending commands
    for cmd_file in "$COMMANDS_DIR"/*.md; do
        if [ -f "$cmd_file" ]; then
            log "INFO" "Found existing pending command: $cmd_file"
            process_command "$cmd_file"
        fi
    done

    # Check if inotify is available
    if command -v inotifywait &> /dev/null; then
        log "INFO" "Using inotify for file watching"
        watch_with_inotify
    else
        log "INFO" "Using polling for file watching"
        watch_with_polling
    fi
}

# Watch using inotify
watch_with_inotify() {
    inotifywait -m -e create -e moved_to "$COMMANDS_DIR" --format '%f' 2>/dev/null | while read filename; do
        if [[ "$filename" == *.md ]]; then
            sleep 1  # Wait for file to be fully written
            process_command "$COMMANDS_DIR/$filename"
        fi
    done
}

# Watch using polling (fallback)
watch_with_polling() {
    while true; do
        for cmd_file in "$COMMANDS_DIR"/*.md; do
            if [ -f "$cmd_file" ]; then
                process_command "$cmd_file"
            fi
        done
        sleep $(echo "scale=2; $POLL_INTERVAL/1000" | bc)
    done
}

# Run main
main "$@"
