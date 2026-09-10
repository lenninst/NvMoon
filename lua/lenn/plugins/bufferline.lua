return {
  {
    "akinsho/bufferline.nvim",
    version = "*",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    event = "VeryLazy",
    keys = {
      { "<S-l>",      "<cmd>BufferLineCycleNext<cr>",       desc = "Next buffer" },
      { "<S-h>",      "<cmd>BufferLineCyclePrev<cr>",       desc = "Prev buffer" },

      { "<leader>bb", "<cmd>BufferLineCyclePrev<cr>",       desc = "Previous" },
      { "<leader>bn", "<cmd>BufferLineCycleNext<cr>",       desc = "Next" },
      { "<leader>bD", "<cmd>BufferLineSortByDirectory<cr>", desc = "Sort by directory" },
      { "<leader>bL", "<cmd>BufferLineSortByExtension<cr>", desc = "Sort by language" },
      { "<leader>be", "<cmd>BufferLinePickClose<cr>",       desc = "Pick which buffer to close" },
      -- { "<leader>bf", "<cmd>BufferLinePick<cr>",            desc = "Find" },
      { "<leader>bj", "<cmd>BufferLinePick<cr>",            desc = "Jump" },
      { "<leader>bh", "<cmd>BufferLineCloseLeft<cr>",       desc = "Close all to the left" },
      { "<leader>bl", "<cmd>BufferLineCloseRight<cr>",      desc = "Close all to the right" },
      { "<leader>bW", "<cmd>noautocmd w<cr>",               desc = "Save without formatting (noautocmd)" },
    },

    config = function()
      require("bufferline").setup({
        options = {
          mode = "buffers",
          numbers = "none",
          close_command = "bdelete! %d",
          right_mouse_command = "bdelete! %d",
          left_mouse_command = "buffer %d",
          indicator = {
            icon = "▎",
            style = "icon",
          },
          buffer_close_icon = "",
          modified_icon = "●",
          close_icon = "",
          left_trunc_marker = "",
          right_trunc_marker = "",
          max_name_length = 30,
          max_prefix_length = 30,
          truncate_names = true,
          tab_size = 21,
          diagnostics = "nvim_lsp",
          diagnostics_update_in_insert = false,
          color_icons = true,
          show_buffer_icons = true,
          show_buffer_close_icons = true,
          show_close_icon = true,
          show_tab_indicators = true,
          persist_buffer_sort = true,
          separator_style = "thin",
          enforce_regular_tabs = false,
          always_show_bufferline = true,
          offsets = {
            {
              filetype = "neo-tree",
              text = "Explorer",
              highlight = "Directory",
              text_align = "left",
            },
          },
        },
      })
      vim.api.nvim_set_hl(0, "BufferLineFill", { bg = "none" })
      vim.api.nvim_set_hl(0, "BufferLineBackground", { bg = "none" })
      vim.api.nvim_set_hl(0, "BufferLineBufferSelected", { fg = "#f9e2af", italic = true })
    end,
  },
}
