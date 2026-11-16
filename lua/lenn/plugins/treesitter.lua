return {
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    build = ":TSUpdate",
    lazy = false,
    config = function()
      require("nvim-treesitter").install({
        "lua",
        "vim",
        "vimdoc",
        "query",
        "javascript",
        "typescript",
        "tsx",
        "rust",
        "toml",
        "html",
        "css",
        "json",
        "c_sharp",
        "java",
        "dart",
        "bash",
        "markdown",
        "markdown_inline",
        "haskell",
        "supercollider",
      })

      vim.api.nvim_create_autocmd("FileType", {
        pattern = "*",
        callback = function()
          -- Neorg starts treesitter and configures folding for norg buffers.
          if vim.bo.filetype == "norg" then
            return
          end
          local ok = pcall(vim.treesitter.start)
          if ok then
            vim.wo.foldmethod = "expr"
            vim.wo.foldexpr = "v:lua.vim.treesitter.foldexpr()"
            vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
          end
        end,
      })
    end,
  },
}
