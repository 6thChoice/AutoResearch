# 快速使用指南

## 方式一：使用快捷脚本（推荐）

```bash
# 1. 创建任务
./quick-task.sh "创建一个计算斐波那契数列的 Python 脚本"

# 2. 实时监控
./watch.sh
```

## 方式二：直接放 MD 文件

```bash
# 直接将任务文件放到 pending 目录
cat > volumes/commands/pending/my-task.md << 'EOF'
---
id: my-task-001
created_at: 2026-02-22T00:00:00Z
session_id: auto
command_type: new
---

# 任务描述
创建一个 hello.py 文件，打印 Hello World
EOF

# 查看进度
docker logs -f claude-code-agent
```

## 方式三：一行命令

```bash
# 创建任务并立即监控
./quick-task.sh "你的任务" && ./watch.sh
```

## 实时了解进展

| 方法 | 命令 | 说明 |
|------|------|------|
| 监控脚本 | `./watch.sh` | 高亮显示关键信息 |
| Docker 日志 | `docker logs -f claude-code-agent` | 原始日志 |
| 查看报告 | `cat volumes/reports/pending/report-*.md` | 查看最新报告 |
| 查看工作区 | `ls volumes/workspace/` | 查看生成的文件 |

## 多轮对话

```bash
# 第一次任务（新会话）
./quick-task.sh "创建一个项目结构"

# 查看返回的 session_id，例如: abc123

# 继续对话
./quick-task.sh "添加单元测试" abc123
```

## 常用命令

```bash
# 启动容器
cd docker && docker compose up -d

# 停止容器
docker compose down

# 重建容器
docker compose build --no-cache && docker compose up -d

# 清理工作区
rm -rf volumes/workspace/*

# 查看所有会话
ls volumes/sessions/
```
