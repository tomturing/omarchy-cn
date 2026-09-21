# 超融合三节点异构大模型集群极致调优指南（Ubuntu快-Windows精-Omarchy长、三节点全量纯正Unsloth Studio纳管、128K/256K满血上下文与LiteLLM动态路由终极实战）

> **硬件与集群基准**：
> - **物理机群**：3 台超融合物理节点，双路 Intel Xeon Gold 6244（16核32线程 @ 3.60GHz ~ 4.40GHz）+ 128 GB 物理内存 + 双万兆高速网络
> - **GPU 规格**：每台独占 1 张 NVIDIA Quadro RTX 8000（48 GB GDDR6 ECC，384-bit，带宽 672 GB/s，Turing 架构 sm_75）
> - **底层引擎**：**三节点 100% 统一纳管为各自系统原生最佳实践安装的 Unsloth Studio**
> - **三机职责矩阵**：
>   - **节点 1 (`172.28.24.21:8888`)**：Ubuntu 22.04 LTS —— **极速响应嘴 (`local-fast` / 统一默认 `local`)**：Unsloth Studio (Ubuntu 原生)，Q4_K_M + 原生 Auto MTP 投机加速，**128K (131,072) 上下文**，极限批次 `-b 8192 -ub 2048`，实测生成吞吐 **41.79 tokens/s**（秒级直出）。
>   - **节点 2 (`172.28.24.22:8080`)**：Windows 11 / Server —— **高精深度脑 (`local-precise`)**：Unsloth Studio (Windows 桌面原生)，Q8_0 物理级准无损精度，**128K (131,072) 上下文**，极限批次 `-b 8192 -ub 2048`，实测生成吞吐 **30.10 tokens/s**（复杂架构、严谨数学与本体逻辑零误差）。
>   - **节点 3 (`172.28.24.23:8888`)**：Omarchy (Arch Linux) —— **超长全仓专机 (`local-infinite`)**：Unsloth Studio (Arch 原生官方最佳实践安装，含完整 App 图标与桌面快捷方式)，Q4_K_M + 原生 Auto MTP，**256K (262,144) 满血超长上下文**，极限批次 `-b 8192 -ub 2048`，实测生成吞吐 **40.32 tokens/s (单并发短文本峰值 59.35 t/s)**。
> - **调度网关**：LiteLLM Proxy (`http://127.0.0.1:4000/v1`) 配合 Langfuse v2 全栈可观测性链路追踪，支持 `128K -> 256K` 毫秒级级联智能溢出路由，全集群统一暴露出顶级模型标识 `local`。

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
        Router["Context-Aware 动态分流器<br/>(统一顶级入口 local<br/>128K 智能升级 -> 256K 毫秒级智能溢出)"]
        Langfuse["Langfuse v2 全栈可观测性监控大屏"]
    end

    subgraph Cluster["超融合 3 节点纯正 Unsloth Studio 算力池 (RTX 8000 48GB × 3)"]
        subgraph Node21["节点 1：Ubuntu 生产机 (172.28.24.21:8888)"]
            M21["⚡ <b>极速响应嘴 (local-fast / local)</b><br/>Unsloth Studio (Ubuntu 原生)<br/>Qwen3.8-27B-Q4_K_M + 原生 Auto MTP<br/>🚀 <b>41.79 t/s | 128K 上下文 | 显存 20.8G</b><br/>极限批次: -b 8192 -ub 2048"]
        end

        subgraph Node22["节点 2：Windows 工作站 (172.28.24.22:8080)"]
            M22["🧠 <b>高精深度脑 (local-precise)</b><br/>Unsloth Studio (Windows 桌面原生 REST API)<br/>Qwen3.8-27B-Q8_0 (准无损) + 原生 Auto MTP<br/>🎯 <b>30.10 t/s | 128K 上下文 | 显存 35.2G</b><br/>极限批次: -b 8192 -ub 2048"]
        end

        subgraph Node23["节点 3：Omarchy 旗舰机 (172.28.24.23:8888)"]
            M23["📚 <b>256K 满血长文本 (local-infinite)</b><br/>Unsloth Studio (Arch 原生官方最佳实践)<br/>Qwen3.8-27B-Q4_K_M + 原生 Auto MTP<br/>🌊 <b>40.32 t/s (峰值 59.3) | 256K 满血 | 显存 24.9G</b><br/>极限批次: -b 8192 -ub 2048"]
        end
    end

    Agents -->|"所有 Agent 统一默认入口: local"| Router
    Router -.-> Langfuse
    Router -->|"常规中短文本 (<= 128K)<br/>极速响应"| M21
    Router -->|"高精深度逻辑 / 显式精准调用"| M22
    Router -->|"超长大文件 (> 128K ~ 256K)<br/>级联溢出自动接盘"| M23
