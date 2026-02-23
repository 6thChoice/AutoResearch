"""上下文管理器 - 生成内存中的上下文文本，供 coding_bridge 拼入 prompt

codingAgent 不支持文件级上下文注入，所以改为：
- 在内存中维护 global / project 上下文
- 每步执行前生成 task 上下文
- 将三层上下文合并为一段文本，传给 coding_bridge.send_task(context=...)
"""

from planAgent.core import llm

# ── Prompt 模板 ──────────────────────────────────────────

PROJECT_CONTEXT_SYSTEM = """你是一个项目上下文生成器。根据项目目标和当前进度，生成项目级上下文。
输出纯 Markdown。内容应包括：
- 项目目标与愿景
- 技术栈与架构概述
- 当前进度摘要
- 关键设计决策
保持简洁，不超过 50 行。"""

TASK_CONTEXT_SYSTEM = """你是一个任务上下文生成器。根据步骤信息和项目背景，生成任务级上下文。
输出纯 Markdown。内容应包括：
- 当前步骤在整体计划中的位置
- 前置步骤的完成情况
- 本步骤的具体目标与约束
- 与其他步骤的依赖关系
保持简洁，不超过 30 行。"""

PROJECT_UPDATE_SYSTEM = """你是一个项目上下文更新器。根据最新的执行报告更新项目级上下文。
你会收到当前的项目上下文和最新执行报告。输出更新后的完整项目上下文（纯 Markdown）。
保留仍然有效的信息，更新进度，添加新的设计决策。不超过 50 行。"""


class ContextManager:
    """管理 global / project / task 三层上下文（内存模式）"""

    def __init__(self):
        self.global_ctx: str = ""
        self.project_ctx: str = ""
        self.task_ctx: str = ""

    def init_project(self, goal: str, steps: list[dict]):
        """项目开始时，生成 global + project 上下文"""
        steps_text = "\n".join(
            f"  {i}. {s.get('title', '未命名步骤')}: {s.get('description', '')[:80]}"
            for i, s in enumerate(steps, 1)
        )
        msg = f"项目目标：{goal}\n\n执行计划：\n{steps_text}"

        # global 上下文：直接用目标和计划
        self.global_ctx = f"# 项目计划\n\n目标：{goal}\n\n步骤：\n{steps_text}"

        # project 上下文：LLM 生成
        self.project_ctx = llm.call(PROJECT_CONTEXT_SYSTEM, msg)

        print("[Context] 已初始化 global + project 上下文")

    def write_task_context(self, step: dict, step_num: int, total: int, history: list[dict]):
        """每步执行前，生成 task 上下文"""
        history_text = "\n".join(
            f"  {'✓' if h['status'].upper() in ('SUCCESS', 'COMPLETED') else '✗'} {h['step']}"
            for h in history
        ) or "  （无）"

        msg = f"""当前步骤：{step_num}/{total} - {step.get('title', '未命名步骤')}
描述：{step.get('description', '')}
约束：{step.get('constraints', '无')}

已完成步骤：
{history_text}"""

        self.task_ctx = llm.call(TASK_CONTEXT_SYSTEM, msg)
        print(f"[Context] 已生成 task 上下文 (步骤 {step_num}/{total})")

    def update_project(self, report_body: str):
        """步骤完成后，根据报告更新 project 上下文"""
        msg = f"""当前项目上下文：
{self.project_ctx}

最新执行报告：
{report_body[:2000]}"""

        self.project_ctx = llm.call(PROJECT_UPDATE_SYSTEM, msg)

    def cleanup_task(self):
        """步骤完成后清理 task 上下文"""
        self.task_ctx = ""

    def build_context(self) -> str:
        """合并三层上下文为一段文本，用于注入 prompt"""
        sections = []

        if self.global_ctx:
            sections.append(self.global_ctx.strip())

        if self.project_ctx:
            sections.append("# 项目上下文\n\n" + self.project_ctx.strip())

        if self.task_ctx:
            sections.append("# 当前任务上下文\n\n" + self.task_ctx.strip())

        return "\n\n---\n\n".join(sections)
