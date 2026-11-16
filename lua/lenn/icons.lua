-- Canonical Nerd Font glyphs used by the NvMoon UI.
-- Keep custom icons to the approved Nerd Font glyph set so emoji and ordinary
-- Unicode symbols cannot leak into the interface.
local M = {
  active = "",
  collapsed = "",
  expanded = "",
  arrow_right = "",
  diagnostic = "",
  check = "",
  close = "",
  circle = "",
  dot = "󰧞",
  package = "",
  wrench = "",
  search = "",
  hourglass = "",
  external = "",
  folder_open = "",
  folder_closed = "",
  project = "",
  folder_empty = "",
  file_default = "",
  explorer_files = "",
  explorer_git = "",
  play = "",
  diff_added = "",
  diff_modified = "",
  diff_removed = "",
  lualine_finder = "",
  lualine_lsp = "",
  lualine_warn = "",
  lualine_outline = "",
  generic = "",
  claude = "󰚩",
  codex = "",
  copilot = "",
  cursor = "",
  factory = "",
  gemini = "",
  opencode = "",
  pi = "󰬌",
  poolside = "",
  aider = "",
  cline = "",
  deepagents = "󰚩",
  kiro = "",
  sweep = "",
  amazon_q = "",
  windsurf = "",
  junie = "",
}

local approved_glyphs = {}
for _, glyph in pairs(M) do
  if type(glyph) == "string" then
    local codepoint = vim.fn.char2nr(glyph, 1)
    local is_private_use = (codepoint >= 0xE000 and codepoint <= 0xF8FF)
        or (codepoint >= 0xF0000 and codepoint <= 0xFFFFD)
        or (codepoint >= 0x100000 and codepoint <= 0x10FFFD)
    if is_private_use then
      approved_glyphs[glyph] = true
    end
  end
end

function M.is_nerd_font_glyph(value)
  if type(value) ~= "string" or vim.fn.strchars(value) ~= 1 then
    return false
  end

  return approved_glyphs[value] == true
end

function M.normalize(value, fallback)
  return M.is_nerd_font_glyph(value) and value or (fallback or M.generic)
end

return M
