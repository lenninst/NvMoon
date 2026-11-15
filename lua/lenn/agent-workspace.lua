-- Agent Workspace — Zed-style unified agent interface
-- Three panels on the left side:
--   | Threads+Skills | Agent | [code buffers] | Explorer |
-- Threads+Skills is a vertical split: Threads (top, 3/4) + Skills (bottom, 1/4)
-- Panels are created manually with vsplit/split, not via Edgy.
--
-- Usage: require("lenn.agent-workspace").toggle()

local M = {}

-- ─── State ──────────────────────────────────────────────────────────────────

local threads_buf = nil       -- threads list buffer (persisted across toggles)
local skills_buf = nil        -- skills list buffer (persisted across toggles)
local agent_buf = nil         -- agent selector buffer (persisted across toggles)
local current_term = nil      -- current toggleterm instance
local current_provider = nil  -- current provider name
local current_thread_id = nil -- current thread/session ID

-- Window IDs for our panels (so we can hide/show them on toggle)
local threads_win = nil
local skills_win = nil
local agent_win = nil

-- Panel sizes
local threads_width = 50
local agent_width = 60
local skills_height_ratio = 0.25  -- Skills occupies 25% of left panel height

-- Track whether panels are currently visible
local panels_visible = false

-- Provider definitions — loaded from agent-market dynamically
local market = require("lenn.agent-market")
local providers = market.get_providers()

-- Fallback: if market returns empty, use defaults
if #providers == 0 then
  providers = {
    { name = "OpenCode", cmd = "opencode", icon = "◼" },
    { name = "Junie", cmd = "junie", icon = "🟢" },
    { name = "Codex", cmd = "codex", icon = "⌘" },
    { name = "Claude Code", cmd = "claude", icon = "◆" },
    { name = "Kiro", cmd = "kiro-cli chat", icon = "⚡" },
  }
end

-- ─── Window Style Helper ────────────────────────────────────────────────────

-- Namespace IDs for highlights (lazy-initialized to avoid headless crash)
local threads_ns = nil
local skills_ns = nil

local function get_threads_ns()
  if threads_ns == nil then
    threads_ns = vim.api.nvim_create_namespace("_agent_threads_hl")
  end
  return threads_ns
end

local function get_skills_ns()
  if skills_ns == nil then
    skills_ns = vim.api.nvim_create_namespace("_agent_skills_hl")
  end
  return skills_ns
end

