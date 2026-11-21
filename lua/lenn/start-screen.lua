-- Start screen for empty editor windows.
--
-- Replaces two kinds of "nothing open" buffers with a centered, read-only menu:
--   * an empty, unnamed, unmodified buffer ([No Name] at startup or after
--     closing the last file)
--   * a buffer whose name is a directory (`nvim .`, restored sessions).
--     Typing there and saving fails with E502, so it should never be editable.
--
-- Typing an insert key (i/a/o/...) on the start screen opens a fresh empty
-- buffer and enters insert mode, so typing "by accident" just works.

local M = {}

local nf = require("lenn.icons")
local ns = vim.api.nvim_create_namespace("lenn_start_screen")
local item_maps = {} -- buf -> { [row] = key }
local discarding = false -- our own buffer cleanup must not re-trigger checks

local ITEMS = {
  { key = "e", icon = nf.folder_open, label = "Open explorer" },
  { key = "f", icon = nf.search, label = "Find file" },
  { key = "n", icon = nf.file_default, label = "New file" },
  { key = "r", icon = nf.hourglass, label = "Recent files" },
  { key = "p", icon = nf.project, label = "Open project" },
}

-- ─── Detection ─────────────────────────────────────────────────────────────

local function is_start_buf(buf)
  return vim.api.nvim_buf_is_valid(buf) and vim.b[buf].lenn_start_screen == true
end

