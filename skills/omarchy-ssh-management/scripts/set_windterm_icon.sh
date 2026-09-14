#!/bin/bash
# ==============================================================================
# 一键修改 WindTerm 会话图标脚本（绕过 Hyprland/XWayland 下拉弹窗失焦穿透问题）
# ==============================================================================

set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

ICON="${1:-session::cmd}"

echo -e "${BLUE}=== WindTerm 会话图标一键修改工具 ===${NC}"
echo -e "目标图标: ${YELLOW}${ICON}${NC}"

# 1. 检查 WindTerm 是否正在运行
if pgrep -i "windterm" >/dev/null 2>&1; then
    echo -e " [${RED}WARNING${NC}] 检测到 WindTerm 正在运行！"
    echo -e " 为避免内存中的旧配置覆盖文件，请先在图形界面中关闭会话弹窗并完全退出 WindTerm。"
    read -rp "是否已退出 WindTerm 并继续? (y/N): " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo "已取消操作。"
        exit 1
    fi
fi

WIND_TERM_DIR="$HOME/.wind/profiles/default.v10/terminal"
if [ ! -d "$WIND_TERM_DIR" ]; then
    echo -e " [${RED}ERROR${NC}] 未找到 WindTerm 终端配置目录: $WIND_TERM_DIR"
    exit 1
fi

# 2. 修改全局默认新建模板 session.config
SESSION_CONFIG="$WIND_TERM_DIR/session.config"
if [ -f "$SESSION_CONFIG" ]; then
    # 使用 Python 安全处理 JSON
    python3 -c "
import json
p = '$SESSION_CONFIG'
try:
    with open(p, 'r', encoding='utf-8') as f:
        data = json.load(f)
except Exception:
    data = {}
data['session.icon'] = '$ICON'
with open(p, 'w', encoding='utf-8') as f:
    json.dump(data, f, indent=4, ensure_ascii=False)
"
    echo -e " [${GREEN}OK${NC}] 已更新全局会话模板: $SESSION_CONFIG"
else
    cat << CFG_EOF > "$SESSION_CONFIG"
{
    "session.icon" : "$ICON"
}
CFG_EOF
    echo -e " [${GREEN}OK${NC}] 已新建全局会话模板: $SESSION_CONFIG"
fi

# 3. 批量更新现有用户会话 user.sessions
USER_SESSIONS="$WIND_TERM_DIR/user.sessions"
if [ -f "$USER_SESSIONS" ]; then
    # 备份原有文件
    cp "$USER_SESSIONS" "$USER_SESSIONS.bak.$(date +%s)"
    python3 -c "
import json
p = '$USER_SESSIONS'
try:
    with open(p, 'r', encoding='utf-8') as f:
        data = json.load(f)
    if isinstance(data, list):
        for item in data:
            if isinstance(item, dict):
                item['session.icon'] = '$ICON'
        with open(p, 'w', encoding='utf-8') as f:
            json.dump(data, f, indent=4, ensure_ascii=False)
        print(' [OK] 现有会话图标已全部更新为 $ICON')
    else:
        print(' [WARN] user.sessions 格式非列表，未作批量替换')
except Exception as e:
    print(f' [ERROR] 更新失败: {e}')
"
fi

echo -e "\n${GREEN}=== 图标更新成功！===${NC}"
echo -e "现在重新打开 WindTerm，会话树与标签页将显示最新图标。"
