"""LLM 调用封装（OpenAI 兼容接口）"""

import json
import re
from openai import OpenAI

from planAgent.config import LLM_MODEL, LLM_MAX_TOKENS, LLM_BASE_URL, LLM_API_KEY


client = OpenAI(base_url=LLM_BASE_URL, api_key=LLM_API_KEY)


def call(system: str, message: str, model: str = LLM_MODEL) -> str:
    """调用 LLM，返回文本响应"""
    resp = client.chat.completions.create(
        model=model,
        max_tokens=LLM_MAX_TOKENS,
        messages=[
            {"role": "system", "content": system},
            {"role": "user", "content": message},
        ],
    )
    return resp.choices[0].message.content


def call_json(system: str, message: str, model: str = LLM_MODEL) -> dict | list:
    """调用 LLM，从响应中提取 JSON"""
    text = call(system, message, model)
    # 尝试从 ```json ... ``` 代码块提取
    m = re.search(r"```json\s*([\s\S]*?)```", text)
    if m:
        return json.loads(m.group(1))
    # 尝试直接解析
    return json.loads(text)
