return {
  {
    "grddavies/tidal.nvim",
    lazy = false,
    dependencies = {
      "nvim-treesitter/nvim-treesitter",
    },
    config = function(_, opts)
      require("tidal").setup(opts)

      local function show_repl(name, split)
        local proc = require("tidal.core.state")[name]
        if not proc or not proc.buf or not proc.buf.bufnr then
          vim.notify(name == "ghci" and "Tidal is not running" or "SuperCollider is not running", vim.log.levels.WARN)
          return
        end
        proc.buf:show({ split = split })
      end

      vim.api.nvim_create_user_command("TidalNotification", function()
        show_repl("ghci", "v")
      end, { desc = "Show Tidal REPL output" })
      vim.api.nvim_create_user_command("SuperColliderNotification", function()
        show_repl("sclang", "h")
      end, { desc = "Show SuperCollider REPL output" })
    end,
    opts = {
      boot = {
        sclang = { enabled = true },
      },
      mappings = {
        send_line = { mode = { "i", "n" }, key = "<leader>1" },
        send_visual = { mode = { "x" }, key = "<leader>1" },
        send_block = { mode = { "i", "n", "x" }, key = "<M-CR>" },
        send_node = { mode = "n", key = "<leader><CR>" },
        send_silence = { mode = "n", key = "<leader>2" },
        send_hush = { mode = "n", key = "<leader><Esc>" },
      },
    },
  },
}
