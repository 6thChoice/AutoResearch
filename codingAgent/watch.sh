#!/bin/bash
# 实时监控脚本 - 监控容器内 Claude Code 的终端内容
# 用法: ./watch.sh [选项]
#
# 选项:
#   --attach, -a    附加到 tmux 会话 (交互式，可手动介入)
#   --tail, -t      实时查看日志文件 (默认)
#   --status, -s    仅显示状态概览

PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
REPORTS_DIR="$PROJECT_ROOT/volumes/reports/pending"
WORKSPACE_DIR="$PROJECT_ROOT/volumes/workspace"
COMMANDS_DIR="$PROJECT_ROOT/volumes/commands/pending"
LOGS_DIR="$PROJECT_ROOT/volumes/logs"
TMUX_SESSION="claude_session"

# 解析参数
MODE="tail"
case "$1" in
    --attach|-a) MODE="attach" ;;
    --tail|-t) MODE="tail" ;;
    --status|-s) MODE="status" ;;
esac

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

show_status() {
    local pending=$(ls $COMMANDS_DIR/*.md 2>/dev/null | wc -l)
    local reports=$(ls $REPORTS_DIR/*.md 2>/dev/null | wc -l)
    local files=$(ls $WORKSPACE_DIR 2>/dev/null | grep -v .gitkeep | wc -l)
    local log_size=$(du -h $LOGS_DIR/claude_runtime.log 2>/dev/null | cut -f1 || echo "0")

    # 检查 tmux 会话状态
    local tmux_status="未运行"
    if docker exec claude-code-agent tmux has-session -t $TMUX_SESSION 2>/dev/null; then
        tmux_status="${GREEN}运行中${NC}"
    fi

    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║          Claude Code 终端监控系统                            ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}📊 状态概览:${NC}"
    echo -e "   📋 待处理任务: ${YELLOW}${pending}${NC} 个"
    echo -e "   📄 生成报告: ${GREEN}${reports}${NC} 个"
    echo -e "   📁 工作区文件: ${CYAN}${files}${NC} 个"
    echo -e "   📝 日志大小: ${log_size}"
    echo -e "   🖥️  Tmux状态: ${tmux_status}"
    echo ""
    echo -e "${BLUE}📖 使用说明:${NC}"
    echo -e "   ${BOLD}./watch.sh --attach${NC}  附加到终端 (Ctrl+B D 退出)"
    echo -e "   ${BOLD}./watch.sh --tail${NC}    实时查看日志"
    echo -e "   ${BOLD}./watch.sh --status${NC}  仅显示状态"
}

# 模式1: 附加到 tmux 会话 (交互式)
mode_attach() {
    echo -e "${GREEN}🔗 附加到 Claude Code 终端会话...${NC}"
    echo -e "${YELLOW}提示: 按 Ctrl+B 然后按 D 可以退出但不停止任务${NC}"
    echo ""
    docker exec -it claude-code-agent tmux attach-session -t $TMUX_SESSION
}

# 模式2: 实时查看日志文件
mode_tail() {
    echo -e "${GREEN}📜 实时查看 Claude Code 日志...${NC}"
    echo -e "${YELLOW}提示: 按 Ctrl+C 退出${NC}"
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"

    # 确保日志目录存在
    mkdir -p $LOGS_DIR

    # 实时 tail 日志，过滤 ANSI 转义码
    tail -f $LOGS_DIR/claude_runtime.log 2>/dev/null | while IFS= read -r line; do
        # 移除 ANSI 转义码
        clean_line=$(echo "$line" | sed 's/\x1b\[[0-9;]*[mGKH]//g')

        # 高亮关键信息
        if [[ "$clean_line" == *"任务开始"* ]] || [[ "$clean_line" == *"任务ID"* ]]; then
            echo -e "${GREEN}$clean_line${NC}"
        elif [[ "$clean_line" == *"任务结束"* ]] || [[ "$clean_line" == *"退出码"* ]]; then
            echo -e "${YELLOW}$clean_line${NC}"
        elif [[ "$clean_line" == *"======="* ]]; then
            echo -e "${CYAN}$clean_line${NC}"
        elif [[ "$clean_line" == *"错误"* ]] || [[ "$clean_line" == *"Error"* ]] || [[ "$clean_line" == *"error"* ]]; then
            echo -e "${RED}$clean_line${NC}"
        elif [[ "$clean_line" == *"EXIT_CODE"* ]]; then
            echo -e "${BOLD}$clean_line${NC}"
        else
            echo "$clean_line"
        fi
    done
}

# 模式3: 仅显示状态
mode_status() {
    show_status
}

# 主逻辑
case "$MODE" in
    attach)
        mode_attach
        ;;
    tail)
        show_status
        echo ""
        mode_tail
        ;;
    status)
        mode_status
        ;;
esac
