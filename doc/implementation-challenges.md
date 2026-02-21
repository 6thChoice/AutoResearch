# 科研智能体系统 - 实现难点与关键要点分析

## 文档信息

| 属性 | 值 |
|------|-----|
| 版本 | v1.0 |
| 日期 | 2026-02-20 |
| 关联文档 | main-design-v4.md |
| 状态 | 技术分析 |

---

## 1. 概述

本文档基于 v4.0 架构设计，分析系统实现过程中的技术难点和多智能体系统的关键实现要点，为后续开发提供指导。

---

## 2. 核心实现难点

### 2.1 OpenCode 沙盒集成

#### 2.1.1 问题描述

OpenCode 原生设计是在宿主机上运行，需要将其改造为在 Docker 容器内运行，同时保持与规划层的通信能力。

#### 2.1.2 技术挑战

| 挑战 | 说明 | 风险等级 |
|------|------|---------|
| **环境隔离** | OpenCode 需要在容器内访问文件系统、执行命令，需要正确配置权限 | 高 |
| **API 通信** | 规划层需要通过 HTTP API 与容器内的 OpenCode 通信 | 中 |
| **模型调用** | 容器内的 OpenCode 需要访问外部 LLM API（Anthropic） | 中 |
| **资源限制** | 容器资源限制可能影响 OpenCode 的执行效率 | 中 |
| **状态持久化** | 容器重启后需要恢复 OpenCode 的执行状态 | 高 |

#### 2.1.3 解决方案

```python
# 方案：双层通信架构
class OpenCodeSandboxBridge:
    """OpenCode 沙盒通信桥"""

    def __init__(self, sandbox_id: str):
        self.sandbox_id = sandbox_id
        self.api_endpoint = f"http://{sandbox_id}:8080"
        self.progress_dir = "/workspace/.progress"

    # 方式1: HTTP API（实时通信）
    async def invoke_via_api(self, task: str) -> str:
        """通过 HTTP API 调用 OpenCode"""
        async with aiohttp.ClientSession() as session:
            async with session.post(
                f"{self.api_endpoint}/invoke",
                json={"task": task}
            ) as response:
                return await response.json()["task_id"]

    # 方式2: 文件系统（进度报告）
    def read_progress_via_file(self) -> List[ProgressReport]:
        """通过文件系统读取进度报告"""
        # 宿主机挂载了容器的 /workspace 目录
        report_dir = f"/mnt/sandboxes/{self.sandbox_id}/.progress"
        return self._load_reports(report_dir)
```

**关键配置：**

```yaml
# docker-compose.yml
services:
  opencode-sandbox:
    image: opencode-research:latest
    volumes:
      - ./sandboxes/${SANDBOX_ID}/workspace:/workspace
      - ./sandboxes/${SANDBOX_ID}/progress:/workspace/.progress
    environment:
      - ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
      - OPENCODE_MODEL=claude-3-5-sonnet-20241022
    ports:
      - "${API_PORT}:8080"
```

---

### 2.2 Skills 机制实现

#### 2.2.1 问题描述

Skills 机制是约束 OpenCode 行为的核心，需要设计一套可靠的方式让 OpenCode 在特定节点执行特定行为（如生成进度报告）。

#### 2.2.2 技术挑战

| 挑战 | 说明 | 风险等级 |
|------|------|---------|
| **触发可靠性** | 如何确保 OpenCode 在正确的节点触发 Skill | 高 |
| **格式一致性** | 如何确保生成的报告格式始终一致 | 中 |
| **Skill 组合** | 多个 Skill 同时激活时的优先级和冲突处理 | 中 |
| **动态加载** | 任务运行时动态加载/卸载 Skill | 低 |

#### 2.2.3 解决方案

**方案：基于 Prompt 的 Skill 注入 + 后置验证**

```
┌─────────────────────────────────────────────────────────┐
│                    Skill 执行流程                        │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  1. 任务开始前                                          │
│     │                                                   │
│     ▼                                                   │
│  ┌─────────────────┐                                   │
│  │ 加载 Skills     │                                   │
│  │ 注入到 System   │                                   │
│  │ Prompt          │                                   │
│  └────────┬────────┘                                   │
│           ▼                                             │
│  2. OpenCode 执行任务                                   │
│     │                                                   │
│     │ (Skills 约束行为)                                 │
│     ▼                                                   │
│  3. 关键节点触发                                        │
│     │                                                   │
│     ▼                                                   │
│  ┌─────────────────┐                                   │
│  │ 生成进度报告    │                                   │
│  │ (按 Skill 模板) │                                   │
│  └────────┬────────┘                                   │
│           ▼                                             │
│  4. 后置验证                                            │
│     │                                                   │
│     ▼                                                   │
│  ┌─────────────────┐                                   │
│  │ 验证报告格式    │                                   │
│  │ 不符合则重新生成│                                   │
│  └─────────────────┘                                   │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

**Skill 注入示例：**

```markdown
# System Prompt 注入内容

