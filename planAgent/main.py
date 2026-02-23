"""Plan Agent 入口"""

import sys
from planAgent.core.orchestrator import Orchestrator


def main():
    if len(sys.argv) > 1:
        goal = " ".join(sys.argv[1:])
    else:
        goal = input("请输入项目目标: ").strip()
        if not goal:
            print("目标不能为空")
            sys.exit(1)

    orchestrator = Orchestrator()
    orchestrator.run(goal)


if __name__ == "__main__":
    main()
