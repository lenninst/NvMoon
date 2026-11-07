local M = {}

local buf
local entries = {}
local lines = {}

local function project_name(path)
  return vim.fn.fnamemodify(path or vim.fn.getcwd(), ":t")
end

local function codex_entries()
  local home = vim.env.CODEX_HOME or vim.fn.expand("~/.codex")
  local paths = vim.fn.globpath(home .. "/sessions", "**/rollout-*.jsonl", false, true)
  table.sort(paths, function(a, b)
    local sa = (vim.uv or vim.loop).fs_stat(a)
    local sb = (vim.uv or vim.loop).fs_stat(b)
    return (sa and sa.mtime.sec or 0) > (sb and sb.mtime.sec or 0)
  end)

  local result = {}
  local cwd = vim.fn.getcwd()
  for _, path in ipairs(paths) do
    if #result >= 50 then
      break
    end
    local read_ok, content = pcall(vim.fn.readfile, path, "", 1)
    local first = read_ok and content[1] or nil
    local ok, meta = pcall(vim.json.decode, first or "")
    local payload = ok and type(meta) == "table" and meta.payload or nil
    if payload and payload.id and payload.cwd == cwd then
      result[#result + 1] = {
        provider = "Codex",
        id = payload.id,
        title = string.format("%s · %s", project_name(payload.cwd), payload.id:sub(-8)),
      }
    end
  end
  return result
end

local function render()
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  lines = { "Threads · <CR> open · r refresh", "" }
  entries = entries or {}
  for _, entry in ipairs(entries) do
    lines[#lines + 1] = string.format("%s  %s", entry.provider, entry.title)
  end
  if #entries == 0 then
    lines[#lines + 1] = "No saved threads for this project"
  end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

local function refresh()
  entries = codex_entries()
  entries[#entries + 1] = {
    provider = "Claude Code",
    id = "picker",
    title = "Browse saved conversations",
  }
  render()

  local opencode_out = {}
  vim.fn.jobstart({ "opencode", "session", "list", "--max-count", "50", "--format", "json" }, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      opencode_out = data or {}
    end,
    on_exit = function(_, code)
      vim.schedule(function()
        if code == 0 then
          local ok, sessions = pcall(vim.json.decode, table.concat(opencode_out, "\n"))
          if ok and type(sessions) == "table" then
            for _, session in ipairs(sessions) do
              local directory = session.directory or (session.location and session.location.directory) or ""
              if directory == vim.fn.getcwd() and session.id then
                entries[#entries + 1] = {
                  provider = "OpenCode",
                  id = session.id,
                  title = session.title or session.id,
                }
              end
            end
          end
        end
        render()
      end)
    end,
  })

  local kiro_out = {}
  vim.fn.jobstart({ "kiro-cli", "chat", "--list-sessions", "--format", "json" }, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      kiro_out = data or {}
    end,
    on_exit = function(_, code)
      vim.schedule(function()
        if code == 0 then
          local ok, cwds = pcall(vim.json.decode, table.concat(kiro_out, "\n"))
          if ok and type(cwds) == "table" then
            local cwd = vim.fn.getcwd()
            for _, envelope in ipairs(cwds) do
              if envelope.cwd == cwd and type(envelope.sessions) == "table" then
                for _, session in ipairs(envelope.sessions) do
                  entries[#entries + 1] = {
                    provider = "Kiro",
                    id = session.sessionId,
                    title = session.title or session.sessionId,
                  }
                end
              end
            end
          end
        end
        render()
      end)
    end,
  })
end

local function open_entry()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local entry = entries[row - 2]
  if not entry then
    return
  end
  local Terminal = require("toggleterm.terminal").Terminal
  local display_name = entry.provider .. " Thread " .. entry.id
  local cmd
  if entry.provider == "OpenCode" then
    cmd = "opencode mini --session " .. entry.id
  elseif entry.provider == "Codex" then
    cmd = "codex resume " .. entry.id
  elseif entry.provider == "Kiro" then
    cmd = "kiro-cli chat --resume-id " .. entry.id
  else
    cmd = "claude --resume"
  end
  local term
  for _, candidate in ipairs(require("toggleterm.terminal").get_all(true)) do
    if candidate.display_name == display_name then
      term = candidate
      break
    end
  end
  term = term or Terminal:new({
    display_name = display_name,
    cmd = cmd,
    direction = "vertical",
    size = math.max(18, math.min(42, math.floor(vim.o.columns * 0.3))),
    hidden = true,
    start_in_insert = true,
    close_on_exit = false,
  })
  if not term.bufnr or not vim.api.nvim_buf_is_valid(term.bufnr) then
    term:spawn()
  end
  vim.b[term.bufnr].agent_provider = entry.provider
  vim.b[term.bufnr].agent_panel = true
  vim.keymap.set("t", "<C-n>", function()
    require("lenn.agent-sessions").new()
  end, { buffer = term.bufnr, desc = "Agents: new session" })
  require("edgy.layout").update()
  if term:is_open() then
    local win = require("edgy").get_win(term.window)
    if win then
      win:focus()
    else
      vim.api.nvim_set_current_win(term.window)
    end
  else
    term:open()
  end
end

function M.open()
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, "Agent Threads")
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "hide"
    vim.bo[buf].swapfile = false
    vim.bo[buf].filetype = "agent-threads"
    vim.keymap.set("n", "r", refresh, { buffer = buf, desc = "Threads: refresh" })
    vim.keymap.set("n", "<CR>", open_entry, { buffer = buf, desc = "Threads: open" })
    vim.keymap.set("n", "q", function()
      require("edgy").close("bottom")
    end, { buffer = buf, desc = "Threads: hide panel" })
  end
  vim.cmd("botright 12split")
  vim.api.nvim_win_set_buf(0, buf)
  refresh()
end

return M
