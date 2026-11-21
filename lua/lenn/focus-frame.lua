-- Highlighted, rounded frame around the focused window only.
--
-- Split separators are shared between neighbouring windows (a window's right
-- separator is also its neighbour's left edge, and spans the neighbour's whole
-- height), so highlighting WinSeparator always lights up several panels and can
-- never be rounded. Instead this draws thin, non-focusable floats around the
-- current window:
--
--   ╭──────────╮
--   │  window  │
--   ╰──────────╯
--
-- Where each side goes (it never covers the bufferline, lualine or any text):
--   * next to another window      → over the shared separator line
--   * top of the screen           → on the window's own title (winbar) row,
--                                   only over its blank cells
--   * bottom of the screen        → on the window's last row, only after the
--                                   end of the text shown there
--   * left/right edge of screen   → on the window's own first/last column
--                                   (panels keep those columns blank)
-- File windows get a small winbar with the file name, which hosts their top side.
-- Mouse events pass through the floats; other floats are drawn above them.

local M = {}

local pool = {} -- name -> { buf, win }
local used = {} -- names drawn in the current update
local enabled = true
local last_key = nil -- skip identical redraws (our own floats fire WinResized)

-- ─── Highlights ────────────────────────────────────────────────────────────

local function hl_attr(name, attr)
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
  return ok and hl[attr] and string.format("#%06x", hl[attr]) or nil
end

local frame_fg = "#89b4fa"
local hl_cache = {}

local function set_highlight()
  frame_fg = hl_attr("AgentFocusFrame", "fg") or hl_attr("Title", "fg") or hl_attr("Function", "fg") or frame_fg
  hl_cache = {}
end

-- A frame highlight with the background of `group` (so only the line shows)
local function frame_hl(group)
  group = group or "Normal"
  if hl_cache[group] then return hl_cache[group] end
  local name = "LennFocusFrame" .. group:gsub("[^%w]", "")
  vim.api.nvim_set_hl(0, name, { fg = frame_fg, bg = hl_attr(group, "bg") or hl_attr("Normal", "bg") or "NONE", bold = true })
  hl_cache[group] = name
  return name
end

-- The group a window uses for its Normal background (panels remap it)
local function window_normal_group(win)
  for mapping in (vim.wo[win].winhighlight or ""):gmatch("[^,]+") do
    local from, to = mapping:match("^([^:]+):(.+)$")
    if from == "Normal" then return to end
  end
  return "Normal"
end

-- ─── Float pool ────────────────────────────────────────────────────────────

local function draw(name, row, col, lines, group)
  local width = vim.fn.strdisplaywidth(lines[1] or "")
  if width <= 0 or #lines == 0 then return end
  used[name] = true
  local item = pool[name]
  if not item or not vim.api.nvim_buf_is_valid(item.buf) then
    item = { buf = vim.api.nvim_create_buf(false, true) }
    vim.bo[item.buf].bufhidden = "hide"
    vim.bo[item.buf].filetype = "lenn-focus-frame"
    pool[name] = item
  end
  vim.api.nvim_buf_set_lines(item.buf, 0, -1, false, lines)
  local config = {
    relative = "editor", row = row, col = col, width = width, height = #lines,
    focusable = false, zindex = 5, style = "minimal", mouse = false,
  }
  if item.win and vim.api.nvim_win_is_valid(item.win) then
    vim.api.nvim_win_set_config(item.win, config)
  else
    config.noautocmd = true
    item.win = vim.api.nvim_open_win(item.buf, false, config)
    vim.wo[item.win].winblend = 0
  end
  local hl = frame_hl(group)
  vim.wo[item.win].winhighlight = "Normal:" .. hl .. ",NormalFloat:" .. hl
end

local function hide_unused()
  for name, item in pairs(pool) do
    if not used[name] and item.win and vim.api.nvim_win_is_valid(item.win) then
      pcall(vim.api.nvim_win_hide, item.win)
      item.win = nil
    end
  end
end

local function hide_all()
  last_key = nil
  used = {}
  hide_unused()
end

-- ─── Screen rows we may draw on ────────────────────────────────────────────

