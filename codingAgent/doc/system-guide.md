# codingAgent 系统使用指南

> 轻量级 Docker 沙盒编码智能体。
> 将 Markdown 任务文件放入 `volumes/tasks/`，容器内 Monitor 自动拾取并调用 Claude Code 执行，完成后生成报告。

---

## 目录

- [架构概览](#架构概览)
- [快速开始](#快速开始)
- [任务提交](#任务提交)
- [报告查看](#报告查看)
- [配置文件](#配置文件)
- [容器配置](#容器配置)
- [清空并重建](#清空并重建)
- [调试信息查看](#调试信息查看)
- [目录结构](#目录结构)
- [常见问题](#常见问题)

---

## 架构概览

```
宿主机                                Docker 容器 (coding-agent)
┌─────────────────────┐              ┌────────────────────────────────┐
│                     │ Volume Mount │                                │
│  volumes/tasks/     │◄────────────►│  monitor.py (主循环)            │
│    *.md (新任务)     │              │    ├─ inotifywait 监听新文件    │
│    done/ (已完成)    │              │    ├─ 读取 .md 任务内容         │
│                     │              │    ├─ claude --print 执行       │
│  volumes/reports/   │◄─────────────│    └─ 移动任务到 done/          │
│    report-*.md      │              │                                │
│                     │              │  on_stop_hook.py (Stop Hook)   │
│  volumes/workspace/ │◄────────────►│    ├─ claude 退出时自动触发     │
│    (Claude 工作目录) │              │    ├─ 收集 git status/diff     │
│                     │              │    └─ 生成 report-*.md         │
│  volumes/logs/      │◄─────────────│                                │
│    (Claude 日志)     │              │  工作目录: /app/workspace      │
└─────────────────────┘              └────────────────────────────────┘
```

核心流程：

1. 将 `.md` 任务文件放入 `volumes/tasks/`
2. 容器内 `monitor.py` 通过 `inotifywait` 检测到新文件
3. 读取文件内容作为 prompt，调用 `claude --print` 执行
4. Claude Code 执行完毕后，Stop Hook 自动生成报告到 `volumes/reports/`
5. 任务文件被移动到 `volumes/tasks/done/`

---

## 快速开始

### 1. 环境准备

- Docker + Docker Compose
- NVIDIA Docker Runtime（如需 GPU）
- API Token（Anthropic 或兼容接口）

### 2. 配置

```bash
cd codingAgent
cp .env.example .env
```

编辑 `.env`，填入 API 凭证：

```bash
ANTHROPIC_BASE_URL=https://api.anthropic.com
ANTHROPIC_AUTH_TOKEN=sk-ant-xxx       # 必填
ANTHROPIC_MODEL=claude-sonnet-4-20250514
```

### 3. 构建并启动

```bash
cd docker
docker compose build
docker compose up -d
```

### 4. 提交任务

```bash
cat > volumes/tasks/my-task.md << 'EOF'
用 Python 写一个快速排序算法，保存为 quicksort.py，并包含单元测试。
EOF
```

### 5. 查看结果

```bash
# 查看报告
cat volumes/reports/report-my-task.md

# 查看工作区产出
ls volumes/workspace/

# 查看容器日志
docker logs coding-agent
```

---

## 任务提交

任务文件就是普通的 Markdown 文件，文件内容即为给 Claude 的 prompt。

### 格式

无需 frontmatter，无需特殊格式。文件内容直接作为 Claude 的输入：

```markdown
创建一个 Flask REST API，包含用户的 CRUD 操作。
要求：
- 使用 SQLite 数据库
- 包含输入验证
- 写好 README
```

### 文件命名

- 必须以 `.md` 结尾
- 文件名（不含扩展名）作为 `task_id`，会出现在报告文件名中
- 例：`fix-login-bug.md` → 报告为 `report-fix-login-bug.md`

### 提交方式

直接将文件写入 `volumes/tasks/` 目录即可：

```bash
# 方式一：直接写入
echo "实现一个计算器程序" > volumes/tasks/calculator.md

# 方式二：复制文件
cp my-task.md volumes/tasks/

# 方式三：heredoc（适合多行任务）
cat > volumes/tasks/api-server.md << 'EOF'
用 Node.js 实现一个 HTTP 服务器：
1. 监听 3000 端口
2. GET /health 返回 {"status": "ok"}
3. POST /echo 返回请求体
EOF
```

### 执行顺序

- 启动时：按文件名字母序处理 `volumes/tasks/` 中已有的 `.md` 文件
- 运行中：通过 `inotifywait` 实时检测新文件，检测到后延迟 0.5 秒（确保写入完成）再执行
- 串行执行：同一时间只执行一个任务

### 执行参数

Monitor 调用 Claude 时使用以下参数：

| 参数 | 值 | 说明 |
|------|-----|------|
| `--print` | - | 非交互模式，直接输出结果 |
| `--output-format` | `text` | 纯文本输出 |
| `--verbose` | - | 详细输出 |
| `--max-turns` | `50` | 最大对话轮次 |
| `--permission-mode` | `bypassPermissions` | 跳过权限确认（沙盒内安全） |
| timeout | 1800s | 30 分钟超时 |

---

## 报告查看

每个任务执行完成后，Stop Hook 自动生成报告。

### 报告位置

```
volumes/reports/report-<task_id>.md
```

### 报告内容

```markdown
# Task Report: <task_id>

- Completed: 2026-02-23 12:30:00
- Status: completed

## Git Changes

### Changed Files
```
 M quicksort.py
?? test_quicksort.py
```

### Diff Summary
```
 quicksort.py   | 45 +++++++++++++++++++++++++++++++++++++++++++++
 test_quicksort.py | 30 ++++++++++++++++++++++++++++++
 2 files changed, 75 insertions(+)
```
```

报告包含：
- 任务 ID 和完成时间
- `git status --short`（变更文件列表）
- `git diff --stat HEAD`（变更统计）

### 查看命令

```bash
# 列出所有报告
ls volumes/reports/

# 查看特定报告
cat volumes/reports/report-my-task.md

# 查看最新报告
ls -lt volumes/reports/ | head -5
```

---

## 配置文件

### .env — 环境变量

```bash
# API 配置（必填）
ANTHROPIC_BASE_URL=https://api.anthropic.com    # API 端点
ANTHROPIC_AUTH_TOKEN=sk-ant-xxx                  # API Token
ANTHROPIC_MODEL=claude-sonnet-4-20250514        # 模型名称

# 代理配置（可选）
HTTP_PROXY=http://127.0.0.1:7890
HTTPS_PROXY=http://127.0.0.1:7890
```

支持任何兼容 Anthropic API 格式的端点，例如：

```bash
# 使用 BigModel GLM
ANTHROPIC_BASE_URL=https://open.bigmodel.cn/api/anthropic
ANTHROPIC_MODEL=glm-5
```

### settings.json — Claude Code Stop Hook

构建镜像时自动写入 `/home/node/.claude/settings.json`：

```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "python3 /app/scripts/on_stop_hook.py",
            "timeout": 30
          }
        ]
      }
    ]
  }
}
```

这个配置让 Claude Code 每次执行结束时自动调用 `on_stop_hook.py` 生成报告。

---

## 容器配置

### docker-compose.yml

```yaml
services:
  coding-agent:
    build:
      context: ..
      dockerfile: docker/Dockerfile
    container_name: coding-agent
    network_mode: host              # 共享宿主机网络（方便代理访问）
    env_file: ../.env               # 加载环境变量
    environment:
      - NVIDIA_VISIBLE_DEVICES=all
      - NVIDIA_DRIVER_CAPABILITIES=compute,utility
    volumes:
      - ../volumes/tasks:/app/tasks         # 任务输入
      - ../volumes/reports:/app/reports     # 报告输出
      - ../volumes/workspace:/app/workspace # Claude 工作目录
      - ../volumes/logs:/home/node/.claude/logs  # Claude 日志
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
    restart: unless-stopped
```

### 网络模式

默认 `network_mode: host`，容器直接使用宿主机网络。好处：
- 可直接访问宿主机代理（如 `127.0.0.1:7890`）
- 无需端口映射

如不需要代理，可改为 bridge 模式并移除代理环境变量。

### GPU 配置

默认分配所有 GPU。如需指定特定 GPU：

```yaml
environment:
  - NVIDIA_VISIBLE_DEVICES=0        # 只用 GPU 0
```

### 不需要 GPU

修改 `Dockerfile` 基础镜像：

```dockerfile
# 替换
FROM nvidia/cuda:12.1.0-runtime-ubuntu22.04
# 为
FROM ubuntu:22.04
```

并移除 `docker-compose.yml` 中的 `deploy.resources` 段和 NVIDIA 环境变量。

### Volume 挂载

| 宿主机路径 | 容器路径 | 用途 |
|------------|----------|------|
| `volumes/tasks` | `/app/tasks` | 任务文件（输入） |
| `volumes/reports` | `/app/reports` | 报告文件（输出） |
| `volumes/workspace` | `/app/workspace` | Claude 工作目录 |
| `volumes/logs` | `/home/node/.claude/logs` | Claude Code 日志 |

### Dockerfile 技术栈

| 组件 | 说明 |
|------|------|
| 基础镜像 | `nvidia/cuda:12.1.0-runtime-ubuntu22.04` |
| Node.js | 20 |
| Claude Code | `@anthropic-ai/claude-code` (latest) |
| Python | 3.10 |
| inotify-tools | 文件监听 |
| 运行用户 | `node` (UID 1000) |

### 容器环境变量

| 变量 | 值 | 说明 |
|------|-----|------|
| `NODE_ENV` | `production` | Node 环境 |
| `CLAUDE_LOG_LEVEL` | `debug` | Claude 日志级别 |
| `FORCE_COLOR` | `1` | 启用彩色输出 |

---

## 清空并重建

以下步骤用于清空沙盒容器与持久化数据，并重建一个全新的环境。

### 1. 停止并移除容器

```bash
cd codingAgent/docker
docker compose down
```

### 2. 清空持久化目录

```bash
cd ..
rm -rf volumes/tasks/*
rm -rf volumes/reports/*
rm -rf volumes/workspace/*
rm -rf volumes/claude-home/*
```

### 3. 重新构建并启动

```bash
cd docker
docker compose build
docker compose up -d
```

如果你希望保留历史报告或工作区内容，请不要删除对应的 `volumes/` 子目录。

---

## 调试信息查看

### Docker 容器日志

Monitor 脚本的所有输出都打印到 stdout，通过 Docker 日志查看：

```bash
# 实时跟踪
docker logs -f coding-agent

# 最近 50 行
docker logs --tail 50 coding-agent

# 带时间戳
docker logs -f --timestamps coding-agent
```

日志格式示例：

```
[monitor] codingAgent monitor starting
[monitor] Claude Code version: 1.0.33
[monitor] Starting task: my-task
[monitor] Prompt length: 128 chars
[monitor] Task my-task finished with exit code 0
[monitor] Output length: 2048 chars
[monitor] Moved my-task.md to done/
[monitor] Watching for new tasks...
```

### Claude Code 日志

Claude Code 的详细日志挂载到宿主机：

```bash
# 查看日志目录
ls volumes/logs/

# 查看最新日志
ls -lt volumes/logs/ | head -10
```

容器内 `CLAUDE_LOG_LEVEL=debug`，会输出完整的调试信息。

### Stop Hook 日志

`on_stop_hook.py` 的输出写入 stderr，会出现在 Docker 日志中：

```
[hook] Report written: report-my-task.md
```

### 任务执行状态

```bash
# 查看待处理任务
ls volumes/tasks/*.md 2>/dev/null

# 查看已完成任务
ls volumes/tasks/done/

# 查看工作区文件变更
ls -la volumes/workspace/

# 查看 workspace 的 git 状态（如果是 git 仓库）
cd volumes/workspace && git status
```

### 进入容器调试

```bash
# 进入容器 shell
docker exec -it coding-agent bash

# 查看进程
ps aux

# 手动执行 claude 测试
claude --version

# 查看文件系统
ls -la /app/tasks/ /app/reports/ /app/workspace/

# 查看 Claude 配置
cat /home/node/.claude/settings.json
```

### 常用调试命令汇总

```bash
# 容器状态
docker ps | grep coding-agent
docker inspect coding-agent | jq '.[0].State'

# 资源使用
docker stats coding-agent --no-stream

# GPU 状态
docker exec coding-agent nvidia-smi

# 重启容器
docker restart coding-agent

# 重建并启动
cd docker && docker compose up -d --build
```

---

## 目录结构

```
codingAgent/
├── .env                    # 环境变量（从 .env.example 复制并修改）
├── .env.example            # 环境变量模板
│
├── docker/
│   ├── Dockerfile          # 容器镜像定义
│   └── docker-compose.yml  # 编排配置
│
├── scripts/
│   ├── monitor.py          # 主监控脚本（任务调度）
│   └── on_stop_hook.py     # Stop Hook（报告生成）
│
├── volumes/                # 数据卷（持久化，与容器共享）
│   ├── tasks/              # 任务输入
│   │   ├── *.md            # 待处理任务
│   │   └── done/           # 已完成任务
│   ├── reports/            # 报告输出
│   │   └── report-*.md
│   ├── workspace/          # Claude 工作目录
│   └── logs/               # Claude Code 日志
│
└── doc/
    └── system-guide.md     # 本文档
```

---

## 常见问题

### 容器启动失败

```bash
# 检查 .env 配置
cat .env

# 查看启动日志
docker logs coding-agent
```

常见原因：`.env` 未创建、Token 未填写、Docker 未安装 nvidia-container-toolkit。

### 任务没有被执行

```bash
# 确认文件在正确目录且为 .md 后缀
ls volumes/tasks/*.md

# 确认容器在运行
docker ps | grep coding-agent

# 查看 monitor 日志
docker logs --tail 20 coding-agent
```

### 任务超时

默认 30 分钟超时。如需调整，修改 `scripts/monitor.py` 第 62 行的 `timeout` 值：

```python
timeout=1800,  # 改为你需要的秒数
```

修改后需重新构建镜像：`cd docker && docker compose up -d --build`

### 报告没有生成

Stop Hook 依赖 `TASK_ID` 环境变量。检查：

```bash
# 查看 hook 是否配置正确
docker exec coding-agent cat /home/node/.claude/settings.json

# 查看 hook 日志（在 docker logs 中搜索 [hook]）
docker logs coding-agent 2>&1 | grep hook
```

### 权限问题

容器以 UID 1000 运行。如果 volumes 目录权限不对：

```bash
chown -R 1000:1000 volumes/
```

### 代理问题

容器使用 `host` 网络模式。如果宿主机没有代理服务，从 `.env` 中移除或注释掉 `HTTP_PROXY` 和 `HTTPS_PROXY`。

### 清理数据

```bash
# 清理已完成任务
rm -rf volumes/tasks/done/*

# 清理报告
rm -rf volumes/reports/*

# 清理工作区
rm -rf volumes/workspace/*

# 清理日志
rm -rf volumes/logs/*
```
