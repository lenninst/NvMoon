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
      { "<leader>gg", "<cmd>Neogit<cr>",        desc = "Neogit status" },
      { "<leader>gc", "<cmd>Neogit commit<cr>", desc = "Neogit commit" },
      { "<leader>gp", "<cmd>Neogit push<cr>",   desc = "Neogit push" },
      { "<leader>gl", "<cmd>Neogit pull<cr>",   desc = "Neogit pull" },
    },
    opts = {
      integrations = {
        diffview = true,
      },
      kind = "tab",
    },
  },
}
