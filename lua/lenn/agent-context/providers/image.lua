-- Image provider: attach an image from the clipboard, the project, or a path.
-- Agent TUIs can't receive image bytes through the terminal, so the image is
-- passed as an absolute path the agent can open with its own file tools.
local nf = require("lenn.icons")

local M = {
  name = "Image",
  icon = nf.image,
  extensions = { "png", "jpg", "jpeg", "gif", "webp", "bmp", "svg" },
}

local function is_image(path)
  local ext = (path:match("%.([%w]+)$") or ""):lower()
  return vim.tbl_contains(M.extensions, ext)
end

local function clipboard_dir()
  local dir = vim.fn.stdpath("cache") .. "/agent-context/images"
  vim.fn.mkdir(dir, "p")
  return dir
end

-- Which image MIME type the clipboard holds, and the command to dump it.
local function clipboard_source()
  if vim.env.WAYLAND_DISPLAY and vim.fn.executable("wl-paste") == 1 then
    local res = vim.system({ "wl-paste", "--list-types" }, { text = true }):wait(2000)
    for mime in (res.stdout or ""):gmatch("[^\n]+") do
      if mime:match("^image/") then return mime, { "wl-paste", "--no-newline", "--type", mime } end
    end
  elseif vim.env.DISPLAY and vim.fn.executable("xclip") == 1 then
    local res = vim.system({ "xclip", "-selection", "clipboard", "-t", "TARGETS", "-o" }, { text = true }):wait(2000)
    for mime in (res.stdout or ""):gmatch("[^\n]+") do
      if mime:match("^image/") then return mime, { "xclip", "-selection", "clipboard", "-t", mime, "-o" } end
    end
  end
end

function M.save_clipboard()
  local mime, cmd = clipboard_source()
  if not mime then return nil, "clipboard has no image" end
  local ext = mime:match("^image/([%w]+)") or "png"
  if ext == "jpeg" then ext = "jpg" end
  local path = string.format("%s/clipboard-%s.%s", clipboard_dir(), os.date("%Y%m%d-%H%M%S"), ext)
  local res = vim.system(cmd):wait(5000)
  if res.code ~= 0 or not res.stdout or #res.stdout == 0 then return nil, "could not read clipboard" end
  local fd = io.open(path, "wb")
  if not fd then return nil, "cannot write " .. path end
  fd:write(res.stdout)
  fd:close()
  return path
end

function M.available() return true end

function M.make_item(path)
  path = vim.fs.normalize(vim.fn.fnamemodify(vim.fn.expand(path), ":p"))
  return {
    provider = "image",
    key = "image:" .. path,
    label = "@Image:" .. vim.fn.fnamemodify(path, ":t"),
    path = path,
  }
end

local function from_path(ctx, cb)
  vim.ui.input({ prompt = "Image path: ", default = vim.fn.expand("~/Pictures/"), completion = "file" }, function(input)
    if not input or vim.trim(input) == "" then return cb(nil) end
    local path = vim.fn.expand(vim.trim(input))
    if vim.fn.filereadable(path) ~= 1 then
      vim.notify("agent-context: not a readable file: " .. path, vim.log.levels.WARN)
      return cb(nil)
    end
    if not is_image(path) then
      vim.notify("agent-context: not an image: " .. path, vim.log.levels.WARN)
      return cb(nil)
    end
    cb(M.make_item(path))
  end)
end

local function from_project(ctx, cb)
  local chosen
  Snacks.picker.files({
    title = "Add context: project images",
    cwd = ctx.cwd,
    ft = M.extensions,
    confirm = function(picker, item)
      chosen = item
      picker:close()
    end,
    on_close = function()
      vim.schedule(function()
        if not chosen or not chosen.file then return cb(nil) end
        local file = chosen.file:match("^/") and chosen.file or ((chosen.cwd or ctx.cwd) .. "/" .. chosen.file)
        cb(M.make_item(file))
      end)
    end,
  })
end

function M.items(ctx, cb)
  local has_clip = clipboard_source() ~= nil
  local choices = {
    { id = "clipboard", label = "From clipboard" .. (has_clip and "" or "  (no image in clipboard)") },
    { id = "project", label = "From project files" },
    { id = "path", label = "From path…" },
  }
  vim.ui.select(choices, {
    prompt = "Attach image",
    format_item = function(c) return c.label end,
  }, function(choice)
    if not choice then return cb(nil) end
    if choice.id == "clipboard" then
      local path, err = M.save_clipboard()
      if not path then
        vim.notify("agent-context: " .. err, vim.log.levels.WARN)
        return cb(nil)
      end
      cb(M.make_item(path))
    elseif choice.id == "project" then
      if not rawget(_G, "Snacks") then return from_path(ctx, cb) end
      from_project(ctx, cb)
    else
      from_path(ctx, cb)
    end
  end)
end

function M.resolve(item)
  if vim.fn.filereadable(item.path) ~= 1 then return nil, "image not found: " .. item.path end
  local size = vim.fn.getfsize(item.path)
  return {
    tag = "image",
    attrs = { path = item.path, bytes = size },
    body = "Image file attached by the user. Open it from this path to view it: " .. item.path,
  }
end

return M
