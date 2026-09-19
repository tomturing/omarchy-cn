#!/bin/bash
# 将 Langfuse 项目 API Key 自动绑定至 LiteLLM 服务并热重启
set -e

if [ "$#" -ne 2 ]; then
    echo "用法: $0 <LANGFUSE_PUBLIC_KEY> <LANGFUSE_SECRET_KEY>"
    echo "示例: $0 pk-lf-123456 sk-lf-654321"
    exit 1
fi

PK="$1"
SK="$2"
HOST="http://localhost:3000"

echo "正在将 Langfuse API Key 绑定到 LiteLLM 服务..."

SERVICE_FILE="$HOME/.config/systemd/user/litellm.service"
cat << SERVICE_EOF > "$SERVICE_FILE"
[Unit]
Description=LiteLLM Unified Proxy & Observability Gateway
After=network.target

[Service]
Type=simple
WorkingDirectory=$HOME/.config/litellm
ExecStart=$HOME/.config/litellm/.venv/bin/litellm --config $HOME/.config/litellm/config.yaml --port 4000
Restart=always
RestartSec=3
StandardOutput=journal
StandardError=journal
Environment="PYTHONUNBUFFERED=1"
Environment="DOCS_URL=/docs"
Environment="LANGFUSE_PUBLIC_KEY=$PK"
Environment="LANGFUSE_SECRET_KEY=$SK"
Environment="LANGFUSE_HOST=$HOST"

[Install]
WantedBy=default.target
SERVICE_EOF

CONFIG_FILE="$HOME/.config/litellm/config.yaml"
if ! grep -q '"langfuse"' "$CONFIG_FILE"; then
    sed -i 's/callbacks: \["prometheus"\]/callbacks: \["prometheus", "langfuse"\]/' "$CONFIG_FILE"
fi

systemctl --user daemon-reload
systemctl --user restart litellm.service

echo "LiteLLM 已成功连接 Langfuse！"
echo "后续所有 Agent（Claude、Pi、Hermes）调用将实时同步到 http://localhost:3000"
