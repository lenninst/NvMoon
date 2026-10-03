local map = vim.keymap.set
local function o(desc)
  return { noremap = true, silent = true, desc = desc }
end

map("n", "<leader>w", "<cmd>write<cr>", o("Write file"))
map("n", "<leader>q", "<cmd>quit<cr>", o("Quit window"))

map({ "n", "x" }, "gy", '"+y', o("Copy to clipboard (system)"))
map({ "n", "x" }, "gp", '"+p', o("Paste from clipboard (system)"))

-- window navigation
map("n", "<C-h>", "<C-w>h", o("Window left"))
map("n", "<C-j>", "<C-w>j", o("Window down"))
map("n", "<C-k>", "<C-w>k", o("Window up"))
map("n", "<C-l>", "<C-w>l", o("Window right"))

map("n", "<C-Up>", ":resize -2<CR>", o("Decrease window height"))
map("n", "<C-Down>", ":resize +2<CR>", o("Increase window height"))
map("n", "<C-Left>", ":vertical resize -2<CR>", o("Decrease window width"))
map("n", "<C-Right>", ":vertical resize +2<CR>", o("Increase window width"))

map("t", "<C-h>", "<C-\\><C-N><C-w>h", o("Window left"))
map("t", "<C-j>", "<C-\\><C-N><C-w>j", o("Window down"))
map("t", "<C-k>", "<C-\\><C-N><C-w>k", o("Window up"))
map("t", "<C-l>", "<C-\\><C-N><C-w>l", o("Window right"))

map("i", "<A-Up>", "<C-\\><C-N><C-w>k", o("Window up"))
map("i", "<A-Down>", "<C-\\><C-N><C-w>j", o("Window down"))
map("i", "<A-Left>", "<C-\\><C-N><C-w>h", o("Window left"))
map("i", "<A-Right>", "<C-\\><C-N><C-w>l", o("Window right"))

-- move current line / block
map("n", "<A-j>", ":m .+1<CR>==", o("Move line down"))
map("n", "<A-k>", ":m .-2<CR>==", o("Move line up"))
map("i", "<A-j>", "<Esc>:m .+1<CR>==gi", o("Move line down"))
map("i", "<A-k>", "<Esc>:m .-2<CR>==gi", o("Move line up"))
map("x", "<A-j>", ":m '>+1<CR>gv-gv", o("Move selection down"))
map("x", "<A-k>", ":m '<-2<CR>gv-gv", o("Move selection up"))

-- indent keeping the visual selection
map("v", "<", "<gv", o("Indent (keep selection)"))
map("v", ">", ">gv", o("Dedent (keep selection)"))

-- quickfix
map("n", "]q", ":cnext<CR>", o("Next quickfix entry"))
map("n", "[q", ":cprev<CR>", o("Previous quickfix entry"))

-- LSP
map("n", "<leader>la", vim.lsp.buf.code_action, o("Code action"))
map("n", "<leader>li", vim.lsp.buf.hover, o("Hover documentation"))
map("n", "<leader>lr", vim.lsp.buf.rename, o("Rename symbol"))
map("n", "<leader>ll", vim.lsp.codelens.run, o("Run CodeLens action"))
map("n", "<leader>lS", vim.lsp.buf.document_symbol, o("Document symbols"))
map("n", "<leader>ls", vim.lsp.buf.workspace_symbol, o("Workspace symbols"))
map("n", "<leader>ld", vim.diagnostic.setloclist, o("Buffer diagnostics to loclist"))
map("n", "<leader>lq", vim.diagnostic.setqflist, o("Buffer diagnostics to quickfix"))
map("n", "<leader>lj", vim.diagnostic.goto_next, o("Next diagnostic"))
map("n", "<leader>lk", vim.diagnostic.goto_prev, o("Previous diagnostic"))