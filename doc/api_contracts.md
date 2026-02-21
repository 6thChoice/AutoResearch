# API 契约文档

## 文档信息

| 属性 | 值 |
|------|-----|
| 版本 | v1.0 |
| 日期 | 2026-02-20 |
| 状态 | 接口定义 |

---

## 1. 概述

本文档定义了科研智能体系统中各模块之间的 API 契约。所有接口均使用 Pydantic 模型定义，确保类型安全和数据验证。

### 1.1 设计原则

1. **接口优先**: 先定义接口，后实现功能
2. **类型安全**: 使用 Pydantic 进行严格类型检查
3. **版本控制**: 接口变更需要版本管理
4. **向后兼容**: 新版本尽量保持向后兼容

### 1.2 接口分类

| 分类 | 描述 | 模块 |
|------|------|------|
| OpenCode 接口 | 规划层与沙盒内 OpenCode 的通信 | `schemas/opencode_interface.py` |
| 消息类型 | 模块间通信的消息格式 | `schemas/message_types.py` |
| 状态模型 | 任务状态和上下文管理 | `schemas/state_models.py` |

---

## 2. OpenCode 接口

规划层 Agent 与沙盒内 OpenCode Agent 之间的通信接口。

### 2.1 核心数据流

```
┌─────────────────┐                    ┌─────────────────────┐
│  Planning Layer │                    │  OpenCode in Sandbox│
│     Agent       │                    │                     │
├─────────────────┤                    ├─────────────────────┤
│                 │  OpenCodeInvocation│                     │
│                 │ ─────────────────> │                     │
│                 │                    │  Execute Task       │
│                 │                    │  • Code Generation  │
│                 │                    │  • Bash Commands    │
│                 │                    │  • File Operations  │
│                 │                    │                     │
│                 │  ProgressReport    │                     │
│                 │ <───────────────── │  (via .progress/)   │
│                 │                    │                     │
│                 │  OpenCodeResult    │                     │
│                 │ <───────────────── │                     │
└─────────────────┘                    └─────────────────────┘
```

### 2.2 调用接口

#### invoke_opencode_agent

**用途**: 调用 OpenCode 执行任务

**输入**: `OpenCodeInvocation`

```python
{
    "sandbox_id": "sb_mnist_001",           # 必填: 目标沙盒ID
    "task_description": "复现 MNIST 项目...", # 必填: 任务描述
    "skills": ["progress-report"],          # 可选: 激活的 Skills
    "working_dir": "/workspace",            # 可选: 工作目录
    "timeout_seconds": 7200,                # 可选: 超时时间
    "mode": "async"                         # 可选: 执行模式
}
```

**输出**: `OpenCodeResult`

```python
{
    "task_id": "opencode_task_001",
    "sandbox_id": "sb_mnist_001",
    "status": "COMPLETED",
    "summary": "MNIST 模型复现完成",
    "artifacts": {
        "model_path": "/workspace/model.pt"
    },
    "metrics": {
        "accuracy": 0.968
    }
}
```

### 2.3 进度报告接口

#### read_progress_report

**用途**: 读取任务进度报告

**输入**: `ProgressReportToolInput`

```python
{
    "sandbox_id": "sb_mnist_001",
    "task_id": "opencode_task_001",
    "report_type": "all"  # 或具体类型
}
```

**输出**: `List[ProgressReport]`

#### ProgressReport 结构

```python
{
    "report_type": "MILESTONE_REPORT",
    "task_id": "opencode_task_001",
    "timestamp": "2026-02-20T10:30:00Z",
    "status": "RUNNING",
    "progress": "50/100 (50%)",
    "summary": "模型训练进行中...",
    "key_indicators": [
        {"name": "accuracy", "value": "97.5%", "target": "95%", "status": "achieved"}
    ],
    "problems_and_solutions": "学习率调整...",
    "next_steps": "运行测试集评估"
}
```

### 2.4 报告类型触发规则

| 报告类型 | 触发条件 | 优先级 |
|---------|---------|--------|
| `START_REPORT` | 任务开始时 | 最高 |
| `PERIODIC_REPORT` | 每 30 分钟 | 中 |
| `MILESTONE_REPORT` | 进度 25%/50%/75% | 高 |
| `COMPLETE_REPORT` | 任务完成时 | 最高 |
| `FAILED_REPORT` | 任务失败时 | 最高 |
| `ABORT_REPORT` | 任务中止时 | 最高 |
| `ERROR_LOOP_REPORT` | 检测到错误循环 | 最高 |

