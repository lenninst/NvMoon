-- Agent Market — Mason-style UI for discovering and managing AI agents
-- Inspired by mason.nvim's package manager interface.
--
-- Usage: require("lenn.agent-market").open()

local M = {}

-- ─── Icons (Mason-style) ────────────────────────────────────────────────────
local icons = {
  installed = "◉",
  not_installed = "○",
  configured = "✓",
  package = "📦",
}

-- ─── Market Catalog ─────────────────────────────────────────────────────────
local MARKET_AGENTS = {
  -- ─── ACP Registry agents (Zed-compatible) ─────────────────────────────
  {
    name = "Claude Code",
    icon = "◆",
    description = "Agente de Anthropic, potente para refactorización y arquitectura.",
    cmd = "claude",
    install_cmd = "npm install -g @anthropic-ai/claude-code",
    update_cmd = "npm update -g @anthropic-ai/claude-code",
    url = "https://docs.anthropic.com/en/docs/agents/claude-code",
    check_cmd = "which claude",
  },
  {
    name = "Codex",
    icon = "⌘",
    description = "Agente de OpenAI para generación y explicación de código.",
    cmd = "codex",
    install_cmd = "npm install -g @openai/codex",
    update_cmd = "npm update -g @openai/codex",
    url = "https://github.com/openai/codex",
    check_cmd = "which codex",
  },
  {
    name = "Copilot",
    icon = "🐙",
    description = "Agente de GitHub Copilot para terminal y automatización.",
    cmd = "copilot",
    install_cmd = "npm install -g @github/copilot",
    update_cmd = "npm update -g @github/copilot",
    url = "https://github.com/features/copilot",
    check_cmd = "which copilot",
  },
  {
    name = "Cursor",
    icon = "🔮",
    description = "Agente de Cursor para terminal, soporta GPT-5 y Claude.",
    cmd = "cursor-agent",
    install_cmd = "curl -fsSL https://get.cursor.sh | bash",
    update_cmd = "cursor-agent update",
    url = "https://cursor.com/docs/cli/installation",
    check_cmd = "which cursor-agent",
  },
  {
    name = "Factory Droid",
    icon = "🤖",
    description = "Agente de Factory para terminal, desktop y cloud con BYOK.",
    cmd = "droid",
    install_cmd = "curl -fsSL https://get.factory.ai | sh",
    update_cmd = "npm update -g droid",
    url = "https://innfactory.ai",
    check_cmd = "which droid",
  },
  {
    name = "Gemini CLI",
    icon = "💎",
    description = "Agente de Google Gemini para desarrollo de software.",
    cmd = "gemini",
    install_cmd = "npm install -g @google/gemini-cli",
    update_cmd = "npm update -g @google/gemini-cli",
    url = "https://geminicli.com",
    check_cmd = "which gemini",
  },
  {
    name = "OpenCode",
    icon = "◼",
    description = "Agente de código open-source, rápido y ligero.",
    cmd = "opencode",
    install_cmd = "curl -fsSL https://opencode.ai/install.sh | sh",
    update_cmd = "opencode update",
    url = "https://opencode.ai",
    check_cmd = "which opencode",
  },
  {
    name = "Pi",
    icon = "π",
    description = "Agente open-source de Earendil Works con soporte multi-proveedor.",
    cmd = "pi",
    install_cmd = "npm install -g @earendil-works/pi-coding-agent",
    update_cmd = "pi update",
    url = "https://github.com/earendil-works/pi",
    check_cmd = "which pi",
  },
  {
    name = "Poolside",
    icon = "🏊",
    description = "Agente de Poolside con sandbox, MCP y ACP integrado.",
    cmd = "pool",
    install_cmd = "curl -fsSL https://downloads.poolside.ai/pool/install.sh | sh",
    update_cmd = "pool update",
    url = "https://docs.poolside.ai",
    check_cmd = "which pool",
  },
  -- ─── Popular CLI agents ───────────────────────────────────────────────
  {
    name = "Aider",
    icon = "🦾",
    description = "Editor de código con IA, soporta múltiples modelos.",
    cmd = "aider",
    install_cmd = "pip install aider-chat",
    update_cmd = "pip install --upgrade aider-chat",
    url = "https://aider.chat",
    check_cmd = "which aider",
  },
  {
    name = "Cline",
    icon = "⚙️",
    description = "Agente open-source con plugins, schedules y headless CI.",
    cmd = "cline",
    install_cmd = "npm install -g cline",
    update_cmd = "npm update -g cline",
    url = "https://cline.bot",
    check_cmd = "which cline",
  },
  {
    name = "Deep Agents",
    icon = "🧠",
    description = "Agente de LangChain con memoria persistente y búsqueda web.",
    cmd = "deepagents",
    install_cmd = "uv tool install deepagents-cli",
    update_cmd = "uv tool upgrade deepagents-cli",
    url = "https://www.langchain.com/blog/introducing-deepagents-cli",
    check_cmd = "which deepagents",
  },
  {
    name = "Kiro",
    icon = "⚡",
    description = "Agente de AWS para desarrollo con agentes personalizados.",
    cmd = "kiro-cli chat",
    install_cmd = "npm install -g @aws/kiro-cli",
    update_cmd = "npm update -g @aws/kiro-cli",
    url = "https://github.com/awslabs/kiro",
    check_cmd = "which kiro-cli",
  },
  {
    name = "Sweep",
    icon = "🧹",
    description = "Agente para implementar issues de GitHub automáticamente.",
    cmd = "sweep",
    install_cmd = "pip install sweep",
    update_cmd = "pip install --upgrade sweep",
    url = "https://sweep.dev",
    check_cmd = "which sweep",
  },
  -- ─── IDE-integrated agents (no standalone CLI) ────────────────────────
  {
    name = "Amazon Q",
    icon = "🔵",
    description = "Asistente de AWS para código, seguridad y operaciones.",
    cmd = "amazon-q",
    install_cmd = "Disponible como extensión IDE.",
    url = "https://aws.amazon.com/q/developer/",
    check_cmd = "which amazon-q",
  },
  {
    name = "Windsurf Cascade",
    icon = "🌊",
    description = "Agente de Codeium integrado en editor Windsurf.",
    cmd = "cascade",
    install_cmd = "Disponible desde Windsurf editor.",
    url = "https://windsurf.com",
    check_cmd = "which cascade",
  },
  -- ─── JetBrains ecosystem ──────────────────────────────────────────────
  {
    name = "Junie",
    icon = "🟢",
    description = "Asistente de JetBrains para desarrollo autónomo.",
    cmd = "junie",
    install_cmd = "Disponible en JetBrains Toolbox o IDEs.",
    url = "https://www.jetbrains.com/junie/",
    check_cmd = "which junie",
  },
}

