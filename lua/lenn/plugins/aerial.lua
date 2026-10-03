return {
  {
    "stevearc/aerial.nvim",
    cmd = { "AerialToggle", "AerialOpen" },
    keys = {
      { "<leader>lo", "<cmd>AerialToggle<cr>", desc = "Outline" },
    },
    opts = {
      layout = {
        default_direction = "prefer_right",
        min_width = 20,
      },
    },
  },
}