print("options.lua loaded")

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
