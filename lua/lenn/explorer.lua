-- Explorer (neo-tree) helpers shared by neotree.lua, bufferline and lualine:
--   * Zed-style highlights (quiet guides, bold opened files)
--   * title(): folder shown as the tree root, for the bufferline offset
--   * sources + show(): switch the panel between Files / Buffers / Git
-- Usage: require("lenn.explorer").setup() (called from plugins/neotree.lua)
local M = {}
local nf = require("lenn.icons")

M.sources = {
  { name = "filesystem", label = "Files", icon = nf.explorer_files },
  { name = "buffers", label = "Buffers", icon = nf.file_default },
  { name = "git_status", label = "Git", icon = nf.explorer_git },
}

-- The docked (non-float) neo-tree window, if visible: win, buf, source name
function M.visible()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].filetype == "neo-tree" and vim.api.nvim_win_get_config(win).relative == "" then
      local ok, source = pcall(vim.api.nvim_buf_get_var, buf, "neo_tree_source")
      return win, buf, ok and source or nil
    end
  end
end

-- Root folder of each source, recorded when neo-tree renders (see on_render).
-- title() runs while the tabline is drawn, on every cursor move, so it must
-- only read this cache: calling into neo-tree there (manager.get_state creates
-- state as a side effect) raised errors from manager.lua and broke the tabline.
local roots = {}

function M.on_render(state)
  if state and state.name and state.path then roots[state.name] = state.path end
end

-- Root folder of the visible tree (follows navigation into subfolders); cwd otherwise
function M.root()
  local _, _, source = M.visible()
  return (source and roots[source]) or vim.fn.getcwd()
end

local function title()
  local root = M.root()
  local name = vim.fn.fnamemodify(root, ":t")
  if name == "" then name = root end
  local _, _, source = M.visible()
  for _, s in ipairs(M.sources) do
    if s.name == source and s.name ~= "filesystem" then return string.format("%s %s · %s", nf.project, name, s.label) end
  end
  return nf.project .. " " .. name
end

-- Bufferline offset text over the explorer column. Never throws.
function M.title()
  local ok, text = pcall(title)
  return ok and text or "Explorer"
end

-- Show `source` in the explorer panel, reusing its window (same position)
function M.show(source, focus)
  local ok, command = pcall(require, "neo-tree.command")
  if not ok then
    vim.cmd("Neotree " .. (focus and "focus " or "show ") .. source)
    return
  end
  command.execute({ source = source, action = focus and "focus" or "show" })
end

function M.set_highlights()
  local function attr(name, key)
    local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
    return ok and hl[key] or nil
  end
  local dim = attr("LineNr", "fg") or attr("NonText", "fg")
  local subtle = attr("Comment", "fg")
  local text = attr("Normal", "fg")
  local set = vim.api.nvim_set_hl
  -- Thin, quiet guides and chevrons; the file names carry the contrast
  set(0, "NeoTreeIndentMarker", { fg = dim })
  set(0, "NeoTreeExpander", { fg = subtle })
  -- Files open in a buffer stand out
  set(0, "NeoTreeFileNameOpened", { fg = text, bold = true })
  -- Full-width selection row
  set(0, "NeoTreeCursorLine", { bg = attr("CursorLine", "bg"), bold = true })
end

function M.setup()
  M.set_highlights()
  local group = vim.api.nvim_create_augroup("LennExplorer", { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = M.set_highlights })
  vim.api.nvim_create_autocmd("DirChanged", {
    group = group,
    callback = function() vim.cmd.redrawtabline() end,
  })
end

return M
