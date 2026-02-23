# codingAgent 系统使用指南

> 基于 Docker 容器的 Claude Code 沙盒编码智能体系统。
> 通过文件驱动的方式提交任务，容器内 Monitor 自动拾取并调度 Claude Code 执行，执行完成后生成结构化报告。

---

## 目录

- [系统架构](#系统架构)
- [快速开始](#快速开始)
- [任务提交](#任务提交)
- [会话管理](#会话管理)
- [上下文注入系统](#上下文注入系统)
- [实时监控](#实时监控)
- [报告与交接](#报告与交接)
- [配置参考](#配置参考)
- [调试信息查看](#调试信息查看)
- [容器配置](#容器配置)
- [目录结构](#目录结构)
- [常见问题](#常见问题)

---

## 系统架构

```
宿主机                                    Docker 容器 (claude-code-agent)
┌──────────────────────┐                 ┌──────────────────────────────────┐
│                      │   Volume Mount  │                                  │
│  quick-task.sh ──────┼──────────────►  │  monitor.sh (主循环)              │
│  create-command.sh   │                 │    ├─ inotify / polling 监听     │
│                      │                 │    ├─ 解析 frontmatter           │
│  volumes/commands/   │◄───────────────►│    ├─ session.sh (会话管理)       │
│    pending/  *.md    │                 │    ├─ combine_context.py (上下文) │
│    processed/        │                 │    ├─ tmux + claude --print      │
│                      │                 │    ├─ 报告生成                    │
│  volumes/reports/    │◄────────────────│    └─ validate_handover.py       │
│    pending/  *.md    │                 │                                  │
│                      │                 │  工作目录: /app/volumes/workspace │
│  volumes/workspace/  │◄───────────────►│  Claude Home: /home/node/.claude │
│  volumes/logs/       │◄────────────────│  日志: /app/volumes/logs         │
│  volumes/sessions/   │◄───────────────►│  会话: /app/volumes/sessions     │
│                      │                 │                                  │
│  watch.sh (监控)     │                 └──────────────────────────────────┘
└──────────────────────┘
```

核心流程：

1. 宿主机将 Markdown 任务文件写入 `volumes/commands/pending/`
2. 容器内 `monitor.sh` 通过 inotify（或 polling）检测到新文件
3. 解析 frontmatter 获取任务元数据，管理会话状态
4. 组合层级化上下文，注入到任务描述前
5. 在 tmux 中启动 `claude --print` 执行任务
6. 执行完成后解析 JSONL 日志，提取思考过程和工具调用
7. 生成详细报告，运行交接验证，将任务文件归档到 `processed/`

---

## 快速开始

### 1. 环境准备

前置要求：
- Docker + Docker Compose
- NVIDIA Docker Runtime（GPU 支持）
- Anthropic API Token

### 2. 配置

```bash
cd codingAgent
cp .env.example .env
```

编辑 `.env` 填入你的配置：

```bash
ANTHROPIC_BASE_URL=https://api.anthropic.com
ANTHROPIC_AUTH_TOKEN=sk-ant-xxx          # 必填：API Token
ANTHROPIC_MODEL=claude-sonnet-4-6       # 模型选择
TZ=UTC
```

### 3. 构建并启动

```bash
cd docker
docker compose build
docker compose up -d
```

### 4. 验证运行

```bash
# 查看容器状态
docker ps | grep claude-code-agent

# 查看启动日志
docker logs claude-code-agent

# 验证 GPU（可选）
docker exec claude-code-agent nvidia-smi
```

### 5. 提交第一个任务

```bash
cd codingAgent
./quick-task.sh "创建一个 hello.py，打印 Hello World"
```

### 6. 查看结果

```bash
# 实时监控
./watch.sh --tail

# 查看报告
ls volumes/reports/pending/
cat volumes/reports/pending/report-*.md
```

---

## 任务提交

### 方式一：quick-task.sh（推荐）

最简单的方式，一行命令创建任务：

```bash
# 新任务（自动创建新会话）
./quick-task.sh "用 Python 写一个快速排序算法"

# 继续已有会话
./quick-task.sh "给排序函数添加单元测试" <session_id>
```

`session_id` 可以从上一次的报告中获取。

### 方式二：create-command.sh（更多选项）

```bash
# 新任务
./scripts/create-command.sh -t new "实现用户登录功能"

# 继续会话
./scripts/create-command.sh -t continue -s <session_id> "添加密码验证"

# 带约束条件
./scripts/create-command.sh -t new -c "使用Python,不使用第三方库" "实现 JSON 解析器"

# 结束会话
./scripts/create-command.sh -t end -s <session_id> "任务完成"
```

### 方式三：手动创建 Markdown 文件

直接在 `volumes/commands/pending/` 下创建 `.md` 文件：

```markdown
---
id: my-task-001
created_at: 2026-02-23T10:00:00Z
session_id: auto
command_type: new
---

# 任务指令

## 任务描述
用 Python 实现一个简单的 HTTP 服务器，支持 GET 和 POST 请求。

## 约束条件
- 仅使用标准库
- 端口使用 8080

## 预期输出
- server.py 文件
- README.md 使用说明
```

### 任务文件 Frontmatter 字段

| 字段 | 必填 | 说明 |
|------|------|------|
| `id` | 是 | 任务唯一标识，用于报告关联 |
| `created_at` | 否 | ISO 8601 时间戳 |
| `session_id` | 是 | `auto` = 新建会话；指定 UUID = 继续/结束已有会话 |
| `command_type` | 是 | `new` / `continue` / `end` |

---

## 会话管理

系统支持多轮对话，通过 `session_id` 串联同一会话的多次任务。

### 会话生命周期

```
new (session_id=auto)  →  创建新会话，分配 UUID
        ↓
continue (session_id=xxx)  →  继续已有会话，递增轮次
        ↓
end (session_id=xxx)  →  标记会话结束
```

### 会话状态文件

存储在 `volumes/sessions/<session_id>.json`：

```json
{
  "session_id": "9b869c54-47cf-4b4c-ab8a-83483453972b",
  "created_at": "2026-02-23T04:19:39Z",
  "last_activity": "2026-02-23T04:19:49Z",
  "turn_count": 3,
  "status": "active",
  "workspace": "/app/volumes/workspace"
}
```

### 查看活跃会话

```bash
# 查看所有会话文件
ls volumes/sessions/

# 查看某个会话状态
cat volumes/sessions/<session_id>.json | jq '.'
```

---

## 上下文注入系统

系统支持三级层级化上下文，在任务执行前自动组合并注入到 Claude 的提示词中。

### 上下文层级

```
Global（全局）     →  所有任务通用的规范和指南
  docker/context/global/*.md

Project（项目）    →  特定项目的架构和约定
  docker/context/project/*.md
  volumes/workspace/.context/*.md    （workspace 内的项目上下文）
  volumes/context/project/*.md       （运行时注入，优先级最高）

Task（任务）       →  特定任务的背景信息
  docker/context/task/*.md
  volumes/context/task/*.md          （运行时注入，优先级最高）
```

优先级：运行时目录 (`volumes/context/`) > workspace 目录 > 模板目录 (`docker/context/`)

同名文件会被高优先级覆盖。

### 上下文文件格式

每个 `.md` 文件支持 Frontmatter 元数据：

```markdown
---
title: 编码规范
priority: 10
tags: [coding, standards]
enabled: true
---

## 实际内容...
```

| 字段 | 说明 |
|------|------|
| `title` | 显示标题 |
| `priority` | 排序优先级，数字越小越靠前 |
| `tags` | 标签，用于过滤 |
| `enabled` | `false` 则跳过该文件 |

### 内置上下文模板

| 文件 | 层级 | 说明 |
|------|------|------|
| `global/coding-standards.md` | Global | 编码规范、Git 提交规范 |
| `global/tool-usage.md` | Global | Claude Code 工具使用指南 |
| `project/project-overview.md` | Project | 项目概述模板（默认 disabled） |
| `task/task-context.md` | Task | 任务上下文模板（默认 disabled） |

### 手动使用上下文组合器

```bash
# 进入容器
docker exec -it claude-code-agent bash

# 组合所有层级
python3 /app/templates/context/combine_context.py --task-id task-001 --output /tmp/ctx.md

# 只组合全局和项目级
python3 /app/templates/context/combine_context.py --levels global,project

# 按标签过滤
python3 /app/templates/context/combine_context.py --tags python,api

# 列出所有上下文文件
python3 /app/templates/context/combine_context.py --list-levels

# 验证上下文文件
python3 /app/templates/context/combine_context.py --validate
```

---

## 实时监控

### watch.sh 监控脚本

```bash
# 实时日志流（默认模式）—— 带颜色高亮
./watch.sh
./watch.sh --tail

# 附加到容器内 tmux 会话（交互式，可手动介入）
./watch.sh --attach
# 退出: Ctrl+B 然后按 D（不会中断任务）

# 仅显示状态概览
./watch.sh --status
```

状态概览会显示：待处理任务数、已生成报告数、工作区文件数、日志大小、tmux 运行状态。

### Docker 日志

```bash
# Monitor 脚本的标准输出
docker logs -f claude-code-agent

# 最近 100 行
docker logs --tail 100 claude-code-agent
```

### 容器内直接查看

```bash
# 进入容器
docker exec -it claude-code-agent bash

# 查看运行时日志
tail -f /app/volumes/logs/claude_runtime.log

# 查看特定任务的调试日志
tail -f /app/volumes/logs/debug-<command_id>.log

# 附加到 tmux 会话
tmux attach -t claude_session
```

---

## 报告与交接

### 报告生成流程

每个任务执行完成后，系统会：

1. 从 JSONL 日志中提取 AI 思考过程、工具调用记录、会话统计
2. 启动第二轮 Claude 调用，生成详细执行报告
3. 更新 `AGENT_MISSION.md`（进度、避坑指南、下一步）
4. 运行 `validate_handover.py` 交接验证

### 报告文件

报告输出到 `volumes/reports/pending/`：

| 文件 | 说明 |
|------|------|
| `report-<command_id>.md` | 主报告（如有详细报告则合并） |
| `detailed-report-<command_id>.md` | 详细执行报告（含成果、决策、填坑记录） |

报告包含以下章节：
- 执行摘要 / 任务概览
- 核心成果（文件变更、功能实现、验证结果）
- ADR 与决策同步
- 填坑记录与风险预警
- AI 思考过程（从 JSONL 提取）
- 工具调用记录
- 会话统计
- 文件变更（git status）

### AGENT_MISSION.md（跨智能体记忆）

位于 `volumes/workspace/AGENT_MISSION.md`，是项目的"记忆中枢"：

- 项目愿景与目标
- 当前工作计划 (Roadmap)
- 实施进度追踪
- 避坑指南与经验记录
- 下一步指令
- 变更历史

每个任务结束时自动更新，确保下一个智能体可以无缝接手。

### ADR（架构决策记录）

涉及架构变动时，系统会在 `volumes/workspace/docs/decisions/` 下创建 ADR 文件：

```
ADR-01: 决策标题
├── Context（背景）
├── Failed Attempts（失败尝试）
├── Final Decision（最终决策）
└── Consequences（影响）
```

### 交接验证

`validate_handover.py` 自动检查：
- AGENT_MISSION.md 是否存在且包含必要章节
- 下一步是否有待办事项
- ADR 目录状态
- 未提交的 Git 变更
- 遗留临时文件

```bash
# 手动运行验证
docker exec claude-code-agent python3 /app/scripts/validate_handover.py

# 严格模式（警告也视为错误）
docker exec claude-code-agent python3 /app/scripts/validate_handover.py --strict
```

---

## 配置参考

### .env 环境变量

```bash
ANTHROPIC_BASE_URL=https://api.anthropic.com   # API 地址
ANTHROPIC_AUTH_TOKEN=sk-ant-xxx                 # API Token（必填）
ANTHROPIC_MODEL=claude-sonnet-4-6              # 模型
TZ=UTC                                          # 时区
```

### config/settings.json

```json
{
  "monitor": {
    "poll_interval_ms": 1000,    // polling 间隔（毫秒），inotify 不可用时生效
    "use_inotify": true          // 优先使用 inotify
  },
  "session": {
    "timeout_minutes": 30,       // 会话超时时间
    "max_turns": 100             // 最大对话轮次
  },
  "paths": {
    "commands": "/app/volumes/commands",
    "reports": "/app/volumes/reports",
    "workspace": "/app/volumes/workspace",
    "sessions": "/app/volumes/sessions"
  },
  "logging": {
    "level": "info",
    "container_log": "/app/logs/monitor.log",
    "host_log": "./logs/host-monitor.log"
  }
}
```

### .clauderc（Claude 行为约束）

容器内 `/home/node/.clauderc` 定义了 Claude 的 systemPrompt，强制执行以下行为：

1. 修改核心逻辑前先检查 `AGENT_MISSION.md`
2. 失败方案必须记录在避坑指南中
3. 任务结束前必须更新进度和下一步指令
4. 架构变动需创建 ADR
5. 使用 Conventional Commits 提交
6. 保持交接意识

### monitor.sh 环境变量

以下变量可在 `docker-compose.yml` 的 `environment` 中覆盖：

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `COMMANDS_DIR` | `/app/volumes/commands/pending` | 任务文件目录 |
| `PROCESSED_DIR` | `/app/volumes/commands/processed` | 已处理任务目录 |
| `REPORTS_DIR` | `/app/volumes/reports/pending` | 报告输出目录 |
| `WORKSPACE_DIR` | `/app/volumes/workspace` | 工作目录 |
| `SESSIONS_DIR` | `/app/volumes/sessions` | 会话状态目录 |
| `POLL_INTERVAL` | `1000` | Polling 间隔（毫秒） |
| `TMUX_SESSION` | `claude_session` | Tmux 会话名 |

---

## 调试信息查看

### 日志文件一览

| 文件 | 位置（宿主机） | 说明 |
|------|----------------|------|
| 终端录制 | `volumes/logs/claude_runtime.log` | `script` 命令录制的完整终端输出 |
| 任务调试日志 | `volumes/logs/debug-<command_id>.log` | Claude Code `--debug-file` 输出 |
| 最新调试日志 | `volumes/claude-home/debug/latest` | 指向最新的调试文件 |
| Monitor 日志 | `logs/monitor.log` | Monitor 脚本日志 |
| Docker 日志 | `docker logs claude-code-agent` | 容器标准输出 |

### JSONL 会话日志

Claude Code 的完整会话记录（含思考过程、工具调用）存储在：

```
volumes/claude-home/projects/-app-volumes-workspace/<session_id>.jsonl
```

每行是一个 JSON 对象，结构如下：

```json
// 用户消息
{"type": "user", "message": {"content": "任务描述..."}}

// 助手消息（包含思考、工具调用、文本回复）
{"type": "assistant", "message": {"content": [
  {"type": "thinking", "thinking": "让我分析一下..."},
  {"type": "tool_use", "name": "Write", "id": "xxx", "input": {...}},
  {"type": "text", "text": "我已经完成了..."}
]}}
```

### 手动提取会话信息

```bash
# 进入容器
docker exec -it claude-code-agent bash

# 提取思考过程
source /app/scripts/session.sh
extract_thinking <session_id>

# 提取工具调用
extract_tool_uses <session_id>

# 查看会话统计
get_session_stats <session_id>

# 生成完整会话摘要
generate_session_summary <session_id>
```

### 常用调试命令

```bash
# 查看容器健康状态
docker inspect claude-code-agent | jq '.[0].State.Health'

# 查看容器资源使用
docker stats claude-code-agent --no-stream

# 查看 GPU 使用
docker exec claude-code-agent nvidia-smi

# 查看待处理任务
ls -la volumes/commands/pending/

# 查看已处理任务
ls -la volumes/commands/processed/

# 查看最新报告
ls -lt volumes/reports/pending/ | head -5

# 查看会话状态
cat volumes/sessions/*.json | jq '.'
```

---

## 容器配置

### docker-compose.yml 关键配置

```yaml
services:
  claude-code:
    build:
      context: ..
      dockerfile: docker/Dockerfile
    container_name: claude-code-agent
    restart: unless-stopped

    # 使用 host 网络模式，直接访问宿主机代理
    network_mode: host

    # GPU 支持
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all              # 分配所有 GPU
              capabilities: [gpu]

    # 代理配置（host 网络模式下直接访问 127.0.0.1）
    environment:
      - HTTP_PROXY=http://127.0.0.1:7890
      - HTTPS_PROXY=http://127.0.0.1:7890
      - NO_PROXY=localhost,127.0.0.1
```

### 网络模式

默认使用 `network_mode: host`，容器直接共享宿主机网络栈。好处：
- 可直接访问宿主机的代理（如 `127.0.0.1:7890`）
- 无需端口映射

如果不需要代理，可以改为 bridge 模式并移除代理环境变量。

### GPU 配置

默认分配所有 GPU。如需指定特定 GPU：

```yaml
deploy:
  resources:
    reservations:
      devices:
        - driver: nvidia
          device_ids: ['0']          # 只使用 GPU 0
          capabilities: [gpu]
```

或通过环境变量控制：

```yaml
environment:
  - NVIDIA_VISIBLE_DEVICES=0,1       # 指定可见 GPU
```

### 不需要 GPU 的场景

如果不需要 GPU 支持，修改 `Dockerfile` 的基础镜像：

```dockerfile
# 替换
FROM nvidia/cuda:12.1.0-runtime-ubuntu22.04
# 为
FROM ubuntu:22.04
```

并移除 `docker-compose.yml` 中的 `deploy.resources` 段。

### Volume 挂载

| 宿主机路径 | 容器路径 | 读写 | 用途 |
|------------|----------|------|------|
| `volumes/commands` | `/app/volumes/commands` | rw | 任务文件 |
| `volumes/reports` | `/app/volumes/reports` | rw | 报告输出 |
| `volumes/workspace` | `/app/volumes/workspace` | rw | Claude 工作目录 |
| `volumes/sessions` | `/app/volumes/sessions` | rw | 会话状态 |
| `volumes/logs` | `/app/volumes/logs` | rw | 运行时日志 |
| `volumes/claude-home` | `/home/node/.claude` | rw | Claude 会话数据 |
| `volumes/context` | `/app/volumes/context` | ro | 运行时上下文（planAgent 写入） |
| `config` | `/app/config` | ro | 配置文件 |

### 日志轮转

Docker 日志配置了自动轮转：

```yaml
logging:
  driver: "json-file"
  options:
    max-size: "10m"      # 单文件最大 10MB
    max-file: "3"        # 最多保留 3 个文件
```

### 健康检查

```yaml
healthcheck:
  test: ["CMD", "pgrep", "-f", "monitor.sh"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 10s
```

### 任务执行超时

Monitor 中的默认超时：
- 任务执行：600 秒（10 分钟）
- 报告生成：180 秒（3 分钟）

如需修改，编辑 `scripts/container/monitor.sh` 中的 `max_wait` 和 `summary_timeout` 变量。

### 容器内技术栈

| 组件 | 版本 |
|------|------|
| 基础镜像 | NVIDIA CUDA 12.1.0 + Ubuntu 22.04 |
| Node.js | 20 |
| Claude Code | @anthropic-ai/claude-code (latest) |
| Python | 3.10 |
| tmux | 系统包 |
| inotify-tools | 系统包 |
| jq | 系统包 |

容器以非 root 用户 `node` (UID 1000) 运行。

---

## 目录结构

```
codingAgent/
├── .env                          # 环境变量（从 .env.example 复制）
├── .env.example                  # 环境变量模板
├── quick-task.sh                 # 快速创建任务
├── watch.sh                      # 实时监控
│
├── docker/
│   ├── Dockerfile                # 容器镜像定义
│   ├── docker-compose.yml        # 编排配置
│   ├── context/                  # 上下文模板
│   │   ├── combine_context.py    # 上下文组合器
│   │   ├── global/               # 全局上下文
│   │   ├── project/              # 项目上下文
│   │   └── task/                 # 任务上下文
│   └── templates/
│       ├── .clauderc             # Claude 行为约束
│       ├── AGENT_MISSION.md      # 任务指挥手册模板
│       ├── validate_handover.py  # 交接验证脚本
│       └── decisions/            # ADR 模板目录
│
├── scripts/
│   ├── container/
│   │   ├── monitor.sh            # 容器内主循环（核心）
│   │   └── session.sh            # 会话管理 + JSONL 解析
│   └── create-command.sh         # 创建任务（带选项）
│
├── config/
│   └── settings.json             # 系统配置
│
├── volumes/                      # 数据卷（持久化）
│   ├── commands/
│   │   ├── pending/              # 待处理任务
│   │   └── processed/            # 已处理任务
│   ├── reports/
│   │   └── pending/              # 生成的报告
│   ├── workspace/                # Claude 工作目录
│   ├── sessions/                 # 会话状态 JSON
│   ├── logs/                     # 运行时日志
│   ├── claude-home/              # Claude Code 内部数据
│   │   ├── projects/             # JSONL 会话日志
│   │   ├── debug/                # 调试文件
│   │   └── todos/                # Todo 文件
│   └── context/                  # 运行时上下文（planAgent 写入）
│
└── logs/                         # 系统日志
    └── monitor.log
```

---

## 常见问题

### 容器启动失败

```bash
# 检查 .env 是否存在且 Token 已填写
cat .env | grep ANTHROPIC_AUTH_TOKEN

# 检查 Docker 日志
docker logs claude-code-agent
```

### GPU 不可用

```bash
# 确认 nvidia-docker 已安装
nvidia-smi
docker run --rm --gpus all nvidia/cuda:12.1.0-runtime-ubuntu22.04 nvidia-smi
```

### 任务没有被执行

```bash
# 确认文件在正确目录且为 .md 后缀
ls -la volumes/commands/pending/

# 确认容器在运行
docker ps | grep claude-code-agent

# 查看 monitor 日志
docker logs --tail 50 claude-code-agent
```

### 网络/代理问题

容器使用 `host` 网络模式。如果宿主机没有运行代理服务，移除 `docker-compose.yml` 中的代理环境变量，或修改为你的代理地址。

### 权限问题

容器以 UID 1000 运行。如果 volumes 目录权限不对：

```bash
chown -R 1000:1000 volumes/
```

### 清理旧数据

```bash
# 清理旧日志
find volumes/logs -name "debug-*.log" -mtime +7 -delete

# 清理已处理任务
rm -rf volumes/commands/processed/*

# 清理旧报告
rm -rf volumes/reports/pending/*

# 清理 Claude 会话数据
rm -rf volumes/claude-home/projects/*
rm -rf volumes/claude-home/debug/*
rm -rf volumes/claude-home/todos/*
```
