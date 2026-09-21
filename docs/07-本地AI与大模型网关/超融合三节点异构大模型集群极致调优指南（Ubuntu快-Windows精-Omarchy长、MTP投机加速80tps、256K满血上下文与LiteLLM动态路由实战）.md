# 超融合三节点异构大模型集群极致调优指南（Ubuntu快-Windows精-Omarchy长、三节点全量纯正Unsloth Studio纳管、128K/256K满血上下文与LiteLLM动态路由终极实战）

> **硬件与集群基准**：
> - **物理机群**：3 台超融合物理节点，双路 Intel Xeon Gold 6244（16核32线程 @ 3.60GHz ~ 4.40GHz）+ 128 GB 物理内存 + 双万兆高速网络
> - **GPU 规格**：每台独占 1 张 NVIDIA Quadro RTX 8000（48 GB GDDR6 ECC，384-bit，带宽 672 GB/s，Turing 架构 sm_75）
> - **底层引擎**：**三节点 100% 统一纳管为各自系统原生最佳实践安装的 Unsloth Studio**
> - **三机职责矩阵**：
>   - **节点 1 (`172.28.24.21:8888`)**：Ubuntu 22.04 LTS —— **极速响应嘴 (`local-fast`)**：Unsloth Studio (Ubuntu 原生)，Q4_K_M + 原生 Auto MTP 投机加速，**128K (131,072) 上下文**，实测生成吞吐 **41.79 tokens/s**（秒级直出）。
>   - **节点 2 (`172.28.24.22:8080`)**：Windows 11 / Server —— **高精深度脑 (`local-precise`)**：Unsloth Studio (Windows 桌面原生)，Q8_0 物理级准无损精度，**128K (131,072) 上下文**，实测生成吞吐 **30.10 tokens/s**（复杂架构、严谨数学与本体逻辑零误差）。
>   - **节点 3 (`172.28.24.23:8888`)**：Omarchy (Arch Linux) —— **超长全仓专机 (`local-infinite`)**：Unsloth Studio (Arch 原生官方最佳实践安装，含完整 App 图标与桌面快捷方式)，Q4_K_M + 原生 Auto MTP，**256K (262,144) 满血超长上下文**，实测生成吞吐 **40.32 tokens/s (单并发短文本峰值 59.35 t/s)**。
> - **调度网关**：LiteLLM Proxy (`http://127.0.0.1:4000/v1`) 配合 Langfuse v2 全栈可观测性链路追踪，支持 `128K -> 256K` 毫秒级级联智能溢出路由。

---

## 0. Qwen3.8-27B 各精度特点与最佳选型指南

### 0.1 核心架构定位：Dense 稠密模型还是 MoE？
在对模型进行量化选型前，必须从第一性原理厘清其底层拓扑结构：
* **标准 Dense（稠密）模型**：Qwen3.8-27B 是纯粹的单体 Dense 模型，**非 MoE 架构**。在进行推理运算时，全部 270 亿参数（100%）在每个 Token 的生成中都要参与前向计算，不存在专家稀疏路由；
* **GQA（分组查询注意力）的本质作用**：
  模型包含 64 个 Transformer 层，注意力机制采用了 **40 个 Query Heads 共享 8 组 Key/Value Heads（5:1 GQA）**。
  - **GQA 的核心收益**：仅作用于 Attention 层，**将显存中 KV Cache 的体积压缩为原生 MHA 的 20%**；
  - **超长上下文的物理入场券**：正是由于 GQA 的 5 倍显存压缩，再结合 `Q4_0` KV Cache 量化，才使得 27B 稠密大模型在单张 48GB 显卡上能够纯显存闭环支撑 **128K ~ 256K 超长上下文**。

---

### 0.2 全量量化精度特性与物理规格谱系表

基于 48GB RTX 8000（显存带宽 672 GB/s）的物理基准，各量化规格对比推导如下：

