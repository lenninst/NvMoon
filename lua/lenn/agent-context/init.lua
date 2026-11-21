-- Agent context picker, inspired by Zed's "add context" popover.
--
-- <C-a> inside an agent terminal opens a compose float. Typing "@" there (or
-- <C-a> again) opens the category popover; the chosen item is inserted as a
-- mention and resolved into the prompt when sending with <C-s>.
--
-- Usage: require("lenn.agent-context").setup({ open_key = "<C-a>" })
--
-- Providers live in lua/lenn/agent-context/providers/<id>.lua and expose:
--   name, icon            display data
--   available(ctx)        -> boolean, reason?
--   items(ctx, cb)        pick an item (may open UI); cb(item) or cb(nil)
--   resolve(item, ctx, limits) -> { tag, attrs, body } | nil, err
local M = {}
local nf = require("lenn.icons")

M.config = {
  open_key = "<C-a>",      -- terminal mode, agent buffers: open compose
  popover_key = "<C-a>",   -- inside compose (insert/normal): open popover
  trigger = "@",           -- inside compose (insert): open popover after whitespace
  send_key = "<C-s>",
  bracketed_paste = true,  -- boolean, or { ["Provider Name"] = false, default = true }
  limits = {
    file_bytes = 64 * 1024,
    file_lines = 1500,
    dir_entries = 200,
    diff_bytes = 100 * 1024,
    thread_bytes = 48 * 1024,  -- most recent messages of an attached thread
    thread_messages = 30,
    total_bytes = 200 * 1024,
  },
  symbols = {
    project_only = true,  -- hide workspace symbols outside the project (e.g. LSP libraries)
  },
}

-- Popover order. Categories whose provider module does not exist yet are
-- shown dimmed, so adding one is just dropping a file in providers/.
M.categories = {
  { id = "files", name = "Files & Directories", icon = nf.ui_folder },
  { id = "symbols", name = "Symbols", icon = nf.lualine_outline },
  { id = "threads", name = "Threads", icon = nf.thread },
  { id = "image", name = "Image", icon = nf.image },
  { id = "selection", name = "Selection", icon = nf.selection },
  { id = "branch_diff", name = "Branch Diff", icon = nf.explorer_git },
}

-- Returns provider, err. Only successful loads are cached by require(), so a
-- provider added or fixed while Neovim is running is picked up on next use.
-- err is "missing" when the module doesn't exist, or the load error message.
local load_errors = {}

function M.provider(id)
  local name = "lenn.agent-context.providers." .. id
  local ok, mod = pcall(require, name)
  if ok then
    load_errors[id] = nil
    return mod
  end
  if tostring(mod):find("module '" .. name:gsub("%-", "%%-") .. "' not found", 1) then
    return nil, "missing"
  end
  if load_errors[id] ~= tostring(mod) then
    load_errors[id] = tostring(mod)
    vim.notify("agent-context: provider " .. id .. " failed to load:\n" .. tostring(mod), vim.log.levels.ERROR)
  end
  return nil, "load error (see :messages)"
end

local function setup_highlights()
  vim.api.nvim_set_hl(0, "AgentContextMention", { link = "Special", default = true })
  vim.api.nvim_set_hl(0, "AgentContextDim", { link = "Comment", default = true })
  vim.api.nvim_set_hl(0, "AgentContextSel", { link = "PmenuSel", default = true })
  vim.api.nvim_set_hl(0, "AgentContextKey", { link = "Number", default = true })
end

-- Agent terminals are created in several places (direct termopen, explorer
-- window, toggleterm); all of them tag the buffer with b:agent_panel, so a
-- single autocmd installs the keymap regardless of which path ran.
local function install_terminal_map(buf)
  if vim.bo[buf].buftype ~= "terminal" or not vim.b[buf].agent_panel then return end
  if vim.b[buf].agent_context_maps then return end
  vim.b[buf].agent_context_maps = true
  vim.keymap.set("t", M.config.open_key, function() require("lenn.agent-context.compose").open() end,
    { buffer = buf, desc = "Agent: compose with context", nowait = true })
  vim.keymap.set("n", M.config.open_key, function() require("lenn.agent-context.compose").open() end,
    { buffer = buf, desc = "Agent: compose with context", nowait = true })
end

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  setup_highlights()

  local group = vim.api.nvim_create_augroup("LennAgentContext", { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = setup_highlights })
  vim.api.nvim_create_autocmd({ "TermOpen", "TermEnter", "BufEnter" }, {
    group = group,
    callback = function(args) install_terminal_map(args.buf) end,
  })
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do install_terminal_map(buf) end

  -- Providers may track editor state (e.g. the last visual selection)
  for _, cat in ipairs(M.categories) do
    local provider = M.provider(cat.id)
    if provider and provider.setup then provider.setup(group) end
  end

  -- :'<,'>LagentCompose opens the compose with the selection already mentioned
  vim.api.nvim_create_user_command("LagentCompose", function(args)
    local mentions = {}
    if args.range > 0 then
      local selection = M.provider("selection")
      local sel = selection and selection.capture()
      if sel then mentions[1] = selection.make_item(sel) end
    end
    require("lenn.agent-context.compose").open({ mentions = mentions })
  end, { force = true, range = true, desc = "Compose a prompt with context for the active agent" })
end

return M
