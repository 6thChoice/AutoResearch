# 科研智能体系统开发路线设计

## 文档信息

| 属性 | 值 |
|------|-----|
| 版本 | v1.0 |
| 日期 | 2026-02-20 |
| 状态 | 规划文档 |
| 关联文档 | main-design-v4.md, implementation-challenges.md |

---

## 一、开发总览

### 1.1 当前状态分析

| 模块 | 设计状态 | 实现状态 |
|------|---------|---------|
| Sandbox 核心层 | ✅ 完整 | ✅ 已实现 |
| OpenCode 沙盒集成 | ✅ 设计 | ❌ 未实现 |
| Skills 机制 | ✅ 设计 | ❌ 未实现 |
| 规划层 Agent | ✅ 设计 | ❌ 未实现 |
| Idea 规范化模块 | ✅ 设计 | ❌ 未实现 |
| 实验计划模块 | ✅ 设计 | ❌ 未实现 |
| 结果分析模块 | ✅ 设计 | ❌ 未实现 |
| 状态同步机制 | ✅ 设计 | ❌ 未实现 |

### 1.2 系统架构回顾

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           科研智能体系统 v4.0                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                      第一层：交互层 (Interaction)                     │   │
│  │  ┌──────────────────────┐      ┌──────────────────────┐            │   │
│  │  │   Idea 规范化模块    │      │    实验计划模块      │            │   │
│  │  │  (LangChain Agent)   │      │  (LangChain Agent)   │            │   │
│  │  └──────────────────────┘      └──────────────────────┘            │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                ▼                              ▼                            │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                      第二层：执行层 (Execution)                       │   │
│  │  ┌───────────────────────────────────────────────────────────────┐ │   │
│  │  │              规划层 Agent (LangChain Agent)                    │ │   │
│  │  │  • 任务规划与分解    • 状态管理    • 长程规划                  │ │   │
│  │  │  • 工具函数: invoke_opencode_agent, read_progress_report      │ │   │
│  │  └───────────────────────────────────────────────────────────────┘ │   │
│  │                              │                                      │   │
│  │                              ▼                                      │   │
│  │  ┌───────────────────────────────────────────────────────────────┐ │   │
│  │  │            沙盒容器层 (Sandbox Container)                       │ │   │
│  │  │  ┌─────────────────────────────────────────────────────────┐  │ │   │
│  │  │  │            OpenCode Agent (Coding Agent)                 │  │ │   │
│  │  │  │  • Skills Engine (SKILL.md)                             │  │ │   │
│  │  │  │  • Tool Chain (Bash/Read/Write)                         │  │ │   │
│  │  │  │  • Progress Report Generator                            │  │ │   │
│  │  │  └─────────────────────────────────────────────────────────┘  │ │   │
│  │  └───────────────────────────────────────────────────────────────┘ │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                ▼                                                            │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                      第三层：分析层 (Analysis)                        │   │
│  │                 实验结果分析模块 (LangChain Agent)                   │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 二、开发原则（避免返工的核心）

### 2.1 分层渐进原则

```
基础设施层 → 能力层 → 协调层 → 应用层
```

**每个层次完成后再进入下一层**，避免上层依赖不稳定导致大规模返工。

**依赖关系图**:

```
应用层 (Idea规范化, 实验计划, 结果分析)
         ↑
协调层 (规划层Agent, 状态同步, 检查点)
         ↑
能力层 (Skills, 错误检测, 进度报告)
         ↑
基础设施层 (OpenCode集成, Sandbox核心)
```

### 2.2 接口契约优先原则

在实现任何模块前，先定义：

1. **输入/输出接口**：使用 Pydantic 模型
2. **通信协议**：消息格式、调用方式
3. **验收标准**：测试用例

```python
# 示例：先定义接口
from pydantic import BaseModel
from typing import Callable, List

class OpenCodeToolInterface(BaseModel):
    """OpenCode 工具接口契约"""
    invoke_opencode_agent: Callable[[str, List[str]], str]
    read_progress_report: Callable[[str, str], "ProgressReport"]
    query_task_status: Callable[[str, str], "TaskStatus"]

    class Config:
        arbitrary_types_allowed = True
```

### 2.3 最小可用版本 (MVP) 原则

每个模块先实现**最小可用版本**：

- 核心路径打通
- 异常处理简化
- 日志记录完善

**然后再迭代增强**，避免过度设计。

### 2.4 集成测试先行

在完成基础设施后，先写一个**端到端的集成测试场景**，作为后续开发的验收标准。

```python
# tests/integration/test_e2e_workflow.py
async def test_complete_research_workflow():
    """完整的科研工作流测试"""
    # 1. 用户提交 Idea
    # 2. Idea 规范化
    # 3. 实验计划生成
    # 4. Baseline 复现
    # 5. Idea 实现
    # 6. 结果分析
    pass
```

---

## 三、模块开发顺序（由底层到上层）