## 必须遵守的规则 (progress-report Skill)

你在执行任务时必须遵守以下规则：

### 报告触发条件
- 任务开始时：立即生成 START_REPORT
- 每30分钟：生成 PERIODIC_REPORT
- 进度达到 25%/50%/75%：生成 MILESTONE_REPORT
- 任务完成/失败/中止：生成对应的结束报告

### 报告格式
必须使用以下 Markdown 格式：

```markdown
# 进度报告

**文档类型**: PROGRESS
**任务ID**: {当前任务ID}
...
```

### 报告存储
所有报告必须写入 `/workspace/.progress/` 目录
```

**后置验证器：**

```python
class ProgressReportValidator:
    """进度报告验证器"""

    REQUIRED_FIELDS = [
        "文档类型", "任务ID", "生成时间",
        "状态", "进度", "执行摘要"
    ]

    VALID_STATUSES = [
        "RUNNING", "COMPLETED", "FAILED",
        "ABORTED", "ERROR_LOOP"
    ]

    def validate(self, report_path: str) -> ValidationResult:
        """验证报告格式"""
        with open(report_path, 'r') as f:
            content = f.read()

        errors = []

        # 检查必需字段
        for field in self.REQUIRED_FIELDS:
            if f"**{field}**:" not in content:
                errors.append(f"缺少必需字段: {field}")

        # 检查状态值
        import re
        status_match = re.search(r'\*\*状态\*\*:\s*(\w+)', content)
        if status_match:
            status = status_match.group(1)
            if status not in self.VALID_STATUSES:
                errors.append(f"无效的状态值: {status}")

        return ValidationResult(
            valid=len(errors) == 0,
            errors=errors
        )
```

---

### 2.3 错误循环检测

#### 2.3.1 问题描述

OpenCode 在遇到问题时可能会陷入重复尝试相同解决方案的循环，需要可靠的检测机制来识别并中断这种循环。

#### 2.3.2 技术挑战

| 挑战 | 说明 | 风险等级 |
|------|------|---------|
| **错误相似度判断** | 如何判断两个错误是否"相同"（语义相似 vs 字面相同） | 高 |
| **误报率** | 正常的重试可能被误判为错误循环 | 中 |
| **漏报率** | 真正的错误循环可能未被检测到 | 高 |
| **上下文丢失** | 错误发生时可能丢失关键上下文信息 | 中 |

#### 2.3.3 解决方案

**方案：多维度错误分析 + LLM 辅助判断**

```python
class EnhancedErrorLoopDetector:
    """增强的错误循环检测器"""

    def __init__(self):
        self.error_history: List[ErrorRecord] = []
        self.ERROR_WINDOW = 600  # 10分钟
        self.MAX_CONSECUTIVE = 3
        self.MAX_IN_WINDOW = 5

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

        # 3. 语义相似度检测（使用 Embedding）
        semantic_match = self._check_semantic_similarity(error_record)

        # 4. 错误类型聚合
        type_aggregation = self._check_type_aggregation()

        # 5. 综合判断
        is_loop = (
            exact_match.count >= self.MAX_CONSECUTIVE or
            semantic_match.max_similarity > 0.9 or
            type_aggregation.count >= self.MAX_IN_WINDOW
        )

        # 添加到历史
        self.error_history.append(error_record)

        return ErrorAnalysis(
            is_error_loop=is_loop,
            exact_match_count=exact_match.count,
            semantic_similarity=semantic_match.max_similarity,
            type_aggregation_count=type_aggregation.count,
            recommendation=self._generate_recommendation(is_loop, error_record)
        )

    def _check_semantic_similarity(self, error: ErrorRecord) -> SimilarityResult:
        """使用 Embedding 检测语义相似错误"""
        # 获取当前错误消息的 embedding
        current_embedding = self._get_embedding(error.error_message)

        max_similarity = 0.0
        similar_errors = []

        for record in self.error_history:
            if record.embedding is None:
                record.embedding = self._get_embedding(record.error_message)

            similarity = cosine_similarity(current_embedding, record.embedding)
            if similarity > 0.8:  # 语义相似阈值
                similar_errors.append((record, similarity))
                max_similarity = max(max_similarity, similarity)

        return SimilarityResult(
            max_similarity=max_similarity,
            similar_errors=similar_errors
        )

    def _get_embedding(self, text: str) -> np.ndarray:
        """获取文本 embedding"""
        # 调用 embedding 模型
        response = openai.embeddings.create(
            model="text-embedding-3-small",
            input=text
        )
        return np.array(response.data[0].embedding)
