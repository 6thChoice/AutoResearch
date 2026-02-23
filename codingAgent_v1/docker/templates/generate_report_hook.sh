#!/bin/bash
# 报告生成 Hook 脚本
# 在 Claude Code 完成任务后，强制执行结构化报告编写

set -e

# 配置
WORKSPACE_DIR="${WORKSPACE_DIR:-/app/volumes/workspace}"
REPORTS_DIR="${REPORTS_DIR:-/app/volumes/reports/pending}"
TEMPLATE_FILE="${TEMPLATE_FILE:-/app/templates/report.md}"
SESSION_ID="$1"
COMMAND_ID="$2"
TASK_DESCRIPTION="$3"
START_TIME="$4"
END_TIME="$5"
EXIT_CODE="$6"

# 计算执行时长
calculate_duration() {
    local start="$1"
    local end="$2"
    if [ -n "$start" ] && [ -n "$end" ]; then
        local start_sec=$(date -d "$start" +%s 2>/dev/null || echo "0")
        local end_sec=$(date -d "$end" +%s 2>/dev/null || echo "0")
        local diff=$((end_sec - start_sec))
        local minutes=$((diff / 60))
        local seconds=$((diff % 60))
        echo "${minutes}m ${seconds}s"
    else
        echo "未知"
    fi
}

# 获取 Git 信息
get_git_info() {
    cd "$WORKSPACE_DIR" 2>/dev/null || return
    if [ -d ".git" ]; then
        local commit_hash=$(git rev-parse --short HEAD 2>/dev/null || echo "无")
        local branch=$(git branch --show-current 2>/dev/null || echo "HEAD")
        echo "Commit: $commit_hash | Branch: $branch"
    else
        echo "非 Git 项目"
    fi
}

# 获取文件变更
get_file_changes() {
    cd "$WORKSPACE_DIR" 2>/dev/null || return
    if [ -d ".git" ]; then
        git status --short 2>/dev/null | head -20 || echo "无变更"
    else
        find . -type f -mmin -30 -not -path "./.git/*" -not -path "./__pycache__/*" 2>/dev/null | head -20 || echo "无变更"
    fi
}

# 获取 AGENT_MISSION.md 中的当前阶段
get_current_phase() {
    local mission_file="$WORKSPACE_DIR/AGENT_MISSION.md"
    if [ -f "$mission_file" ]; then
        grep -E "^\- \[\/\]" "$mission_file" 2>/dev/null | head -1 || echo "未设置"
    else
        echo "AGENT_MISSION.md 不存在"
    fi
}

# 生成报告提示词
generate_report_prompt() {
    local duration=$(calculate_duration "$START_TIME" "$END_TIME")
    local git_info=$(get_git_info)
    local file_changes=$(get_file_changes)
    local current_phase=$(get_current_phase)
    local status="SUCCESS"
    [ "$EXIT_CODE" != "0" ] && status="FAILED"

    cat << PROMPT_EOF
请根据以下信息，按照指定模板编写一份详细的执行报告。

## 任务信息
- **任务ID**: $COMMAND_ID
- **会话ID**: $SESSION_ID
- **执行状态**: $status
- **执行时长**: $duration
- **Git 信息**: $git_info
- **原始指令**: $TASK_DESCRIPTION

## 文件变更
$file_changes

## 当前 Mission 阶段
$current_phase

---

请生成一份 Markdown 格式的报告，包含以下章节：

### 1. 任务概览 (Task Overview)
- 原始指令
- 关联的 Mission 阶段
- 执行时长

### 2. 核心成果 (Key Deliverables)
- 详细说明修改了哪些文件
- 实现了哪些功能
- 验证结果（测试、运行等）

### 3. ADR & 决策同步 (Architectural Decisions)
- 如果有架构决策，记录下来
- 决策理由

### 4. 填坑记录与风险预警 (Pitfalls & Lessons)
- 遇到的问题和解决方案
- 残留风险或后续注意事项

### 5. Mission 手册更新说明 (Mission Sync)
- 进度更新
- 下一步建议

### 6. 原始执行指纹 (Artifacts)
- Git 信息
- 相关日志路径

请确保报告内容详实、结构清晰，为后续接手的智能体提供完整上下文。

将报告内容输出到: $REPORTS_DIR/detailed-report-$COMMAND_ID.md
PROMPT_EOF
}

# 主函数
main() {
    echo "=========================================="
    echo "📋 开始生成详细执行报告..."
    echo "=========================================="

    # 生成提示词
    local prompt=$(generate_report_prompt)

    # 创建临时文件存储提示词
    local prompt_file=$(mktemp)
    echo "$prompt" > "$prompt_file"

    # 执行报告生成
    echo "正在生成报告..."

    # 使用 Claude Code 生成报告（较短超时）
    local report_timeout=120
    local exit_code=0

    # 在 Tmux 中执行
    tmux kill-session -t report_gen 2>/dev/null || true
    tmux new-session -d -s report_gen -x 200 -y 50 \
        "claude --print --permission-mode bypassPermissions \"\$(cat $prompt_file)\"; echo \"REPORT_EXIT:\$?\" > /tmp/report_exit"

    local waited=0
    while [ $waited -lt $report_timeout ]; do
        if ! tmux has-session -t report_gen 2>/dev/null; then
            sleep 1
            break
        fi
        sleep 1
        waited=$((waited + 1))
    done

    if [ $waited -ge $report_timeout ]; then
        echo "⚠️ 报告生成超时"
        tmux kill-session -t report_gen 2>/dev/null || true
    fi

    rm -f "$prompt_file"

    echo "=========================================="
    echo "✅ 报告生成完成"
    echo "=========================================="
}

main "$@"