```
阶段 0: 环境准备与验收标准定义
    ↓
阶段 1: 基础设施层 (Infrastructure)
    ├── OpenCode 沙盒集成
    ├── Skills 引擎基础
    └── 进度报告机制
    ↓
阶段 2: 能力层 (Capability)
    ├── progress-report Skill
    ├── baseline-reproduction Skill
    ├── idea-implementation Skill
    └── 错误循环检测器
    ↓
阶段 3: 协调层 (Coordination)
    ├── 规划层 Agent
    ├── 任务状态机
    ├── 状态同步机制
    └── 检查点恢复
    ↓
阶段 4: 应用层 (Application)
    ├── Idea 规范化模块
    ├── 实验计划模块
    └── 结果分析模块
    ↓
阶段 5: 集成与优化
```

---

## 四、各阶段详细开发流程

### 阶段 0: 环境准备与验收标准定义 (1 天)

**目标**: 确立开发标准和验收基准

**输出物**:

```
research/
├── tests/
│   └── integration/
│       └── test_e2e_workflow.py    # 端到端测试场景
├── schemas/
│   ├── opencode_interface.py       # OpenCode 接口定义
│   ├── message_types.py            # 消息类型定义
│   └── state_models.py             # 状态模型定义
└── docs/
    └── api_contracts.md            # API 契约文档
```

**任务清单**:

- [ ] 定义端到端测试场景
- [ ] 定义核心接口 (Pydantic 模型)
- [ ] 编写 API 契约文档
- [ ] 评审接口定义

**验收标准**:

- [ ] 端到端测试场景定义完成
- [ ] 核心接口定义完成
- [ ] API 契约文档评审通过

---

### 阶段 1: 基础设施层 (5-7 天)

#### 1.1 OpenCode 沙盒集成 (3-4 天)

**目标**: 将 OpenCode 部署到沙盒容器内，实现与规划层的通信

**模块内部开发流程**:

```
步骤 1: 创建 OpenCode Docker 镜像 (0.5 天)
├── 编写 Dockerfile.opencode
├── 配置 Bun Runtime
├── 安装 OpenCode CLI
└── 验证: 手动启动容器，执行 opencode 命令

步骤 2: 实现通信桥 (1 天)
├── OpenCodeSandboxBridge 类
├── HTTP API 调用方式
├── 文件系统读取方式
└── 验证: 单元测试 + 手动测试

步骤 3: 扩展 SandboxManager (1 天)
├── create_opencode_sandbox() 方法
├── OpenCode 特有配置支持
└── 验证: 创建带 OpenCode 的沙盒

步骤 4: 实现工具函数 (0.5-1 天)
├── invoke_opencode_agent
├── read_progress_report
├── query_task_status
├── abort_opencode_task
└── 验证: LangChain 工具测试
```

**输出物**:

```
research/
├── sandbox/
│   ├── Dockerfile.opencode          # OpenCode 镜像定义
│   ├── opencode_manager.py          # OpenCode 管理器
│   └── opencode_bridge.py           # 通信桥
├── tools/
│   └── opencode_tools.py            # LangChain 工具
└── tests/
    └── test_opencode_integration.py
```

**关键实现要点**:

```dockerfile
# sandbox/Dockerfile.opencode
FROM node:24-slim

# 安装系统依赖
RUN apt-get update && apt-get install -y \
    git \
    curl \
    && rm -rf /var/lib/apt/lists/*

# 安装 Bun
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:$PATH"

# 安装 OpenCode
RUN bun install -g opencode

# 配置工作目录
WORKDIR /workspace

# 创建必要目录
RUN mkdir -p /workspace/.progress /workspace/.context

# 暴露 API 端口
EXPOSE 8080

# 启动 OpenCode 服务
CMD ["opencode", "serve", "--port", "8080"]
```

```python
# sandbox/opencode_bridge.py
class OpenCodeSandboxBridge:
    """OpenCode 沙盒通信桥"""

    def __init__(self, sandbox_id: str, api_endpoint: str):
        self.sandbox_id = sandbox_id
        self.api_endpoint = api_endpoint
        self.progress_dir = "/workspace/.progress"

    # 方式1: HTTP API（实时通信）
    async def invoke_via_api(self, task: str, skills: List[str]) -> str:
        """通过 HTTP API 调用 OpenCode"""
        async with aiohttp.ClientSession() as session:
            async with session.post(
                f"{self.api_endpoint}/invoke",
                json={"task": task, "skills": skills}
            ) as response:
                data = await response.json()
                return data["task_id"]

    # 方式2: 文件系统（进度报告）
    def read_progress_via_file(self, task_id: str) -> List["ProgressReport"]:
        """通过文件系统读取进度报告"""
        report_dir = f"{self.progress_dir}/{task_id}"
        return self._load_reports(report_dir)
```

**注意事项**:

1. **网络配置**: 容器内需要访问外部 LLM API，确保代理配置正确传递
2. **资源隔离**: OpenCode 可能消耗大量资源，需要合理设置 CPU/内存限制
3. **日志收集**: 容器内日志需要能被宿主机访问
4. **安全性**: API 端点需要适当的访问控制

