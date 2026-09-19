# 07-本地 AI 与大模型网关

本目录收录在 **Omarchy (Arch Linux + Hyprland)** 环境下，针对多 AI 编码助手（Claude Code、Pi Agent、Hermes Agent 等）与异构私有模型推理集群的统一网关架构设计、全链路可观测性监控大屏与踩坑实战指南。

---

## 📚 文档列表

| 文档名称 | 核心内容与技术栈 | 对应场景 / 解决痛点 |
| :--- | :--- | :--- |
| [本地多Agent统一LLM网关与全链路可观测性实战（LiteLLM集中路由、Langfuse深度链路追踪、双异构算力节点高可用与Claude-Pi-Hermes全纳管）.md](./本地多Agent统一LLM网关与全链路可观测性实战（LiteLLM集中路由、Langfuse深度链路追踪、双异构算力节点高可用与Claude-Pi-Hermes全纳管）.md) | **LiteLLM Proxy**、**Langfuse v2**、**Prometheus Exporter**、双物理节点异构算力（Linux Q8_0 + Win Q4_K）、**Claude/Pi/Hermes 协议纳管** | 密钥碎片化管理、多 Agent 协议不通、私有模型与云端 API 统一调度、自动故障熔断降级、思维链与调用瀑布流全可观测性追踪 |
| [Unsloth-Studio与Qwen3.8-27B双异构算力深度调优、基准评测与全量知识图谱抽取实战（RTX8000显存压榨、MTP多Token推测加速、跨平台TTFT吞吐对比与长文本抽取避坑）.md](./Unsloth-Studio与Qwen3.8-27B双异构算力深度调优、基准评测与全量知识图谱抽取实战（RTX8000显存压榨、MTP多Token推测加速、跨平台TTFT吞吐对比与长文本抽取避坑）.md) | **Unsloth Studio**、**Qwen3.8-27B (Q8_0 / Q4_K_M)**、**Quadro RTX 8000 48GB**、**MTP 投机解码**、**Semantica 图谱抽取**、**vis-network 全景图** | 显存容量规划、Flash Attention 语法陷阱、Windows 0.0.0.0 绑定与防火墙排错、双节点 TTFT/吞吐深度对比、思考模式 Token 耗尽截断治理、yEd 拓扑一键舒展 |
| [超融合三节点异构大模型集群极致调优指南（Ubuntu快-Windows精-Omarchy长、MTP投机加速80tps、256K满血上下文与LiteLLM动态路由实战）.md](./超融合三节点异构大模型集群极致调优指南（Ubuntu快-Windows精-Omarchy长、MTP投机加速80tps、256K满血上下文与LiteLLM动态路由实战）.md) | **超融合 3 节点集群**、**Ubuntu 快 (80tps MTP)**、**Windows 精 (Q8_0)**、**Omarchy 长 (256K Q4 KV)**、**LiteLLM Context-Aware 动态级联** | 响应速度第一优先级、打字速度突破 80t/s、256K 满血上下文纯显存闭环、Token 上限截断根治、跨系统按需智能分流 |

---

## 🛠️ 对应 Agent 技能 (Skill)

* **`skills/omarchy-local-llm-gateway`**：本地大模型网关与可观测性全链路诊断与运维技能。
  * 包含网关环境探测、双节点算力探活、Langfuse 状态检查与一键绑定热重启工具链。