```

---

### 2.4 规划层与 OpenCode 的状态同步

#### 2.4.1 问题描述

规划层需要实时了解 OpenCode 的执行状态，但两者运行在不同的进程中，状态同步存在延迟和一致性挑战。

#### 2.4.2 技术挑战

| 挑战 | 说明 | 风险等级 |
|------|------|---------|
| **状态延迟** | 规划层读取的状态可能是过期的 | 中 |
| **并发冲突** | 多个组件同时读写状态文件 | 高 |
| **部分失败** | 状态更新部分成功导致不一致 | 中 |
| **网络分区** | 网络故障导致通信中断 | 高 |

#### 2.4.3 解决方案

**方案：事件驱动 + 最终一致性**

```
┌─────────────────────────────────────────────────────────────────┐
│                      状态同步架构                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  OpenCode Agent                     规划层 Agent               │
│       │                                   │                     │
│       │ 1. 状态变更                        │                     │
│       ▼                                   │                     │
│  ┌─────────────┐                          │                     │
│  │ 写入进度    │                          │                     │
│  │ 报告文件    │                          │                     │
│  └──────┬──────┘                          │                     │
│         │                                 │                     │
│         │ 2. 发送事件通知                  │                     │
│         ▼                                 │                     │
│  ┌─────────────┐      事件总线      ┌──────▼──────┐            │
│  │ Event       │─────────────────▶│ Event       │            │
│  │ Publisher   │                   │ Consumer    │            │
│  └─────────────┘                   └──────┬──────┘            │
│                                           │                     │
│                                           │ 3. 接收事件         │
│                                           ▼                     │
│                                    ┌─────────────┐             │
│                                    │ 更新本地    │             │
│                                    │ 状态缓存    │             │
│                                    └──────┬──────┘             │
│                                           │                     │
│                                           │ 4. 必要时读取       │
│                                           ▼                     │
│                                    ┌─────────────┐             │
│                                    │ 读取完整    │             │
│                                    │ 进度报告    │             │
│                                    └─────────────┘             │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**事件定义：**

```python
from dataclasses import dataclass
from datetime import datetime
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

    def to_message(self) -> str:
        """序列化为消息"""
        return json.dumps({
            "event_id": self.event_id,
            "event_type": self.event_type.value,
            "task_id": self.task_id,
            "sandbox_id": self.sandbox_id,
            "timestamp": self.timestamp.isoformat(),
            "payload": self.payload
        })
```

**状态缓存：**

```python
class StateCache:
    """状态缓存（带 TTL）"""

    def __init__(self, ttl_seconds: int = 30):
        self.cache: Dict[str, CachedState] = {}
        self.ttl = ttl_seconds

    def get(self, key: str) -> Optional[dict]:
        """获取缓存状态"""
        if key in self.cache:
            cached = self.cache[key]
            if time.time() - cached.timestamp < self.ttl:
                return cached.data
            else:
                del self.cache[key]
        return None

    def set(self, key: str, data: dict):
        """设置缓存状态"""
        self.cache[key] = CachedState(
            data=data,
            timestamp=time.time()
        )

    def invalidate(self, key: str):
        """使缓存失效"""
        if key in self.cache:
            del self.cache[key]
```

---

### 2.5 长程任务的上下文管理

#### 2.5.1 问题描述

科研实验可能持续数小时甚至数天，OpenCode 需要在长程任务中保持上下文连贯性，同时避免上下文窗口溢出。

#### 2.5.2 技术挑战

| 挑战 | 说明 | 风险等级 |
|------|------|---------|
| **上下文丢失** | 长时间运行后丢失早期重要信息 | 高 |
| **窗口溢出** | 对话历史超出模型上下文限制 | 高 |
| **状态恢复** | 任务中断后如何恢复上下文 | 中 |
| **信息压缩** | 如何有效压缩历史信息 | 中 |

#### 2.5.3 解决方案

**方案：分层上下文管理**

