#!/usr/bin/env bash
# 一键部署 Omarchy 顶部栏居中实时网速显示插件 (local.netspeed)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="$(cd "$SCRIPT_DIR/../../../templates/netspeed" && pwd)"

echo "=== 开始部署 Omarchy 顶部栏居中实时网速显示组件 ==="

PLUGIN_DIR="$HOME/.config/omarchy/plugins/local.netspeed"

# 1. 复制插件工程文件
echo "-> [1/3] 部署插件工程至 $PLUGIN_DIR ..."
mkdir -p "$PLUGIN_DIR"
cp "$TEMPLATES_DIR/manifest.json" "$PLUGIN_DIR/manifest.json"
cp "$TEMPLATES_DIR/netspeed.sh" "$PLUGIN_DIR/netspeed.sh"
cp "$TEMPLATES_DIR/NetSpeed.qml" "$PLUGIN_DIR/NetSpeed.qml"
chmod +x "$PLUGIN_DIR/netspeed.sh"
echo "   [OK] manifest.json, netspeed.sh 与 NetSpeed.qml 部署就绪"

# 2. 修改 ~/.config/omarchy/shell.json 启用居中布局
echo "-> [2/3] 配置 ~/.config/omarchy/shell.json 居中布局 ..."
SHELL_JSON="$HOME/.config/omarchy/shell.json"

if [ -f "$SHELL_JSON" ]; then
    python3 -c '
import json, sys

path = "'"$SHELL_JSON"'"
with open(path, "r") as f:
    data = json.load(f)

bar = data.get("bar", {})
layout = bar.get("layout", {})
center = layout.get("center", [])

has_netspeed = any(item.get("id") == "local.netspeed" for item in center)
if not has_netspeed:
    # 查找天气组件位置，插入在天气组件之后，或直接追加
    weather_idx = -1
    for i, item in enumerate(center):
        if item.get("id") == "omarchy.weather":
            weather_idx = i
            break
    if weather_idx != -1:
        center.insert(weather_idx + 1, {"id": "local.netspeed"})
    else:
        center.append({"id": "local.netspeed"})
    layout["center"] = center
    bar["layout"] = layout
    data["bar"] = bar
    with open(path, "w") as f:
        json.dump(data, f, indent=2)
    print("   [OK] local.netspeed 插件已插入 shell.json center 区域")
else:
    print("   [OK] shell.json center 区域已包含 local.netspeed")
'
else
    echo "   [WARN] 未找到 $SHELL_JSON，请确认 Omarchy Shell 已初始化"
fi

# 3. 热重载 Omarchy 桌面组件
echo "-> [3/3] 重启 Quickshell 桌面环境以热生效 ..."
if command -v omarchy-restart-shell >/dev/null 2>&1; then
    omarchy-restart-shell >/dev/null 2>&1 || true
    echo "   [OK] Quickshell 已成功重载"
fi

echo -e "\n✅ 顶部栏居中实时网速显示部署完成！请查看屏幕上方居中位置的上下行速率显示。"
