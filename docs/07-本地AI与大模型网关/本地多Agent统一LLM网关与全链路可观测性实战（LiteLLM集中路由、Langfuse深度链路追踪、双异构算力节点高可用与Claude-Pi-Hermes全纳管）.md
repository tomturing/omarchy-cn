# 本地多 Agent 统一 LLM 网关与全链路可观测性实战

> 涵盖：LiteLLM Proxy 集中路由、Langfuse 本地自建可观测性大屏、三节点异构私有算力集群（Ubuntu Q4_K_M + Windows Q8_0 + Omarchy 256K）高可用与自动 Fallback 熔断、Claude Code / Pi / Hermes / Antigravity 全 Agent 统一接入及源码级避坑实录。

---

## 一、核心痛点与问题背景

在现代 Arch Linux + Hyprland (Omarchy) 极客开发工作流中，开发者往往同时常驻运行多个专门的 AI 编码助手与智能体（Agent），例如：
* **Claude Code**：用于工程级终端代码编辑与自动化排错；
* **Pi Agent**：轻量级实时交互与快捷查询小助手；
* **Hermes Agent**：支持复杂会话状态、长期记忆与工具调用的自主 Agent；
* **Antigravity**：Google DeepMind 出品的高阶配对编程助手。

与此同时，本地局域网内通常接入了不同配置的私有推理服务器（如 Linux/Windows/Omarchy 三节点运行 Unsloth Studio），并结合云端 API（如阿里百炼 DashScope、DeepSeek 等）。在这种高度异构的多 Agent、多模型环境下，开发者普遍面临以下**四大核心痛点**：

| 痛点分类 | 典型故障表现 | 底层根因分析 |
| :--- | :--- | :--- |
| **痛点 1：密钥与配置碎片化，维护极其痛苦** | 轮换一次 API Key 或调整模型地址，需要翻找修改 `~/.pi/agent/`、`~/.claude/`、`~/.hermes/` 及 Shell 环境变量等数个互不相干的配置文件。 | 各 Agent 客户端独立管理上游 Provider，缺少统一的反向代理接入层。 |
| **痛点 2：协议壁垒与专有格式冲突** | Claude Code 强制要求 Anthropic Messages 协议（`/v1/messages`），而私有算力池（Unsloth Studio）仅暴露 OpenAI 兼容接口，导致私有算力无法直接供给 Claude 使用。 | 缺少双向协议映射中间件（OpenAI ⇋ Anthropic 互相转换）。 |
| **痛点 3：缺少高可用、负载均衡与容灾熔断** | 私有服务器因长上下文爆显存或离线时，所有 CLI 任务直接抛出 HTTP 500/Connection Refused 报错崩溃中断。 | 缺少上游健康探活、动态路由重试与自动降级（Fallback）机制。 |
| **痛点 4：完全缺乏调用可观测性（黑盒运行）** | Agent 工具调用（Tool Calling）失败时不知传参内容；思维链（Reasoning）被隐藏；不知晓各任务的实时 Token 消耗与推理耗时分布。 | 缺乏统一的 LLM 工程可观测性追踪面板（Traces & Metrics）。 |

为一劳永逸彻底解决上述问题，本文基于 **LiteLLM Proxy** 打造本地统一集中网关，自建轻量级 **Langfuse v2** 可观测性平台，并将局域网内三节点异构私有算力集群统一调度，实现各大 Agent 的透明化全纳管。

---

## 二、多 Agent 与三节点异构算力全链路拓扑图