-- ─── State ──────────────────────────────────────────────────────────────────
local installed_providers = {
  "OpenCode", "Junie", "Codex", "Claude Code", "Kiro",
}
local custom_providers = {}
local g_state = {} -- mutable state per window instance

local function is_installed(agent)
  local _ = vim.fn.system(agent.check_cmd)
  return vim.v.shell_error == 0
end

local function is_configured(agent_name)
  for _, p in ipairs(installed_providers) do
    if p == agent_name then return true end
  end
  for _, p in ipairs(custom_providers) do
    if p.name == agent_name then return true end
  end
  return false
end

-- ─── Helpers ────────────────────────────────────────────────────────────────

local function count_installed(agents)
  local count = 0
  for _, agent in ipairs(agents) do
    if is_configured(agent.name) then count = count + 1 end
  end
  for _, p in ipairs(custom_providers) do
    count = count + 1
  end
  return count
end

local function get_agent_at_line(agents, line_num)
  -- Mason-style layout: header lines + 1 line per agent
  -- Line 1: header bar
  -- Line 2: keymaps hint
  -- Line 3: blank
  -- Line 4+: agents (1 per line)
  local header_lines = 3
  local agent_index = line_num - header_lines
  if agent_index >= 1 and agent_index <= #agents then
    return agents[agent_index]
  end
  return nil
end

-- ─── Mason-style UI ─────────────────────────────────────────────────────────

