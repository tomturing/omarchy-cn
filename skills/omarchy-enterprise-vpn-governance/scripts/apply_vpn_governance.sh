#!/bin/bash
# ==============================================================================
# apply_vpn_governance.sh: 一键应用企业级 VPN 自启治理与生命周期管理方案
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../" && pwd)"
TEMPLATE_DIR="${REPO_ROOT}/templates/sangfor"

if [ ! -d "${TEMPLATE_DIR}" ]; then
    echo "[ERROR] 未找到配置模板目录: ${TEMPLATE_DIR}"
    exit 1
fi

bash "${TEMPLATE_DIR}/install.sh"
