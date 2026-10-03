return {
  {
    "coffebar/neovim-project",
    lazy = false,
    priority = 999,
    dependencies = {
      "nvim-lua/plenary.nvim",
      "folke/snacks.nvim",
      "Shatur/neovim-session-manager",
    },
    opts = {
      projects = {
        "~/dev/*",
        "~/*",
      },
      discovery = {
        enabled = true,
        patterns = { ".git", ".hg", ".svn", "package.json", "go.mod", "Cargo.toml", "pyproject.toml", ".project" },
      },
      picker = {
        type = "snacks",
      },
      auto_load = false,
    },
    keys = {
      { "<leader>p",  "<cmd>NeovimProjectDiscover<cr>", desc = "Projects: recent" },
      { "<leader>po", "<cmd>NeovimProjectDiscover<cr>", desc = "Projects: open project" },
      { "<leader>pr", "<cmd>NeovimProjectHistory<cr>",  desc = "Projects: history" },
    },
  },
}