local function tabline_visible()
  return vim.o.showtabline == 2 or (vim.o.showtabline == 1 and #vim.api.nvim_list_tabpages() > 1)
end

local function statusline_row()
  if vim.o.laststatus ~= 3 then return nil end
  return vim.o.lines - vim.o.cmdheight - 1
end

-- Per-cell blank flags of a rendered string, without padding
local function cells_from_text_raw(text, width)
  local cells = {}
  for _, ch in ipairs(vim.fn.split(text, "\\zs")) do
    local w = math.max(1, vim.fn.strdisplaywidth(ch))
    for _ = 1, w do table.insert(cells, ch == " ") end
  end
  for i = #cells + 1, width do cells[i] = true end
  return cells
end

-- Convert a rendered string into per-cell "free" flags (true = blank), with a
-- one-cell gap kept next to any text so the line never touches it.
local function cells_from_text(text, width)
  local cells = {}
  for _, ch in ipairs(vim.fn.split(text, "\\zs")) do
    local w = math.max(1, vim.fn.strdisplaywidth(ch))
    for _ = 1, w do table.insert(cells, ch == " ") end
  end
  for i = #cells + 1, width do cells[i] = true end
  local padded = {}
  for i = 1, width do
    padded[i] = cells[i] and (cells[i - 1] ~= false) and (cells[i + 1] ~= false)
  end
  return padded
end

-- Free cells of the window's winbar row (its title row), window-relative 1..width
local function winbar_cells(win)
  local expr = vim.wo[win].winbar
  local width = vim.api.nvim_win_get_width(win)
  if not expr or expr == "" then return nil end
  local ok, res = pcall(vim.api.nvim_eval_statusline, expr, { winid = win, use_winbar = true, maxwidth = width })
  if not ok or not res then return nil end
  -- Corner on the first cell (when blank) + a line after the last title text;
  -- gaps between title items (e.g. "Threads   Tasks") stay untouched.
  local cells = cells_from_text(res.str or "", width)
  local raw = cells_from_text_raw(res.str or "", width)
  local last = 0
  for i = 1, width do if not raw[i] then last = i end end
  local out = {}
  for i = 1, width do
    out[i] = (i == 1 and raw[1]) or (i > last + 1 and cells[i])
  end
  return out
end

-- Free cells of the window's first/last *text* row, from the buffer (the screen
-- would show our own frame once it is drawn there). Gutter counts as occupied.
local function text_row_cells(win, which)
  local info = vim.fn.getwininfo(win)[1]
  local width = vim.api.nvim_win_get_width(win)
  if not info then return nil end
  return vim.api.nvim_win_call(win, function()
    local topline = vim.fn.line("w0")
    local lnum = which == "first" and topline or (topline + info.height - 1)
    local cells = {}
    if lnum > vim.fn.line("$") then
      for i = 1, width do cells[i] = true end -- past the end of the buffer
      return cells
    end
    local leftcol = vim.fn.winsaveview().leftcol
    local text = vim.fn.getline(lnum)
    local shown = vim.fn.strdisplaywidth(text) - leftcol
    if text:match("^%s*$") then shown = 0 end
    local used = info.textoff + math.max(0, shown)
    local gutter_blank = info.textoff == 0
    for i = 1, width do
      if i <= info.textoff then
        cells[i] = gutter_blank
      else
        cells[i] = i > used + 1 -- +1: keep a gap after the text
      end
    end
    return cells
  end)
end

local function mask_key(mask, n)
  if not mask then return "-" end
  local out = {}
  for i = 1, n do out[i] = mask[i] and "1" or "0" end
  return table.concat(out)
end

-- Draw a horizontal side from screen col x0 to x1 (inclusive) on `row`.
-- `free(x)` (optional) says whether screen col x may be drawn on.
local function draw_hline(prefix, row, x0, x1, left_corner, right_corner, free, group)
  local runs, current = {}, nil
  for x = x0, x1 do
    local ch = "─"
    if x == x0 and left_corner then ch = left_corner end
    if x == x1 and right_corner then ch = right_corner end
    if not free or free(x) then
      if current and current.last == x - 1 then
        current.text = current.text .. ch
        current.last = x
      else
        current = { start = x, last = x, text = ch }
        table.insert(runs, current)
      end
    else
      current = nil
    end
  end
  for i, run in ipairs(runs) do
    draw(prefix .. i, row, run.start, { run.text }, group)
  end
end

-- Group a window maps `from` to (panels remap Normal / WinBar)
local function window_group(win, from)
  for mapping in (vim.wo[win].winhighlight or ""):gmatch("[^,]+") do
    local a, b = mapping:match("^([^:]+):(.+)$")
    if a == from then return b end
  end
  return from
end

-- ─── Update ────────────────────────────────────────────────────────────────

-- File windows have no title row; give them one (file name) so the frame's top
-- side has somewhere to go without covering code.
local function ensure_file_winbars()
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_config(w).relative == "" then
      local b = vim.api.nvim_win_get_buf(w)
      if vim.bo[b].buftype == "" and vim.wo[w].winbar == "" and vim.api.nvim_buf_get_name(b) ~= "" then
        vim.wo[w].winbar = " %{%v:lua.require'lenn.focus-frame'.file_title()%}"
      end
    end
  end
end

function M.file_title()
  local buf = vim.api.nvim_get_current_buf()
  local name = vim.api.nvim_buf_get_name(buf)
  local rel = name ~= "" and vim.fn.fnamemodify(name, ":~:.") or "[No Name]"
  local icon = require("lenn.icons").file_default
  local ok, devicons = pcall(require, "nvim-web-devicons")
  if ok then icon = devicons.get_icon(name, nil, { default = true }) or icon end
  return icon .. " " .. rel:gsub("%%", "%%%%") .. (vim.bo[buf].modified and " ●" or "")
