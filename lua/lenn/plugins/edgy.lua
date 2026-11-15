-- Edgy layout — only handles the file explorer on the right.
-- Agent panels (Threads + Agent) are created manually by agent-workspace.lua
-- using vertical splits on the left side.

local M = {}

local function toggle_workspace()
  -- Toggle agent panels (Threads + Agent) via agent-workspace
  require("lenn.agent-workspace").toggle()
end

local function toggle_threads()
  -- Toggle only the Threads panel independently using agent-workspace
  local agent_ws = require("lenn.agent-workspace")
  agent_ws.toggle_threads_only()
end

local function new_session()
  require("lenn.agent-workspace").new_session()
end

local function refresh_threads()
  require("lenn.agent-workspace").refresh()
end

local function open_market()
  require("lenn.agent-workspace").open_market()
end

local function open_skill_market()
  require("lenn.agent-workspace").open_skill_market()
end

return {
  {
    "folke/edgy.nvim",
    event = "VeryLazy",
    dependencies = { "akinsho/toggleterm.nvim" },
    keys = {
      {
        "<leader>ap",
        toggle_workspace,
        desc = "Agents: toggle workspace",
      },
      {
        "<leader>al",
        toggle_threads,
        desc = "Agents: toggle threads only",
      },
      {
        "<leader>at",
        new_session,
        desc = "Agents: new session",
      },
      {
        "<leader>ar",
        refresh_threads,
        desc = "Agents: refresh threads",
      },
      {
        "<leader>am",
        open_market,
        desc = "Agents: open market",
      },
      {
        "<leader>asm",
        open_skill_market,
        desc = "Agents: open skill market",
      },
      {
        "<leader>ae",
        function()
          require("edgy").toggle("right")
        end,
        desc = "Explorer: toggle",
      },
    },
    init = function()
      vim.opt.laststatus = 3
      vim.opt.splitkeep = "screen"

      -- Pre-load agent-workspace so commands exist
      require("lenn.agent-workspace")
    end,
    opts = {
      animate = { enabled = false },
      options = {},
      left = {},
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
      wo = {
        winbar = false,
        winfixwidth = true,
        winfixheight = true,
        signcolumn = "no",
        winhighlight = "WinBar:EdgyWinBar,Normal:EdgyNormal",
      },
      keys = {
        ["<C-n>"] = function()
          new_session()
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
        ["Q"] = function(win)
          win.view.edgebar:close()
        end,
      },
    },
  },
}
