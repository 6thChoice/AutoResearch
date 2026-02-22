#!/usr/bin/env python3
"""
上下文组合器 (Context Combiner)

层级化上下文管理系统：
- Global 级：所有项目通用的上下文
- Project 级：特定项目的上下文
- Task 级：特定任务的上下文

组合后的上下文会注入到任务描述前，提供给 Claude Code。

使用方法:
    python3 combine_context.py --task-id <task_id> --output <output_file>
    python3 combine_context.py --list-levels
    python3 combine_context.py --validate
"""

import os
import sys
import json
import argparse
from pathlib import Path
from datetime import datetime
from typing import Optional, List, Dict, Any


class ContextLevel:
    """上下文层级定义"""
    GLOBAL = "global"
    PROJECT = "project"
    TASK = "task"


class ContextCombiner:
    """上下文组合器"""

    def __init__(self,
                 context_base_dir: str = "/app/templates/context",
                 workspace_dir: str = "/app/volumes/workspace"):
        self.context_base_dir = Path(context_base_dir)
        self.workspace_dir = Path(workspace_dir)

        # 各层级目录
        self.global_dir = self.context_base_dir / ContextLevel.GLOBAL
        self.project_dir = self.context_base_dir / ContextLevel.PROJECT
        self.task_dir = self.context_base_dir / ContextLevel.TASK

        # 项目级上下文也可以放在 workspace 中
        self.project_workspace_dir = self.workspace_dir / ".context"

    def get_context_files(self, level: str, task_id: Optional[str] = None) -> List[Path]:
        """获取指定层级的所有上下文文件"""
        files = []

        if level == ContextLevel.GLOBAL:
            dir_path = self.global_dir
        elif level == ContextLevel.PROJECT:
            # 项目级优先使用 workspace 中的
            dir_path = self.project_workspace_dir if self.project_workspace_dir.exists() else self.project_dir
        elif level == ContextLevel.TASK:
            if task_id:
                dir_path = self.task_dir / task_id
            else:
                dir_path = self.task_dir
        else:
            return files

        if dir_path.exists():
            # 按文件名排序，支持数字前缀排序 (如 01-xxx.md, 02-xxx.md)
            md_files = list(dir_path.glob("*.md"))
            md_files.sort(key=lambda x: x.name)
            files.extend(md_files)

        return files

    def read_context_file(self, file_path: Path) -> Dict[str, Any]:
        """读取上下文文件，支持 Frontmatter"""
        content = file_path.read_text(encoding="utf-8")

        # 解析 Frontmatter（简单实现，不依赖 yaml 库）
        metadata = {
            "source": str(file_path),
            "level": "",
            "priority": 0,
            "enabled": True,
            "tags": []
        }
        body = content

        if content.startswith("---"):
            parts = content.split("---", 2)
            if len(parts) >= 3:
                frontmatter_text = parts[1].strip()
                body = parts[2].strip()

                # 简单解析 YAML frontmatter
                for line in frontmatter_text.split("\n"):
                    line = line.strip()
                    if ":" in line:
                        key, value = line.split(":", 1)
                        key = key.strip()
                        value = value.strip()

                        # 解析不同类型的值
                        if value.startswith("[") and value.endswith("]"):
                            # 列表类型
                            items = value[1:-1].split(",")
                            metadata[key] = [i.strip() for i in items if i.strip()]
                        elif value.lower() == "true":
                            metadata[key] = True
                        elif value.lower() == "false":
                            metadata[key] = False
                        elif value.isdigit():
                            metadata[key] = int(value)
                        else:
                            # 移除引号
                            if (value.startswith('"') and value.endswith('"')) or \
                               (value.startswith("'") and value.endswith("'")):
                                value = value[1:-1]
                            metadata[key] = value

        return {
            "metadata": metadata,
            "content": body
        }

    def combine(self,
                task_id: Optional[str] = None,
                levels: Optional[List[str]] = None,
                tags: Optional[List[str]] = None,
                include_disabled: bool = False) -> str:
        """
        组合所有层级的上下文

        Args:
            task_id: 任务 ID，用于加载任务级上下文
            levels: 要包含的层级，默认全部
            tags: 过滤标签
            include_disabled: 是否包含禁用的上下文

        Returns:
            组合后的上下文文本
        """
        if levels is None:
            levels = [ContextLevel.GLOBAL, ContextLevel.PROJECT, ContextLevel.TASK]

        combined_sections = []

        for level in levels:
            files = self.get_context_files(level, task_id)

            if not files:
                continue

            level_contents = []

            for file_path in files:
                ctx = self.read_context_file(file_path)
                metadata = ctx["metadata"]

                # 跳过禁用的上下文
                if not include_disabled and not metadata.get("enabled", True):
                    continue

                # 标签过滤
                if tags:
                    ctx_tags = metadata.get("tags", [])
                    if not any(t in ctx_tags for t in tags):
                        continue

                # 格式化内容
                title = metadata.get("title", file_path.stem)
                priority = metadata.get("priority", 0)

                level_contents.append({
                    "priority": priority,
                    "title": title,
                    "source": file_path.name,
                    "content": ctx["content"]
                })

            # 按优先级排序
            level_contents.sort(key=lambda x: x["priority"])

            if level_contents:
                level_header = self._get_level_header(level)
                sections = []

                for item in level_contents:
                    sections.append(f"### {item['title']}\n")
                    sections.append(f"> 来源: {item['source']}\n")
                    sections.append(item["content"])
                    sections.append("\n")

                combined_sections.append(f"{level_header}\n\n" + "\n".join(sections))

        return self._format_output(combined_sections, task_id)

    def _get_level_header(self, level: str) -> str:
        """获取层级标题"""
        headers = {
            ContextLevel.GLOBAL: "## 🌐 项目开发规范",
            ContextLevel.PROJECT: "## 📁 项目设计与愿景",
            ContextLevel.TASK: "## 🎯 任务信息"
        }
        return headers.get(level, f"## {level}")

    def _format_output(self, sections: List[str], task_id: Optional[str] = None) -> str:
        """格式化输出"""
        timestamp = datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")

        header = f"""# 📋 组合上下文 (Combined Context)

> 生成时间: {timestamp}
> 任务 ID: {task_id or '未指定'}
>
> 以下内容由上下文组合器自动生成，包含多个层级的上下文信息。
> 请在执行任务时参考这些上下文。

---

"""

        if not sections:
            return header + "_暂无上下文信息_\n"

        return header + "\n---\n\n".join(sections)

    def inject_to_task(self, task_description: str, context: str) -> str:
        """
        将上下文注入到任务描述前

        Args:
            task_description: 原始任务描述
            context: 组合后的上下文

        Returns:
            注入上下文后的完整提示
        """
        separator = "\n\n---\n\n**以下是您的具体任务：**\n\n"

        return context + separator + task_description

    def list_levels(self) -> Dict[str, Any]:
        """列出所有层级的上下文文件"""
        result = {}

        for level in [ContextLevel.GLOBAL, ContextLevel.PROJECT, ContextLevel.TASK]:
            files = self.get_context_files(level)
            result[level] = {
                "directory": str(self.get_context_files(level)[0].parent) if files else "无文件",
                "files": [
                    {
                        "name": f.name,
                        "size": f.stat().st_size,
                        "modified": datetime.fromtimestamp(f.stat().st_mtime).isoformat()
                    }
                    for f in files
                ]
            }

        return result

    def validate(self) -> List[Dict[str, Any]]:
        """验证所有上下文文件"""
        errors = []

        for level in [ContextLevel.GLOBAL, ContextLevel.PROJECT, ContextLevel.TASK]:
            files = self.get_context_files(level)

            for file_path in files:
                try:
                    ctx = self.read_context_file(file_path)

                    # 检查内容是否为空
                    if not ctx["content"].strip():
                        errors.append({
                            "file": str(file_path),
                            "level": level,
                            "error": "内容为空"
                        })

                except Exception as e:
                    errors.append({
                        "file": str(file_path),
                        "level": level,
                        "error": str(e)
                    })

        return errors