**验收标准**:

- [ ] OpenCode 容器能够正常启动和运行
- [ ] 能够通过 HTTP API 调用 OpenCode
- [ ] 能够读取进度报告文件
- [ ] LangChain 工具能够正常调用

---

#### 1.2 Skills 引擎基础 (1 天)

**目标**: 实现 Skills 的加载、注入和验证机制

**模块内部开发流程**:

```
步骤 1: 定义 Skill 基类 (0.25 天)
├── Skill 基类结构
├── 触发条件接口
├── 输出格式定义
└── 验证: 基类单元测试

步骤 2: 实现 Skill 加载器 (0.25 天)
├── 从目录加载 Skills
├── Skill 优先级排序
└── 验证: 加载测试 Skills

步骤 3: 实现 Skill 注入器 (0.5 天)
├── 注入到 System Prompt
├── 后置验证机制
└── 验证: 端到端注入测试
```

**输出物**:

```
research/
├── skills/
│   ├── __init__.py
│   ├── base.py                      # Skill 基类
│   ├── engine.py                    # Skills 引擎
│   ├── loader.py                    # Skill 加载器
│   └── validator.py                 # 输出验证器
└── .opencode/
    └── skill/
        └── _template/
            └── SKILL.md             # Skill 模板
```

**关键实现要点**:

```python
# skills/base.py
from abc import ABC, abstractmethod
from pydantic import BaseModel
from typing import List, Dict, Any
from enum import Enum

class TriggerType(Enum):
    """触发类型"""
    TASK_START = "task_start"
    TASK_COMPLETE = "task_complete"
    PERIODIC = "periodic"
    MILESTONE = "milestone"
    ERROR = "error"
    ERROR_LOOP = "error_loop"

class TriggerCondition(BaseModel):
    """触发条件"""
    trigger_type: TriggerType
    interval_seconds: int = None  # 用于 PERIODIC
    milestone_percentages: List[int] = None  # 用于 MILESTONE
    error_threshold: int = None  # 用于 ERROR_LOOP

class Skill(ABC):
    """Skill 基类"""

    name: str
    description: str
    priority: int = 0
    triggers: List[TriggerCondition]

    @abstractmethod
    def get_prompt(self) -> str:
        """获取注入到 System Prompt 的内容"""
        pass

    @abstractmethod
    def validate_output(self, output: str) -> bool:
        """验证输出是否符合要求"""
        pass
```

```python
# skills/engine.py
class SkillEngine:
    """Skills 引擎"""

    def __init__(self, skill_dir: str):
        self.skill_dir = skill_dir
        self.skills: List[Skill] = []
        self.validator = SkillOutputValidator()

    def load_skills(self, skill_names: List[str]) -> None:
        """加载指定的 Skills"""
        for name in skill_names:
            skill = self._load_skill(name)
            if skill:
                self.skills.append(skill)
        # 按优先级排序
        self.skills.sort(key=lambda s: s.priority, reverse=True)

    def inject_to_prompt(self, base_prompt: str) -> str:
        """将 Skills 注入到 System Prompt"""
        skill_prompts = []
        for skill in self.skills:
            skill_prompts.append(skill.get_prompt())

        injection = "\n\n---\n\n".join(skill_prompts)
        return f"{base_prompt}\n\n{injection}"

    def validate_output(self, output: str, context: dict) -> "ValidationResult":
        """验证输出是否符合 Skill 要求"""
        for skill in self.skills:
            result = self.validator.validate(output, skill)
            if not result.valid:
                return result
        return ValidationResult(valid=True)
```

**验收标准**:

- [ ] Skill 基类定义完成
- [ ] 能够从目录加载 Skills
- [ ] 能够将 Skills 注入到 Prompt
- [ ] 能够验证输出格式

---

#### 1.3 进度报告机制 (1 天)

**目标**: 实现进度报告的生成、存储和读取

**模块内部开发流程**:

```
步骤 1: 定义报告格式 (0.25 天)
├── ProgressReport 模型
├── 报告类型枚举
└── 验证: Pydantic 验证

步骤 2: 实现报告生成器 (0.25 天)
├── 模板渲染
├── 字段填充
└── 验证: 生成测试报告

步骤 3: 实现报告读取器 (0.25 天)
├── 文件系统读取
├── 解析和验证
└── 验证: 读取测试

步骤 4: 实现触发检测 (0.25 天)
├── 定时触发
├── 里程碑触发
├── 错误触发
└── 验证: 触发条件测试
```

**输出物**:

```
research/
├── progress/
│   ├── __init__.py
│   ├── models.py                    # 报告模型
│   ├── generator.py                 # 报告生成器
│   ├── reader.py                    # 报告读取器
│   └── triggers.py                  # 触发检测
└── templates/
    └── progress_report.md           # 报告模板
```

**关键实现要点**:

