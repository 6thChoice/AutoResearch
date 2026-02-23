---
title: 编码规范
priority: 10
tags: [coding, standards]
enabled: true
---

## 编码规范

### 通用规范

1. **代码风格**
   - 使用有意义的变量名和函数名
   - 保持函数简洁，单一职责
   - 添加必要的注释，特别是复杂逻辑处

2. **文件组织**
   - 相关功能放在同一目录
   - 使用清晰的目录结构
   - 遵循项目的文件命名规范

3. **错误处理**
   - 始终处理可能的错误情况
   - 提供有意义的错误信息
   - 记录错误日志

### Git 提交规范

使用 Conventional Commits 格式：

```
<type>(<scope>): <subject>

<body>

<footer>
```

类型：
- `feat`: 新功能
- `fix`: Bug 修复
- `docs`: 文档更新
- `refactor`: 重构
- `test`: 测试
- `chore`: 构建/工具
