# Plan: 上下文管理能力集成

## 问题

planAgent 目前只通过 task md 文件与 codingAgent 通信，完全不管上下文层。
codingAgent 容器内的 `combine_context.py` 能组合 global/project/task 三层上下文，
但 project 和 task 层都是空模板（enabled: false），且没有 volume 挂载让外部写入。

## 设计方案

### 1. 路径结构改造

```
codingAgent/
├── docker/context/              ← 模板（只读，COPY 进镜像）
│   ├── combine_context.py       ← 改造：支持运行时目录覆盖
│   ├── global/                  ← 不变，通用规范
│   │   ├── coding-standards.md
│   │   └── tool-usage.md
│   ├── project/                 ← 保留为模板参考
│   │   └── project-overview.md
│   └── task/
│       └── task-context.md      ← 保留为模板参考
│
├── volumes/
│   ├── context/                 ← 新增！运行时上下文（volume 挂载）
│   │   ├── project/             ← planAgent 写入的项目级上下文
│   │   │   └── project-overview.md
│   │   └── task/                ← planAgent 写入的任务级上下文
│   │       └── <task-id>/
│   │           └── task-context.md
│   ├── commands/
│   ├── reports/
│   └── workspace/
```

### 2. combine_context.py 改造

核心变更：引入 `runtime_dir` 参数（默认 `/app/volumes/context`）。

查找逻辑变为：
- **global**: 只读模板目录 `/app/templates/context/global/`（不变）
- **project**: 优先 `runtime_dir/project/`，fallback 到模板目录
- **task**: 优先 `runtime_dir/task/<task-id>/`，fallback 到模板目录

新增 CLI 参数：`--runtime-dir /app/volumes/context`

### 3. docker-compose.yml 新增 volume

```yaml
- ../volumes/context:/app/volumes/context
```

### 4. monitor.sh 调整

调用 combine_context.py 时传入 `--runtime-dir`：

```bash
python3 /app/templates/context/combine_context.py \
    --task-id "$command_id" \
    --runtime-dir /app/volumes/context \
    --output "$context_file"
```

### 5. planAgent 新增 context_manager.py

```python
class ContextManager:
    """管理 codingAgent 的运行时上下文"""

    def __init__(self, context_dir):
        # context_dir = codingAgent/volumes/context/

    def init_project(self, goal, plan_steps) -> None:
        """run() 开始时，LLM 基于 goal + 步骤生成 project-overview.md"""

    def update_project(self, step_result, remaining_steps) -> None:
        """每步完成后，LLM 基于报告更新 project-overview.md（进度、已知问题等）"""

    def write_task_context(self, task_id, step, history) -> None:
        """每步执行前，LLM 基于当前步骤 + 历史生成 task-context.md"""

    def cleanup_task(self, task_id) -> None:
        """步骤完成后清理 task 目录"""
```

### 6. orchestrator.py 集成

```
run(goal):
  plan(goal)
  context_manager.init_project(goal, steps)    ← 新增
  execute_loop()
  summarize()

execute_loop() 每步:
  context_manager.write_task_context(task_id, step, history)  ← 新增：执行前
  send_task(...)
  wait_for_report(...)
  context_manager.update_project(report, remaining_steps)     ← 新增：执行后
  evaluate & apply decision
```

### 7. config.py 新增

```python
CONTEXT_DIR = CODING_AGENT_ROOT / "volumes" / "context"
```

## 改动文件清单

| 文件 | 操作 |
|------|------|
| `planAgent/config.py` | 新增 CONTEXT_DIR |
| `planAgent/core/context_manager.py` | 新建 |
| `planAgent/core/orchestrator.py` | 集成 ContextManager |
| `codingAgent/docker/context/combine_context.py` | 新增 --runtime-dir 逻辑 |
| `codingAgent/scripts/container/monitor.sh` | 调用时传 --runtime-dir |
| `codingAgent/docker/docker-compose.yml` | 新增 context volume |

## 不改动

- `docker/context/global/` — 模板不动
- `docker/context/project/` — 模板保留做参考
- `docker/context/task/` — 模板保留做参考
- `Dockerfile` — 模板 COPY 逻辑不变
