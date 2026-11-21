local map = vim.keymap.set
local function o(desc)
  return { noremap = true, silent = true, desc = desc }
end

map("n", "<leader>w", "<cmd>write<cr>", o("Write file"))
map("n", "<leader>q", "<cmd>quit<cr>", o("Quit window"))

-- Quit Neovim in one step (panels, agent terminals and all), after confirming.
-- Lists unsaved files and running terminals/agents so nothing is lost by surprise.
local function quit_all()
  local modified, running = {}, 0
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      if vim.bo[buf].buftype == "" and vim.bo[buf].modified then
        local name = vim.api.nvim_buf_get_name(buf)
        modified[#modified + 1] = name ~= "" and vim.fn.fnamemodify(name, ":~:.") or "[No Name]"
      elseif vim.bo[buf].buftype == "terminal" then
        local job = vim.b[buf].terminal_job_id
        local ok, res = pcall(vim.fn.jobwait, { job }, 0)
        if job and ok and res[1] == -1 then running = running + 1 end
      end
    end
  end

  local lines = { "Quit Neovim?" }
  if #modified > 0 then
    lines[#lines + 1] = "\nUnsaved changes (" .. #modified .. "):"
    for i = 1, math.min(#modified, 8) do lines[#lines + 1] = "  • " .. modified[i] end
    if #modified > 8 then lines[#lines + 1] = "  … and " .. (#modified - 8) .. " more" end
  end
  if running > 0 then
    lines[#lines + 1] = "\nRunning terminals/agents that will be stopped: " .. running
  end
  local msg = table.concat(lines, "\n")

  if #modified == 0 then
    if vim.fn.confirm(msg, "&Yes\n&No", 2, "Question") == 1 then vim.cmd("qa!") end
    return
  end

  local choice = vim.fn.confirm(msg, "&Save all and quit\n&Discard changes and quit\n&Cancel", 3, "Warning")
  if choice == 1 then
    local ok, err = pcall(vim.cmd, "wall")
    if not ok then
      vim.notify("Could not save everything, not quitting:\n" .. tostring(err), vim.log.levels.ERROR)
      return
    end
    vim.cmd("qa!")
  elseif choice == 2 then
    vim.cmd("qa!")
  end
end

map("n", "<leader>Q", quit_all, o("Quit Neovim (confirm)"))
vim.api.nvim_create_user_command("QuitAll", quit_all, { desc = "Quit Neovim after confirming" })

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

-- Ctrl-w followed by hjkl works from terminal-mode agent panels too.
map("t", "<C-w>h", "<C-\\><C-N><C-w>h", o("Window left"))
map("t", "<C-w>j", "<C-\\><C-N><C-w>j", o("Window down"))
map("t", "<C-w>k", "<C-\\><C-N><C-w>k", o("Window up"))
map("t", "<C-w>l", "<C-\\><C-N><C-w>l", o("Window right"))

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

-- Kiro agent browser & creator
map("n", "<leader>ka", function() require("lenn.kiro-agents").browse() end, o("Kiro: browse agents"))
map("n", "<leader>kA", function() require("lenn.kiro-agents").create() end, o("Kiro: create new agent"))

-- Requirements panel (split sidebar by default, float with 'f')
map("n", "<leader>yp", function() require("lenn.requirements-panel").open() end, o("Requirements: open panel (sidebar)"))
map("n", "<leader>yf", function() require("lenn.requirements-panel").open({ float = true }) end, o("Requirements: open panel (float)"))
