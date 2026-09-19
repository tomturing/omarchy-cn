#!/usr/bin/env bash
# ==============================================================================
# manage_gateway.sh - Helper script to manage LiteLLM and Langfuse services
# Usage: ./manage_gateway.sh {status|restart|reload|logs|test}
# ==============================================================================

set -euo pipefail

ACTION="${1:-status}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LANGFUSE_COMPOSE="${HOME}/.config/langfuse/docker-compose.yml"

case "$ACTION" in
    status)
        echo "=== LiteLLM systemd service status ==="
        systemctl --user status litellm --no-pager || true
        echo ""
        echo "=== Langfuse Docker containers ==="
        if [ -f "$LANGFUSE_COMPOSE" ]; then
            docker compose -f "$LANGFUSE_COMPOSE" ps
        else
            echo "Langfuse compose file not found at $LANGFUSE_COMPOSE"
        fi
        ;;
    restart)
        echo "Restarting LiteLLM gateway..."
        systemctl --user restart litellm
        echo "Restarting Langfuse stack..."
        if [ -f "$LANGFUSE_COMPOSE" ]; then
            docker compose -f "$LANGFUSE_COMPOSE" restart
        fi
        echo "Done."
        ;;
    reload)
        echo "Reloading LiteLLM configuration..."
        systemctl --user reload litellm
        echo "Done."
        ;;
    logs)
        journalctl --user -u litellm -f
        ;;
    test)
        bash "${SCRIPT_DIR}/test_agents.sh"
        ;;
    check)
        bash "${SCRIPT_DIR}/check_gateway_env.sh"
        ;;
    *)
        echo "Usage: $0 {status|restart|reload|logs|test|check}"
        exit 1
        ;;
esac