-- Custom highlight groups for Threads and Skills panels (use 0 for local scope)
local function setup_highlights()
  -- Mauve (Catppuccin Mauve: #cba6f7) for active thread
  vim.api.nvim_set_hl(0, "AgentActiveThread", { fg = "#cba6f7", bold = true })
  -- Green (Catppuccin Green: #a6e3a1) for enabled skills
  vim.api.nvim_set_hl(0, "AgentEnabledSkill", { fg = "#a6e3a1", bold = true })
  -- Disabled skill icon (subtle gray)
  vim.api.nvim_set_hl(0, "AgentDisabledSkill", { fg = "#6c7086" })
end

-- Apply neo-tree-like visual style to a window: transparent background,
-- full-width cursor line, no signcolumn/foldcolumn, relative numbers off.
local function apply_neo_tree_style(win)
  if not win or not vim.api.nvim_win_is_valid(win) then return end
  vim.wo[win].cursorline = true
  vim.wo[win].signcolumn = "no"
  vim.wo[win].foldcolumn = "0"
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].winfixwidth = true
  vim.wo[win].colorcolumn = ""
  vim.wo[win].winhighlight = "Normal:NeoTreeNormal,NormalNC:NeoTreeNormalNC,CursorLine:NeoTreeCursorLine"
end

setup_highlights()

-- ─── Threads Collection ─────────────────────────────────────────────────────

local function project_name(path)
  return vim.fn.fnamemodify(path or vim.fn.getcwd(), ":t")
end

local function collect_threads(cb)
  -- Collect threads from ALL projects, grouped by project directory.
  -- Each thread includes `cwd` so render_threads can group them.
  local all_threads = {}
  local completed = 0
  local total = 4 -- Codex, OpenCode, Kiro, Junie

  -- Codex threads (file-based, synchronous) — collect from ALL projects
  local function add_codex()
    local home = vim.env.CODEX_HOME or vim.fn.expand("~/.codex")
    local paths = vim.fn.globpath(home .. "/sessions", "**/rollout-*.jsonl", false, true)
    table.sort(paths, function(a, b)
      local sa = (vim.uv or vim.loop).fs_stat(a)
      local sb = (vim.uv or vim.loop).fs_stat(b)
      return (sa and sa.mtime.sec or 0) > (sb and sb.mtime.sec or 0)
    end)
    for _, path in ipairs(paths) do
      if #all_threads >= 100 then break end
      local read_ok, content = pcall(vim.fn.readfile, path, "", 1)
      if read_ok and content[1] then
        local ok, meta = pcall(vim.json.decode, content[1])
        if ok and type(meta) == "table" then
          local payload = meta.payload
          if payload and payload.id and payload.cwd then
            table.insert(all_threads, {
              provider = "Codex",
              icon = "⌘",
              id = payload.id,
              cwd = payload.cwd,
              title = string.format("%s · %s", project_name(payload.cwd), payload.id:sub(-8)),
            })
          end
        end
      end
    end
    completed = completed + 1
    if completed == total then cb(all_threads) end
  end

  -- OpenCode threads (async via jobstart) — collect from ALL projects
  local opencode_data = {}
  vim.fn.jobstart({ "opencode", "session", "list", "--max-count", "100", "--format", "json" }, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      opencode_data = vim.list_extend(opencode_data, data or {})
    end,
    on_exit = function(_, code)
      vim.schedule(function()
        if code == 0 and #opencode_data > 0 then
          local json_str = table.concat(opencode_data, "\n")
          local ok, sessions = pcall(vim.json.decode, json_str)
          if ok and type(sessions) == "table" then
            for _, s in ipairs(sessions) do
              local dir = s.directory or (s.location and s.location.directory) or ""
              if dir ~= "" and s.id then
                table.insert(all_threads, {
                  provider = "OpenCode",
                  icon = "◼",
                  id = s.id,
                  cwd = dir,
                  title = s.title or s.id,
                })
              end
            end
          end
        end
        completed = completed + 1
        if completed == total then cb(all_threads) end
      end)
    end,
  })

  -- Kiro threads (async via jobstart) — collect from ALL projects
  local kiro_data = {}
  vim.fn.jobstart({ "kiro-cli", "chat", "--list-sessions", "--format", "json" }, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      kiro_data = vim.list_extend(kiro_data, data or {})
    end,
    on_exit = function(_, code)
      vim.schedule(function()
        if code == 0 and #kiro_data > 0 then
          local json_str = table.concat(kiro_data, "\n")
          local ok, cwds = pcall(vim.json.decode, json_str)
          if ok and type(cwds) == "table" then
            for _, envelope in ipairs(cwds) do
              if type(envelope.sessions) == "table" then
                local dir = envelope.cwd or ""
                for _, s in ipairs(envelope.sessions) do
                  if s.sessionId and dir ~= "" then
                    table.insert(all_threads, {
                      provider = "Kiro",
                      icon = "⚡",
                      id = s.sessionId,
                      cwd = dir,
                      title = s.title or s.sessionId,
                    })
                  end
                end
              end
            end
          end
        end
        completed = completed + 1
        if completed == total then cb(all_threads) end
      end)
    end,
  })

  -- Junie threads (file-based, synchronous) — collect from ALL projects
  local function add_junie()
    local home = vim.env.JUNIE_HOME or vim.fn.expand("~/.junie")
    local index_file = home .. "/sessions/index.jsonl"
    local stat = (vim.uv or vim.loop).fs_stat(index_file)
    if stat then
      local read_ok, lines = pcall(vim.fn.readfile, index_file)
      if read_ok then
        for _, line in ipairs(lines) do
          if #all_threads >= 100 then break end
          if type(line) == "string" and line:len() > 0 then
            local ok, meta = pcall(vim.json.decode, line)
            if ok and type(meta) == "table" then
              local sessionId = meta.sessionId
              local projectDir = meta.projectDir or ""
              local taskName = meta.taskName or sessionId
              if sessionId and projectDir ~= "" then
                table.insert(all_threads, {
                  provider = "Junie",
                  icon = "🟢",
                  id = sessionId,
                  cwd = projectDir,
                  title = taskName,
                })
              end
            end
          end
        end
      end
    end
    completed = completed + 1
    if completed == total then cb(all_threads) end
  end

  -- Codex is synchronous, run it immediately
  add_codex()
  -- Junie is also synchronous
  add_junie()
end

-- ─── Threads Panel ──────────────────────────────────────────────────────────

-- Maps screen row numbers (1-based) to thread indices for open_thread().
-- Header lines and project separator lines are skipped.
local thread_row_map = {}

-- ─── Skills Panel ──────────────────────────────────────────────────────────