```python
# progress/models.py
from pydantic import BaseModel
from datetime import datetime
from typing import List, Dict, Optional
from enum import Enum

class ReportType(Enum):
    """报告类型"""
    START = "START_REPORT"
    PERIODIC = "PERIODIC_REPORT"
    MILESTONE = "MILESTONE_REPORT"
    COMPLETE = "COMPLETE_REPORT"
    FAILED = "FAILED_REPORT"
    ABORT = "ABORT_REPORT"
    ERROR_LOOP = "ERROR_LOOP_REPORT"

class TaskStatus(Enum):
    """任务状态"""
    RUNNING = "RUNNING"
    COMPLETED = "COMPLETED"
    FAILED = "FAILED"
    ABORTED = "ABORTED"
    ERROR_LOOP = "ERROR_LOOP"

class KeyIndicator(BaseModel):
    """关键指标"""
    name: str
    value: str
    target: Optional[str] = None
    status: str = "pending"  # pending, achieved, failed

class ProgressReport(BaseModel):
    """进度报告"""
    report_type: ReportType
    task_id: str
    timestamp: datetime
    status: TaskStatus
    progress: str  # "30/100 (30%)"

    summary: str  # 200字以内的摘要
    key_indicators: List[KeyIndicator] = []
    problems_and_solutions: str = ""
    next_steps: str = ""

    agent_signature: str = "OpenCode-Agent"
```

**验收标准**:

- [ ] 报告模型定义完成
- [ ] 报告生成器能够生成符合格式的报告
- [ ] 报告读取器能够解析报告文件
- [ ] 触发检测能够正确识别触发条件

---

### 阶段 2: 能力层 (4-5 天)

#### 2.1 progress-report Skill (1 天)

**目标**: 实现核心的进度报告 Skill

**开发流程**:

```
步骤 1: 编写 SKILL.md (0.25 天)
├── 触发规则定义
├── 输出模板
├── 示例
└── 验证: 文档评审

步骤 2: 实现触发检测逻辑 (0.5 天)
├── 时间检测
├── 进度估算
├── 事件检测
└── 验证: 触发单元测试

步骤 3: 集成测试 (0.25 天)
├── 完整流程测试
└── 验证: 端到端测试
```

**输出物**:

```
research/.opencode/skill/progress-report/
├── SKILL.md                         # Skill 定义
└── templates/
    └── report_template.md           # 报告模板
```

**Skill 定义示例**:

```markdown
# progress-report Skill

## 概述

此 Skill 强制 OpenCode 在关键节点生成进度报告，确保规划层能够了解执行状态。

## 触发规则

| 触发条件 | 报告类型 | 优先级 |
|---------|---------|--------|
| 任务开始 | START_REPORT | 最高 |
| 每 30 分钟 | PERIODIC_REPORT | 中 |
| 进度 25%/50%/75% | MILESTONE_REPORT | 高 |
| 任务完成 | COMPLETE_REPORT | 最高 |
| 任务失败 | FAILED_REPORT | 最高 |
| 任务中止 | ABORT_REPORT | 最高 |
| 错误循环 | ERROR_LOOP_REPORT | 最高 |

## 输出格式

所有报告必须使用以下 Markdown 格式，并保存到 `/workspace/.progress/{task_id}/` 目录：

```markdown
# 进度报告

**文档类型**: PROGRESS
**任务ID**: {task_id}
**生成时间**: {timestamp}
**状态**: RUNNING|COMPLETED|FAILED|ABORTED|ERROR_LOOP
**进度**: {current}/{total} ({percentage}%)

---

## 执行摘要
{200字以内的摘要}

## 关键指标
| 指标名 | 值 | 目标 | 状态 |
|--------|-----|------|------|
| ... | ... | ... | ... |

## 问题与解决方案
{遇到的问题和采取的解决方案}

## 下一步
{下一步计划}

---
**Agent签名**: OpenCode-Agent-{version}
```

## 存储位置

所有报告存储在 `/workspace/.progress/` 目录，按任务 ID 组织。
```

**验收标准**:

- [ ] SKILL.md 文档完成
- [ ] 所有触发条件正确检测
- [ ] 生成的报告格式正确
- [ ] 报告保存到正确位置

---

#### 2.2 其他 Skills (2 天)

##### 2.2.1 baseline-reproduction Skill (1 天)

**目标**: 约束 Baseline 复现行为

**关键行为**:

- 严格按照文献配置复现
- 验证复现结果是否达标
- 生成复现报告

**输出物**:

```
research/.opencode/skill/baseline-reproduction/
├── SKILL.md
└── templates/
    └── reproduction_report.md
```

##### 2.2.2 idea-implementation Skill (0.5 天)

**目标**: 约束 Idea 实现行为

**关键行为**:

- 按照实现策略编写代码
- 确保代码质量
- 生成实现文档

##### 2.2.3 error-recovery Skill (0.5 天)

**目标**: 约束错误恢复行为

**关键行为**:

- 分析错误原因
- 尝试多种解决方案
- 记录恢复过程

---

#### 2.3 错误循环检测器 (1 天)

