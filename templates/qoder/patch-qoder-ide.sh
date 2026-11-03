#!/usr/bin/env bash
# ==============================================================================
# Qoder IDE CN 文件监听引擎热修复与加固脚本 (Qoder IDE Watcher Hardening)
# 
# 根因: @parcel/watcher v2.5.1 在高并发目录变更（如 git worktree 创建/删除）时
#       存在 C++ 空指针解引用与 UAF 竞态漏洞 (DirTree::remove / mDirCacheMutex)，
#       导致 Node utilityProcess 崩溃 (Exit 139 / SIGSEGV)，引发 IDE 窗口白屏或异常退出。
# 方案: 升级并热替换为 @parcel/watcher v2.6.0 (引入 Meyers 单例全局互斥锁全面加固)，
#       同时提供用户空间无损拦截与系统级 ALPM Hook 双重防线。
# ==============================================================================

set -euo pipefail

# 唯一调用链路追踪标识 (可观测性设计)
TRACE_ID="qoder-patch-$(date +%s%N | cut -b1-13)-${RANDOM}"
LOG_PREFIX="[watcher-hardening][${TRACE_ID}]"

log_info() {
    echo -e "${LOG_PREFIX} [INFO] $*"
}

log_warn() {
    echo -e "${LOG_PREFIX} [WARN] $*" >&2
}

log_error() {
    echo -e "${LOG_PREFIX} [ERROR] $*" >&2
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSETS_DIR="${SCRIPT_DIR}/assets"
SYSTEM_TARGET_DIR="/usr/lib/qoder-cn-ide/app/node_modules/@parcel/watcher"
USER_DATA_DIR="${HOME}/.local/share/qoder-ide/patches"
USER_BIN_FILE="${HOME}/.local/bin/qoder-cn-ide"

mode="auto"
if [[ $# -gt 0 ]]; then
    case "$1" in
        --system) mode="system" ;;
        --user)   mode="user" ;;
        --auto)   mode="auto" ;;
        --help|-h)
            echo "用法: $0 [--system | --user | --auto]"
            echo "  --system: 对 /usr/lib/qoder-cn-ide 进行系统级二进制替换 (需 root 权限)"
            echo "  --user:   对当前用户环境部署透明 Hook 拦截与补丁 (免 root 权限)"
            echo "  --auto:   自动探测权限，优先系统级，无权限时回退至用户级"
            exit 0
            ;;
        *)
            log_error "未知参数: $1"
            exit 1
            ;;
    esac
fi

# 解压准备二进制
ensure_binary_asset() {
    local gz_file="${ASSETS_DIR}/build/Release/watcher.node.gz"
    local raw_node="${ASSETS_DIR}/build/Release/watcher.node"
    if [[ ! -f "${raw_node}" ]]; then
        if [[ -f "${gz_file}" ]]; then
            log_info "正在从 ${gz_file} 解压 watcher.node (v2.6.0)..."
            gzip -dc "${gz_file}" > "${raw_node}"
            chmod +x "${raw_node}"
        else
            log_error "未找到加固二进制资源: ${gz_file}"
            exit 1
        fi
    fi
}

# 部署系统级加固
apply_system_patch() {
    log_info "执行系统级加固: 目标路径 ${SYSTEM_TARGET_DIR}..."
    if [[ ! -d "${SYSTEM_TARGET_DIR}" ]]; then
        log_warn "未检测到系统安装的 Qoder IDE CN (${SYSTEM_TARGET_DIR} 不存在)，跳过系统级修补。"
        return 0
    fi

    if [[ "${EUID}" -ne 0 ]]; then
        log_error "系统级修补需要 root 权限，请使用 sudo 运行此模式。"
        return 1
    fi

    local target_binary="${SYSTEM_TARGET_DIR}/build/Release/watcher.node"
    local backup_binary="${SYSTEM_TARGET_DIR}/build/Release/watcher.node.orig"

    ensure_binary_asset

    if [[ -f "${target_binary}" ]]; then
        # 如果尚未备份，先做一次安全备份
        if [[ ! -f "${backup_binary}" ]]; then
            log_info "创建原版二进制备份: ${backup_binary}"
            cp "${target_binary}" "${backup_binary}"
        fi
    fi

    log_info "覆盖安装安全版 watcher.node (v2.6.0)..."
    cp -f "${ASSETS_DIR}/build/Release/watcher.node" "${target_binary}"
    chmod 755 "${target_binary}"

    log_info "系统级加固完成！已成功将 /usr/lib/qoder-cn-ide 原生模块加固至 v2.6.0。"
}

# 部署用户级透明拦截防线
apply_user_patch() {
    log_info "执行用户级透明加固: 目标目录 ${USER_DATA_DIR}..."

    ensure_binary_asset

    local patch_target="${USER_DATA_DIR}/watcher-2.6.0"
    mkdir -p "${patch_target}/build/Release"
    mkdir -p "${patch_target}/node_modules"

    cp -f "${ASSETS_DIR}/build/Release/watcher.node" "${patch_target}/build/Release/"
    cp -f "${ASSETS_DIR}/index.js" "${patch_target}/"
    cp -f "${ASSETS_DIR}/wrapper.js" "${patch_target}/"
    cp -f "${ASSETS_DIR}/package.json" "${patch_target}/"
    cp -f "${ASSETS_DIR}/watcher-hook.js" "${USER_DATA_DIR}/"

    cp -rf "${ASSETS_DIR}/node_modules/"* "${patch_target}/node_modules/"

    log_info "已部署独立运行时资产到 ${patch_target}"

    # 检查并加固用户启动脚本 ~/.local/bin/qoder-cn-ide
    if [[ -f "${USER_BIN_FILE}" ]]; then
        if grep -q "watcher-hook.js" "${USER_BIN_FILE}"; then
            log_info "用户启动包装器 ${USER_BIN_FILE} 已包含 watcher-hook 注入配置。"
        else
            log_info "正在向用户启动包装器 ${USER_BIN_FILE} 注入安全加载钩子..."
            # 在 exec 之前注入 NODE_OPTIONS
            local temp_bin
            temp_bin="$(mktemp)"
            awk '
                BEGIN { injected=0 }
                /^exec / && injected==0 {
                    print "# 注入文件监听引擎加固加载器，根治 @parcel/watcher v2.5.1 并发空指针 UAF 崩溃"
                    print "QODER_PATCH_HOOK=\"${HOME}/.local/share/qoder-ide/patches/watcher-hook.js\""
                    print "if [[ -f \"${QODER_PATCH_HOOK}\" ]]; then"
                    print "    export NODE_OPTIONS=\"--require ${QODER_PATCH_HOOK} ${NODE_OPTIONS:-}\""
                    print "fi\n"
                    injected=1
                }
                { print }
            ' "${USER_BIN_FILE}" > "${temp_bin}"
            chmod +x "${temp_bin}"
            mv "${temp_bin}" "${USER_BIN_FILE}"
            log_info "成功加固启动包装器 ${USER_BIN_FILE}"
        fi
    else
        log_warn "未找到用户启动包装器 ${USER_BIN_FILE}，建议创建以确保自动注入。"
    fi

    log_info "用户级透明加固完成！已建立持久化自愈防线。"
}

# 流程控制
case "${mode}" in
    system)
        apply_system_patch
        ;;
    user)
        apply_user_patch
        ;;
    auto)
        if [[ "${EUID}" -eq 0 ]]; then
            apply_system_patch
        else
            apply_user_patch
        fi
        ;;
esac
