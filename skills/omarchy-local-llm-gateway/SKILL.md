---
name: omarchy-local-llm-gateway
description: Manage, diagnose, route, and observe local LLM gateways (LiteLLM + Langfuse) across a 3-node heterogeneous GPU cluster (Ubuntu Fast 80tps MTP, Windows Precise Q8_0, Omarchy Infinite 256K Context) and integrate multi-agent frameworks (Claude Code, Pi, Hermes, dsh, OpenManus). Use when users need to restart/hot-reload LiteLLM, verify/fix Langfuse tracing, manage context-aware cascading routing, resolve Agent token-cap/compaction crashes, or diagnose cluster node health.
---

# Omarchy 本地多 Agent 统一 LLM 网关与全链路可观测性 Skill

This skill provides operational workflows, diagnostic recipes, error-recovery runbooks, and automation scripts for managing a **Unified Local LLM Gateway (LiteLLM Proxy) with Full-Stack Observability (Langfuse v2)** across a **3-node heterogeneous GPU cluster (RTX 8000 48GB × 3)** under **Omarchy (Arch Linux + Hyprland)**.

It enforces a **"Speed First, Context Guaranteed, Precision Decoupled"** tiering model across Ubuntu (`.21`), Windows (`.22`), and Omarchy (`.23`).

---

## 1. When to Use This Skill

Activate this skill whenever a user encounters any of the following scenarios:
* **Cluster Role Management**: Need to query, restart, or tune the 3 nodes:
  - **Node 1 (Ubuntu `.21:8888`)**: **Fast Tier (local-fast)** —— `Qwen3.8-27B-Q4_K_M` + MTP 投机加速 (75~88 t/s, TTFT 0.15s).
  - **Node 2 (Windows `.22:8080`)**: **Precise Tier (local-precise)** —— `Qwen3.8-27B-Q8_0` 物理级无损精度 (30 t/s).
  - **Node 3 (Omarchy `.23:9999`)**: **Infinite Tier (local-infinite)** —— `Qwen3.8-27B-Q4_K_M` + Q4 KV Cache 满血 256K 上下文.
* **Agent "Exceeded Token Limit" or Compaction Failures**: Agent (e.g. `dsh` or Claude Code) reports "已达到输出 token 上限" or fails to summarize because its configured context window mismatches physical node limits.
* **Claude Code 500 Internal Server Error**: Claude Code crashes on local nodes with `Template error: reasoning effort high not supported`.
* **LiteLLM Swagger / Metrics Issues**: Accessing `/docs` returns 404 (needs `DOCS_URL=/docs`) or Prometheus metrics need validation.
* **Langfuse Traces Missing**: LiteLLM fails to push trace spans, or `langfuse` Python SDK crashes with `AttributeError: module 'langfuse' has no attribute 'version'`.

---

## 2. Quick Diagnostic Workflow

Run the bundled diagnostic script to verify systemd service, Docker containers, cluster node connectivity, and Agent environment settings:

```bash
bash <skill_dir>/scripts/check_gateway_env.sh
```

### Diagnostic Checklist:
| Check Item | Target State | Failure Root Cause & Action |
| :--- | :--- | :--- |
| **LiteLLM Proxy Service** | `systemctl --user is-active litellm` = `active` | Gateway down. Check `journalctl --user -u litellm -n 50`. |
| **LiteLLM Port 4000** | `127.0.0.1:4000` LISTEN | Port collision or wrong bind host. Check `lsof -i :4000`. |
| **Node 1 (Ubuntu Fast:8888)** | HTTP 200, Q4_K_M + MTP active | Node unreachable or Unsloth service down. |
| **Node 2 (Windows Precise:8080)** | HTTP 200, Q8_0 model loaded | Windows node firewall blocked port 8080 or model not loaded. |
| **Node 3 (Omarchy 256K:9999)** | HTTP 200, `ctx-size` = 262144 | Omarchy node offline or port 9999 closed. |
| **Langfuse Web Container** | `langfuse-web` Up & healthy (`127.0.0.1:3000`) | Postgres down or Docker not running. |
| **Agent Context Realism** | `dsh` contextWindow = 65536 / 262144 | Mismatched context window causes compaction failure. |

---

## 3. Gateway Management & Lifecycle Runbook

Use the bundled management tool:

```bash
bash <skill_dir>/scripts/manage_gateway.sh {status|restart|reload|logs|test|check}
```

### 3.1 Service Control Commands
* **Hot-Reload Config (Zero-Downtime)**:
  ```bash
  systemctl --user reload litellm
  ```
* **Restart Gateway**:
  ```bash
  systemctl --user restart litellm
  ```
* **Follow Live Access & Trace Logs**:
  ```bash
  journalctl --user -u litellm -f
  ```

---

## 4. Context-Aware Cascading Routing Recipe

In `~/.config/litellm/config.yaml`:
```yaml
model_list:
  - model_name: local-auto
    litellm_params:
      model: openai/qwen-fast
      api_base: http://172.28.24.21:8888/v1
      api_key: sk-unsloth-ubuntu21-masterkey
      max_input_tokens: 8192
      drop_params: true
      additional_drop_params: ["reasoning_effort"]

  - model_name: local-precise
    litellm_params:
      model: openai/unsloth-Qwen3.8-27B-Q8_0
      api_base: http://172.28.24.22:8080/v1
      api_key: sk-unsloth-win22-masterkey
      max_input_tokens: 65536
      drop_params: true
      additional_drop_params: ["reasoning_effort"]

  - model_name: local-infinite
    litellm_params:
      model: openai/qwen-long-256k
      api_base: http://172.28.24.23:9999/v1
      api_key: sk-local-litellm-master-key
      max_input_tokens: 262144
      drop_params: true
      additional_drop_params: ["reasoning_effort"]

router_settings:
  routing_strategy: "usage-based-routing"
  context_window_fallbacks:
    - local-auto: ["local-precise", "local-infinite"]
    - local-precise: ["local-infinite"]
```

---

## 5. Agent Context Calibration & Compaction Runbook

### 5.1 dsh Agent Calibration (`~/.dsh/settings.yaml`)
To prevent `dsh` from assuming a 1M token cloud context and getting truncated at 64K:
```yaml
agent-default-model:
  provider: local-gateway
  model: local-auto

llm-pi-ai:
  providers:
    local-gateway:
      baseURL: http://127.0.0.1:4000/v1
      models:
        - id: local-auto
          name: "Local Auto (Fast 8K -> Precise 64K -> Infinite 256K)"
          contextWindow: 65536     # Explicitly triggers compaction at ~52K
        - id: local-infinite
          name: "Local Infinite (Omarchy 256K)"
          contextWindow: 262144
```

### 5.2 Claude Code Calibration (`~/.claude/settings.json`)
```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "http://127.0.0.1:4000",
    "ANTHROPIC_AUTH_TOKEN": "sk-local-litellm-master-key",
    "ANTHROPIC_MODEL": "claude-3-7-sonnet-20250219",
    "MAX_THINKING_TOKENS": "0"
  }
}
```

---

## 6. End-to-End Integration Testing

Run the multi-tier benchmark test script:

```bash
bash <skill_dir>/scripts/test_agents.sh
```
This tests `local-fast` (Ubuntu), `local-precise` (Windows), and `local-auto` while measuring TTFT, generation speed (tokens/sec), and outputting direct Langfuse trace URLs.
