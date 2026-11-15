-- Skill Market — Mason-style UI for discovering and managing Agent Skills
-- Two tabs: Installed (local skills) and Marketplace (download from GitHub)
-- Supports installing from catalog, custom GitHub URLs, and links to claudemarket.ai
--
-- Usage: require("lenn.skill-market").open()

local M = {}

local skills_module = require("lenn.agent-skills")
local skill_repo = require("lenn.skill-repo")

-- ─── State ──────────────────────────────────────────────────────────────────
local current_tab = "installed"  -- "installed" or "marketplace"
local search_query = ""
local install_buf_ref = nil      -- reference to buffer for callbacks
local install_win_ref = nil      -- reference to window for callbacks

-- ─── Icons ──────────────────────────────────────────────────────────────────
local icons = {
  enabled = "✓",
  disabled = "○",
  installed = "✓",
  not_installed = "○",
  skill = "🔧",
  search = "🔍",
  loading = "⏳",
  external = "↗",
}

-- ─── Helpers ────────────────────────────────────────────────────────────────

local function get_item_at_line(items, line_num)
  local header_lines = 4  -- tab bar + header + keymaps + blank
  local item_index = line_num - header_lines
  if item_index >= 1 and item_index <= #items then
    return items[item_index]
  end
  return nil
end

-- ─── Tab Rendering ──────────────────────────────────────────────────────────

local function render_tab_bar(buf, tab)
  local tabs = { "Installed", "Marketplace" }
  local tab_line = "  ┌─────────┬─────────────┐"
  tab_line = tab_line .. "\n  │"
  for _, t in ipairs(tabs) do
    local label = " " .. t .. " "
    local padding = 11 - #label
    if t == tab then
      tab_line = tab_line .. " " .. label .. string.rep(" ", padding) .. " │"
    else
      tab_line = tab_line .. " " .. label .. string.rep(" ", padding) .. " │"
    end
  end
  tab_line = tab_line .. "\n  └─────────┴─────────────┘"
  return tab_line
end

-- ─── Installed Tab ──────────────────────────────────────────────────────────

local function render_installed_tab(buf, skills)
  local enabled_count = 0
  for _, s in ipairs(skills) do
    if s.enabled then enabled_count = enabled_count + 1 end
  end
  local total = #skills

  local lines = {}

  -- Tab bar
  table.insert(lines, "  ┌─────────┬─────────────┐")
  table.insert(lines, "  │ Installed │ Marketplace │")
  table.insert(lines, "  └─────────┴─────────────┘")
  table.insert(lines, string.format("  Skills: %d/%d enabled  (Tab switch  ·  <CR>/s toggle  ·  d doc  ·  K desc  ·  R refresh  ·  x uninstall  ·  q close)", enabled_count, total))
  table.insert(lines, "")

  if #skills == 0 then
    table.insert(lines, "  No skills installed in ~/.junie/skills/")
    table.insert(lines, "")
    table.insert(lines, "  Press Tab to go to Marketplace and install skills.")
  else
    local sorted = vim.list_extend({}, skills)
    table.sort(sorted, function(a, b)
      if a.enabled ~= b.enabled then return a.enabled end
      return a.name < b.name
    end)

    for _, skill in ipairs(sorted) do
      local status = skill.enabled and icons.enabled or icons.disabled
      local desc_preview = ""
      if skill.description and skill.description:len() > 0 then
        local desc = skill.description:gsub("\n", " "):gsub("%s+", " "):gsub("^%s+", "")
        if desc:len() > 50 then desc = desc:sub(1, 47) .. "..." end
        desc_preview = " — " .. desc
      end
      table.insert(lines, string.format("  [%s] %s%s", status, skill.name, desc_preview))
    end
  end

  table.insert(lines, "")
  return lines, sorted or skills
end

-- ─── Marketplace Tab ────────────────────────────────────────────────────────

