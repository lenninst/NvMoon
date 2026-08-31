return {
  {
    "lewis6991/gitsigns.nvim",
    event = { "BufReadPre", "BufNewFile" },
    config = function()
      require("gitsigns").setup({
        signs = {
          add = { text = "│" },
          change = { text = "│" },
          delete = { text = "_" },
          topdelete = { text = "‾" },
          changedelete = { text = "~" },
          untracked = { text = "┆" },
        },
        current_line_blame = false,
        on_attach = function(bufnr)
          local gs = package.loaded.gitsigns
          local map = vim.keymap.set

          local function opts(desc)
            return { buffer = bufnr, desc = desc }
          end

          -- Navegación entre hunks
          map("n", "]c", function()
            if vim.wo.diff then return "]c" end
            vim.schedule(function() gs.next_hunk() end)
            return "<Ignore>"
          end, { expr = true, buffer = bufnr, desc = "Next hunk" })

          map("n", "[c", function()
            if vim.wo.diff then return "[c" end
            vim.schedule(function() gs.prev_hunk() end)
            return "<Ignore>"
          end, { expr = true, buffer = bufnr, desc = "Prev hunk" })

          -- Acciones
          map("n", "<leader>hs", gs.stage_hunk, opts("Stage hunk"))
          map("n", "<leader>hr", gs.reset_hunk, opts("Reset hunk"))
          map("n", "<leader>hp", gs.preview_hunk, opts("Preview hunk"))
          map("n", "<leader>hb", function() gs.blame_line({ full = true }) end, opts("Blame line"))
          map("n", "<leader>tb", gs.toggle_current_line_blame, opts("Toggle blame"))
          map("n", "<leader>hd", gs.diffthis, opts("Diff this"))
        end,
      })
    end,
  },
}
