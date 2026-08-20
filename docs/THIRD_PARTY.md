# 第三方组件说明

本仓库的 MIT License 只覆盖项目自产脚本和文档，不改变以下第三方组件的许可证：

| 组件 | 固定身份 | 许可证/审查边界 |
| --- | --- | --- |
| Qwen3.8-27B | `Qwen/Qwen3.8-27B` | 项目记录为 Apache-2.0；使用方仍需完成适用性审查 |
| Unsloth GGUF | 仓库、revision、文件大小和 SHA-256 固定于 `.env.example` | 量化制品的发布者和模型许可证需一并审查 |
| llama.cpp CUDA image | 镜像固定到 SHA-256 digest | 遵循上游 llama.cpp 及镜像内组件许可证 |
| NVIDIA CUDA runtime libraries | 随容器镜像提供 | 遵循 NVIDIA 对应许可条款 |

SHA-256 只能证明下载制品与已记录字节一致，不能证明发布者可信、模型适合特定业务，也不能替代
组织或法律审查。升级任何第三方身份时，应同时评估许可证、来源、质量、安全和运行性能。
