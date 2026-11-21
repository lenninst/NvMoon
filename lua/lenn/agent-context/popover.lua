-- Floating category menu for the agent context picker.
-- j/k or arrows move (skipping unavailable rows), <CR> confirms, 1-9 jumps,
-- <Esc>/q cancels. Unavailable categories are rendered dimmed.
local M = {}

local ns = vim.api.nvim_create_namespace("lenn_agent_context_popover")

-- opts.ctx: shared context; opts.on_select(category, provider); opts.on_cancel()
function M.open(opts)
  local ctx_mod = require("lenn.agent-context")
  local rows = {}
  for _, cat in ipairs(ctx_mod.categories) do
    local provider, load_err = ctx_mod.provider(cat.id)
    local ok, reason = false, load_err == "missing" and "not implemented yet" or load_err
    if provider then
      local call_ok, avail, why = pcall(provider.available, opts.ctx)
      ok = call_ok and avail == true
      reason = (not call_ok and tostring(avail)) or why
    end
    rows[#rows + 1] = { cat = cat, provider = provider, enabled = ok, reason = reason }
  end

  local lines, width = {}, 0
  for i, row in ipairs(rows) do
    local text = string.format(" %d  %s  %s", i, row.cat.icon, (row.provider and row.provider.name) or row.cat.name)
    if not row.enabled and row.reason then text = text .. "  · " .. row.reason end
    lines[i] = text .. " "
    width = math.max(width, vim.fn.strdisplaywidth(lines[i]))
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  for i, row in ipairs(rows) do
    vim.api.nvim_buf_set_extmark(buf, ns, i - 1, 0, {
      end_col = #lines[i],
      hl_group = row.enabled and "Normal" or "AgentContextDim",
    })
    vim.api.nvim_buf_set_extmark(buf, ns, i - 1, 1, { end_col = 2, hl_group = "AgentContextKey" })
  end

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "cursor",
    row = 1,
    col = 0,
    width = width,
    height = #lines,
    style = "minimal",
    border = "rounded",
    title = " Add context ",
    title_pos = "left",
    zindex = 60,
  })
  vim.wo[win].cursorline = true
  vim.wo[win].winhighlight = "CursorLine:AgentContextSel"

  local closed = false
  local function close()
    if closed then return end
    closed = true
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
  end

  local function first_enabled(from, step)
    local i = from
    for _ = 1, #rows do
      if i < 1 then i = #rows elseif i > #rows then i = 1 end
      if rows[i].enabled then return i end
      i = i + step
    end
  end

  local function move(step)
    local cur = vim.api.nvim_win_get_cursor(win)[1]
    local target = first_enabled(cur + step, step)
    if target then vim.api.nvim_win_set_cursor(win, { target, 0 }) end
  end

  local function confirm(index)
    local row = rows[index or vim.api.nvim_win_get_cursor(win)[1]]
    if not row then return end
    if not row.enabled then
      vim.notify(row.cat.name .. ": " .. (row.reason or "unavailable"), vim.log.levels.INFO)
      return
    end
    close()
    vim.schedule(function() opts.on_select(row.cat, row.provider) end)
  end

  local function cancel()
    close()
    vim.schedule(opts.on_cancel)
  end

  local map = function(lhs, fn) vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true }) end
  for _, k in ipairs({ "j", "<Down>", "<C-n>", "<Tab>" }) do map(k, function() move(1) end) end
  for _, k in ipairs({ "k", "<Up>", "<C-p>", "<S-Tab>" }) do map(k, function() move(-1) end) end
  map("<CR>", function() confirm() end)
  for i = 1, math.min(#rows, 9) do map(tostring(i), function() confirm(i) end) end
  for _, k in ipairs({ "<Esc>", "q", "<C-c>" }) do map(k, cancel) end
  vim.api.nvim_create_autocmd("WinLeave", {
    buffer = buf,
    once = true,
    callback = function()
      if not closed then cancel() end
    end,
  })

  local start = first_enabled(1, 1)
  if start then vim.api.nvim_win_set_cursor(win, { start, 0 }) end
end

return M