def main():
    parser = argparse.ArgumentParser(
        description="上下文组合器 - 层级化上下文管理系统",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
示例:
  # 组合所有层级上下文
  python3 combine_context.py --task-id task-001 --output context.md

  # 只组合全局和项目级
  python3 combine_context.py --levels global,project --output context.md

  # 列出所有上下文文件
  python3 combine_context.py --list-levels

  # 验证上下文文件
  python3 combine_context.py --validate

  # 注入到任务描述
  python3 combine_context.py --task-id task-001 --inject task.md --output combined.md
        """
    )

    parser.add_argument("--context-dir", default="/app/templates/context",
                        help="上下文基础目录")
    parser.add_argument("--workspace-dir", default="/app/volumes/workspace",
                        help="工作区目录")
    parser.add_argument("--task-id", help="任务 ID")
    parser.add_argument("--levels", help="要包含的层级，逗号分隔 (global,project,task)")
    parser.add_argument("--tags", help="过滤标签，逗号分隔")
    parser.add_argument("--output", "-o", help="输出文件路径")
    parser.add_argument("--inject", help="要注入上下文的任务文件")
    parser.add_argument("--list-levels", action="store_true", help="列出所有上下文层级")
    parser.add_argument("--validate", action="store_true", help="验证上下文文件")

    args = parser.parse_args()

    combiner = ContextCombiner(
        context_base_dir=args.context_dir,
        workspace_dir=args.workspace_dir
    )

    # 列出层级
    if args.list_levels:
        result = combiner.list_levels()
        print(json.dumps(result, indent=2, ensure_ascii=False))
        return

    # 验证
    if args.validate:
        errors = combiner.validate()
        if errors:
            print("❌ 发现以下问题：")
            for err in errors:
                print(f"  - [{err['level']}] {err['file']}: {err['error']}")
            sys.exit(1)
        else:
            print("✅ 所有上下文文件验证通过")
            return

    # 解析层级
    levels = None
    if args.levels:
        levels = [l.strip() for l in args.levels.split(",")]

    # 解析标签
    tags = None
    if args.tags:
        tags = [t.strip() for t in args.tags.split(",")]

    # 组合上下文
    context = combiner.combine(
        task_id=args.task_id,
        levels=levels,
        tags=tags
    )

    # 如果需要注入任务
    if args.inject:
        task_path = Path(args.inject)
        if task_path.exists():
            task_content = task_path.read_text(encoding="utf-8")

            # 跳过 frontmatter
            if task_content.startswith("---"):
                parts = task_content.split("---", 2)
                if len(parts) >= 3:
                    frontmatter = parts[1]
                    task_body = parts[2].strip()
                    combined = combiner.inject_to_task(task_body, context)
                    output_content = f"---{frontmatter}---\n\n{combined}"
                else:
                    combined = combiner.inject_to_task(task_content, context)
                    output_content = combined
            else:
                combined = combiner.inject_to_task(task_content, context)
                output_content = combined
        else:
            print(f"❌ 任务文件不存在: {args.inject}", file=sys.stderr)
            sys.exit(1)
    else:
        output_content = context

    # 输出
    if args.output:
        Path(args.output).write_text(output_content, encoding="utf-8")
        print(f"✅ 上下文已写入: {args.output}")
    else:
        print(output_content)


if __name__ == "__main__":
    main()
