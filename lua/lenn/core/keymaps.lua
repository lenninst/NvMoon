local map = vim.keymap.set
local opts = { noremap = true, silent = true }

map("n", "<leader>w", "<cmd>write<cr>", { desc = "Save" })
map("n", "<leader>q", "<cmd>quit<cr>", { desc = "Exit" })

map({ "n", "x" }, "gy", '"+y', { desc = "Copiar al portapapeles" })
map({ "n", "x" }, "gp", '"+p', { desc = "Pegar del portapapeles" })

-- navegación entre ventanas
map("n", "<C-h>", "<C-w>h", opts)
map("n", "<C-j>", "<C-w>j", opts)
map("n", "<C-k>", "<C-w>k", opts)
map("n", "<C-l>", "<C-w>l", opts)

-- Redimensionar ventanas
map("n", "<C-Up>", ":resize -2<CR>", opts)
map("n", "<C-Down>", ":resize +2<CR>", opts)
map("n", "<C-Left>", ":vertical resize -2<CR>", opts)
map("n", "<C-Right>", ":vertical resize +2<CR>", opts)

-- Mover línea/bloque actual con Alt-j/k
map("n", "<A-j>", ":m .+1<CR>==", opts)
map("n", "<A-k>", ":m .-2<CR>==", opts)
map("i", "<A-j>", "<Esc>:m .+1<CR>==gi", opts)
map("i", "<A-k>", "<Esc>:m .-2<CR>==gi", opts)
map("x", "<A-j>", ":m '>+1<CR>gv-gv", opts)
map("x", "<A-k>", ":m '<-2<CR>gv-gv", opts)

-- Navegación por QuickFix
map("n", "]q", ":cnext<CR>", opts)
map("n", "[q", ":cprev<CR>", opts)

-- Navegación entre ventanas dentro de una terminal
map("t", "<C-h>", "<C-\\><C-N><C-w>h", opts)
map("t", "<C-j>", "<C-\\><C-N><C-w>j", opts)
map("t", "<C-k>", "<C-\\><C-N><C-w>k", opts)
map("t", "<C-l>", "<C-\\><C-N><C-w>l", opts)

-- Navegación con Alt en insert mode
map("i", "<A-Up>", "<C-\\><C-N><C-w>k", opts)
map("i", "<A-Down>", "<C-\\><C-N><C-w>j", opts)
map("i", "<A-Left>", "<C-\\><C-N><C-w>h", opts)
map("i", "<A-Right>", "<C-\\><C-N><C-w>l", opts)

-- Mejor indentado (se mantiene la selección visual)
map("v", "<", "<gv", opts)
map("v", ">", ">gv", opts)