```mermaid
flowchart TD
    subgraph Clients ["本地 AI 编码助手 (Clients / Agents)"]
        C1["Claude Code<br/>(Anthropic 协议: /v1/messages)"]
        C2["Pi Agent<br/>(OpenAI 协议: /v1/chat/completions)"]
        C3["Hermes Agent<br/>(OpenAI 协议 / 复杂工具链)"]
        C4["Antigravity<br/>(OpenAI 协议 / ANTHROPIC env)"]
    end

    subgraph Gateway ["LiteLLM 统一网关 (localhost:4000)"]
        direction TB
        GW_CORE["LiteLLM Proxy Core<br/>(systemd 用户守护进程)"]
        GW_MAP["双向协议转换 + 模型别名映射 + drop_params 过滤"]
        GW_ROUTER["智能负载均衡 + 故障自动降级 (Fallback)"]
        GW_METRICS["Prometheus Metrics (/metrics/) + Swagger UI (/docs)"]

        GW_CORE --> GW_MAP
        GW_MAP --> GW_ROUTER
        GW_CORE --> GW_METRICS
    end

    subgraph Observability ["全链路可观测性大屏 (localhost:3000)"]
        LF_WEB["Langfuse Web UI / Ingestion API"]
        LF_DB[("PostgreSQL 15 持久化库")]
        LF_WEB --- LF_DB
    end

    subgraph Private_Cluster ["局域网私有异构算力集群 (三节点 Unsloth Studio)"]
        N1["节点 1: Ubuntu 21 (172.28.24.21:8888)<br/>Qwen3.8-27B Q4_K_M + MTP · 128K · 41 t/s"]
        N2["节点 2: Windows 22 (172.28.24.22:8080)<br/>Qwen3.8-27B Q8_0 高精度 · 128K · 30 t/s"]
        N3["节点 3: Omarchy 23 (172.28.24.23:8888)<br/>Qwen3.8-27B Q4_K_M + MTP · 256K · 40 t/s"]
    end

    subgraph Cloud ["云端提供商 (可选备用)"]
        CLOUD_ALI["阿里百炼 DashScope<br/>(Qwen-Plus / GLM-5 / Kimi-K2)"]
        CLOUD_DS["DeepSeek<br/>(deepseek-chat / deepseek-reasoner)"]
    end

    C1 -->|统一虚拟 Key: sk-local-litellm-master-key| GW_CORE
    C2 -->|统一虚拟 Key: sk-local-litellm-master-key| GW_CORE
    C3 -->|统一虚拟 Key: sk-local-litellm-master-key| GW_CORE
    C4 -->|统一虚拟 Key: sk-local-litellm-master-key| GW_CORE

    GW_CORE -.->|异步推送 Trace / Span / Tokens / 延迟| LF_WEB
    GW_ROUTER -->|local-auto / local-fast · 极速| N1
    GW_ROUTER -->|local-precise · 高精度| N2
    GW_ROUTER -->|local-infinite · 256K 超长上下文| N3
    GW_ROUTER -.->|云端兜底| CLOUD_ALI
    GW_ROUTER -.->|云端兜底| CLOUD_DS
```

---

## 三、三节点异构算力池接入与智能路由设计

### 1. 物理节点与规格参数

| 节点 | 地址 | 系统 | 模型 | 量化 | 上下文 | 实测吞吐 | 适用场景 |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **节点 1 (Ubuntu 21)** | `172.28.24.21:8888` | Ubuntu + Unsloth Studio | Qwen3.8-27B-UD-Q4_K_M | Q4_K_M + MTP | 128K | **~41 t/s** | 极速日常编码、实时交互 |
| **节点 2 (Windows 22)** | `172.28.24.22:8080` | Windows + Unsloth Studio | Qwen3.8-27B-GGUF | Q8_0 无损 | 128K | **~30 t/s** | 高精度代码审查、复杂推理 |
| **节点 3 (Omarchy 23)** | `172.28.24.23:8888` | Omarchy + Unsloth Studio | Qwen3.8-27B-UD-Q4_K_M | Q4_K_M + MTP | **256K** | **~40 t/s** | 超长上下文、全库分析 |

### 2. 网关模型路由别名设计

网关层对上层 Agent 暴露以下统一别名：

| 别名 | 路由目标 | 使用场景 |
| :--- | :--- | :--- |
| `local-auto` / `local-fast` / `local-qwen` | 节点 1 (Ubuntu · Q4_K_M · 极速) | 默认首选，日常编码 |
| `local-precise` / `node2-qwen` | 节点 2 (Windows · Q8_0 · 高精度) | 需要高精度时强制指定 |
| `local-infinite` / `node3-qwen` | 节点 3 (Omarchy · 256K · 超长上下文) | 全库分析、超长文档 |
| `claude-3-7-sonnet-20250219` | → 节点 1 (映射别名) | Claude Code 透明无感接入 |
| `claude-3-5-sonnet-20241022` | → 节点 2 (映射别名) | Claude Code 透明无感接入 |
| `claude-3-5-haiku-20241022` | → 节点 1 (映射别名) | Claude Code 透明无感接入 |

> **Fallback 降级链**：`local-auto` → 节点 1 故障自动切节点 2 → 节点 2 故障兜底至云端。

---

## 四、LiteLLM 网关落地与源码级避坑实录

### 1. 虚拟环境与守护进程部署

```bash
# 创建独立环境并安装 LiteLLM (使用 uv 极速包管理器)
mkdir -p ~/.config/litellm
cd ~/.config/litellm
uv venv
uv pip install "litellm[proxy]" "langfuse<3" "prometheus-client"
```

