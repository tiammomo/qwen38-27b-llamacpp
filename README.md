# Qwen3.8 27B / llama.cpp 本地推理服务

[![validate](https://github.com/tiammomo/qwen38-27b-llamacpp/actions/workflows/validate.yml/badge.svg)](https://github.com/tiammomo/qwen38-27b-llamacpp/actions/workflows/validate.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

使用 llama.cpp CUDA 和 Docker Compose 在单张 NVIDIA GPU 上运行
`Qwen3.8-27B-UD-IQ3_XXS.gguf`，提供 OpenAI 兼容的文本 API。

本项目面向 RTX 5070 Ti 16GB 调优，默认使用 128K context、单并发、Q4 KV cache 和全 GPU
offload。模型、GGUF revision、文件哈希与容器镜像摘要均已固定，适合作为本机其他项目和可信
局域网设备共用的长期推理服务。

## 主要特性

- OpenAI 兼容的 `/v1/chat/completions` 与 `/v1/models` 接口；
- 经过本机验证的 128K 长上下文配置；
- 自动下载、断点续传、文件大小与 SHA-256 校验；
- Docker 健康检查、自动重启、日志轮转和 GPU 状态检查；
- 默认仅监听回环地址，局域网模式强制启用 Bearer API Key；
- 容器只读根文件系统、丢弃 Linux capabilities，并以非 root 用户运行；
- 文本推理专用，默认关闭多模态投影。

## 运行配置

| 项目 | 默认值 |
| --- | --- |
| 模型 ID | `qwen3.8-27b-ud-iq3-xxs` |
| 本机 Base URL | `http://127.0.0.1:18080/v1` |
| Context | `131072` |
| 并发槽位 | `1` |
| 单次最大生成 | `4096` tokens |
| KV cache | `q4_0` |
| GPU offload | 全部模型层 |
| API 类型 | OpenAI Compatible / 文本 |

仓库模板默认使用 `127.0.0.1` 且不启用认证。本机当前部署已经启用局域网模式：

| 项目 | 当前值 |
| --- | --- |
| 局域网 Base URL | `http://192.168.31.114:18080/v1` |
| 监听地址 | `0.0.0.0:18080` |
| API Key | 已启用，仅保存在本机 `.env` |
| 防火墙来源 | `192.168.31.0/24` |

当前部署无论从本机还是局域网调用，都必须使用真实 API Key，不能再使用 `local` 占位值。

## 前置条件

- Linux 或 WSL2 x86_64；
- NVIDIA GPU 与可用驱动；
- Docker Engine、Docker Compose v2 和 NVIDIA Container Runtime；
- `curl`、`jq`、`flock`、`sha256sum`；
- 首次下载约需 11GB 网络流量和磁盘空间；
- Python 3.11+，用于静态检查、访问配置和长上下文基准。

宿主机不需要安装 CUDA Toolkit、CMake 或 C++ 编译器。

## 快速开始

```bash
git clone git@github.com:tiammomo/qwen38-27b-llamacpp.git
cd qwen38-27b-llamacpp

test -f .env || cp .env.example .env
chmod 600 .env

./scripts/start.sh
./scripts/smoke-test.sh
```

`start.sh` 会依次完成环境预检、端口检查、模型下载或完整性校验、容器启动和健康等待。首次下载
支持断点续传；已存在且校验通过的模型不会重复下载。

单独验证模型文件：

```bash
./scripts/download-model.sh --verify-only
```

## API 调用

### 客户端参数

```dotenv
QWEN_BASE_URL=http://127.0.0.1:18080/v1
QWEN_API_KEY=服务端配置的真实密钥
QWEN_MODEL=qwen3.8-27b-ud-iq3-xxs
```

局域网另一台机器将 `QWEN_BASE_URL` 改为：

```dotenv
QWEN_BASE_URL=http://192.168.31.114:18080/v1
```

### Python OpenAI SDK

```python
import os

from openai import OpenAI

client = OpenAI(
    base_url=os.environ["QWEN_BASE_URL"],
    api_key=os.environ["QWEN_API_KEY"],
)

response = client.chat.completions.create(
    model=os.environ.get("QWEN_MODEL", "qwen3.8-27b-ud-iq3-xxs"),
    messages=[{"role": "user", "content": "用一句话介绍你自己。"}],
    temperature=0.6,
    max_tokens=512,
    extra_body={"chat_template_kwargs": {"enable_thinking": False}},
)

print(response.choices[0].message.content)
```

不要把真实 API Key 写进源码、README、日志或 Git。Thinking、流式输出、curl 和响应字段说明见
[API 指南](docs/API.md)。

## 局域网访问

在可信局域网中启用非回环监听：

```bash
./scripts/configure-access.py lan
./scripts/start.sh
./scripts/smoke-test.sh
```

`configure-access.py` 会在密钥为空时生成随机 API Key，并安全写入权限为 `0600` 的 `.env`，不会
回显密钥。它不会自动修改 Windows、Linux、路由器或云防火墙。

恢复仅本机监听：

```bash
./scripts/configure-access.py local
./scripts/start.sh
./scripts/smoke-test.sh
```

恢复回环监听时会保留已有 API Key，避免意外中断现有调用方。WSL mirrored networking、Hyper-V
firewall、另一台机器验证方法和 Docker 项目接入示例见 [接入指南](docs/INTEGRATION.md)。

## 启停与运维

```bash
# 启动或应用 .env 变更，并等待服务健康
./scripts/start.sh

# 验证健康、模型列表和一次实际推理
./scripts/smoke-test.sh

# 查看容器、API 健康和 GPU 显存
./scripts/status.sh

# 跟踪日志；Ctrl+C 只结束查看
docker compose logs --follow --tail=100

# 停止并删除容器和项目网络
./scripts/stop.sh
```

`stop.sh` 不会删除模型、CUDA cache、镜像或 `.env`。容器使用 `restart: unless-stopped`，Docker
恢复后会自动尝试拉起。

仅临时暂停且保留容器：

```bash
docker compose stop
docker compose start
```

修改 `.env` 后应执行 `./scripts/start.sh`。`docker compose restart` 不会重新读取 Compose 配置。

## 性能边界

当前 16GB 显存配置推荐保持：

```dotenv
CTX_SIZE=131072
PARALLEL=1
CACHE_TYPE_K=q4_0
CACHE_TYPE_V=q4_0
BATCH_SIZE=512
UBATCH_SIZE=128
```

本机 120K token needle-retrieval 基准通过，prompt 处理约 `705 tok/s`，生成约 `11.72 tok/s`。
256K 虽可加载，但显存余量和速度都不适合长期服务。

日常输入建议控制在 100K–112K tokens，为系统提示、聊天模板、工具消息和输出预留空间。若更
重视并发，应先把 context 降至 32K/64K 后重新测试，不要直接在 128K 下把 `PARALLEL` 提高到 2。
完整记录见 [128K 与 256K 上下文对比](docs/context-benchmark-2026-08-20.md)。

## 固定制品

| 制品 | 固定值 |
| --- | --- |
| 基础模型 | `Qwen/Qwen3.8-27B` |
| GGUF 仓库 | `unsloth/Qwen3.8-27B-GGUF` |
| GGUF 文件 | `Qwen3.8-27B-UD-IQ3_XXS.gguf` |
| GGUF revision | `27af057ecb382ddfea5d12837360a8980560e3ed` |
| 文件大小 | `10,934,860,704` bytes |
| SHA-256 | `c0b7c3038681ed2e3040456c1dd45f9858b6c2290bed172c70388a94874f3eee` |
| llama.cpp | CUDA server build `10524`，commit `9ee9fc04c` |

下载、校验和 Compose 共用 `.env` 中的制品元数据。更换模型时必须同时更新仓库、revision、
文件名、大小、SHA-256、服务模型 ID、文档和测试预期。

## 安全边界

- 默认回环监听适合可信的单用户本机；
- 非回环监听必须配置 API Key 和限制来源地址的防火墙；
- 当前局域网直连使用 HTTP，Bearer token 与请求内容没有 TLS 加密；
- 不要在路由器上把 `18080` 映射到公网；
- 公网、不可信 Wi-Fi、敏感数据或多用户场景应增加 TLS、访问控制、限流与审计；
- 当前 CORS 仅允许 localhost，远程网页前端应通过受控后端代理调用。

## 文档

- [API 调用](docs/API.md)
- [配置说明](docs/CONFIGURATION.md)
- [其他项目与局域网接入](docs/INTEGRATION.md)
- [启停、监控与故障排查](docs/OPERATIONS.md)
- [性能与质量优化路线图](docs/ROADMAP.md)
- [第三方组件与许可证](docs/THIRD_PARTY.md)

## 验证

```bash
./scripts/check.sh
./scripts/preflight.sh
./scripts/smoke-test.sh
```

`check.sh` 会检查 Bash/Python 语法、ShellCheck（若本机已安装）、Compose 配置和 Git whitespace；
GitHub Actions 会强制安装并运行 ShellCheck。

## License

项目自产脚本和文档采用 [MIT License](LICENSE)。模型、GGUF 和容器镜像遵循各自许可证，详情见
[第三方说明](docs/THIRD_PARTY.md)。
