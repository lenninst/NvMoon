return {
  {
    "NeogitOrg/neogit",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "sindrets/diffview.nvim",
      "nvim-telescope/telescope.nvim",
    },
    cmd = "Neogit",
    keys = {
      { "<leader>gg", "<cmd>Neogit<cr>",        desc = "Git: status" },
      { "<leader>gc", "<cmd>Neogit commit<cr>", desc = "Git: commit" },
      { "<leader>gp", "<cmd>Neogit push<cr>",   desc = "Git: push" },
      { "<leader>gl", "<cmd>Neogit pull<cr>",   desc = "Git: pull" },
    },
    opts = {
      integrations = {
        diffview = true,
      },
      kind = "tab",
    },
  },
}
