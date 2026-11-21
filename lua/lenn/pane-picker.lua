-- tmux-style "display-panes": show a big number over every window and jump to
-- the one whose number you press. Like tmux `prefix q`.
--
--   <M-q> / <leader>wq   show numbers (works from normal, insert and terminal mode)
--   1-9, 0               focus that window (0 = 10th); letters a-z for more
--   any other key / wait cancel
--
-- Numbers go left-to-right, then top-to-bottom, so they stay stable per layout.

local M = {}

local TIMEOUT_MS = 4000
local LABELS = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0",
  "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m",
  "n", "o", "p", "r", "s", "t", "u", "v", "w", "x", "y", "z" }

-- 5x5 block font for digits (tmux draws its numbers the same way)
local FONT = {
  ["0"] = { "█████", "█   █", "█   █", "█   █", "█████" },
  ["1"] = { "  ██ ", " ███ ", "  ██ ", "  ██ ", " ████" },
  ["2"] = { "█████", "    █", "█████", "█    ", "█████" },
  ["3"] = { "█████", "    █", " ████", "    █", "█████" },
  ["4"] = { "█   █", "█   █", "█████", "    █", "    █" },
  ["5"] = { "█████", "█    ", "█████", "    █", "█████" },
  ["6"] = { "█████", "█    ", "█████", "█   █", "█████" },
  ["7"] = { "█████", "    █", "   █ ", "  █  ", "  █  " },
  ["8"] = { "█████", "█   █", "█████", "█   █", "█████" },
  ["9"] = { "█████", "█   █", "█████", "    █", "█████" },
}

local function set_highlights()
  local function fg(name, fallback)
    local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
    return ok and hl.fg and string.format("#%06x", hl.fg) or fallback
  end
  local function bg(name, fallback)
    local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
    return ok and hl.bg and string.format("#%06x", hl.bg) or fallback
  end
  -- Like tmux: the active pane's number in one color, the others in another
  vim.api.nvim_set_hl(0, "PanePickerNumber", { fg = fg("Function", "#89b4fa"), bg = bg("NormalFloat", bg("Normal", "#1e1e2e")), bold = true })
  vim.api.nvim_set_hl(0, "PanePickerActive", { fg = fg("DiagnosticError", "#f38ba8"), bg = bg("NormalFloat", bg("Normal", "#1e1e2e")), bold = true })
end

-- Visible, non-floating windows of the current tab, sorted by screen position.
local function target_windows()
  local wins = {}
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local cfg = vim.api.nvim_win_get_config(win)
    if cfg.relative == "" and vim.api.nvim_win_get_height(win) > 0 and vim.api.nvim_win_get_width(win) > 0 then
      local pos = vim.api.nvim_win_get_position(win)
      table.insert(wins, { win = win, row = pos[1], col = pos[2] })
    end
  end
  table.sort(wins, function(a, b)
    if a.col ~= b.col then return a.col < b.col end
    return a.row < b.row
  end)
  return wins
end

local function open_label(win, label, active)
  local width = vim.api.nvim_win_get_width(win)
  local height = vim.api.nvim_win_get_height(win)
  local glyph = FONT[label]
  local lines
  if glyph and width >= 9 and height >= 7 then
    lines = {}
    for _, row in ipairs(glyph) do table.insert(lines, " " .. row .. " ") end
    table.insert(lines, 1, string.rep(" ", 7))
    table.insert(lines, string.rep(" ", 7))
  else
    lines = { " " .. label .. " " } -- tiny window or letter label
  end
  local w = vim.fn.strdisplaywidth(lines[1])
  local h = #lines

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].bufhidden = "wipe"
  local float = vim.api.nvim_open_win(buf, false, {
    relative = "win",
    win = win,
    row = math.max(0, math.floor((height - h) / 2)),
    col = math.max(0, math.floor((width - w) / 2)),
    width = w,
    height = h,
    style = "minimal",
    focusable = false,
    zindex = 250,
    noautocmd = true,
  })
  local group = active and "PanePickerActive" or "PanePickerNumber"
  vim.wo[float].winhighlight = "Normal:" .. group .. ",NormalFloat:" .. group
  vim.wo[float].winblend = 0
  return float
end

function M.pick()
  local wins = target_windows()
  if #wins < 2 then
    vim.notify("Only one window", vim.log.levels.INFO)
    return
  end
  set_highlights()

  local current = vim.api.nvim_get_current_win()
  local floats, by_label = {}, {}
  for i, entry in ipairs(wins) do
    local label = LABELS[i]
    if not label then break end
    by_label[label] = entry.win
    table.insert(floats, open_label(entry.win, label, entry.win == current))
  end
  vim.cmd.redraw()

  -- Wait for a key (with timeout, like tmux's display-panes-time)
  local key = ""
  local deadline = vim.uv.now() + TIMEOUT_MS
  while vim.uv.now() < deadline do
    local ok, char = pcall(vim.fn.getcharstr, 0)
    if ok and char ~= "" then key = char; break end
    vim.wait(15)
  end

  for _, float in ipairs(floats) do
    if vim.api.nvim_win_is_valid(float) then pcall(vim.api.nvim_win_close, float, true) end
  end

  local target = by_label[key:lower()]
  if target and vim.api.nvim_win_is_valid(target) then
    vim.api.nvim_set_current_win(target)
    -- Land in insert mode on terminals (agents), like clicking into them
    if vim.bo[vim.api.nvim_win_get_buf(target)].buftype == "terminal" then
      vim.cmd.startinsert()
    else
      vim.cmd.stopinsert()
    end
  end
  vim.cmd.redraw()
end

function M.setup()
  local pick = function() vim.schedule(M.pick) end
  vim.keymap.set({ "n", "i", "t" }, "<M-q>", pick, { desc = "Pick window (tmux display-panes)" })
  vim.keymap.set("n", "<leader>wq", M.pick, { desc = "Workspace: pick window by number" })
  vim.api.nvim_create_user_command("PanePick", M.pick, { desc = "Pick window by number" })
end

return M
