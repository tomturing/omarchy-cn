#!/usr/bin/env bash
# Voxtype 离线语音识别一键自动化配置脚本（RTX显卡GPU加速、普通话模型及剪贴板直通）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Voxtype 离线语音输入自动化部署与 GPU 加速配置 ===${NC}\n"

# 1. 检查并安装 voxtype-bin
echo -n "[1/5] 检查 voxtype-bin 安装状态... "
if ! pacman -Qi voxtype-bin >/dev/null 2>&1; then
    echo -e "${YELLOW}未安装${NC}"
    echo "正在使用 yay 安装 voxtype-bin..."
    yay -S --needed --noconfirm voxtype-bin
    echo -e "${GREEN}[PASS] voxtype-bin 安装完成${NC}"
else
    echo -e "${GREEN}[PASS] voxtype-bin 已安装${NC}"
fi

# 2. 准备模型目录与 Whisper Small 模型
MODEL_DIR="$HOME/.local/share/voxtype/models"
mkdir -p "$MODEL_DIR"

echo -n "[2/5] 检查 Whisper Small 普通话模型 (ggml-small.bin)... "
if [ ! -f "$MODEL_DIR/ggml-small.bin" ]; then
    echo -e "${YELLOW}模型不存在，开始下载 (~466MB)...${NC}"
    # 优先从国内镜像或官方源下载
    MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin"
    curl -L --progress-bar -o "$MODEL_DIR/ggml-small.bin" "$MODEL_URL"
    echo -e "${GREEN}[PASS] 模型下载完成${NC}"
else
    echo -e "${GREEN}[PASS] ggml-small.bin 已就绪 ($(du -h "$MODEL_DIR/ggml-small.bin" | cut -f1))${NC}"
fi

# 3. 部署 Voxtype 配置文件
echo -n "[3/5] 部署 Voxtype 配置文件 (~/.config/voxtype/config.toml)... "
mkdir -p "$HOME/.config/voxtype"
TEMPLATE_CONFIG="$REPO_ROOT/templates/voxtype/config.toml"

if [ -f "$TEMPLATE_CONFIG" ]; then
    cp "$TEMPLATE_CONFIG" "$HOME/.config/voxtype/config.toml"
else
    # 回退内置生成
    cat > "$HOME/.config/voxtype/config.toml" << 'EOF'
state_file = "auto"
engine = "whisper"

[hotkey]
enabled = false

[audio]
device = "pulse"
sample_rate = 16000
max_duration_secs = 60
pause_media = true

[whisper]
model = "small"
language = "zh"
translate = false
mode = "local"
flash_attention = true
on_demand_loading = false
gpu_isolation = false
initial_prompt = "这是一段中文普通话日常对话与编程开发指令，请正确使用简体中文和标点符号。"

[output]
mode = "paste"
fallback_to_clipboard = true
type_delay_ms = 1

[output.notification]
on_recording_start = false
on_recording_stop = false
on_transcription = false
EOF
fi
echo -e "${GREEN}[PASS] 配置文件写入完成 (mode=paste, flash_attention=true)${NC}"

# 4. 配置 systemd 用户服务以使用 Vulkan GPU 加速
echo -n "[4/5] 配置 systemd 服务使用 voxtype-vulkan GPU 硬件加速... "
mkdir -p "$HOME/.config/systemd/user"
cat > "$HOME/.config/systemd/user/voxtype.service" << 'EOF'
[Unit]
Description=Voxtype push-to-talk voice-to-text daemon
Documentation=https://voxtype.io
PartOf=graphical-session.target
After=graphical-session.target

[Service]
Type=simple
ExecStart=/usr/lib/voxtype/voxtype-vulkan daemon
Restart=on-failure
RestartSec=5

# Ensure we have access to the display
Environment=XDG_RUNTIME_DIR=%t

[Install]
WantedBy=graphical-session.target
EOF
echo -e "${GREEN}[PASS] systemd 用户服务已配置为 voxtype-vulkan${NC}"

# 5. 重启并验证守护进程
echo -n "[5/5] 启动并启用 voxtype 用户级服务... "
systemctl --user daemon-reload
systemctl --user enable --now voxtype.service
sleep 1.5

if systemctl --user is-active --quiet voxtype.service; then
    echo -e "${GREEN}[PASS] voxtype.service 正在运行！${NC}"
else
    echo -e "${RED}[FAIL] voxtype.service 启动失败，请运行 journalctl --user -u voxtype -e 查看日志${NC}"
    exit 1
fi

echo -e "\n${GREEN}=== Voxtype 部署成功！ ===${NC}"
echo "全局快捷键："
echo "  - 按 Super + Ctrl + X：切换开启/结束录音 (Toggle)"
echo "  - 长按 F9：按住说话，松开自动转文字 (Push-to-Talk)"
