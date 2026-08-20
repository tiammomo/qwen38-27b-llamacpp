# OpenAI 兼容 API

默认 Base URL：

```text
http://127.0.0.1:18080/v1
```

模型 ID：

```text
qwen3.8-27b-ud-iq3-xxs
```

这是 llama.cpp 的 OpenAI 兼容接口，不是云端 Qwen 专有 API。当前部署只启用文本输入。

## 健康和模型列表

```bash
curl --fail http://127.0.0.1:18080/health
curl --fail http://127.0.0.1:18080/v1/models | jq
```

## Chat Completions

```bash
curl --fail --silent --show-error \
  http://127.0.0.1:18080/v1/chat/completions \
  -H 'Content-Type: application/json' \
  --data-binary @- <<'JSON'
{
  "model": "qwen3.8-27b-ud-iq3-xxs",
  "messages": [
    {"role": "system", "content": "回答要准确、简洁。"},
    {"role": "user", "content": "解释什么是 KV cache。"}
  ],
  "temperature": 0.6,
  "max_tokens": 512,
  "chat_template_kwargs": {"enable_thinking": false}
}
JSON
```

最终答案位于 `choices[0].message.content`。

## Thinking

按请求开启：

```json
"chat_template_kwargs": {
  "enable_thinking": true
}
```

服务使用 `deepseek` reasoning format，思考内容和最终答案分别出现在：

```text
choices[0].message.reasoning_content
choices[0].message.content
```

Thinking token 计入 completion token；开启 Thinking 后要为 `max_tokens` 留出更多余量。不需要思考
轨迹、只要求结构化输出或极短答案时，建议明确设置 `enable_thinking=false`。

## 流式输出

请求体增加：

```json
"stream": true
```

并使用：

```bash
curl -N http://127.0.0.1:18080/v1/chat/completions ...
```

服务会返回 Server-Sent Events；客户端应逐行处理 `data:` 事件并识别结束事件。

## Python OpenAI SDK

在调用方项目安装 SDK：

```bash
uv add openai
```

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://127.0.0.1:18080/v1",
    api_key="local",  # 默认服务不校验；SDK 要求非空值
)

response = client.chat.completions.create(
    model="qwen3.8-27b-ud-iq3-xxs",
    messages=[
        {"role": "system", "content": "你是一名中文技术助手。"},
        {"role": "user", "content": "介绍一下 llama.cpp。"},
    ],
    temperature=0.6,
    max_tokens=512,
    extra_body={"chat_template_kwargs": {"enable_thinking": False}},
)

print(response.choices[0].message.content)
```

若 `.env` 配置了 `LLAMA_API_KEY`，将示例中的 `local` 换成真实值。curl 请求则增加：

```bash
-H "Authorization: Bearer $LLAMA_API_KEY"
```

不要把真实密钥写入脚本、README 或 Git。

## 上下文和输出边界

- `CTX_SIZE=131072` 是输入、聊天模板、历史消息和输出共享的总预算；
- 日常输入建议控制在 100K–112K tokens；
- 请求显式设置 `max_tokens`，普通请求建议 512–4096；
- Thinking 会额外消耗输出预算；
- 超长请求的处理速度和生成速度都会随上下文增长而下降。

## Docker 客户端注意事项

宿主机程序可直接访问 `127.0.0.1:18080`。另一个 Docker 容器中的 `127.0.0.1` 指向该容器
自身，因此需要加入合适的 Docker 网络或通过受控的宿主机网关访问，不能直接复制宿主机 URL。
