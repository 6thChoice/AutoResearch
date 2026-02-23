# 指令文档格式规范

本文档定义了向 Claude Code 容器发送指令的 Markdown 文档格式。

## 文件命名

建议使用以下命名格式：
```
<timestamp>-<id>.md
例如: 20260221-100001-cmd001.md
```

## 文档结构

```markdown
---
id: <uuid>
created_at: <timestamp>
session_id: <会话ID>
command_type: <new|continue|end>
---

# 指令标题

## 任务描述
<详细描述>

## 约束条件
- <可选条件>

## 预期输出
- <预期内容>
```

## Frontmatter 字段说明

| 字段 | 必填 | 说明 |
|------|------|------|
| `id` | 是 | 指令唯一标识符，建议使用 UUID |
| `created_at` | 是 | 创建时间，ISO 8601 格式 (如 `2026-02-21T10:00:00Z`) |
| `session_id` | 是 | 会话 ID。新会话使用 `auto`，继续会话使用具体 ID |
| `command_type` | 是 | 指令类型：`new`、`continue`、`end` |

## 指令类型详解

### new - 创建新会话

用于启动一个新的 Claude Code 会话。

```markdown
---
id: cmd-001
created_at: 2026-02-21T10:00:00Z
session_id: auto
command_type: new
---

# 创建新项目

## 任务描述
请在 workspace 目录下创建一个新的 Node.js 项目，包含以下内容：
1. 初始化 package.json
2. 创建基本的目录结构
3. 添加 TypeScript 配置

## 预期输出
- package.json 文件
- tsconfig.json 文件
- src/ 目录
```

### continue - 继续会话

在现有会话中继续对话，Claude Code 会保持上下文。

```markdown
---
id: cmd-002
created_at: 2026-02-21T10:05:00Z
session_id: <从上次报告获取的 session_id>
command_type: continue
---

# 继续开发

## 任务描述
基于之前的设置，请添加一个简单的 HTTP 服务器实现。

## 约束条件
- 使用 Express 框架
- 监听 3000 端口
```

### end - 结束会话

标记当前会话结束。

```markdown
---
id: cmd-003
created_at: 2026-02-21T10:10:00Z
session_id: <session_id>
command_type: end
---

# 结束会话

## 任务描述
任务已完成，请结束当前会话。
```

## 最佳实践

1. **任务描述清晰**：提供具体、可执行的指令
2. **合理使用会话**：相关任务放在同一会话中
3. **及时结束会话**：完成的任务及时发送 `end` 指令
4. **UUID 生成**：
   ```bash
   # Linux
   uuidgen

   # 或使用 Python
   python3 -c "import uuid; print(str(uuid.uuid4()))"
   ```

## 示例脚本

### 创建新指令

```bash
#!/bin/bash
SESSION_ID="${1:-auto}"
COMMAND_ID=$(uuidgen)
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

cat > volumes/commands/pending/cmd-${COMMAND_ID:0:8}.md << EOF
---
id: ${COMMAND_ID}
created_at: ${TIMESTAMP}
session_id: ${SESSION_ID}
command_type: new
---

# 新任务

## 任务描述
$2
EOF

echo "Command created: cmd-${COMMAND_ID:0:8}.md"
```