```
┌─────────────────────────────────────────────────────────────────┐
│                      上下文分层结构                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Layer 0: 任务级上下文（持久化）                                │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • 任务目标和要求                                          │   │
│  │ • 关键配置参数                                            │   │
│  │ • 技术约束和验收标准                                      │   │
│  │ 存储: /workspace/.context/task_context.md                │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Layer 1: 阶段级上下文（定期保存）                              │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • 当前阶段目标                                            │   │
│  │ • 已完成的工作摘要                                        │   │
│  │ • 遇到的问题和解决方案                                    │   │
│  │ 存储: /workspace/.context/phase_summary_{n}.md           │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Layer 2: 会话级上下文（活跃内存）                              │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • 最近 N 轮对话                                          │   │
│  │ • 当前正在处理的子任务                                    │   │
│  │ • 临时变量和状态                                          │   │
│  │ 存储: 内存中，受上下文窗口限制                            │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**上下文压缩策略：**

```python
class ContextCompressor:
    """上下文压缩器"""

    def __init__(self, max_tokens: int = 100000):
        self.max_tokens = max_tokens
        self.tokenizer = tiktoken.encoding_for_model("claude-3-5-sonnet")

    def compress(self, messages: List[dict]) -> List[dict]:
        """压缩对话历史"""
        current_tokens = self._count_tokens(messages)

        if current_tokens <= self.max_tokens:
            return messages

        # 压缩策略
        compressed = []

        # 1. 保留系统消息
        system_messages = [m for m in messages if m["role"] == "system"]
        compressed.extend(system_messages)

        # 2. 保留最近的对话
        recent_messages = messages[-20:]  # 最近20轮

        # 3. 中间部分生成摘要
        middle_messages = messages[len(system_messages):-20]
        if middle_messages:
            summary = self._generate_summary(middle_messages)
            compressed.append({
                "role": "user",
                "content": f"[历史摘要]\n{summary}"
            })

        compressed.extend(recent_messages)

        return compressed

    def _generate_summary(self, messages: List[dict]) -> str:
        """使用 LLM 生成摘要"""
        # 调用 LLM 生成压缩摘要
        prompt = f"""请总结以下对话的关键信息，包括：
1. 已完成的主要工作
2. 遇到的关键问题和解决方案
3. 重要的决策和结论

对话内容：
{self._format_messages(messages)}

请用简洁的要点形式输出，不超过500字。"""

        response = anthropic_client.messages.create(
            model="claude-3-5-haiku-20241022",  # 使用快速模型
            max_tokens=1000,
            messages=[{"role": "user", "content": prompt}]
        )
        return response.content[0].text
```

---

## 3. 多智能体系统关键要点

### 3.1 智能体角色与职责划分

#### 3.1.1 设计原则

| 原则 | 说明 |
|------|------|
| **单一职责** | 每个智能体只负责一个明确的功能领域 |
| **松耦合** | 智能体之间通过明确定义的接口通信，减少直接依赖 |
| **高内聚** | 相关功能集中在一个智能体内 |
| **可替换性** | 智能体实现可以被替换而不影响整体系统 |

#### 3.1.2 角色定义

```python
from abc import ABC, abstractmethod
from typing import Any, Dict, Optional
from dataclasses import dataclass

@dataclass
class AgentCapability:
    """智能体能力声明"""
    name: str
    description: str
    input_schema: dict
    output_schema: dict

class BaseAgent(ABC):
    """智能体基类"""

    def __init__(self, agent_id: str, config: dict):
        self.agent_id = agent_id
        self.config = config
        self.capabilities: List[AgentCapability] = []

    @abstractmethod
    async def execute(self, task: dict) -> dict:
        """执行任务"""
        pass

    @abstractmethod
    def get_status(self) -> dict:
        """获取状态"""
        pass

    def declare_capability(self, capability: AgentCapability):
        """声明能力"""
        self.capabilities.append(capability)

# 具体智能体实现
class PlanningAgent(BaseAgent):
    """规划层智能体"""

    def __init__(self, agent_id: str, config: dict):
        super().__init__(agent_id, config)
        self.declare_capability(AgentCapability(
            name="task_decomposition",
            description="将复杂任务分解为子任务",
            input_schema={"task": "string"},
            output_schema={"subtasks": "list"}
        ))
        self.declare_capability(AgentCapability(
            name="invoke_opencode",
            description="调用 OpenCode 执行代码任务",
            input_schema={"task": "string", "skills": "list"},
            output_schema={"task_id": "string", "status": "string"}
        ))

class OpenCodeAgent(BaseAgent):
    """OpenCode 智能体"""

    def __init__(self, agent_id: str, config: dict, sandbox_id: str):
        super().__init__(agent_id, config)
        self.sandbox_id = sandbox_id
        self.declare_capability(AgentCapability(
            name="code_execution",
            description="在沙盒内执行代码",
            input_schema={"code": "string", "language": "string"},
            output_schema={"result": "string", "status": "string"}
        ))
        self.declare_capability(AgentCapability(
            name="progress_reporting",
            description="生成任务进度报告",
            input_schema={"event_type": "string", "context": "dict"},
            output_schema={"report": "string", "path": "string"}
        ))
```

### 3.2 智能体通信协议

#### 3.2.1 通信模式

| 模式 | 使用场景 | 示例 |
|------|---------|------|
| **请求-响应** | 同步操作，需要立即返回结果 | 查询任务状态 |
| **发布-订阅** | 异步事件通知 | 进度更新、错误告警 |
| **共享存储** | 大数据量传递 | 进度报告文件 |

#### 3.2.2 消息格式规范

```python
from dataclasses import dataclass
from datetime import datetime
from enum import Enum
from typing import Any, Dict, Optional
import uuid

class MessagePriority(Enum):
    LOW = 1
    NORMAL = 2
    HIGH = 3
    URGENT = 4