---

## 3. 消息类型

模块间通信使用的标准化消息格式。

### 3.1 消息头 (MessageHeader)

所有消息必须包含的标准头部:

```python
{
    "message_type": "REQ",          # REQ/DEL/ANALYSIS/MEET/DESIGN/SUMMARY
    "sender": "idea_normalization", # 发送方模块
    "receiver": "experiment_planning", # 接收方模块
    "timestamp": "2026-02-20T10:00:00Z",
    "session_id": "session_001",
    "parent_message_id": null,      # 父消息引用
    "priority": "high",             # urgent/high/medium/low
    "status": "pending"             # pending/in_progress/completed/rejected
}
```

### 3.2 核心消息类型

#### IdeaInput - Idea 输入

```python
{
    "raw_description": "复现 MNIST 项目，用 CNN 替代 MLP",
    "references": ["paper1.pdf", "paper2.pdf"],
    "code_repository": "https://github.com/xxx/xxx.git",
    "constraints": {
        "gpu": "1x A100",
        "time": "1 day"
    }
}
```

#### NormalizedIdea - 规范化 Idea

```python
{
    "title": "CNN-based MNIST Classification",
    "summary": "使用卷积神经网络替代多层感知机进行手写数字识别",
    "problem_statement": "MLP 在图像任务上准确率受限",
    "proposed_solution": "引入卷积层提取空间特征",
    "innovation_points": ["局部感受野", "权重共享"],
    "task_type": "image_classification",
    "dataset": "MNIST",
    "baselines": ["MLP"],
    "evaluation_metrics": ["accuracy"],
    "success_criteria": "准确率 > 98%"
}
```

#### TaskRequest - 任务请求

```python
{
    "task_id": "task_001",
    "session_id": "session_001",
    "task_type": "baseline_reproduction",  # 或 idea_implementation
    "description": "克隆仓库并复现 MNIST 项目",
    "sandbox_config": {
        "base_image": "python-ml",
        "dependencies": ["torch", "numpy"]
    },
    "skills_to_use": ["progress-report", "baseline-reproduction"],
    "timeout_seconds": 7200
}
```

#### StrategyResponse - 实现策略

```python
{
    "strategy_id": "strategy_001",
    "title": "CNN 改进策略",
    "description": "逐步替换 MLP 层为卷积层",
    "steps": [
        {
            "step_id": "step_1",
            "order": 1,
            "description": "添加卷积层",
            "estimated_time": "2h",
            "skills": ["idea-implementation"]
        }
    ],
    "risks": ["过拟合风险"],
    "fallback_options": ["增加 Dropout"]
}
```

---

## 4. 状态模型

任务生命周期和上下文管理的数据结构。

### 4.1 任务状态机

```
                    ┌──────────────┐
                    │   PENDING    │
                    └──────┬───────┘
                           │ start
                           ▼
                    ┌──────────────┐
           pause ┌──│   RUNNING    │──┐ complete
                 │  └──────┬───────┘  │
                 │         │          │
                 ▼         │ fail     ▼
          ┌──────────────┐ │  ┌──────────────┐
          │   PAUSED     │ │  │  COMPLETED   │
          └──────┬───────┘ │  └──────────────┘
                 │         │
                 │         ▼
                 │  ┌──────────────┐
                 └─►│   FAILED     │◄──┐ retry
                    └──────────────┘   │
                           │           │
                           │ cancel    │
                           ▼           │
                    ┌──────────────┐   │
                    │  CANCELLED   │───┘
                    └──────────────┘
```

### 4.2 TaskState 结构

```python
{
    "task_id": "task_001",
    "session_id": "session_001",
    "sandbox_id": "sb_001",
    "state": "running",
    "progress_percent": 50,
    "current_step": "训练模型",
    "total_steps": 4,
    "completed_steps": 2,
    "created_at": "2026-02-20T10:00:00Z",
    "started_at": "2026-02-20T10:05:00Z",
    "artifacts": {
        "model_path": "/workspace/model.pt"
    },
    "metrics": {
        "train_accuracy": 0.975
    }
}
```

