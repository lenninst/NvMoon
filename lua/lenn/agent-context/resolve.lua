-- Turns context mentions into a single <context> block with size limits.
local M = {}

-- Cut text to max_bytes at a line boundary. Returns text, truncated.
function M.truncate(text, max_bytes)
  if #text <= max_bytes then return text, false end
  local cut = text:sub(1, max_bytes)
  local last_nl = cut:match(".*()\n")
  if last_nl and last_nl > max_bytes / 2 then cut = cut:sub(1, last_nl - 1) end
  return cut, true
end

-- Read a text file honoring limits. Returns body, info | nil, err.
-- info = { truncated = bool, lines = n }
function M.read_file(path, limits)
  local fd = io.open(path, "rb")
  if not fd then return nil, "cannot read " .. path end
  local data = fd:read(limits.file_bytes + 1) or ""
  fd:close()
  if data:sub(1, 8192):find("\0", 1, true) then return nil, "binary file skipped" end

  local truncated = #data > limits.file_bytes
  data = M.truncate(data, limits.file_bytes)
  local lines = vim.split(data, "\n", { plain = true })
  if #lines > limits.file_lines then
    lines = vim.list_slice(lines, 1, limits.file_lines)
    truncated = true
  end
  return table.concat(lines, "\n"), { truncated = truncated, lines = #lines }
end

local function escape_attr(value)
  return (tostring(value):gsub("&", "&amp;"):gsub('"', "&quot;"):gsub("<", "&lt;"))
end

local function render_block(block)
  local attrs = {}
  local keys = vim.tbl_keys(block.attrs or {})
  table.sort(keys)
  for _, k in ipairs(keys) do attrs[#attrs + 1] = string.format('%s="%s"', k, escape_attr(block.attrs[k])) end
  local open = "<" .. block.tag .. (#attrs > 0 and (" " .. table.concat(attrs, " ")) or "") .. ">"
  return open .. "\n" .. (block.body or "") .. "\n</" .. block.tag .. ">"
end

-- entries: list of { item, provider }. Returns context string ("" if none) and warnings.
function M.resolve_all(entries, ctx, limits)
  local parts, warnings, used = {}, {}, 0
  for _, entry in ipairs(entries) do
    local ok, block, err = pcall(entry.provider.resolve, entry.item, ctx, limits)
    if not ok then
      block, err = nil, block
    end
    if not block then
      warnings[#warnings + 1] = entry.item.label .. ": " .. tostring(err or "could not resolve")
    else
      local remaining = limits.total_bytes - used
      if remaining <= 256 then
        warnings[#warnings + 1] = entry.item.label .. ": skipped, total context limit reached"
      else
        local body, cut = M.truncate(block.body or "", remaining - 256)
        if cut then
          block.attrs = block.attrs or {}
          block.attrs.truncated = "true"
          block.body = body
          warnings[#warnings + 1] = entry.item.label .. ": truncated to fit total context limit"
        end
        local rendered = render_block(block)
        used = used + #rendered
        parts[#parts + 1] = rendered
      end
    end
  end
  if #parts == 0 then return "", warnings end
  return "<context>\n" .. table.concat(parts, "\n\n") .. "\n</context>", warnings
end

return M
