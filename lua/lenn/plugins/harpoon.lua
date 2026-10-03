return {
  {
    "ThePrimeagen/harpoon",
    branch = "harpoon2",
    dependencies = { "nvim-lua/plenary.nvim" },
    config = true,
    opts = {
      settings = {
        sync_on_ui_close = true,
      },
    },
    keys = function()
      local keys = {
        {
          "<leader>ha",
          function() require("harpoon"):list():add() end,
          desc = "Harpoon: add file",
        },
        {
          "<leader>hm",
          function() require("harpoon").ui:toggle_quick_menu(require("harpoon"):list()) end,
          desc = "Harpoon: open menu",
        },
      }
      for i = 1, 4 do
        table.insert(keys, {
          "<leader>h" .. i,
          function() require("harpoon"):list():select(i) end,
          desc = "Harpoon: jump to file " .. i,
        })
      end
      return keys
    end,
  },
}
