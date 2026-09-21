# ============================================================
# 统一本地 LiteLLM 网关 —— 所有 Agent 使用同一套配置
# Base: http://127.0.0.1:4000 (OpenAI compat: /v1)
# Master Key: sk-local-litellm-master-key
# ============================================================
# 追加至 ~/.bashrc 的 "Local LLM Gateway" 配置块

export ANTHROPIC_BASE_URL="http://127.0.0.1:4000"
export ANTHROPIC_API_KEY="sk-local-litellm-master-key"
export ANTHROPIC_AUTH_TOKEN="sk-local-litellm-master-key"   # Claude Code 备用变量名
export ANTHROPIC_MODEL="local-auto"                        # 智能分流中枢 (极速 128K -> 高精 -> 满血 256K)
export ANTHROPIC_DEFAULT_SONNET_MODEL="local-auto"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="local-fast"
export ANTHROPIC_DEFAULT_OPUS_MODEL="local-precise"

export OPENAI_BASE_URL="http://127.0.0.1:4000/v1"          # Codex / OpenAI SDK
export OPENAI_API_KEY="sk-local-litellm-master-key"
export OPENAI_MODEL="local-auto"

export DEEPSEEK_BASE_URL="http://127.0.0.1:4000"
export DEEPSEEK_API_KEY="sk-local-litellm-master-key"

# ------------------------------------------------------------
# 提示：桌面级与 systemd --user 环境持久化 (覆盖 GUI 与桌面图标启动的应用)
# 写入 ~/.config/environment.d/10-litellm-gateway.conf 并执行:
# systemctl --user import-environment ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN ANTHROPIC_API_KEY ANTHROPIC_MODEL ANTHROPIC_DEFAULT_SONNET_MODEL OPENAI_BASE_URL OPENAI_API_KEY OPENAI_MODEL
# ------------------------------------------------------------

