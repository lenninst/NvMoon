-- Selection provider: the last visual selection made in a file buffer.
-- The compose float is usually opened from an agent terminal, so the live
-- visual selection is gone by then; we snapshot it whenever visual mode ends.
local nf = require("lenn.icons")

local M = {
  name = "Selection",
  icon = nf.selection,
}

local last -- { buf, path, rel, ft, start_line, end_line, text }

function M.capture(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "" then return end
  local path = vim.api.nvim_buf_get_name(buf)
  if path == "" then return end

  local s = vim.api.nvim_buf_get_mark(buf, "<")
  local e = vim.api.nvim_buf_get_mark(buf, ">")
  if s[1] == 0 or e[1] == 0 then return end
  local maxcol = vim.v.maxcol
  local ok, lines = pcall(vim.fn.getregion,
    { buf, s[1], math.min(s[2] + 1, maxcol), 0 },
    { buf, e[1], math.min(e[2] + 1, maxcol), 0 },
    { type = vim.fn.visualmode() })
  if not ok or #lines == 0 then return end
  local text = table.concat(lines, "\n")
  if vim.trim(text) == "" then return end

  last = {
    buf = buf,
    path = path,
    rel = vim.fn.fnamemodify(path, ":~:."),
    ft = vim.bo[buf].filetype,
    start_line = s[1],
    end_line = e[1],
    text = text,
  }
  return last
end

function M.clear() last = nil end
function M.get() return last end

function M.setup(group)
  vim.api.nvim_create_autocmd("ModeChanged", {
    group = group,
    pattern = "[vV\22]*:*",
    callback = function(args)
      -- '< and '> are set once visual mode has fully ended
      vim.schedule(function() M.capture(args.buf) end)
    end,
  })
end

function M.available()
  if not last then return false, "no visual selection" end
  return true
end

function M.make_item(sel)
  local range = sel.start_line == sel.end_line and tostring(sel.start_line)
    or (sel.start_line .. "-" .. sel.end_line)
  local name = vim.fn.fnamemodify(sel.path, ":t")
  return {
    provider = "selection",
    key = string.format("selection:%s:%s:%d", sel.path, range, #sel.text),
    label = string.format("@Selection:%s:%s", name, range),
    snapshot = sel,
    range = range,
  }
end

function M.items(_, cb)
  if not last then return cb(nil) end
  cb(M.make_item(last))
end

function M.resolve(item, _, limits)
  local sel = item.snapshot
  local body, cut = require("lenn.agent-context.resolve").truncate(sel.text, limits.file_bytes)
  local attrs = { path = sel.rel, lines = item.range, language = sel.ft ~= "" and sel.ft or nil }
  if cut then attrs.truncated = "true" end
  return { tag = "selection", attrs = attrs, body = body }
end

return M
