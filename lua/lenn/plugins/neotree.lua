return {
  {
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-tree/nvim-web-devicons",
      "MunifTanjim/nui.nvim",
    },
    cmd = "Neotree",
    keys = {
      { "<leader>e", "<cmd>Neotree toggle<cr>", desc = "Explorer: toggle" },
      { "<leader>ee", function() require("lenn.explorer").show("filesystem", true) end, desc = "Explorer: files" },
      { "<leader>eb", function() require("lenn.explorer").show("buffers", true) end, desc = "Explorer: buffers" },
      { "<leader>eg", function() require("lenn.explorer").show("git_status", true) end, desc = "Explorer: git status" },
    },
    config = function()
      local nf = require("lenn.icons")
      require("neo-tree").setup({
        close_if_last_window = true,
        popup_border_style = "rounded",
        -- Blank first row, then neo-tree's default short root path (~/…)
        add_blank_line_at_top = true,
        enable_opened_markers = true,
        default_component_configs = {
          indent = {
            indent_size = 2,
            padding = 1,
            -- Zed-style straight guides on every level
            with_markers = true,
            indent_marker = "│",
            last_indent_marker = "│",
            highlight = "NeoTreeIndentMarker",
            with_expanders = true,
            expander_collapsed = nf.ui_chevron_right,
            expander_expanded = nf.ui_chevron_down,
            expander_highlight = "NeoTreeExpander",
          },
          icon = {
            folder_closed = nf.folder_closed .. " ",
            folder_open = nf.folder_open .. " ",
            folder_empty = nf.folder_empty .. " ",
            default = nf.file_default,
          },
          modified = {
            symbol = nf.dot,
          },
          name = {
            trailing_slash = false,
            use_git_status_colors = true,
            highlight_opened_files = true,
          },
        },
        filesystem = {
          hijack_netrw_behavior = "disabled",
          filtered_items = {
            visible = true,
            hide_dotfiles = false,
            hide_gitignored = false,
          },
          follow_current_file = {
            enabled = true,
          },
        },
        window = {
          width = 30,
        },
        -- Files / Buffers / Git are switched from lualine (or <leader>ef/eb/eg)
        source_selector = {
          winbar = false,
          statusline = false,
        },
        event_handlers = {
          -- Record each source's root for the bufferline title (lenn.explorer)
          {
            event = "after_render",
            handler = function(state) require("lenn.explorer").on_render(state) end,
          },
        },
      })

      vim.api.nvim_set_hl(0, "NeoTreeNormal", { bg = "none" })
      vim.api.nvim_set_hl(0, "NeoTreeNormalNC", { bg = "none" })
      vim.api.nvim_set_hl(0, "NeoTreeEndOfBuffer", { bg = "none" })
      require("lenn.explorer").setup()
    end,
  },
}
