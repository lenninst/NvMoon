-- Neorg: structured note taking with the Norg file format (.norg).
-- `version = "*"` makes lazy.nvim install the latest stable release from
-- luarocks, together with its Lua dependencies and the norg treesitter parsers.
local notes_dir = vim.fn.expand("~/notes")
local requirements_dir = vim.fn.expand("~/requirements")

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
              requirements = requirements_dir,
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
      { "<leader>yr", "<cmd>Neorg workspace requirements<cr>", desc = "Requirements: open workspace" },
      {
        "<leader>yn",
        function()
          local path = requirements_dir .. "/requirements.md"
          vim.fn.mkdir(requirements_dir, "p")
          if vim.fn.filereadable(path) == 0 then
            vim.fn.writefile({
              "# Requirements",
              "",
              "## Functional Requirements (RF)",
              "",
              "## Non-Functional Requirements (RNF)",
              "",
              "## Actors",
              "",
              "## References",
            }, path)
          end
          vim.cmd.edit(vim.fn.fnameescape(path))
        end,
        desc = "Requirements: new requirement file",
      },
      {
        "<leader>yi",
        function()
          local path = requirements_dir .. "/index.norg"
          vim.fn.mkdir(requirements_dir, "p")
          if vim.fn.filereadable(path) == 0 then
            vim.fn.writefile({
              "= Requirements Index",
              "",
              "This is the entry point for the requirements workspace.",
              "Use it to organize projects and link to requirement files.",
              "",
              "* Projects::",
              "  - Add your projects here with links to their requirement files.",
              "",
              "* Quick Links::",
              "  - Use \\`space yn\\` to create a new requirement file.",
              "  - Use \\`space yr\\` to open this workspace.",
            }, path)
          end
          vim.cmd.edit(vim.fn.fnameescape(path))
        end,
        desc = "Requirements: open index",
      },
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
      vim.fn.mkdir(requirements_dir, "p")

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
