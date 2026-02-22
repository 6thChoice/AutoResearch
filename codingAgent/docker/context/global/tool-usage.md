---
title: 工具使用指南
priority: 20
tags: [tools, guide]
enabled: true
---

## 工具使用指南

### Claude Code 工具

1. **Read** - 读取文件
   - 读取前确认文件路径存在
   - 对于大文件使用 offset 和 limit 参数

2. **Write** - 写入文件
   - 必须先读取现有文件
   - 创建新文件时使用

3. **Edit** - 编辑文件
   - 必须先读取文件
   - old_string 必须唯一且精确匹配

4. **Bash** - 执行命令
   - 提供清晰的命令描述
   - 对于可能运行时间长的命令设置 timeout

5. **Grep** - 搜索内容
   - 使用 glob 参数限制搜索范围
   - 支持正则表达式

### 工作区目录

- 工作区: `/app/volumes/workspace`
- 日志目录: `/app/volumes/logs`
- 报告目录: `/app/volumes/reports`
