# 运维与故障排查

## 生命周期

启动并等待健康：

```bash
./scripts/start.sh
./scripts/smoke-test.sh
```

查看状态和日志：

```bash
./scripts/status.sh
docker compose logs --follow --tail=100
```

停止并删除容器和项目网络：

```bash
./scripts/stop.sh
```

模型、缓存、镜像和 `.env` 都会保留。Compose 设置为 `restart: unless-stopped`；容器存在且未被
手动停止时，Docker daemon 恢复后会尝试自动拉起。

## 常见问题

### `.env` 不存在

```bash
cp .env.example .env
```

不要用该命令覆盖已经包含本地端口或 API Key 的 `.env`。

### 端口已占用

```bash
ss -ltnp | grep ':18080'
docker ps --format '{{.Names}}\t{{.Ports}}'
```

停止明确的冲突服务，或修改 `.env` 中的 `PUBLISH_PORT`。不要盲目结束未知进程。

### 容器不能使用 GPU

```bash
nvidia-smi
docker info --format '{{json .Runtimes}}'
./scripts/preflight.sh
```

Docker runtime 列表必须包含 `nvidia`。本项目不会自动安装或修改宿主机驱动、Docker 或
NVIDIA Container Toolkit。

### 启动超时或不健康

```bash
docker compose ps
docker compose logs --tail=200 llama-server
```

重点检查模型路径、GGUF 校验、显存不足和 CUDA 初始化错误。模型校验命令：

```bash
./scripts/download-model.sh --verify-only
```

### OOM 或生成极慢

先恢复已验证参数：

```dotenv
CTX_SIZE=131072
PARALLEL=1
CACHE_TYPE_K=q4_0
CACHE_TYPE_V=q4_0
BATCH_SIZE=512
UBATCH_SIZE=128
```

仍有压力时优先降低 `CTX_SIZE` 到 `65536`，而不是增加 CPU offload 或提高并发。每次调整后运行
smoke test，并用真实业务输入重新测量显存、首 token 延迟和生成速度。

### 配置修改没有生效

`docker compose restart` 不会重新应用 Compose 变化。使用：

```bash
./scripts/start.sh
./scripts/smoke-test.sh
```

## 指标

服务启用了本机 Prometheus metrics endpoint：

```bash
curl --fail http://127.0.0.1:18080/metrics
```

该端点目前没有独立认证或持久监控后端，不应随 API 一起直接暴露到不可信网络。

## 长上下文基准

示例：

```bash
./scripts/context-benchmark.py \
  --base-url http://127.0.0.1:18080 \
  --target-tokens 120000 \
  --secret 'needle-2026'
```

120K 测试会持续数分钟并独占推理槽位，不应在有交互请求时运行。
