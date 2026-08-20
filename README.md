# Qwen3.8 27B / llama.cpp 本地推理服务

在单张 NVIDIA GPU 上通过 llama.cpp CUDA server 运行
`Qwen3.8-27B-UD-IQ3_XXS.gguf`，提供仅监听本机回环地址的 OpenAI 兼容文本 API。

本项目是当前主推理服务。默认面向 RTX 5070 Ti 16GB：128K context、单并发、Q4 KV
cache、全部模型层 GPU offload。默认 API 地址为：

```text
http://127.0.0.1:18080/v1
```

## 固定制品

- 基础模型：`Qwen/Qwen3.8-27B`，Apache-2.0。
- GGUF：`unsloth/Qwen3.8-27B-GGUF`。
- 文件：`Qwen3.8-27B-UD-IQ3_XXS.gguf`，10,934,860,704 字节。
- GGUF revision：`27af057ecb382ddfea5d12837360a8980560e3ed`。
- SHA-256：`c0b7c3038681ed2e3040456c1dd45f9858b6c2290bed172c70388a94874f3eee`。
- llama.cpp：官方 CUDA 镜像 build `10524`、commit `9ee9fc04c`，镜像固定到摘要。

下载脚本、模型校验和 Compose 共用 `.env` 中的制品元数据，避免在多个脚本中分别维护。
模型与第三方组件的许可证边界见 [第三方说明](docs/THIRD_PARTY.md)。

## 前置条件

- Linux/WSL2 x86_64 和 NVIDIA GPU/驱动；
- Docker Engine、Docker Compose v2、NVIDIA Container Runtime；
- `curl`、`jq`、util-linux `flock`、`sha256sum`；
- 首次下载约需 11GB 网络流量和磁盘空间；
- Python 3.11+ 仅用于长上下文 benchmark 和静态检查。

项目不要求在宿主机编译 llama.cpp，因此不需要 CMake、CUDA Toolkit 或 C++ 编译器。

## 首次启动

```bash
cd /home/tiammomo/projects/infra/qwen38-27b-llamacpp
test -f .env || cp .env.example .env
chmod 600 .env
./scripts/start.sh
./scripts/smoke-test.sh
```

`start.sh` 会执行环境和端口预检、断点续传或全量模型校验，然后启动容器并等待其进入
`healthy`。模型损坏时脚本会拒绝覆盖；请先人工检查文件，再决定是否删除并重新下载。

单独校验现有模型：

```bash
./scripts/download-model.sh --verify-only
```

## 日常运维

```bash
# 容器状态、健康状态和 GPU 显存
./scripts/status.sh

# 日志；Ctrl+C 只退出日志查看
docker compose logs --follow --tail=100

# 停止并删除容器/网络，不删除模型、缓存、镜像或 .env
./scripts/stop.sh
```

只临时停止并保留容器：

```bash
docker compose stop
docker compose start
```

修改 `.env` 后执行 `./scripts/start.sh`，让 Compose 根据新配置重建容器。不要只运行
`docker compose restart`，因为 restart 不会重新读取并应用 Compose 变化。

完整运维和故障排查见 [运维指南](docs/OPERATIONS.md)。

## API 快速调用

```bash
curl --fail --silent --show-error \
  http://127.0.0.1:18080/v1/chat/completions \
  -H 'Content-Type: application/json' \
  --data-binary @- <<'JSON'
{
  "model": "qwen3.8-27b-ud-iq3-xxs",
  "messages": [
    {"role": "system", "content": "你是一名严谨的中文技术助手。"},
    {"role": "user", "content": "用一句话介绍你自己。"}
  ],
  "temperature": 0.6,
  "max_tokens": 512,
  "chat_template_kwargs": {"enable_thinking": false}
}
JSON
```

客户端配置：

| 字段 | 默认值 |
| --- | --- |
| Provider | OpenAI Compatible |
| Base URL | `http://127.0.0.1:18080/v1` |
| API Key | 默认未启用；客户端强制要求时可填 `local` |
| Model | `qwen3.8-27b-ud-iq3-xxs` |
| Context | `131072` |
| 建议单次最大输出 | `4096` |

Python、流式输出、Thinking 和 API Key 用法见 [API 指南](docs/API.md)。其他本机项目、Docker
项目和局域网机器的完整接入步骤见 [接入指南](docs/INTEGRATION.md)。

## 配置原则

编辑 `.env` 后重新运行启动与 smoke test：

```bash
./scripts/start.sh
./scripts/smoke-test.sh
```

日常请求建议把输入控制在 100K–112K tokens 内，为系统提示、聊天模板、工具消息和回复
预留空间。当前 16GB GPU 不建议把 128K 提升到 256K，也不建议在保持 128K 的同时把
`PARALLEL` 提高到 2。实测数据见
[128K 与 256K 上下文对比](docs/context-benchmark-2026-08-20.md)。

所有环境变量、API Key 和远程访问安全规则见 [配置指南](docs/CONFIGURATION.md)。

## 验证与开发

```bash
./scripts/check.sh
./scripts/preflight.sh
./scripts/smoke-test.sh
```

`check.sh` 执行 Bash/Python 语法、可选 ShellCheck、Compose 配置和 Git whitespace 检查；
CI 会强制安装并运行 ShellCheck。后续质量、工具调用和并发验证计划见
[优化路线图](docs/ROADMAP.md)。

## 安全边界

- 默认只监听 `127.0.0.1`，没有 API Key；适用于可信单用户本机。
- 非回环监听时，预检要求配置 `LLAMA_API_KEY`，但这仍不能替代 TLS、反向代理、限流和防火墙。
- 容器为只读根文件系统、丢弃全部 capabilities、启用 `no-new-privileges`，模型目录只读挂载。
- 默认 `--no-mmproj`，不提供图片、音频或视频输入。

项目自产脚本和文档采用 [MIT License](LICENSE)；模型、GGUF 和容器镜像遵循各自许可证。
