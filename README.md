# Qwen3.8 27B UD-IQ3_XXS / llama.cpp

在单张 NVIDIA GPU 上用 llama.cpp CUDA server 运行 `Qwen3.8-27B-UD-IQ3_XXS.gguf`，提供 OpenAI 兼容 API。

## 固定版本

- 基础模型：`Qwen/Qwen3.8-27B`，Apache-2.0。
- GGUF：`unsloth/Qwen3.8-27B-GGUF`。
- 文件：`Qwen3.8-27B-UD-IQ3_XXS.gguf`。
- 仓库修订：`27af057ecb382ddfea5d12837360a8980560e3ed`。
- 大小：`10,934,860,704` 字节。
- SHA-256：`c0b7c3038681ed2e3040456c1dd45f9858b6c2290bed172c70388a94874f3eee`。
- llama.cpp：官方 CUDA 镜像摘要 `sha256:ea610f2c82d033b6765b24fa7c0ab15c267d564f883de7c494f1e3073d496374`，build `10524`（commit `9ee9fc04c`）。

默认只启用文本输入，不加载多模态 projector，以便在 16GB 显存上留出 KV cache 和 CUDA 运行余量。

## 启动

```bash
./scripts/start.sh
./scripts/smoke-test.sh
```

下载支持断点续传；只有大小和 SHA-256 同时匹配后，临时文件才会变成正式模型文件。

服务仅监听宿主机回环地址：

```text
http://127.0.0.1:18081/v1
```

OpenAI 兼容调用示例：

```bash
curl http://127.0.0.1:18081/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "qwen3.8-27b-ud-iq3-xxs",
    "messages": [{"role": "user", "content": "用一句话介绍你自己"}],
    "max_tokens": 256,
    "temperature": 0.6
  }'
```

## 运维

```bash
./scripts/status.sh
docker compose logs --follow --tail=100
./scripts/stop.sh
```

可在 `.env` 中调整端口、上下文和 batch。默认配置针对 RTX 5070 Ti 16GB：128K context（131072 tokens）、单并发、Q4 KV cache、全部模型层 GPU offload。日常请求建议将输入控制在 100K–112K 内，为回复、系统提示和工具消息保留余量。

128K 与 256K 的实机长上下文对比见 [`docs/context-benchmark-2026-08-20.md`](docs/context-benchmark-2026-08-20.md)。
