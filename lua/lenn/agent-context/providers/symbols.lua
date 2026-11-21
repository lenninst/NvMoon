-- Symbols provider: LSP document symbols of the last code buffer, with <C-t>
-- toggling to live workspace symbols. Reuses Snacks' LSP finder but points it
-- at the tracked code buffer, since the compose float has no LSP itself and
-- the code window may be hidden (e.g. agent workspace mode).
local nf = require("lenn.icons")
local resolve = require("lenn.agent-context.resolve")

local M = {
  name = "Symbols",
  icon = nf.lualine_outline,
  toggle_key = "<C-t>",
}

local last_buf

local function is_code_buf(buf)
  return buf and vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == ""
    and vim.api.nvim_buf_get_name(buf) ~= ""
end

local function clients_for(buf, method)
  local result = {}
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
    local ok, supported = pcall(function() return client:supports_method(method, buf) end)
    if ok and supported then result[#result + 1] = client end
  end
  return result
end

function M.setup(group)
  vim.api.nvim_create_autocmd({ "BufEnter", "LspAttach" }, {
    group = group,
    callback = function(args)
      if is_code_buf(args.buf) then last_buf = args.buf end
    end,
  })
end

function M.target_buf()
  if is_code_buf(last_buf) then return last_buf end
end

function M.available()
  local buf = M.target_buf()
  if not buf then return false, "no code buffer" end
  if #clients_for(buf, "textDocument/documentSymbol") == 0
    and #clients_for(buf, "workspace/symbol") == 0 then
    return false, "no LSP for " .. vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":t")
  end
  return true
end

local function to_item(chosen, ctx)
  local file = chosen.file
  if not file then return nil end
  file = vim.fs.normalize(vim.fn.fnamemodify(file, ":p"))
  local range = chosen.range or (chosen.item and chosen.item.location and chosen.item.location.range)
  local start_line = range and range.start.line or (chosen.pos and chosen.pos[1] - 1) or 0
  local end_line = range and range["end"].line or start_line
  return {
    provider = "symbols",
    key = string.format("symbols:%s:%d:%s", file, start_line, chosen.name or ""),
    label = "@Symbol:" .. (chosen.name or "?"),
    name = chosen.name,
    kind = chosen.kind,
    file = file,
    rel = vim.fs.relpath(ctx.cwd, file) or vim.fn.fnamemodify(file, ":~:."),
    start_line = start_line,
    end_line = end_line,
    col = range and range.start.character or 0,
  }
end

function M.items(ctx, cb)
  local buf = M.target_buf()
  if not buf then return cb(nil) end
  local lsp = require("snacks.picker.source.lsp")
  local chosen, switching = nil, false
  local open
  local project_only = require("lenn.agent-context").config.symbols.project_only
  local root = vim.fs.normalize(vim.fn.fnamemodify(ctx.cwd, ":p")):gsub("/?$", "/")

  local function picker_opts(workspace)
    return {
      title = (workspace and "Workspace symbols" or "Document symbols") .. "  ·  "
        .. M.toggle_key .. " " .. (workspace and "document" or "workspace"),
      finder = function(opts, fctx)
        fctx.filter.current_buf = buf
        return lsp.symbols(opts, fctx)
      end,
      transform = workspace and project_only and function(item)
        if not item.file then return false end
        local file = vim.fs.normalize(vim.fn.fnamemodify(item.file, ":p"))
        return file:sub(1, #root) == root
      end or nil,
      confirm = function(picker, item)
        chosen = item
        picker:close()
      end,
      on_close = function()
        if switching then return end
        vim.schedule(function() cb(chosen and to_item(chosen, ctx) or nil) end)
      end,
      actions = {
        agent_context_toggle_scope = function(picker)
          switching = true
          picker:close()
          vim.schedule(function()
            switching = false
            open(not workspace)
          end)
        end,
      },
      win = {
        input = { keys = { [M.toggle_key] = { "agent_context_toggle_scope", mode = { "i", "n" } } } },
      },
    }
  end

  open = function(workspace)
    if workspace then
      Snacks.picker.lsp_workspace_symbols(picker_opts(true))
    else
      Snacks.picker.lsp_symbols(picker_opts(false))
    end
  end

  local has_doc = #clients_for(buf, "textDocument/documentSymbol") > 0
  open(not has_doc)
end

-- Lines of `file`, preferring the loaded buffer so unsaved edits are included.
local function file_lines(file)
  local buf = vim.fn.bufnr(file)
  if buf ~= -1 and vim.api.nvim_buf_is_loaded(buf) then
    return vim.api.nvim_buf_get_lines(buf, 0, -1, false), buf
  end
  local ok, lines = pcall(vim.fn.readfile, file)
  return ok and lines or nil, nil
end

-- Some servers only report the name range. Expand it with treesitter to the
-- largest node that starts on the same line (the whole declaration).
local function expand_range(buf, item)
  if not buf then return item.start_line, item.end_line end
  local ok, node = pcall(vim.treesitter.get_node, { bufnr = buf, pos = { item.start_line, item.col } })
  if not ok or not node then return item.start_line, item.end_line end
  local best = node
  local parent = node:parent()
  while parent and parent:parent() do
    local srow = parent:range()
    if srow ~= item.start_line then break end
    best = parent
    parent = parent:parent()
  end
  local srow, _, erow = best:range()
  return srow, erow
end

function M.resolve(item, _, limits)
  local lines, buf = file_lines(item.file)
  if not lines then return nil, "cannot read " .. item.rel end
  local s, e = item.start_line, item.end_line
  if s == e then s, e = expand_range(buf, item) end
  e = math.min(e, #lines - 1)

  local truncated = false
  if e - s + 1 > limits.file_lines then
    e = s + limits.file_lines - 1
    truncated = true
  end
  local body, cut = resolve.truncate(table.concat(vim.list_slice(lines, s + 1, e + 1), "\n"), limits.file_bytes)
  local attrs = {
    name = item.name,
    kind = item.kind,
    path = item.rel,
    lines = (s + 1) .. "-" .. (e + 1),
  }
  if truncated or cut then attrs.truncated = "true" end
  return { tag = "symbol", attrs = attrs, body = body }
end

return M
