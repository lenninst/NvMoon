-- Read saved agent conversations as { role, text } messages.
-- One reader per provider; stores match the ones the thread collectors in
-- lenn.agent-workspace read from.
local M = {}

local MAX_MESSAGE_CHARS = 4000

local function home(env, default)
  return vim.env[env] or vim.fn.expand(default)
end

local function readlines(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  return ok and lines or nil
end

local function decode(line)
  local ok, obj = pcall(vim.json.decode, line, { luanil = { object = true, array = true } })
  return ok and type(obj) == "table" and obj or nil
end

local function text_parts(content, accepted)
  if type(content) == "string" then return content end
  if type(content) ~= "table" then return nil end
  local out = {}
  for _, part in ipairs(content) do
    if type(part) == "table" and accepted[part.type] and type(part.text) == "string" then
      out[#out + 1] = part.text
    end
  end
  return #out > 0 and table.concat(out, "\n") or nil
end

local function push(messages, role, text)
  if not text then return end
  text = vim.trim(text)
  if text == "" then return end
  messages[#messages + 1] = { role = role, text = text }
end

local readers = {}

-- Claude Code: ~/.claude/projects/<slug>/<id>.jsonl
function readers.claude(id)
  local path = vim.fn.glob(home("CLAUDE_CONFIG_DIR", "~/.claude") .. "/projects/*/" .. id .. ".jsonl", false, true)[1]
  local lines = path and readlines(path)
  if not lines then return nil, "transcript not found" end
  local messages = {}
  for _, line in ipairs(lines) do
    local e = decode(line)
    if e and (e.type == "user" or e.type == "assistant") and not e.isMeta and not e.isSidechain
      and type(e.message) == "table" then
      local text = text_parts(e.message.content, { text = true })
      -- skip slash-command / hook wrappers like <command-name>…
      if text and not (e.type == "user" and text:match("^%s*<")) then push(messages, e.type, text) end
    end
  end
  return messages
end

-- Codex: ~/.codex/sessions/**/rollout-*-<id>.jsonl
function readers.codex(id)
  local path = vim.fn.globpath(home("CODEX_HOME", "~/.codex") .. "/sessions", "**/rollout-*" .. id .. ".jsonl", false, true)[1]
  local lines = path and readlines(path)
  if not lines then return nil, "transcript not found" end
  local messages = {}
  for _, line in ipairs(lines) do
    local e = decode(line)
    local p = e and e.type == "response_item" and e.payload
    if p and p.type == "message" and (p.role == "user" or p.role == "assistant") then
      local text = text_parts(p.content, { input_text = true, output_text = true })
      -- environment/instructions blocks are injected as user messages
      if text and not (p.role == "user" and text:match("^%s*<")) then push(messages, p.role, text) end
    end
  end
  return messages
end

-- Kiro: ~/.kiro/sessions/*/<id>/messages.jsonl
function readers.kiro(id)
  local base = home("KIRO_HOME", "~/.kiro") .. "/sessions/*/"
  local path = vim.fn.glob(base .. id .. "/messages.jsonl", false, true)[1]
    or vim.fn.glob(base .. "sess_" .. id .. "/messages.jsonl", false, true)[1]
  local lines = path and readlines(path)
  if not lines then return nil, "transcript not found" end
  local messages = {}
  for _, line in ipairs(lines) do
    local e = decode(line)
    local p = e and e.payload
    if p and (p.type == "user" or p.type == "assistant") and type(p.content) == "string" then
      push(messages, p.type, p.content)
    end
  end
  return messages
end

-- Junie keeps a rendered transcript.md per session
function readers.junie(id)
  local path = home("JUNIE_HOME", "~/.junie") .. "/sessions/" .. id .. "/transcript.md"
  local lines = readlines(path)
  if not lines then return nil, "transcript not found" end
  return { { role = "transcript", text = table.concat(lines, "\n") } }
end

-- OpenCode: session_message rows in the sqlite store
function readers.opencode(id)
  if vim.fn.executable("sqlite3") ~= 1 then return nil, "sqlite3 not installed" end
  if not id:match("^[%w_%-]+$") then return nil, "invalid session id" end
  local db = home("XDG_DATA_HOME", "~/.local/share") .. "/opencode/opencode.db"
  local res = vim.system({ "sqlite3", "-readonly", "-json", db,
    "select type, data from session_message where session_id = '" .. id .. "' order by seq" }, { text = true }):wait(5000)
  if res.code ~= 0 then return nil, "could not read OpenCode store" end
  local rows = decode(res.stdout ~= "" and res.stdout or "[]") or {}
  local messages = {}
  for _, row in ipairs(rows) do
    local data = decode(row.data or "")
    if data and row.type == "user" then
      push(messages, "user", data.text)
    elseif data and row.type == "assistant" then
      push(messages, "assistant", text_parts(data.content, { text = true }))
    end
  end
  return messages
end

local provider_keys = {
  ["Claude Code"] = "claude",
  Codex = "codex",
  Kiro = "kiro",
  Junie = "junie",
  OpenCode = "opencode",
}

function M.supported(provider) return provider_keys[provider] ~= nil end

-- Returns messages | nil, err
function M.read(provider, id)
  local key = provider_keys[provider]
  if not key then return nil, "no transcript reader for " .. tostring(provider) end
  local ok, messages, err = pcall(readers[key], id)
  if not ok then return nil, tostring(messages) end
  return messages, err
end

-- Render the most recent messages that fit in max_bytes / max_messages.
-- Returns text, info = { total, included }
function M.render(messages, max_bytes, max_messages)
  local chunks, used = {}, 0
  local first = math.max(1, #messages - max_messages + 1)
  for i = #messages, first, -1 do
    local m = messages[i]
    local text = m.text
    if m.role == "transcript" then
      -- single rendered document (Junie): keep the most recent part
      if #text > max_bytes then
        local tail = text:sub(-max_bytes)
        text = "… (earlier transcript omitted)\n" .. (tail:match("\n(.*)") or tail)
      end
    elseif vim.fn.strchars(text) > MAX_MESSAGE_CHARS then
      text = vim.fn.strcharpart(text, 0, MAX_MESSAGE_CHARS) .. "\n… (message truncated)"
    end
    local label = m.role == "user" and "User" or m.role == "assistant" and "Assistant" or "Transcript"
    local chunk = "## " .. label .. "\n" .. text
    if used + #chunk > max_bytes then
      if #chunks == 0 then
        chunks[1] = require("lenn.agent-context.resolve").truncate(chunk, max_bytes)
      end
      break
    end
    table.insert(chunks, 1, chunk)
    used = used + #chunk + 2
  end
  return table.concat(chunks, "\n\n"), { total = #messages, included = #chunks }
end

return M
