# 本地多 Agent 统一 LLM 网关与全链路可观测性实战
> 涵盖：LiteLLM Proxy 集中路由、Langfuse 本地自建可观测性大屏、双异构私有算力节点（Linux Q8_0 + Win Q4_K）高可用与自动 Fallback 熔断、Claude Code / Pi / Hermes 全 Agent 无缝纳管及源码级避坑实录。

---

## 一、核心痛点与问题背景

在现代 Arch Linux + Hyprland (Omarchy) 极客开发工作流中，开发者往往同时常驻运行多个专门的 AI 编码助手与智能体（Agent），例如：
* **Claude Code**：用于工程级终端代码编辑与自动化排错；
* **Pi Agent**：轻量级实时交互与快捷查询小助手；
* **Hermes Agent**：支持复杂会话状态、长期记忆与工具调用的自主 Agent。

与此同时，本地局域网内通常接入了不同配置的私有推理服务器（如 Linux GPU 工作站、Windows 本地算力机运行 llama.cpp / Unsloth Studio），并结合云端 API（如阿里百炼 DashScope、DeepSeek 等）。在这种高度异构的多 Agent、多模型环境下，开发者普遍面临以下**四大核心痛点**：

| 痛点分类 | 典型故障表现 | 底层根因分析 |
| :--- | :--- | :--- |
| **痛点 1：密钥与配置碎片化，维护极其痛苦** | 轮换一次 API Key 或调整模型地址，需要翻找修改 `~/.pi/agent/`、`~/.claude/`、`~/.hermes/` 及 Shell 环境变量等数个互不相干的配置文件。 | 各 Agent 客户端独立管理上游 Provider，缺少统一的反向代理接入层。 |
| **痛点 2：协议壁垒与专有格式冲突** | Claude Code 强制要求 Anthropic Messages 协议（`/v1/messages`），而私有算力池（llama.cpp / Unsloth）仅暴露 OpenAI 兼容接口，导致私有算力无法直接供给 Claude 使用。 | 缺少双向协议映射中间件（OpenAI ⇋ Anthropic 互相转换）。 |
| **痛点 3：缺少高可用、负载均衡与容灾熔断** | 私有服务器因长上下文爆显存或离线时，所有 CLI 任务直接抛出 HTTP 500/Connection Refused 报错崩溃中断。 | 缺少上游健康探活、动态路由重试与自动降级（Fallback）机制。 |
| **痛点 4：完全缺乏调用可观测性（黑盒运行）** | Agent 工具调用（Tool Calling）失败时不知传参内容；思维链（Reasoning）被隐藏；不知晓各任务的实时 Token 消耗与推理耗时分布。 | 缺乏统一的 LLM 工程可观测性追踪面板（Traces & Metrics）。 |

为一劳永逸彻底解决上述问题，本文基于 **LiteLLM Proxy** 打造本地统一集中网关，自建轻量级 **Langfuse v2** 可观测性平台，并将局域网内双异构私有算力集群统一调度，实现各大 Agent 的透明化全纳管。

---

## 二、多 Agent 与异构算力全链路拓扑图

```mermaid
flowchart TD
    subgraph Clients ["本地 AI 编码助手 (Clients / Agents)"]
        C1["Claude Code<br/>(Anthropic 协议: /v1/messages)"]
        C2["Pi Agent<br/>(OpenAI 协议: /v1/chat/completions)"]
        C3["Hermes Agent<br/>(OpenAI 协议 / 复杂工具链)"]
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

    subgraph Private_Cluster ["局域网私有异构算力集群 (Unsloth / llama.cpp)"]
        N1["节点 1: Linux 服务器 (192.168.1.101:8888)<br/>Qwen 3.8 27B Q8_0 (高精度主力)"]
        N2["节点 2: Windows 工作站 (192.168.1.102:8080)<br/>Qwen 3.8 27B Q4_K_M (轻量快速/热备)"]
    end

    subgraph Cloud ["云端提供商 (可选备用)"]
        CLOUD_ALI["阿里百炼 DashScope<br/>(Qwen-Plus / GLM-5)"]
    end

    C1 -->|统一虚拟 Key: sk-local-master-key-example| GW_CORE
    C2 -->|统一虚拟 Key: sk-local-master-key-example| GW_CORE
    C3 -->|统一虚拟 Key: sk-local-master-key-example| GW_CORE

    GW_CORE -.->|异步推送 Trace / Span / Tokens / 延迟| LF_WEB
    GW_ROUTER -->|优先路由 / 高精度| N1
    GW_ROUTER -.->|节点1异常时自动熔断备用| N2
    GW_ROUTER -.->|云端兜底| CLOUD_ALI
```

