-- Threads provider: attach a previous agent conversation (any provider) as
-- context. Threads of the current project are listed first; the thread the
-- active session is running is left out.
local nf = require("lenn.icons")
local transcripts = require("lenn.agent-context.transcripts")

local M = {
  name = "Threads",
  icon = nf.thread,
}

function M.available()
  if not rawget(_G, "Snacks") then return false, "snacks.nvim not loaded" end
  local ok, ws = pcall(require, "lenn.agent-workspace")
  if not ok or not ws.list_threads then return false, "agent workspace not loaded" end
  return true
end

local function rel_time(epoch)
  local ok, ws = pcall(require, "lenn.agent-workspace")
  if ok and ws._ui and ws._ui.rel_time then return ws._ui.rel_time(epoch) end
  return os.date("%Y-%m-%d", epoch)
end

local function short(text, max)
  text = (text or ""):gsub("%s+", " ")
  if vim.fn.strchars(text) > max then text = vim.fn.strcharpart(text, 0, max - 1) .. "…" end
  return text
end

local function sort_threads(threads, cwd, skip_id)
  local mine, others = {}, {}
  for _, t in ipairs(threads) do
    if t.id ~= skip_id and transcripts.supported(t.provider) then
      table.insert(t.cwd == cwd and mine or others, t)
    end
  end
  return vim.list_extend(mine, others)
end

function M.make_item(thread)
  return {
    provider = "threads",
    key = "threads:" .. thread.provider .. ":" .. thread.id,
    label = "@Thread:" .. short(thread.title, 40),
    thread_provider = thread.provider,
    id = thread.id,
    title = thread.title,
    cwd = thread.cwd,
  }
end

local preview_cache = {}

local function preview(pctx)
  local t = pctx.item.thread
  local key = t.provider .. ":" .. t.id
  if not preview_cache[key] then
    local messages, err = transcripts.read(t.provider, t.id)
    local text = messages and transcripts.render(messages, 16 * 1024, 12) or ("(" .. tostring(err) .. ")")
    preview_cache[key] = vim.split(text, "\n", { plain = true })
  end
  pctx.preview:reset()
  pctx.preview:set_lines(preview_cache[key])
  pctx.preview:highlight({ ft = "markdown" })
  pctx.preview:set_title(t.provider .. " · " .. short(t.title, 50))
end

function M.items(ctx, cb)
  local skip_id = ctx.session and ctx.session.thread_id
  require("lenn.agent-workspace").list_threads(function(threads)
    threads = sort_threads(threads or {}, ctx.cwd, skip_id)
    if #threads == 0 then
      vim.notify("agent-context: no saved threads", vim.log.levels.INFO)
      return cb(nil)
    end
    local items = {}
    for _, t in ipairs(threads) do
      items[#items + 1] = {
        text = table.concat({ t.provider, t.title or "", vim.fn.fnamemodify(t.cwd or "", ":t") }, " "),
        thread = t,
      }
    end

    local chosen
    Snacks.picker.pick({
      title = "Add context: threads",
      items = items,
      format = function(item)
        local t = item.thread
        local here = t.cwd == ctx.cwd
        return {
          { (t.icon or nf.thread) .. " ", "Special" },
          { short(t.title, 60) .. " " },
          { vim.fn.fnamemodify(t.cwd or "", ":t") .. " ", here and "Directory" or "Comment" },
          { rel_time(t.updated or 0), "Comment" },
        }
      end,
      preview = preview,
      confirm = function(picker, item)
        chosen = item
        picker:close()
      end,
      on_close = function()
        vim.schedule(function() cb(chosen and M.make_item(chosen.thread) or nil) end)
      end,
    })
  end)
end

function M.resolve(item, _, limits)
  local messages, err = transcripts.read(item.thread_provider, item.id)
  if not messages then return nil, err end
  if #messages == 0 then return nil, "thread has no messages" end
  local body, info = transcripts.render(messages, limits.thread_bytes, limits.thread_messages)
  local attrs = {
    agent = item.thread_provider,
    id = item.id,
    title = short(item.title, 80),
    messages = info.included < info.total and (info.included .. "/" .. info.total) or tostring(info.total),
  }
  return { tag = "thread", attrs = attrs, body = body }
end

return M
