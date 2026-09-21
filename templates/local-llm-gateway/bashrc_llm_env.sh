# ============================================================
# 统一本地 LiteLLM 网关 —— 所有 Agent 使用同一套配置
# Base: http://127.0.0.1:4000 (OpenAI compat: /v1)
# Master Key: sk-local-litellm-master-key
# ============================================================
# 追加至 ~/.bashrc 的 "Local LLM Gateway" 配置块

export ANTHROPIC_BASE_URL="http://127.0.0.1:4000"
export ANTHROPIC_API_KEY="sk-local-litellm-master-key"
export ANTHROPIC_AUTH_TOKEN="sk-local-litellm-master-key"   # Claude Code 备用变量名
export ANTHROPIC_MODEL="local"                             # 统一所有 Agent 默认模型名
export ANTHROPIC_DEFAULT_SONNET_MODEL="local"

export OPENAI_BASE_URL="http://127.0.0.1:4000/v1"          # Codex / OpenAI SDK
export OPENAI_API_KEY="sk-local-litellm-master-key"
export OPENAI_MODEL="local"

export DEEPSEEK_BASE_URL="http://127.0.0.1:4000"
export DEEPSEEK_API_KEY="sk-local-litellm-master-key"

# ------------------------------------------------------------
# 提示：桌面级与 systemd --user 环境持久化 (覆盖 GUI 与非终端启动的应用)
# 写入 ~/.config/environment.d/10-litellm-gateway.conf:
# ANTHROPIC_BASE_URL="http://127.0.0.1:4000"
# ANTHROPIC_AUTH_TOKEN="sk-local-litellm-master-key"
# ANTHROPIC_MODEL="local"
# OPENAI_BASE_URL="http://127.0.0.1:4000/v1"
# OPENAI_MODEL="local"
# ------------------------------------------------------------

