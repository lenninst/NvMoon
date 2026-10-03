return {
  {
    "akinsho/toggleterm.nvim",
    version = "*",
    event = "VeryLazy",
    opts = {
      size = function(term)
        if term.direction == "float" then
          return 80
        end
        return 15
      end,
      open_mapping = nil,
      shade_filetypes = {},
      shade_terminals = false,
      start_in_insert = true,
      insert_mappings = true,
      terminal_mappings = true,
      persist_size = true,
      direction = "float",
      float_opts = {
        border = "rounded",
        width = math.floor(vim.o.columns * 0.85),
        height = math.floor(vim.o.lines * 0.85),
        winblend = 0,
      },
      auto_scroll = true,
    },
    keys = {
      {
        "<leader>t",
        function() require("toggleterm").toggle(nil, nil, nil) end,
        desc = "Terminal: toggle (float)",
      },
      {
        "<leader>th",
        function() require("toggleterm").toggle(nil, nil, { direction = "horizontal" }) end,
        desc = "Terminal: toggle (horizontal split)",
      },
      {
        "<leader>tv",
        function() require("toggleterm").toggle(nil, nil, { direction = "vertical" }) end,
        desc = "Terminal: toggle (vertical split)",
      },
      {
        "<leader>c",
        function()
          local Terminal = require("toggleterm.terminal").Terminal
          local codex = Terminal:new({
            cmd = "codex",
            hidden = true,
            direction = "float",
            float_opts = {
              border = "rounded",
              width = math.floor(vim.o.columns * 0.85),
              height = math.floor(vim.o.lines * 0.85),
            },
          })
          codex:toggle()
        end,
        desc = "Codex: toggle",
      },
      {
        "<leader>cx",
        function()
          local Terminal = require("toggleterm.terminal").Terminal
          Terminal:new({ cmd = "codex", direction = "float" }):toggle()
        end,
        desc = "Codex: new instance",
      },
    },
  },
}
