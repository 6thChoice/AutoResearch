# Coding Agent 接口规范

> 本文档描述 Coding Agent（沙盒代码智能体）的上下文输入和工作报告输出格式，供 Plan Agent 进行集成调用时参考。

---

## 概述

Coding Agent 是一个基于 Docker 容器的 Claude Code 自动化执行系统，通过文件系统进行异步通信。它接收 Markdown 格式的指令文件，执行代码任务，并生成结构化的执行报告。

### 核心特性

- **GPU 支持**: 基于 NVIDIA CUDA 12.1，支持深度学习任务
- **异步通信**: 通过 MD 文件传递指令和报告
- **跨智能体记忆**: AGENT_MISSION.md 任务手册 + ADR 架构决策记录
- **结构化报告**: 基于模板的详细执行报告

---

## 1. 输入接口

### 1.1 指令文件格式

指令文件放置在 `volumes/commands/pending/` 目录下，使用 Markdown + YAML Frontmatter 格式。

#### 文件结构

```markdown
---
id: task-<uuid>
created_at: 2026-02-22T00:00:00Z
session_id: auto | <session-uuid>
command_type: new | continue | end
---

## 任务描述

<具体的任务内容>

## 约束条件（可选）

<任务的约束和限制>

## 预期输出（可选）

<期望的输出结果>
```

#### Frontmatter 字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `id` | string | 是 | 任务唯一标识，格式: `task-<uuid>` |
| `created_at` | ISO 8601 | 是 | 任务创建时间 |
| `session_id` | string | 是 | 会话 ID，新任务用 `auto`，继续对话用具体 ID |
| `command_type` | enum | 是 | 指令类型: `new` / `continue` / `end` |

#### 指令类型说明

| command_type | session_id | 说明 |
|--------------|------------|------|
| `new` | `auto` 或留空 | 创建新会话执行任务 |
| `continue` | 具体会话 ID | 继续已有会话的对话 |
| `end` | 具体会话 ID | 结束指定会话 |

#### 示例指令文件

```markdown
---
id: histoformer-task
session_id: auto
command_type: new
created_at: 2026-02-22T07:45:00Z
---

## 任务描述

请完成以下任务：

1. 克隆 GitHub 项目：https://github.com/sunshangquan/Histoformer.git
2. 分析项目结构，了解这是什么类型的项目
3. 查看 README 或其他文档，理解项目用途
4. 安装项目所需的依赖（注意：GPU 可用，RTX 3080 10GB）
5. 尝试运行项目，记录运行结果

## 约束条件

- 在 workspace 目录下操作
- 详细记录每一步的操作和结果
- 如果遇到错误，尝试分析原因并解决
- GPU 可用，可以安装 CUDA 相关依赖

## 预期输出

- 项目成功克隆到 workspace 目录
- 项目依赖安装完成
- 项目运行结果（成功或失败原因）
```

### 1.2 层级化上下文系统

Coding Agent 支持多层级上下文注入，可在执行任务前自动组合不同层级的上下文信息。

#### 上下文层级

```
┌─────────────────────────────────────────────────┐
│  Global 级 (docker/context/global/)             │
│  ├── coding-standards.md    编码规范            │
│  └── tool-usage.md          工具使用指南        │
├─────────────────────────────────────────────────┤
│  Project 级 (workspace/.context/ 或 context/project/) │
│  ├── project-overview.md    项目概述            │
│  └── architecture.md        架构设计            │
├─────────────────────────────────────────────────┤
│  Task 级 (context/task/<task-id>/)              │
│  └── *.md                   任务特定上下文      │
└─────────────────────────────────────────────────┘
```

| 层级 | 目录 | 用途 | 示例内容 |
|------|------|------|----------|
| **Global** | `context/global/` | 所有项目通用 | 编码规范、工具使用、安全规则 |
| **Project** | `workspace/.context/` | 特定项目 | 项目架构、技术栈、API 文档 |
| **Task** | `context/task/<task-id>/` | 特定任务 | 相关代码片段、参考文档 |

#### 上下文文件格式

支持 YAML Frontmatter：

```markdown
---
title: 编码规范
priority: 10          # 优先级，数字越大越靠前
tags: [coding, standards]  # 标签，可用于过滤
enabled: true         # 是否启用
---

## 编码规范内容...
```

### 1.3 任务指挥手册 (AGENT_MISSION.md)

每个项目维护一个 AGENT_MISSION.md 文件，作为跨智能体交接的"记忆中枢"。

#### 文件结构

```markdown
# Agent 任务指挥手册 (Mission Control)

## 项目愿景与目标
- **目标**: [项目目标]
- **技术栈**: [主要技术栈]
- **关键约束**: [限制条件]

## 当前工作计划 (Roadmap)
- [ ] 阶段 1: [描述]
- [ ] 阶段 2: [描述]
- [ ] 阶段 3: [描述]

## 实施进度追踪
| 模块 | 状态 | 进度 | 最后更新 | 备注 |
| :--- | :--- | :--- | :--- | :--- |
| [模块名] | 未开始 | 0% | - | - |

## 避坑指南与经验记录 (The Pitfalls)
> 记录格式：**[日期]** 问题描述 → 失败尝试 → 最终方案

## 下一步指令 (Next Steps)
- [ ] [待完成任务 1]
- [ ] [待完成任务 2]

## 变更历史
| 日期 | 智能体 | 变更内容 |
| :--- | :--- | :--- |
| YYYY-MM-DD | Agent | 初始化文档 |
```