---

## 三、双异构算力池接入与智能路由设计

集群中接入了两台提供不同精度与算力特性的私有推理服务器：

### 1. 物理节点与规格参数

| 节点标识 | 物理服务器与监听地址 | 加载模型 (Model ID) | 量化精度与特性 | 适用工作负载场景 |
| :--- | :--- | :--- | :--- | :--- |
| **节点 1 (Linux)** | `http://192.168.1.101:8888/v1` | `unsloth-Qwen3.8-27B-Q8_0` | **Q8_0 (高精度)**<br>保留绝大部分浮点精度，推理逻辑严密 | 核心代码重构、复杂 Agent 工具决策、疑难 Bug 排查 |
| **节点 2 (Windows)** | `http://192.168.1.102:8080/v1` | `Qwen3.8-27B-GGUF` | **Q4_K_M (轻量量化)**<br>显存占用低，首字生成速度极快 | 日常快速问答、常规补全、作为节点 1 的灾备冗余 |

### 2. 网关模型暴露与智能路由规则

在 LiteLLM 网关层对上层 Agent 暴露以下模型：
1. **`node1-qwen` / `qwen-q8`**：强制打到节点 1（Linux Q8_0 高精度）。
2. **`node2-qwen` / `qwen-q4`**：强制打到节点 2（Windows Q4_K 快速）。
3. **`local-qwen`（智能路由别名）**：
   * 默认优先路由至 **节点 1 (Linux Q8_0)**；
   * 一旦节点 1 离线或出现 HTTP 500/超时，LiteLLM Router 在毫秒级内自动 **Fallback 降级至节点 2 (Windows Q4_K)**，上层 Agent 零感知。
4. **`claude-3-7-sonnet-20250219` 等别名**：映射至本地算力，无缝接管 Claude Code。

---

## 四、LiteLLM 网关落地与源码级避坑实录

### 1. 虚拟环境与守护进程部署

采用独立 Python 虚拟环境与 systemd 用户服务进行管理，确保开机自启且无环境污染：

```bash
# 1. 创建独立环境并安装 LiteLLM 代理与依赖 (使用 uv 极速包管理器)
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

---

### 2. 核心踩坑与根治方案

#### 踩坑 1：浏览器访问 `http://localhost:4000/docs` 返回 404
* **现象**：浏览器打开 `/docs` 报错 `{"detail":"Not Found"}`。
* **源码根因**：查阅 LiteLLM 源码 `litellm/proxy/utils.py`：
  ```python
  def _get_docs_url() -> str | None:
      if docs_url := os.getenv("DOCS_URL"):
          return docs_url
      if str_to_bool(os.getenv("NO_DOCS")) is True:
          return None
      return "/"  # 默认 Swagger UI 挂载在根路径 "/"，而非 "/docs"
  ```
* **根治方案**：在 systemd 服务配置中显式注入环境变量 `Environment="DOCS_URL=/docs"`，重启后 `/docs` 正常输出完整的 Swagger UI 交互控制台。

#### 踩坑 2：`/metrics/` 输出大量非排版纯文本
* **现象**：浏览器打开 `/metrics/` 看到纯文本形式的 `# HELP litellm_requests_metric ...`。
* **根因解释**：`/metrics` 属于标准的云原生 Prometheus Exporter 接口规范，专供 Prometheus Server 或 Datadog 周期性拉取监控指标，并非面向人类的图形化前端。图形化调用监控统一交由 Langfuse 实现。