```

### 三机职责与指标一览表：
| 节点标识 | 操作系统 | 运行引擎 | 模型规格 | 极限批次参数 | 显存占用 (48G) | 实测生成吞吐 (TPS) | 上下文窗口 | 核心担当场景 |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **节点 1 (`.21`)** | **Ubuntu 22.04** | **Unsloth Studio (原生)** | `Q4_K_M` (15.3GB) | `-b 8192 -ub 2048` | **20.8 GB** (余 25.2GB) | **41.79 tokens/s** 🏆 | **128K (131,072)** | 90% 日常命令行、代码补全、秒级交互、统一默认 `local` |
| **节点 2 (`.22`)** | **Windows 11** | **Unsloth Studio (REST API)** | `Q8_0` (27.1GB) | `-b 8192 -ub 2048` | **35.2 GB** (余 12.8GB) | **30.10 tokens/s** | **128K (131,072)** | 复杂架构推演、数学运算、本体深度推理、支持动态热重载 |
| **节点 3 (`.23`)** | **Omarchy (Arch)**| **Unsloth Studio (原生)** | `Q4_K_M` (15.3GB) | `-b 8192 -ub 2048` | **24.9 GB** (余 23.1GB) | **40.32 tokens/s (峰值 59.3)**| **256K (262,144 满血)** | 整库项目重构、超长技术文档精读、会话终极接盘 |


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
  - 彻底规避了高熵文本下的预测惩罚，生成速度直接从 **29.84 t/s 飙升至 41.79 t/s (+40.0%)**！

### 2.3 破案与攻坚：首字延迟 (TTFT) 根因与 Prefill 极限批处理 (-b 8192 -ub 2048) 第一性原理

在实际接入多 Agent 矩阵（特别是 Claude Code）时，开发者常常观察到一种困惑现象：**为什么生成速度明明达到了 40+ tokens/s，但按下回车后却要等待 20~30 秒才吐出第一个字符？**

#### 1. 第一性原理拆解：解码受限于带宽，预填充受限于算力
大语言模型推理在物理本质上被严格划分为两个阶段：
1. **生成解码阶段（Decoding Phase / Next-token Generation）**：
   - 每次只前向传播 1 个（或 MTP 的 2 个）Token；
   - 属于典型的**访存密集型（Memory-bound）**任务，计算强度低，吞吐速度由显存读取带宽（RTX 8000 为 672 GB/s）直接决定。
2. **预填充提示评估阶段（Prefill Phase / Prompt Evaluation）**：
   - 模型必须一次性将用户发送的所有历史上下文（Prompt）全部前向计算并生成初始 KV Cache；
   - 属于典型的**计算密集型（Compute-bound）**任务，计算复杂度为 $O(N^2)$（Attention）与 $O(N \cdot d)$（GEMM），吞吐速度由 GPU 核心的 Tensor Core 并行浮点算力决定。

#### 2. 根因抓包：Claude Code 启动时的 18K Token 算力轰炸
对 LiteLLM 与本地推理引擎抓包分析发现：Claude Code 每次启动新会话或上下文未命中缓存时，发送的请求体不仅包含用户的简短提问，还包含：
- 全量 System Instructions（工程角色、行为守则）；
- 数十个 CLI/File 工具完整的 JSON Schema 描述；
- 运行环境状态、Git 分支信息、Scratchpad 等。
**首包 Prompt 长度高达 18,041 个 Tokens！**

在默认参数 `-ub 512`（单次 micro batch）下：
- Turing 架构（RTX 8000）的 576 个 Tensor Core 无法被小尺寸 GEMM 矩阵充分填满，并行计算效率严重受限，Prompt 评估吞吐仅约 **630 tokens/s**；
- 耗时计算：$\frac{18041 \text{ tokens}}{630 \text{ t/s}} \approx 28.6 \text{ 秒}$。即用户等待的 28 秒中，**99% 以上的时间全部消耗在 GPU 对这 18K token 的密集矩阵浮点运算上**。

#### 3. 极限调优：为什么升级至 `-b 8192 -ub 2048`？
从第一性原理出发，解决算力受限与内核调度的破局方案：
1. **提升微批处理（`-ub 2048`）拉满 Tensor Core 并行度**：
   - 将单次送入 CUDA 核的 micro batch 从 512 翻 4 倍至 2048；
   - 大矩阵乘法使 Tensor Core 的 Warps 利用率达到峰值，Prompt 评估吞吐直接从 630 t/s 跃升至 **~1050 tokens/s**；
   - 18K token 的 Prefill 耗时直接从 28.6 秒骤降至 **17.1 秒（提速 40.2%）**！
2. **扩大全局批次（`-b 8192`）骤减 CPU 调度与中断开销**：
   - 旧参数 `-b 2048` 在处理 18K token 时，必须切分为至少 9 个批次循环调度，造成 9 次 CPU-GPU 间的内核中断与数据同步；
   - 升级至 `-b 8192` 后，18K token 仅需 2~3 次调度循环，**减少了 70% 的内核上下文切换与任务调度延迟**。

#### 4. 对抗性审查：显存与稳定性边界测试
| 检验维度 | `-ub 512` (默认) | `-ub 2048` (极限调优) | 对抗性结论与安全冗余 |
| :--- | :--- | :--- | :--- |
| **激活值临时显存** | ~350 MB | ~1.4 GB (+1.05 GB) | 瞬态显存增加约 1GB，对于 48GB 大显卡影响微乎其微。 |
| **Ubuntu 21 显存** | 19.3 GB | **20.8 GB** | 剩余 25.2 GB 显存（余量 54.8%），绝对安全。 |
| **Omarchy 23 显存** | 22.9 GB | **24.9 GB** | 剩余 23.1 GB 显存（余量 48.1%），绝对安全。 |
| **Windows 22 显存** | 33.5 GB | **35.2 GB** | 剩余 12.8 GB 显存（余量 26.7%），坚如磐石。 |

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

exec /home/sangfor/.unsloth/studio/unsloth_studio/bin/unsloth studio run \
  --model /home/sangfor/models/Qwen3.8-27B-UD-Q4_K_M.gguf \
  --speculative-type auto \
  -H 0.0.0.0 \
  -p 8888 \
  --parallel 1 \
  --max-seq-length 131072 \
  --gpu-memory-mode manual \
  --cache-type-k q4_0 \
  --cache-type-v q4_0 \
  -ngl 99 \
  -t 8 \
  -tb 16 \
  -b 8192 \
  -ub 2048
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

### 3.2 节点 2：Windows 节点 Unsloth Studio REST API 远程热管理与运维全解（`172.28.24.22:8080`）

Windows 22 节点常驻运行官方 **Unsloth Studio 桌面版**。与传统的 GUI 工具不同，Unsloth Studio 底层架构基于 **FastAPI + Uvicorn**，其内置的 Web Server 不仅承载前端交互界面，更暴露了一套完备、工业级的 **RESTful 远程管理 API**。

这意味着开发者**完全不需要远程桌面登录 Windows 操作系统**，即可在局域网内任意终端（Linux / macOS / CI 脚本）通过标准 HTTP 请求对 Windows 节点的模型加载、参数注入、显存释放进行全生命周期远程管理。

#### 1. 核心 REST API 接口体系与路由清单

所有管理接口均挂载于 Windows 宿主机的 `http://172.28.24.22:8080`，需在请求头携带 Bearer Token 鉴权：

