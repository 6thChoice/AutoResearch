#!/usr/bin/env python3
"""
交接验证脚本 (Handover Validation Script)

在 Claude 完成工作后，自动检查它是否更新了必要的交接文档。
用于确保智能体之间的无缝接手。

使用方法:
    python3 validate_handover.py [--strict]

选项:
    --strict  严格模式，任何警告都视为错误
"""

import os
import sys
import re
from datetime import datetime
from pathlib import Path


class HandoverValidator:
    def __init__(self, workspace_dir: str = ".", strict: bool = False):
        self.workspace = Path(workspace_dir)
        self.strict = strict
        self.errors = []
        self.warnings = []

    def error(self, msg: str):
        """记录错误"""
        self.errors.append(msg)
        print(f"❌ 错误: {msg}")

    def warning(self, msg: str):
        """记录警告"""
        self.warnings.append(msg)
        if self.strict:
            self.errors.append(msg)
            print(f"❌ 警告 (严格模式): {msg}")
        else:
            print(f"⚠️  警告: {msg}")

    def success(self, msg: str):
        """记录成功"""
        print(f"✅ {msg}")

    def check_mission_file(self) -> bool:
        """检查 AGENT_MISSION.md 是否存在且内容完整"""
        mission_file = self.workspace / "AGENT_MISSION.md"

        if not mission_file.exists():
            self.error("AGENT_MISSION.md 文件丢失，无法进行交接！")
            return False

        self.success("AGENT_MISSION.md 文件存在")

        content = mission_file.read_text(encoding="utf-8")

        # 检查必要章节
        required_sections = [
            ("项目愿景", ["项目愿景", "愿景与目标"]),
            ("实施进度", ["实施进度", "进度追踪"]),
            ("避坑指南", ["避坑指南", "Pitfalls", "经验"]),
            ("下一步", ["下一步", "Next Steps", "待完成"]),
        ]

        results = []
        for section_name, patterns in required_sections:
            found = any(p in content for p in patterns)
            if not found:
                self.warning(f"缺少『{section_name}』章节")
            else:
                self.success(f"『{section_name}』章节存在")
            results.append(found)

        # 检查是否有待办事项
        todo_patterns = [r"\[ \]", r"- \[ \]", r"TODO", r"待完成"]
        has_todos = any(re.search(p, content) for p in todo_patterns)
        if not has_todos:
            self.warning("『下一步』中没有待办事项，后续智能体可能不知道从哪里开始")
        else:
            self.success("『下一步』中有待办事项")

        return all(results)

    def check_decisions_dir(self) -> bool:
        """检查 docs/decisions/ 目录"""
        decisions_dir = self.workspace / "docs" / "decisions"

        if not decisions_dir.exists():
            # 不强制要求，只是提示
            print("ℹ️  docs/decisions/ 目录不存在（如无架构决策则正常）")
            return True

        adr_files = list(decisions_dir.glob("ADR-*.md"))
        if adr_files:
            self.success(f"发现 {len(adr_files)} 个 ADR 文档")
        else:
            print("ℹ️  暂无 ADR 文档")

        return True

    def check_recent_changes(self) -> bool:
        """检查最近的变更是否被记录"""
        # 检查 git 是否可用
        git_dir = self.workspace / ".git"
        if not git_dir.exists():
            print("ℹ️  非 Git 项目，跳过提交检查")
            return True

        # 检查未提交的变更
        import subprocess
        try:
            result = subprocess.run(
                ["git", "status", "--porcelain"],
                cwd=self.workspace,
                capture_output=True,
                text=True
            )
            if result.stdout.strip():
                uncommitted = result.stdout.strip().split("\n")
                self.warning(f"有 {len(uncommitted)} 个未提交的变更")
            else:
                self.success("工作区干净，无未提交变更")
        except Exception as e:
            print(f"ℹ️  无法检查 Git 状态: {e}")

        return True

    def check_workspace_files(self) -> bool:
        """检查工作区文件"""
        # 检查是否有明显的临时文件未清理
        temp_patterns = ["*.tmp", "*.temp", "*.bak", "*~"]
        temp_files = []
        for pattern in temp_patterns:
            temp_files.extend(self.workspace.glob(pattern))

        if temp_files:
            self.warning(f"发现 {len(temp_files)} 个临时文件未清理")
        else:
            self.success("无遗留临时文件")

        return True

    def validate(self) -> bool:
        """执行所有检查"""
        print("=" * 50)
        print("🔍 交接验证开始")
        print("=" * 50)
        print()

        results = [
            self.check_mission_file(),
            self.check_decisions_dir(),
            self.check_recent_changes(),
            self.check_workspace_files(),
        ]

        print()
        print("=" * 50)
        print("📊 验证结果")
        print("=" * 50)
        print(f"  错误: {len(self.errors)}")
        print(f"  警告: {len(self.warnings)}")
        print()

        if self.errors:
            print("❌ 验证失败，请修复以上错误后重试")
            return False
        elif self.warnings:
            print("⚠️  验证通过（有警告），建议优化后交接")
            return True
        else:
            print("✅ 验证通过，可以安全交接")
            return True


def main():
    strict = "--strict" in sys.argv
    workspace = os.environ.get("WORKSPACE_DIR", ".")

    validator = HandoverValidator(workspace, strict)
    success = validator.validate()

    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