-- Maps screen row numbers to skill indices for toggle_skill_in_skills_buf().
local skills_row_map = {}

local function render_threads(threads)
  if not threads_buf or not vim.api.nvim_buf_is_valid(threads_buf) then return end

  -- Group threads by project directory
  local projects = {}      -- { cwd, name, threads = {} }
  local project_order = {} -- preserve insertion order
  local project_map = {}   -- cwd -> project object

  for _, t in ipairs(threads) do
    local cwd = t.cwd or ""
    if not project_map[cwd] then
      local proj = {
        cwd = cwd,
        name = project_name(cwd),
        threads = {},
      }
      project_map[cwd] = proj
      table.insert(project_order, proj)
    end
    table.insert(project_map[cwd].threads, t)
  end

  -- Sort projects: current project first, then alphabetically
  local cwd = vim.fn.getcwd()
  table.sort(project_order, function(a, b)
    local a_is_current = (a.cwd == cwd)
    local b_is_current = (b.cwd == cwd)
    if a_is_current and not b_is_current then return true end
    if not a_is_current and b_is_current then return false end
    return a.name < b.name
  end)

  -- Sort threads within each project by most recent first (already sorted by collector)

  local lines = {
    "╭─ Threads ──────────────────────╮",
    "│ <CR> open  ·  r refresh        │",
    "│ <C-n> new session              │",
    "╰────────────────────────────────╯",
    "",
  }

  -- Reset row map
  thread_row_map = {}

  if #project_order == 0 then
    table.insert(lines, "  No threads found")
    table.insert(lines, "")
    table.insert(lines, "  Press <C-n> to start a new session")
  else
    local thread_idx = 0
    for _, proj in ipairs(project_order) do
      -- Project header
      local current_marker = (proj.cwd == cwd) and "▸ " or "  "
      local header = string.format("%s── %s ──", current_marker, proj.name)
      table.insert(lines, header)
      -- No row map entry for header line

      for _, t in ipairs(proj.threads) do
        thread_idx = thread_idx + 1
        local marker = (t.id == current_thread_id) and "▸ " or "  "
        table.insert(lines, string.format("    %s%s %s", marker, t.icon, t.title))
        -- Map the current line number to thread_idx
        thread_row_map[#lines] = thread_idx
      end
      table.insert(lines, "") -- blank line between projects
    end
  end

  table.insert(lines, "")

  vim.bo[threads_buf].modifiable = true
  vim.api.nvim_buf_set_lines(threads_buf, 0, -1, false, lines)
  vim.bo[threads_buf].modifiable = false

  -- Highlight active thread lines in mauve
  if threads_buf and vim.api.nvim_buf_is_valid(threads_buf) then
    local ns = get_threads_ns()
    vim.api.nvim_buf_clear_namespace(threads_buf, ns, 0, -1)
    for row, idx in pairs(thread_row_map) do
      -- Find the thread by index
      local count = 0
      for _, proj in ipairs(project_order) do
        for _, t in ipairs(proj.threads) do
          count = count + 1
          if count == idx and t.id == current_thread_id then
            -- Use buf_add_highlight for the entire line (col 0 to -1)
            vim.api.nvim_buf_add_highlight(threads_buf, ns, "AgentActiveThread", row - 1, 0, -1)
            break
          end
        end
      end
    end
  end
end

-- ─── Skills Panel (separate buffer & window) ────────────────────────────────

local function render_skills()
  if not skills_buf or not vim.api.nvim_buf_is_valid(skills_buf) then return end

  local skills = require("lenn.agent-skills").get_skills()

  local lines = {
    "╭─ Skills ───────────────────────╮",
    "│ s toggle  ·  <CR> doc  ·  m market │",
    "╰────────────────────────────────╯",
    "",
  }

  -- Reset row map
  skills_row_map = {}

  if #skills == 0 then
    table.insert(lines, "  No skills installed")
  else
    for _, skill in ipairs(skills) do
      local status = skill.enabled and "✓" or "○"
      local desc_preview = ""
      if skill.description and skill.description:len() > 0 then
        local desc = skill.description:gsub("\n", " "):gsub("%s+", " "):gsub("^%s+", "")
        if desc:len() > 30 then
          desc = desc:sub(1, 27) .. "..."
        end
        desc_preview = " — " .. desc
      end
      local line = string.format("  [%s] %s%s", status, skill.name, desc_preview)
      table.insert(lines, line)
      skills_row_map[#lines] = skill
    end
  end

  table.insert(lines, "")

  vim.bo[skills_buf].modifiable = true
  vim.api.nvim_buf_set_lines(skills_buf, 0, -1, false, lines)
  vim.bo[skills_buf].modifiable = false

  -- Highlight enabled skill lines in green, disabled in gray
  local ns = get_skills_ns()
  vim.api.nvim_buf_clear_namespace(skills_buf, ns, 0, -1)
  for row, skill in pairs(skills_row_map) do
    local hl_group = skill.enabled and "AgentEnabledSkill" or "AgentDisabledSkill"
    vim.api.nvim_buf_add_highlight(skills_buf, ns, hl_group, row - 1, 0, -1)
  end
end

local function toggle_skill_in_skills_buf()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local skill = skills_row_map[row]
  if not skill then return end

  require("lenn.agent-skills").toggle(skill.name)
  render_skills()
  M.refresh_threads()
end

local function read_skill_doc_from_skills_buf()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local skill = skills_row_map[row]
  if not skill or not skill.path then return end

  vim.cmd("split " .. vim.fn.fnameescape(skill.path))
end

local function open_skill_market()
  require("lenn.skill-market").open()
end

function M.refresh_skills()
  render_skills()
end

-- Create the skills buffer (lazy, once)
function M.ensure_skills_buf()
  if skills_buf and vim.api.nvim_buf_is_valid(skills_buf) then
    return skills_buf
  end

  skills_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(skills_buf, "Agent Skills")
  vim.bo[skills_buf].buftype = "nofile"
  vim.bo[skills_buf].bufhidden = "hide"
  vim.bo[skills_buf].swapfile = false
  vim.bo[skills_buf].filetype = "agent-skills"

  vim.keymap.set("n", "s", toggle_skill_in_skills_buf, { buffer = skills_buf, desc = "Toggle skill" })
  vim.keymap.set("n", "<CR>", read_skill_doc_from_skills_buf, { buffer = skills_buf, desc = "Read skill doc" })
  vim.keymap.set("n", "m", open_skill_market, { buffer = skills_buf, desc = "Open Skill Market" })
  vim.keymap.set("n", "r", function() M.refresh_skills() end, { buffer = skills_buf, desc = "Refresh skills" })
  vim.keymap.set("n", "q", function() M.toggle_threads_only() end, { buffer = skills_buf, desc = "Close panels" })

  return skills_buf
end

local threads_data = {}


function M.refresh_threads()
  collect_threads(function(threads)
    threads_data = threads
    render_threads(threads)
  end)
  render_skills()
end

-- Create the threads buffer (lazy, once). Edgy will display it in its left edge.
function M.ensure_threads_buf()
  if threads_buf and vim.api.nvim_buf_is_valid(threads_buf) then
    return threads_buf
  end

  threads_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(threads_buf, "Agent Threads")
  vim.bo[threads_buf].buftype = "nofile"
  vim.bo[threads_buf].bufhidden = "hide"
  vim.bo[threads_buf].swapfile = false
  vim.bo[threads_buf].filetype = "agent-threads"

  vim.keymap.set("n", "<CR>", M.open_thread, { buffer = threads_buf, desc = "Open thread" })
  vim.keymap.set("n", "r", function() M.refresh_threads() end, { buffer = threads_buf, desc = "Refresh threads" })
  vim.keymap.set("n", "<C-n>", M.new_session, { buffer = threads_buf, desc = "New agent session" })
  vim.keymap.set("n", "q", function() M.toggle_threads_only() end, { buffer = threads_buf, desc = "Close Threads panel" })

  return threads_buf
end

function M.open_thread()
  local row = vim.api.nvim_win_get_cursor(0)[1]

  -- Use row map to find the thread index at this row
  local idx = thread_row_map[row]
  if not idx or idx < 1 or idx > #threads_data then return end

  local thread = threads_data[idx]
  current_thread_id = thread.id

  -- Change directory to the thread's project if different
  local changed_dir = false
  if thread.cwd and thread.cwd ~= vim.fn.getcwd() then
    vim.cmd("cd " .. vim.fn.fnameescape(thread.cwd))
    changed_dir = true
    -- Update NeoTree to the new directory
    local neo_tree_avail = pcall(require, "neo-tree")
    if neo_tree_avail then
      vim.api.nvim_command("Neotree " .. vim.fn.fnameescape(thread.cwd))
    end
  end

  -- Refresh threads display to update the current project marker
  render_threads(threads_data)

  -- Defer launching the provider so NeoTree and directory change complete first.
  -- NeoTree is async and can take a few ms to refresh; without this delay,
  -- launch_provider grabs focus before NeoTree finishes, making the explorer
  -- appear stale most of the time.
  vim.schedule(function()
    if changed_dir then
      -- Give NeoTree one more cycle to finish its own scheduled updates
      vim.schedule(function()
        M.launch_provider(thread.provider, thread.id)
      end)
    else
      M.launch_provider(thread.provider, thread.id)
    end
  end)
end

-- ─── Agent Panel ────────────────────────────────────────────────────────────

-- Collect active toggleterm sessions for display
local function get_active_sessions()
  local sessions = {}
  local Terminal = require("toggleterm.terminal")
  for _, t in ipairs(Terminal.get_all(true)) do
    local name = t.display_name or "Agent"
    local provider = vim.b[t.bufnr] and vim.b[t.bufnr].agent_provider or "Unknown"
    local is_open = t:is_open()
    table.insert(sessions, {
      name = name,
      provider = provider,
      open = is_open,
      terminal = t,
    })
  end
  return sessions
end

local function render_agent_panel()
  if not agent_buf or not vim.api.nvim_buf_is_valid(agent_buf) then return end

  local lines = {
    "╭─ Agent ────────────────────────╮",
    "│ Provider: " .. (current_provider or "None") .. "              │",
    "│ <S-p> select provider          │",
    "│ <S-m> agent market             │",
    "│ <C-n> new session              │",
    "│ <C-r> refresh threads          │",
    "╰────────────────────────────────╯",
    "",
  }

  -- Show active sessions first
  local sessions = get_active_sessions()
  if #sessions > 0 then
    table.insert(lines, "Active sessions:")
    for i, s in ipairs(sessions) do
      local status_icon = s.open and "▶" or "○"
      local marker = (s.provider == current_provider) and "▸ " or "  "
      table.insert(lines, string.format("%s%s %s - %s", marker, status_icon, s.provider, s.name))
    end
    table.insert(lines, "")
  end

  if current_term then
    table.insert(lines, "  ── Active Terminal ──")
    table.insert(lines, "  Provider: " .. (current_provider or "Unknown"))
    if current_thread_id then
      table.insert(lines, "  Thread: " .. current_thread_id:sub(-12))
    end
    table.insert(lines, "  Press <C-\\> to exit terminal")
  else
    if #sessions == 0 then
      table.insert(lines, "")
      table.insert(lines, "  No active session")
      table.insert(lines, "  Press <S-p> to select a provider")
    end
  end

  table.insert(lines, "")
  table.insert(lines, "Available providers:")
  for _, p in ipairs(providers) do
    local active = (p.name == current_provider) and "▸ " or "  "
    table.insert(lines, string.format("%s%s %s", active, p.icon, p.name))
  end

  vim.bo[agent_buf].modifiable = true
  vim.api.nvim_buf_set_lines(agent_buf, 0, -1, false, lines)
  vim.bo[agent_buf].modifiable = false
end

-- Create the agent panel buffer (lazy, once). Edgy will display it in its left edge.
function M.ensure_agent_buf()
  if agent_buf and vim.api.nvim_buf_is_valid(agent_buf) then
    return agent_buf
  end

  agent_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(agent_buf, "Agent Panel")
  vim.bo[agent_buf].buftype = "nofile"
  vim.bo[agent_buf].bufhidden = "hide"
  vim.bo[agent_buf].swapfile = false
  vim.bo[agent_buf].filetype = "agent-panel"

  vim.keymap.set("n", "<CR>", M.toggle_session, { buffer = agent_buf, desc = "Toggle session" })
  vim.keymap.set("n", "<S-p>", M.select_provider, { buffer = agent_buf, desc = "Select provider" })
  vim.keymap.set("n", "<S-m>", M.open_market, { buffer = agent_buf, desc = "Open Agent Market" })
  vim.keymap.set("n", "<C-n>", M.new_session, { buffer = agent_buf, desc = "New session" })
  vim.keymap.set("n", "<C-r>", function() M.refresh_threads() end, { buffer = agent_buf, desc = "Refresh threads" })
  vim.keymap.set("n", "q", function() M.toggle() end, { buffer = agent_buf, desc = "Close panel" })

  render_agent_panel()
  return agent_buf
end

-- ─── Provider Selection ─────────────────────────────────────────────────────

function M.toggle_session()
  local sessions = get_active_sessions()
  if #sessions == 0 then
    M.new_session()
    return
  end

  vim.ui.select(sessions, {
    prompt = "Toggle session:",
    format_item = function(s)
      local status_icon = s.open and "▶" or "○"
      return string.format("%s %s - %s", status_icon, s.provider, s.name)
    end,
  }, function(session)
    if session then
      if session.open then
        session.terminal:close()
      else
        session.terminal:open()
      end
      current_provider = session.provider
      current_term = session.terminal
      render_agent_panel()
    end
  end)
end

function M.select_provider()
  vim.ui.select(providers, {
    prompt = "Select agent provider:",
    format_item = function(p)
      return string.format("%s %s", p.icon, p.name)
    end,
  }, function(provider)
    if provider then
      M.launch_provider(provider.name, nil)
    end
  end)
end

-- ─── Session Management ─────────────────────────────────────────────────────

function M.new_session()
  vim.ui.select(providers, {
    prompt = "New agent session:",
    format_item = function(p)
      return string.format("%s %s", p.icon, p.name)
    end,
  }, function(provider)
    if provider then
      M.launch_provider(provider.name, nil)
    end
  end)
end

-- Restore the agent panel buffer after closing a terminal
local function restore_agent_panel()
  if not agent_win or not vim.api.nvim_win_is_valid(agent_win) then return end
  -- Restore the agent panel buffer in the agent window
  local buf = M.ensure_agent_buf()
  vim.api.nvim_win_set_buf(agent_win, buf)
  current_term = nil
  render_agent_panel()
end

function M.launch_provider(provider_name, thread_id)
  current_provider = provider_name
  current_thread_id = thread_id

  local provider = nil
  for _, p in ipairs(providers) do
    if p.name == provider_name then
      provider = p
      break
    end
  end
  if not provider then return end

  -- Build command from the provider definition (supports dynamic providers from market)
  local cmd = provider.cmd or provider_name
  if thread_id then
    -- Try to append session resume to the command
    if provider_name == "OpenCode" then
      cmd = "opencode mini --session " .. thread_id
    elseif provider_name == "Junie" then
      cmd = "junie resume " .. thread_id
    elseif provider_name == "Codex" then
      cmd = "codex resume " .. thread_id
    elseif provider_name == "Kiro" then
      cmd = "kiro-cli chat --resume-id " .. thread_id
    elseif provider_name == "Claude Code" then
      cmd = "claude --resume"
    else
      -- Generic fallback: append thread_id to command
      cmd = cmd .. " " .. thread_id
    end
  end

  -- If we have an agent window open, launch the terminal IN that window
  if agent_win and vim.api.nvim_win_is_valid(agent_win) then
    -- Open the terminal directly in the agent window using vim.termopen
    vim.api.nvim_set_current_win(agent_win)
    local term_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(agent_win, term_buf)

    -- Run the command via the shell so it handles arguments correctly
    local shell = vim.o.shell or "bash"
    local shell_arg = vim.o.shellcmdflag or "-c"

    local job = vim.fn.termopen({ shell, shell_arg, cmd }, {
      cwd = vim.fn.getcwd(),
      on_exit = function()
        -- Restore agent panel when terminal exits
        vim.schedule(restore_agent_panel)
      end,
    })

    if not job then
      -- Fallback: restore panel if termopen fails
      restore_agent_panel()
      return
    end

    current_term = { bufnr = term_buf, job = job }
    vim.b[term_buf].agent_panel = true
    vim.b[term_buf].agent_provider = provider_name

    -- Keymaps for the terminal
    vim.keymap.set("t", "<C-\\>", function()
      -- Close terminal and restore agent panel
      if job then
        vim.api.nvim_chan_send(job, "\x04") -- Ctrl+D to exit
      end
    end, { buffer = term_buf, desc = "Exit terminal" })

    vim.keymap.set("t", "<C-n>", function()
      -- Close current terminal and start new session
      if job then
        vim.api.nvim_chan_send(job, "\x04")
      end
      vim.schedule(M.new_session)
    end, { buffer = term_buf, desc = "New session" })

    vim.api.nvim_set_current_win(agent_win)
    vim.cmd.startinsert()
    return
  end

  -- Fallback: use ToggleTerm if no agent window is open
  local display_name = provider_name .. (thread_id and " Thread" or " Session")
  local Terminal = require("toggleterm.terminal").Terminal

  -- Reuse existing terminal
  for _, t in ipairs(require("toggleterm.terminal").get_all(true)) do
    if t.display_name == display_name then
      current_term = t
      if not t:is_open() then t:open() end
      vim.api.nvim_set_current_win(t.window)
      render_agent_panel()
      return
    end
  end

  -- Create new terminal
  current_term = Terminal:new({
    display_name = display_name,
    cmd = cmd,
    direction = "vertical",
    size = math.max(40, math.floor(vim.o.columns * 0.35)),
    hidden = true,
    start_in_insert = true,
    close_on_exit = false,
  })

  current_term:open()
  vim.b[current_term.bufnr].agent_panel = true
  vim.b[current_term.bufnr].agent_provider = provider_name

  vim.keymap.set("t", "<C-n>", M.new_session, {
    buffer = current_term.bufnr,
    desc = "Agents: new session",
  })

  render_agent_panel()
end

-- ─── Public API ─────────────────────────────────────────────────────────────

-- Edgy calls these commands when opening pinned views.
-- They create the buffers in the current window.
-- Check if our panels are currently visible
local function is_open()
  return panels_visible
end

-- Hide our panels (preserves windows, buffers, and terminal jobs)
local function hide_panels()
  local hidden = false
  for _, win_id in ipairs({ threads_win, skills_win, agent_win }) do
    if win_id and vim.api.nvim_win_is_valid(win_id) then
      -- Use hide to keep the window and buffer alive but invisible
      pcall(vim.api.nvim_win_hide, win_id)
      hidden = true
    end
  end
  if hidden then
    panels_visible = false
  end
end

-- Check if we have hidden windows to restore
local function has_hidden_windows()
  if threads_win and vim.api.nvim_win_is_valid(threads_win) then
    return true
  end
  if skills_win and vim.api.nvim_win_is_valid(skills_win) then
    return true
  end
  if agent_win and vim.api.nvim_win_is_valid(agent_win) then
    return true
  end
  return false
end

-- Restore hidden panels or create new ones
local function open_panels()
  -- If already visible, just refresh
  if panels_visible then
    M.refresh()
    return
  end

  -- Try to restore hidden windows first
  if has_hidden_windows() then
    -- Restore threads window if hidden
    if threads_win and vim.api.nvim_win_is_valid(threads_win) then
      local buf_t = M.ensure_threads_buf()
      vim.api.nvim_win_set_buf(threads_win, buf_t)
      vim.api.nvim_win_set_width(threads_win, threads_width)
      apply_neo_tree_style(threads_win)
      M.refresh_threads()
    end

    -- Restore skills window if hidden
    if skills_win and vim.api.nvim_win_is_valid(skills_win) then
      local buf_s = M.ensure_skills_buf()
      vim.api.nvim_win_set_buf(skills_win, buf_s)
      vim.api.nvim_win_set_width(skills_win, threads_width)
      apply_neo_tree_style(skills_win)
      render_skills()
    end

    -- Restore agent window if hidden
    if agent_win and vim.api.nvim_win_is_valid(agent_win) then
      local buf_a = M.ensure_agent_buf()
      vim.api.nvim_win_set_buf(agent_win, buf_a)
      vim.api.nvim_win_set_width(agent_win, agent_width)
      vim.wo[agent_win].winfixwidth = true
      -- If there was a terminal active, it's already in the buffer
      render_agent_panel()
    end

    panels_visible = true
    return
  end

  -- Create new panels from scratch
  local orig_win = vim.api.nvim_get_current_win()
  local orig_buf = vim.api.nvim_win_get_buf(orig_win)

  -- Create Threads+Skills panel (leftmost vertical split)
  vim.cmd("leftabove vsplit")
  threads_win = vim.api.nvim_get_current_win()
  local buf_t = M.ensure_threads_buf()
  vim.api.nvim_win_set_buf(threads_win, buf_t)
  vim.api.nvim_win_set_width(threads_win, threads_width)
  apply_neo_tree_style(threads_win)

  -- Split horizontally to create Skills panel below Threads
  -- Use rightbelow so Skills appears BELOW Threads
  vim.cmd("rightbelow split")
  skills_win = vim.api.nvim_get_current_win()
  local buf_s = M.ensure_skills_buf()
  vim.api.nvim_win_set_buf(skills_win, buf_s)
  vim.api.nvim_win_set_width(skills_win, threads_width)
  apply_neo_tree_style(skills_win)

  -- Set heights: Skills gets 25%, Threads gets 75%
  local total_height = vim.o.lines
  local skills_height = math.max(6, math.floor(total_height * skills_height_ratio))
  vim.api.nvim_win_set_height(skills_win, skills_height)
  vim.api.nvim_win_set_height(threads_win, total_height - skills_height)

  M.refresh_threads()
  render_skills()

  -- Move back to original window and create Agent panel
  vim.api.nvim_set_current_win(orig_win)
  vim.cmd("leftabove vsplit")
  agent_win = vim.api.nvim_get_current_win()
  local buf_a = M.ensure_agent_buf()
  vim.api.nvim_win_set_buf(agent_win, buf_a)
  vim.api.nvim_win_set_width(agent_win, agent_width)

  -- Set winfixwidth on all panels
  vim.wo[agent_win].winfixwidth = true

  -- Move back to original buffer
  vim.api.nvim_set_current_win(orig_win)
  if not vim.api.nvim_win_is_valid(orig_win) then
    orig_win = vim.api.nvim_get_current_win()
  end
  vim.api.nvim_win_set_buf(orig_win, orig_buf)

  panels_visible = true
end

function M.open()
  open_panels()
end

function M.toggle()
  if is_open() then
    hide_panels()
  else
    open_panels()
  end
end

-- Toggle only the Threads+Skills panel independently
-- Uses close/create instead of hide/show to guarantee correct position
function M.toggle_threads_only()
  -- Check if threads window exists and is valid (visible)
  local threads_exists = threads_win and vim.api.nvim_win_is_valid(threads_win)

  if threads_exists then
    -- Close both threads and skills windows
    pcall(vim.api.nvim_win_close, threads_win, true)
    pcall(vim.api.nvim_win_close, skills_win, true)
    threads_win = nil
    skills_win = nil
  else
    -- Find the leftmost window to create the split from.
    -- We need the Threads panel to be the FIRST panel on the left,
    -- so we split from the leftmost non-floating window.
    local leftmost_win = nil
    local leftmost_col = 999999
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local config = vim.api.nvim_win_get_config(win)
      -- Skip floating windows
      if config.relative ~= "" then goto continue end
      local col = config.col or 0
      if col < leftmost_col then
        leftmost_col = col
        leftmost_win = win
      end
      ::continue::
    end

    local orig_win = vim.api.nvim_get_current_win()
    local orig_buf = vim.api.nvim_win_get_buf(orig_win)

    -- Focus the leftmost window and split from there
    if leftmost_win then
      vim.api.nvim_set_current_win(leftmost_win)
    end
    vim.cmd("leftabove vsplit")
    threads_win = vim.api.nvim_get_current_win()
    local buf_t = M.ensure_threads_buf()
    vim.api.nvim_win_set_buf(threads_win, buf_t)
    vim.api.nvim_win_set_width(threads_win, threads_width)
    apply_neo_tree_style(threads_win)

    -- Split horizontally to create Skills panel below Threads
    -- Use rightbelow so Skills appears BELOW Threads
    vim.cmd("rightbelow split")
    skills_win = vim.api.nvim_get_current_win()
    local buf_s = M.ensure_skills_buf()
    vim.api.nvim_win_set_buf(skills_win, buf_s)
    vim.api.nvim_win_set_width(skills_win, threads_width)
    apply_neo_tree_style(skills_win)

    -- Set heights: Skills gets 25%, Threads gets 75%
    local total_height = vim.o.lines
    local skills_height = math.max(6, math.floor(total_height * skills_height_ratio))
    vim.api.nvim_win_set_height(skills_win, skills_height)
    vim.api.nvim_win_set_height(threads_win, total_height - skills_height)

    M.refresh_threads()
    render_skills()

    -- Restore focus to original window/buffer
    vim.api.nvim_set_current_win(orig_win)
    if not vim.api.nvim_win_is_valid(orig_win) then
      orig_win = vim.api.nvim_get_current_win()
    end
    vim.api.nvim_win_set_buf(orig_win, orig_buf)
  end
end

function M._is_left_open()
  return is_open()
end

-- Create commands for Edgy compatibility (in case Edgy tries to call them)
local function setup_commands()
  vim.api.nvim_create_user_command("LagentThreads", function()
    local buf = M.ensure_threads_buf()
    M.refresh_threads()
    vim.api.nvim_win_set_buf(0, buf)
  end, { force = true, bang = false })

  vim.api.nvim_create_user_command("LagentPanel", function()
    local buf = M.ensure_agent_buf()
    vim.api.nvim_win_set_buf(0, buf)
  end, { force = true, bang = false })
end

setup_commands()

function M.refresh()
  M.refresh_threads()
  render_skills()
  render_agent_panel()
end

function M.get_threads_buf()
  return threads_buf
end

function M.get_threads_win()
  return threads_win
end

-- Open the Agent Market floating window
function M.open_market()
  market.open()
end

-- Open the Skill Market floating window
function M.open_skill_market()
  require("lenn.skill-market").open()
end

return M