function M.open()
  local width = 80
  local height = math.min(30, vim.o.lines - 8)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, "Agent Market")
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "agent-market"

  -- Build combined agent list (market + custom)
  local all_agents = vim.list_extend({}, MARKET_AGENTS)
  for _, custom in ipairs(custom_providers) do
    table.insert(all_agents, custom)
  end

  -- Store state for this window
  g_state.buf = buf
  g_state.agents = all_agents

  M.render(buf, all_agents)

  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " Agent Market ",
    title_pos = "center",
  })

  -- Mason-style keymaps
  vim.keymap.set("n", "<CR>", function()
    local line = vim.api.nvim_win_get_cursor(0)[1]
    local agent = get_agent_at_line(all_agents, line)
    if agent then M.toggle_agent(buf, all_agents, agent) end
  end, { buffer = buf, desc = "Install/Uninstall agent" })

  vim.keymap.set("n", "i", function()
    local line = vim.api.nvim_win_get_cursor(0)[1]
    local agent = get_agent_at_line(all_agents, line)
    if agent then M.install_agent(buf, all_agents, agent) end
  end, { buffer = buf, desc = "Install agent" })

  vim.keymap.set("n", "u", function()
    local line = vim.api.nvim_win_get_cursor(0)[1]
    local agent = get_agent_at_line(all_agents, line)
    if agent then M.update_agent(buf, all_agents, agent) end
  end, { buffer = buf, desc = "Update agent" })

  vim.keymap.set("n", "U", function()
    M.check_all_updates(buf, all_agents)
  end, { buffer = buf, desc = "Check all updates" })

  vim.keymap.set("n", "o", function()
    local line = vim.api.nvim_win_get_cursor(0)[1]
    local agent = get_agent_at_line(all_agents, line)
    if agent then M.open_url(agent.url) end
  end, { buffer = buf, desc = "Open URL" })

  vim.keymap.set("n", "R", function()
    M.render(buf, all_agents)
  end, { buffer = buf, desc = "Refresh" })

  vim.keymap.set("n", "?", function()
    M.show_help(buf, all_agents)
  end, { buffer = buf, desc = "Toggle help" })

  vim.keymap.set("n", "q", function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf, desc = "Close" })

  vim.keymap.set("n", "<Esc>", function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf, desc = "Close" })

  vim.keymap.set("n", "K", function()
    local line = vim.api.nvim_win_get_cursor(0)[1]
    local agent = get_agent_at_line(all_agents, line)
    if agent then
      vim.notify(agent.description, vim.log.levels.INFO, { title = agent.name })
    end
  end, { buffer = buf, desc = "Show info" })

  vim.api.nvim_set_current_win(win)
end

-- ─── Render (Mason-style) ───────────────────────────────────────────────────

