-- Omarchy 高频实用快捷键与 F1 截图标注配置片段
-- 推荐置于 ~/.config/hypr/bindings.lua 或 ~/.config/hypr/local.lua

-- 1. F1 快速唤起 Tensaku 批注截图
hl.unbind("F1")
o.bind("F1", "Screenshot", "/home/tom/.local/bin/tensaku-capture")

-- 2. 常用开发与办公应用
o.bind("SUPER + A", "Antigravity", { launch = "antigravity" })
o.bind("SUPER + B", "Browser", { omarchy = "browser" })

-- 3. SSH Spotlight 会话管理器 (解绑默认浏览器快捷键)
hl.unbind("SUPER + SHIFT + RETURN")
o.bind("SUPER + SHIFT + RETURN", "SSH Sessions", { launch = "ssh-manager" })

-- 4. 快捷键锁屏触发切回英文输入法 (防锁屏输入密码弹拼音)
hl.unbind("SUPER + CTRL + L")
o.bind("SUPER + CTRL + L", "Lock system", "bash -c 'gdbus call --session --dest org.fcitx.Fcitx5 --object-path /rime --method org.fcitx.Fcitx.Rime1.SetAsciiMode true >/dev/null 2>&1; omarchy-system-lock'")
