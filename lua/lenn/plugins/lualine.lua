return {
  {
    "nvim-lualine/lualine.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      local ICON = {
        explorer = "\u{f07c}",
        finder = "\u{f002}",
        lsp = "\u{f0e7}",
        error = "\u{f00d}",
        warn = "\u{f071}",
        diff = "\u{f440}",
        outline = "\u{f0e8}",
      }

      local palette = {}

      local function hl(name)
        local ok, ret = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
        if ok and type(ret) == "table" then
          return ret
        end
        return {}
      end

      local function hex(value)
        return value and string.format("#%06x", value) or nil
      end

      local function fg(name, fallback)
        return hex(hl(name).fg) or fallback
      end

      local function bg(name, fallback)
        return hex(hl(name).bg) or fallback
      end

      local function channels(color)
        local c = color:gsub("#", "")
        return tonumber(c:sub(1, 2), 16), tonumber(c:sub(3, 4), 16), tonumber(c:sub(5, 6), 16)
      end

      local function lighten(color, amount)
        local r, g, b = channels(color)
        return string.format(
          "#%02x%02x%02x",
          math.floor(r + (255 - r) * amount),
          math.floor(g + (255 - g) * amount),
          math.floor(b + (255 - b) * amount)
        )
      end

      local function darken(color, amount)
        local r, g, b = channels(color)
        return string.format(
          "#%02x%02x%02x",
          math.floor(r * (1 - amount)),
          math.floor(g * (1 - amount)),
          math.floor(b * (1 - amount))
        )
      end

      local function readable(background)
        local r, g, b = channels(background)
        local luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255
        return luminance > 0.5 and palette.editor_bg or palette.fg
      end

      local function resolve()
        palette.fg = fg("Normal", "#cdd6f4")
        palette.editor_bg = bg("Normal", "#1e1e2e")
        palette.dim = fg("Comment", palette.fg)
        palette.faint = fg("NonText", palette.dim)
        palette.error = fg("DiagnosticError", palette.fg)
        palette.warn = fg("DiagnosticWarn", palette.fg)
        palette.info = fg("DiagnosticInfo", palette.dim)
        palette.accent = fg("Directory", palette.info)
        palette.added = fg("diffAdded", fg("Constant", palette.fg))

        local bar_bg = bg("StatusLine", palette.editor_bg)
        if bar_bg == palette.editor_bg then
          bar_bg = darken(palette.editor_bg, 0.45)
        end
        palette.bar_bg = bar_bg

        palette.mode = {
          n = { bg = lighten(palette.fg, 0.45) },
          i = { bg = palette.info },
          v = { bg = fg("Special", palette.accent) },
          s = { bg = palette.warn },
          c = { bg = bg("Search", darken(palette.editor_bg, 0.2)) },
          r = { bg = palette.error },
          t = { bg = fg("Constant", palette.warn) },
        }
        for _, mode in pairs(palette.mode) do
          mode.fg = readable(mode.bg)
          mode.gui = "bold"
        end
      end

      local mode_labels = {
        n = "NORMAL",
        i = "INSERT",
        v = "VISUAL",
        V = "VISUAL LINE",
        ["\22"] = "VISUAL BLOCK",
        s = "SELECT",
        S = "SELECT LINE",
        c = "COMMAND",
        r = "REPLACE",
        R = "REPLACE",
        t = "TERMINAL",
      }

      local function lsp_icon()
        local clients = vim.lsp.get_clients({ bufnr = 0 })
        if #clients == 0 then
          return ""
        end
        for _, client in ipairs(clients) do
          for _, progress in ipairs(client.progress or {}) do
            local value = progress.value
            if type(value) == "table" and value.kind then
              return ICON.lsp .. " " .. client.name
            end
          end
        end
        return ICON.lsp
      end

      local function lsp_color()
        for _, client in ipairs(vim.lsp.get_clients({ bufnr = 0 })) do
          for _, progress in ipairs(client.progress or {}) do
            local value = progress.value
            if type(value) == "table" and value.kind then
              return { fg = palette.info, bg = "none" }
            end
          end
        end
        return { fg = palette.faint, bg = "none" }
      end

      local function diagnostic_count(severity, icon)
        local count = vim.diagnostic.count(0)[severity] or 0
        return count > 0 and (icon .. " " .. count) or ""
      end

      local function cursor_position()
        return string.format("%d:%d", vim.fn.line("."), vim.fn.col("."))
      end

      local function mode_label()
        local mode = vim.fn.mode(1)
        return mode_labels[mode:sub(1, 1)] or string.upper(mode)
      end

      local function mode_color()
        return palette.mode[vim.fn.mode(1):sub(1, 1)] or { fg = palette.dim, bg = palette.bar_bg }
      end

      local function filetype_label()
        local ft = vim.bo.filetype
        return ft ~= "" and (ft:sub(1, 1):upper() .. ft:sub(2)) or ""
      end

      local function diff_stats()
        local status = vim.b.gitsigns_status_dict
        if type(status) ~= "table" then
          return 0
        end
        return (status.added or 0) + (status.removed or 0)
      end

      local function diff_label()
        local changed = diff_stats()
        return changed > 0 and (ICON.diff .. " " .. changed) or ""
      end

      resolve()

      require("lualine").setup({
        options = {
          theme = "auto",
          globalstatus = true,
          component_separators = { left = "", right = "" },
          section_separators = { left = "", right = "" },
        },

        sections = {
          lualine_a = {
            {
              function()
                return ICON.explorer
              end,
              color = { fg = palette.faint, bg = "none" },
              padding = { left = 2, right = 1 },
              on_click = function()
                vim.cmd("Neotree toggle")
              end,
            },
            {
              function()
                return ICON.finder
              end,
              color = { fg = palette.faint, bg = "none" },
              padding = { left = 1, right = 1 },
              on_click = function()
                Snacks.picker.files()
              end,
            },
            {
              lsp_icon,
              color = lsp_color,
              cond = function()
                return #vim.lsp.get_clients({ bufnr = 0 }) > 0
              end,
              padding = { left = 1, right = 1 },
              on_click = function()
                vim.cmd("LspLog")
              end,
            },
            {
              function()
                return diagnostic_count(vim.diagnostic.severity.ERROR, ICON.error)
              end,
              color = { fg = palette.error, bg = "none" },
              cond = function()
                return (vim.diagnostic.count(0)[vim.diagnostic.severity.ERROR] or 0) > 0
              end,
              padding = { left = 1, right = 1 },
              on_click = function()
                vim.cmd("Trouble diagnostics")
              end,
            },
            {
              function()
                return diagnostic_count(vim.diagnostic.severity.WARN, ICON.warn)
              end,
              color = { fg = palette.warn, bg = "none" },
              cond = function()
                return (vim.diagnostic.count(0)[vim.diagnostic.severity.WARN] or 0) > 0
              end,
              padding = { left = 1, right = 1 },
              on_click = function()
                vim.cmd("Trouble diagnostics")
              end,
            },
          },
          lualine_b = {},
          lualine_c = {},
          lualine_x = {
            {
              cursor_position,
              color = { fg = palette.dim },
              padding = { left = 1, right = 1 },
              on_click = function()
                vim.ui.input({ prompt = "Ir a linea: ", default = tostring(vim.fn.line(".")) }, function(input)
                  if input and input ~= "" then
                    pcall(vim.cmd, input)
                  end
                end)
              end,
            },
            {
              "mode",
              fmt = function()
                return mode_label()
              end,
              color = mode_color,
              padding = { left = 1, right = 1 },
            },
            {
              filetype_label,
              color = { fg = palette.dim },
              cond = function()
                return vim.bo.filetype ~= ""
              end,
              padding = { left = 1, right = 1 },
            },
            { "branch", color = { fg = palette.faint }, padding = { left = 1, right = 1 } },
            {
              diff_label,
              color = { fg = palette.added },
              cond = function()
                return diff_stats() > 0
              end,
              padding = { left = 1, right = 1 },
            },
            {
              function()
                return ICON.outline
              end,
              color = { fg = palette.faint },
              padding = { left = 1, right = 2 },
              on_click = function()
                vim.cmd("AerialToggle")
              end,
            },
          },
          lualine_y = {},
          lualine_z = {},
        },
      })

      local function apply_bar()
        vim.api.nvim_set_hl(0, "StatusLine", { fg = palette.fg, bg = palette.bar_bg })
        vim.api.nvim_set_hl(0, "StatusLineNC", { fg = palette.fg, bg = palette.bar_bg })
      end

      apply_bar()
      vim.o.laststatus = 3

      vim.api.nvim_create_autocmd("ColorScheme", {
        callback = function()
          resolve()
          apply_bar()
          require("lualine").refresh()
        end,
      })
    end,
  },
}