**目标**: 检测 OpenCode 是否陷入错误循环

**开发流程**:

```
步骤 1: 实现基础检测 (0.25 天)
├── 精确匹配检测
├── 错误历史管理
└── 验证: 基础测试

步骤 2: 实现语义相似度检测 (0.5 天)
├── Embedding 计算
├── 相似度比较
└── 验证: 语义测试

步骤 3: 综合判断与告警 (0.25 天)
├── 多维度分析
├── 告警生成
└── 验证: 集成测试
```

**输出物**:

```
research/
├── monitoring/
│   ├── __init__.py
│   ├── error_detector.py            # 错误检测器
│   └── error_history.py             # 错误历史管理
└── tests/
    └── test_error_detection.py
```

**关键实现要点**:

```python
# monitoring/error_detector.py
class EnhancedErrorLoopDetector:
    """增强的错误循环检测器"""

    ERROR_WINDOW = 600  # 10分钟窗口
    MAX_CONSECUTIVE = 3  # 连续相同错误阈值
    MAX_IN_WINDOW = 5    # 窗口内错误阈值

    def __init__(self):
        self.error_history: List[ErrorRecord] = []
        self.embedding_cache: Dict[str, np.ndarray] = {}

    def analyze_error(self, error: Exception, context: Dict) -> ErrorAnalysis:
        """分析错误"""
        error_record = ErrorRecord(
            timestamp=time.time(),
            error_type=type(error).__name__,
            error_message=str(error),
            stack_trace=traceback.format_exc(),
            context=context
        )

        # 1. 清理过期记录
        self._cleanup_old_records()

        # 2. 精确匹配检测
        exact_match = self._check_exact_match(error_record)

        # 3. 语义相似度检测
        semantic_match = self._check_semantic_similarity(error_record)

        # 4. 错误类型聚合
        type_aggregation = self._check_type_aggregation()

        # 5. 综合判断
        is_loop = (
            exact_match.count >= self.MAX_CONSECUTIVE or
            semantic_match.max_similarity > 0.9 or
            type_aggregation.count >= self.MAX_IN_WINDOW
        )

        self.error_history.append(error_record)

        return ErrorAnalysis(
            is_error_loop=is_loop,
            exact_match_count=exact_match.count,
            semantic_similarity=semantic_match.max_similarity,
            recommendation=self._generate_recommendation(is_loop, error_record)
        )
```

**验收标准**:

- [ ] 能够检测精确相同的错误
- [ ] 能够检测语义相似的错误
- [ ] 能够生成错误循环告警
- [ ] 误报率 < 5%

---

### 阶段 3: 协调层 (5-6 天)

#### 3.1 规划层 Agent (2-3 天)

**目标**: 实现任务规划和分解的核心 Agent

**开发流程**:

```
步骤 1: 定义 Agent 结构 (0.5 天)
├── LangChain Agent 配置
├── 工具函数注册
├── Prompt 模板
└── 验证: Agent 创建测试

步骤 2: 实现任务分解 (1 天)
├── 任务解析
├── 步骤规划
├── 依赖管理
└── 验证: 分解测试

步骤 3: 实现状态管理 (0.5 天)
├── 上下文管理
├── 状态持久化
└── 验证: 状态测试

步骤 4: 集成测试 (0.5-1 天)
├── 完整工作流测试
└── 验证: 端到端测试
```

**输出物**:

```
research/
├── agents/
│   ├── __init__.py
│   ├── planning_agent.py            # 规划层 Agent
│   ├── task_decomposer.py           # 任务分解器
│   └── context_manager.py           # 上下文管理器
└── prompts/
    └── planning_agent_prompt.py     # Prompt 模板
```

**关键实现要点**:

```python
# agents/planning_agent.py
from langchain.agents import AgentExecutor, create_react_agent
from langchain_core.language_models import BaseLanguageModel

class PlanningAgent:
    """规划层 Agent"""

    def __init__(self, llm: BaseLanguageModel, tools: List):
        self.llm = llm
        self.tools = tools  # 包含 OpenCode 工具
        self.context = AgentContext()
        self.task_queue = TaskQueue()
        self.agent_executor = self._create_agent()

    def _create_agent(self) -> AgentExecutor:
        """创建 LangChain Agent"""
        prompt = self._build_prompt()
        agent = create_react_agent(self.llm, self.tools, prompt)
        return AgentExecutor(agent=agent, tools=self.tools)

    async def execute_strategy(self, strategy: "Strategy") -> "ExecutionResult":
        """执行实现策略"""
        # 1. 分解任务
        tasks = self._decompose_strategy(strategy)

        # 2. 排序任务（考虑依赖）
        ordered_tasks = self._order_tasks(tasks)

        # 3. 依次执行
        for task in ordered_tasks:
            # 调用 OpenCode
            task_id = await self._invoke_opencode(task)

            # 等待并读取进度报告
            report = await self._wait_for_completion(task_id)

            # 处理结果
            if report.status == "FAILED":
                await self._handle_failure(task, report)
            else:
                self.context.update(task, report)

        return ExecutionResult(
            status="completed",
            summary=self._generate_summary()
        )

    async def _invoke_opencode(self, task: "Task") -> str:
        """调用 OpenCode 执行任务"""
        invoke_tool = next(t for t in self.tools if t.name == "invoke_opencode_agent")
        result = await invoke_tool.ainvoke({
            "sandbox_id": self.sandbox_id,
            "task_description": task.description,
            "skills": task.required_skills
        })
        return result["task_id"]
```