#### 踩坑 3：Claude Code 触发本地模型报 500 Jinja Exception
* **现象**：Claude Code 向网关发起请求后，LiteLLM 报错：
  ```text
  Error: Jinja Exception: Unexpected reasoning effort high. Supported types are xhigh (default), medium, and low.
  ```
* **源码根因**：Claude Code 默认会发送 Anthropic 的扩展思考参数（Extended Thinking），LiteLLM 在将 `/v1/messages` 转换为 OpenAI 兼容接口时，自动追加了 `reasoning_effort: "high"`。然而本地私有模型（llama.cpp / Unsloth GGUF）内置的 Jinja 模板校验仅允许 `xhigh`、`medium` 或 `low`，遇到 `high` 直接抛出模板异常并中断生成。
* **根治方案**：在 `config.yaml` 中配置参数清洗过滤：
  ```yaml
  litellm_params:
    drop_params: true
    additional_drop_params: ["reasoning_effort"]
  ```
  并在 `~/.claude/settings.json` 中配置 `"MAX_THINKING_TOKENS": "0"` 协同关闭未知模型的过度推理参数，彻底消除 500 报错。

---

## 五、Langfuse 本地自建版全链路可观测性大屏

### 1. 轻量化 Docker 架构选型

为了避免官方最新 v3/v4 版本因强制引入 ClickHouse、MinIO、Redis 导致常驻吃掉 4GB+ 内存，在本地开发环境选用经典稳定的 **Langfuse v2**（仅需 PostgreSQL 15 容器 + Web 容器，常驻仅吃 ~300MB 内存）。

创建配置文件目录 `~/.config/langfuse/docker-compose.yml`：
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

### 2. 权限打通与一键管理

配置 sudoers 免密规则，避免管理容器时被指纹验证超时拦截：
```bash
echo "tom ALL=(ALL) NOPASSWD: /usr/bin/docker, /usr/bin/docker-compose" | sudo tee /etc/sudoers.d/tom-docker
chmod 440 /etc/sudoers.d/tom-docker
```

一键拉起 Langfuse 服务：
```bash
sudo docker compose -f ~/.config/langfuse/docker-compose.yml up -d
```
启动完成后即可在浏览器中访问：**`http://localhost:3000`**。

### 3. 可观测性联动避坑：Python SDK 版本断裂

* **现象**：在 LiteLLM 中配置 `callbacks: ["langfuse"]` 后，控制台抛出异常：
  ```text
  AttributeError: module 'langfuse' has no attribute 'version'
  ```
* **源码根因**：安装了过新的 `langfuse>=4.0`，其内部调整了模块导出方式；而 LiteLLM 的回调模块中调用了 `langfuse.version.__version__`。
* **根治方案**：将虚拟环境中的 SDK 锁定为 v2 兼容版：
  ```bash
  uv pip install "langfuse<3"
  ```

### 4. 自动绑定与生效验证

使用自动化绑定脚本 `link-litellm.sh` 将 Langfuse 项目中生成的 `Public Key` 与 `Secret Key` 注入 LiteLLM：
```bash
~/.config/langfuse/link-litellm.sh "pk-lf-..." "sk-lf-..."
```
当任意 Agent 发起请求时，LiteLLM 会将事件异步推送到 `http://localhost:3000/api/public/ingestion`。
在 Langfuse Web 界面的 **Tracing -> Traces** 页面即可看到：
* `litellm-acompletion`（来自 Pi/Hermes 等 OpenAI 格式调用的追踪）
* `litellm-anthropic_messages`（来自 Claude Code 的调用追踪）
* 请求详情中包含完整的 Prompt、最终输出、思维链内容、Prompt Tokens、Completion Tokens 与精确耗时。

---

## 六、本地三大 Agent 全纳管配置实录

