-- Compose float for the agent panel: write a prompt, add @mentions, send it to
-- whichever agent session is active at send time.
local M = {}
local nf = require("lenn.icons")

local ns = vim.api.nvim_create_namespace("lenn_agent_context_mentions")

local state = {
  buf = nil,
  win = nil,
  origin_win = nil,
  items = {}, -- extmark id -> item
}

local function config() return require("lenn.agent-context").config end

local function active_session()
  local ok, ws = pcall(require, "lenn.agent-workspace")
  if not ok or not ws.active_session then return nil end
  return ws.active_session()
end

local function make_ctx()
  local session = active_session()
  return {
    session = session,
    cwd = (session and session.cwd) or vim.fn.getcwd(),
    origin_win = state.origin_win,
  }
end

local function win_title()
  local session = active_session()
  local name = session and session.provider or "no active agent"
  return string.format(" %s Compose · %s ", nf.agent, name)
end

local function refresh_title()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_set_config(state.win, { title = win_title(), title_pos = "left" })
  end
end

-- ─── Mentions ───────────────────────────────────────────────────────────────

local function resume_insert(row, col)
  if not (state.win and vim.api.nvim_win_is_valid(state.win)) then return end
  vim.api.nvim_set_current_win(state.win)
  local line = vim.api.nvim_buf_get_lines(state.buf, row - 1, row, false)[1] or ""
  if col >= #line then
    vim.api.nvim_win_set_cursor(state.win, { row, #line })
    vim.cmd.startinsert({ bang = true })
  else
    vim.api.nvim_win_set_cursor(state.win, { row, col })
    vim.cmd.startinsert()
  end
end

local function insert_text(row, col, text)
  vim.api.nvim_buf_set_text(state.buf, row - 1, col, row - 1, col, { text })
  return col + #text
end

function M.add_mention(item, row, col)
  local label = item.label
  insert_text(row, col, label .. " ")
  local id = vim.api.nvim_buf_set_extmark(state.buf, ns, row - 1, col, {
    end_row = row - 1,
    end_col = col + #label,
    hl_group = "AgentContextMention",
  })
  state.items[id] = item
  return col + #label + 1
end

-- Mentions still present in the buffer, in document order, deduplicated.
-- A mention whose text was edited or deleted no longer contributes context.
local function collect_mentions()
  local marks = vim.api.nvim_buf_get_extmarks(state.buf, ns, 0, -1, { details = true })
  local result, seen = {}, {}
  for _, mark in ipairs(marks) do
    local id, row, col, details = mark[1], mark[2], mark[3], mark[4]
    local item = state.items[id]
    if item and details.end_row then
      local ok, text = pcall(vim.api.nvim_buf_get_text, state.buf, row, col, details.end_row, details.end_col, {})
      if ok and table.concat(text, "\n") == item.label and not seen[item.key] then
        seen[item.key] = true
        result[#result + 1] = item
      end
    end
  end
  return result
end

-- ─── Popover ────────────────────────────────────────────────────────────────

-- Opens the category popover; on cancel inserts `fallback` (the typed "@").
function M.open_popover(fallback)
  if not (state.win and vim.api.nvim_win_is_valid(state.win)) then return end
  local cursor = vim.api.nvim_win_get_cursor(state.win)
  local row, col = cursor[1], cursor[2]
  local ctx = make_ctx()
  vim.cmd.stopinsert()

  local function restore(new_col) resume_insert(row, new_col or col) end
  local function cancel()
    if fallback then return restore(insert_text(row, col, fallback)) end
    restore()
  end

  vim.schedule(function()
    require("lenn.agent-context.popover").open({
      ctx = ctx,
      on_cancel = cancel,
      on_select = function(_, provider)
        local ok, err = pcall(provider.items, ctx, function(item)
          if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then return end
          if not item then return cancel() end
          restore(M.add_mention(item, row, col))
        end)
        if not ok then
          vim.notify("agent-context: " .. tostring(err), vim.log.levels.ERROR)
          cancel()
        end
      end,
    })
  end)
end

-- ─── Send ───────────────────────────────────────────────────────────────────

local function use_bracketed_paste(provider)
  local opt = config().bracketed_paste
  if type(opt) ~= "table" then return opt ~= false end
  if opt[provider] ~= nil then return opt[provider] end
  return opt.default ~= false
end

local function job_running(job)
  local ok, res = pcall(vim.fn.jobwait, { job }, 0)
  return ok and res[1] == -1
end

function M.build_prompt()
  local text = vim.trim(table.concat(vim.api.nvim_buf_get_lines(state.buf, 0, -1, false), "\n"))
  local ctx = make_ctx()
  local entries = {}
  for _, item in ipairs(collect_mentions()) do
    local provider = require("lenn.agent-context").provider(item.provider)
    if provider then entries[#entries + 1] = { item = item, provider = provider } end
  end
  local context, warnings = require("lenn.agent-context.resolve").resolve_all(entries, ctx, config().limits)
  if context ~= "" then text = text .. "\n\n" .. context end
  return text, warnings, ctx
end

function M.send()
  if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then return end
  local session = active_session()
  if not session or not session.job or not job_running(session.job) then
    vim.notify("agent-context: no running agent session to send to", vim.log.levels.WARN)
    return
  end

  local prompt, warnings = M.build_prompt()
  if prompt == "" then return end
  for _, w in ipairs(warnings) do vim.notify("agent-context: " .. w, vim.log.levels.WARN) end

  local payload = prompt
  if use_bracketed_paste(session.provider) then payload = "\27[200~" .. prompt .. "\27[201~" end
  local ok, err = pcall(vim.api.nvim_chan_send, session.job, payload)
  if not ok then
    vim.notify("agent-context: send failed: " .. tostring(err), vim.log.levels.ERROR)
    return
  end
  -- TUIs need a moment to finish handling the paste before Enter submits it
  vim.defer_fn(function() pcall(vim.api.nvim_chan_send, session.job, "\r") end, 80)

  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, {})
  vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
  state.items = {}
  M.close()

  local term_win = session.bufnr and vim.fn.bufwinid(session.bufnr) or -1
  if term_win ~= -1 then
    vim.api.nvim_set_current_win(term_win)
    vim.cmd.startinsert()
  end
end

-- ─── Window ─────────────────────────────────────────────────────────────────

local function ensure_buf()
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then return state.buf end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, "Agent Compose")
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "agent-compose"
  pcall(vim.treesitter.start, buf, "markdown")
  state.buf = buf
  state.items = {}

  local cfg = config()
  local opts = function(desc) return { buffer = buf, desc = desc, nowait = true } end
  vim.keymap.set("i", cfg.trigger, function()
    local col = vim.api.nvim_win_get_cursor(0)[2]
    local before = col > 0 and vim.api.nvim_get_current_line():sub(col, col) or ""
    if before ~= "" and not before:match("%s") then return cfg.trigger end
    vim.schedule(function() M.open_popover(cfg.trigger) end)
    return ""
  end, vim.tbl_extend("force", opts("Agent: add context"), { expr = true }))
  vim.keymap.set({ "i", "n" }, cfg.popover_key, function() M.open_popover(nil) end, opts("Agent: add context"))
  vim.keymap.set({ "i", "n" }, cfg.send_key, M.send, opts("Agent: send prompt"))
  vim.keymap.set("n", "<Esc>", M.close, opts("Close compose"))
  vim.keymap.set("n", "q", M.close, opts("Close compose"))
  return buf
end

local function win_config()
  local origin = state.origin_win
  local footer = string.format(" %s context · %s send · <Esc> close ", config().trigger, config().send_key)
  local base = {
    style = "minimal",
    border = "rounded",
    title = win_title(),
    title_pos = "left",
    footer = footer,
    footer_pos = "right",
    zindex = 50,
  }
  if origin and vim.api.nvim_win_is_valid(origin) and vim.b[vim.api.nvim_win_get_buf(origin)].agent_panel then
    local w, h = vim.api.nvim_win_get_width(origin), vim.api.nvim_win_get_height(origin)
    local height = math.max(3, math.min(10, h - 4))
    return vim.tbl_extend("force", base, {
      relative = "win",
      win = origin,
      width = math.max(20, w - 4),
      height = height,
      row = math.max(0, h - height - 3),
      col = 1,
    })
  end
  local width = math.min(100, math.floor(vim.o.columns * 0.6))
  local height = 10
  return vim.tbl_extend("force", base, {
    relative = "editor",
    width = width,
    height = height,
    row = vim.o.lines - height - 5,
    col = math.floor((vim.o.columns - width) / 2),
  })
end

-- Append mentions at the end of the last line (used by :'<,'>LagentCompose)
local function append_mentions(mentions)
  for _, item in ipairs(mentions or {}) do
    local row = vim.api.nvim_buf_line_count(state.buf)
    local line = vim.api.nvim_buf_get_lines(state.buf, row - 1, row, false)[1] or ""
    local col = #line
    if col > 0 and not line:sub(-1):match("%s") then col = insert_text(row, col, " ") end
    M.add_mention(item, row, col)
  end
end

-- opts.mentions: items to add right away
function M.open(opts)
  opts = opts or {}
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_set_current_win(state.win)
    refresh_title()
    append_mentions(opts.mentions)
    return
  end
  state.origin_win = vim.api.nvim_get_current_win()
  local mode = vim.fn.mode()
  if mode == "t" or mode == "i" then vim.cmd.stopinsert() end
  local buf = ensure_buf()
  append_mentions(opts.mentions)
  vim.schedule(function()
    state.win = vim.api.nvim_open_win(buf, true, win_config())
    vim.wo[state.win].wrap = true
    vim.wo[state.win].linebreak = true
    local last = vim.api.nvim_buf_line_count(buf)
    vim.api.nvim_win_set_cursor(state.win, { last, #(vim.api.nvim_buf_get_lines(buf, last - 1, last, false)[1] or "") })
    vim.cmd.startinsert({ bang = true })
  end)
end

function M.close()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win = nil
  if state.origin_win and vim.api.nvim_win_is_valid(state.origin_win) then
    vim.api.nvim_set_current_win(state.origin_win)
  end
end

-- Exposed for tests / other modules
M._state = state
M._collect_mentions = collect_mentions

return M
