# Plan Agent MVP 设计

## 核心思路

Plan Agent 是一个基于 LLM 的异步循环系统，不直接操作代码，只操作"策略"和"任务流"。通过文件系统与 CodingAgent 协作。

MVP 目标：跑通 **"输入目标 → 自动拆解 → 逐步执行 → 根据反馈调整 → 完成"** 这条主线。

---

## 核心循环

```
用户输入目标
    ↓
LLM 拆解为步骤列表
    ↓
┌─→ 取下一步，生成 task.md → commands/pending/
│   ↓
│   轮询等待 reports/pending/ 出现报告
│   ↓
│   读取报告，交给 LLM 评估
│   ↓
│   LLM 决定：继续原计划 / 调整计划 / 重试 / 失败终止
│   ↓
└─← 还有下一步？
    ↓
完成，输出总结
```

---

## 文件结构

```
planAgent/
├── doc/                    # 设计文档
├── core/
│   ├── __init__.py
│   ├── orchestrator.py     # 主循环：init → plan → execute loop → summarize
│   ├── llm.py              # LLM 调用封装（Claude API）
│   └── coding_bridge.py    # 与 CodingAgent 的文件交互（写指令、读报告、轮询等待）
├── config.py               # 路径配置、超时等
└── main.py                 # 入口
```

---

## 模块职责

### main.py
程序入口，接收用户输入的项目目标，启动 orchestrator。

### config.py
路径配置（commands/pending、reports/pending、workspace 等）、超时时间、重试次数、LLM 模型配置。

### core/orchestrator.py
一个类搞定主循环 + 状态管理 + MISSION.md 更新：
- `run(goal)`: 主入口
- `plan(goal)`: 调用 LLM 拆解目标为步骤列表
- `execute_loop()`: 逐步执行，每步发任务 → 等报告 → 评估 → 决策
- `evaluate(report)`: 调用 LLM 评估报告，返回决策（next / retry / replan / abort）
- `summarize()`: 项目完成后输出总结

状态用实例变量维护：
- `steps: list[dict]` — 步骤队列
- `current_step: int` — 当前步骤索引
- `session_id: str | None` — 当前 CodingAgent 会话 ID
- `retry_count: int` — 当前步骤重试计数

### core/llm.py
封装 Claude API 调用：
- `call(system_prompt, user_message) -> str`: 基础调用
- 支持结构化输出解析（从 LLM 响应中提取 JSON/YAML）

### core/coding_bridge.py
与 CodingAgent 的文件交互：
- `send_task(task_id, description, session_id, command_type) -> str`: 写指令文件到 commands/pending/
- `wait_for_report(task_id, timeout) -> dict`: 轮询等待报告文件出现，解析 frontmatter + 内容
- `parse_report(filepath) -> dict`: 解析报告的 status、session_id、内容等

轮询实现：`while not os.path.exists(report_path): sleep(5)`，不用 watchdog。

---

## 与 CodingAgent 的交互协议

### 发送任务
写 Markdown 文件到 `volumes/commands/pending/task-<id>.md`：
```markdown
---
id: task-<uuid>
created_at: <ISO8601>
session_id: auto | <session-uuid>
command_type: new | continue | end
---

## 任务描述
<具体任务内容>

## 约束条件
<约束>

## 预期输出
<期望结果>
```

### 接收报告
从 `volumes/reports/pending/report-<id>.md` 读取，关键字段：
- `status`: SUCCESS / FAILED / PARTIAL_SUCCESS
- `session_id`: 用于后续 continue 对话
- 核心成果、填坑记录、下一步建议

### 文件流转
```
commands/pending/task-xxx.md  →  CodingAgent 处理  →  commands/processed/task-xxx.md
                                                   →  reports/pending/report-task-xxx.md
```

---

## 容错机制

1. **重试**: 同一步骤失败时，最多重试 3 次，使用 `command_type: continue` 继续会话
2. **重规划**: LLM 评估报告后认为需要调整策略时，重新生成后续步骤
3. **Human-in-the-loop**: 连续 3 次失败无法恢复时，终端 `input()` 请求人工介入
4. **超时**: 单任务等待报告默认超时 10 分钟

---

## MVP 不做的事

- 任务依赖图（线性执行即可）
- watchdog 文件监听（轮询够用）
- 细粒度组件拆分（一个 orchestrator 搞定）
- prompt 文件分离（直接写在代码里）
- Web UI / API 接口
- 多项目并行
