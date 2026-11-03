#!/usr/bin/env bash
# ==============================================================================
# Qoder IDE CN 文件监听引擎加固与自愈机制安装器 (Install Hardening System)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TRACE_ID="qoder-install-$(date +%s%N | cut -b1-13)-${RANDOM}"
LOG_PREFIX="[watcher-install][${TRACE_ID}]"

log_info() {
    echo -e "${LOG_PREFIX} [INFO] $*"
}

log_warn() {
    echo -e "${LOG_PREFIX} [WARN] $*" >&2
}

log_error() {
    echo -e "${LOG_PREFIX} [ERROR] $*" >&2
}

log_info "正在启动 Qoder IDE CN 文件监听引擎加固方案安装程序..."

# 1. 始终部署当前用户的运行时拦截防线（第一道防线：免 root、防 pacman 冲掉）
"${SCRIPT_DIR}/patch-qoder-ide.sh" --user

# 2. 如果具备 root 权限，部署系统级 Pacman ALPM Hook 与系统补丁（第二道防线）
if [[ "${EUID}" -eq 0 ]]; then
    log_info "检测到 root 权限，正在部署系统级 Pacman ALPM 自愈 Hook..."
    
    mkdir -p /usr/share/qoder-ide
    cp -rf "${SCRIPT_DIR}/assets" /usr/share/qoder-ide/
    cp -f "${SCRIPT_DIR}/patch-qoder-ide.sh" /usr/share/qoder-ide/
    chmod +x /usr/share/qoder-ide/patch-qoder-ide.sh

    mkdir -p /etc/pacman.d/hooks
    cp -f "${SCRIPT_DIR}/qoder-ide-watcher.hook" /etc/pacman.d/hooks/
    log_info "成功安装 ALPM 钩子到 /etc/pacman.d/hooks/qoder-ide-watcher.hook"

    # 执行系统原生修补
    /usr/share/qoder-ide/patch-qoder-ide.sh --system
else
    log_warn "当前为非 root 用户运行。用户级持久防线已就绪并生效。"
    log_info "若需要部署系统级 Pacman ALPM 自动挂载钩子，请使用 sudo 重新运行此脚本："
    log_info "  sudo ${BASH_SOURCE[0]}"
fi

log_info "Qoder IDE CN 文件监听加固安装完成！"