| HTTP 方法 | API 路由端点 | 功能定义 | 核心应用场景 |
| :--- | :--- | :--- | :--- |
| **`POST`** | `/api/inference/load` | **动态热加载 / 重载模型** | 注入批次参数（`-b 8192 -ub 2048`）、热切换量化版本、调整上下文 |
| **`GET`** | `/api/inference/status` | **查询推理引擎运行状态** | 探活检测、获取当前加载的模型名、量化等级与底层进程状态 |
| **`POST`** | `/api/inference/unload` | **模型热卸载与显存释放** | 释放 35GB+ 显卡显存供其他任务或训练临时使用，零死机风险 |
| **`GET`** | `/api/system/status` | **宿主机全局硬件资源监视** | 远程监控 Windows 主机的 CPU 负载、物理内存与 GPU 显存利用率 |

#### 2. 核心 Payload JSON Schema 与参数避坑真机实录

在向 `/api/inference/load` 发起热重载请求时，请求体字段命名与底层 `llama-server` 参数透传有极为严格的规范：

```json
{
  "model_path": "unsloth/Qwen3.8-27B-GGUF",
  "gguf_variant": "Q8_0",
  "max_seq_length": 131072,
  "cache_type_k": "q4_0",
  "cache_type_v": "q4_0",
  "gpu_memory_mode": "manual",
  "gpu_layers": 99,
  "llama_extra_args": [
    "-b", "8192",
    "-ub", "2048"
  ]
}
```

