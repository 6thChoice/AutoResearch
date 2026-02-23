"""Plan Agent 主编排器"""

from planAgent.core import llm, coding_bridge
from planAgent.core.context_manager import ContextManager
from planAgent.config import MAX_RETRIES, MAX_CONSECUTIVE_FAILURES

PLANNER_SYSTEM = """你是一个项目规划智能体。你的任务是将用户的项目目标拆解为具体的、可执行的步骤。

输出要求：返回一个 JSON 数组，每个元素是一个步骤对象：
```json
[
  {
    "title": "步骤标题",
    "description": "详细的任务描述，要足够具体让执行者能独立完成",
    "constraints": "约束条件（可选）",
    "expected_output": "预期输出（可选）"
  }
]
```

原则：
- 每个步骤应该是独立可执行的
- 步骤之间按顺序执行
- 描述要具体、明确，不要模糊
- 步骤数量合理，不要过度拆分"""

EVALUATOR_SYSTEM = """你是一个执行结果评估智能体。根据原始任务和执行报告，判断下一步行动。

输出要求：返回一个 JSON 对象：
```json
{
  "decision": "next | retry | replan | abort",
  "reason": "决策理由",
  "adjusted_steps": []
}
```

决策说明：
- next: 任务成功，继续下一步
- retry: 任务失败但可重试，给出改进建议
- replan: 需要调整后续计划，在 adjusted_steps 中给出新步骤（格式同规划输出）
- abort: 无法继续，需要人工介入"""


class Orchestrator:
    def __init__(self):
        self.steps: list[dict] = []
        self.current_step: int = 0
        self.retry_count: int = 0
        self.consecutive_failures: int = 0
        self.history: list[dict] = []
        self.ctx = ContextManager()

    def run(self, goal: str):
        """主入口"""
        print(f"\n{'='*60}")
        print(f"[Plan Agent] 目标: {goal}")
        print(f"{'='*60}\n")

        self.plan(goal)
        self.ctx.init_project(goal, self.steps)
        self.execute_loop()
        self.summarize()

    def plan(self, goal: str):
        """调用 LLM 拆解目标"""
        print("[Plan Agent] 正在拆解目标为执行步骤...")
        self.steps = llm.call_json(PLANNER_SYSTEM, f"项目目标：{goal}")
        print(f"[Plan Agent] 已拆解为 {len(self.steps)} 个步骤：")
        for i, step in enumerate(self.steps, 1):
            print(f"  {i}. {step['title']}")
        print()

    def execute_loop(self):
        """逐步执行循环"""
        while self.current_step < len(self.steps):
            step = self.steps[self.current_step]
            step_num = self.current_step + 1
            total = len(self.steps)

            try:
                print(f"\n{'─'*40}")
                print(f"[Step {step_num}/{total}] {step['title']}")
                print(f"{'─'*40}")
            except:
                print(f"\n{'─'*40}")
                print(f"[Step {step}")
                print(f"{'─'*40}")

            # 生成 task 上下文
            self.ctx.write_task_context(step, step_num, total, self.history)

            # 合并三层上下文
            context = self.ctx.build_context()

            # 发送任务给 CodingAgent v2
            task_id = coding_bridge.send_task(
                description=step["description"],
                context=context,
                constraints=step.get("constraints", ""),
                expected_output=step.get("expected_output", ""),
            )
            print(f"[Plan Agent] 已发送任务: {task_id}，等待执行结果...")

            # 等待报告
            report = coding_bridge.wait_for_report(task_id)
            if report is None:
                print("[Plan Agent] ⚠ 任务超时！")
                self._handle_failure(step, "任务执行超时，未收到报告")
                continue

            status = report.get("status", "unknown")
            print(f"[Plan Agent] 收到报告，状态: {status}")

            # 更新 project 上下文 & 清理 task 上下文
            self.ctx.update_project(report.get("body", "")[:2000])
            self.ctx.cleanup_task()

            # 记录历史
            self.history.append({
                "step": step["title"],
                "task_id": task_id,
                "status": status,
            })

            # 评估结果
            decision = self._evaluate(step, report)
            self._apply_decision(decision, step)

    def _evaluate(self, step: dict, report: dict) -> dict:
        """调用 LLM 评估报告"""
        msg = f"""原始任务：
标题：{step['title']}
描述：{step['description']}

执行报告：
状态：{report.get('status', 'unknown')}
内容：
{report.get('body', '无内容')[:3000]}

剩余步骤：{[s['title'] for s in self.steps[self.current_step + 1:]]}"""

        return llm.call_json(EVALUATOR_SYSTEM, msg)

    def _apply_decision(self, decision: dict, step: dict):
        """应用评估决策"""
        action = decision.get("decision", "abort")
        reason = decision.get("reason", "")
        print(f"[Plan Agent] 决策: {action} — {reason}")

        if action == "next":
            self.current_step += 1
            self.retry_count = 0
            self.consecutive_failures = 0

        elif action == "retry":
            self.retry_count += 1
            if self.retry_count > MAX_RETRIES:
                self._handle_failure(step, f"重试 {MAX_RETRIES} 次仍失败")

        elif action == "replan":
            new_steps = decision.get("adjusted_steps", [])
            normalized = []
            for s in new_steps:
                if isinstance(s, str):
                    normalized.append({"title": s, "description": s})
                elif isinstance(s, dict):
                    normalized.append(s)
            if normalized:
                self.steps = self.steps[:self.current_step] + normalized
                print(f"[Plan Agent] 已重规划，新计划共 {len(self.steps)} 步")
            self.retry_count = 0

        else:  # abort
            self._handle_failure(step, reason)

    def _handle_failure(self, step: dict, reason: str):
        """处理失败：计数 → 人工介入 → 跳过或终止"""
        self.consecutive_failures += 1
        self.retry_count = 0

        if self.consecutive_failures >= MAX_CONSECUTIVE_FAILURES:
            print(f"\n[Plan Agent] ⚠ 连续 {self.consecutive_failures} 次失败，请求人工介入")
            print(f"  失败原因: {reason}")
            user_input = input("\n请输入指令 (skip=跳过/abort=终止/其他=作为新指令继续): ").strip()
            self.consecutive_failures = 0

            if user_input == "abort":
                self.current_step = len(self.steps)
            elif user_input == "skip":
                self.current_step += 1
            else:
                self.steps[self.current_step] = {
                    "title": "人工指令",
                    "description": user_input,
                }
        else:
            print(f"[Plan Agent] 跳过失败步骤: {step['title']}")
            self.current_step += 1

    def summarize(self):
        """输出执行总结"""
        print(f"\n{'='*60}")
        print("[Plan Agent] 执行总结")
        print(f"{'='*60}")
        total = len(self.history)
        success = sum(1 for h in self.history if h["status"].lower() in ("success", "completed"))
        print(f"  总步骤: {total}，成功: {success}，失败: {total - success}")
        for h in self.history:
            mark = "✓" if h["status"].lower() in ("success", "completed") else "✗"
            print(f"  {mark} {h['step']} [{h['status']}]")
        print()
