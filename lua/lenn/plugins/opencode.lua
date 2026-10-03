return {
  {
    "NickvanDyke/opencode.nvim",
    event = "VeryLazy",
    dependencies = {
      { "folke/snacks.nvim", optional = true },
    },
    keys = {
      { "<leader>a",  function() require("opencode").ask("@this: ") end,  desc = "Opencode: Ask" },
      { "<leader>ao", function() require("opencode").ask("") end,        desc = "Opencode: Ask (sin contexto)" },
      { "<leader>am", function() require("opencode").prompt("Select model") end, desc = "Opencode: Select Model" },
      { "<leader>aa", function() require("opencode").prompt("Select agent") end, desc = "Opencode: Select Agent" },
      { "<leader>an", function() require("opencode").prompt("@") end,      desc = "Opencode: Add Context" },
      { "<leader>as", function() require("opencode").select() end,         desc = "Opencode: Select" },
    },
  },
}