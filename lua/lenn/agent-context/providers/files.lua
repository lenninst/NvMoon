-- Files & Directories provider: Snacks picker over files and folders (fd).
local nf = require("lenn.icons")
local resolve = require("lenn.agent-context.resolve")

local M = {
  name = "Files & Directories",
  icon = nf.ui_folder,
}

function M.available()
  if not rawget(_G, "Snacks") then return false, "snacks.nvim not loaded" end
  return true
end

local function relpath(path, cwd)
  local rel = vim.fs.relpath and vim.fs.relpath(cwd, path)
  return rel or vim.fn.fnamemodify(path, ":~:.")
end

function M.make_item(path, ctx)
  path = vim.fs.normalize(vim.fn.fnamemodify(path, ":p")):gsub("/$", "")
  local is_dir = vim.fn.isdirectory(path) == 1
  local rel = relpath(path, ctx.cwd)
  return {
    provider = "files",
    kind = is_dir and "dir" or "file",
    path = path,
    rel = rel,
    key = "files:" .. path,
    label = "@" .. rel .. (is_dir and "/" or ""),
  }
end

function M.items(ctx, cb)
  local chosen
  local picker_opts = {
    title = "Add context: files & directories",
    cwd = ctx.cwd,
    confirm = function(picker, item)
      chosen = item
      picker:close()
    end,
    on_close = function()
      vim.schedule(function()
        if not chosen then return cb(nil) end
        local file = chosen.file
        if not file then return cb(nil) end
        if not file:match("^/") then file = (chosen.cwd or ctx.cwd) .. "/" .. file end
        cb(M.make_item(file, ctx))
      end)
    end,
  }
  -- fd can list directories as well; other finders only return files
  if vim.fn.executable("fd") == 1 then
    picker_opts.cmd = "fd"
    picker_opts.args = { "--type", "d" }
  end
  Snacks.picker.files(picker_opts)
end

local function dir_listing(path, limit)
  local entries = {}
  if vim.fn.executable("fd") == 1 then
    local res = vim.system({ "fd", "--type", "f", "--color", "never", "-E", ".git", ".", path }, { text = true }):wait()
    if res.code == 0 then
      for line in (res.stdout or ""):gmatch("[^\n]+") do entries[#entries + 1] = line end
    end
  else
    for name, type in vim.fs.dir(path, { depth = 4 }) do
      if type == "file" and not name:match("^%.git/") then entries[#entries + 1] = path .. "/" .. name end
    end
  end
  table.sort(entries)
  local total = #entries
  if total > limit then entries = vim.list_slice(entries, 1, limit) end
  for i, e in ipairs(entries) do entries[i] = relpath(e, path) end
  return entries, total
end

function M.resolve(item, ctx, limits)
  if item.kind == "dir" then
    if vim.fn.isdirectory(item.path) ~= 1 then return nil, "directory not found" end
    local entries, total = dir_listing(item.path, limits.dir_entries)
    local body = table.concat(entries, "\n")
    if total > #entries then body = body .. string.format("\n… %d more files", total - #entries) end
    return { tag = "directory", attrs = { path = item.rel, files = total }, body = body }
  end

  local body, info = resolve.read_file(item.path, limits)
  if not body then return nil, info end
  local attrs = { path = item.rel }
  if info.truncated then
    attrs.truncated = "true"
    attrs.lines = "1-" .. info.lines
  end
  return { tag = "file", attrs = attrs, body = body }
end

return M