编写 systemd 用户单元文件 `~/.config/systemd/user/litellm.service`：
```ini
[Unit]
Description=LiteLLM Unified Proxy & Observability Gateway
After=network.target

[Service]
Type=simple
WorkingDirectory=%h/.config/litellm
ExecStart=%h/.config/litellm/.venv/bin/litellm --config %h/.config/litellm/config.yaml --port 4000
Restart=always
RestartSec=3
StandardOutput=journal
StandardError=journal
Environment="PYTHONUNBUFFERED=1"
Environment="DOCS_URL=/docs"

[Install]
WantedBy=default.target
```

激活并启动服务：
```bash
systemctl --user daemon-reload
systemctl --user enable --now litellm.service
```

### 2. 核心踩坑与根治方案

#### 踩坑 1：浏览器访问 `/docs` 返回 404
* **源码根因**：LiteLLM 默认 Swagger UI 挂载在根路径 `/` 而非 `/docs`。
* **根治方案**：在 systemd 服务中注入 `Environment="DOCS_URL=/docs"`，重启后 `/docs` 正常。

#### 踩坑 2：Claude Code 触发本地模型报 500 Jinja Exception
* **现象**：`Error: Jinja Exception: Unexpected reasoning effort high`
* **根因**：Claude Code 默认发送 `reasoning_effort: "high"`，本地 Unsloth 模板仅接受 `xhigh/medium/low`。
* **根治方案**：在 `config.yaml` 中过滤掉该参数：
  ```yaml
  litellm_params:
    drop_params: true
    additional_drop_params: ["reasoning_effort"]
  ```
  并在 `~/.claude/settings.json` 配置 `"MAX_THINKING_TOKENS": "0"` 协同关闭思维链。

---

## 五、Langfuse 本地自建版全链路可观测性大屏

### 1. 轻量化 Docker 架构选型

选用 **Langfuse v2**（仅需 PostgreSQL 15 + Web 容器，常驻内存 ~300MB），避免 v3/v4 强制引入 ClickHouse/MinIO/Redis 导致吃掉 4GB+ 内存。

`~/.config/langfuse/docker-compose.yml`：
```yaml
services:
  postgres:
    image: postgres:15-alpine
    container_name: langfuse-postgres
    restart: always
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: langfuse_password_secure
      POSTGRES_DB: langfuse
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 3s
      timeout: 3s
      retries: 10

  langfuse:
    image: ghcr.io/langfuse/langfuse:2
    container_name: langfuse-server
    restart: always
    depends_on:
      postgres:
        condition: service_healthy
    environment:
      DATABASE_URL: postgresql://postgres:${POSTGRES_PASSWORD:-langfuse_password_secure}@postgres:5432/langfuse
      NEXTAUTH_URL: http://localhost:3000
      NEXTAUTH_SECRET: ${NEXTAUTH_SECRET:-your_nextauth_secret_generate_with_openssl}
      SALT: ${SALT:-your_salt_generate_with_openssl}
      ENCRYPTION_KEY: ${ENCRYPTION_KEY:-your_encryption_key_generate_with_openssl}
      TELEMETRY_ENABLED: "false"
    ports:
      - "3000:3000"

volumes:
  pgdata:
```

### 2. 可观测性联动避坑：Python SDK 版本断裂

* **现象**：`AttributeError: module 'langfuse' has no attribute 'version'`
* **根因**：安装了 `langfuse>=4.0`，LiteLLM 回调模块调用了旧版路径。
* **根治方案**：`uv pip install "langfuse<3"`

---

## 六、全 Agent 统一接入配置实录（三节点版）

> **核心设计原则**：所有 Agent 统一指向 LiteLLM 网关（`http://127.0.0.1:4000`），使用同一个 master key，网关侧集中管理上游路由与密钥轮换。

### 0. Shell 全局环境变量（所有 Agent 的兜底层）

在 `~/.bashrc` 中注入统一环境变量，覆盖所有通过 Shell 启动的 CLI 工具：

```bash
# ============================================================
# 统一本地 LiteLLM 网关 —— 所有 Agent 使用同一套配置
# Base: http://127.0.0.1:4000 (OpenAI compat: /v1)
# Master Key: sk-local-litellm-master-key
# ============================================================
export ANTHROPIC_BASE_URL="http://127.0.0.1:4000"
export ANTHROPIC_API_KEY="sk-local-litellm-master-key"
export ANTHROPIC_AUTH_TOKEN="sk-local-litellm-master-key"   # Claude Code 备用变量名

export OPENAI_BASE_URL="http://127.0.0.1:4000/v1"          # Codex / OpenAI SDK
export OPENAI_API_KEY="sk-local-litellm-master-key"

export DEEPSEEK_BASE_URL="http://127.0.0.1:4000"
export DEEPSEEK_API_KEY="sk-local-litellm-master-key"
```