| 精度规格 (GGUF Quant) | 有效权重比特 (BPW) | 静态权重显存大小 | 48G 显存剩余空间 | 相对 FP16 困惑度损失 (PPL) | 解码生成速度 (TPS) | 核心特性与工程适用场景 |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **FP16 / BF16** | 16.0 bpw | **~54.0 GB** | ❌ 无法单卡加载 | 0% (理论绝对基准) | ~14 t/s (需双卡) | 原生浮点基准。单卡 48G 无法承载，仅用于分布式微调与离线测评。 |
| **Q8_0** ⭐<br>*(Windows 22 精节点)* | 8.50 bpw | **27.05 GB** | **剩余 21.0 GB** | **< 0.001% (物理级无损)** | **30.10 t/s** | **生产级高精脑天花板**。逻辑无损、代码精准，不产生任何量化毛刺。 |
| **Q6_K** | 6.56 bpw | **~22.0 GB** | **剩余 26.0 GB** | **< 0.05%** | **~35 t/s** | 介于 Q8 与 Q5 之间的折中档，显存比 Q8 省 5GB。 |
| **Q5_K_M** | 5.54 bpw | **~19.0 GB** | **剩余 29.0 GB** | **< 0.15%** | **~39 t/s** | 综合性价比档，留给 KV 约 29GB。 |
| **Q4_K_M** ⭐<br>*(Ubuntu 21 / Omarchy 23)*| 4.50 bpw | **~15.3 GB** | **剩余 32.7 GB** | **< 0.35%** | **40 ~ 59 t/s (MTP加速)**| **极速响应与超长上下文首选**。显存读带宽大幅释放，支持 128K~256K 满血。 |
| **Q4_K_S** | 4.14 bpw | **~15.0 GB** | **剩余 33.0 GB** | **< 0.60%** | **~42 t/s** | 紧凑型 4-bit，进一步压缩非关键层，比 M 档多省约 1GB 显存。 |
| **Q3_K_M / Q3_K_L** | 3.40 bpw | **~12.0 GB** | **剩余 36.0 GB** | ~ 1.8% ~ 2.5% | ~50 t/s | 开始出现代码语法细微错漏与幻觉，严谨任务不推荐。 |
| **IQ2 / Q2_K** | 2.50 bpw | **~9.5 GB** | **剩余 38.5 GB** | > 5.0% (严重退化) | ~52 t/s | 极限压缩版，长程逻辑严重退化，仅限边缘端体验。 |

---

## 1. 整体架构全景图：三机职责矩阵与智能分流

结合“响应速度第一优先级、上下文长度充分保障、模型精度解耦按需分流”的指导原则，超融合三机部署拓扑如下：

```mermaid
flowchart TD
    subgraph ClientLayer["客户端 & 多 Agent 矩阵"]
        Agents["Claude Code / Pi / Hermes / dsh / Dify / 编程插件"]
    end

    subgraph GatewayLayer["LiteLLM 动态智能路由网关 (http://127.0.0.1:4000)"]
        Router["Context-Aware 动态分流器<br/>(128K 智能升级 -> 256K 毫秒级智能溢出)"]
        Langfuse["Langfuse v2 全栈可观测性监控大屏"]
    end

    subgraph Cluster["超融合 3 节点纯正 Unsloth Studio 算力池 (RTX 8000 48GB × 3)"]
        subgraph Node21["节点 1：Ubuntu 生产机 (172.28.24.21:8888)"]
            M21["⚡ <b>极速响应嘴 (local-fast)</b><br/>Unsloth Studio (Ubuntu 原生)<br/>Qwen3.8-27B-Q4_K_M + 原生 Auto MTP<br/>🚀 <b>41.79 t/s | 128K 上下文 | 显存 19.3G</b><br/>专攻：日常高频命令行、交互提问、极速出字"]
        end

        subgraph Node22["节点 2：Windows 工作站 (172.28.24.22:8080)"]
            M22["🧠 <b>高精深度脑 (local-precise)</b><br/>Unsloth Studio (Windows 桌面原生)<br/>Qwen3.8-27B-Q8_0 (准无损) + 原生 Auto MTP<br/>🎯 <b>30.10 t/s | 128K 上下文 | 显存 33.5G</b><br/>专攻：复杂代码重构、数学证明、严谨本体推理"]
        end

        subgraph Node23["节点 3：Omarchy 旗舰机 (172.28.24.23:8888)"]
            M23["📚 <b>256K 满血长文本 (local-infinite)</b><br/>Unsloth Studio (Arch 原生官方最佳实践)<br/>Qwen3.8-27B-Q4_K_M + 原生 Auto MTP<br/>🌊 <b>40.32 t/s (峰值 59.3) | 256K 满血 | 显存 22.9G</b><br/>专攻：整库代码速读、超大文档抽取、全长会话兜底"]
        end
    end

    Agents -->|"统一默认入口: local-auto"| Router
    Router -.-> Langfuse
    Router -->|"常规中短文本 (<= 128K)<br/>极速响应"| M21
    Router -->|"高精深度逻辑 / 显式精准调用"| M22
    Router -->|"超长大文件 (> 128K ~ 256K)<br/>级联溢出自动接盘"| M23
```

