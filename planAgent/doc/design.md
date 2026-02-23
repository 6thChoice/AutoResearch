为了与你现有的 Coding Agent 高效协同，**Plan Agent** 的架构应当设计为一个**基于状态机的异步循环系统**。

它不直接操作代码，而是操作“策略”和“任务流”。以下是 Plan Agent 的代码架构设计方案：

---

## 1. 代码架构：模块化设计

建议采用 Python 实现，核心分为 **Orchestrator (编排器)**、**Planner (规划器)** 和 **Observer (观察者)** 三大层。

### 1.1 核心组件类图

* **`ProjectOrchestrator`**: 主控中心。负责初始化项目、维护主循环、调用其他组件。
* **`MissionManager`**: 专门负责读写 `AGENT_MISSION.md` 和维护 `Roadmap` 状态。
* **`TaskPlanner`**: 调用大模型进行任务拆解，将高阶目标转化为符合 Coding Agent 规范的 Markdown 指令。
* **`ReportEvaluator`**: 负责解析 `reports/pending/` 下的报告，判断任务是 `SUCCESS`、`FAILED` 还是需要 `HUMAN_INTERVENTION`。
* **`StateStore`**: 维护当前会话的 `session_id`、任务队列和重试计数。

---

## 2. 关键工具 (Key Tools) 实现

Plan Agent 需要具备以下底层工具来支撑其决策：

### 2.1 任务拆解引擎 (Decomposition Engine)

* **功能**: 输入“项目愿景”和“当前进度”，输出“下一个具体的 Task 文件”。
* **实现细节**: 使用结构化输出（如 Pydantic）强迫 LLM 输出符合你接口规范的 YAML Frontmatter。

### 2.2 异步文件监听器 (Async File Watcher)

* **功能**: 监控 `volumes/reports/pending/` 文件夹。
* **工具**: 推荐使用 `watchdog` 库。
* **逻辑**: 一旦检测到新报告生成，触发 `ReportEvaluator` 流程。

### 2.3 任务依赖图 (Task Dependency Graph)

* **功能**: 维护任务之间的先后顺序。
* **逻辑**: 当一个任务失败时，自动挂起后续依赖该任务的所有子任务。

---

## 3. 代码运转逻辑 (Operational Flow)

Plan Agent 的生命周期是一个典型的 **REPL (Read-Eval-Print-Loop)** 变体：

### 第一阶段：项目初始化 (Initialization)

1. 用户输入目标（例如：“开发一个基于 Transformer 的 A 股因子回测系统”）。
2. Plan Agent 生成初始 `AGENT_MISSION.md`，写入 `workspace`。
3. 初始化 `Roadmap`，将其中的第一项转化为 `task-001.md` 放入 `commands/pending/`。

### 第二阶段：执行监控 (Monitoring Loop)

```python
while not project_completed:
    # 1. 检查是否有新的执行报告
    report = observer.wait_for_report(timeout=600) 
    
    if report:
        # 2. 评估结果
        analysis = evaluator.analyze(report)
        
        # 3. 更新记忆中枢
        mission_manager.sync(analysis) # 将填坑记录、ADR 同步到 AGENT_MISSION.md
        
        if analysis.status == "SUCCESS":
            # 4. 推进计划
            next_step = planner.get_next_task()
            if next_step:
                commander.send(next_step)
            else:
                project_completed = True
        else:
            # 5. 容错逻辑
            handle_failure(analysis)

```

### 第三阶段：容错与重规划 (Self-Correction)

* **重试策略**: 如果是偶发性报错（如网络超时），Plan Agent 下发 `command_type: continue`。
* **降级策略**: 如果逻辑报错，Plan Agent 修改下一次任务的指令，增加“增加日志打印”或“编写测试用例”的约束条件，强制 Coding Agent 缩小排查范围。

---

## 4. 核心文件结构建议

```bash
plan-agent/
├── core/
│   ├── orchestrator.py    # 主循环逻辑
│   ├── planner.py         # LLM 任务拆解
│   ├── evaluator.py       # 报告解析与评分
│   └── mission.py         # AGENT_MISSION.md 读写器
├── tools/
│   ├── file_watcher.py    # 监控 reports 目录
│   └── llm_client.py      # 封装不同模型的调用 (Claude/Qwen)
├── prompts/
│   ├── planner_v1.txt     # 任务拆解的 System Prompt
│   └── evaluator_v1.txt   # 报告分析的 System Prompt
└── main.py                # 程序入口

```

---

## 5. 针对你项目的特别建议

1. **ADR 驱动决策**: 你的规范中提到了 ADR。Plan Agent 应该在发现 Coding Agent 提交了 `architecture.md` 的变动时，自动更新其内部的“技术选型”认知。
2. **GPU 资源感知**: 既然你支持 CUDA，Plan Agent 在拆解任务时，应判断任务是否涉及模型训练。如果是，在 `task-xxx.md` 的约束条件中显式加入 `Ensure GPU utilization is monitored`。
3. **Human-in-the-loop**: 当 Plan Agent 连续 3 次无法解决某个 Bug 时，应在宿主机终端抛出提醒，请求人工接入。
