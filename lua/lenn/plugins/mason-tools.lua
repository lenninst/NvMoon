return {
  "WhoIsSethDaniel/mason-tool-installer.nvim",
  dependencies = { "williamboman/mason.nvim", "williamboman/mason-lspconfig.nvim" },
  config = function()
    require("mason-tool-installer").setup({
      ensure_installed = {
        -- LSPs
        "lua-language-server",
        "typescript-language-server",
        "eslint-lsp",
        "xml-language-server",
        "basedpyright",
        "ruff",
        "rust-analyzer",
        "csharp-language-server",

        -- Formatters
        "stylua",
        "prettier",

        -- Linters
        "markdownlint",

        -- Debuggers
        "debugpy",
      },
      auto_update = true,
      run_on_start = true,
      start_delay = 500,
      debounce_hours = 24,
    })
  end,
}