**验收标准**:

- [ ] Agent 能够正确创建和配置
- [ ] 任务分解逻辑正确
- [ ] 能够调用 OpenCode 工具
- [ ] 状态管理正常工作

---

#### 3.2 任务状态机 (1 天)

**目标**: 管理任务的生命周期状态

**输出物**:

```
research/
├── state/
│   ├── __init__.py
│   ├── task_state.py                # 任务状态定义
│   ├── state_machine.py             # 状态机实现
│   └── transitions.py               # 状态转换规则
```

**关键实现要点**:

```python
# state/task_state.py
from enum import Enum

class TaskState(Enum):
    """任务状态"""
    PENDING = "pending"           # 等待执行
    RUNNING = "running"           # 执行中
    PAUSED = "paused"             # 已暂停
    COMPLETED = "completed"       # 已完成
    FAILED = "failed"             # 已失败
    CANCELLED = "cancelled"       # 已取消

# state/state_machine.py
class TaskStateMachine:
    """任务状态机"""

    # 允许的状态转换
    TRANSITIONS = {
        TaskState.PENDING: [TaskState.RUNNING, TaskState.CANCELLED],
        TaskState.RUNNING: [TaskState.COMPLETED, TaskState.FAILED,
                           TaskState.PAUSED, TaskState.CANCELLED],
        TaskState.PAUSED: [TaskState.RUNNING, TaskState.CANCELLED],
        TaskState.COMPLETED: [],  # 终态
        TaskState.FAILED: [TaskState.PENDING],  # 可重试
        TaskState.CANCELLED: [],  # 终态
    }

    def __init__(self, task_id: str):
        self.task_id = task_id
        self.state = TaskState.PENDING
        self.history: List[Tuple[TaskState, datetime, Optional[str]]] = []

    def transition(self, new_state: TaskState, reason: str = None) -> bool:
        """状态转换"""
        if new_state not in self.TRANSITIONS[self.state]:
            return False

        old_state = self.state
        self.state = new_state
        self.history.append((old_state, datetime.now(), reason))
        return True
```

---

#### 3.3 状态同步机制 (1 天)

**目标**: 实现规划层与 OpenCode 之间的状态同步

**输出物**:

```
research/
├── sync/
│   ├── __init__.py
│   ├── event_bus.py                 # 事件总线
│   ├── state_cache.py               # 状态缓存
│   └── sync_manager.py              # 同步管理器
```

**关键实现要点**:

```python
# sync/event_bus.py
from dataclasses import dataclass
from typing import Callable, Dict, List
from enum import Enum

class EventType(Enum):
    TASK_STARTED = "task_started"
    TASK_PROGRESS = "task_progress"
    TASK_COMPLETED = "task_completed"
    TASK_FAILED = "task_failed"
    REPORT_GENERATED = "report_generated"
    ERROR_DETECTED = "error_detected"
    ERROR_LOOP_DETECTED = "error_loop_detected"

@dataclass
class TaskEvent:
    """任务事件"""
    event_id: str
    event_type: EventType
    task_id: str
    sandbox_id: str
    timestamp: datetime
    payload: dict

class EventBus:
    """事件总线"""

    def __init__(self):
        self.subscribers: Dict[EventType, List[Callable]] = {}

    def subscribe(self, event_type: EventType, handler: Callable):
        """订阅事件"""
        if event_type not in self.subscribers:
            self.subscribers[event_type] = []
        self.subscribers[event_type].append(handler)

    async def publish(self, event: TaskEvent):
        """发布事件"""
        handlers = self.subscribers.get(event.event_type, [])
        for handler in handlers:
            await handler(event)
```

---

#### 3.4 检查点恢复 (1 天)

**目标**: 扩展现有检查点机制以支持 Agent 状态恢复

**输出物**:

```
research/
├── checkpoint/
│   ├── __init__.py
│   ├── agent_checkpoint.py          # Agent 检查点
│   └── recovery_manager.py          # 恢复管理器
```

---

### 阶段 4: 应用层 (6-8 天)

#### 4.1 Idea 规范化模块 (2-3 天)

**目标**: 实现用户 Idea 的解析、规范化和策略生成

**开发流程**:

```
步骤 1: 定义模块接口 (0.5 天)
├── 输入/输出模型
├── 与用户交互协议
└── 验证: 接口定义

步骤 2: 实现 Idea 解析 (1 天)
├── 文献分析
├── 代码仓库分析
├── 策略生成
└── 验证: 解析测试

步骤 3: 实现用户交互 (0.5 天)
├── 澄清问题生成
├── 确认流程
└── 验证: 交互测试

步骤 4: 集成测试 (0.5-1 天)
```

