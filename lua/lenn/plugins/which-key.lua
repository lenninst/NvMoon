return {
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    keys = {
      {
        "<leader>?",
        function()
          require("which-key").show({ global = false })
        end,
        desc = "Which Key: all mappings",
      },
    },
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
        { "<leader>a", group = "AI" },
        { "<leader>b", group = "Buffers" },
        { "<leader>c", group = "Codex" },
        { "<leader>d", group = "Debug" },
        { "<leader>e", group = "Explorer" },
        { "<leader>f", group = "Search" },
        { "<leader>h", group = "Hunk / Harpoon" },
        { "<leader>l", group = "LSP" },
        { "<leader>p", group = "Projects" },
        { "<leader>r", group = "Remote (Distant)" },
        { "<leader>t", group = "Terminal" },
        { "<leader>u", group = "UI" },
        { "<leader>x", group = "Trouble" },
      },
    },
  },
}
