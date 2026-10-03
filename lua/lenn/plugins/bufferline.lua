return {
  {
    "akinsho/bufferline.nvim",
    version = "*",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    event = "VeryLazy",
    keys = {
      { "<S-l>",      "<cmd>BufferLineCycleNext<cr>",       desc = "Buffers: next" },
      { "<S-h>",      "<cmd>BufferLineCyclePrev<cr>",       desc = "Buffers: previous" },

      { "<leader>bb", "<cmd>BufferLineCyclePrev<cr>",       desc = "Buffers: previous" },
      { "<leader>bn", "<cmd>BufferLineCycleNext<cr>",       desc = "Buffers: next" },
      { "<leader>bD", "<cmd>BufferLineSortByDirectory<cr>", desc = "Buffers: sort by directory" },
      { "<leader>bL", "<cmd>BufferLineSortByExtension<cr>", desc = "Buffers: sort by language" },
      { "<leader>be", "<cmd>BufferLinePickClose<cr>",       desc = "Buffers: pick one to close" },
      -- { "<leader>bf", "<cmd>BufferLinePick<cr>",            desc = "Find" },
      { "<leader>bj", "<cmd>BufferLinePick<cr>",            desc = "Buffers: jump to" },
      { "<leader>bh", "<cmd>BufferLineCloseLeft<cr>",       desc = "Buffers: close all to the left" },
      { "<leader>bl", "<cmd>BufferLineCloseRight<cr>",      desc = "Buffers: close all to the right" },
      { "<leader>bW", "<cmd>noautocmd w<cr>",               desc = "Buffers: save without autocmds" },
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
          custom_filter = function(bufnr)
            local buf = vim.bo[bufnr]
            if not buf.buflisted or buf.buftype ~= "" then
              return false
            end
            local name = vim.api.nvim_buf_get_name(bufnr)
            local pristine = not buf.modified
              and vim.api.nvim_buf_line_count(bufnr) == 1
              and vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1] == ""
            return not (name == "" and pristine)
          end,
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