**输出物**:

```
research/
├── modules/
│   └── idea_normalization/
│       ├── __init__.py
│       ├── agent.py                 # Idea 规范化 Agent
│       ├── parser.py                # Idea 解析器
│       ├── strategy_generator.py    # 策略生成器
│       └── interaction.py           # 用户交互
```

**验收标准**:

- [ ] 能够解析用户输入的 Idea
- [ ] 能够生成实现策略
- [ ] 能够与用户进行澄清交互
- [ ] 输出格式符合规范

---

#### 4.2 实验计划模块 (2 天)

**目标**: 实现实验计划的设计和生成

**开发流程**:

```
步骤 1: 定义模块接口 (0.5 天)
步骤 2: 实现 Baseline 识别 (0.5 天)
步骤 3: 实现实验设计 (0.5 天)
步骤 4: 实现评估指标体系 (0.5 天)
```

**输出物**:

```
research/
├── modules/
│   └── experiment_planning/
│       ├── __init__.py
│       ├── agent.py                 # 实验计划 Agent
│       ├── baseline_identifier.py   # Baseline 识别
│       ├── experiment_designer.py   # 实验设计
│       └── metrics.py               # 评估指标
```

---

#### 4.3 结果分析模块 (2-3 天)

**目标**: 实现实验结果的分析和价值判断

**开发流程**:

```
步骤 1: 定义模块接口 (0.5 天)
步骤 2: 实现指标分析 (1 天)
├── 关键指标计算
├── 对比分析
└── 显著性检验
步骤 3: 实现价值判断 (0.5 天)
步骤 4: 实现优化方案生成 (0.5 天)
步骤 5: 集成测试 (0.5 天)
```

**输出物**:

```
research/
├── modules/
│   └── result_analysis/
│       ├── __init__.py
│       ├── agent.py                 # 结果分析 Agent
│       ├── metrics_analyzer.py      # 指标分析
│       ├── value_assessment.py      # 价值判断
│       └── report_generator.py      # 报告生成
```

---

### 阶段 5: 集成与优化 (3-5 天)

#### 5.1 端到端集成测试 (2 天)

**目标**: 运行完整的系统测试

**任务清单**:

- [ ] 运行阶段 0 定义的测试场景
- [ ] 修复发现的问题
- [ ] 补充缺失的测试用例

#### 5.2 性能优化 (1-2 天)

**目标**: 优化系统性能

**任务清单**:

- [ ] 上下文压缩优化
- [ ] 并行执行优化
- [ ] 资源管理优化
- [ ] 响应时间优化

#### 5.3 文档完善 (1 天)

**目标**: 完善系统文档

**任务清单**:

- [ ] API 文档
- [ ] 部署指南
- [ ] 使用示例
- [ ] 故障排除指南

---

## 五、模块内部开发通用流程模板

每个模块开发时应遵循以下流程：

```
┌─────────────────────────────────────────────────────────┐
│                    模块开发流程                          │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  1. 接口设计 (TDD 红灯阶段)                             │
│     ├── 定义输入/输出 Pydantic 模型                     │
│     ├── 编写接口测试用例                                │
│     └── 验收: 测试失败 (红灯)                           │
│                                                         │
│  2. 核心实现 (TDD 绿灯阶段)                             │
│     ├── 实现核心逻辑                                    │
│     ├── 通过所有测试用例                                │
│     └── 验收: 测试通过 (绿灯)                           │
│                                                         │
│  3. 异常处理                                            │
│     ├── 添加错误处理逻辑                                │
│     ├── 编写异常测试用例                                │
│     └── 验收: 异常场景覆盖                              │
│                                                         │
│  4. 集成验证                                            │
│     ├── 与依赖模块集成                                  │
│     ├── 编写集成测试                                    │
│     └── 验收: 集成测试通过                              │
│                                                         │
│  5. 日志与监控                                          │
│     ├── 添加结构化日志                                  │
│     ├── 添加关键指标                                    │
│     └── 验收: 日志可观测                                │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

---

## 六、避免返工的关键策略

### 6.1 契约驱动开发

```
设计文档 → 接口契约 → 测试用例 → 实现
```

**每一步都要评审**，确保方向正确。

### 6.2 增量集成

不要等到所有模块完成才集成：

- 完成一个模块，立即进行集成测试
- 使用 Mock 替代未完成的依赖

```python
# 示例：使用 Mock 进行集成测试
from unittest.mock import AsyncMock, MagicMock

@pytest.fixture
def mock_opencode_tools():
    """Mock OpenCode 工具"""
    return {
        "invoke_opencode_agent": AsyncMock(return_value={"task_id": "test_001"}),
        "read_progress_report": AsyncMock(return_value=mock_report),
    }