各 Agent 原始配置文件已全量备份至 `~/.agent_configs_backup_<时间戳>/`。

### 1. Pi Agent 全纳管配置

编辑 `~/.pi/agent/models.json`：
```json
{
  "providers": {
    "local-gateway": {
      "baseUrl": "http://127.0.0.1:4000/v1",
      "api": "openai-completions",
      "models": [
        {
          "id": "node1-qwen",
          "name": "Node 1: Linux Qwen 3.8 27B (Q8_0 高精度)",
          "reasoning": true
        },
        {
          "id": "node2-qwen",
          "name": "Node 2: Windows Qwen 3.8 27B (Q4_K_M 快速)",
          "reasoning": true
        },
        {
          "id": "local-qwen",
          "name": "Local Auto (Node 1 优先，故障切 Node 2)",
          "reasoning": true
        },
        {
          "id": "qwen-plus",
          "name": "Aliyun DashScope Qwen Plus"
        }
      ]
    }
  }
}
```

编辑 `~/.pi/agent/auth.json`：
```json
{
  "local-gateway": {
    "type": "api_key",
    "key": "sk-local-litellm-master-key-example"
  }
}
```

编辑 `~/.pi/agent/settings.json`：
```json
{
  "defaultProvider": "local-gateway",
  "defaultModel": "node1-qwen",
  "enabledModels": ["node1-qwen", "node2-qwen", "local-qwen", "qwen-plus"]
}
```

### 2. Hermes Agent 全纳管配置

编辑 `~/.hermes/config.yaml`：
```yaml
model:
  default: local-qwen
  provider: custom
  base_url: http://127.0.0.1:4000/v1
  api_key: sk-local-litellm-master-key-example
```

在交互中可通过参数随时指定特定节点：
```bash
hermes chat --model node1-qwen   # 强制指定 Linux Q8_0
hermes chat --model node2-qwen   # 强制指定 Windows Q4_K_M
```

### 3. Claude Code 全纳管配置

编辑 `~/.claude/settings.json`：
```json
{
  "env": {
    "ANTHROPIC_AUTH_TOKEN": "sk-local-litellm-master-key-example",
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

在 `~/.bashrc` 中注入环境变量持久化：
```bash
export ANTHROPIC_BASE_URL="http://127.0.0.1:4000"
export ANTHROPIC_API_KEY="sk-local-litellm-master-key-example"
```

---

## 七、日常运维、健康诊断与自愈手册

### 1. 核心状态检查命令

```bash
# 1. 检查网关运行状态
systemctl --user status litellm

# 2. 查看网关实时结构化调用日志
journalctl --user -u litellm -f

# 3. 检查所有上游物理节点实时探活情况
curl -s -H "Authorization: Bearer sk-local-litellm-master-key-example" http://localhost:4000/health | jq '{healthy_count, unhealthy_count, healthy: [.healthy_endpoints[].model]}'

# 4. 检查 Langfuse 容器状态
sudo docker compose -f ~/.config/langfuse/docker-compose.yml ps
```

### 2. 常用故障排错速查表

| 故障表现 | 排查方向 | 快速自愈命令 |
| :--- | :--- | :--- |
| **Agent 请求报错 Connection Refused** | LiteLLM 守护进程未启动或端口被占 | `systemctl --user restart litellm && journalctl --user -u litellm -n 30` |
| **Claude 报错 Unexpected reasoning effort** | 检查 `config.yaml` 是否漏配参数丢弃 | 确认 `additional_drop_params: ["reasoning_effort"]` 已配置并重启网关 |
| **Langfuse 无新增调用记录** | 检查 API Key 绑定或依赖版本断裂 | 检查 `journalctl --user -u litellm` 是否有 Auth/Version 报错，执行 `~/.config/langfuse/link-litellm.sh` 重新配对 |
| **私有节点响应变慢或显存用尽** | 检查是否需要临时切换轻量节点 | 执行 `pi --model node2-qwen` 或在网关中动态调整 Fallback 顺序 |
