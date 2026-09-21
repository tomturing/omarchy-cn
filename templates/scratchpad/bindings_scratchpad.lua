-- =================================================================
-- 核心独立弹出/隐藏 Scratchpad 快捷键模板（保持默认 SUPER+S / SUPER+ALT+S 通用模式）
-- =================================================================

-- 1. Antigravity 开发主站 (Super + A)
hl.unbind("SUPER + A")
o.bind("SUPER + A", "Toggle Antigravity", "omarchy-toggle-scratchpad '^antigravity$' antigravity 'uwsm-app -- antigravity'")

-- 2. Google AI 独立应用 (Super + X)
hl.unbind("SUPER + X")
o.bind("SUPER + X", "Toggle Google AI", "omarchy-toggle-scratchpad '(chrome-gemini|google-ai)' gemini 'omarchy-launch-webapp https://gemini.google.com'")

-- 3. Foot 专属下拉便签终端 (Super + Z)
o.bind("SUPER + Z", "Toggle Foot Terminal", "omarchy-toggle-scratchpad foot-scratchpad foot 'uwsm-app -- foot --app-id=foot-scratchpad'")