@dataclass
class AgentMessage:
    """智能体间通信消息"""

    # 必需字段
    message_id: str
    sender_id: str
    receiver_id: str
    message_type: str
    timestamp: datetime
    payload: Dict[str, Any]

    # 可选字段
    correlation_id: Optional[str] = None  # 关联的请求ID
    priority: MessagePriority = MessagePriority.NORMAL
    ttl_seconds: Optional[int] = None  # 消息有效期
    callback_url: Optional[str] = None  # 回调地址

    @classmethod
    def create(cls,
               sender_id: str,
               receiver_id: str,
               message_type: str,
               payload: Dict[str, Any],
               **kwargs) -> 'AgentMessage':
        """创建消息"""
        return cls(
            message_id=str(uuid.uuid4()),
            sender_id=sender_id,
            receiver_id=receiver_id,
            message_type=message_type,
            timestamp=datetime.now(),
            payload=payload,
            **kwargs
        )

    def to_json(self) -> str:
        """序列化为 JSON"""
        return json.dumps({
            "message_id": self.message_id,
            "sender_id": self.sender_id,
            "receiver_id": self.receiver_id,
            "message_type": self.message_type,
            "timestamp": self.timestamp.isoformat(),
            "payload": self.payload,
            "correlation_id": self.correlation_id,
            "priority": self.priority.value,
            "ttl_seconds": self.ttl_seconds,
            "callback_url": self.callback_url
        })
```

#### 3.2.3 消息路由

```python
class MessageRouter:
    """消息路由器"""

    def __init__(self):
        self.routes: Dict[str, List[str]] = {}  # agent_id -> [supported_types]
        self.handlers: Dict[str, Callable] = {}

    def register_agent(self, agent_id: str, supported_types: List[str]):
        """注册智能体"""
        self.routes[agent_id] = supported_types

    def route(self, message: AgentMessage) -> Optional[str]:
        """路由消息"""
        receiver = message.receiver_id

        # 直接路由
        if receiver in self.routes:
            if message.message_type in self.routes[receiver]:
                return receiver

        # 广播路由
        if receiver == "broadcast":
            return [
                agent_id for agent_id, types in self.routes.items()
                if message.message_type in types
            ]

        return None
```

### 3.3 任务编排与协调

#### 3.3.1 任务状态机

```python
from enum import Enum
from typing import Optional
from dataclasses import dataclass

class TaskState(Enum):
    """任务状态"""
    PENDING = "pending"           # 等待执行
    RUNNING = "running"           # 执行中
    PAUSED = "paused"             # 已暂停
    COMPLETED = "completed"       # 已完成
    FAILED = "failed"             # 已失败
    CANCELLED = "cancelled"       # 已取消