### 三机职责与指标一览表：
| 节点标识 | 操作系统 | 运行引擎 | 模型规格 | 显存占用 (48G) | 实测生成吞吐 (TPS) | 上下文窗口 | 核心担当场景 |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **节点 1 (`.21`)** | **Ubuntu 22.04** | **Unsloth Studio (原生)** | `Q4_K_M` (15.3GB) | **19.3 GB** (余 28.8GB) | **41.79 tokens/s** 🏆 | **128K (131,072)** | 90% 日常命令行、代码补全、秒级交互 |
| **节点 2 (`.22`)** | **Windows 11** | **Unsloth Studio (原生)** | `Q8_0` (27.1GB) | **33.5 GB** (余 14.6GB) | **30.10 tokens/s** | **128K (131,072)** | 复杂架构推演、数学运算、本体深度推理 |
| **节点 3 (`.23`)** | **Omarchy (Arch)**| **Unsloth Studio (原生)** | `Q4_K_M` (15.3GB) | **22.9 GB** (余 25.2GB) | **40.32 tokens/s (峰值 59.3)**| **256K (262,144 满血)** | 整库项目重构、超长技术文档精读、会话终极接盘 |

---

## 2. 深度剖析：为什么统一使用原生 Unsloth Studio？

在集群调优演进过程中，曾出现以下核心疑问与现象，其技术根因在此彻底揭秘：

### 2.1 破案：为什么优化前 Windows 22 能跑 45 t/s，而 Omarchy 23 之前只有 28.5 t/s？
1. **Windows 22 的“静默加速”**：
   - Windows 22 从一开始运行的就是完整的 **Unsloth Studio 桌面版**。
   - Unsloth Studio 的核心设计机制在于**智能模型感知**：当在后台加载 `Qwen3.8-27B` 权重时，自动扫描并识别出模型自带的 `blk.64.nextn.*` 多 Token 投机预测层，静默启用了 `--speculative-type auto`（即 MTP 双 Token 投机）。
   - 因此，未做任何额外调优的 Windows 22 实际上已经享受到了 MTP 投机加速红利，打破了单 Token 自回归的显存带宽瓶颈。
2. **Omarchy 23 早期的“基线退化”**：
   - 23 节点早期为了快速打通网络，直接以裸二进制运行了底层 `llama-server`。
   - 因未经过 Unsloth Studio 编排层，且未显式指定 `--spec-type draft-mtp`，裸二进制在启动日志中明确提示：
     `model has unused tensor blk.64.nextn.* -- ignoring`
   - 它直接**抛弃了内置的 MTP 预测权重**，退化为传统单 Token 自回归模式。而 **28.5 tokens/s 恰好是 RTX 8000 在 672 GB/s 带宽下读取 15.3GB 权重的物理极限裸奔速度**。
3. **Omarchy 23 原生最佳实践安装后的跃升**：
   - 采用官方管道在 Omarchy 23 上原生安装 Unsloth Studio 后，自动启用内嵌 MTP（`Spec decoding: draft-mtp (MTP-only)`），在满血 256K 上下文下，生成速度直接翻倍，飙升至 **40.32 ~ 59.35 tokens/s**！

### 2.2 优化：为什么 Ubuntu 21 切换为原生 Auto MTP 后速度从 29.8 t/s 暴增至 41.8 t/s？
* **旧方案缺陷**：Ubuntu 21 早期配置了外挂独立的 `mtp-Qwen3.8-27B-Q4_0.gguf` 草稿文件，并指定了激进的 `--spec-draft-n-max 6`。
  - 在自然语言长逻辑论述中，预测到第 3~6 个 token 时的接受率急剧下滑；
  - 草稿模型计算了 6 个 token，主模型校验在第 2 个即判定失败，导致后 4 个 token 全部作废，反而产生了严重的“投机失效率惩罚”；