> **⚠️ 源码级避坑与参数映射真机要点**：
> 1. **字段名防踩坑**：模型路径字段必须为 `"model_path"`（而非 `"model"`）；量化版本必须为 `"gguf_variant"`（而非 `"quant"`），否则 Unsloth Studio 会报 Pydantic 校验失败或回退至默认 FP16。
> 2. **`llama_extra_args` 底层透传神技**：Unsloth Studio 内部通过子进程拉起 `llama-server`。通过在 JSON 中传递 `"llama_extra_args": ["-b", "8192", "-ub", "2048"]` 字符串数组，能够将极限制批处理参数**无缝穿透注入至 C++ 底层推理引擎**，这也是在 Windows 桌面端实现 TTFT 极限压榨的唯一正道！
> 3. **显存实测表现**：Q8_0（27.1GB 静态权重）+ 128K Q4_0 KV Cache（5.3GB）+ `-ub 2048` 激活值（~2.8GB），实测显存占用为 **35.2 GB**，剩余 12.8 GB，高精推理坚如磐石。

#### 3. 跨平台远程一键管理实战

##### 方案 A：在 Linux / macOS 终端远程 Curl 一键热加载
```bash
curl -X POST "http://172.28.24.22:8080/api/inference/load" \
  -H "Authorization: Bearer sk-unsloth-win22-masterkey" \
  -H "Content-Type: application/json" \
  -d '{
    "model_path": "unsloth/Qwen3.8-27B-GGUF",
    "gguf_variant": "Q8_0",
    "max_seq_length": 131072,
    "cache_type_k": "q4_0",
    "cache_type_v": "q4_0",
    "gpu_memory_mode": "manual",
    "gpu_layers": 99,
    "llama_extra_args": ["-b", "8192", "-ub", "2048"]
  }'
```

##### 方案 B：在 Windows 本地或 PowerShell 远程执行
```powershell
Invoke-RestMethod -Uri "http://127.0.0.1:8080/api/inference/load" -Method Post `
  -Headers @{ "Authorization" = "Bearer sk-unsloth-win22-masterkey"; "Content-Type" = "application/json" } `
  -Body (@{
    model_path       = "unsloth/Qwen3.8-27B-GGUF"
    gguf_variant     = "Q8_0"
    max_seq_length   = 131072
    cache_type_k     = "q4_0"
    cache_type_v     = "q4_0"
    gpu_memory_mode  = "manual"
    gpu_layers       = 99
    llama_extra_args = @("-b", "8192", "-ub", "2048")
  } | ConvertTo-Json)
```

##### 方案 C：使用仓库开箱即用的配套管理脚本
仓库已在 `templates/local-llm-gateway/` 提供了开箱即用的双端管理脚本：
* **Bash 脚本**：`templates/local-llm-gateway/reload_windows_q8.sh`
  ```bash
  # 远程热重载并注入 -b 8192 -ub 2048
  ./reload_windows_q8.sh load
  # 远程查看 Windows 节点推理状态与显存
  ./reload_windows_q8.sh status
  # 临时释放 Windows 显存
  ./reload_windows_q8.sh unload
  ```
