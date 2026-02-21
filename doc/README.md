# 科研智能体系统文档

## 文档列表

| 文档 | 说明 |
|------|------|
| [main-design-v4.md](./main-design-v4.md) | **系统架构设计 v4.0** - OpenCode 沙盒部署、Skills 机制、进度报告 |
| [development-roadmap.md](./development-roadmap.md) | **开发路线设计** - 模块开发顺序、内部流程、避免返工策略 |
| [implementation-challenges.md](./implementation-challenges.md) | **实现难点分析** - 技术挑战、多智能体关键要点、优先级建议 |
| [communication-protocol-v2.md](./communication-protocol-v2.md) | 通信协议 - 自然语言通信、Markdown 文档格式 |
| [tool-functions.md](./tool-functions.md) | 工具函数清单 - 沙盒管理、代码操作、实验追踪 |
| [state-management.md](./state-management.md) | 状态管理 - 检查点、调试工具、故障恢复 |
| [api_contracts.md](./api_contracts.md) | **API 契约** - OpenCode 接口、消息类型、状态模型定义 |

## 快速导航

### 了解系统整体架构

1. [main-design-v4.md](./main-design-v4.md)
   - 第1-2章：概述与三层架构
   - 第4章：OpenCode 沙盒部署方案
   - 第5章：Skills 设计

### 开始开发

1. [development-roadmap.md](./development-roadmap.md)
   - 第2章：开发原则（避免返工）
   - 第3章：模块开发顺序
   - 第4章：各阶段详细开发流程

### 实现多智能体系统

1. [implementation-challenges.md](./implementation-challenges.md)
   - 第2章：核心实现难点
   - 第3章：多智能体系统关键要点

### 实现模块间通信

1. [communication-protocol-v2.md](./communication-protocol-v2.md)
   - 第2章：文档结构标准
   - 第3章：模块间通信示例

### 开发工具函数

1. [tool-functions.md](./tool-functions.md)
   - 第2章：沙盒管理工具
   - 第6章：OpenCode 交互工具（v4 新增）

### 实现状态持久化

1. [state-management.md](./state-management.md)
   - 第2章：状态文件结构
   - 第3章：检查点机制

### 开发前准备 (阶段 0)

1. [api_contracts.md](./api_contracts.md)
   - 第2章：OpenCode 接口定义
   - 第3章：消息类型规范
   - 第4章：状态模型定义

## 架构概览 (v4.0)

```
┌─────────────────────────────────────────────────────────────┐
│                      科研智能体系统 v4.0                       │
├─────────────────────────────────────────────────────────────┤
│  第一层（交互层）                                             │
│  ├── Idea 规范化模块 (LangChain Agent)                       │
│  └── 实验计划模块 (LangChain Agent)                          │
├─────────────────────────────────────────────────────────────┤
│  第二层（执行层）                                             │
│  ├── 规划层 Agent (LangChain Agent)                         │
│  │   └── 工具函数: invoke_opencode_agent, read_progress     │
│  └── 沙盒容器                                                │
│      └── OpenCode Agent (Skills 约束 + 进度报告)             │
├─────────────────────────────────────────────────────────────┤
│  第三层（分析层）                                             │
│  └── 实验结果分析模块 (LangChain Agent)                       │
└─────────────────────────────────────────────────────────────┘
```

## v4.0 核心变更

| 变更项 | v3 | v4 |
|--------|-----|-----|
| Coding Agent 位置 | 规划层内部（Sub Agent） | 沙盒容器内（独立） |
| 通信方式 | 直接返回执行过程 | 进度报告文件 |
| 行为约束 | 无 | Skills 机制 |
| 上下文压力 | 高 | 低 |

## 实现优先级

| 阶段 | 内容 |
|------|------|
| P0 | OpenCode 沙盒集成、progress-report Skill |
| P1 | 工具函数实现、错误循环检测 |
| P2 | 状态同步、检查点恢复 |
| P3 | 其他 Skills、监控告警 |

## 版本历史

| 版本 | 日期 | 修改内容 |
|------|------|----------|
| v4.0 | 2026-02-20 | OpenCode 沙盒部署方案，Skills 机制，进度报告通信 |
| v3.0 | 2024-02-19 | 规范化设计，明确关键机制 |