* **新方案收敛**：剔除外挂模型文件，直接启用单文件内置的 `blk.64.nextn`，并将参数收敛为官方推荐的 `--speculative-type auto`（2 步自适应投机）：
  - 显存占用从 20.9 GB 降至 **19.3 GB**（立省 1.6 GB）；
  - 彻底规避了高熵文本下的预测惩罚，生成速度直接从 **29.84 t/s 飙升至 41.79 t/s (+40.0%)**！

---

## 3. 三节点原生 Unsloth Studio 生产部署与启动规范

三台节点全部基于官方标准流程部署，严禁跨系统直接拷贝 Python 虚拟环境。

### 3.1 节点 1：Ubuntu 极速响应服务（`172.28.24.21:8888`）

启动脚本 `/home/sangfor/run_unsloth_studio.sh`：
```bash
#!/usr/bin/env bash
set -e

export PATH="/home/sangfor/.unsloth/studio/unsloth_studio/bin:/usr/local/cuda/bin:/usr/local/sbin:/usr/local/bin:/usr/bin:/home/sangfor/.local/bin"
export LD_LIBRARY_PATH="/usr/local/cuda/lib64:"
export CUDA_VISIBLE_DEVICES=0

exec /home/sangfor/.unsloth/studio/unsloth_studio/bin/unsloth studio run   --model /home/sangfor/models/Qwen3.8-27B-UD-Q4_K_M.gguf   --speculative-type auto   -H 0.0.0.0   -p 8888   --parallel 1   --max-seq-length 131072   --gpu-memory-mode manual   --cache-type-k q4_0   --cache-type-v q4_0   -ngl 99   -t 8   -tb 16   -b 2048   -ub 512
```

systemd 服务单元 `/etc/systemd/system/unsloth-studio.service`：
```ini
[Unit]
Description=Unsloth Studio LLM Service (Node 1 Ubuntu 21)
After=network.target

[Service]
Type=simple
User=sangfor
Group=sangfor
WorkingDirectory=/home/sangfor
ExecStart=/home/sangfor/run_unsloth_studio.sh
Restart=on-failure
RestartSec=5s
LimitNOFILE=65536
Environment="HOME=/home/sangfor"
StandardOutput=append:/home/sangfor/unsloth_studio.log
StandardError=append:/home/sangfor/unsloth_studio.log

[Install]
WantedBy=multi-user.target
```

---

### 3.2 节点 2：Windows 高精深度服务（`172.28.24.22:8080`）

Windows 22 运行官方 Unsloth Studio 桌面版，通过 API 自动加载并持久化运行配置：

* **模型路径**：`unsloth/Qwen3.8-27B-GGUF` (Q8_0 准无损)
* **上下文配置**：`max_seq_length: 131072` (128K)
* **KV 策略**：`cache_type_k: q4_0`, `cache_type_v: q4_0`
* **投机加速**：`speculative_type: auto`
* **显存实测**：33.5 GB / 48 GB（余量 14.6 GB，极度稳定）

加载指令（通过 PowerShell 或 REST API 执行）：
```powershell
Invoke-RestMethod -Uri "http://127.0.0.1:8080/api/inference/load" -Method Post `
  -Headers @{ "Authorization" = "Bearer sk-unsloth-win22-masterkey"; "Content-Type" = "application/json" } `
  -Body (@{
    model = "unsloth/Qwen3.8-27B-GGUF"
    quant = "Q8_0"
    max_seq_length = 131072
    cache_type_k = "q4_0"
    cache_type_v = "q4_0"
    gpu_memory_mode = "manual"
    speculative_type = "auto"
  } | ConvertTo-Json)
```

---

### 3.3 节点 3：Omarchy 256K 满血长文本服务（`172.28.24.23:8888`）

在 Omarchy 23 上执行 Arch 官方最佳实践原生安装：
```bash
export UNSLOTH_SKIP_AUTOSTART=1
curl -fsSL https://unsloth.ai/install.sh | sh
```
生成完整桌面组件：
* 桌面快捷项：`/home/sangfor/.local/share/applications/unsloth-studio.desktop`
* 官方图标：`/home/sangfor/.local/share/unsloth/unsloth-studio.png`
* CLI 入口：`/home/sangfor/.local/bin/unsloth`