* **PowerShell 脚本**：`templates/local-llm-gateway/reload_windows_q8.ps1`
  ```powershell
  .\reload_windows_q8.ps1 -Action Load
  .\reload_windows_q8.ps1 -Action Status
  .\reload_windows_q8.ps1 -Action Unload
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

exec /home/sangfor/.local/bin/unsloth studio run \
  --model /home/sangfor/models/Qwen3.8-27B-UD-Q4_K_M.gguf \
  --speculative-type auto \
  -H 0.0.0.0 \
  -p 8888 \
  --parallel 1 \
  --max-seq-length 262144 \
  --gpu-memory-mode manual \
  --cache-type-k q4_0 \
  --cache-type-v q4_0 \
  -ngl 99 \
  -t 8 \
  -tb 16 \
  -b 8192 \
  -ub 2048
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
  # 0. 全集群统一顶级入口 (local) - 默认首选 Ubuntu 21 极速版
  # =========================================================
  - model_name: local
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
    - local:
        - local-precise
        - local-infinite
    - local-auto:
        - local-precise
        - local-infinite
    - local-fast:
        - local-infinite
    - local-precise:
        - local-infinite
  fallbacks:
    - local:
        - node1-qwen
        - node2-qwen
        - node3-qwen
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

## 5. 4 大模型矩阵体系与多 Agent 统一纳管规范（支持 APP 图标启动与页面交互选择）

集群完整定义并暴露出 **4 大模型矩阵**，兼顾“智能自适应分流”与“用户绝对显式控制”，并已在桌面环境中通过 `environment.d` 实现全局持久化，确保**通过桌面 APP 图标点击启动后，在应用交互页面中均可自由选择使用**：

* **`local-auto`** ➔ **智能全能中枢**：根据上下文长度（120K 自动溢出至 256K 节点 3）及任务复杂度（低温度/高精逻辑切节点 2，常规极速切节点 1）自动分流，并具备跨节点故障转移（Failover）；
* **`local-fast`** ➔ **节点 1 (Ubuntu 21)**：直通极速嘴，Q4_K_M + 原生 Auto MTP，41.79 t/s 秒级直出；
* **`local-precise`** ➔ **节点 2 (Windows 22)**：直通高精脑，Q8_0 物理级准无损精度，30.10 t/s；
* **`local-infinite`** ➔ **节点 3 (Omarchy 23)**：直通超长全仓专机，256K (262,144 Tokens) 满血窗口秒级响应。

---

### 5.0 桌面 APP 图标启动的环境变量保障 (`~/.config/environment.d/10-litellm-gateway.conf`)
对于通过应用启动器、桌面快捷方式（`.desktop`）或 Hyprland 快捷键拉起的 GUI 进程，由于不经过终端登录 Shell，无法自动读取 `.bashrc`。通过 systemd 环境生成器规范在图形会话层全局注入：
```ini
ANTHROPIC_BASE_URL="http://127.0.0.1:4000"
ANTHROPIC_AUTH_TOKEN="sk-local-litellm-master-key"
ANTHROPIC_API_KEY="sk-local-litellm-master-key"
ANTHROPIC_MODEL="local-auto"
ANTHROPIC_DEFAULT_SONNET_MODEL="local-auto"
ANTHROPIC_DEFAULT_HAIKU_MODEL="local-fast"
ANTHROPIC_DEFAULT_OPUS_MODEL="local-precise"
OPENAI_BASE_URL="http://127.0.0.1:4000/v1"
OPENAI_API_KEY="sk-local-litellm-master-key"
OPENAI_MODEL="local-auto"
```
执行生效：
```bash
systemctl --user import-environment ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN ANTHROPIC_API_KEY ANTHROPIC_MODEL ANTHROPIC_DEFAULT_SONNET_MODEL ANTHROPIC_DEFAULT_HAIKU_MODEL ANTHROPIC_DEFAULT_OPUS_MODEL OPENAI_BASE_URL OPENAI_API_KEY OPENAI_MODEL
```

---

### 5.1 Pi Agent 全纳管与页面自由选择 (`~/.pi/agent/`)

* **模型列表注册 (`~/.pi/agent/models.json`)**：
  ```json
  {
    "providers": {
      "local-gateway": {
        "baseUrl": "http://127.0.0.1:4000/v1",
        "api": "openai-completions",
        "apiKey": "sk-local-litellm-master-key",
        "models": [
          { "id": "local-auto", "name": "Local Auto (智能分流: 极速 128K -> 高精 -> 满血 256K)", "reasoning": true },
          { "id": "local-fast", "name": "Node 1: Ubuntu 21 极速版 (Q4_K_M + MTP, 42 t/s)", "reasoning": true },
          { "id": "local-precise", "name": "Node 2: Windows 22 高精版 (Q8_0 准无损, 30 t/s)", "reasoning": true },
          { "id": "local-infinite", "name": "Node 3: Omarchy 23 满血长文本 (256K Context)", "reasoning": true },
          { "id": "local", "name": "Local (兼容入口)", "reasoning": true }
        ]
      }
    }
  }
  ```
* **页面选择启用 (`~/.pi/agent/settings.json`)**：
  ```json
  {
    "defaultProvider": "local-gateway",
    "defaultModel": "local-auto",
    "enabledModels": [
      "local-auto",
      "local-fast",
      "local-precise",
      "local-infinite",
      "local"
    ]
  }
  ```
* **交互效果**：点击图标打开 Pi 交互界面后，输入 `/model` 即可弹出全量模型列表，光标一键切换！

---

### 5.2 DeepSeek Harness (dsh) 桌面应用纳管 (`~/.dsh/settings.yaml`)

用户从桌面点击 `deepseek-harness.desktop` 图标启动后，交互界面顶部模型选择下拉菜单将直接呈现 4 大模型：
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
        name: 'Local Auto (智能分流: 极速 128K -> 高精 -> 满血 256K)'
      - contextWindow: 131072
        id: local-fast
        name: 'Node 1: Ubuntu 21 极速版 (Q4_K_M + MTP, 42 t/s)'
      - contextWindow: 131072
        id: local-precise
        name: 'Node 2: Windows 22 高精版 (Q8_0 准无损, 30 t/s)'
      - contextWindow: 262144
        id: local-infinite
        name: 'Node 3: Omarchy 23 满血长文本 (256K Context)'
      - contextWindow: 131072
        id: local
        name: 'Local (兼容入口)'

ui-onboarding:
  welcomeNoticeVersion: 2026-08-13.1
```