> **为什么需要多个变量名**：不同 Agent 读取的环境变量名不一致——Claude Code 优先读 `ANTHROPIC_AUTH_TOKEN`，OpenAI SDK 读 `OPENAI_API_KEY`，DeepSeek 客户端读 `DEEPSEEK_API_KEY`。统一写入后，新开任何 terminal 均自动继承。

### 1. Claude Code 全纳管配置

编辑 `~/.claude/settings.json`：
```json
{
  "env": {
    "ANTHROPIC_AUTH_TOKEN": "sk-local-litellm-master-key",
    "ANTHROPIC_BASE_URL": "http://127.0.0.1:4000",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "claude-3-5-haiku-20241022",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "claude-3-7-sonnet-20250219",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "claude-3-7-sonnet-20250219",
    "ANTHROPIC_MODEL": "claude-3-7-sonnet-20250219",
    "API_TIMEOUT_MS": "3000000",
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1"
  },
  "includeCoAuthoredBy": false,
  "skipDangerousModePermissionPrompt": true,
  "theme": "light"
}
```

> `claude-3-7-sonnet-20250219` 等别名在 LiteLLM 中映射至节点 1/2，Claude Code 完全无感知地使用本地推理服务。

### 2. Pi Agent 全纳管配置

**关键变更**：`models.json` 必须含 `apiKey` 字段，否则鉴权静默失败（Pi 不报错，但请求会被 LiteLLM 拒绝）。

编辑 `~/.pi/agent/models.json`：
```json
{
  "providers": {
    "local-gateway": {
      "baseUrl": "http://127.0.0.1:4000/v1",
      "api": "openai-completions",
      "apiKey": "sk-local-litellm-master-key",
      "models": [
        {
          "id": "local-auto",
          "name": "Node 1: Ubuntu 21 极速版 (Q4_K_M + MTP, 128K)",
          "reasoning": true
        },
        {
          "id": "local-precise",
          "name": "Node 2: Windows 22 高精版 (Q8_0 无损, 128K)",
          "reasoning": true
        },
        {
          "id": "local-infinite",
          "name": "Node 3: Omarchy 23 满血长文本 (Q4_K_M, 256K)",
          "reasoning": true
        },
        {
          "id": "local-qwen",
          "name": "Local Auto (Node 1 优先，自动故障切换)",
          "reasoning": true
        },
        {
          "id": "qwen-plus",
          "name": "Aliyun DashScope Qwen Plus"
        },
        {
          "id": "glm-5",
          "name": "GLM-5",
          "reasoning": true
        }
      ]
    }
  }
}
```

编辑 `~/.pi/agent/settings.json`：
```json
{
  "theme": "omarchy-system",
  "defaultProvider": "local-gateway",
  "defaultModel": "local-auto",
  "enabledModels": [
    "local-auto",
    "local-precise",
    "local-infinite",
    "local-qwen",
    "qwen-plus",
    "glm-5"
  ],
  "retry": {
    "enabled": true,
    "provider": {
      "timeoutMs": 3000000
    }
  },
  "enableInstallTelemetry": false,
  "enableAnalytics": false
}
```

### 3. Hermes Agent 全纳管配置

编辑 `~/.hermes/config.yaml` 中的 model 节：
```yaml
model:
  default: local-qwen
  provider: custom
  base_url: http://127.0.0.1:4000/v1
  api_key: sk-local-litellm-master-key
```

在交互中可通过参数随时指定特定节点：
```bash
hermes chat --model local-auto     # 极速（节点 1）
hermes chat --model local-precise  # 高精度（节点 2）
hermes chat --model local-infinite # 256K 超长（节点 3）
```

### 4. dsh (Pi CLI) 全纳管配置

编辑 `~/.dsh/settings.yaml`：
```yaml
agent-default-model:
  model: local-auto
  provider: local-gateway
llm-pi-ai:
  providers:
    local-gateway:
      api: openai-completions
      apiKeyEnv: DEEPSEEK_API_KEY    # 读取 ~/.bashrc 中统一注入的 master key
      baseURL: http://127.0.0.1:4000/v1
      displayName: Local Gateway (LiteLLM 三节点集群)
      models:
        - contextWindow: 131072
          id: local-auto
          name: "Node 1: Ubuntu 21 极速版 (Q4_K_M + MTP, 80 t/s)"
        - contextWindow: 131072
          id: local-fast
          name: "Node 1: Ubuntu 21 极速版 (Q4_K_M + MTP, 80 t/s)"
        - contextWindow: 131072
          id: local-precise
          name: "Node 2: Windows 22 高精版 (Q8_0 无损精度)"
        - contextWindow: 262144
          id: local-infinite
          name: "Node 3: Omarchy 23 满血长文本 (256K Context)"
```

