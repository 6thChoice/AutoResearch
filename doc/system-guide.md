# Plan-Coding 双智能体系统指南

## 系统概述

本系统由两个协作智能体组成：

- **planAgent** — 规划层。接收用户的项目目标，调用 LLM（DeepSeek-Reasoner）将其拆解为有序步骤，逐步派发给执行层，并根据执行报告做出"继续 / 重试 / 重规划 / 终止"的决策。运行在宿主机上。
- **codingAgent** — 执行层。Docker 沙盒内运行 Claude Code CLI，通过 inotifywait 监听任务文件，执行编码工作，Stop Hook 自动生成报告。

两者通过**文件协议**通信：planAgent 写 `.md` 到 `tasks/`，codingAgent 写 `report-*.md` 到 `reports/`。

```
用户目标
  │
  ▼
planAgent (宿主机)
  │  ① LLM 拆解为步骤
  │  ② 生成三层上下文
  │  ③ 写任务文件 → volumes/tasks/task-xxxx.md
  │  ④ 轮询 reports/ 等待报告
  │  ⑤ LLM 评估 → 决策下一步
  │
  ▼
codingAgent (Docker)
  │  inotifywait 检测到新文件
  │  claude --print -p "<文件内容>"
  │  Stop Hook → volumes/reports/report-task-xxxx.md
  │
  ▼
循环直到所有步骤完成
```

---

## 快速开始

### 1. 启动 codingAgent

```bash
cd codingAgent

# 配置 API 凭证
cp .env.example .env
# 编辑 .env，填入 ANTHROPIC_AUTH_TOKEN 和 ANTHROPIC_MODEL

# 构建并启动容器
cd docker
docker compose up -d --build
```

容器启动后 monitor.py 自动进入监听状态，等待 `volumes/tasks/` 中出现 `.md` 文件。

### 2. 配置 planAgent

编辑 `planAgent/config.py`，确认 LLM 配置：

```python
LLM_BASE_URL = "https://api.deepseek.com/v1"
LLM_API_KEY  = "sk-xxx"
LLM_MODEL    = "deepseek-reasoner"
```

### 3. 运行

```bash
# 方式一：命令行参数
python -m planAgent.main "用 Flask 写一个带用户认证的 REST API"

# 方式二：交互式输入
python -m planAgent.main
# > 请输入项目目标: ...
```

planAgent 会自动完成：拆解 → 派发 → 等待 → 评估 → 循环，直到所有步骤完成或人工介入。

---

## 上下文管理

planAgent 维护三层上下文，全部在内存中管理，最终拼接为一段文本注入任务 prompt：

| 层级 | 生命周期 | 内容 | 长度限制 |
|------|---------|------|---------|
| **global** | 整个项目 | 项目目标 + 完整步骤列表 | 无（通常很短） |
| **project** | 整个项目，每步后更新 | 技术栈、架构、进度摘要、关键决策 | ≤ 50 行 |
| **task** | 单步骤，执行后清除 | 当前步骤位置、前置完成情况、依赖关系 | ≤ 30 行 |

### 上下文流转

```
init_project(goal, steps)
  ├─ global_ctx  = 目标 + 步骤列表（直接拼接）
  └─ project_ctx = LLM 生成（PROJECT_CONTEXT_SYSTEM prompt）

每步执行前:
  └─ task_ctx = LLM 生成（TASK_CONTEXT_SYSTEM prompt）

每步执行后:
  ├─ project_ctx = LLM 更新（PROJECT_UPDATE_SYSTEM prompt + 报告摘要）
  └─ task_ctx = 清空

发送任务时:
  └─ build_context() → global + project + task 用 "---" 分隔，拼入 prompt
```

上下文不通过文件注入 codingAgent，而是直接拼入任务 `.md` 文件的开头部分。codingAgent 的 monitor.py 会把整个文件内容作为 `claude -p` 的 prompt。

---

## 文件协议

### 任务文件

路径：`codingAgent/volumes/tasks/task-<8位hex>.md`

```markdown
# 项目计划                          ← global 上下文
...
---
# 项目上下文                        ← project 上下文
...
---
# 当前任务上下文                     ← task 上下文
...

## 任务描述
<具体任务内容>

## 约束条件
<约束，可选>

## 预期输出
<预期结果，可选>
```

### 报告文件

路径：`codingAgent/volumes/reports/report-task-<8位hex>.md`

由 `on_stop_hook.py`（Claude Code Stop Hook）自动生成：

```markdown
# Task Report: task-abc12345
- Completed: 2026-02-23 12:30:00
- Status: completed

## Git Changes
### Changed Files
 M app.py
?? tests/

### Diff Summary
 app.py | 42 +++++++++++++++
 1 file changed, 42 insertions(+)
```

planAgent 通过 `parse_report()` 提取 `status` 和 `completed` 字段，并将完整 `body` 传给 LLM 评估。

---

## 关键配置项

### planAgent/config.py