### 1.4 行为约束配置 (.clauderc)

通过 `.clauderc` 文件强制 Claude 遵守特定规则：

```json
{
  "systemPrompt": "你是这个长期项目的维护者。你的行为准则如下：
1. 文档先于代码：在修改任何核心逻辑前，先检查 AGENT_MISSION.md
2. 记录失败：如果尝试一个修复方案失败了，必须在避坑指南中记录
3. 强制更新：任务结束前，必须更新实施进度和下一步指令
4. ADR 触发：架构变动或复杂 Bug 修复时，创建 ADR 文档
5. 提交规范：使用 Conventional Commits 格式提交代码
6. 交接意识：时刻记住，你的工作可能由其他智能体接手"
}
```

---

## 2. 输出接口

### 2.1 执行报告格式

任务完成后，Coding Agent 生成详细的执行报告文件，位于 `volumes/reports/pending/` 目录。

#### 报告文件命名

- 简要报告: `report-<command_id>.md`
- 详细报告: `detailed-report-<command_id>.md`

#### 报告结构

```markdown
---
session_id: "<session-uuid>"
report_date: "2026-02-22T15:30:00Z"
status: "SUCCESS" | "FAILED" | "PARTIAL_SUCCESS"
tags: [tag1, tag2, tag3]
---

# 执行任务总结报告

## 1. 任务概览 (Task Overview)
- **原始指令**: [引用原始任务描述]
- **关联 Mission 阶段**: [当前阶段]
- **执行状态**: SUCCESS/FAILED/PARTIAL_SUCCESS

## 2. 核心成果 (Key Deliverables)
> 详细说明修改了哪些文件，实现了哪些功能

### 文件变更
| 文件路径 | 操作 | 说明 |
| :--- | :--- | :--- |
| path/to/file | 创建/修改/删除 | 变更说明 |

### 功能实现
- [实现的功能列表]

### 验证结果
- [测试结果、运行结果等]

## 3. ADR & 决策同步 (Architectural Decisions)
> 如果有架构决策或重要技术选择，记录在这里

- **决策内容**: [描述决策]
- **理由**: [为什么做这个决策]
- **影响**: [对项目的影响]

## 4. 填坑记录与风险预警 (Pitfalls & Lessons)
> **最重要**：记录遇到的问题和解决方案

### 问题 N: [问题标题]
- **遇到的问题**: [描述问题]
- **失败尝试**: [尝试过但失败的方法]
- **最终方案**: [成功的解决方案]
- **残留风险**: [还有什么需要注意的]

## 5. Mission 手册更新说明 (Mission Sync)
- **进度更新**: [更新了哪些进度]
- **下一手建议**: [为下一个智能体建议的具体任务]

## 6. 原始执行指纹 (Artifacts)
- **Git Commit**: [commit hash]
- **相关日志**: [日志文件路径]

---

## 原始执行数据

### 会话状态
- 当前轮次: N
- 等待继续: 是/否

### AI 思考过程
\`\`\`
[从 jsonl 文件提取的 thinking 内容]
\`\`\`

### 工具调用记录
\`\`\`json
[从 jsonl 文件提取的 tool_use 记录]
\`\`\`

### 会话统计
[消息统计、工具调用统计等]

### 运行日志摘要
\`\`\`
[执行日志摘要]
\`\`\`

### 文件变更
[Git status 或最近修改的文件列表]
```

### 2.2 会话状态文件

会话状态存储在 `volumes/sessions/` 目录下，JSON 格式：

```json
{
  "session_id": "uuid",
  "created_at": "2026-02-22T10:00:00Z",
  "last_activity": "2026-02-22T10:30:00Z",
  "turn_count": 3,
  "status": "active",
  "workspace": "/app/volumes/workspace"
}
```

#### 会话状态字段

| 字段 | 类型 | 说明 |
|------|------|------|
| `session_id` | string | 会话唯一标识 |
| `created_at` | ISO 8601 | 会话创建时间 |
| `last_activity` | ISO 8601 | 最后活动时间 |
| `turn_count` | number | 对话轮次 |
| `status` | enum | 会话状态: `active` / `ended` |
| `workspace` | string | 工作区路径 |

### 2.3 调试日志

日志文件位于 `volumes/logs/` 目录：

| 文件 | 说明 |
|------|------|
| `claude_runtime.log` | 实时运行日志（包含终端输出） |
| `debug-<task-id>.log` | 特定任务的详细调试日志 |
| `monitor.log` | 监控脚本日志 |

### 2.4 ADR 架构决策记录

对于复杂的代码改动，自动生成 ADR 文档，位于 `workspace/docs/decisions/` 目录：

```markdown
# ADR-NNNN: 决策标题

## 上下文
遇到了什么问题

## 失败的尝试
试过但无效的方案

## 最终决策
选择的方案

## 后果
副作用和注意事项
```