class TaskStateMachine:
    """任务状态机"""

    # 允许的状态转换
    TRANSITIONS = {
        TaskState.PENDING: [TaskState.RUNNING, TaskState.CANCELLED],
        TaskState.RUNNING: [TaskState.COMPLETED, TaskState.FAILED, TaskState.PAUSED, TaskState.CANCELLED],
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

    def can_transition_to(self, new_state: TaskState) -> bool:
        """检查是否可以转换到目标状态"""
        return new_state in self.TRANSITIONS[self.state]
```

#### 3.3.2 任务依赖管理

```python
from typing import Dict, List, Set
from collections import defaultdict

class TaskDependencyManager:
    """任务依赖管理器"""

    def __init__(self):
        self.dependencies: Dict[str, Set[str]] = defaultdict(set)  # task_id -> depends_on
        self.dependents: Dict[str, Set[str]] = defaultdict(set)    # task_id -> depended_by

    def add_dependency(self, task_id: str, depends_on: str):
        """添加依赖"""
        self.dependencies[task_id].add(depends_on)
        self.dependents[depends_on].add(task_id)

    def get_ready_tasks(self, completed_tasks: Set[str]) -> List[str]:
        """获取可以执行的任务"""
        ready = []
        for task_id, deps in self.dependencies.items():
            if task_id not in completed_tasks:
                if deps.issubset(completed_tasks):
                    ready.append(task_id)
        return ready

    def get_blocked_tasks(self, failed_task: str) -> Set[str]:
        """获取被失败任务阻塞的任务"""
        blocked = set()
        to_check = list(self.dependents[failed_task])

        while to_check:
            task_id = to_check.pop()
            if task_id not in blocked:
                blocked.add(task_id)
                to_check.extend(self.dependents[task_id])

        return blocked
```

### 3.4 故障恢复与容错

#### 3.4.1 故障类型与处理策略

| 故障类型 | 检测方式 | 处理策略 |
|---------|---------|---------|
| **智能体崩溃** | 心跳超时 | 重启智能体，从检查点恢复 |
| **任务超时** | 定时器 | 中止任务，生成超时报告 |
| **通信失败** | 重试计数 | 重试 + 降级方案 |
| **资源耗尽** | 监控告警 | 扩容或任务排队 |
| **错误循环** | 模式检测 | 中断并请求人工干预 |

#### 3.4.2 检查点机制

```python
import pickle
from dataclasses import dataclass
from typing import Any, Dict
from pathlib import Path

@dataclass
class Checkpoint:
    """检查点"""
    checkpoint_id: str
    task_id: str
    timestamp: datetime
    state: Dict[str, Any]
    metadata: Dict[str, Any]

class CheckpointManager:
    """检查点管理器"""

    def __init__(self, checkpoint_dir: str):
        self.checkpoint_dir = Path(checkpoint_dir)
        self.checkpoint_dir.mkdir(parents=True, exist_ok=True)

    def save(self, task_id: str, state: dict, metadata: dict = None) -> Checkpoint:
        """保存检查点"""
        checkpoint = Checkpoint(
            checkpoint_id=str(uuid.uuid4()),
            task_id=task_id,
            timestamp=datetime.now(),
            state=state,
            metadata=metadata or {}
        )

        path = self.checkpoint_dir / f"{task_id}_{checkpoint.checkpoint_id}.ckpt"
        with open(path, 'wb') as f:
            pickle.dump(checkpoint, f)

        return checkpoint

    def load(self, task_id: str) -> Optional[Checkpoint]:
        """加载最新检查点"""
        checkpoints = list(self.checkpoint_dir.glob(f"{task_id}_*.ckpt"))
        if not checkpoints:
            return None

        # 按时间排序，返回最新的
        latest = max(checkpoints, key=lambda p: p.stat().st_mtime)
        with open(latest, 'rb') as f:
            return pickle.load(f)

    def restore(self, task_id: str, agent: BaseAgent) -> bool:
        """从检查点恢复智能体状态"""
        checkpoint = self.load(task_id)
        if checkpoint is None:
            return False

        # 恢复状态
        agent.restore_state(checkpoint.state)
        return True
```

#### 3.4.3 重试策略

```python
from typing import Callable, TypeVar, Optional
from functools import wraps
import asyncio

T = TypeVar('T')

class RetryPolicy:
    """重试策略"""

    def __init__(
        self,
        max_retries: int = 3,
        base_delay: float = 1.0,
        max_delay: float = 60.0,
        exponential_base: float = 2.0,
        retryable_exceptions: tuple = (Exception,)
    ):
        self.max_retries = max_retries
        self.base_delay = base_delay
        self.max_delay = max_delay
        self.exponential_base = exponential_base
        self.retryable_exceptions = retryable_exceptions

    def calculate_delay(self, attempt: int) -> float:
        """计算重试延迟（指数退避）"""
        delay = self.base_delay * (self.exponential_base ** attempt)
        return min(delay, self.max_delay)

def with_retry(policy: RetryPolicy):
    """重试装饰器"""
    def decorator(func: Callable[..., T]) -> Callable[..., T]:
        @wraps(func)
        async def wrapper(*args, **kwargs) -> T:
            last_exception = None

            for attempt in range(policy.max_retries + 1):
                try:
                    return await func(*args, **kwargs)
                except policy.retryable_exceptions as e:
                    last_exception = e
                    if attempt < policy.max_retries:
                        delay = policy.calculate_delay(attempt)
                        await asyncio.sleep(delay)

            raise last_exception

        return wrapper
    return decorator

# 使用示例
@with_retry(RetryPolicy(max_retries=3, base_delay=1.0))
async def invoke_opencode(task: str) -> str:
    """带重试的 OpenCode 调用"""
    # ...
    pass
```

### 3.5 资源管理与调度

#### 3.5.1 资源池设计

```python
from dataclasses import dataclass
from typing import Optional, Dict
from enum import Enum
import asyncio

class ResourceType(Enum):
    CPU = "cpu"
    MEMORY = "memory"
    GPU = "gpu"

@dataclass
class ResourceRequest:
    """资源请求"""
    cpu: float = 1.0
    memory_gb: float = 4.0
    gpu: int = 0

@dataclass
class ResourceAllocation:
    """资源分配"""
    allocation_id: str
    sandbox_id: str
    resources: Dict[ResourceType, float]
    allocated_at: datetime

class ResourcePool:
    """资源池"""

    def __init__(self, total_cpu: float, total_memory: float, total_gpu: int):
        self.total = {
            ResourceType.CPU: total_cpu,
            ResourceType.MEMORY: total_memory,
            ResourceType.GPU: total_gpu
        }
        self.available = self.total.copy()
        self.allocations: Dict[str, ResourceAllocation] = {}
        self.lock = asyncio.Lock()

    async def acquire(self, request: ResourceRequest, sandbox_id: str) -> Optional[ResourceAllocation]:
        """获取资源"""
        async with self.lock:
            # 检查资源是否足够
            if not self._can_allocate(request):
                return None

            # 分配资源
            allocation = ResourceAllocation(
                allocation_id=str(uuid.uuid4()),
                sandbox_id=sandbox_id,
                resources={
                    ResourceType.CPU: request.cpu,
                    ResourceType.MEMORY: request.memory_gb,
                    ResourceType.GPU: request.gpu
                },
                allocated_at=datetime.now()
            )

            self.available[ResourceType.CPU] -= request.cpu
            self.available[ResourceType.MEMORY] -= request.memory_gb
            self.available[ResourceType.GPU] -= request.gpu

            self.allocations[allocation.allocation_id] = allocation
            return allocation

    async def release(self, allocation_id: str):
        """释放资源"""
        async with self.lock:
            if allocation_id not in self.allocations:
                return

            allocation = self.allocations.pop(allocation_id)
            self.available[ResourceType.CPU] += allocation.resources[ResourceType.CPU]
            self.available[ResourceType.MEMORY] += allocation.resources[ResourceType.MEMORY]
            self.available[ResourceType.GPU] += allocation.resources[ResourceType.GPU]

    def _can_allocate(self, request: ResourceRequest) -> bool:
        """检查是否可以分配"""
        return (
            self.available[ResourceType.CPU] >= request.cpu and
            self.available[ResourceType.MEMORY] >= request.memory_gb and
            self.available[ResourceType.GPU] >= request.gpu
        )
```

#### 3.5.2 任务调度器

```python
from typing import List, Optional
from queue import PriorityQueue
from dataclasses import dataclass, field

@dataclass(order=True)
class ScheduledTask:
    """调度任务"""
    priority: int
    task_id: str = field(compare=False)
    request: ResourceRequest = field(compare=False)
    created_at: datetime = field(compare=False)

class TaskScheduler:
    """任务调度器"""

    def __init__(self, resource_pool: ResourcePool):
        self.resource_pool = resource_pool
        self.queue: PriorityQueue = PriorityQueue()
        self.running_tasks: Dict[str, str] = {}  # task_id -> allocation_id

    def submit(self, task_id: str, request: ResourceRequest, priority: int = 0):
        """提交任务"""
        task = ScheduledTask(
            priority=priority,
            task_id=task_id,
            request=request,
            created_at=datetime.now()
        )
        self.queue.put(task)

    async def schedule(self) -> Optional[str]:
        """调度下一个可执行任务"""
        if self.queue.empty():
            return None

        # 查看队首任务
        task = self.queue.queue[0]

        # 尝试分配资源
        allocation = await self.resource_pool.acquire(task.request, task.task_id)

        if allocation:
            # 分配成功，从队列移除
            self.queue.get()
            self.running_tasks[task.task_id] = allocation.allocation_id
            return task.task_id

        return None

    async def complete(self, task_id: str):
        """完成任务"""
        if task_id in self.running_tasks:
            allocation_id = self.running_tasks.pop(task_id)
            await self.resource_pool.release(allocation_id)
```

---

## 4. 安全与隔离

### 4.1 沙盒安全配置

```yaml
# 安全配置示例
security:
  # 容器隔离
  container:
    privileged: false
    user: "1000:1000"  # 非 root 用户
    read_only_root_fs: true
    no_new_privileges: true

  # 资源限制
  resources:
    cpu_limit: 4
    memory_limit: 16Gi
    pids_limit: 256

  # 网络隔离
  network:
    enabled: true
    allowed_domains:
      - api.anthropic.com
      - github.com
      - huggingface.co
    dns_servers:
      - 8.8.8.8

  # 文件系统
  filesystem:
    volumes:
      - source: ./sandboxes/${SANDBOX_ID}/workspace
        target: /workspace
        options: rw
      - source: ./sandboxes/${SANDBOX_ID}/data
        target: /data
        options: ro  # 只读
```

### 4.2 API 密钥管理

```python
from cryptography.fernet import Fernet
import os

class SecretManager:
    """密钥管理器"""

    def __init__(self, encryption_key: bytes = None):
        key = encryption_key or os.environ.get("ENCRYPTION_KEY")
        if key:
            self.cipher = Fernet(key)
        else:
            self.cipher = None

    def store_secret(self, key: str, value: str):
        """存储密钥"""
        if self.cipher:
            encrypted = self.cipher.encrypt(value.encode())
            # 存储到安全的密钥存储
        else:
            # 开发环境：存储到环境变量
            os.environ[key] = value

    def get_secret(self, key: str) -> str:
        """获取密钥"""
        if self.cipher:
            encrypted = self._retrieve_encrypted(key)
            return self.cipher.decrypt(encrypted).decode()
        else:
            return os.environ.get(key, "")

    def inject_to_sandbox(self, sandbox_id: str, keys: List[str]):
        """将密钥注入沙盒"""
        secrets = {k: self.get_secret(k) for k in keys}
        # 通过安全通道传递给容器
        return secrets
```

---

## 5. 监控与可观测性

### 5.1 监控指标设计

```python
from dataclasses import dataclass
from typing import Dict, List
from prometheus_client import Counter, Histogram, Gauge

# 定义指标
TASK_COUNTER = Counter(
    'agent_tasks_total',
    'Total number of tasks',
    ['agent_type', 'status']
)

TASK_DURATION = Histogram(
    'agent_task_duration_seconds',
    'Task duration in seconds',
    ['agent_type'],
    buckets=[60, 300, 600, 1800, 3600, 7200]
)

CONTEXT_SIZE = Gauge(
    'agent_context_tokens',
    'Current context size in tokens',
    ['agent_id']
)

ERROR_LOOP_COUNTER = Counter(
    'agent_error_loops_total',
    'Total number of error loops detected',
    ['agent_id']
)

@dataclass
class MonitoringMetrics:
    """监控指标"""
    # 任务指标
    tasks_submitted: int = 0
    tasks_completed: int = 0
    tasks_failed: int = 0

    # 性能指标
    avg_task_duration: float = 0.0
    avg_context_tokens: int = 0

    # 资源指标
    cpu_usage: float = 0.0
    memory_usage: float = 0.0
    gpu_usage: float = 0.0

    # 错误指标
    error_count: int = 0
    error_loop_count: int = 0
    retry_count: int = 0
```

### 5.2 日志规范

```python
import structlog
from typing import Any, Dict

# 配置结构化日志
structlog.configure(
    processors=[
        structlog.stdlib.filter_by_level,
        structlog.stdlib.add_logger_name,
        structlog.stdlib.add_log_level,
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.JSONRenderer()
    ],
    wrapper_class=structlog.stdlib.BoundLogger,
    context_class=dict,
    logger_factory=structlog.stdlib.LoggerFactory(),
)

class AgentLogger:
    """智能体日志器"""

    def __init__(self, agent_id: str, agent_type: str):
        self.logger = structlog.get_logger().bind(
            agent_id=agent_id,
            agent_type=agent_type
        )

    def log_task_start(self, task_id: str, task_type: str):
        self.logger.info(
            "task_started",
            task_id=task_id,
            task_type=task_type
        )

    def log_task_complete(self, task_id: str, duration: float, result: str):
        self.logger.info(
            "task_completed",
            task_id=task_id,
            duration_seconds=duration,
            result=result
        )

    def log_error(self, error: Exception, context: Dict[str, Any] = None):
        self.logger.error(
            "error_occurred",
            error_type=type(error).__name__,
            error_message=str(error),
            context=context or {}
        )

    def log_progress_report(self, task_id: str, report_type: str, path: str):
        self.logger.info(
            "progress_report_generated",
            task_id=task_id,
            report_type=report_type,
            report_path=path
        )
```

---

## 6. 实现优先级建议

### 6.1 分阶段实现路线

| 阶段 | 内容 | 优先级 | 预计工作量 |
|------|------|--------|-----------|
| **P0** | OpenCode 沙盒基础集成 | 最高 | 2 周 |
| **P0** | progress-report Skill | 最高 | 1 周 |
| **P1** | 工具函数实现 (4 个) | 高 | 1 周 |
| **P1** | 错误循环检测 | 高 | 1 周 |
| **P2** | 状态同步机制 | 中 | 1 周 |
| **P2** | 检查点恢复 | 中 | 1 周 |
| **P3** | 其他 Skills | 低 | 2 周 |
| **P3** | 监控告警 | 低 | 1 周 |

### 6.2 技术风险评估

| 风险 | 可能性 | 影响 | 缓解措施 |
|------|--------|------|---------|
| OpenCode 容器化问题 | 高 | 高 | 提前进行 PoC 验证 |
| Skills 触发不可靠 | 中 | 高 | 设计后置验证机制 |
| 错误循环误报 | 中 | 中 | 多维度检测 + 阈值调优 |
| 状态同步延迟 | 中 | 中 | 事件驱动 + 缓存机制 |
| 资源竞争 | 低 | 高 | 资源池 + 优先级调度 |

---

## 7. 附录

### 7.1 参考资源

- [OpenCode 官方文档](https://github.com/opencode-ai/opencode)
- [LangChain Agent 文档](https://python.langchain.com/docs/modules/agents/)
- [Docker 容器安全最佳实践](https://docs.docker.com/engine/security/)
- [多智能体系统设计模式](https://www.oreilly.com/library/view/design-patterns-for/9781492091154/)

### 7.2 相关文档

| 文档 | 路径 | 说明 |
|------|------|------|
| 架构设计 v4 | ./main-design-v4.md | 系统架构设计 |
| 工具函数清单 | ./tool-functions.md | 可用工具函数 |
| 状态管理设计 | ./state-management.md | 状态和调试管理 |
