这份文档旨在指导你如何在 Docker 沙箱环境中构建一套**全维度日志监控体系**。通过结合文件审计、网络拦截和环境变量注入，你将能够捕获 Claude Code 的每一个动作，包括它隐藏的“思考（Thinking）”逻辑。

---

## 🏗️ 方案架构概览

为了获得最全的信息，我们将日志收集分为三个维度：

1. **物理层（文件）**：捕获本地持久化的结构化日志。
2. **传输层（API）**：通过 MITM 捕获模型原始的 `thinking` 块和 `tool_use` 细节。
3. **应用层（环境）**：强制 CLI 输出底层的调试信息。

---

## 第一部分：本地日志挖掘 (Internal Logs)

Claude Code 会在后台静默记录详细的会话状态。

### 1. 定位日志

在 Linux/Docker 环境中，日志通常位于：

* **路径**: `~/.claude/logs/` (即 `/root/.claude/logs/`)
* **格式**: 通常为 JSONL 或纯文本。

### 2. 实现实时外挂

在 `entrypoint.sh` 中添加一个符号链接，将隐藏的日志目录映射到共享卷：

```bash
ln -s /root/.claude/logs /app/volumes/logs/internal_debug

```

**监控技巧**：使用 `jq` 过滤出工具调用的耗时和状态：

```bash
tail -f /root/.claude/logs/*.log | jq 'select(.type=="tool_use") | {tool: .name, input: .input}'

```

---

## 第二部分：API 拦截代理 (Thinking Blocks)

这是获取模型“心路历程”的核心步骤。Claude Code 在 UI 上会精简输出，但 API 响应中包含完整的思考链。

### 1. 配置 mitmproxy

在 Dockerfile 中安装并配置拦截脚本。

**拦截脚本 `parse_thinking.py**`:

```python
import json
from mitmproxy import http

def response(flow: http.HTTPFlow):
    # 只关注 Anthropic API 流量
    if "api.anthropic.com" in flow.request.pretty_url:
        try:
            response_data = json.loads(flow.response.get_text())
            # 提取 Thinking 块 (针对支持思考的模型)
            content = response_data.get("content", [])
            for block in content:
                if block.get("type") == "thinking":
                    log_entry = f"\n[THINKING] {block['thinking']}\n"
                    with open("/app/volumes/logs/ai_thinking.log", "a") as f:
                        f.write(log_entry)
                
                if block.get("type") == "tool_use":
                    with open("/app/volumes/logs/tool_calls.log", "a") as f:
                        f.write(f"[TOOL] {block['name']} -> {block['input']}\n")
        except:
            pass

```

### 2. 注入环境变量

在容器启动时，强制 Node.js 使用该代理：

```bash
# 启动 mitmdump 后台运行
mitmdump -s parse_thinking.py --set keep_host_header=true -p 8080 &

# 设置代理环境
export HTTPS_PROXY=http://127.0.0.1:8080
export http_proxy=http://127.0.0.1:8080

# 关键：跳过 Node.js 的证书验证（仅限内部安全沙箱）
export NODE_TLS_REJECT_UNAUTHORIZED=0

```

---

## 第三部分：环境变量增强 (System Verbose)

通过开关开启 Claude Code 及其底层 Node.js 模块的冗余模式。

### 1. 核心变量配置表

| 变量名 | 取值 | 作用 |
| --- | --- | --- |
| **`CLAUDE_LOG_LEVEL`** | `debug` | 开启 Claude 内部组件的详细日志（状态机转换、任务队列）。 |
| **`DEBUG`** | `claude:*` | 激活 Node.js 的 `debug` 库，输出所有以 `claude:` 开头的模块日志。 |
| **`FORCE_COLOR`** | `1` | 即使在管道或重定向输出中，也强制保留颜色代码，方便后续审计识别。 |

### 2. 启动命令示例

```bash
CLAUDE_LOG_LEVEL=debug DEBUG=claude:* claude --yes "你的指令" 2>&1 | tee /app/volumes/logs/system_trace.log

```

---

## 第四部分：统一日志收集脚本 (Unified Collector)

为了方便调试，你可以运行以下 Python 脚本，它会实时聚合三个渠道的信息并结构化输出到终端。

```python
import subprocess
import os

def start_debug_env():
    print("🚀 启动全维度监控环境...")
    
    # 1. 启动 mitmproxy 捕获思考块
    subprocess.Popen(["mitmdump", "-s", "parse_thinking.py", "-q"], 
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    
    # 2. 设置环境
    env = os.environ.copy()
    env["HTTPS_PROXY"] = "http://127.0.0.1:8080"
    env["NODE_TLS_REJECT_UNAUTHORIZED"] = "0"
    env["CLAUDE_LOG_LEVEL"] = "debug"
    env["DEBUG"] = "claude:*"

    print("🔎 正在监听：ai_thinking.log, tool_calls.log, system_trace.log")
    
    # 3. 运行 Claude
    # 我们使用 -print 配合 verbose 环境，可以获得更纯净的结构化数据
    subprocess.run(["claude", "--yes", "你的任务"], env=env)

if __name__ == "__main__":
    start_debug_env()

```

---

## 📝 调试清单 (Checklist)

* [ ] **检查证书**：如果 `NODE_TLS_REJECT_UNAUTHORIZED=0` 不起作用，请确保 mitmproxy 的证书已安装到容器的 `ca-certificates` 中。
* [ ] **性能影响**：`mitmdump` 对 API 响应有毫秒级延迟，通常不影响 Agent 逻辑。
* [ ] **磁盘空间**：`debug` 级别日志增长极快，建议将 `/app/volumes/logs` 挂载到宿主机的 SSD。