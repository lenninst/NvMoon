return {
  {
    "windwp/nvim-autopairs",
    event = "InsertEnter",
    opts = {
      check_ts = true,
      ts_config = {
        lua = { "string" },
        javascript = { "template_string" },
      },
      disable_filetype = { "TelescopePrompt", "snacks_picker_input" },
      fast_wrap = {
        map = "<M-e>",
      },
    },
  },
  {
    "numToStr/Comment.nvim",
    event = { "BufReadPost", "BufNewFile" },
    opts = {},
  },
}
