local function agent_panel_width()
  return math.max(18, math.min(42, math.floor(vim.o.columns * 0.3)))
end

local function threads_panel_height()
  return math.max(4, math.min(18, math.floor(vim.o.lines * 0.22)))
end

local function new_agent_session()
  require("lenn.agent-sessions").new()
end

local function open_opencode_session()
  require("lenn.agent-sessions").open("OpenCode", "opencode")
end

local function toggle_agent_view()
  local layout = require("edgy.config").layout.left
  if layout then
    for _, view in ipairs(layout.views) do
      if view.get_title() == "Agents" then
        for _, win in ipairs(view.wins) do
          if win:is_valid() and not win:is_pinned() then
            win:toggle()
            return true
          end
        end
      end
    end
  end
  new_agent_session()
end

local function show_agent_view(open)
  local layout = require("edgy.config").layout.left
  if layout then
    for _, view in ipairs(layout.views) do
      if view.get_title() == "Agents" then
        for _, win in ipairs(view.wins) do
          if win:is_valid() and not win:is_pinned() then
            if not win.visible then
              win:show(true)
            end
            vim.api.nvim_set_current_win(win.win)
            return
          end
        end
      end
    end
  end
  open()
end

local function send_to_opencode(keys)
  show_agent_view(open_opencode_session)
  local term
  for _, candidate in ipairs(require("toggleterm.terminal").get_all(true)) do
    if vim.b[candidate.bufnr].agent_provider == "OpenCode" then
      term = candidate
    end
  end
  vim.defer_fn(function()
    if term and term.job_id then
      term:send(keys)
    end
  end, 500)
end

return {
  {
    "folke/edgy.nvim",
    event = "VeryLazy",
    dependencies = { "akinsho/toggleterm.nvim" },
    keys = {
      {
        "<leader>ap",
        function()
          toggle_agent_view()
        end,
        desc = "Agents: toggle panel",
      },
      {
        "<leader>at",
        new_agent_session,
        desc = "Agents: new session",
      },
      {
        "<leader>al",
        function()
          require("edgy").toggle("bottom")
        end,
        desc = "Threads: toggle panel",
      },
      {
        "<leader>am",
        function()
          send_to_opencode("\24m")
        end,
        desc = "OpenCode: select model",
      },
      {
        "<leader>ar",
        function()
          send_to_opencode("\24l")
        end,
        desc = "OpenCode: switch thread",
      },
    },
    init = function()
      vim.opt.laststatus = 3
      vim.opt.splitkeep = "screen"

      local group = vim.api.nvim_create_augroup("NvMoonEdgyResize", { clear = true })
      vim.api.nvim_create_autocmd("VimResized", {
        group = group,
        callback = function()
          vim.schedule(function()
            local layout = package.loaded["edgy.layout"]
            if layout then
              layout.layout()
            end
          end)
        end,
      })
    end,
    opts = {
      animate = { enabled = false },
      options = {
        left = { size = agent_panel_width },
        bottom = { size = threads_panel_height },
      },
      left = {
        {
          title = "Agents",
          ft = "toggleterm",
          filter = function(buf)
            return vim.b[buf].agent_panel == true or vim.b[buf].agent_provider ~= nil
          end,
          size = { width = agent_panel_width },
          wo = { winfixwidth = false },
        },
      },
      right = {
        {
          title = "Explorer",
          ft = "neo-tree",
          filter = function(buf)
            return vim.b[buf].neo_tree_source == "filesystem"
          end,
          size = { width = 30 },
        },
      },
      bottom = {
        {
          title = "Threads",
          ft = "agent-threads",
          size = { height = threads_panel_height },
          pinned = true,
          open = function()
            require("lenn.agent-threads").open()
          end,
        },
      },
      wo = {
        -- Avoid drawing Edgy's winbar during embedded UI screen resizes.
        -- Neovim 0.12.6 can assert on an out-of-range grid row in this path.
        winbar = false,
        winfixwidth = false,
        signcolumn = "no",
        winhighlight = "WinBar:EdgyWinBar,Normal:EdgyNormal",
      },
      keys = {
        ["N"] = function()
          new_agent_session()
        end,
        ["q"] = function(win)
          win:close()
        end,
        ["<c-q>"] = function(win)
          win:hide()
        end,
        ["]w"] = function(win)
          win:next({ visible = true, focus = true })
        end,
        ["[w"] = function(win)
          win:prev({ visible = true, focus = true })
        end,
        ["<c-w>>"] = function(win)
          win:resize("width", 2)
        end,
        ["<c-w><lt>"] = function(win)
          win:resize("width", -2)
        end,
        ["<c-w>+"] = function(win)
          win:resize("height", 2)
        end,
        ["<c-w>-"] = function(win)
          win:resize("height", -2)
        end,
        ["Q"] = function(win)
          win.view.edgebar:close()
        end,
      },
    },
  },
}