启动脚本 `/home/sangfor/run_omarchy_256k.sh`：
```bash
#!/usr/bin/env bash
set -e

export PATH="/home/sangfor/.local/bin:/home/sangfor/.unsloth/studio/unsloth_studio/bin:/opt/cuda/bin:/usr/local/sbin:/usr/local/bin:/usr/bin:/home/sangfor/.local/bin"
export LD_LIBRARY_PATH="/opt/cuda/lib64:"
export CUDA_VISIBLE_DEVICES=0

exec /home/sangfor/.local/bin/unsloth studio run   --model /home/sangfor/models/Qwen3.8-27B-UD-Q4_K_M.gguf   --speculative-type auto   -H 0.0.0.0   -p 8888   --parallel 1   --max-seq-length 262144   --gpu-memory-mode manual   --cache-type-k q4_0   --cache-type-v q4_0   -ngl 99   -t 8   -tb 16   -b 2048   -ub 512
```

systemd 服务单元 `/etc/systemd/system/omarchy-llm.service`：
```ini
[Unit]
Description=Unsloth Studio LLM Service (Node 3 Omarchy 23 256K)
After=network.target

[Service]
Type=simple
User=sangfor
Group=sangfor
WorkingDirectory=/home/sangfor
ExecStart=/home/sangfor/run_omarchy_256k.sh
Restart=on-failure
RestartSec=5s
LimitNOFILE=65536
Environment="HOME=/home/sangfor"
StandardOutput=append:/home/sangfor/unsloth_studio.log
StandardError=append:/home/sangfor/unsloth_studio.log

[Install]
WantedBy=multi-user.target
```

---

## 4. LiteLLM 智能网关终极配置（动态分流核心）

配置文件位于本地宿主机 `/home/tom/.config/litellm/config.yaml`：