function M.render(buf, agents)
  if not vim.api.nvim_buf_is_valid(buf) then return end

  local installed_count = count_installed(agents)
  local total = #agents

  -- Header bar (Mason-style)
  local header = string.format("Agent Market  (%d/%d installed)", installed_count, total)
  local header_padded = header .. string.rep(" ", math.max(0, 78 - #header))

  local keymaps_line = "<CR> toggle  ·  i install  ·  u update  ·  U check all  ·  o URL  ·  K info  ·  ? help  ·  q close"

  local lines = {
    header_padded,
    keymaps_line,
    "",
  }

  -- Sort: configured first, then alphabetically
  local configured_agents = {}
  local unconfigured_agents = {}
  for _, agent in ipairs(agents) do
    if is_configured(agent.name) then
      table.insert(configured_agents, agent)
    else
      table.insert(unconfigured_agents, agent)
    end
  end
  table.sort(configured_agents, function(a, b) return a.name < b.name end)
  table.sort(unconfigured_agents, function(a, b) return a.name < b.name end)

  local sorted = {}
  for _, a in ipairs(configured_agents) do table.insert(sorted, a) end
  for _, a in ipairs(unconfigured_agents) do table.insert(sorted, a) end

  g_state.sorted_agents = sorted

  for _, agent in ipairs(sorted) do
    local configured = is_configured(agent.name)
    local installed = is_installed(agent)

    local status_icon
    if configured and installed then
      status_icon = icons.installed
    elseif configured and not installed then
      status_icon = "◉" -- configured but not installed
    else
      status_icon = icons.not_installed
    end

    local name_display = agent.icon .. " " .. agent.name
    local line = string.format("  %s  %s", status_icon, name_display)
    table.insert(lines, line)
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  -- Apply Mason-style highlighting
  M.apply_highlights(buf, sorted)
end

function M.apply_highlights(buf, agents)
  -- Clear old highlights
  vim.api.nvim_buf_clear_namespace(buf, 0, 0, -1)

  -- Header line
  vim.api.nvim_buf_add_highlight(buf, 0, "Title", 0, 0, -1)
  -- Keymaps line
  vim.api.nvim_buf_add_highlight(buf, 0, "Comment", 1, 0, -1)

  -- Agent lines (start at line 3, index 0)
  local header_lines = 3
  for i, agent in ipairs(agents) do
    local line = header_lines + i - 1
    local configured = is_configured(agent.name)
    local installed = is_installed(agent)

    -- Status icon highlight
    if configured and installed then
      vim.api.nvim_buf_add_highlight(buf, 0, "DiagnosticInfo", line, 2, 3)
    elseif configured then
      vim.api.nvim_buf_add_highlight(buf, 0, "DiagnosticWarn", line, 2, 3)
    else
      vim.api.nvim_buf_add_highlight(buf, 0, "NonText", line, 2, 3)
    end

    -- Agent name highlight
    vim.api.nvim_buf_add_highlight(buf, 0, "Function", line, 5, 5 + #agent.icon + 1 + #agent.name)
  end
end

-- ─── Actions ────────────────────────────────────────────────────────────────

function M.toggle_agent(buf, agents, agent)
  if is_configured(agent.name) then
    for i, p in ipairs(installed_providers) do
      if p == agent.name then
        table.remove(installed_providers, i)
        break
      end
    end
    vim.notify("✗ " .. agent.name .. " removido del workspace", vim.log.levels.INFO, { title = "Agent Market" })
  else
    table.insert(installed_providers, agent.name)
    vim.notify("✓ " .. agent.name .. " agregado al workspace", vim.log.levels.INFO, { title = "Agent Market" })
  end
  M.render(buf, agents)
end

function M.install_agent(buf, agents, agent)
  if is_configured(agent.name) then
    vim.notify(agent.name .. " ya está configurado", vim.log.levels.WARN, { title = "Agent Market" })
    return
  end

  table.insert(installed_providers, agent.name)
  vim.notify("✓ " .. agent.name .. " configurado", vim.log.levels.INFO, { title = "Agent Market" })

  -- If not installed on system, open terminal for installation
  if not is_installed(agent) and agent.install_cmd and agent.install_cmd:sub(1, 3) ~= "Dis" then
    M.open_install_terminal(agent)
  end

  M.render(buf, agents)
end

function M.uninstall_agent(buf, agents, agent)
  if not is_configured(agent.name) then
    vim.notify(agent.name .. " no está configurado", vim.log.levels.WARN, { title = "Agent Market" })
    return
  end

  for i, p in ipairs(installed_providers) do
    if p == agent.name then
      table.remove(installed_providers, i)
      break
    end
  end
  vim.notify("✗ " .. agent.name .. " removido", vim.log.levels.INFO, { title = "Agent Market" })
  M.render(buf, agents)
end

-- Alias for backward compatibility
function M.check_updates(buf, agents)
  return M.check_all_updates(buf, agents)
end

function M.open_install_terminal(agent)
  vim.notify("Instalando " .. agent.name .. "...", vim.log.levels.INFO, { title = "Agent Market" })

  local term_buf = vim.api.nvim_create_buf(false, true)
  local width = 70
  local height = 12
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local win = vim.api.nvim_open_win(term_buf, true, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " Installing " .. agent.name .. " ",
  })

  local shell = vim.o.shell or "bash"
  local shell_arg = vim.o.shellcmdflag or "-c"

  vim.fn.termopen({ shell, shell_arg, agent.install_cmd }, {
    cwd = vim.fn.getcwd(),
    on_exit = function()
      vim.notify(agent.name .. " instalación completada", vim.log.levels.INFO, { title = "Agent Market" })
    end,
  })

  vim.keymap.set("t", "<C-q>", function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = term_buf, desc = "Close" })
end

function M.add_custom_agent(buf, agents)
  vim.ui.input({ prompt = "Comando del agente: " }, function(cmd)
    if not cmd or cmd == "" then return end
    vim.ui.input({ prompt = "Icono (emoji): ", default = "✦" }, function(icon)
      local custom = {
        name = cmd,
        icon = icon or "✦",
        cmd = cmd,
        description = "Agente personalizado",
        url = "",
        install_cmd = "",
        check_cmd = "which " .. cmd,
      }
      table.insert(custom_providers, custom)
      table.insert(installed_providers, custom.name)
      vim.notify("✓ " .. custom.name .. " agregado", vim.log.levels.INFO, { title = "Agent Market" })
      if buf and vim.api.nvim_buf_is_valid(buf) then
        -- Rebuild agents list
        local all = vim.list_extend({}, MARKET_AGENTS)
        for _, c in ipairs(custom_providers) do table.insert(all, c) end
        M.render(buf, all)
      end
    end)
  end)
end

function M.show_help(buf, agents)
  local help_lines = {
    "Agent Market — Help",
    "",
    "Keybindings:",
    "  <CR>        Toggle agent (add/remove from workspace)",
    "  i           Install agent under cursor",
    "  u           Update agent under cursor",
    "  U           Check all agents for updates",
    "  o           Open agent URL in browser",
    "  K           Show agent description",
    "  R           Refresh status",
    "  ?           Toggle this help",
    "  q           Close window",
    "",
    "Status icons:",
    "  ◉  Configured and installed",
    "  ○  Not configured",
    "",
    "Press any key to close",
  }

  vim.api.nvim_buf_set_keymap(buf, "n", "", "", {
    callback = function()
      vim.api.nvim_buf_del_keymap(buf, "n", "")
      M.render(buf, agents)
    end,
    once = true,
  })

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, help_lines)
  vim.bo[buf].modifiable = false
