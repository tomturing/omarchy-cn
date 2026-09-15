-- 追加至 ~/.config/hypr/windowrules.lua

-- 1. SSH 会话管理器 (sshs) Spotlight 居中浮动窗口规则
o.window("sshs-floating", {
  tag = "+terminal",
  float = true,
  center = true,
  size = { 960, 600 },
})

-- 2. WindTerm 全功能终端大尺寸居中浮动规则（避免被 Hyprland 平铺挤碎）
o.window("WindTerm", {
  float = true,
  center = true,
  size = { 1400, 900 },
})