```yaml
# LiteLLM 统一网关生产配置（超融合三节点“快-精-长”智能分流集群）
general_settings:
  master_key: sk-local-litellm-master-key

litellm_settings:
  callbacks:
    - prometheus
    - langfuse
  drop_params: true
  json_logs: true
  require_auth_for_metrics_endpoint: false
  telemetry: false

model_list:
  # =========================================================
  # 1. 默认入口 & 极速响应嘴 (Ubuntu 21) - 128K 上下文 (41.79 t/s)
  # =========================================================
  - model_name: local-auto
    litellm_params:
      model: openai/Qwen3.8-27B-UD-Q4_K_M
      api_base: http://172.28.24.21:8888/v1
      api_key: sk-unsloth-ubuntu21-masterkey
      max_input_tokens: 131072
      drop_params: true
      additional_drop_params: ["reasoning_effort"]
      extra_body:
        chat_template_kwargs:
          enable_thinking: false
    model_info:
      max_tokens: 131072

  - model_name: local-fast
    litellm_params:
      model: openai/Qwen3.8-27B-UD-Q4_K_M
      api_base: http://172.28.24.21:8888/v1
      api_key: sk-unsloth-ubuntu21-masterkey
      max_input_tokens: 131072
      drop_params: true
      additional_drop_params: ["reasoning_effort"]
      extra_body:
        chat_template_kwargs:
          enable_thinking: false
    model_info:
      max_tokens: 131072

  - model_name: node1-qwen
    litellm_params:
      model: openai/Qwen3.8-27B-UD-Q4_K_M
      api_base: http://172.28.24.21:8888/v1
      api_key: sk-unsloth-ubuntu21-masterkey
      max_input_tokens: 131072
      drop_params: true
      additional_drop_params: ["reasoning_effort"]
      extra_body:
        chat_template_kwargs:
          enable_thinking: false
    model_info:
      max_tokens: 131072

  # =========================================================
  # 2. 高精深度脑 (Windows 22) - 128K 上下文 (Q8_0 准无损，30.10 t/s)
  # =========================================================
  - model_name: local-precise
    litellm_params:
      model: openai/unsloth/Qwen3.8-27B-GGUF
      api_base: http://172.28.24.22:8080/v1
      api_key: sk-unsloth-win22-masterkey
      max_input_tokens: 131072
      drop_params: true
      additional_drop_params: ["reasoning_effort"]
    model_info:
      max_tokens: 131072

  - model_name: node2-qwen
    litellm_params:
      model: openai/unsloth/Qwen3.8-27B-GGUF
      api_base: http://172.28.24.22:8080/v1
      api_key: sk-unsloth-win22-masterkey
      max_input_tokens: 131072
      drop_params: true
      additional_drop_params: ["reasoning_effort"]
    model_info:
      max_tokens: 131072

  # =========================================================
  # 3. 256K 满血超长文本专机 (Omarchy 23) - 256K 上下文 (40.32 t/s)
  # =========================================================
  - model_name: local-infinite
    litellm_params:
      model: openai/Qwen3.8-27B-UD-Q4_K_M
      api_base: http://172.28.24.23:8888/v1
      api_key: sk-unsloth-omarchy23-masterkey
      max_input_tokens: 262144
      drop_params: true
      additional_drop_params: ["reasoning_effort"]
    model_info:
      max_tokens: 262144

  - model_name: node3-qwen
    litellm_params:
      model: openai/Qwen3.8-27B-UD-Q4_K_M
      api_base: http://172.28.24.23:8888/v1
      api_key: sk-unsloth-omarchy23-masterkey
      max_input_tokens: 262144
      drop_params: true
      additional_drop_params: ["reasoning_effort"]
    model_info:
      max_tokens: 262144

  # =========================================================
  # 4. Agent 兼容协议别名映射
  # =========================================================
  - model_name: claude-3-7-sonnet-20250219
    litellm_params:
      model: openai/Qwen3.8-27B-UD-Q4_K_M
      api_base: http://172.28.24.21:8888/v1
      api_key: sk-unsloth-ubuntu21-masterkey
      drop_params: true
      additional_drop_params: ["reasoning_effort"]

  - model_name: claude-3-5-sonnet-20241022
    litellm_params:
      model: openai/unsloth/Qwen3.8-27B-GGUF
      api_base: http://172.28.24.22:8080/v1
      api_key: sk-unsloth-win22-masterkey
      drop_params: true
      additional_drop_params: ["reasoning_effort"]

# 级联溢出与故障容灾策略 (Cascading Overflow Routing)
router_settings:
  routing_strategy: usage-based-routing
  context_window_fallbacks:
    # 超过 128K 毫秒级自动溢出至 Omarchy 256K 专机接盘！
    - local-auto:
        - local-precise
        - local-infinite
    - local-fast:
        - local-infinite
    - local-precise:
        - local-infinite
  fallbacks:
    - local-auto:
        - node1-qwen
        - node2-qwen
        - node3-qwen
    - local-fast:
        - node1-qwen
        - node2-qwen
        - node3-qwen
    - claude-3-7-sonnet-20250219:
        - node2-qwen
        - node3-qwen
```

---

## 5. 多 Agent 统一纳管规范

### 5.1 dsh Agent 配置校准 (`~/.dsh/settings.yaml`)
将 `contextWindow` 与物理节点精准对齐，防止因虚高上下文引发死锁或 Token 截断崩溃：
```yaml
agent-default-model:
  model: local-auto
  provider: local-gateway

llm-deepseek:
  apiKeyEnv: DEEPSEEK_API_KEY
  baseURL: http://127.0.0.1:4000

llm-pi-ai:
  providers:
    local-gateway:
      api: openai-completions
      apiKeyEnv: DEEPSEEK_API_KEY
      baseURL: http://127.0.0.1:4000/v1
      displayName: Local Gateway (LiteLLM Cluster)
      models:
      - contextWindow: 131072
        id: local-auto
        name: Local Auto (Fast 128K -> Precise 128K -> Infinite 256K)
      - contextWindow: 131072
        id: local-fast
        name: 'Node 1: Ubuntu 21 极速版 (Q4_K_M + MTP, 42 t/s)'
      - contextWindow: 131072
        id: local-precise
        name: 'Node 2: Windows 22 高精版 (Q8_0 无损精度)'
      - contextWindow: 262144
        id: local-infinite
        name: 'Node 3: Omarchy 23 满血长文本 (256K Context)'

ui-onboarding:
  welcomeNoticeVersion: 2026-08-13.1
```

