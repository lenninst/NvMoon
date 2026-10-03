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
        "<leader>dr",
        function() require("dap").continue() end,
        desc = "Debug: run / continue",
      },
      {
        "<leader>ds",
        function() require("dap").step_over() end,
        desc = "Debug: step over",
      },
      {
        "<leader>di",
        function() require("dap").step_into() end,
        desc = "Debug: step into",
      },
      {
        "<leader>do",
        function() require("dap").step_out() end,
        desc = "Debug: step out",
      },
      {
        "<leader>dt",
        function() require("dap").terminate() end,
        desc = "Debug: terminate",
      },
      {
        "<F5>",
        function() require("dap").continue() end,
        desc = "Debug: run / continue",
      },
      {
        "<leader>db",
        function() require("dap").toggle_breakpoint() end,
        desc = "Debug: toggle breakpoint",
      },
      {
        "<leader>dv",
        function() require("dap-view").toggle() end,
        desc = "Debug: toggle view",
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
