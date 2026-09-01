return {

  {
    "catppuccin/nvim",
    name = "catppuccin",
    priority = 1000,
    config = function()
      require("catppuccin").setup({
        flavour = "mocha",
      })
      vim.cmd.colorscheme("catppuccin-nvim")
    end,
  },

  {
    "nvim-lualine/lualine.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      require("lualine").setup({
        options = {
          theme = "auto",
          globalstatus = true,
          component_separators = { left = "", right = "" },
          section_separators = { left = "", right = "" },
        },

        sections = {

          lualine_a = {
            {
              "mode",
              fmt = function()
                return " "
              end,
              color = function()
                local mode_colors = {
                  n = { bg = "#89b4fa" },
                  i = { bg = "#94e2d5" },
                  v = { bg = "#cba6f7" },
                  V = { bg = "#f9e2af" },
                  [""] = { bg = "#f9e2af" },
                  c = { bg = "#f2cdcd" },
                  R = { bg = "#eba0ac" },
                  t = { bg = "#fab387" },
                }
                return mode_colors[vim.fn.mode()] or { fg = "#1e1e2e" }
              end,
            },
          },
          lualine_b = { "branch", "diff", "diagnostics" },
          lualine_c = { "" },
          lualine_x = { "fileformat", "filetype" },
          lualine_y = {
            {

              "location",
              padding = { left = 1, right = 1 },
            },
          },
          lualine_z = {
            {

              "progress",
              padding = { left = 1, right = 0 },
            },
            {
              function()
                return "/" .. vim.fn.line("$")
              end,
              padding = { left = 0, right = 1 },
            },
          },
        },
      })
    end,
  },
}
