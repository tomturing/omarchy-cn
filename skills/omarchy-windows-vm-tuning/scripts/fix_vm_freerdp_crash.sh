#!/bin/bash
# ==============================================================================
# 修复 Omarchy Windows VM 剪贴板闪退脚本
# （终极方案：保留 xfreerdp3 原生无黑边缩放，应用上游剪贴板修复补丁）
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$SCRIPT_DIR/rebuild_freerdp_with_patch.sh"
