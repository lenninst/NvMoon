return {
  {
    "folke/snacks.nvim",
    priority = 1000,
    lazy = false,
    opts = {
      picker = { enabled = true },
      bigfile = { enabled = true },
      quickfile = { enabled = true },
      dashboard = {
        enabled = true,
        preset = {
          header = [[
░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
░    ░░░░░   ░░░░░░░░░░░░░   ░░░░░░░   ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
▒  ▒   ▒▒▒   ▒▒▒▒▒▒▒▒▒▒▒▒▒  ▒   ▒▒▒    ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒
▒   ▒   ▒▒   ▒   ▒▒▒▒▒   ▒   ▒   ▒ ▒   ▒▒▒▒   ▒▒▒▒▒▒▒▒   ▒▒▒▒▒   ▒   ▒▒
▓   ▓▓   ▓   ▓▓   ▓▓▓   ▓▓   ▓▓   ▓▓   ▓▓   ▓▓   ▓▓▓   ▓▓   ▓▓▓   ▓▓
▓   ▓▓▓  ▓   ▓▓▓   ▓   ▓▓▓   ▓▓▓  ▓▓   ▓   ▓▓▓▓   ▓   ▓▓▓▓   ▓▓   ▓▓
▓   ▓▓▓▓  ▓  ▓▓▓▓     ▓▓▓▓   ▓▓▓▓▓▓▓   ▓▓   ▓▓   ▓▓▓   ▓▓   ▓▓▓   ▓▓
█   ██████   █████   █████   ███████   ████   ████████   █████    ██
███████████████████████████████████████████████████████████████████████

]],
        },
        sections = {
          { section = "header" },
          { section = "keys",   gap = 1, padding = 1 },
          { section = "startup" },
        },
      },
      notifier = {
        enabled = true,
        timeout = 3000,
        style = "compact", -- "compact", "fancy",  "minimal"
        position = "bottom_right",
        top_down = false,
      },
      words = {
        enabled = true,
      },
    },
    keys = {
      { "<leader>ff", function() Snacks.picker.files() end,     desc = "Find files" },
      { "<leader>fg", function() Snacks.picker.grep() end,      desc = "Live grep" },
      { "<leader>fb", function() Snacks.picker.buffers() end,   desc = "Buffers" },
      { "<leader>fh", function() Snacks.picker.help() end,      desc = "Help tags" },
      { "<leader>fo", function() Snacks.picker.recent() end,    desc = "Recent files" },
      { "<leader>fs", function() Snacks.picker.grep_word() end, desc = "Search word under cursor" },
    },
  },
}
