-- Load all plugin specs
local specs = {}

-- UI
table.insert(specs, require("lenn.plugins.ui"))

-- Snacks (picker, dashboard, notifier)
table.insert(specs, require("lenn.plugins.snacks"))

-- Edgy (panel layout — agents, threads, explorer)
table.insert(specs, require("lenn.plugins.edgy"))

-- ToggleTerm / Codex
table.insert(specs, require("lenn.plugins.codex"))

-- OpenCode.nvim
table.insert(specs, require("lenn.plugins.opencode"))

-- Kiro agents (browser + creator)
table.insert(specs, require("lenn.plugins.kiro-agents"))

-- LSP
table.insert(specs, require("lenn.plugins.lsp"))

-- Completion
table.insert(specs, require("lenn.plugins.completion"))

-- Git
table.insert(specs, require("lenn.plugins.git"))

-- NeoTree file explorer
table.insert(specs, require("lenn.plugins.neotree"))

-- Treesitter
table.insert(specs, require("lenn.plugins.treesitter"))

-- Formatting
table.insert(specs, require("lenn.plugins.formatting"))

-- Lualine statusline
table.insert(specs, require("lenn.plugins.lualine"))

-- Noice notifications
table.insert(specs, require("lenn.plugins.noice"))

-- Which-key
table.insert(specs, require("lenn.plugins.which-key"))

-- Trouble
table.insert(specs, require("lenn.plugins.trouble"))

-- Flash
table.insert(specs, require("lenn.plugins.flash"))

-- Harpoon
table.insert(specs, require("lenn.plugins.harpoon"))

-- Bufferline
table.insert(specs, require("lenn.plugins.bufferline"))

-- Wayfinder
table.insert(specs, require("lenn.plugins.wayfinder"))

-- Auto pairs
table.insert(specs, require("lenn.plugins.autopairs"))

-- Aerial
table.insert(specs, require("lenn.plugins.aerial"))

-- DAP debugger
table.insert(specs, require("lenn.plugins.dap"))

-- DAP Python
table.insert(specs, require("lenn.plugins.dap-python"))

-- Mason tools
table.insert(specs, require("lenn.plugins.mason-tools"))

-- Neogit
table.insert(specs, require("lenn.plugins.neogit"))

-- Projects
table.insert(specs, require("lenn.plugins.projects"))

-- Minty
table.insert(specs, require("lenn.plugins.minty"))

-- Tidal
table.insert(specs, require("lenn.plugins.tidal"))

-- Distant
table.insert(specs, require("lenn.plugins.distant"))

return specs
