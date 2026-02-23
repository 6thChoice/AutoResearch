"""Plan Agent 配置"""

from pathlib import Path

# CodingAgent volumes 路径
CODING_AGENT_ROOT = Path(__file__).parent.parent / "codingAgent"
TASKS_DIR = CODING_AGENT_ROOT / "volumes" / "tasks"
TASKS_DONE_DIR = TASKS_DIR / "done"
REPORTS_DIR = CODING_AGENT_ROOT / "volumes" / "reports"
WORKSPACE = CODING_AGENT_ROOT / "volumes" / "workspace"

# 超时与重试
REPORT_POLL_INTERVAL = 5        # 轮询间隔（秒）
REPORT_TIMEOUT = 1800           # 单任务超时（秒），与 codingAgent 的 30 分钟对齐
MAX_RETRIES = 3                 # 单步骤最大重试次数
MAX_CONSECUTIVE_FAILURES = 3    # 连续失败触发人工介入

# LLM 配置
LLM_BASE_URL = "https://api.deepseek.com/v1"
LLM_API_KEY = "sk-ec0b934f34bc45e8879e8301c9b7907d"
LLM_MODEL = "deepseek-reasoner"
LLM_MAX_TOKENS = 4096
