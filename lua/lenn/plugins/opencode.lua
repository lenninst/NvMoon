return {
  {
    "NickvanDyke/opencode.nvim",
    event = "VeryLazy",
    dependencies = {
      { "folke/snacks.nvim", optional = true },
    },
    keys = {
      { "<leader>a",  function() require("opencode").ask("@this: ") end,   desc = "AI: ask with context" },
      { "<leader>ao", function() require("opencode").ask("") end,         desc = "AI: ask without context" },
      { "<leader>am", function() require("opencode").prompt("Select model") end, desc = "AI: select model" },
      { "<leader>aa", function() require("opencode").prompt("Select agent") end, desc = "AI: select agent" },
      { "<leader>an", function() require("opencode").prompt("@") end,      desc = "AI: add context" },
      { "<leader>as", function() require("opencode").select() end,         desc = "AI: select" },
    },
  },
}