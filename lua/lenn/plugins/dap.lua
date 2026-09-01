return {
  {
    "mfussenegger/nvim-dap",
    dependencies = {
      "nvim-neotest/nvim-nio",
      {
        "igorlfs/nvim-dap-view",
        opts = {},
      },
    },
    keys = {
      {
        "<F5>",
        function() require("dap").continue() end,
        desc = "Debug: Start/Continue",
      },
      {
        "<F1>",
        function() require("dap").step_into() end,
        desc = "Debug: Step Into",
      },
      {
        "<F2>",
        function() require("dap").step_over() end,
        desc = "Debug: Step Over",
      },
      {
        "<F3>",
        function() require("dap").step_out() end,
        desc = "Debug: Step Out",
      },
      {
        "<leader>db",
        function() require("dap").toggle_breakpoint() end,
        desc = "Debug: Toggle Breakpoint",
      },
      {
        "<leader>dv",
        function() require("dap-view").toggle() end,
        desc = "Debug: Toggle View",
      },
    },
    config = function()
      local dap = require("dap")

      -- Adapter para C#
      dap.adapters.netcoredbg = {
        type = "executable",
        command = vim.fn.exepath("netcoredbg"),
        args = { "--interpreter=vscode" },
      }

      dap.configurations.cs = {
        {
          type = "netcoredbg",
          name = "Launch - netcoredbg",
          request = "launch",
          program = function()
            return vim.fn.input(
              "Path to dll: ",
              vim.fn.getcwd() .. "/bin/Debug/",
              "file"
            )
          end,
        },
      }

      vim.fn.sign_define("DapBreakpoint", { text = "●", texthl = "DiagnosticError" })
      vim.fn.sign_define("DapStopped", { text = "▶", texthl = "DiagnosticWarn" })
    end,
  },
}
