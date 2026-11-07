local M = {}

local session_number = 0
local providers = {
  { name = "OpenCode", cmd = "opencode" },
  { name = "Codex", cmd = "codex" },
  { name = "Claude Code", cmd = "claude" },
  { name = "Kiro", cmd = "kiro-cli chat" },
}

function M.open(provider, cmd)
  session_number = session_number + 1
  local Terminal = require("toggleterm.terminal").Terminal
  local term = Terminal:new({
    display_name = string.format("Agent %s %d", provider, session_number),
    cmd = cmd,
    direction = "vertical",
    size = math.max(18, math.min(42, math.floor(vim.o.columns * 0.3))),
    hidden = true,
    start_in_insert = true,
    close_on_exit = false,
  })
  term:open()
  vim.b[term.bufnr].agent_panel = true
  vim.b[term.bufnr].agent_provider = provider
  vim.keymap.set("t", "<C-n>", M.new, { buffer = term.bufnr, desc = "Agents: new session" })
  require("edgy.layout").update()
  return term
end

function M.new()
  vim.ui.select(providers, {
    prompt = "New agent session:",
    format_item = function(provider)
      return provider.name
    end,
  }, function(provider)
    if provider then
      M.open(provider.name, provider.cmd)
    end
  end)
end

return M