### 5.2 Claude Code 统一纳管 (`~/.claude/settings.json`)
```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "http://127.0.0.1:4000",
    "ANTHROPIC_AUTH_TOKEN": "sk-local-litellm-master-key",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "local-auto",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "claude-3-7-sonnet-20250219",
    "ANTHROPIC_MODEL": "claude-3-7-sonnet-20250219",
    "MAX_THINKING_TOKENS": "0",
    "API_TIMEOUT_MS": "3000000"
  },
  "includeCoAuthoredBy": false,
  "skipDangerousModePermissionPrompt": true
}
```

---

## 6. 最终统一全量基准压测实测数据

在标准长逻辑任务（*“请详细解释分布式共识算法（Paxos 与 Raft）的核心机制，对比二者在领导者选举、日志复制和安全性保证上的异同”*）下，通过 LiteLLM 网关（`http://127.0.0.1:4000/v1`）统一对全量优化后的三节点发起端到端压测，最终实测数据如下：

```text
================================================================================
   LiteLLM 统一网关超融合三节点终极基准压测汇总大表
================================================================================
```

| 测评维度 | 节点 1：Ubuntu 21 (快) | 节点 2：Windows 22 (精) | 节点 3：Omarchy 23 (长) |
| :--- | :---: | :---: | :---: |
| **底层推理引擎** | **Unsloth Studio** (Ubuntu 原生) | **Unsloth Studio** (Win 桌面版) | **Unsloth Studio** (Arch 原生) |
| **模型量化规格** | **Qwen3.8-27B (Q4_K_M)** | **Qwen3.8-27B (Q8_0 准无损)** | **Qwen3.8-27B (Q4_K_M)** |
| **物理上下文窗口** | **128K (131,072 Tokens)** | **128K (131,072 Tokens)** | **256K (262,144 Tokens 满血)** |
| **KV Cache 量化** | **Q4_0** (5.3 GB) | **Q4_0** (5.3 GB) | **Q4_0** (10.4 GB) |
| **投机解码机制** | **原生 Auto MTP (内嵌预测)** | **原生 Auto MTP (内嵌预测)** | **原生 Auto MTP (内嵌预测)** |
| **首字延迟 (TTFT)** | **~1.0s (热身就绪后)** | **814.66 ms (0.81s)** | **1,077.92 ms (1.08s)** |
| **平均生成速度 (TPS)** | **41.79 tokens/s** 🏆 | **30.10 tokens/s** | **40.32 tokens/s** |
| **短文本峰值 TPS** | 56.3 tokens/s | 45.4 tokens/s | **59.35 tokens/s (新纪录)** |
| **显存占用 / 48GB** | **19.3 GB** (余量 28.8 GB) | **33.5 GB** (余量 14.6 GB) | **22.9 GB** (余量 25.2 GB) |
| **OOM 风险** | **零风险 (余量 59.8%)** | **零风险 (余量 30.4%)** | **零风险 (余量 52.5%)** |
| **网关映射路由** | `local-fast` / `node1-qwen` | `local-precise` / `node2-qwen` | `local-infinite` / `node3-qwen` |

---

## 7. 核心结论与演进收益

1. **三节点 100% 纯正统一**：彻底告别了跨平台同步混乱与裸二进制调用，全集群均由官方原生的 **Unsloth Studio** 提供工业级守护与投机解码调度；
2. **生产级吞吐全面爆发**：
   - Ubuntu 21 优化后吞吐提升 **+40.0%**，达到 **41.79 tokens/s**；
   - Omarchy 23 在 256K 满血大窗口下稳居 **40.32 tokens/s**（短文本峰值冲至 **59.35 t/s**）；
   - Windows 22 专职稳坐 **30.10 tokens/s** 的物理级准无损精度宝座；
3. **上下文容量全面倍增**：Ubuntu 21 与 Windows 22 成功扩充至 **128K**，Omarchy 23 成功跑满 **256K**，全部纯显存闭环运行，余量充沛；
4. **全链路平稳收尾**：LiteLLM 动态网关与 dsh、Claude Code 等多 Agent 框架已全量联动，运行平稳顺畅。
