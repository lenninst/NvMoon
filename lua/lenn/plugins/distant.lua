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
  keys = {
    { "<leader>rm", "<cmd>DistantConnect ssh://<cr>", desc = "Remote: connect over SSH" },
    { "<leader>ro", "<cmd>DistantOpen<cr>", desc = "Remote: open remote path" },
    { "<leader>rd", "<cmd>DistantDisconnect<cr>", desc = "Remote: disconnect" },
    { "<leader>rs", "<cmd>DistantShell<cr>", desc = "Remote: open shell" },
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
  end,
}