end

function M.update()
  if not enabled then return hide_all() end
  ensure_file_winbars()
  local win = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_get_config(win).relative ~= "" then
    return -- keep the frame on the last real window while a float has focus
  end

  local normal = 0
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_config(w).relative == "" then normal = normal + 1 end
  end
  if normal < 2 then return hide_all() end

  local pos = vim.api.nvim_win_get_position(win)
  local row, col = pos[1], pos[2]
  local height = vim.api.nvim_win_get_height(win) -- includes the winbar
  local width = vim.api.nvim_win_get_width(win)
  local columns = vim.o.columns
  local status_row = statusline_row() or (vim.o.lines - vim.o.cmdheight)
  local first_row = tabline_visible() and 1 or 0
  local inner_group = window_normal_group(win)

  -- Left / right: the separator next to the window, or its own outer column
  local left_col = col - 1 >= 0 and col - 1 or col
  local right_col = col + width < columns and col + width or col + width - 1

  -- Never draw on the bufferline (top) or lualine (bottom): at the screen
  -- edges the frame goes inside the window, on its title (winbar) row and its
  -- last row, and only over blank cells there.
  local top_row, top_mask, top_group
  if row - 1 >= first_row then
    top_row, top_group = row - 1, "WinSeparator"
  else
    top_row = row
    top_mask = winbar_cells(win)
    top_group = top_mask and window_group(win, "WinBar") or inner_group
    top_mask = top_mask or text_row_cells(win, "first")
  end

  local bottom_row, bottom_mask, bottom_group
  if row + height < status_row then
    bottom_row, bottom_group = row + height, "WinSeparator"
  else
    bottom_row, bottom_group = row + height - 1, inner_group
    bottom_mask = text_row_cells(win, "last")
  end

  -- Screen col -> may we draw there? Cells outside the window (separators) are free.
  local function mask_fn(mask)
    if not mask then return nil end
    return function(x)
      if x < col or x >= col + width then return true end
      return mask[x - col + 1] == true
    end
  end

  local left_group = left_col < col and "WinSeparator" or inner_group
  local right_group = right_col >= col + width and "WinSeparator" or inner_group

  local key = table.concat({ win, row, col, height, width, columns, vim.o.lines, vim.o.cmdheight,
    top_row, bottom_row, mask_key(top_mask, width), mask_key(bottom_mask, width), inner_group, top_group }, ":")
  if key == last_key then return end
  last_key = key

  used = {}
  draw_hline("top", top_row, left_col, right_col, "╭", "╮", mask_fn(top_mask), top_group)
  draw_hline("bottom", bottom_row, left_col, right_col, "╰", "╯", mask_fn(bottom_mask), bottom_group)

  local v0, v1 = top_row + 1, bottom_row - 1
  if v1 >= v0 then
    local vlines = {}
    for _ = v0, v1 do table.insert(vlines, "│") end
    draw("left", v0, left_col, vlines, left_group)
    draw("right", v0, right_col, vlines, right_group)
  end
  hide_unused()
end

local pending = false
function M.schedule_update(force)
  if force then last_key = nil end
  if pending then return end
  pending = true
  vim.schedule(function()
    pending = false
    local ok, err = pcall(M.update)
    if not ok then vim.notify("focus-frame: " .. tostring(err), vim.log.levels.DEBUG) end
  end)
end

function M.toggle()
  enabled = not enabled
  M.update()
end

function M.setup()
  -- After plugins/colorscheme set AgentFocusFrame
  vim.schedule(set_highlight)
  local group = vim.api.nvim_create_augroup("LennFocusFrame", { clear = true })
  vim.api.nvim_create_autocmd({ "WinEnter", "WinResized", "VimResized", "WinClosed", "WinNew",
    "TabEnter", "BufWinEnter", "BufEnter", "VimEnter", "ModeChanged", "BufModifiedSet",
    "CursorHold", "CursorHoldI", "OptionSet" }, {
    group = group,
    callback = function(args)
      if args.event == "OptionSet" and not vim.tbl_contains(
        { "showtabline", "laststatus", "cmdheight", "winbar" }, args.match) then
        return
      end
      -- Only WinResized can come from our own floats; everything else redraws
      M.schedule_update(args.event ~= "WinResized")
    end,
  })
  -- The statusline text (cursor position) moves as you type: recheck its gaps
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "TextChanged", "TextChangedI", "TextChangedT" }, {
    group = group,
    callback = function() M.schedule_update(false) end,
  })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = function()
      vim.schedule(function() set_highlight(); M.schedule_update(true) end)
    end,
  })
  vim.api.nvim_create_user_command("FocusFrameToggle", M.toggle, { desc = "Toggle focused-window frame" })
end

return M