local function is_directory_buf(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  return name ~= "" and vim.fn.isdirectory(name) == 1
end

local function is_empty_noname_buf(buf)
  if vim.api.nvim_buf_get_name(buf) ~= "" then return false end
  if vim.bo[buf].modified then return false end
  if vim.api.nvim_buf_line_count(buf) > 1 then return false end
  return (vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or "") == ""
end

-- Only plain, non-floating editor windows (no panels, terminals, explorers).
local function should_replace(win, dirs_only)
  if not vim.api.nvim_win_is_valid(win) then return false end
  if vim.api.nvim_win_get_config(win).relative ~= "" then return false end
  local buf = vim.api.nvim_win_get_buf(win)
  if is_start_buf(buf) or vim.b[buf].agent_panel or vim.b[buf].lenn_keep_empty then return false end
  if vim.bo[buf].buftype ~= "" or vim.bo[buf].filetype ~= "" then return false end
  if dirs_only then return is_directory_buf(buf) end
  return is_directory_buf(buf) or is_empty_noname_buf(buf)
end

-- ─── Rendering ─────────────────────────────────────────────────────────────

local function render(buf, win)
  if not is_start_buf(buf) or not vim.api.nvim_win_is_valid(win) then return end
  local width = vim.api.nvim_win_get_width(win)
  local height = vim.api.nvim_win_get_height(win)

  local body = {
    { text = nf.generic .. "  NvMoon", hl = "Title" },
    { text = "No file open", hl = "Comment" },
    { text = "" },
  }
  for _, item in ipairs(ITEMS) do
    table.insert(body, { item = item, text = string.format("%s  %-16s [%s]", item.icon, item.label, item.key) })
  end
  table.insert(body, { text = "" })
  table.insert(body, { text = "Start typing (i) to write in a new buffer", hl = "Comment" })

  local block_width = 0
  for _, line in ipairs(body) do
    block_width = math.max(block_width, vim.fn.strdisplaywidth(line.text))
  end
  local left = math.max(0, math.floor((width - block_width) / 2))
  local top = math.max(0, math.floor((height - #body) / 2))

  local lines, marks = {}, {}
  for _ = 1, top do table.insert(lines, "") end
  for _, line in ipairs(body) do
    -- Title/hints are centered on their own; menu items share a left edge.
    local pad = line.item and left
      or math.max(0, math.floor((width - vim.fn.strdisplaywidth(line.text)) / 2))
    local text = string.rep(" ", pad) .. line.text
    table.insert(lines, text)
    table.insert(marks, { row = #lines - 1, pad = pad, line = line })
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].modified = false

  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  local item_rows = {}
  for _, mark in ipairs(marks) do
    if mark.line.item then
      item_rows[mark.row + 1] = mark.line.item
      local text = lines[mark.row + 1]
      local key_start = text:find("%[" .. mark.line.item.key .. "%]")
      vim.api.nvim_buf_set_extmark(buf, ns, mark.row, mark.pad, {
        end_col = mark.pad + #mark.line.item.icon, hl_group = "Special",
      })
      if key_start then
        vim.api.nvim_buf_set_extmark(buf, ns, mark.row, key_start - 1, {
          end_col = key_start + 2, hl_group = "Keyword",
        })
      end
    elseif mark.line.hl and mark.line.text ~= "" then
      vim.api.nvim_buf_set_extmark(buf, ns, mark.row, 0, { end_row = mark.row + 1, hl_group = mark.line.hl, hl_eol = false })
    end
  end
  item_maps[buf] = {}
  for row, item in pairs(item_rows) do item_maps[buf][row] = item.key end

  -- Park the cursor on the first menu item.
  local first = math.huge
  for row in pairs(item_rows) do first = math.min(first, row) end
  if first ~= math.huge and vim.api.nvim_win_get_buf(win) == buf then
    pcall(vim.api.nvim_win_set_cursor, win, { first, left })
  end
end

-- ─── Actions ───────────────────────────────────────────────────────────────

-- Replace the start screen in `win` with a new empty, editable buffer.
local function open_empty(win)
  win = win or vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_create_buf(true, false)
  vim.b[buf].lenn_keep_empty = true -- the user asked for it; don't replace
  vim.api.nvim_win_set_buf(win, buf)
  return buf
end

local function open_explorer()
  local ok = pcall(vim.cmd, "Neotree focus filesystem left reveal_force_cwd")
  if not ok then pcall(vim.cmd, "Neotree") end
end

local function new_file()
  local win = vim.api.nvim_get_current_win()
  vim.ui.input({ prompt = "New file (empty = scratch): ", default = vim.fn.getcwd() .. "/", completion = "file" }, function(input)
    if input == nil then return end
    input = vim.trim(input)
    if input == "" or input:sub(-1) == "/" then
      if vim.api.nvim_win_is_valid(win) then vim.api.nvim_set_current_win(win) end
      open_empty(win)
      return
    end
    local path = vim.fn.fnamemodify(vim.fn.expand(input), ":p")
    vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_set_current_win(win) end
    vim.cmd("edit " .. vim.fn.fnameescape(path))
  end)
end

local ACTIONS = {
  e = open_explorer,
  f = function()
    if _G.Snacks then Snacks.picker.files() else vim.cmd("browse edit") end
  end,
  n = new_file,
  r = function()
    if _G.Snacks then Snacks.picker.recent() else vim.cmd("browse oldfiles") end
  end,
  p = function() pcall(vim.cmd, "NeovimProjectDiscover") end,
}

local function set_keymaps(buf)
  local opts = { buffer = buf, nowait = true, silent = true }
  for key, fn in pairs(ACTIONS) do
    vim.keymap.set("n", key, fn, opts)
  end
  vim.keymap.set("n", "<CR>", function()
    local row = vim.api.nvim_win_get_cursor(0)[1]
    local key = (item_maps[buf] or {})[row]
    if key and ACTIONS[key] then ACTIONS[key]() end
  end, opts)
  -- Insert/change keys: start writing in a fresh buffer instead of erroring.
  for _, key in ipairs({ "i", "a", "o", "I", "A", "O", "s", "S", "c", "C", "R" }) do
    vim.keymap.set("n", key, function()
      open_empty()
      vim.cmd("startinsert")
    end, opts)
  end
  -- Paste goes into a new buffer too.
  for _, key in ipairs({ "p", "P" }) do
    if not ACTIONS[key] then
      vim.keymap.set("n", key, function()
        open_empty()
        vim.cmd("normal! " .. key)
      end, opts)
    end
  end
  -- Keys that would edit text are no-ops here.
  for _, key in ipairs({ "x", "X", "d", "D", "u", "<C-r>", "J", ".", "~", ">", "<" }) do
    vim.keymap.set("n", key, "<Nop>", opts)
  end
end

local function create_start_buf()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.b[buf].lenn_start_screen = true
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].undolevels = -1
  vim.bo[buf].filetype = "lenn-start"
  set_keymaps(buf)
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf, once = true, callback = function() item_maps[buf] = nil end,
  })
  return buf
end

-- Wipe the buffer we replaced if nothing else shows it (prevents directory
-- buffers from lingering in the buffer list / writing swap files).
local function discard(buf)
  if not vim.api.nvim_buf_is_valid(buf) or is_start_buf(buf) then return end
  if #vim.fn.win_findbuf(buf) > 0 or vim.bo[buf].modified then return end
  if is_directory_buf(buf) or is_empty_noname_buf(buf) then
    discarding = true
    pcall(vim.api.nvim_buf_delete, buf, { force = false })
    discarding = false
  end
end

function M.show(win, dirs_only)
  win = win or vim.api.nvim_get_current_win()
  if not should_replace(win, dirs_only) then return end
  local old = vim.api.nvim_win_get_buf(win)
  local buf = create_start_buf()
  vim.api.nvim_win_set_buf(win, buf)
  local wo = vim.wo[win][0]
  wo.number = false
  wo.relativenumber = false
  wo.signcolumn = "no"
  wo.cursorline = false
  wo.foldcolumn = "0"
  wo.list = false
  wo.wrap = false
  render(buf, win)
  vim.schedule(function() discard(old) end)
end

function M.check_all(dirs_only)
  -- Don't fight the Snacks dashboard while it is visible.
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].filetype == "snacks_dashboard" then return end
  end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    M.show(win, dirs_only)
  end
end

function M.setup()
  local group = vim.api.nvim_create_augroup("LennStartScreen", { clear = true })
  local pending, pending_full = false, false
  local function check_soon(full)
    pending_full = pending_full or full
    if pending then return end
    pending = true
    vim.schedule(function()
      local dirs_only = not pending_full
      pending, pending_full = false, false
      if vim.v.exiting ~= vim.NIL then return end
      M.check_all(dirs_only)
    end)
  end

  vim.api.nvim_create_autocmd("VimEnter", {
    group = group,
    -- Run after other VimEnter handlers (sessions, Neotree for `nvim <dir>`)
    callback = function() vim.defer_fn(function() M.check_all(false) end, 50) end,
  })
  -- Startup / session restore / closing the last file → any empty buffer.
  -- `:enew` and `:tabnew` are left alone, so you can still get a blank buffer.
  vim.api.nvim_create_autocmd("SessionLoadPost", {
    group = group,
    callback = function() check_soon(true) end,
  })
  vim.api.nvim_create_autocmd("BufDelete", {
    group = group,
    callback = function(args)
      -- Only closing a real file buffer counts; plugins constantly create and
      -- wipe scratch buffers, and leaving the start screen wipes it too.
      if discarding or is_start_buf(args.buf) then return end
      if not vim.bo[args.buf].buflisted or vim.bo[args.buf].buftype ~= "" then return end
      check_soon(true)
    end,
  })
  -- Directory buffers are never useful to edit: redirect them whenever seen.
  vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
    group = group,
    callback = function(args)
      if is_directory_buf(args.buf) then check_soon(false) end
    end,
  })
  -- Keep the menu centered.
  vim.api.nvim_create_autocmd({ "VimResized", "WinResized" }, {
    group = group,
    callback = function()
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        local buf = vim.api.nvim_win_get_buf(win)
        if is_start_buf(buf) then render(buf, win) end
      end
    end,
  })
end

return M
