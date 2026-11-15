return {
  {
    "saghen/blink.compat",
    lazy = true,
    opts = {},
  },
  {
    "saghen/blink.cmp",
    version = "1.*",
    dependencies = { "rafamadriz/friendly-snippets" },
    opts = {
      keymap = {
        ["<Tab>"] = {
          "select_next",
          "fallback",
        },

        ["<S-Tab>"] = {
          "select_prev",
          "fallback",
        },

        ["<CR>"] = {
          "accept",
          "fallback",
        },
      },
      appearance = {
        nerd_font_variant = "mono",
      },
      completion = {
        documentation = { auto_show = true },
        menu = {
          border = "rounded",
        },
      },
      sources = {
        default = { "lsp", "omni", "path", "snippets", "buffer" },
        providers = {
          omni = {
            name = "omni",
            module = "blink.compat.source",
            score_offset = -3,
            opts = {},
          },
        },
      },
      signature = { enabled = true },
    },
    opts_extend = { "sources.default" },
  },
}
