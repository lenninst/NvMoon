return {
	{
		"nvim-neo-tree/neo-tree.nvim",
		branch = "v3.x",
		dependencies = {
			"nvim-lua/plenary.nvim",
			"nvim-tree/nvim-web-devicons",
			"MunifTanjim/nui.nvim",
		},
		cmd = "Neotree",
		keys = {
			{ "<leader>e", "<cmd>Neotree toggle<cr>", desc = "Explorer" },
		},
		config = function()
			require("neo-tree").setup({
				close_if_last_window = true,
				default_component_configs = {
					indent = {
						with_markers = false,
						with_expanders = true,
						expander_collapsed = "",
						expander_expanded = "",
					},
					icon = {
						folder_closed = " ",
						folder_open = " ",
						folder_empty = " ",
						default = "󰉋 ",
					},
				},
				filesystem = {
					filtered_items = {
						visible = true,
						hide_dotfiles = false,
						hide_gitignored = false,
					},
					follow_current_file = {
						enabled = true,
					},
				},
				window = {
					width = 30,
				},
			})

			vim.api.nvim_set_hl(0, "NeoTreeNormal", { bg = "none" })
			vim.api.nvim_set_hl(0, "NeoTreeNormalNC", { bg = "none" })
			vim.api.nvim_set_hl(0, "NeoTreeEndOfBuffer", { bg = "none" })
		end,
	},
}
