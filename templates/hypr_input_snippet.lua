-- 存放路径: ~/.config/hypr/input.lua (Omarchy 语法)
hl.config({
  input = {
    follow_mouse = 0,
    -- 关键：只保留 compose:caps，绝不添加 shift:both_capslock_cancel
    kb_options = "compose:caps",
  },
})

-- 若使用标准 ~/.config/hypr/hyprland.conf，语法为：
-- input {
--     kb_options = compose:caps
-- }
