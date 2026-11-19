-- Requirements Panel — Interactive panel for planning and managing requirements
-- Three tabs: Requirements, Tasks, References
-- Integrates with agent-tasks.lua for task creation with RF/RNF prefixes
--
-- Usage: require("lenn.requirements-panel").open()

local M = {}
local nf = require("lenn.icons")
local tasks = require("lenn.agent-tasks")

-- ─── State ──────────────────────────────────────────────────────────────────
local current_tab = "requirements"  -- "requirements", "tasks", or "references"
local req_buf_ref = nil             -- reference to buffer for callbacks
local req_win_ref = nil             -- reference to window for callbacks
local requirements_dir = vim.fn.expand("~/requirements")
local panel_mode = "split"          -- "split" (right sidebar) or "float"
local req_width = 48                -- default width for split mode

-- ─── Icons ──────────────────────────────────────────────────────────────────
local icons = {
  functional = nf.check,
  nonfunctional = nf.circle,
  task = nf.dot,
  file = nf.file_default,
  folder = nf.folder_open,
  search = nf.search,
  external = nf.external,
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

local function ensure_requirements_dir()
  if vim.fn.isdirectory(requirements_dir) == 0 then
    vim.fn.mkdir(requirements_dir, "p")
  end
end

-- Scan requirements directory for .md and .norg files
local function scan_requirements()
  ensure_requirements_dir()
  local results = {}
  local cmd = string.format("find %s -maxdepth 2 -type f \\( -name '*.md' -o -name '*.norg' \\) 2>/dev/null",
    vim.fn.shellescape(requirements_dir))
  local handle = io.popen(cmd)
  if handle then
    for line in handle:lines() do
      local rel_path = line:sub(#requirements_dir + 2)
      local name = vim.fn.fnamemodify(line, ":t")
      local ext = vim.fn.fnamemodify(line, ":e")
      local is_norg = (ext == "norg")
      table.insert(results, {
        path = line,
        rel_path = rel_path,
        name = name,
        is_norg = is_norg,
        ext = ext,
      })
    end
    handle:close()
  end
  table.sort(results, function(a, b) return a.path < b.path end)
  return results
end

-- Scan for reference files (PDF, Word, etc.)
local function scan_references()
  ensure_requirements_dir()
  local results = {}
  local cmd = string.format("find %s -maxdepth 2 -type f \\( -name '*.pdf' -o -name '*.doc' -o -name '*.docx' -o -name '*.txt' \\) 2>/dev/null",
    vim.fn.shellescape(requirements_dir))
  local handle = io.popen(cmd)
  if handle then
    for line in handle:lines() do
      local name = vim.fn.fnamemodify(line, ":t")
      local ext = vim.fn.fnamemodify(line, ":e")
      table.insert(results, {
        path = line,
        name = name,
        ext = ext,
      })
    end
    handle:close()
  end
  table.sort(results, function(a, b) return a.path < b.path end)
  return results
end

-- Extract RF/RNF prefixes from a file
local function extract_requirement_ids(filepath)
  local ids = {}
  local ok, lines = pcall(vim.fn.readfile, filepath)
  if not ok or #lines == 0 then
    return ids
  end
  for _, line in ipairs(lines) do
    -- Match patterns like RF001, RNF001, [RF001], [RNF001]
    local match = line:match("%[?(R[FN]?%d+)%]?")
    if match then
      table.insert(ids, match)
    end
  end
  return ids
end

-- Get tasks linked to requirements (by prefix in title)
local function get_linked_tasks()
  local cwd = vim.fn.getcwd()
  local local_tasks = tasks.local_tasks(cwd)
  local linked = {}
  for _, task in ipairs(local_tasks) do
    local prefix = task.title:match("^%[(R[FN]?%d+)%]")
    if prefix then
      table.insert(linked, {
        task = task,
        prefix = prefix,
      })
    end
  end
  return linked
end

-- ─── Tab Rendering ──────────────────────────────────────────────────────────

local function render_tab_bar(tab)
  local tabs = { "Requirements", "Tasks", "References" }
  local lines = {}
  table.insert(lines, "  ┌──────────────┬─────────┬────────────┐")
  local tab_line = "  │"
  for _, t in ipairs(tabs) do
    local label = " " .. t .. " "
    local padding = 14 - #label
    tab_line = tab_line .. label .. string.rep(" ", padding) .. "│"
  end
  table.insert(lines, tab_line)
  table.insert(lines, "  └──────────────┴─────────┴────────────┘")
  return lines
end

-- ─── Requirements Tab ───────────────────────────────────────────────────────

local function render_requirements_tab()
  local files = scan_requirements()
  local lines = {}

  -- Tab bar
  vim.list_extend(lines, render_tab_bar("requirements"))

  -- Header with Sommerville phase title (English)
  table.insert(lines, "  ╔══════════════════════════════════════════════════════════╗")
  table.insert(lines, "  ║  REQUIREMENTS ELICITATION - Sommerville Ch. 4           ║")
  table.insert(lines, "  ║  Discovering, eliciting, and defining stakeholder needs ║")
  table.insert(lines, "  ╚══════════════════════════════════════════════════════════╝")
  table.insert(lines, string.format("  Files: %d  (Tab switch  ·  <CR> open  ·  n new  ·  E edit  ·  D delete  ·  R refresh  ·  q close)", #files))
  table.insert(lines, "")

  if #files == 0 then
    table.insert(lines, "  No requirement files found in ~/requirements/")
    table.insert(lines, "")
    table.insert(lines, "  Press n to create a new requirement file.")
  else
    for _, file in ipairs(files) do
      local icon = file.is_norg and icons.folder or icons.file
      local ext_tag = file.is_norg and " [norg]" or " [md]"
      table.insert(lines, string.format("  %s %s%s", icon, file.name, ext_tag))
    end
  end

  table.insert(lines, "")
  return lines, files
end

-- ─── Tasks Tab ──────────────────────────────────────────────────────────────

local function render_tasks_tab()
  local linked = get_linked_tasks()
  local lines = {}

  -- Tab bar
  vim.list_extend(lines, render_tab_bar("tasks"))

  -- Header
  table.insert(lines, string.format("  Linked tasks: %d  (Tab switch  ·  <CR> toggle  ·  c complete  ·  f fail  ·  a archive  ·  R refresh  ·  q close)", #linked))
  table.insert(lines, "")

  if #linked == 0 then
    table.insert(lines, "  No tasks linked to requirements yet.")
    table.insert(lines, "")
    table.insert(lines, "  Tasks created with [RF001] or [RNF001] prefix will appear here.")
  else
    -- Group by prefix
    local groups = {}
    for _, item in ipairs(linked) do
      if not groups[item.prefix] then
        groups[item.prefix] = {}
      end
      table.insert(groups[item.prefix], item)
    end

    for prefix, items in pairs(groups) do
      table.insert(lines, string.format("  ── %s (%d tasks) ──", prefix, #items))
      for _, item in ipairs(items) do
        local status_icon
        if item.task.done then
          status_icon = icons.functional
        elseif item.task.status == "in_progress" then
          status_icon = icons.search
        elseif item.task.status == "failed" then
          status_icon = icons.nonfunctional
        else
          status_icon = icons.task
        end
        local title = item.task.title:gsub("^%[" .. prefix .. "%] ", "")
        table.insert(lines, string.format("  [%s] %s", status_icon, title))
      end
      table.insert(lines, "")
    end
  end

  table.insert(lines, "")
  return lines, linked
end

-- ─── References Tab ─────────────────────────────────────────────────────────

local function render_references_tab()
  local refs = scan_references()
  local lines = {}

  -- Tab bar
  vim.list_extend(lines, render_tab_bar("references"))

  -- Header
  table.insert(lines, string.format("  References: %d  (Tab switch  ·  <CR> open  ·  A attach  ·  D delete  ·  R refresh  ·  q close)", #refs))
  table.insert(lines, "")

  if #refs == 0 then
    table.insert(lines, "  No reference files found.")
    table.insert(lines, "")
    table.insert(lines, "  Press A to attach a reference file (PDF, Word, etc.).")
  else
    for _, ref in ipairs(refs) do
      local icon = icons.external
      table.insert(lines, string.format("  %s %s", icon, ref.name))
    end
  end

  table.insert(lines, "")
  return lines, refs
end

-- ─── Main Render ────────────────────────────────────────────────────────────

function M.render(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return end

  local lines
  if current_tab == "requirements" then
    lines = render_requirements_tab()
  elseif current_tab == "tasks" then
    lines = render_tasks_tab()
  else
    lines = render_references_tab()
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

  -- Sommerville phase title box (lines 3-5, only in requirements tab)
  if current_tab == "requirements" then
    vim.api.nvim_buf_add_highlight(buf, 0, "Title", 3, 0, -1)
    vim.api.nvim_buf_add_highlight(buf, 0, "Title", 4, 0, -1)
    vim.api.nvim_buf_add_highlight(buf, 0, "Title", 5, 0, -1)
    -- Keymaps line
    vim.api.nvim_buf_add_highlight(buf, 0, "Comment", 6, 0, -1)
    -- Item lines start at line 7 (0-indexed)
    local header_lines = 7
  else
    -- Keymaps line
    vim.api.nvim_buf_add_highlight(buf, 0, "Comment", 3, 0, -1)
    -- Item lines start at line 4 (0-indexed)
    local header_lines = 4
  end

  if current_tab == "requirements" then
    local files = scan_requirements()
    for i = 1, #files do
      local line = header_lines + i - 1
      vim.api.nvim_buf_add_highlight(buf, 0, "Function", line, 4, -1)
    end
  elseif current_tab == "tasks" then
    local linked = get_linked_tasks()
    for i = 1, #linked do
      local line = header_lines + i - 1
      local item = linked[i]
      if item.task.done then
        vim.api.nvim_buf_add_highlight(buf, 0, "DiagnosticOk", line, 2, 3)
      elseif item.task.status == "in_progress" then
        vim.api.nvim_buf_add_highlight(buf, 0, "DiagnosticWarn", line, 2, 3)
      elseif item.task.status == "failed" then
        vim.api.nvim_buf_add_highlight(buf, 0, "DiagnosticError", line, 2, 3)
      else
        vim.api.nvim_buf_add_highlight(buf, 0, "NonText", line, 2, 3)
      end
      vim.api.nvim_buf_add_highlight(buf, 0, "Function", line, 5, -1)
    end
  else
    local refs = scan_references()
    for i = 1, #refs do
      local line = header_lines + i - 1
      vim.api.nvim_buf_add_highlight(buf, 0, "Function", line, 4, -1)
    end
  end
end

-- ─── Actions ────────────────────────────────────────────────────────────────

local function switch_tab(buf)
  if current_tab == "requirements" then
    current_tab = "tasks"
  elseif current_tab == "tasks" then
    current_tab = "references"
  else
    current_tab = "requirements"
  end
  M.render(buf)
end

local function open_file(buf)
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local files = scan_requirements()
  local file = get_item_at_line(files, line)
  if file then
    vim.cmd("edit " .. vim.fn.fnameescape(file.path))
  end
end

local function new_requirement_file(buf)
  local name = vim.fn.input("Requirement file name (without extension): ")
  if not name or name == "" then return end

  ensure_requirements_dir()
  local ext = vim.fn.input("Format (md/norg) [md]: ")
  if not ext or ext == "" then ext = "md" end
  ext = ext:lower()
  if ext ~= "md" and ext ~= "norg" then ext = "md" end

  local filepath = requirements_dir .. "/" .. name .. "." .. ext
  local content

  if ext == "norg" then
    content = {
      "= " .. name,
      "",
      "* Status:: draft",
      "",
      "== Functional Requirements",
      "",
      "== Non-Functional Requirements",
      "",
      "== Actors",
      "",
      "== Acceptance Criteria",
      "",
      "== References",
    }
  else
    content = {
      "# " .. name,
      "",
      "## Functional Requirements (RF)",
      "",
      "## Non-Functional Requirements (RNF)",
      "",
      "## Actors",
      "",
      "## Acceptance Criteria",
      "",
      "## References",
    }
  end

  vim.fn.writefile(content, filepath)
  M.render(buf)
  vim.notify("Created: " .. filepath, vim.log.levels.INFO)
end

local function edit_requirement(buf)
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local files = scan_requirements()
  local file = get_item_at_line(files, line)
  if file then
    vim.cmd("vsplit " .. vim.fn.fnameescape(file.path))
  end
end

local function delete_requirement(buf)
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local files = scan_requirements()
  local file = get_item_at_line(files, line)
  if file then
    if vim.fn.confirm("Delete: " .. file.name .. "?", "&Yes\n&No") == 1 then
      vim.fn.delete(file.path)
      M.render(buf)
      vim.notify("Deleted: " .. file.name, vim.log.levels.INFO)
    end
  end
end

local function toggle_task(buf)
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local linked = get_linked_tasks()
  local item = get_item_at_line(linked, line)
  if item then
    local cwd = vim.fn.getcwd()
    if item.task.done then
      tasks.update_local(cwd, item.task.id, { status = "pending", done = false })
    else
      tasks.update_local(cwd, item.task.id, { status = "completed", done = true })
    end
    M.render(buf)
  end
end

local function complete_task(buf)
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local linked = get_linked_tasks()
  local item = get_item_at_line(linked, line)
  if item then
    tasks.update_local(vim.fn.getcwd(), item.task.id, { status = "completed", done = true })
    M.render(buf)
  end
end

local function fail_task(buf)
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local linked = get_linked_tasks()
  local item = get_item_at_line(linked, line)
  if item then
    tasks.update_local(vim.fn.getcwd(), item.task.id, { status = "failed" })
    M.render(buf)
  end
end

local function archive_task(buf)
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local linked = get_linked_tasks()
  local item = get_item_at_line(linked, line)
  if item then
    tasks.update_local(vim.fn.getcwd(), item.task.id, { status = "archived" })
    M.render(buf)
  end
end

local function open_reference(buf)
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local refs = scan_references()
  local ref = get_item_at_line(refs, line)
  if ref then
    if ref.ext == "pdf" then
      vim.notify("Opening PDF: " .. ref.name .. " (use your system PDF viewer)", vim.log.levels.INFO)
    else
      vim.cmd("edit " .. vim.fn.fnameescape(ref.path))
    end
  end
end

local function attach_reference(buf)
  local path = vim.fn.input("Path to reference file: ")
  if not path or path == "" then return end
  if vim.fn.filereadable(path) == 0 then
    vim.notify("File not found: " .. path, vim.log.levels.ERROR)
    return
  end

  ensure_requirements_dir()
  local dest = requirements_dir .. "/references/"
  if vim.fn.isdirectory(dest) == 0 then
    vim.fn.mkdir(dest, "p")
  end

  local name = vim.fn.fnamemodify(path, ":t")
  local final_dest = dest .. name
  if vim.fn.copy(path, final_dest) == 0 then
    M.render(buf)
    vim.notify("Attached: " .. name, vim.log.levels.INFO)
  else
    vim.notify("Failed to copy file", vim.log.levels.ERROR)
  end
end

local function delete_reference(buf)
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local refs = scan_references()
  local ref = get_item_at_line(refs, line)
  if ref then
    if vim.fn.confirm("Delete: " .. ref.name .. "?", "&Yes\n&No") == 1 then
      vim.fn.delete(ref.path)
      M.render(buf)
      vim.notify("Deleted: " .. ref.name, vim.log.levels.INFO)
    end
  end
end

-- ─── Open Window ────────────────────────────────────────────────────────────

local function find_editor_window(preferred)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local config = vim.api.nvim_win_get_config(win)
    if config.relative ~= "" then goto continue end
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].buftype == "" and vim.bo[buf].filetype ~= "neo-tree" then
      return win
    end
    ::continue::
  end
  return preferred
end

local function open_split()
  local focus_win = vim.api.nvim_get_current_win()
  local base_win = find_editor_window(focus_win) or focus_win

  vim.api.nvim_set_current_win(base_win)
  vim.cmd("rightbelow vsplit")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_width(win, req_width)
  vim.wo[win].winfixwidth = true
  vim.wo[win].signcolumn = "no"
  vim.wo[win].foldcolumn = "0"
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].cursorline = true
  vim.wo[win].cursorlineopt = "line"

  if vim.api.nvim_win_is_valid(focus_win) then
    vim.api.nvim_set_current_win(focus_win)
  end

  return win
end

local function open_float()
  local width = 80
  local height = math.min(30, vim.o.lines - 8)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local win = vim.api.nvim_open_win(req_buf_ref, true, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " Requirements Panel ",
    title_pos = "center",
  })

  return win
end

local function setup_keymaps(buf, win)
  -- Common keymaps
  vim.keymap.set("n", "<Tab>", function() switch_tab(buf) end, { buffer = buf, desc = "Switch tab" })
  vim.keymap.set("n", "R", function() M.render(buf) end, { buffer = buf, desc = "Refresh" })
  vim.keymap.set("n", "q", function()
    if panel_mode == "float" then
      vim.api.nvim_win_close(win, true)
    else
      vim.api.nvim_win_close(win, true)
    end
  end, { buffer = buf, desc = "Close" })

  -- Toggle panel mode
  vim.keymap.set("n", "F", function()
    M.toggle_mode()
  end, { buffer = buf, desc = "Toggle float/split mode" })

  -- Requirements tab keymaps
  vim.keymap.set("n", "<CR>", function()
    if current_tab == "requirements" then
      open_file(buf)
    elseif current_tab == "tasks" then
      toggle_task(buf)
    else
      open_reference(buf)
    end
  end, { buffer = buf, desc = "Open/Toggle" })

  vim.keymap.set("n", "n", function() new_requirement_file(buf) end, { buffer = buf, desc = "New requirement file" })
  vim.keymap.set("n", "E", function() edit_requirement(buf) end, { buffer = buf, desc = "Edit in split" })
  vim.keymap.set("n", "D", function()
    if current_tab == "requirements" then
      delete_requirement(buf)
    else
      delete_reference(buf)
    end
  end, { buffer = buf, desc = "Delete" })

  -- Tasks tab keymaps
  vim.keymap.set("n", "c", function() complete_task(buf) end, { buffer = buf, desc = "Complete task" })
  vim.keymap.set("n", "f", function() fail_task(buf) end, { buffer = buf, desc = "Fail task" })
  vim.keymap.set("n", "a", function() archive_task(buf) end, { buffer = buf, desc = "Archive task" })

  -- References tab keymaps
  vim.keymap.set("n", "A", function() attach_reference(buf) end, { buffer = buf, desc = "Attach reference" })

  -- Close on Escape
  vim.keymap.set("n", "<Esc>", function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf, desc = "Close" })
end

function M.open(opts)
  opts = opts or {}
  current_tab = "requirements"

  -- Determine mode: explicit option > saved state > default (split)
  local mode = opts.float and "float" or (opts.mode or panel_mode)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, "Requirements Panel")
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "requirements-panel"

  req_buf_ref = buf
  M.render(buf)

  local win
  if mode == "float" then
    win = open_float()
  else
    win = open_split()
  end

  req_win_ref = win
  panel_mode = mode

  setup_keymaps(buf, win)

  -- Focus the panel window
  vim.api.nvim_set_current_win(win)
end

-- Toggle between split and float mode
function M.toggle_mode()
  local buf = req_buf_ref
  local win = req_win_ref
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  if not win or not vim.api.nvim_win_is_valid(win) then return end

  local old_mode = panel_mode
  if panel_mode == "split" then
    panel_mode = "float"
  else
    panel_mode = "split"
  end

  -- Close current window
  vim.api.nvim_win_close(win, true)

  -- Reopen in the new mode
  local focus_win = vim.api.nvim_get_current_win()
  local new_win
  if panel_mode == "float" then
    new_win = open_float()
  else
    new_win = open_split()
  end

  req_win_ref = new_win
  setup_keymaps(buf, new_win)
  vim.api.nvim_set_current_win(new_win)

  local mode_name = panel_mode == "float" and "Float" or "Split (sidebar)"
  vim.notify("Requirements panel: " .. mode_name, vim.log.levels.INFO)
end

function M.toggle()
  -- Check if panel is already open
  if req_buf_ref and vim.api.nvim_buf_is_valid(req_buf_ref) then
    if req_win_ref and vim.api.nvim_win_is_valid(req_win_ref) then
      vim.api.nvim_win_close(req_win_ref, true)
      req_win_ref = nil
      return
    end
  end
  M.open()
end

function M.get_win()
  return req_win_ref
end

function M.get_buf()
  return req_buf_ref
end

return M
