-- Neorg: structured note taking with the Norg file format (.norg).
-- `version = "*"` makes lazy.nvim install the latest stable release from
-- luarocks, together with its Lua dependencies and the norg treesitter parsers.
local notes_dir = vim.fn.expand("~/notes")

return {
  {
    "nvim-neorg/neorg",
    version = "*",
    lazy = false,
    priority = 100,
    opts = {
      load = {
        ["core.defaults"] = {},
        ["core.concealer"] = {
          config = { icon_preset = "diamond" },
        },
        ["core.dirman"] = {
          config = {
            workspaces = {
              notes = notes_dir,
            },
            default_workspace = "notes",
            index = "index.norg",
          },
        },
        ["core.journal"] = {
          config = {
            workspace = "notes",
            strategy = "flat",
          },
        },
        ["core.summary"] = {},
        ["core.qol.toc"] = {},
        ["core.qol.todo_items"] = {},
        ["core.ui.calendar"] = {},
      },
    },
    keys = {
      { "<leader>nn", "<Plug>(neorg.dirman.new-note)", desc = "Notes: new note" },
      { "<leader>nj", "<cmd>Neorg journal today<cr>", desc = "Notes: journal (today)" },
      { "<leader>ny", "<cmd>Neorg journal yesterday<cr>", desc = "Notes: journal (yesterday)" },
      { "<leader>nt", "<cmd>Neorg toc<cr>", desc = "Notes: table of contents" },
      { "<leader>nw", "<cmd>Neorg workspace notes<cr>", desc = "Notes: open workspace" },
      {
        "<leader>ni",
        function()
          vim.cmd.edit(vim.fn.fnameescape(notes_dir .. "/index.norg"))
        end,
        desc = "Notes: open index",
      },
    },
    config = function(_, opts)
      -- The norg parsers are installed as luarocks packages (lazy-rocks) and
      -- lazy only appends their directories to `package.cpath` after Neorg has
      -- already tried to load them, so register them up front.
      local rocks_root = require("lazy.core.config").options.rocks.root
      for _, rock in ipairs({ "tree-sitter-norg", "tree-sitter-norg-meta" }) do
        local lang = rock:gsub("^tree%-sitter%-", ""):gsub("%-", "_")
        local dir = rocks_root .. "/" .. rock .. "/lib/lua/5.1"
        local parser = dir .. "/parser/" .. lang .. ".so"
        if vim.uv.fs_stat(parser) then
          vim.opt.runtimepath:append(dir)
          vim.treesitter.language.add(lang, { path = parser })
        end
      end

      require("neorg").setup(opts)

      -- Keep the workspace around so `:Neorg` commands never fail on a fresh machine.
      vim.fn.mkdir(notes_dir, "p")

      vim.api.nvim_create_autocmd("FileType", {
        pattern = "norg",
        callback = function()
          vim.wo.wrap = true
          vim.wo.linebreak = true
          vim.wo.spell = true
        end,
      })
    end,
  },
}
