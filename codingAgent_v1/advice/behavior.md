要实现“智能体之间的无缝接手”，核心在于构建一套**持久化上下文协议（Persistent Context Protocol）**。Claude Code 本身是瞬时的，但它操作的文件系统是持久的。

你可以通过以下方案，让 Claude Code 在容器内养成“边工作边写日记”的习惯，为下一个智能体留下完整的“数字遗产”。

---

## 一：建立“任务指挥手册” (The Mission Control Pattern)

在项目根目录强制建立一个特殊的元数据文件（例如 `AGENT_MISSION.md`），并将其作为 Claude 的 **System Prompt** 的一部分。

### 1. 结构化的文档模板

要求 Claude 维护以下格式的文档：

| 模块 | 内容描述 | 价值 |
| --- | --- | --- |
| **🎯 项目愿景** | 最终目标、技术栈、核心业务逻辑。 | 确保接手者不偏离主轴。 |
| **📅 工作计划** | 当前阶段、待办事项 (TODO)、已完成事项 (DONE)。 | 明确当前处于流水线的哪个环节。 |
| **🚧 避坑指南 (Pits)** | 记录报错、尝试过的失败方案、第三方库的 Bug。 | **价值最高**：防止后续智能体重复尝试错误路径。 |
| **💡 决策记录 (ADR)** | 为什么要改这个架构？权衡了什么？ | 防止接手者因为“看不顺眼”而重构掉关键逻辑。 |

---

## 二：配置 `.clauderc` 强制执行 (Automation)

Claude Code 启动时会读取配置。你可以通过环境变量或配置文件，注入“强制记录”的指令。

在容器的 `/root/.clauderc` 或项目的 `.clauderc` 中加入：

```json
{
  "systemPrompt": "在开始任何代码修改前，请先查阅 AGENT_MISSION.md。每完成一个子任务，必须更新该文件中的『实施进度』和『避坑指南』部分。如果遇到复杂的调试过程，必须详细记录失败的尝试及其原因。"
}

```

---

## 三：构建“任务结束”自动总结脚本

利用你之前的 Python 自动化框架，在 Claude 完成任务后，增加一个**强制总结阶段**。

### Python 封装逻辑示例：

```python
def run_claude_with_summary(task):
    # 1. 执行主线任务
    run_claude(task)
    
    # 2. 强制总结任务（不给它拒绝的机会）
    summary_prompt = """
    请分析你刚才的操作，更新 AGENT_MISSION.md：
    1. 刚才遇到了哪些报错或逻辑陷阱？
    2. 你是如何解决的？（记录在『避坑指南』）
    3. 目前的实施进度百分比是多少？
    4. 下一个接手的智能体应该从哪一行代码开始？
    """
    run_claude(summary_prompt, auto_yes=True)

```

---

## 四：利用 Git Commit 作为“时光机”

智能体对代码的理解往往基于 `git log`。强制 Claude 使用 **Conventional Commits** 并在 Commit Message 中包含详尽的思考。

**要求 Claude 的 Commit 格式：**

```text
feat(auth): 修复了 JWT 刷新逻辑

- 踩坑记录：之前尝试用 redis 存储，但发现容器内网络延迟波动，改用本地缓存。
- 实施进度：登录模块完成 90%。
- 下一步：对接前端拦截器。

```

---

## 五：针对“踩坑”的细粒度记录（ADR 机制）

建议在项目中设立 `docs/decisions/` 目录。每当 Claude 遇到重大逻辑变更或耗时 15 分钟以上的 Bug，要求它生成一个编号文件：`0001-fix-async-deadlock.md`。

**文件内容应包含：**

1. **Context**: 发生了什么？
2. **Failed Attempts**: 试过什么？（这部分对后续智能体最有用）
3. **Solution**: 最终解法。
4. **Status**: 已解决/遗留。

---

## 总结：如何构建接手流程？

当 **Agent B** 启动进入容器接替 **Agent A** 时，它的标准动作应该是：

1. **Read `AGENT_MISSION.md**`: 了解全局进度和当前任务。
2. **Scan `docs/decisions/**`: 了解已有的技术决策，避免质疑前人的代码。
3. **Review `git log**`: 看看前人最近 3 次 commit 的“填坑”心得。


# 模板

为了实现智能体之间的高效接手，我们需要一套**结构化、机器可读且具备防御性**（防止后来的 AI 犯错）的模板。

以下我为你设计了三套互补的模板：**核心任务手册**、**避坑深度记录**，以及一套**自动化约束指令**。

---

## 1. 核心任务手册：`AGENT_MISSION.md`

这是项目的“指挥中心”。建议放在根目录，要求智能体在每次任务开始和结束时更新。