### 5. Antigravity（本机 AGY）

Antigravity 通过 Shell 环境变量读取 `ANTHROPIC_BASE_URL` 和 `ANTHROPIC_API_KEY`，已在 `~/.bashrc` 统一注入，无需额外配置文件。

### 6. Codex（ChatGPT Desktop）— 架构性限制说明

> **⚠️ Codex 无法接入本地网关**：Codex 是 OpenAI 出品的 Electron GUI 应用，通过 OAuth 账号登录认证，不读取 `OPENAI_BASE_URL` 环境变量，不支持 `base_url` 重定向，属于产品架构封闭限制，无法绕过。

已在 `~/.bashrc` 写入 `OPENAI_BASE_URL` 以覆盖命令行工具（如 `openai` Python SDK、`curl` 脚本等），但 Codex GUI 进程不受影响。

---

## 七、各 Agent 接入状态汇总（最新）

| Agent | 接入方式 | Base URL | API Key | 默认模型 | 状态 |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Claude Code** | `~/.claude/settings.json` env | `http://127.0.0.1:4000` | master-key | `claude-3-7-sonnet-20250219` | ✅ 已接入 |
| **Pi Agent** | `~/.pi/agent/models.json` | `http://127.0.0.1:4000/v1` | master-key（直接写入） | `local-auto` | ✅ 已接入 |
| **Hermes** | `~/.hermes/config.yaml` | `http://127.0.0.1:4000/v1` | master-key（直接写入） | `local-qwen` | ✅ 已接入 |
| **dsh** | `~/.dsh/settings.yaml` | `http://127.0.0.1:4000/v1` | `$DEEPSEEK_API_KEY` env | `local-auto` | ✅ 已接入 |
| **Antigravity** | Shell env (`~/.bashrc`) | `http://127.0.0.1:4000` | `$ANTHROPIC_API_KEY` env | `local-auto` | ✅ 已接入 |
| **Codex** | ❌ 账号登录 (OAuth) | 不支持重定向 | OpenAI 账号 | gpt-5.x | ⚠️ 架构限制，无法接入 |

---

## 八、日常运维、健康诊断与自愈手册

### 1. 核心状态检查命令

```bash
# 1. 检查网关运行状态
systemctl --user status litellm

# 2. 查看网关实时结构化调用日志
journalctl --user -u litellm -f

# 3. 检查三节点实时探活情况
curl -s -H "Authorization: Bearer sk-local-litellm-master-key" \
  http://localhost:4000/health | jq '{healthy_count, unhealthy_count}'

# 4. 快速验证三节点全通
for node in local-auto local-precise local-infinite; do
  echo -n "[$node] "
  curl -s http://localhost:4000/v1/chat/completions \
    -H "Authorization: Bearer sk-local-litellm-master-key" \
    -H "Content-Type: application/json" \
    -d "{\"model\": \"$node\", \"messages\": [{\"role\": \"user\", \"content\": \"hi\"}], \"max_tokens\": 5}" \
    | jq -r '.choices[0].message.content // .error.message'
done
```

### 2. 常用故障排错速查表

| 故障表现 | 排查方向 | 快速自愈命令 |
| :--- | :--- | :--- |
| **Agent 请求报 Connection Refused** | LiteLLM 进程未启动或端口被占 | `systemctl --user restart litellm && journalctl --user -u litellm -n 30` |
| **Claude 报错 Unexpected reasoning effort** | `config.yaml` 漏配参数丢弃 | 确认 `additional_drop_params: ["reasoning_effort"]` 已配置并重启网关 |
| **Pi Agent 鉴权失败（静默）** | `models.json` 缺 `apiKey` 字段 | 检查并补全 `~/.pi/agent/models.json` 中的 `"apiKey"` |
| **Langfuse 无新增调用记录** | API Key 绑定或依赖版本断裂 | 检查 `journalctl --user -u litellm` 是否有 Auth/Version 报错 |
| **新 shell 环境变量未生效** | `.bashrc` 尚未 source | `source ~/.bashrc` 或重新开 terminal |
| **私有节点响应变慢或显存用尽** | 切换到另一节点 | `pi --model local-precise` 或 `hermes chat --model local-infinite` |
