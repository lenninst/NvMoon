return {
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {
      preset = "modern",
      delay = 300,
      icons = {
        breadcrumb = "»",
        separator = "➜",
        group = "+",
      },
      win = {
        border = "rounded",
        padding = { 1, 2 },
      },
      layout = {
        width = { min = 20 },
        spacing = 3,
      },
      spec = {
        { "<leader>f", group = "Find" },
        { "<leader>h", group = "Git Hunk" },
        { "<leader>g", group = "NeoGit" },
        { "<leader>l", group = "LSP" },
        { "<leader>u", group = " Utils" }
      },
    },
    keys = {
      {
        "<leader>?",
        function()
          require("which-key").show({ global = false })
        end,
        desc = "Buffer local keymaps",
      },
    },
  },
}
