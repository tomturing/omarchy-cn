-- 追加至 ~/.config/hypr/bindings.lua

-- 重要避坑：先解绑 Omarchy 默认绑定的快捷键（默认绑定为启动浏览器 browser）
hl.unbind("SUPER + SHIFT + RETURN")

-- 重新绑定为一键呼出 SSH Spotlight 会话管理器
o.bind("SUPER + SHIFT + RETURN", "SSH Sessions", { launch = "ssh-manager" })
