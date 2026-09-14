# 追加到 ~/.bashrc 或 ~/.zshrc 末尾

# 1. 终端交互式会话启动时默认进入英文输入状态（按 Shift 可随时切回中文）
if [[ $- == *i* ]] && [ -t 0 ] && [ -n "$WAYLAND_DISPLAY$DISPLAY" ]; then
    (gdbus call --session --dest org.fcitx.Fcitx5 --object-path /rime --method org.fcitx.Fcitx.Rime1.SetAsciiMode true >/dev/null 2>&1 &)
fi

# 2. 执行涉及密码输入的命令前，自动将输入法切回英文模式（避免密码输入中混入中文/拼音）
for __pwd_cmd in sudo su pkexec passwd ssh doas; do
    eval "
    $__pwd_cmd() {
        (gdbus call --session --dest org.fcitx.Fcitx5 --object-path /rime --method org.fcitx.Fcitx.Rime1.SetAsciiMode true >/dev/null 2>&1 &)
        command $__pwd_cmd \"\$@\"
    }
    "
done
unset __pwd_cmd
