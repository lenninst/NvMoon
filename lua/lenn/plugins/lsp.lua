return {
  {
    "williamboman/mason.nvim",
    config = function()
      require("mason").setup({
        ui = {
          icons = {
            package_installed = "✓",
            package_pending = "➜",
            package_uninstalled = "✗",
          },
        },
      })
    end,
  },
  {
    "williamboman/mason-lspconfig.nvim",
    dependencies = { "williamboman/mason.nvim" },
    config = function()
      require("mason-lspconfig").setup({
        ensure_installed = {
          "lua_ls",
          "ts_ls",
          "eslint",
          "lemminx"
        },
        automatic_installation = true,
      })
    end,
  },
  {
    "neovim/nvim-lspconfig",
    dependencies = { "mason-lspconfig.nvim", "saghen/blink.cmp" },
    config = function()
      local capabilities = require("blink.cmp").get_lsp_capabilities()

      vim.lsp.config("lua_ls", {
        capabilities = capabilities,
        settings = {
          Lua = {
            diagnostics = { globals = { "vim" } },
          },
        },
      })

      vim.lsp.config("lemminx", {
        capabilities = capabilities,
        filetypes = { "xml", "xsd", "xsl", "xslt", "svg", "axaml" },
      })

      vim.lsp.enable({ "lua_ls", "ts_ls", "eslint", "lemminx" })
    end,
  },
  {
    "seblyng/roslyn.nvim",
    ft = "cs",
    config = function()
      local capabilities = require("blink.cmp").get_lsp_capabilities()

      require("roslyn").setup({
        broad_search = true, -- busca .sln recursivamente hacia arriba (útil en monorepos)
        config = {
          capabilities = capabilities,
          settings = {
            ["csharp|inlay_hints"] = {
              csharp_enable_inlay_hints_for_implicit_object_creation = true,
              csharp_enable_inlay_hints_for_implicit_variable_types = true,
              csharp_enable_inlay_hints_for_lambda_parameter_types = true,
              csharp_enable_inlay_hints_for_types = true,
              dotnet_enable_inlay_hints_for_parameters = true,
              dotnet_enable_inlay_hints_for_indexer_parameters = true,
              dotnet_enable_inlay_hints_for_literal_parameters = true,
              dotnet_enable_inlay_hints_for_object_creation_parameters = true,
              dotnet_enable_inlay_hints_for_other_parameters = true,
            },
            ["csharp|code_lens"] = {
              dotnet_enable_references_code_lens = true,
              dotnet_enable_tests_code_lens = true,
            },
            ["csharp|symbol_search"] = {
              dotnet_search_reference_assemblies = true,
            },
            ["csharp|formatting"] = {
              dotnet_organize_imports_on_format = true,
            },
            ["csharp|completion"] = {
              dotnet_show_completion_items_from_unimported_namespaces = true,
              dotnet_show_name_completion_suggestions = true,
            },
          },
        },
      })
    end,
  },

}