### 4.3 TaskContext 结构

```python
{
    "task_id": "task_002",
    "session_id": "session_001",
    "previous_tasks": [
        {
            "task_id": "task_001",
            "task_type": "baseline_reproduction",
            "status": "completed",
            "summary": "MNIST MLP 复现完成",
            "key_metrics": {"accuracy": 0.968},
            "artifacts": [
                {"artifact_id": "baseline_model", "path": "/workspace/model.pt"}
            ]
        }
    ],
    "available_artifacts": {
        "baseline_model": {"path": "/workspace/model.pt"}
    },
    "normalized_idea": {...},
    "context_summary": "研究目标: CNN 改进..."
}
```

---

## 5. LangChain 工具接口

规划层 Agent 使用的 LangChain 工具定义。

### 5.1 工具列表

| 工具名称 | 用途 | 输入模型 |
|---------|------|---------|
| `invoke_opencode_agent` | 调用 OpenCode 执行任务 | `OpenCodeToolInput` |
| `read_progress_report` | 读取进度报告 | `ProgressReportToolInput` |
| `query_task_status` | 查询任务状态 | `TaskStatusToolInput` |
| `abort_opencode_task` | 中止任务 | `AbortTaskToolInput` |

### 5.2 工具输入示例

#### invoke_opencode_agent

```python
@tool
def invoke_opencode_agent(
    sandbox_id: Annotated[str, "Target sandbox identifier"],
    task_description: Annotated[str, "Task description in natural language"],
    skills: Annotated[Optional[str], "Comma-separated skill names"] = None,
    timeout_seconds: Annotated[int, "Timeout in seconds"] = 3600,
) -> str:
    """Invoke OpenCode agent to execute a task in the sandbox."""
    pass
```

---

## 6. 完整工作流示例

基于 e2e_test.md 的 MNIST 场景:

### 6.1 阶段一: Baseline 复现

```python
# 1. 创建沙盒
sandbox_create(
    idea_id="mnist_experiment",
    base_image="python-ml",
    dependencies="torch,numpy,matplotlib"
)

# 2. 调用 OpenCode 执行复现
invoke_opencode_agent(
    sandbox_id="mnist_experiment",
    task_description="""
    克隆仓库 https://github.com/6thChoice/Digit_recognition.git，
    复现 MNIST 手写数字识别项目，
    验证模型准确率达到预期
    """,
    skills="progress-report,baseline-reproduction",
    timeout_seconds=7200
)

# 3. 读取进度报告
read_progress_report(
    sandbox_id="mnist_experiment",
    task_id="task_xxx"
)
```

### 6.2 阶段二: Idea 实现

```python
# 1. 保存 Baseline 镜像
sandbox_save_as_image(
    idea_id="mnist_experiment",
    image_name="mnist_baseline"
)

# 2. 从镜像创建新沙盒
sandbox_load_from_image(
    image_name="mnist_baseline",
    new_idea_id="mnist_cnn"
)

# 3. 执行 Idea 实现
invoke_opencode_agent(
    sandbox_id="mnist_cnn",
    task_description="""
    将 MLP 替换为 CNN 架构，
    目标准确率 > 98%
    """,
    skills="progress-report,idea-implementation",
    timeout_seconds=7200
)
```

---

## 7. 错误处理

### 7.1 错误类型

| 错误类型 | 描述 | 处理方式 |
|---------|------|---------|
| `SandboxError` | 沙盒相关错误 | 重试或重建沙盒 |
| `OpenCodeError` | OpenCode 执行错误 | 分析原因，调整任务 |
| `TimeoutError` | 任务超时 | 延长超时或分解任务 |
| `ErrorLoopError` | 错误循环 | 中止任务，人工介入 |

### 7.2 错误循环检测

当检测到以下情况时触发错误循环告警:
- 10 分钟内出现 3 次以上相同错误
- 语义相似度 > 0.9 的错误重复出现
- 错误无法通过重试解决

---

## 8. 版本变更记录

| 版本 | 日期 | 变更内容 |
|------|------|---------|
| v1.0 | 2026-02-20 | 初始版本，定义核心接口 |
