return {
  "chipsenkbeil/distant.nvim",
  branch = "v0.3",
  cmd = {
    "Distant",
    "DistantConnect",
    "DistantOpen",
    "DistantLaunch",
    "DistantClose",
    "DistantDisconnect",
    "DistantShell",
  },
  config = function()
    require("distant"):setup({
      manager = {
        auto_install = true,
        daemon = true,
      },
      network = {
        timeout = 30,
        ssh = {
          multiplexing = true,
        },
      },
    })

    vim.keymap.set("n", "<leader>dc", ":DistantConnect ssh://", { desc = "Distant: Connect SSH" })
    vim.keymap.set("n", "<leader>do", ":DistantOpen ", { desc = "Distant: Open remote path" })
    vim.keymap.set("n", "<leader>dd", "<cmd>DistantDisconnect<cr>", { desc = "Distant: Disconnect" })
    vim.keymap.set("n", "<leader>ds", "<cmd>DistantShell<cr>", { desc = "Distant: Remote shell" })
  end,
}
