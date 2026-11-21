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

local function cycle_workspace_mode()
  require("lenn.agent-workspace").next_mode()
end

local function select_workspace_mode()
  require("lenn.agent-workspace").select_mode()
end

local function set_workspace_mode_agent()
  require("lenn.agent-workspace").set_mode("agent")
end

local function set_workspace_mode_edit()
  require("lenn.agent-workspace").set_mode("edit")
end

local function set_workspace_mode_full()
  require("lenn.agent-workspace").set_mode("full")
end

local function set_workspace_mode_plan()
  require("lenn.agent-workspace").set_mode("plan")
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
      -- Workspace modes (DaVinci Resolve-style)
      {
        "<leader>w",
        desc = "Workspace: menu",
      },
      {
        "<leader>w1",
        set_workspace_mode_agent,
        desc = "Workspace: 1-Agent mode",
      },
      {
        "<leader>w2",
        set_workspace_mode_edit,
        desc = "Workspace: 2-Edit mode",
      },
      {
        "<leader>w3",
        set_workspace_mode_full,
        desc = "Workspace: 3-Full mode",
      },
      {
        "<leader>w4",
        set_workspace_mode_plan,
        desc = "Workspace: 4-Plan mode",
      },
      {
        "<M-1>",
        set_workspace_mode_agent,
        mode = { "n", "t", "i" },
        desc = "Workspace: 1-Agent mode (works in any panel/terminal)",
      },
      {
        "<M-2>",
        set_workspace_mode_edit,
        mode = { "n", "t", "i" },
        desc = "Workspace: 2-Edit mode (works in any panel/terminal)",
      },
      {
        "<M-3>",
        set_workspace_mode_full,
        mode = { "n", "t", "i" },
        desc = "Workspace: 3-Full mode (works in any panel/terminal)",
      },
      {
        "<M-4>",
        set_workspace_mode_plan,
        mode = { "n", "t", "i" },
        desc = "Workspace: 4-Plan mode (works in any panel/terminal)",
      },
      {
        "<M-m>",
        function() require("lenn.agent-workspace").toggle_minimize() end,
        mode = { "n", "t", "i" },
        desc = "Window: minimize / restore (keeps its content)",
      },
      {
        "<leader>wm",
        function() require("lenn.agent-workspace").toggle_minimize() end,
        desc = "Workspace: minimize / restore window",
      },
      {
        "<leader>wM",
        function() require("lenn.agent-workspace").restore_all() end,
        desc = "Workspace: restore all minimized windows",
      },
      {
        "<leader>wr",
        function() require("lenn.agent-workspace").rebuild() end,
        desc = "Workspace: rebuild layout",
      },
      {
        "<leader>ww",
        cycle_workspace_mode,
        desc = "Workspace: cycle mode",
      },
      {
        "<leader>wws",
        select_workspace_mode,
        desc = "Workspace: select mode",
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
      options = {
        -- Edgebar width follows the agent workspace's responsive explorer width
        right = {
          size = function()
            return require("lenn.agent-workspace").explorer_width()
          end,
        },
      },
      left = {},
      right = {
        {
          title = "Explorer",
          ft = "neo-tree",
          -- Files / Buffers / Git share the same docked column (switched from lualine)
          filter = function(buf)
            local source = vim.b[buf].neo_tree_source
            return source == "filesystem" or source == "buffers" or source == "git_status"
          end,
          -- Same responsive width the agent workspace uses for its layout
          size = {
            width = function()
              return require("lenn.agent-workspace").explorer_width()
            end,
          },
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