local function render_marketplace_tab(buf, catalog)
  local installed_count = 0
  for _, s in ipairs(catalog) do
    if skill_repo.is_installed(s.name) then installed_count = installed_count + 1 end
  end
  local total = #catalog

  local lines = {}

  -- Tab bar
  table.insert(lines, "  ┌─────────┬─────────────┐")
  table.insert(lines, "  │  Installed │ Marketplace │")
  table.insert(lines, "  └─────────┴─────────────┘")

  -- Header with search info
  local header_info = string.format("  Marketplace: %d/%d installed  (Tab switch  ·  <CR> install  ·  K desc  ·  / search  ·  U install from URL  ·  R refresh  ·  q close)", installed_count, total)
  if search_query ~= "" then
    header_info = string.format("  🔍 Search: '%s' (%d results)  (Esc clear  ·  <CR> install  ·  K desc  ·  U from URL  ·  q close)", search_query, #catalog)
  end
  table.insert(lines, header_info)
  table.insert(lines, "")

  if #catalog == 0 then
    if search_query ~= "" then
      table.insert(lines, "  No skills match '" .. search_query .. "'")
      table.insert(lines, "  Press Esc to clear search")
    else
      table.insert(lines, "  No skills in catalog")
    end
  else
    for _, skill in ipairs(catalog) do
      local is_installed = skill_repo.is_installed(skill.name)
      local status = is_installed and icons.installed or icons.not_installed
      local desc_preview = ""
      if skill.description and skill.description:len() > 0 then
        local desc = skill.description:gsub("\n", " "):gsub("%s+", " "):gsub("^%s+", "")
        if desc:len() > 45 then desc = desc:sub(1, 42) .. "..." end
        desc_preview = " — " .. desc
      end
      local author_tag = skill.author and " (" .. skill.author .. ")" or ""
      local install_tag = is_installed and " [INSTALLED]" or ""
      table.insert(lines, string.format("  [%s] %s%s%s%s", status, skill.name, author_tag, install_tag, desc_preview))
    end
  end

  -- External sources
  table.insert(lines, "")
  table.insert(lines, "  ── External Sources ──")
  table.insert(lines, "  " .. icons.external .. "  claudemarket.ai      https://www.claudemarket.ai")
  table.insert(lines, "  " .. icons.external .. "  mcpservers.org         https://mcpservers.org/agent-skills")
  table.insert(lines, "  " .. icons.external .. "  awesomeskill.ai        https://awesomeskill.ai")
  table.insert(lines, "")
  table.insert(lines, "  Press U to install a skill from a custom GitHub URL")

  return lines
end

-- ─── Main Render ────────────────────────────────────────────────────────────

function M.render(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return end

  local lines
  if current_tab == "installed" then
    local skills = skills_module.get_skills()
    lines, _ = render_installed_tab(buf, skills)
  else
    local catalog = skill_repo.search(search_query)
    lines = render_marketplace_tab(buf, catalog)
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  M.apply_highlights(buf)
end

function M.apply_highlights(buf)
  vim.api.nvim_buf_clear_namespace(buf, 0, 0, -1)

  -- Tab bar highlights (lines 0-2)
  vim.api.nvim_buf_add_highlight(buf, 0, "Title", 0, 0, -1)
  vim.api.nvim_buf_add_highlight(buf, 0, "Title", 1, 0, -1)
  vim.api.nvim_buf_add_highlight(buf, 0, "Title", 2, 0, -1)

  -- Keymaps line
  vim.api.nvim_buf_add_highlight(buf, 0, "Comment", 3, 0, -1)

  -- Skill lines start at line 4 (0-indexed)
  local header_lines = 4

  if current_tab == "installed" then
    local skills = skills_module.get_skills()
    local sorted = vim.list_extend({}, skills)
    table.sort(sorted, function(a, b)
      if a.enabled ~= b.enabled then return a.enabled end
      return a.name < b.name
    end)
    for i, skill in ipairs(sorted) do
      local line = header_lines + i - 1
      if skill.enabled then
        vim.api.nvim_buf_add_highlight(buf, 0, "DiagnosticInfo", line, 2, 3)
      else
        vim.api.nvim_buf_add_highlight(buf, 0, "NonText", line, 2, 3)
      end
      vim.api.nvim_buf_add_highlight(buf, 0, "Function", line, 5, 5 + #skill.name)
    end
  else
    local catalog = skill_repo.search(search_query)
    for i, skill in ipairs(catalog) do
      local line = header_lines + i - 1
      local is_installed = skill_repo.is_installed(skill.name)
      if is_installed then
        vim.api.nvim_buf_add_highlight(buf, 0, "DiagnosticInfo", line, 2, 3)
      else
        vim.api.nvim_buf_add_highlight(buf, 0, "NonText", line, 2, 3)
      end
      vim.api.nvim_buf_add_highlight(buf, 0, "Function", line, 5, 5 + #skill.name)
    end
    -- External sources section
    vim.api.nvim_buf_add_highlight(buf, 0, "Comment", #catalog + header_lines + 1, 0, -1)
    vim.api.nvim_buf_add_highlight(buf, 0, "Comment", #catalog + header_lines + 2, 0, -1)
    vim.api.nvim_buf_add_highlight(buf, 0, "Comment", #catalog + header_lines + 3, 0, -1)
    vim.api.nvim_buf_add_highlight(buf, 0, "Comment", #catalog + header_lines + 4, 0, -1)
  end
end

-- ─── Actions ────────────────────────────────────────────────────────────────

local function switch_tab(buf)
  if current_tab == "installed" then
    current_tab = "marketplace"
  else
    current_tab = "installed"
  end
  M.render(buf)
end

local function toggle_installed_skill(buf)
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local skills = skills_module.get_skills()
  local skill = get_item_at_line(skills, line)
  if not skill then return end

  skills_module.toggle(skill.name)
  M.render(buf)
end

local function uninstall_skill(buf)
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local skills = skills_module.get_skills()
  local skill = get_item_at_line(skills, line)
  if not skill then return end

  if vim.fn.confirm("Uninstall skill: " .. skill.name .. "?", "&Yes\n&No") == 1 then
    skill_repo.uninstall(skill.name, function(success)
      if success then
        M.render(buf)
      end
    end)
  end
end

local function install_marketplace_skill(buf)
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local catalog = skill_repo.search(search_query)
  local skill = get_item_at_line(catalog, line)
  if not skill then return end

  if skill_repo.is_installed(skill.name) then
    vim.notify("Skill already installed: " .. skill.name, vim.log.levels.WARN)
    return
  end

  install_buf_ref = buf
  skill_repo.install(skill, function(success, err)
    if success then
      M.render(buf)
    else
      vim.notify("Failed to install " .. skill.name .. ": " .. (err or "unknown error"), vim.log.levels.ERROR)
    end
  end)
end

local function show_description(buf)
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local item

  if current_tab == "installed" then
    local skills = skills_module.get_skills()
    item = get_item_at_line(skills, line)
  else
    local catalog = skill_repo.search(search_query)
    item = get_item_at_line(catalog, line)
  end

  if item then
    local info = item.description or "Sin descripción"
    if item.author then
      info = info .. "\nAuthor: " .. item.author
    end
    if item.repo then
      info = info .. "\nRepo: " .. item.repo
    end
    vim.notify(info, vim.log.levels.INFO, { title = item.name })
  end
end

local function open_skill_doc(buf)
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local skills = skills_module.get_skills()
  local skill = get_item_at_line(skills, line)
  if skill and skill.path then
    vim.cmd("split " .. vim.fn.fnameescape(skill.path))
  end
end

local function start_search(buf)
  local query = vim.fn.input("Search skills: ")
  if query then
    search_query = query
    current_tab = "marketplace"
    M.render(buf)
  end
end

local function clear_search(buf)
  search_query = ""
  M.render(buf)
end

local function install_from_url(buf)
  local url = vim.fn.input("Install skill from GitHub URL (user/repo/path): ")
  if not url or url == "" then return end

  install_buf_ref = buf
  skill_repo.install_from_url(url, function(success, err)
    if success then
      M.render(buf)
    else
      vim.notify("Failed to install from URL: " .. (err or "unknown error"), vim.log.levels.ERROR)
    end
  end)
end

-- ─── Open Window ────────────────────────────────────────────────────────────

function M.open()
  current_tab = "installed"
  search_query = ""

  local width = 80
  local height = math.min(30, vim.o.lines - 8)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, "Skill Market")
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "skill-market"

  M.render(buf)

  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " Skill Market ",
    title_pos = "center",
  })

  install_buf_ref = buf
  install_win_ref = win

  -- Common keymaps
  vim.keymap.set("n", "<Tab>", function() switch_tab(buf) end, { buffer = buf, desc = "Switch tab" })
  vim.keymap.set("n", "s", function()
    if current_tab == "installed" then toggle_installed_skill(buf)
    else install_marketplace_skill(buf) end
  end, { buffer = buf, desc = "Toggle/Install skill" })
  vim.keymap.set("n", "K", function() show_description(buf) end, { buffer = buf, desc = "Show description" })
  vim.keymap.set("n", "R", function() M.render(buf) end, { buffer = buf, desc = "Refresh" })
  vim.keymap.set("n", "q", function() vim.api.nvim_win_close(win, true) end, { buffer = buf, desc = "Close" })
  vim.keymap.set("n", "<Esc>", function()
    if search_query ~= "" then
      clear_search(buf)
    else
      vim.api.nvim_win_close(win, true)
    end
  end, { buffer = buf, desc = "Clear search / Close" })

  -- Installed tab keymaps
  vim.keymap.set("n", "<CR>", function()
    if current_tab == "installed" then
      toggle_installed_skill(buf)
    else
      install_marketplace_skill(buf)
    end
  end, { buffer = buf, desc = "Toggle/Install skill" })

  vim.keymap.set("n", "d", function() open_skill_doc(buf) end, { buffer = buf, desc = "Open SKILL.md" })
  vim.keymap.set("n", "x", function() uninstall_skill(buf) end, { buffer = buf, desc = "Uninstall skill" })

  -- Marketplace tab keymaps
  vim.keymap.set("n", "/", function() start_search(buf) end, { buffer = buf, desc = "Search skills" })
  vim.keymap.set("n", "U", function() install_from_url(buf) end, { buffer = buf, desc = "Install from URL" })

  vim.keymap.set("n", "?", function() M.show_help(buf) end, { buffer = buf, desc = "Toggle help" })

  vim.api.nvim_set_current_win(win)
end

-- ─── Help ───────────────────────────────────────────────────────────────────

function M.show_help(buf)
  local help_lines = {
    "Skill Market — Help",
    "",
    "Tabs:",
    "  Tab         Switch between Installed and Marketplace",
    "",
    "Installed Tab:",
    "  <CR> / s    Toggle skill (enable/disable)",
    "  d           Open SKILL.md documentation",
    "  x           Uninstall skill (remove from disk)",
    "  K           Show skill description",
    "",
    "Marketplace Tab:",
    "  <CR> / s    Install skill from GitHub",
    "  /           Search skills by name/description",
    "  U           Install from custom GitHub URL",
    "  K           Show skill details",
    "  Esc         Clear search query",
    "",
    "Common:",
    "  R           Refresh",
    "  ?           Toggle this help",
    "  q           Close window",
    "",
    "External Sources:",
    "  claudemarket.ai  - Browse and find skills",
    "  mcpservers.org   - MCP servers and skills directory",
    "  awesomeskill.ai  - Awesome skills marketplace",
    "",
    "Press any key to close",
  }

  vim.api.nvim_buf_set_keymap(buf, "n", "", "", {
    callback = function()
      vim.api.nvim_buf_del_keymap(buf, "n", "")
      M.render(buf)
    end,
    once = true,
  })

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, help_lines)
  vim.bo[buf].modifiable = false
end

return M
