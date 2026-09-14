#!/bin/bash
# ==============================================================================
# 修复 Omarchy Windows VM 剪贴板闪退脚本（迁移至 sdl-freerdp3）
# ==============================================================================

set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

TARGET_SCRIPT="/usr/share/omarchy/bin/omarchy-windows-vm"

echo -e "${BLUE}=== Omarchy Windows VM 剪贴板闪退修复工具 ===${NC}"

# 1. 检查目标脚本是否存在
if [ ! -f "$TARGET_SCRIPT" ]; then
    echo -e " [${RED}ERROR${NC}] 未找到 Omarchy Windows VM 启动脚本: $TARGET_SCRIPT"
    exit 1
fi

# 2. 检查系统是否安装了 sdl-freerdp3
if ! command -v sdl-freerdp3 >/dev/null 2>&1; then
    echo -e " [${RED}FAIL${NC}] 系统中未找到 sdl-freerdp3！请先运行 'sudo pacman -S freerdp' 安装。"
    exit 1
fi
echo -e " [${GREEN}PASS${NC}] sdl-freerdp3 二进制已就绪"

# 3. 检查当前是否已经是 sdl-freerdp3
if grep -q "sdl-freerdp3 /u:" "$TARGET_SCRIPT"; then
    echo -e " [${GREEN}OK${NC}] $TARGET_SCRIPT 已经在使用 sdl-freerdp3，无需重复修复！"
    exit 0
fi

# 4. 执行自动备份与安全替换
echo -e "正在更新 $TARGET_SCRIPT 客户端调用为 sdl-freerdp3 (需要 sudo 权限)..."
sudo sed -i.bak 's/xfreerdp3 \/u:"\$WIN_USER"/sdl-freerdp3 \/u:"\$WIN_USER"/' "$TARGET_SCRIPT"

# 5. 校验替换结果
if grep -q "sdl-freerdp3 /u:" "$TARGET_SCRIPT"; then
    echo -e " [${GREEN}PASS${NC}] 成功将客户端替换为 sdl-freerdp3！"
    echo -e " 原始脚本已安全备份至: ${TARGET_SCRIPT}.bak"
    echo -e "\n${GREEN}=== 修复完成！===${NC}"
    echo -e "现在重新打开 Windows VM，跨系统剪贴板复制将彻底告别崩溃闪退。"
else
    echo -e " [${RED}ERROR${NC}] 替换未生效，请手动检查 $TARGET_SCRIPT 内容。"
    exit 1
fi