```markdown
# 🤖 Agent 任务指挥手册 (Mission Control)

## 🎯 项目愿景与目标
> 描述此项目最终要解决什么问题，以及核心技术架构。
- **目标**: [例如：构建一个高性能的 Python 异步网关]
- **技术栈**: [FastAPI, Redis, Docker]

## 🛠 当前工作计划 (Roadmap)
- [x] 阶段 1: 基础架构搭建
- [/] 阶段 2: 核心逻辑开发 (当前重点 📍)
- [ ] 阶段 3: 自动化测试与部署

## 📊 实施进度追踪
| 模块 | 状态 | 进度 | 负责人(Agent) | 备注 |
| :--- | :--- | :--- | :--- | :--- |
| 认证模块 | 已完成 | 100% | Claude-3.5-Sonnet | 无 |
| 数据流处理 | 进行中 | 65% | Claude-3-Opus | 阻塞于异步锁竞争 |

## 🚧 避坑指南与经验碎碎念 (The Pitfalls)
> **必读：接手者请务必查阅此项，避免重复踩坑。**
1. **[日期: 2026-02-22]**: 发现容器内 `/tmp` 权限限制，导致 `tempfile` 库报错。
   - **失败尝试**: 修改 `chmod 777`（无效，受限于 Docker 安全策略）。
   - **最终方案**: 显式指定存储路径为 `./volumes/tmp`。
2. **[日期: 2026-02-21]**: 不要升级 `pydantic` 到 v2.x，会导致现有的自定义验证器崩溃。

## ⏩ 下一手指令 (Next Steps)
- [ ] 修复 `stream_processor.py` 第 45 行的死锁。
- [ ] 为新的 API 编写 Swagger 文档。

```

---

## 2. 深度决策记录：`docs/decisions/ADR-NNNN.md`

对于复杂的代码改动，要求智能体生成单独的 ADR（Architecture Decision Record）文档。

**模板名：`ADR-0001-template.md**`

```markdown
# ADR [编号]: [简短的决策标题]

- **日期**: {{DATE}}
- **状态**: [提议 / 已接受 / 已废弃]
- **上下文 (Context)**: 
  > 描述当时遇到了什么 Bug 或需求压力。
- **失败的尝试 (Rejected Alternatives)**:
  > **对 AI 极度重要**：记录试过但无效的代码逻辑。
  - *方案 A*: ... (报错信息: `IndexError`)
  - *方案 B*: ... (导致内存泄露)
- **最终决策 (Decision)**:
  > 选择了什么方案，代码实现的逻辑点。
- **后果 (Consequences)**:
  > 这样做有什么副作用？（例如：虽然解决了性能问题，但增加了代码复杂度）。

```

---

## 3. 自动化约束：`.clauderc` 系统提示词

为了确保智能体**自愿**遵守上述模板，你需要在容器配置中注入“纪律”。

在项目的 `.clauderc` 中配置如下：

```json
{
  "systemPrompt": "你是这个长期项目的维护者。你的行为准则如下：\n1. **文档先于代码**：在修改任何核心逻辑前，先检查根目录的 AGENT_MISSION.md。\n2. **记录失败**：如果你尝试一个修复方案失败了，必须在 AGENT_MISSION.md 的『避坑指南』中记录下失败的原因和报错，严禁直接删除重写而不留痕迹。\n3. **强制更新**：任务结束前，必须更新实施进度和下一步指令，确保下一个智能体可以无缝衔接。\n4. **ADR 触发**：如果修改涉及架构变动或复杂的 Bug 修复，请在 docs/decisions/ 下创建新的 ADR 文件。"
}

```

---

## 4. 进阶：自动化验证脚本 (`validate_handover.py`)

你可以编写一个 Python 脚本，在 Claude 完成工作后，自动检查它是否更新了文档。如果不更新，脚本将报错并要求它重新处理。

```python
import os

def check_handover_readiness():
    mission_file = "AGENT_MISSION.md"
    
    if not os.path.exists(mission_file):
        raise Exception("❌ 错误：AGENT_MISSION.md 丢失，无法进行交接！")
    
    with open(mission_file, 'r') as f:
        content = f.read()
        # 简单的启发式检查
        if "Next Steps" not in content or "[ ]" not in content.split("Next Steps")[-1]:
            print("⚠️ 警告：你没有在『下一步』中为后续智能体留下任何任务。")
        
        if "避坑指南" not in content:
            print("⚠️ 警告：没有记录任何踩坑经验。")

# 在 CI/CD 或容器退出前运行
if __name__ == "__main__":
    check_handover_readiness()

```

### 💡 为什么这套方案能行？

1. **防止“幻觉循环”**：当下一个智能体读到“我曾尝试方案 A 报错 B”时，它就不会再浪费 Token 去重新发明那个错误的轮子。
2. **上下文压缩**：复杂的代码历史被压缩成易读的“避坑指南”，接手智能体不需要通过读取上千行日志来理解之前的错误。
3. **责任明确**：通过进度表，你可以清晰地看到哪个 Agent 完成了什么，哪个 Agent 在哪里卡住了。