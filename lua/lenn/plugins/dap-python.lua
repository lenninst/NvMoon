return {
  {
    "mfussenegger/nvim-dap-python",
    ft = "python",
    dependencies = { "mfussenegger/nvim-dap" },
    config = function()
      require("dap-python").setup(vim.fn.stdpath("data") .. "/mason/packages/debugpy/venv/bin/python")
    end,
    keys = {
      {
        "<leader>dp",
        function() require("dap-python").test_method() end,
        desc = "Debug: run python test method",
      },
    },
  },
}
