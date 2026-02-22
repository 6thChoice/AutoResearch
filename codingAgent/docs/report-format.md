# 报告文档格式规范

本文档定义了 Claude Code 容器生成的执行报告的 Markdown 文档格式。

## 文件命名

报告文件命名格式：
```
report-<command_id>.md
例如: report-cmd-001.md
```

## 文档结构

```markdown
---
command_id: <关联的指令ID>
session_id: <会话ID>
created_at: <timestamp>
status: <success|failed|partial|waiting_input>
---

# 执行报告

## 执行摘要
<任务完成情况概述>

## 执行详情
<详细的执行过程和结果>

## 会话状态
- 当前轮次: <N>
- 等待继续: <是/否>
- 下一步建议: <如有>

## 日志
<相关日志信息>

## 文件变更
<文件变更清单>
```

## Frontmatter 字段说明

| 字段 | 说明 |
|------|------|
| `command_id` | 关联的原始指令 ID |
| `session_id` | 执行此任务的会话 ID（用于 continue） |
| `created_at` | 报告生成时间 |
| `status` | 执行状态 |

## 状态类型

| 状态 | 说明 |
|------|------|
| `success` | 任务成功完成 |
| `failed` | 任务执行失败 |
| `partial` | 部分完成 |
| `waiting_input` | 等待用户输入 |

## 报告示例

### 成功报告

```markdown
---
command_id: cmd-001
session_id: a1b2c3d4-e5f6-7890-abcd-ef1234567890
created_at: 2026-02-21T10:02:30Z
status: success
---

# 执行报告

## 执行摘要
成功创建了一个新的 Node.js 项目，包含基本配置文件和目录结构。

## 执行详情
1. 初始化了 package.json，设置项目名称为 "my-project"
2. 创建了 tsconfig.json，配置了 TypeScript 编译选项
3. 创建了 src/ 目录和 index.ts 入口文件
4. 安装了必要的开发依赖：typescript, @types/node

## 会话状态
- 当前轮次: 1
- 等待继续: 是
- 下一步建议: 可以继续添加更多功能代码

## 日志
```
$ npm init -y
$ npm install -D typescript @types/node
$ npx tsc --init
```

## 文件变更
- A  package.json
- A  package-lock.json
- A  tsconfig.json
- A  src/index.ts
```

### 失败报告

```markdown
---
command_id: cmd-002
session_id: a1b2c3d4-e5f6-7890-abcd-ef1234567890
created_at: 2026-02-21T10:05:15Z
status: failed
---

# 执行报告

## 执行摘要
任务执行失败，缺少必要的 API 密钥配置。

## 执行详情
尝试创建 HTTP 服务器时，由于缺少环境变量配置，服务启动失败。

错误信息：
Error: ANTHROPIC_API_KEY is not set

## 会话状态
- 当前轮次: 2
- 等待继续: 是
- 下一步建议: 请配置 ANTHROPIC_API_KEY 环境变量后重试

## 日志
```
Error: ANTHROPIC_API_KEY is not set
    at validateConfig (/app/node_modules/...)
```

## 文件变更
无
```

## 解析报告

### 提取摘要

```bash
awk '
    /^## 执行摘要/ { in_summary=1; next }
    in_summary && /^## / { exit }
    in_summary && NF { print }
' report.md
```

### 提取状态

```bash
awk '
    /^---$/ { in_fm++; next }
    in_fm == 1 && /^status:/ {
        sub(/^status:[[:space:]]*/, "")
        print
        exit
    }
' report.md
```

### 提取 Session ID

```bash
awk '
    /^---$/ { in_fm++; next }
    in_fm == 1 && /^session_id:/ {
        sub(/^session_id:[[:space:]]*/, "")
        print
        exit
    }
' report.md
```

## 宿主机日志格式

当宿主机监控脚本检测到新报告时，会记录以下格式的日志：

```
[2026-02-21T10:02:31Z] [INFO] === Processing report: report-cmd-001.md ===
[2026-02-21T10:02:31Z] [INFO] Report: report-cmd-001.md | Status: success | Session: a1b2c3d4-...
[2026-02-21T10:02:31Z] [INFO] Summary: 成功创建了一个新的 Node.js 项目...
[2026-02-21T10:02:31Z] [INFO] Report archived to: reports/archived/report-cmd-001.md
```