end

-- ─── Update functions ─────────────────────────────────────────────────

function M.update_agent(buf, agents, agent)
  if not is_installed(agent) then
    vim.notify(agent.name .. " no está instalado en el sistema", vim.log.levels.WARN, { title = "Agent Market" })
    return
  end

  if not agent.update_cmd then
    vim.notify(agent.name .. " no tiene comando de actualización definido", vim.log.levels.WARN, { title = "Agent Market" })
    return
  end

  vim.notify("Actualizando " .. agent.name .. "...", vim.log.levels.INFO, { title = "Agent Market" })

  local term_buf = vim.api.nvim_create_buf(false, true)
  local width = 70
  local height = 12
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local win = vim.api.nvim_open_win(term_buf, true, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " Updating " .. agent.name .. " ",
  })

  local shell = vim.o.shell or "bash"
  local shell_arg = vim.o.shellcmdflag or "-c"

  vim.fn.termopen({ shell, shell_arg, agent.update_cmd }, {
    cwd = vim.fn.getcwd(),
    on_exit = function()
      vim.notify(agent.name .. " actualización completada", vim.log.levels.INFO, { title = "Agent Market" })
      M.render(buf, agents)
    end,
  })

  vim.keymap.set("t", "<C-q>", function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = term_buf, desc = "Close" })
end

function M.check_all_updates(buf, agents)
  local configured = {}
  for _, agent in ipairs(agents) do
    if is_configured(agent.name) and is_installed(agent) and agent.update_cmd then
      table.insert(configured, agent)
    end
  end

  if #configured == 0 then
    vim.notify("No hay agentes configurados con comando de actualización", vim.log.levels.INFO, { title = "Agent Market" })
    return
  end

  vim.notify("Verificando actualizaciones para " .. #configured .. " agentes...", vim.log.levels.INFO, { title = "Agent Market" })

  local results = {}
  local checked = 0
  local total = #configured

  for _, agent in ipairs(configured) do
    -- Run version check asynchronously
    local cmd = agent.update_cmd
    -- Extract version check from update command (simplified)
    local version_cmd = agent.cmd .. " --version 2>&1 || " .. agent.cmd .. " version 2>&1 || echo unknown"
    local output = vim.fn.system(version_cmd)
    checked = checked + 1
    
    table.insert(results, string.format("  %s %s  (%s)", agent.icon, agent.name, output:gsub("\n", " "):gsub("%s+$", "")))
  end

  local msg = "Agentes configurados:\n" .. table.concat(results, "\n") .. "\n\nPresiona 'u' en un agente para actualizarlo."
  vim.notify(msg, vim.log.levels.INFO, { title = "Agent Market — Updates" })
end

function M.open_url(url)
  if not url or url == "" then return end
  if vim.fn.has("mac") == 1 then
    vim.fn.system(string.format("open %s", url))
  elseif vim.fn.has("linux") == 1 then
    vim.fn.system(string.format("xdg-open %s", url))
  else
    vim.fn.system(string.format("start %s", url))
  end
  vim.notify("Abriendo " .. url, vim.log.levels.INFO)
end

-- ─── Integration with agent-workspace ───────────────────────────────────────

function M.get_providers()
  local providers = {}
  for _, name in ipairs(installed_providers) do
    for _, agent in ipairs(MARKET_AGENTS) do
      if agent.name == name then
        table.insert(providers, {
          name = agent.name,
          cmd = agent.cmd,
          icon = agent.icon,
        })
        break
      end
    end
  end
  for _, custom in ipairs(custom_providers) do
    table.insert(providers, {
      name = custom.name,
      cmd = custom.cmd,
      icon = custom.icon or "✦",
    })
  end
  return providers
end

return M
