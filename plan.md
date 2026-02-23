# codingAgent MVP 重构计划

## 设计理念

砍掉所有过度工程：session 管理、context 组合器、handover 验证、jsonl 解析、二次总结调用。
只保留核心链路：**接收任务 MD → 启动 claude code → Stop hook 生成报告 → 日志挂载出来**。

## 新架构（4 个核心文件）

```
codingAgent/
├── docker/
│   ├── Dockerfile              # CUDA + Node.js + claude code
│   └── docker-compose.yml      # 容器编排
├── scripts/
│   ├── monitor.sh              # 容器入口：监听任务、启动 claude code
│   └── on-stop-hook.sh         # Stop hook：claude code 结束时生成报告 MD
├── volumes/
│   ├── tasks/                  # planAgent 写入任务 MD（输入）
│   ├── reports/                # hook 生成报告 MD（输出）
│   ├── workspace/              # claude code 工作目录
│   └── logs/                   # ~/.claude/logs/ 挂载出来
└── .env                        # 环境变量
```

## 核心流程

```
planAgent 写入 tasks/task-xxx.md
        ↓
monitor.sh (inotifywait) 检测到新文件
        ↓
读取 MD 内容作为 prompt
        ↓
claude --print --permission-mode bypassPermissions -p "$(cat task.md)"
        ↓
claude code 工作中... (日志写入 ~/.claude/logs/)
        ↓
claude code 结束 → 触发 Stop hook
        ↓
on-stop-hook.sh 读取 stdin JSON，生成 reports/report-xxx.md
        ↓
monitor.sh 将 task 移入 tasks/done/
        ↓
planAgent 读取 reports/ 获取结果
```

## 各文件详细设计

### 1. Dockerfile（精简版）

- 基础镜像：`nvidia/cuda:12.1.0-runtime-ubuntu22.04`
- 安装：Node.js 20、claude-code、inotify-tools、jq、git、tmux
- 去掉：python3、python3-pip、python3-yaml、python3-venv（不再需要 context 组合器）
- 去掉：所有 template 文件复制（AGENT_MISSION、ADR、validate_handover、context 系统）
- 只复制：monitor.sh、on-stop-hook.sh
- 配置 claude code 的 settings.json（内含 Stop hook 配置）到 `/home/node/.claude/settings.json`
- 非 root 用户 node 运行

### 2. docker-compose.yml（精简版）

- 保留：GPU 支持、host 网络模式、代理配置
- 环境变量：ANTHROPIC_BASE_URL、ANTHROPIC_AUTH_TOKEN、ANTHROPIC_MODEL
- volumes 精简为 4 个：
  - `tasks/ → /app/tasks`（任务输入）
  - `reports/ → /app/reports`（报告输出）
  - `workspace/ → /app/workspace`（工作目录）
  - `logs/ → /home/node/.claude/logs`（日志收集）
- 去掉：commands/、sessions/、context/、claude-home/（整个目录）、config/、logs/(app级)

### 3. monitor.sh（~80 行，当前 683 行）

核心逻辑：
```
1. 检查 claude 是否安装
2. 确保目录存在
3. inotifywait 监听 /app/tasks/ 目录
4. 检测到 .md 文件 → 读取内容
5. 从文件名提取 task_id（格式：task-{uuid}.md）
6. 设置环境变量 TASK_ID 供 hook 使用
7. 执行 claude --print --permission-mode bypassPermissions -p "$(cat task.md)"
8. 等待完成，移动 task 到 done/
9. 回到监听
```

去掉的功能：
- session 管理（new/continue/end）
- frontmatter 解析
- context 组合注入
- tmux 包装（直接前台运行 claude）
- jsonl 解析（thinking/tool_use 提取）
- 二次总结调用
- handover 验证

### 4. on-stop-hook.sh（~40 行，新增）

通过 claude code 原生 Stop hook 触发，在 claude code 结束时自动执行：
```
1. 从 stdin 读取 hook JSON（包含 hook_event_name 等）
2. 从环境变量读取 TASK_ID
3. 收集 workspace 的 git diff/status
4. 生成简洁的报告 MD 写入 /app/reports/report-{task_id}.md
5. 报告内容：任务ID、完成时间、状态、git 变更摘要
```

### 5. settings.json（容器内 claude code 配置）

```json
{
  "hooks": {
    "Stop": [{
      "matcher": "*",
      "hooks": [{
        "type": "command",
        "command": "bash /app/scripts/on-stop-hook.sh",
        "timeout": 30
      }]
    }]
  }
}
```

## 删除的文件/目录

- `scripts/container/session.sh` — session 管理
- `scripts/host/extract.sh` — 宿主机报告提取
- `scripts/create-command.sh` — 命令创建辅助
- `scripts/quick-task.sh` — 快速任务
- `scripts/watch.sh` — 监控脚本
- `docker/templates/` — 整个目录（AGENT_MISSION、ADR、validate_handover、.clauderc）
- `docker/context/` — 整个 context 组合系统
- `config/` — settings.json 配置
- `volumes/commands/` — 旧通信目录
- `volumes/sessions/` — session 状态
- `volumes/context/` — context 目录
- `volumes/claude-home/` — 不再挂载整个 .claude 目录，只挂载 logs

## 不变的部分

- GPU 支持（NVIDIA CUDA 基础镜像）
- host 网络模式（代理访问）
- MD 文件通信协议（planAgent ↔ codingAgent）
- bypassPermissions 模式运行
- 环境变量透传（ANTHROPIC_*）

## 实施步骤

1. 创建新的精简目录结构
2. 编写 Dockerfile
3. 编写 docker-compose.yml
4. 编写 monitor.sh
5. 编写 on-stop-hook.sh
6. 创建 .env.example
7. 删除旧文件
