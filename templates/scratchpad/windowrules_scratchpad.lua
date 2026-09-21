-- =================================================================
-- 专属单应用独立弹出 (Scratchpad) 规则模板
-- =================================================================

-- 1. Antigravity: 自动静默送入 special:antigravity，大尺寸浮动居中
o.window("^antigravity$", {
  workspace = "special:antigravity silent",
  float = true,
  center = true,
  size = { 1400, 900 },
})

-- 2. Google AI (Gemini 独立 WebApp): 自动静默送入 special:gemini
o.window("^(chrome-gemini.*|google-ai)$", {
  workspace = "special:gemini silent",
  float = true,
  center = true,
  size = { 1200, 850 },
})

-- 3. Foot 专属下拉终端: 自动静默送入 special:foot
o.window("^foot-scratchpad$", {
  workspace = "special:foot silent",
  float = true,
  center = true,
  size = { 1100, 700 },
})
