return {
  {
    "stevearc/conform.nvim",
    event = { "BufWritePre" },
    cmd = { "ConformInfo" },
    keys = {
      {
        "<leader>lf",
        function()
          require("conform").format({ async = true, lsp_fallback = true })
        end,
        mode = { "n", "x" },
        desc = "Format buffer",
      },
    },
    opts = {
      formatters_by_ft = {
        lua = { "stylua" },
        cs = { "csharpier" },
        javascript = { "prettier" },
        typescript = { "prettier" },
        javascriptreact = { "prettier" },
        typescriptreact = { "prettier" },
        json = { "prettier" },
        css = { "prettier" },
        html = { "prettier" },
        markdown = { "prettier" },
        haskell = function(bufnr)
          local filename = vim.api.nvim_buf_get_name(bufnr)
          if filename:match("%.tidal$") then
            return { "ormolu" }
          end
          return {}
        end,
        python = { "ruff_format" }
      },
      format_on_save = {
        timeout_ms = 1000,
        lsp_fallback = true,
      },
    },
  },
}
