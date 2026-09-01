local opt = vim.opt

opt.number = true
opt.relativenumber = true
opt.cursorline = true
opt.cursorlineopt = "number"
opt.numberwidth = 1

opt.tabstop = 2
opt.shiftwidth = 2
opt.expandtab = true
opt.smartcase = true
opt.wrap = false
opt.signcolumn = "yes"
opt.termguicolors = true
opt.scrolloff = 8
opt.clipboard = "unnamedplus"
opt.fillchars = { eob = " " }
opt.foldlevel = 99
opt.foldlevelstart = 99
-- opt.cmdheight = 1
vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    vim.o.cmdheight = 1
  end,
})

vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1
vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    local arg = vim.fn.argv(0)
    if arg and vim.fn.isdirectory(arg) == 1 then
      vim.cmd("Neotree " .. arg)
    end
  end,
})


vim.diagnostic.config({
  virtual_text = {
    prefix = "",
    spacing = 4,
    source = "if_many",
  },
  signs = true,
  underline = true,
  update_in_insert = false,
  severity_sort = true,
  float = {
    border = "rounded",
    source = "always",
  },
})


vim.g.mapleader = " "
vim.api.nvim_set_hl(0, "YankHighlight", { bg = "#b4befe", fg = "#1e1e2e" })

vim.api.nvim_create_autocmd("TextYankPost", {
  callback = function()
    vim.highlight.on_yank({ higroup = "YankHighlight", timeout = 240 })
  end,
})

vim.filetype.add({
  extension = {
    axaml = "xml",
  },
})
