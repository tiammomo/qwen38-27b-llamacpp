# 其他项目与局域网机器接入指南

## 当前地址与状态

截至 2026-08-20，本机局域网 IPv4 地址为：

```text
192.168.31.114/24
```

默认网关为 `192.168.31.1`。Windows 和 WSL 当前使用 mirrored networking，WSL 的 `eth1`
也显示 `192.168.31.114`。微软说明 mirrored mode 支持从局域网直接连接 WSL 服务，但服务本身
必须监听非回环地址，并受 Hyper-V firewall 控制：
[WSL 网络官方说明](https://learn.microsoft.com/en-us/windows/wsl/networking)。

当前 Qwen 服务已按用户确认启用可信局域网访问：

```text
BIND_ADDRESS=0.0.0.0
PUBLISH_PORT=18080
LLAMA_API_KEY=已配置，不在文档或终端中显示
```

Windows Hyper-V firewall 规则 `QwenLlamaCpp18080` 只放行 TCP `18080`，来源范围为
`192.168.31.0/24`。同一子网内的可信机器可以通过 `192.168.31.114:18080` 访问；路由器不得
配置公网端口转发。

路由器通过 DHCP 分配的地址可能变化。若要长期接入，应在路由器中为本机设置 DHCP 地址保留，
固定为 `192.168.31.114`，或者为调用方配置可解析且稳定的内网主机名。

## 接入参数总表

| 场景 | Base URL | API Key |
| --- | --- | --- |
| 本机普通进程 | `http://127.0.0.1:18080/v1` | 当前必须使用真实 API Key |
| 本机另一 Docker 项目 | `http://llama-server:8080/v1` | 与服务端配置一致 |
| 局域网另一台机器 | `http://192.168.31.114:18080/v1` | 必须配置真实 API Key |

所有场景的模型 ID 都是：

```text
qwen3.8-27b-ud-iq3-xxs
```

## 本机另一个项目接入

### 项目直接运行在宿主机/WSL

在调用方项目自己的本地 `.env` 中配置：

```dotenv
QWEN_BASE_URL=http://127.0.0.1:18080/v1
QWEN_API_KEY=从服务端 .env 安全复制的真实密钥
QWEN_MODEL=qwen3.8-27b-ud-iq3-xxs
```

不要把调用方的真实 API Key 提交到 Git。

Python OpenAI SDK：

```python
import os

from openai import OpenAI

client = OpenAI(
    base_url=os.environ["QWEN_BASE_URL"],
    api_key=os.environ["QWEN_API_KEY"],
)

response = client.chat.completions.create(
    model=os.environ["QWEN_MODEL"],
    messages=[{"role": "user", "content": "你好，请介绍一下你自己。"}],
    max_tokens=512,
    extra_body={"chat_template_kwargs": {"enable_thinking": False}},
)

print(response.choices[0].message.content)
```

Node.js OpenAI SDK：

```javascript
import OpenAI from "openai";

const client = new OpenAI({
  baseURL: process.env.QWEN_BASE_URL,
  apiKey: process.env.QWEN_API_KEY,
});

const response = await client.chat.completions.create({
  model: process.env.QWEN_MODEL,
  messages: [{ role: "user", content: "你好，请介绍一下你自己。" }],
  max_tokens: 512,
  chat_template_kwargs: { enable_thinking: false },
});

console.log(response.choices[0].message.content);
```

### 调用方也在 Docker Compose 中

容器中的 `127.0.0.1` 指向调用方容器自己，不能使用宿主机 URL。可把调用方服务加入现有的
Qwen Docker 网络：

```yaml
services:
  app:
    # image/build 等其他配置略
    environment:
      QWEN_BASE_URL: http://llama-server:8080/v1
      QWEN_API_KEY: ${QWEN_API_KEY:-local}
      QWEN_MODEL: qwen3.8-27b-ud-iq3-xxs
    networks:
      - qwen_api

networks:
  qwen_api:
    external: true
    name: qwen38-27b-llamacpp_default
```

先启动 Qwen 项目，让该网络存在，再启动调用方项目。调用方容器连接该网络期间，Qwen 项目的
`docker compose down` 可能无法删除网络；需要先停止或断开调用方容器。对于长期、多项目接入，
可后续把它改为独立、稳定的外部网络。

## 局域网另一台机器直连

该方式仅适用于可信局域网，不要在路由器上设置公网端口转发。步骤需要在服务端和 Windows
管理员 PowerShell 中分别完成。

### 1. 确认另一台机器位于允许的子网

例如：

```text
192.168.31.50
```

本机当前规则允许整个可信子网 `192.168.31.0/24`。如果只希望放行一台调用方，可以把规则的
`RemoteAddresses` 收紧为该机器的固定地址，例如 `192.168.31.50`；此时最好为调用方设置 DHCP
地址保留，否则它换 IP 后规则会失效。

### 2. 在服务端生成并保存 API Key

在本项目目录执行以下命令。它会把监听地址设为 `0.0.0.0`，并在密钥为空时生成随机密钥；密钥
只写入权限为 `0600` 的 `.env`，不会回显：

```bash
./scripts/configure-access.py lan
```

结果等价于：

```dotenv
BIND_ADDRESS=0.0.0.0
PUBLISH_PORT=18080
LLAMA_API_KEY=自动生成或保留的真实密钥
```

需要配置调用方时，请在本机编辑器中打开 `.env`，安全复制 `LLAMA_API_KEY` 的值。不要把真实值
写入 `.env.example`、文档、Shell history、聊天记录或 Git，也不要复制 `.env` 中的其他配置。

### 3. 创建精确的 WSL Hyper-V 入站规则

本机使用 WSL mirrored networking 且 `firewall=true`。当前已在“以管理员身份运行”的 Windows
PowerShell 中创建以下规则，限制为当前可信子网和 TCP 18080：

```powershell
New-NetFirewallHyperVRule `
  -Name "QwenLlamaCpp18080" `
  -DisplayName "Qwen llama.cpp 18080 from LAN" `
  -Direction Inbound `
  -VMCreatorId "{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}" `
  -Protocol TCP `
  -LocalPorts 18080 `
  -RemoteAddresses "192.168.31.0/24"
```

微软的 `New-NetFirewallHyperVRule` 参数说明见
[Microsoft Learn](https://learn.microsoft.com/en-us/powershell/module/netsecurity/new-netfirewallhypervrule)。

不要使用把 WSL `DefaultInboundAction` 整体改成 `Allow` 的宽泛配置；只开放所需端口和调用方 IP。

查看规则：

```powershell
Get-NetFirewallHyperVRule -Name "QwenLlamaCpp18080"
```

回滚规则：

```powershell
Remove-NetFirewallHyperVRule -Name "QwenLlamaCpp18080"
```

### 4. 重建并验证服务

回到 WSL 项目目录：

```bash
./scripts/start.sh
./scripts/smoke-test.sh
./scripts/status.sh
ss -ltnp | grep ':18080'
```

监听结果应由 `127.0.0.1:18080` 变为 `0.0.0.0:18080`。`smoke-test.sh` 会自动读取本机
`.env` 中的 API Key，但不会打印 Key。

### 5. 在另一台机器验证

Linux/macOS：

```bash
export QWEN_API_KEY='替换为真实值'

curl --fail http://192.168.31.114:18080/health \
  -H "Authorization: Bearer $QWEN_API_KEY"

curl --fail http://192.168.31.114:18080/v1/models \
  -H "Authorization: Bearer $QWEN_API_KEY"
```

Windows PowerShell：

```powershell
Test-NetConnection 192.168.31.114 -Port 18080
$env:QWEN_API_KEY = "替换为真实值"
curl.exe --fail http://192.168.31.114:18080/v1/models `
  -H "Authorization: Bearer $env:QWEN_API_KEY"
```

调用方最终配置：

```dotenv
QWEN_BASE_URL=http://192.168.31.114:18080/v1
QWEN_API_KEY=真实密钥
QWEN_MODEL=qwen3.8-27b-ud-iq3-xxs
```

## 安全限制

上述局域网直连使用 HTTP，Bearer token 和请求内容没有 TLS 加密，只适用于完全可信并受保护的
局域网。以下情况不要使用直连：

- 跨互联网；
- 公共 Wi-Fi、访客网络或不可信 VLAN；
- 请求包含敏感代码、凭据、个人信息或商业数据；
- 多用户且需要审计、配额或细粒度权限。

这些场景应使用 Tailscale/WireGuard，或在 llama.cpp 前部署带 TLS、认证、限流和访问日志的反向
代理。不要把路由器的 18080 端口映射到公网。

当前 CORS 只允许 localhost。远程后端服务、curl 和 OpenAI SDK 不受浏览器 CORS 限制；远程网页
前端不应直接调用 llama.cpp。应由受控后端代理请求，避免把 API Key 暴露给浏览器。

服务当前只有 `PARALLEL=1`。多个项目或机器可以接入，但推理请求会排队，不代表具备多用户并发
容量。需要并发时，应另建 32K/64K profile 并实测，而不是直接在 128K 配置上增加 Slot。

## 排查顺序

1. 服务端 `./scripts/status.sh` 是否为 `healthy`；
2. 服务端 `ss -ltnp` 是否显示 `0.0.0.0:18080`；
3. 两台机器是否都在 `192.168.31.0/24`，路由器是否启用了客户端隔离；
4. Hyper-V firewall 规则中的 `RemoteAddresses` 是否为调用方当前 IP；
5. 调用方 `Test-NetConnection`/`curl` 是否能到达端口；
6. HTTP 401/403 检查 API Key，连接超时检查监听地址、防火墙和路由；
7. HTTP 200 但调用失败时检查 Base URL 是否包含 `/v1`、模型名是否完全一致。