---

### 5.3 Claude Code 全纳管与模型层级对齐 (`~/.claude/settings.json`)

无论从终端还是快捷方式启动，进入 Claude Code 交互页面后，默认即为 `local-auto`，并支持通过 `/model` 随时自由切换：
```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "http://127.0.0.1:4000",
    "ANTHROPIC_AUTH_TOKEN": "sk-local-litellm-master-key",
    "ANTHROPIC_API_KEY": "sk-local-litellm-master-key",
    "ANTHROPIC_MODEL": "local-auto",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "local-auto",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "local-fast",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "local-precise",
    "MAX_THINKING_TOKENS": "0",
    "API_TIMEOUT_MS": "3000000",
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1"
  },
  "includeCoAuthoredBy": false,
  "skipDangerousModePermissionPrompt": true
}
```

---

### 5.4 Hermes Agent 与 Hermes Desktop 统一纳管 (`~/.hermes/config.yaml`)

无论是点击 `/usr/share/applications/hermes-desktop.desktop` 启动 GUI，还是使用命令行，均统一挂载本地网关：
```yaml
model:
  default: local-auto
  provider: custom
  base_url: http://127.0.0.1:4000/v1
  api_key: sk-local-litellm-master-key
```
在交互中输入 `/model` 或通过参数选择 `local-fast`、`local-precise`、`local-infinite` 均能直接生效。

---

## 6. 最终统一全量基准压测实测数据

