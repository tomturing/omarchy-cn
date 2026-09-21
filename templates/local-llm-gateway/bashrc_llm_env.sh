# ============================================================
# 统一本地 LiteLLM 网关 —— 所有 Agent 使用同一套配置
# Base: http://127.0.0.1:4000 (OpenAI compat: /v1)
# Master Key: sk-local-litellm-master-key
# ============================================================
# 追加至 ~/.bashrc 的 "Local LLM Gateway" 配置块

export ANTHROPIC_BASE_URL="http://127.0.0.1:4000"
export ANTHROPIC_API_KEY="sk-local-litellm-master-key"
export ANTHROPIC_AUTH_TOKEN="sk-local-litellm-master-key"   # Claude Code 备用变量名

export OPENAI_BASE_URL="http://127.0.0.1:4000/v1"          # Codex / OpenAI SDK
export OPENAI_API_KEY="sk-local-litellm-master-key"

export DEEPSEEK_BASE_URL="http://127.0.0.1:4000"
export DEEPSEEK_API_KEY="sk-local-litellm-master-key"