```

### 6.3 持续验证

- 每次提交运行单元测试
- 每天运行集成测试
- 每周进行端到端测试

### 6.4 文档同步

- 代码变更时同步更新文档
- API 变更时更新契约文档
- 保持设计与实现的一致性

### 6.5 技术风险前置

对于高风险技术点，在正式开发前进行 **PoC 验证**：

```markdown
# PoC 验证清单

## OpenCode 容器化
- [ ] OpenCode 能否在容器内正常运行？
- [ ] 容器内能否访问外部 LLM API？
- [ ] 进度报告文件能否被宿主机读取？
- [ ] 资源限制是否有效？
- [ ] 网络隔离是否正常？

## Skills 机制
- [ ] Skills 能否正确注入到 Prompt？
- [ ] OpenCode 是否遵循 Skills 约束？
- [ ] 输出验证是否可靠？

## 状态同步
- [ ] 事件总线是否可靠？
- [ ] 状态缓存是否一致？
- [ ] 延迟是否可接受？
```

---

## 七、开发时间线汇总

| 阶段 | 内容 | 预计时间 | 依赖 |
|------|------|---------|------|
| 阶段 0 | 环境准备与验收标准 | 1 天 | - |
| 阶段 1 | 基础设施层 | 5-7 天 | 阶段 0 |
| 阶段 2 | 能力层 | 4-5 天 | 阶段 1 |
| 阶段 3 | 协调层 | 5-6 天 | 阶段 2 |
| 阶段 4 | 应用层 | 6-8 天 | 阶段 3 |
| 阶段 5 | 集成与优化 | 3-5 天 | 阶段 4 |
| **总计** | | **24-32 天** | |

### 甘特图

```
Week 1: [阶段 0][阶段 1: 基础设施层                  ]
Week 2: [阶段 1 续][阶段 2: 能力层          ]
Week 3: [阶段 2 续][阶段 3: 协调层              ]
Week 4: [阶段 3 续][阶段 4: 应用层              ]
Week 5: [阶段 4 续][阶段 5: 集成优化    ]
```

---

## 八、风险与缓解措施

| 风险 | 可能性 | 影响 | 缓解措施 |
|------|--------|------|---------|
| OpenCode 容器化问题 | 高 | 高 | 阶段 1 开始前进行 PoC 验证 |
| Skills 触发不可靠 | 中 | 高 | 设计后置验证机制，报告格式不正确时重新生成 |
| 错误循环误报/漏报 | 中 | 中 | 使用多维度检测 + 阈值调优 |
| 状态同步延迟 | 中 | 中 | 事件驱动 + 缓存机制 |
| 模块间接口变更 | 中 | 高 | 接口契约评审 + 版本控制 |
| 长程任务上下文丢失 | 中 | 高 | 分层上下文管理 + 检查点机制 |
| LLM API 不稳定 | 中 | 中 | 重试机制 + 降级策略 |
| 资源耗尽 | 低 | 高 | 资源池 + 优先级调度 |

---

## 九、附录

### 9.1 目录结构规划

```
research/
├── agents/                      # Agent 实现
│   ├── planning_agent.py
│   └── __init__.py
├── modules/                     # 应用层模块
│   ├── idea_normalization/
│   ├── experiment_planning/
│   └── result_analysis/
├── skills/                      # Skills 引擎
│   ├── base.py
│   ├── engine.py
│   └── loader.py
├── monitoring/                  # 监控模块
│   ├── error_detector.py
│   └── metrics.py
├── progress/                    # 进度报告
│   ├── models.py
│   ├── generator.py
│   └── reader.py
├── state/                       # 状态管理
│   ├── task_state.py
│   └── state_machine.py
├── sync/                        # 状态同步
│   ├── event_bus.py
│   └── state_cache.py
├── tools/                       # LangChain 工具
│   ├── sandbox_tools.py        # 已有
│   └── opencode_tools.py       # 新增
├── sandbox/                     # 沙盒管理 (已有)
├── .opencode/                   # OpenCode 配置
│   └── skill/
│       ├── progress-report/
│       ├── baseline-reproduction/
│       └── idea-implementation/
├── tests/
│   ├── unit/
│   └── integration/
└── docs/                        # 文档
    ├── main-design-v4.md
    ├── implementation-challenges.md
    ├── development-roadmap.md   # 本文档
    └── api_contracts.md
```

### 9.2 相关文档

| 文档 | 路径 | 说明 |
|------|------|------|
| 架构设计 v4 | ./main-design-v4.md | 系统架构设计 |
| 实现难点分析 | ./implementation-challenges.md | 技术挑战与解决方案 |
| 工具函数清单 | ./tool-functions.md | 可用工具函数 |
| 通信协议规范 | ./communication-protocol-v2.md | 模块间通信协议 |
| 状态管理设计 | ./state-management.md | 状态和调试管理 |

### 9.3 版本历史

| 版本 | 日期 | 修改内容 |
|------|------|----------|
| v1.0 | 2026-02-20 | 初始版本，完整开发路线设计 |