---

## 3. 调用示例

### 3.1 创建新任务

```bash
# 方式一：使用快捷脚本
./quick-task.sh "分析 Histoformer 项目结构"

# 方式二：直接创建文件
cat > volumes/commands/pending/my-task.md << 'EOF'
---
id: task-abc123
created_at: 2026-02-22T10:00:00Z
session_id: auto
command_type: new
---

## 任务描述
创建一个 hello.py 文件，打印 Hello World
EOF
```

### 3.2 继续对话

```bash
# 使用之前任务的 session_id 继续对话
./quick-task.sh "添加单元测试" abc123-def456
```

### 3.3 获取执行结果

```bash
# 查看最新报告
cat volumes/reports/pending/report-*.md

# 查看详细报告
cat volumes/reports/pending/detailed-report-*.md

# 实时监控
./watch.sh --tail
```

---

## 4. 集成指南

### 4.1 Plan Agent 调用流程

```
Plan Agent                           Coding Agent
    │                                     │
    │  1. 生成指令文件                      │
    │  ─────────────────────────────────>  │
    │     volumes/commands/pending/        │
    │                                     │
    │                   2. 监听并执行任务   │
    │                  <──────────────────  │
    │                                     │
    │  3. 生成报告文件                      │
    │  <─────────────────────────────────  │
    │     volumes/reports/pending/         │
    │                                     │
    │  4. 解析报告，获取结果                │
    │                                     │
```

### 4.2 关键目录映射

| 用途 | Coding Agent 内部路径 | 宿主机路径 |
|------|----------------------|-----------|
| 指令输入 | `/app/volumes/commands/pending/` | `volumes/commands/pending/` |
| 执行报告 | `/app/volumes/reports/pending/` | `volumes/reports/pending/` |
| 工作区 | `/app/volumes/workspace/` | `volumes/workspace/` |
| 会话状态 | `/app/volumes/sessions/` | `volumes/sessions/` |
| 日志文件 | `/app/volumes/logs/` | `volumes/logs/` |

### 4.3 状态轮询

```bash
# 检查任务是否完成
if [ -f "volumes/commands/processed/task-xxx.md" ]; then
    echo "任务已完成"
    cat volumes/reports/pending/report-task-xxx.md
fi
```

---

## 5. 注意事项

1. **文件格式**: 指令文件必须是有效的 Markdown + YAML Frontmatter 格式
2. **会话管理**: 继续对话必须提供有效的 session_id
3. **超时设置**: 默认任务执行超时为 10 分钟，可调整
4. **权限模式**: 使用 `bypassPermissions` 模式，适合沙箱环境
5. **日志增长**: 建议定期清理旧的日志和会话文件
6. **GPU 要求**: 如需 GPU 支持，确保宿主机已安装 NVIDIA 驱动和 nvidia-docker

---

## 附录：完整示例

### 输入示例

```markdown
---
id: task-20260222-001
created_at: 2026-02-22T10:00:00Z
session_id: auto
command_type: new
---

## 任务描述

实现一个简单的 REST API 服务，包含以下功能：

1. GET /health - 健康检查端点
2. GET /users - 获取用户列表
3. POST /users - 创建新用户

## 约束条件

- 使用 Python Flask 框架
- 数据存储使用内存字典
- 添加基本的错误处理

## 预期输出

- 可运行的 Flask 应用
- 包含基本的 API 文档
```

### 输出示例

```markdown
---
session_id: "abc123-def456-789"
report_date: "2026-02-22T10:15:00Z"
status: "SUCCESS"
tags: [python, flask, rest-api]
---

# 执行任务总结报告

## 1. 任务概览 (Task Overview)
- **原始指令**: 实现 REST API 服务（health check, users CRUD）
- **关联 Mission 阶段**: 阶段 1: 基础功能实现
- **执行状态**: SUCCESS

## 2. 核心成果 (Key Deliverables)

### 文件变更
| 文件路径 | 操作 | 说明 |
| :--- | :--- | :--- |
| app.py | 创建 | Flask 主应用 |
| README.md | 创建 | API 文档 |

### 功能实现
- GET /health 端点，返回 {"status": "ok"}
- GET /users 端点，返回用户列表
- POST /users 端点，创建新用户
- 基本的错误处理（400, 404, 500）

### 验证结果
- 使用 curl 测试所有端点通过
- 健康检查返回正确响应

## 3. ADR & 决策同步 (Architectural Decisions)
- **决策内容**: 使用内存字典而非数据库
- **理由**: 符合任务约束，简化实现

## 4. 填坑记录与风险预警 (Pitfalls & Lessons)
- **遇到的问题**: Flask 需要指定 host='0.0.0.0' 才能在容器外访问
- **解决方案**: 添加 host 参数

## 5. Mission 手册更新说明 (Mission Sync)
- **进度更新**: REST API 基础功能 100% 完成
- **下一手建议**: 添加数据库持久化、添加认证中间件

## 6. 原始执行指纹 (Artifacts)
- **相关日志**: /app/volumes/logs/debug-task-20260222-001.log
```