| 配置项 | 默认值 | 说明 |
|--------|--------|------|
| `CODING_AGENT_ROOT` | `../codingAgent` | codingAgent 根目录（相对于 planAgent） |
| `TASKS_DIR` | `codingAgent/volumes/tasks` | 任务文件写入目录 |
| `REPORTS_DIR` | `codingAgent/volumes/reports` | 报告文件读取目录 |
| `REPORT_POLL_INTERVAL` | `5` 秒 | 轮询报告的间隔 |
| `REPORT_TIMEOUT` | `1800` 秒（30 分钟） | 单任务最大等待时间，与容器超时对齐 |
| `MAX_RETRIES` | `3` | 单步骤最大重试次数 |
| `MAX_CONSECUTIVE_FAILURES` | `3` | 连续失败多少次后触发人工介入 |
| `LLM_BASE_URL` | `https://api.deepseek.com/v1` | 规划用 LLM 的 API 地址 |
| `LLM_MODEL` | `deepseek-reasoner` | 规划用模型 |
| `LLM_MAX_TOKENS` | `4096` | 单次 LLM 调用最大 token |

### codingAgent/.env

| 变量 | 示例 | 说明 |
|------|------|------|
| `ANTHROPIC_BASE_URL` | `https://api.anthropic.com` | Claude Code 使用的 API 端点 |
| `ANTHROPIC_AUTH_TOKEN` | `sk-ant-xxx` | API 密钥 |
| `ANTHROPIC_MODEL` | `claude-sonnet-4-20250514` | 执行用模型 |
| `HTTP_PROXY` / `HTTPS_PROXY` | `http://127.0.0.1:7890` | 代理（可选，容器使用 host 网络） |

### codingAgent 容器内硬编码

| 参数 | 值 | 位置 |
|------|-----|------|
| `--max-turns` | `50` | monitor.py |
| `--permission-mode` | `bypassPermissions` | monitor.py |
| `timeout` | `1800s` | monitor.py |
| Stop Hook 超时 | `30s` | settings.json / Dockerfile |

---

## 决策机制

planAgent 的 LLM 评估器在每步执行后返回四种决策：

| 决策 | 行为 |
|------|------|
| `next` | 步骤成功，推进到下一步，重置重试计数 |
| `retry` | 步骤失败但可重试，重新执行当前步骤（最多 `MAX_RETRIES` 次） |
| `replan` | 需要调整后续计划，用 `adjusted_steps` 替换剩余步骤 |
| `abort` | 无法继续，进入失败处理流程 |

连续失败 `MAX_CONSECUTIVE_FAILURES`（默认 3）次后，系统暂停并提示用户：
- 输入 `skip` — 跳过当前步骤
- 输入 `abort` — 终止整个项目
- 输入其他文本 — 作为新指令替换当前步骤

---

## 调试信息

### planAgent 控制台输出

planAgent 直接在终端打印所有状态，包括：
- `[Plan Agent]` 前缀：目标拆解、任务发送、报告接收、决策结果
- `[Context]` 前缀：上下文初始化和生成
- `[Step N/M]` 前缀：当前执行步骤

### codingAgent 容器日志

```bash
# 查看 monitor 实时日志
docker logs -f coding-agent

# 日志中的关键标记：
# [monitor] Starting task: task-xxx     ← 开始执行
# [monitor] Task xxx finished with exit code 0  ← 执行完成
# [monitor] Moved xxx.md to done/      ← 任务归档
```

### Claude Code 调试日志

容器内 `CLAUDE_LOG_LEVEL=debug`，日志存储在：

```
codingAgent/volumes/claude-home/debug/     ← 每次会话一个 .txt 文件
codingAgent/volumes/claude-home/debug/latest  ← 最近一次会话的符号链接
```

### 文件系统状态

```bash
# 查看待执行任务
ls codingAgent/volumes/tasks/*.md

# 查看已完成任务
ls codingAgent/volumes/tasks/done/

# 查看已生成报告
ls codingAgent/volumes/reports/

# 查看工作区产出
ls codingAgent/volumes/workspace/
```

### Stop Hook 日志

Stop Hook 的输出写入 stderr，会出现在容器日志中：
```
[hook] Report written: report-task-xxx.md
```

如果报告未生成，检查：
1. `settings.json` 中 Stop Hook 配置是否存在
2. `TASK_ID` 环境变量是否正确传递
3. `/app/reports/` 目录权限

---

## 目录结构

```
research/
├── planAgent/                      # 规划智能体（宿主机运行）
│   ├── main.py                     # 入口：python -m planAgent.main
│   ├── config.py                   # 路径、超时、LLM 配置
│   └── core/
│       ├── orchestrator.py         # 主循环：plan → execute → evaluate
│       ├── llm.py                  # LLM 调用封装（OpenAI 兼容接口）
│       ├── coding_bridge.py        # 文件协议：写任务、读报告
│       └── context_manager.py      # 三层上下文管理（内存模式）
│
├── codingAgent/                 # 执行智能体（Docker 容器）
│   ├── .env                        # API 凭证与代理配置
│   ├── docker/
│   │   ├── Dockerfile              # CUDA 基础镜像 + Node.js + Claude Code
│   │   └── docker-compose.yml      # host 网络、GPU、卷挂载
│   ├── scripts/
│   │   ├── monitor.py              # inotifywait 任务调度器
│   │   └── on_stop_hook.py         # Stop Hook 报告生成器
│   └── volumes/                    # 持久化数据（宿主机 ↔ 容器共享）
│       ├── tasks/                  # 任务输入（planAgent 写入）
│       │   └── done/               # 已完成任务归档
│       ├── reports/                # 报告输出（Stop Hook 写入）
│       ├── workspace/              # Claude 工作目录（代码产出）
│       └── claude-home/            # Claude Code 配置与日志
│           ├── settings.json       # Stop Hook 配置
│           └── debug/              # 调试日志
└── doc/
    └── system-guide.md             # 本文档
```