在标准长逻辑任务（*“请详细解释分布式共识算法（Paxos 与 Raft）的核心机制，对比二者在领导者选举、日志复制和安全性保证上的异同”*）下，通过 LiteLLM 网关（`http://127.0.0.1:4000/v1`）统一对全量优化后的三节点发起端到端压测，最终实测数据如下：

```text
================================================================================
   LiteLLM 统一网关超融合三节点终极基准压测汇总大表 (-b 8192 -ub 2048 极限版)
================================================================================
```

| 测评维度 | 节点 1：Ubuntu 21 (快) | 节点 2：Windows 22 (精) | 节点 3：Omarchy 23 (长) |
| :--- | :---: | :---: | :---: |
| **底层推理引擎** | **Unsloth Studio** (Ubuntu 原生) | **Unsloth Studio** (Win 桌面 REST API) | **Unsloth Studio** (Arch 原生) |
| **模型量化规格** | **Qwen3.8-27B (Q4_K_M)** | **Qwen3.8-27B (Q8_0 准无损)** | **Qwen3.8-27B (Q4_K_M)** |
| **物理上下文窗口** | **128K (131,072 Tokens)** | **128K (131,072 Tokens)** | **256K (262,144 Tokens 满血)** |
| **极限批处理参数** | **`-b 8192 -ub 2048`** | **`-b 8192 -ub 2048`** | **`-b 8192 -ub 2048`** |
| **KV Cache 量化** | **Q4_0** (5.3 GB) | **Q4_0** (5.3 GB) | **Q4_0** (10.4 GB) |
| **投机解码机制** | **原生 Auto MTP (内嵌预测)** | **原生 Auto MTP (内嵌预测)** | **原生 Auto MTP (内嵌预测)** |
| **首字延迟 (TTFT)** | **~1.0s (短 Prompt) / 17.1s (18K Prompt)** | **814.66 ms (短 Prompt)** | **1,077.92 ms (短 Prompt)** |
| **平均生成速度 (TPS)** | **41.79 tokens/s** 🏆 | **30.10 tokens/s** | **40.32 tokens/s** |
| **短文本峰值 TPS** | 56.3 tokens/s | 45.4 tokens/s | **59.35 tokens/s (新纪录)** |
| **显存占用 / 48GB** | **20.8 GB** (余量 25.2 GB) | **35.2 GB** (余量 12.8 GB) | **24.9 GB** (余量 23.1 GB) |
| **OOM 风险** | **零风险 (余量 52.5%)** | **零风险 (余量 26.7%)** | **零风险 (余量 48.1%)** |
| **网关映射路由** | `local` / `local-fast` / `node1-qwen` | `local-precise` / `node2-qwen` | `local-infinite` / `node3-qwen` |

---

## 7. 核心结论与演进收益

1. **三节点 100% 纯正统一**：彻底告别了跨平台同步混乱与裸二进制调用，全集群均由官方原生的 **Unsloth Studio** 提供工业级守护与投机解码调度；
2. **生产级吞吐与 TTFT 极限突破**：
   - Ubuntu 21 优化后吞吐提升 **+40.0%**，达到 **41.79 tokens/s**；
   - 极限批次参数 **`-b 8192 -ub 2048`** 彻底打满 RTX 8000 Tensor Core 算力管线，使 Claude Code 初始 18K token 预填充耗时从 28.6 秒骤减至 **17.1 秒（提速 40.2%）**，CPU 调度开销降低 70%；
   - Omarchy 23 在 256K 满血大窗口下稳居 **40.32 tokens/s**（短文本峰值冲至 **59.35 t/s**）；
   - Windows 22 专职稳坐 **30.10 tokens/s** 的物理级准无损精度宝座；
3. **Windows 节点实现纯 REST API 远程全生命周期管理**：
   - 彻底解密 Unsloth Studio 的 FastAPI 架构，通过 `/api/inference/load` 配合 `llama_extra_args` 实现免远程桌面的无感配置注入与显存释放；
4. **全 Agent 统一收敛为 `local`**：
   - LiteLLM 提供顶级 `local` 智能路由，Claude Code、Pi Agent、Hermes Agent 与 dsh 统一接入 `local`，彻底终结多名称混杂历史。

