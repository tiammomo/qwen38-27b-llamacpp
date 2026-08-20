# 配置指南

运行配置位于项目根目录的 `.env`。该文件不进入 Git；`.env.example` 是无密钥模板。

首次部署：

```bash
test -f .env || cp .env.example .env
chmod 600 .env
```

预检要求 `.env` 不可被 group/others 读取，以保护将来可能配置的 API Key。

## 制品身份

| 变量 | 说明 |
| --- | --- |
| `LLAMA_IMAGE` | llama.cpp CUDA 镜像，必须固定到 SHA-256 digest |
| `MODEL_REPOSITORY` | Hugging Face GGUF 仓库，格式为 `owner/repository` |
| `MODEL_REVISION` | 不可变 revision，不接受分支名或 `main` |
| `MODEL_FILE` | `models/` 下的 GGUF 文件名 |
| `MODEL_SIZE_BYTES` | 下载完成后要求的精确字节数 |
| `MODEL_SHA256` | 下载完成后要求的 SHA-256 |
| `SERVED_MODEL_ID` | `/v1/models` 和请求体 `model` 使用的别名 |

这些字段同时供下载、校验和 Compose 使用。更换模型时必须作为一个整体审查和更新，不能只替换
`MODEL_FILE`。

## 网络和认证

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `BIND_ADDRESS` | `127.0.0.1` | 宿主机监听地址 |
| `PUBLISH_PORT` | `18080` | 宿主机端口 |
| `LLAMA_API_KEY` | 空 | 可选 Bearer token；只保存在 `.env` |

默认仅允许本机访问。若客户端强制要求 API Key，但服务仍为默认无认证模式，客户端可以填任意
占位值，例如 `local`。

启用服务端认证：

```dotenv
LLAMA_API_KEY=请替换为足够长的随机值
```

请求增加：

```text
Authorization: Bearer 请替换为相同值
```

非 `127.0.0.1` 监听会被预检拒绝，除非同时设置 API Key。可信局域网可以在严格限制来源地址的
防火墙后直连；公网、不可信网络或包含敏感数据的请求仍应使用 TLS、访问控制和限流，不能直接
暴露 llama.cpp 端口。

本项目提供不会回显密钥的切换命令：

```bash
# 启用局域网监听；LLAMA_API_KEY 为空时自动生成 64 位十六进制密钥
./scripts/configure-access.py lan

# 恢复仅本机监听；为避免意外破坏调用方，已有密钥会保留
./scripts/configure-access.py local
```

切换后必须运行 `./scripts/start.sh` 和 `./scripts/smoke-test.sh`。局域网模式还必须配置宿主机
防火墙；脚本不会自动更改 Windows、路由器或云防火墙。

本机当前局域网地址、WSL Hyper-V firewall 和远程客户端配置见
[其他项目与局域网机器接入指南](INTEGRATION.md)。

## 推理参数

| 变量 | 默认值 | 调整建议 |
| --- | ---: | --- |
| `CTX_SIZE` | `131072` | 当前 16GB GPU 已验证上限；可降低到 65536/32768 节省显存 |
| `N_PREDICT` | `4096` | 服务端生成长度配置；请求仍应显式设置 `max_tokens` |
| `PARALLEL` | `1` | 并发槽位；提高前先降低上下文并重新做显存与质量测试 |
| `GPU_LAYERS` | `all` | 全 GPU offload；CPU offload 会显著改变性能 |
| `CACHE_TYPE_K/V` | `q4_0` | 长上下文的显存优先方案；更高精度会增加显存占用 |
| `BATCH_SIZE` | `512` | Prompt 逻辑 batch；过大可能增加峰值显存 |
| `UBATCH_SIZE` | `128` | 物理 batch，必须不大于 `BATCH_SIZE` |
| `THREADS` | `8` | 常规 CPU 线程 |
| `THREADS_BATCH` | `16` | Prompt batch CPU 线程 |
| `START_TIMEOUT_SECONDS` | `600` | `start.sh` 等待容器健康的最长时间 |

当前显存边界下，推荐保留 `CTX_SIZE=131072` 和 `PARALLEL=1`。若更重视并发而不是单请求长
上下文，应先把上下文降到 32K/64K，再分别执行 smoke test 和业务基准。

## 容器用户

`start.sh` 默认把当前 Linux 用户的 UID/GID 传给容器。需要显式覆盖时，可在 `.env` 增加：

```dotenv
RUNTIME_UID=1000
RUNTIME_GID=1000
```

修改任何配置后执行：

```bash
./scripts/start.sh
./scripts/smoke-test.sh
```
