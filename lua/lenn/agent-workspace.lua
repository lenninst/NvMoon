-- Agent Workspace — Zed-style unified agent interface
-- Three panels on the left side:
--   | Threads+Skills | Agent | [code buffers] | Explorer |
-- Threads+Skills is a vertical split: Threads (top, 3/4) + Skills (bottom, 1/4)
-- Panels are created manually with vsplit/split, not via Edgy.
--
-- Usage: require("lenn.agent-workspace").toggle()

local M = {}
local nf = require("lenn.icons")

-- ─── State ──────────────────────────────────────────────────────────────────

local threads_buf = nil       -- threads list buffer (persisted across toggles)
local skills_buf = nil        -- skills list buffer (persisted across toggles)
local keymaps_buf = nil       -- keymaps help buffer (persisted across toggles)
local agent_buf = nil         -- agent selector buffer (persisted across toggles)
local current_term = nil      -- current toggleterm instance
local current_provider = nil  -- current provider name
local current_thread_id = nil -- current thread/session ID
local new_session_sequence = 0
local selected_agent_tab = "providers"
local direct_agent_sessions = {}
local agent_tabs_cache = {}
local render_agent_tabs
local update_threads_winbar
local render_keymaps_panel
local ensure_cursor_on_content
local show_task_details_float
local get_running_project_sessions
local agent_tab_numbers_visible = false
local agent_tab_number_generation = 0
local last_agent_tab_key_ms = 0
local project_file_stats
local open_task_changes
local active_threads_tab = "threads"
local active_task_pill = "local"  -- pill tab inside Tasks: "local" or "github"
local task_project_cwd = nil
local task_row_map = {}
local task_load_sequence = 0
local task_issues = {}
local task_issue_message = nil
local threads_data = {}
local launch_in_project
local task_folds = {}                 -- fold state per category: { pending=false, in_progress=false, ... }
local task_details_float = nil        -- floating window for task details (K)
local task_details_files = {}         -- maps line_idx (1-based) → file_path in details float

-- Window IDs for our panels (so we can hide/show them on toggle)
local threads_win = nil
local skills_win = nil
local keymaps_win = nil
local agent_win = nil

-- Panel sizes (computed by calculate_panel_widths from the screen size)
local threads_width = 50
local agent_width = 60
local explorer_width = 30
local requirements_width = 48
local skills_height_ratio = 0.18  -- Skills occupies 18% of left panel height
local keymaps_height = 15         -- Help panel max height

-- Every panel scales with the screen but stays within [min, max] columns,
-- so sizes are the same on every open and never collapse or take over.
-- `floor` is the hard minimum used only when the screen is too small for `min`.
local panel_limits = {
  threads = { ratio = 0.18, min = 28, max = 42, floor = 20 },
  explorer = { ratio = 0.15, min = 24, max = 34, floor = 18 },
  agent = { ratio = 0.32, min = 45, max = 90, floor = 30 },
  requirements = { ratio = 0.28, min = 36, max = 70, floor = 24 },
}
local editor_min_width = 60       -- code buffers keep at least this much room

-- Track whether panels are currently visible
local panels_visible = false

-- ─── Workspace Modes ────────────────────────────────────────────────────────
-- Like DaVinci Resolve pages: each mode controls which panels are visible
-- and their layout priorities.
--
-- Modes:
--   "agent"  — Only agent panels (threads+skills+keymaps+agent). All buffers
--              are minimized. Explorer stays available. Panels take full priority.
--   "edit"   — Explorer + buffers take priority. Agent panel is a narrow
--              column between the code buffers and the explorer.
--   "full"   — All panels visible: threads+skills+keymaps+agent + explorer.
--              This is the default complete layout.
--   "plan"   — Requirements panel takes priority + agent panel for ideas.
--              Task panel visible. No code buffers focus.

local current_workspace_mode = "full"  -- default mode

local workspace_modes = {
  agent = {
    name = "Agent",
    icon = nf.mode_agent,
    desc = "Only agent panels + explorer, buffers minimized",
  },
  edit = {
    name = "Edit",
    icon = nf.mode_edit,
    desc = "Explorer + buffers priority, agent beside explorer",
  },
  full = {
    name = "Full",
    icon = nf.mode_full,
    desc = "All panels visible",
  },
  plan = {
    name = "Plan",
    icon = nf.mode_plan,
    desc = "Requirements + tasks + agent for ideas",
  },
}

-- Requirements panel window reference (managed by workspace modes)
local req_win = nil
local req_buf = nil

-- Planner panel window reference (only shown in "plan" mode)
local planner_win = nil
local planner_buf = nil

-- Agent window inside explorer for "edit" mode (agent panel within NeoTree area)
local agent_explorer_win = nil
local agent_explorer_buf = nil

-- Minimized editor windows for "agent" mode (buffers hidden, restored on mode switch)
local minimized_editor_bufs = {}

-- Preserve the agent terminal buffer across workspace mode transitions.
-- When switching modes, the terminal buffer is saved here so the same provider
-- panel is reused instead of creating a new one.
local saved_agent_term_buf = nil

-- ─── Mode Switching ─────────────────────────────────────────────────────────

-- Forward declarations for functions defined later in the file
local hide_panels
local open_panels
local has_hidden_windows
local find_editor_window
local render_agent_panel
local is_workspace_panel
local apply_agent_style
local apply_neo_tree_style
local create_agent_split_in_explorer
local create_planner_file
local restore_agent_term_buf
local resize_panels
local calculate_panel_widths

local function close_agent_in_explorer()
  if agent_explorer_win and vim.api.nvim_win_is_valid(agent_explorer_win) then
    -- Save the terminal buffer so it can be restored in the new workspace panel
    local buf = vim.api.nvim_win_get_buf(agent_explorer_win)
    pcall(vim.api.nvim_win_close, agent_explorer_win, true)
    agent_explorer_win = nil
    if buf and vim.api.nvim_buf_is_valid(buf) and vim.b[buf].agent_panel then
      saved_agent_term_buf = buf
    else
      agent_explorer_buf = nil
    end
  else
    agent_explorer_buf = nil
  end
end

-- Find the NeoTree window if it's open
local function find_neo_tree_win()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].filetype == "neo-tree" then
      return win
    end
  end
  return nil
end

local function open_agent_in_explorer()
  -- Don't close if already open and valid
  if agent_explorer_win and vim.api.nvim_win_is_valid(agent_explorer_win) then
    return
  end
  close_agent_in_explorer()

  -- Open NeoTree if not already open
  local neo_tree_win = find_neo_tree_win()
  if not neo_tree_win then
    pcall(vim.cmd.Neotree, { args = { "focus" } })
    -- Give NeoTree time to open
    vim.schedule(function()
      neo_tree_win = find_neo_tree_win()
      if not neo_tree_win then
        return
      end
      create_agent_split_in_explorer(neo_tree_win)
    end)
    return
  end

  create_agent_split_in_explorer(neo_tree_win)
end

create_agent_split_in_explorer = function(neo_tree_win)
  if not neo_tree_win or not vim.api.nvim_win_is_valid(neo_tree_win) then
    return
  end

  -- Set up the agent buffer
  agent_explorer_buf = M.ensure_agent_buf()

  -- Full-height column on the far left: | Agent | code | Explorer |
  -- (Edgy owns the explorer column, so the agent can't live below NeoTree.)
  calculate_panel_widths()
  agent_explorer_win = vim.api.nvim_open_win(agent_explorer_buf, false, {
    split = "left",
    win = -1,
    width = agent_width,
  })

  -- Style the window to match NeoTree
  vim.wo[agent_explorer_win].signcolumn = "no"
  vim.wo[agent_explorer_win].foldcolumn = "0"
  vim.wo[agent_explorer_win].number = false
  vim.wo[agent_explorer_win].relativenumber = false
  vim.wo[agent_explorer_win].cursorline = true
  vim.wo[agent_explorer_win].winfixwidth = true
  apply_neo_tree_style(agent_explorer_win, " Agent ")
  vim.schedule(resize_panels)

  -- Reuse the running agent terminal (the split may be created deferred)
  restore_agent_term_buf()

  -- Render the agent panel
  vim.schedule(function()
    if agent_explorer_win and vim.api.nvim_win_is_valid(agent_explorer_win) then
      render_agent_panel()
    end
  end)

  -- Add keymap to close the agent panel in explorer
  vim.keymap.set("n", "q", function()
    close_agent_in_explorer()
  end, { buffer = agent_explorer_buf, desc = "Close agent panel" })

  vim.keymap.set("n", "<Esc>", function()
    close_agent_in_explorer()
  end, { buffer = agent_explorer_buf, desc = "Close agent panel" })
end

local function close_requirements_panel()
  if req_win and vim.api.nvim_win_is_valid(req_win) then
    pcall(vim.api.nvim_win_close, req_win, true)
    req_win = nil
  end
  -- Don't delete req_buf if it was created by requirements-panel module
end

-- Close the planner panel (only shown in "plan" mode)
local function close_planner_panel()
  if planner_win and vim.api.nvim_win_is_valid(planner_win) then
    pcall(vim.api.nvim_win_close, planner_win, true)
    planner_win = nil
  end
  if planner_buf and vim.api.nvim_buf_is_valid(planner_buf) then
    pcall(vim.api.nvim_buf_delete, planner_buf, { force = true })
    planner_buf = nil
  end
end

-- Create the planner panel buffer content
local function create_planner_buf()
  if planner_buf and vim.api.nvim_buf_is_valid(planner_buf) then
    return planner_buf
  end

  planner_buf = vim.api.nvim_create_buf(false, true)
  local lines = {
    "  ╔══════════════════════════════════════════════════════════╗",
    "  ║                    PLANNER                               ║",
    "  ║  Create a planning document for your project             ║",
    "  ╚══════════════════════════════════════════════════════════╝",
    "",
    "  Select an option:",
    "    1. Create planner in Markdown format (.md)",
    "    2. Create planner in Norg format (.norg)",
    "    q. Close panel",
    "",
    "  Keymaps:",
    "    <CR> on line · Execute selection",
    "    q · Close panel",
  }
  vim.api.nvim_buf_set_lines(planner_buf, 0, -1, true, lines)
  vim.api.nvim_buf_set_option(planner_buf, "modifiable", false)
  vim.api.nvim_buf_set_option(planner_buf, "buftype", "nofile")
  vim.api.nvim_buf_set_option(planner_buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(planner_buf, "swapfile", false)

  -- Set up keymaps for the planner panel
  vim.keymap.set("n", "<CR>", function()
    local line = vim.api.nvim_get_current_line()
    if line:find("1%.") then
      create_planner_file("md")
    elseif line:find("2%.") then
      create_planner_file("norg")
    end
  end, { buffer = planner_buf, silent = true })

  vim.keymap.set("n", "q", function()
    close_planner_panel()
  end, { buffer = planner_buf, silent = true })

  return planner_buf
end

-- Create a planner file in the specified format
create_planner_file = function(format)
  local project_name = vim.fn.input("Project name [project]: ")
  if not project_name or project_name == "" then project_name = "project" end
  project_name = vim.fn.trim(project_name)

  local planner_dir = vim.fn.expand("~/requirements/planners")
  if vim.fn.isdirectory(planner_dir) == 0 then
    vim.fn.mkdir(planner_dir, "p")
  end

  local filename = project_name .. "-planner"
  local filepath = planner_dir .. "/" .. filename .. "." .. format

  if format == "norg" then
    local content = {
      "= " .. project_name .. " Planner",
      "",
      "* Status:: draft",
      "* Created:: " .. os.date("%Y-%m-%d"),
      "",
      "== Project Overview",
      "",
      "== Goals",
      "",
      "== Scope",
      "",
      "== Milestones",
      "",
      "== Risks",
      "",
      "== Resources",
      "",
      "== Timeline",
    }
    vim.fn.writefile(content, filepath)
  else
    local content = {
      "# " .. project_name .. " Planner",
      "",
      "## Project Overview",
      "",
      "## Goals",
      "",
      "## Scope",
      "",
      "## Milestones",
      "",
      "## Risks",
      "",
      "## Resources",
      "",
      "## Timeline",
    }
    vim.fn.writefile(content, filepath)
  end

  vim.notify("Created planner: " .. filepath, vim.log.levels.INFO)
  -- Open the created file
  vim.cmd("edit " .. filepath)
end

-- Open the planner panel
-- When horizontal=true (full mode), open as a horizontal split below buffers.
-- When horizontal=false (plan mode), open as a vertical split on the side.
local function open_planner_panel(horizontal)
  if planner_win and vim.api.nvim_win_is_valid(planner_win) then
    return
  end

  local buf = create_planner_buf()
  local focus_win = vim.api.nvim_get_current_win()

  -- Split from a code window: the first listed window may be NeoTree or a
  -- floating/terminal window, which leaves the planner as a full-height column.
  local base_win = find_editor_window(focus_win)
  if not base_win then
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if not is_workspace_panel(win) and win ~= req_win
        and vim.api.nvim_win_get_config(win).relative == ""
        and vim.bo[vim.api.nvim_win_get_buf(win)].filetype ~= "neo-tree" then
        base_win = win
        break
      end
    end
  end
  base_win = base_win or focus_win

  vim.api.nvim_set_current_win(base_win)
  if horizontal then
    vim.cmd("rightbelow split")
    planner_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(planner_win, buf)
    vim.wo[planner_win].winfixheight = true
  else
    vim.cmd("rightbelow vsplit")
    planner_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(planner_win, buf)
    vim.wo[planner_win].winfixwidth = false
  end
  vim.wo[planner_win].number = false
  vim.wo[planner_win].relativenumber = false
  vim.wo[planner_win].signcolumn = "no"

  -- Restore focus
  if vim.api.nvim_win_is_valid(focus_win) then
    vim.api.nvim_set_current_win(focus_win)
  end
end

local function open_requirements_panel()
  -- Use the requirements-panel module if available
  local ok, rp = pcall(require, "lenn.requirements-panel")
  if ok then
    -- Check if there are any requirement files; if not, offer to create a default one
    local req_dir = vim.fn.expand("~/requirements")
    if vim.fn.isdirectory(req_dir) == 0 then
      local answer = vim.fn.input("No requirements directory found. Create a default requirements document? (y/n): ")
      if answer:lower() == "y" then
        vim.fn.mkdir(req_dir, "p")
        local format = vim.fn.input("Document format (md/norg) [md]: ")
        if not format or format == "" then format = "md" end
        format = format:lower()
        if format ~= "md" and format ~= "norg" then format = "md" end

        local filename = "requirements"
        local filepath = req_dir .. "/" .. filename .. "." .. format

        if format == "norg" then
          local content = {
            "= Requirements",
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
          vim.fn.writefile(content, filepath)
        else
          local content = {
            "# Requirements",
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
          vim.fn.writefile(content, filepath)
        end
        vim.notify("Created default requirements: " .. filepath, vim.log.levels.INFO)
      end
    end

    -- Open in split mode on the right side
    pcall(function()
      rp.open({ mode = "split" })
      -- Track the window
      req_win = rp.get_win()
      req_buf = rp.get_buf()
    end)
  end
end

-- Restore the saved agent terminal buffer into the current agent window.
-- Called after opening panels in a new workspace mode so the same provider
-- panel is reused instead of creating a new one.
restore_agent_term_buf = function()
  if not saved_agent_term_buf or not vim.api.nvim_buf_is_valid(saved_agent_term_buf) then
    -- Fall back to the current session so it is reused instead of duplicated
    local buf = current_term and current_term.bufnr
    if not buf or not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    saved_agent_term_buf = buf
  end
  -- Try to restore in agent_win first
  if agent_win and vim.api.nvim_win_is_valid(agent_win) then
    vim.api.nvim_win_set_buf(agent_win, saved_agent_term_buf)
    saved_agent_term_buf = nil
    return
  end
  -- Fallback to agent_explorer_win
  if agent_explorer_win and vim.api.nvim_win_is_valid(agent_explorer_win) then
    vim.api.nvim_win_set_buf(agent_explorer_win, saved_agent_term_buf)
    saved_agent_term_buf = nil
    return
  end
end

-- Move a running agent terminal from agent_win to the edit mode explorer split.
-- This is called when switching from "agent"/"full" mode (where agents run
-- inside agent_win) to "edit" mode (where the agent appears in the explorer).
local function move_agent_win_to_explorer()
  if not agent_explorer_win or not vim.api.nvim_win_is_valid(agent_explorer_win) then
    return
  end

  -- Look for a running direct agent session whose buffer is still valid
  for i = #direct_agent_sessions, 1, -1 do
    local s = direct_agent_sessions[i]
    if s.running and s.bufnr and vim.api.nvim_buf_is_valid(s.bufnr) then
      -- Place the terminal buffer in the explorer split window
      vim.api.nvim_win_set_buf(agent_explorer_win, s.bufnr)
      current_term = s
      return
    end
  end

  -- Also check if agent_win still has a terminal buffer (agent_panel marker)
  if agent_win and vim.api.nvim_win_is_valid(agent_win) then
    local buf = vim.api.nvim_win_get_buf(agent_win)
    if buf and vim.api.nvim_buf_is_valid(buf) and vim.b[buf].agent_panel then
      vim.api.nvim_win_set_buf(agent_explorer_win, buf)
      return
    end
  end
end

-- Move any running ToggleTerm agent terminal into the agent panel window.
-- This is called when switching from "edit" mode (where agents run as ToggleTerm)
-- to "agent"/"full" mode (where agents run inside the agent_win panel).
local function move_toggleterm_to_agent_win()
  if not agent_win or not vim.api.nvim_win_is_valid(agent_win) then
    return
  end

  -- If agent_win already has a terminal buffer (restored by restore_agent_term_buf),
  -- do not look for ToggleTerm — the agent is already in place.
  local current_buf = vim.api.nvim_win_get_buf(agent_win)
  if current_buf and vim.api.nvim_buf_is_valid(current_buf) and vim.b[current_buf].agent_panel then
    return
  end

  local Terminal = require("toggleterm.terminal")
  local moved = false
  for _, t in ipairs(Terminal.get_all(true)) do
    if t:is_open() and t.bufnr and vim.api.nvim_buf_is_valid(t.bufnr) then
      local is_agent = vim.b[t.bufnr] and vim.b[t.bufnr].agent_panel
      if is_agent then
        -- Close the ToggleTerm window (hide it)
        if t.window and vim.api.nvim_win_is_valid(t.window) then
          pcall(vim.api.nvim_win_hide, t.window)
        end
        -- Place the terminal buffer into the agent panel window
        vim.api.nvim_win_set_buf(agent_win, t.bufnr)
        current_term = t
        vim.api.nvim_set_current_win(agent_win)
        vim.cmd.startinsert()
        moved = true
        -- Only move the first matching terminal
        break
      end
    end
  end
  if moved then
    render_agent_tabs()
    render_agent_panel()
  end
end

-- Minimize all editor buffer windows (hide them) so only agent panels and explorer are visible.
-- Hidden windows are closed by nvim_win_hide, so we remember their buffers instead.
local function minimize_editor_buffers()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.api.nvim_win_get_config(win).relative == ""
      and not is_workspace_panel(win)
      and vim.bo[buf].filetype ~= "neo-tree"
      and not vim.b[buf].agent_panel then
      if vim.bo[buf].buftype == "" and not vim.tbl_contains(minimized_editor_bufs, buf) then
        table.insert(minimized_editor_bufs, buf)
      end
      pcall(vim.api.nvim_win_hide, win)
    end
  end
end

-- Open a code window in the center column: right after the agent panel,
-- left of the explorer. Shows `buf`, or an empty buffer when nil.
local function open_center_window(buf)
  local anchor
  for _, win in ipairs({ agent_win, agent_explorer_win }) do
    if win and vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_config(win).relative == "" then
      anchor = win
    end
  end
  anchor = anchor or vim.api.nvim_get_current_win()

  vim.api.nvim_set_current_win(anchor)
  vim.cmd("rightbelow vsplit")
  local win = vim.api.nvim_get_current_win()
  if buf then
    vim.api.nvim_win_set_buf(win, buf)
  else
    vim.cmd.enew()
  end
  -- The split inherits the panel's window options; reset them for code
  vim.wo[win].winbar = ""
  vim.wo[win].winhighlight = ""
  vim.wo[win].signcolumn = "yes"
  vim.wo[win].winfixwidth = false
  vim.wo[win].winfixheight = false
  vim.wo[win].number = true
  vim.wo[win].relativenumber = true
  -- No file to show: use the start screen instead of a blank buffer
  if not buf then
    local ok, start_screen = pcall(require, "lenn.start-screen")
    if ok then start_screen.show(win) end
  end
  return win
end

-- Reopen an editor window with the most recent minimized buffer (or an empty one).
-- Must run while the agent panels still exist so there is a window to split from,
-- otherwise NeoTree could end up as the last window and quit Neovim.
local function restore_editor_buffers()
  local bufs = minimized_editor_bufs
  minimized_editor_bufs = {}
  if find_editor_window() then
    return
  end

  local buf
  for i = #bufs, 1, -1 do
    if vim.api.nvim_buf_is_valid(bufs[i]) then
      buf = bufs[i]
      break
    end
  end
  open_center_window(buf)
end

-- Close every window showing an agent buffer except `keep_win`, so switching
-- workspaces never leaves two agent panels on screen.
local function close_duplicate_agent_windows(keep_win)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if win ~= keep_win and vim.api.nvim_win_is_valid(win) then
      local buf = vim.api.nvim_win_get_buf(win)
      if buf == agent_buf or vim.b[buf].agent_panel then
        pcall(vim.api.nvim_win_close, win, false)
      end
    end
  end
end

-- Apply a workspace mode layout
-- True when every window the mode needs is still open. Closing a panel with
-- :q breaks the layout; re-selecting the same mode then rebuilds it.
local function workspace_layout_complete(mode)
  local function ok(win) return win and vim.api.nvim_win_is_valid(win) end
  local required = ({
    agent = { threads_win, skills_win, keymaps_win, agent_win, find_neo_tree_win() },
    edit = { agent_explorer_win, find_neo_tree_win() },
    full = { threads_win, skills_win, keymaps_win, agent_win, planner_win, find_neo_tree_win() },
    plan = { req_win, planner_win, agent_win },
  })[mode] or {}
  -- `required` may contain nils (holes), so walk the expected count explicitly
  local expected = ({ agent = 5, edit = 2, full = 6, plan = 3 })[mode] or 0
  for i = 1, expected do
    if not ok(required[i]) then return false end
  end
  return true
end

local function apply_workspace_mode(mode, opts)
  opts = opts or {}
  local skip_notify = opts.skip_notify or false

  local rebuilding = opts.force or false
  if mode == current_workspace_mode and not opts.force then
    if workspace_layout_complete(mode) then
      if not skip_notify then
        vim.notify("Workspace already complete: " .. workspace_modes[mode].name, vim.log.levels.INFO)
      end
      return
    end
    -- Same mode but some panel was closed: rebuild it from scratch
    rebuilding = true
  end

  -- Tear down the previous layout completely (saves the agent terminal and
  -- restores minimized buffers), so every mode reuses the same agent panel.
  hide_panels()

  current_workspace_mode = mode

  if mode == "agent" then
    -- | Threads+Tasks | Agent (center, expands) | Explorer |
    open_panels()
    -- Reuse the running agent terminal instead of opening a second panel
    restore_agent_term_buf()
    move_toggleterm_to_agent_win()
    -- File buffers are hidden while in agent mode
    minimize_editor_buffers()
    -- Explorer always visible (Edgy keeps it on the right)
    if not find_neo_tree_win() then
      pcall(vim.cmd, "Neotree show right")
    end

  elseif mode == "edit" then
    open_agent_in_explorer()
    -- Restore the saved agent terminal buffer into the explorer split
    restore_agent_term_buf()
    -- If an agent terminal was running in agent_win, move it to the explorer split
    move_agent_win_to_explorer()

  elseif mode == "full" then
    -- Show all panels
    open_panels()
    -- Restore the saved agent terminal buffer into the new panel
    restore_agent_term_buf()
    -- If a ToggleTerm agent terminal was running in edit mode, move it to the panel
    move_toggleterm_to_agent_win()
    -- Show planner panel below buffers (horizontal split)
    open_planner_panel(true)
    -- Explorer on the right, reopened if it was closed
    if not find_neo_tree_win() then
      pcall(vim.cmd, "Neotree show right")
    end

  elseif mode == "plan" then
    -- Hide all editor buffers; only show requirements, planner, and agent panels
    -- Open requirements panel
    open_requirements_panel()
    -- Open planner panel
    open_planner_panel()
    -- Minimize all editor buffer windows
    minimize_editor_buffers()
    -- Open agent as a side panel (just the agent window)
    -- We'll create a minimal agent panel
    local focus_win = vim.api.nvim_get_current_win()
    local leftmost_win = nil
    local leftmost_col = 999999
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local config = vim.api.nvim_win_get_config(win)
      if config.relative ~= "" then goto continue end
      if is_workspace_panel(win) then goto continue end
      if win == req_win then goto continue end
      local col = config.col or 0
      if col < leftmost_col then
        leftmost_col = col
        leftmost_win = win
      end
      ::continue::
    end

    local base_win = leftmost_win or find_editor_window(focus_win) or focus_win
    vim.api.nvim_set_current_win(base_win)
    vim.cmd("leftabove vsplit")
    agent_win = vim.api.nvim_get_current_win()
    local buf_a = M.ensure_agent_buf()
    vim.api.nvim_win_set_buf(agent_win, buf_a)
    vim.api.nvim_win_set_width(agent_win, agent_width)
    vim.wo[agent_win].winfixwidth = true
    apply_agent_style(agent_win)
    -- Restore the saved agent terminal buffer into the plan panel
    restore_agent_term_buf()
    render_agent_panel()
    panels_visible = true

    if vim.api.nvim_win_is_valid(focus_win) then
      vim.api.nvim_set_current_win(focus_win)
    end
  end

  -- Only one agent panel may exist after any mode switch
  close_duplicate_agent_windows(mode == "edit" and agent_explorer_win or agent_win)
  vim.schedule(resize_panels)
  -- Any empty editor window left by the new layout gets the start screen
  vim.schedule(function()
    local ok, start_screen = pcall(require, "lenn.start-screen")
    if ok then start_screen.check_all(false) end
  end)

  if not skip_notify then
    local mode_info = workspace_modes[mode]
    local msg = string.format("Workspace %s: %s %s", rebuilding and "rebuilt" or "mode", mode_info.icon, mode_info.name)
    vim.notify(msg, vim.log.levels.INFO)
  end
end

-- ─── End Workspace Modes ────────────────────────────────────────────────────

-- Provider definitions — loaded from agent-market dynamically
local market = require("lenn.agent-market")
local providers = market.get_providers()

-- Fallback: if market returns empty, use defaults
if #providers == 0 then
  providers = {
    { name = "OpenCode", cmd = "opencode", icon = nf.opencode },
    { name = "Junie", cmd = "junie", icon = nf.junie },
    { name = "Codex", cmd = "codex", icon = nf.codex },
    { name = "Claude Code", cmd = "claude", icon = nf.claude },
    { name = "Kiro", cmd = "kiro-cli chat", icon = nf.kiro },
  }
end

-- ─── Window Style Helper ────────────────────────────────────────────────────

-- Namespace IDs for highlights (lazy-initialized to avoid headless crash)
local threads_ns = nil
local skills_ns = nil
local keymaps_ns = nil

local function get_threads_ns()
  if threads_ns == nil then
    threads_ns = vim.api.nvim_create_namespace("_agent_threads_hl")
  end
  return threads_ns
end

local function get_skills_ns()
  if skills_ns == nil then
    skills_ns = vim.api.nvim_create_namespace("_agent_skills_hl")
  end
  return skills_ns
end

local function get_keymaps_ns()
  if keymaps_ns == nil then
    keymaps_ns = vim.api.nvim_create_namespace("_agent_keymaps_hl")
  end
  return keymaps_ns
end

local function refresh_focused_borders()
  local focused = vim.api.nvim_get_current_win()
  local focused_pos = vim.api.nvim_win_get_position(focused)
  local focused_row_end = focused_pos[1] + vim.api.nvim_win_get_height(focused)
  local focused_col_end = focused_pos[2] + vim.api.nvim_win_get_width(focused)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local pos = vim.api.nvim_win_get_position(win)
    local row_end = pos[1] + vim.api.nvim_win_get_height(win)
    local col_end = pos[2] + vim.api.nvim_win_get_width(win)
    local shares_vertical_edge = (math.abs(col_end - focused_pos[2]) <= 1 or math.abs(pos[2] - focused_col_end) <= 1)
      and math.max(pos[1], focused_pos[1]) < math.min(row_end, focused_row_end)
    local shares_horizontal_edge = (math.abs(row_end - focused_pos[1]) <= 1 or math.abs(pos[1] - focused_row_end) <= 1)
      and math.max(pos[2], focused_pos[2]) < math.min(col_end, focused_col_end)
    local on_focused_outline = win == focused or shares_vertical_edge or shares_horizontal_edge
    local mappings = {}
    for mapping in vim.wo[win].winhighlight:gmatch("[^,]+") do
      local source = mapping:match("^([^:]+):")
      if source ~= "WinSeparator" and source ~= "VertSplit"
        and source ~= "WinBar" and source ~= "StatusLine" then
        table.insert(mappings, mapping)
      end
    end
    -- Separators stay neutral: the focused window gets its own rounded frame
    -- (lenn.focus-frame), so neighbours are never lit up.
    local border_group = "AgentPanelBorder"
    local _ = on_focused_outline
    table.insert(mappings, "WinSeparator:" .. border_group)
    table.insert(mappings, "VertSplit:" .. border_group)
    if win == focused then
      table.insert(mappings, "WinBar:AgentFocusedPanelWinBar")
      table.insert(mappings, "StatusLine:AgentFocusedPanelStatusLine")
    end
    vim.wo[win].winhighlight = table.concat(mappings, ",")
  end
end

-- Helper: read a color from the active colorscheme's highlight groups
local function theme_hl(name)
  local ok, ret = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
  if ok and type(ret) == "table" then return ret end
  return {}
end

local function theme_fg(name, fallback)
  local hl = theme_hl(name)
  if hl.fg then return string.format("#%06x", hl.fg) end
  return fallback
end

local function theme_bg(name, fallback)
  local hl = theme_hl(name)
  if hl.bg then return string.format("#%06x", hl.bg) end
  return fallback
end

-- Custom highlight groups for Threads and Skills panels (use 0 for local scope)
-- Reads colors from the active colorscheme so they adapt when the theme changes.
local function setup_highlights()
  -- Map semantic highlight groups to theme colors with Catppuccin Mocha fallbacks
  local title_color = theme_fg("@text.title", theme_fg("Title", "#cba6f7"))
  local success_color = theme_fg("@text.success", theme_fg("DiagnosticOk", "#a6e3a1"))
  local comment_color = theme_fg("Comment", "#6c7086")
  local uri_color = theme_fg("@text.uri", theme_fg("Underlined", "#89b4fa"))
  local warning_color = theme_fg("@text.warning", theme_fg("DiagnosticWarn", "#f9e2af"))
  local error_color = theme_fg("@text.danger", theme_fg("DiagnosticError", "#f38ba8"))
  local text_color = theme_fg("Normal", "#cdd6f4")
  local special_color = theme_fg("@text.emphasis", theme_fg("Special", "#f5c2e7"))
  local literal_color = theme_fg("@text.literal", theme_fg("Constant", "#94e2d5"))
  local nontext_color = theme_fg("NonText", "#585b70")
  local border_color = theme_fg("FloatBorder", "#45475a")
  local muted_title = theme_fg("@text.uri", theme_fg("Identifier", "#a78bc7"))
  local editor_bg = theme_bg("Normal", "#1e1e2e")
  local float_bg = theme_bg("NormalFloat", theme_bg("Visual", "#302d3e"))
  local subtext_color = theme_fg("NonText", theme_fg("Comment", "#a6adc8"))

  -- Active thread / project name uses the theme's title color
  vim.api.nvim_set_hl(0, "AgentActiveThread", { fg = title_color, bold = true })
  -- Running threads: mauve/purple to mark threads with active sessions
  vim.api.nvim_set_hl(0, "AgentThreadRunning", { fg = theme_fg("@text.title", theme_fg("Title", "#cba6f7")) })
  vim.api.nvim_set_hl(0, "AgentCurrentProject", { fg = title_color })
  vim.api.nvim_set_hl(0, "AgentAddProject", { link = "Special" })
  -- Threads / Tasks tree look
  vim.api.nvim_set_hl(0, "AgentTreeGuide", { fg = subtext_color })
  vim.api.nvim_set_hl(0, "AgentBadge", { link = "Comment" })
  vim.api.nvim_set_hl(0, "AgentThreadTime", { link = "Comment" })
  vim.api.nvim_set_hl(0, "AgentFolderIcon", { link = "Directory" })
  vim.api.nvim_set_hl(0, "AgentProjectName", { link = "Normal" })
  vim.api.nvim_set_hl(0, "AgentTaskTitle", { link = "Normal" })
  vim.api.nvim_set_hl(0, "AgentTaskDetailIcon", { fg = subtext_color })
  vim.api.nvim_set_hl(0, "AgentMinimized", { fg = title_color, bold = true })
  -- Providers cover
  vim.api.nvim_set_hl(0, "AgentCoverTitle", { fg = title_color, bold = true })
  vim.api.nvim_set_hl(0, "AgentCoverSection", { fg = subtext_color, bold = true })
  vim.api.nvim_set_hl(0, "AgentCoverKey", { link = "Special" })
  vim.api.nvim_set_hl(0, "AgentCoverMissing", { link = "NonText" })
  -- Brand-ish colors for provider icons
  vim.api.nvim_set_hl(0, "AgentProviderClaudeCode", { fg = "#d97757" })
  vim.api.nvim_set_hl(0, "AgentProviderCodex", { fg = theme_fg("Normal", "#cdd6f4") })
  vim.api.nvim_set_hl(0, "AgentProviderOpenCode", { fg = theme_fg("Normal", "#cdd6f4") })
  vim.api.nvim_set_hl(0, "AgentProviderJunie", { fg = "#47e054" })
  vim.api.nvim_set_hl(0, "AgentProviderKiro", { fg = "#9046ff" })
  -- Enabled skills use the theme's success color
  vim.api.nvim_set_hl(0, "AgentEnabledSkill", { fg = success_color, bold = true })
  -- Disabled skill icon uses the theme's comment color
  vim.api.nvim_set_hl(0, "AgentDisabledSkill", { fg = comment_color })
  -- Focused panel border uses a muted title/identifier color
  vim.api.nvim_set_hl(0, "AgentFocusedPanelBorder", { fg = muted_title, bg = "NONE" })
  -- Unfocused separators stay dim; the focused window gets an accent frame
  vim.api.nvim_set_hl(0, "AgentPanelBorder", { fg = theme_fg("LineNr", theme_fg("NonText", border_color)), bg = "NONE" })
  vim.api.nvim_set_hl(0, "AgentFocusFrame", { fg = title_color, bold = true })
  vim.api.nvim_set_hl(0, "AgentFocusedPanelWinBar", { fg = title_color, bg = float_bg, bold = true })
  vim.api.nvim_set_hl(0, "AgentFocusedPanelStatusLine", { fg = title_color, bg = float_bg })
  -- Active tab: editor bg text on title-color background
  vim.api.nvim_set_hl(0, "AgentTabActive", { fg = editor_bg, bg = title_color, bold = true })
  vim.api.nvim_set_hl(0, "AgentTabInactive", { fg = subtext_color })
  -- Pills: active uses URI/blue, inactive uses subtext
  vim.api.nvim_set_hl(0, "AgentPillActive", { fg = uri_color, bold = true })
  vim.api.nvim_set_hl(0, "AgentPillInactive", { fg = subtext_color })
  -- Task status colors: inspired by the Help panel approach -- use theme colors
  -- but always fall back to bright Catppuccin Mocha colors that stand out on dark backgrounds.
  -- The key is to NEVER use dim highlights like NonText, Subtext, or @comment for task text.
  -- Pending: bright lavender (always visible, not dim gray)
  vim.api.nvim_set_hl(0, "AgentTaskPending", { fg = theme_fg("Identifier", "#bac2de") })
  -- In Progress: yellow/warning — always bright
  vim.api.nvim_set_hl(0, "AgentTaskInProgress", { fg = theme_fg("DiagnosticWarn", "#f9e2af"), bold = true })
  -- Completed: green/success — always bright
  vim.api.nvim_set_hl(0, "AgentTaskCompleted", { fg = theme_fg("DiagnosticOk", "#a6e3a1"), bold = true })
  -- Failed: red/error — always bright
  vim.api.nvim_set_hl(0, "AgentTaskFailed", { fg = theme_fg("DiagnosticError", "#f38ba8"), bold = true })
  -- Archived: medium gray (readable, not invisible)
  vim.api.nvim_set_hl(0, "AgentTaskArchived", { fg = theme_fg("Conditional", "#939ab7") })
  -- Summary / details panel highlights (match Help panel brightness)
  vim.api.nvim_set_hl(0, "AgentTaskSummary", { fg = theme_fg("Normal", "#cdd6f4") })
  vim.api.nvim_set_hl(0, "AgentTaskSummaryTitle", { fg = theme_fg("Special", "#f5c2e7"), bold = true })
  vim.api.nvim_set_hl(0, "AgentTaskSummaryLabel", { fg = theme_fg("Constant", "#94e2d5"), bold = true })
  vim.api.nvim_set_hl(0, "AgentTaskSummarySep", { fg = theme_fg("NonText", "#585b70") })
  -- Task icons: bright peach to stand out from the background
  vim.api.nvim_set_hl(0, "AgentTaskIcon", { fg = theme_fg("Special", "#f5a97f"), bold = true })
end

-- Apply neo-tree-like visual style to a window: transparent background,
-- full-width cursor line, no signcolumn/foldcolumn, relative numbers off.
apply_neo_tree_style = function(win, title)
  if not win or not vim.api.nvim_win_is_valid(win) then return end
  vim.wo[win].cursorline = true
  vim.wo[win].cursorlineopt = "line"
  vim.wo[win].signcolumn = "no"
  vim.wo[win].foldcolumn = "0"
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].winfixwidth = true
  vim.wo[win].colorcolumn = ""
  vim.wo[win].winbar = title and ("%#NeoTreeWinBar# " .. title) or ""
  vim.wo[win].winhighlight = "Normal:NeoTreeNormal,NormalNC:NeoTreeNormalNC,CursorLine:NeoTreeCursorLine"
  refresh_focused_borders()
end

apply_agent_style = function(win)
  if not win or not vim.api.nvim_win_is_valid(win) then return end
  vim.wo[win].cursorline = true
  vim.wo[win].cursorlineopt = "line"
  vim.wo[win].winfixwidth = true
  vim.wo[win].winbar = ""
  if render_agent_tabs then render_agent_tabs() end
  vim.wo[win].winhighlight = "Normal:NeoTreeNormal,NormalNC:NeoTreeNormalNC,CursorLine:NeoTreeCursorLine"
  refresh_focused_borders()
end

local function clamp(value, min, max)
  return math.max(min, math.min(max, math.floor(value)))
end

local function limit_width(name, columns)
  local l = panel_limits[name]
  return clamp(columns * l.ratio, l.min, l.max)
end

-- Panels each mode places side by side (besides code buffers)
local mode_columns = {
  agent = { "threads", "agent", "explorer" },
  full = { "threads", "agent", "explorer" },
  edit = { "agent", "explorer" },
  plan = { "agent", "requirements", "explorer" },
}

calculate_panel_widths = function()
  local columns = vim.o.columns
  local widths = {}
  for name in pairs(panel_limits) do
    widths[name] = limit_width(name, columns)
  end

  -- Leave room for code in modes that show it; shrink the agent first, then
  -- threads, and on very small screens scale everything proportionally.
  local mode = current_workspace_mode
  local cols = mode_columns[mode] or mode_columns.full
  local reserve = (mode == "full" or mode == "edit") and editor_min_width or 20
  local available = columns - reserve - #cols
  local function total()
    local sum = 0
    for _, name in ipairs(cols) do sum = sum + widths[name] end
    return sum
  end
  for _, name in ipairs({ "agent", "threads", "requirements" }) do
    local excess = total() - available
    if excess > 0 and vim.tbl_contains(cols, name) then
      widths[name] = math.max(panel_limits[name].min, widths[name] - excess)
    end
  end
  local excess = total() - available
  if excess > 0 and total() > 0 then
    local scale = math.max(0.1, available / total())
    for _, name in ipairs(cols) do
      widths[name] = math.max(panel_limits[name].floor, math.floor(widths[name] * scale))
    end
  end

  threads_width = widths.threads
  agent_width = widths.agent
  explorer_width = widths.explorer
  requirements_width = widths.requirements
end

local function visible_window(win)
  return win and vim.api.nvim_win_is_valid(win) and vim.fn.win_id2win(win) > 0
end

-- Windows resized in the current pass; their winfix* flags are released while
-- resizing (Neovim can't take space from a fixed neighbour) and set afterwards.
local fixed_wins = {}

-- Minimized windows (see M.toggle_minimize): win -> state
M._minimized = {}
local MINIMIZED_WIDTH, MINIMIZED_HEIGHT = 3, 1

local function set_fixed_width(win, width)
  if visible_window(win) then
    local m = M._minimized[win]
    if m and m.dir == "width" then width = MINIMIZED_WIDTH end
    fixed_wins[win] = true
    pcall(vim.api.nvim_win_set_width, win, width)
  end
end

-- True when `win` shares its column with another window. Shrinking a window
-- that spans the whole column gives the rows to the command line instead
-- (cmdheight grows, and Neovim aborts once it exceeds the screen height).
local function has_vertical_neighbor(win)
  return vim.api.nvim_win_call(win, function()
    local nr = vim.fn.winnr()
    return vim.fn.winnr("j") ~= nr or vim.fn.winnr("k") ~= nr
  end)
end

local function set_fixed_height(win, height)
  if visible_window(win) and has_vertical_neighbor(win) then
    local m = M._minimized[win]
    if m and m.dir == "height" then height = MINIMIZED_HEIGHT end
    fixed_wins[win] = true
    pcall(vim.api.nvim_win_set_height, win, height)
  end
end

-- Single source of truth for panel sizes in every workspace mode.
-- Fixed-size panels are set first; the agent (agent mode) or the planner
-- (plan mode) then takes the remaining columns.
local apply_panel_sizes
local base_cmdheight = nil

resize_panels = function()
  base_cmdheight = base_cmdheight or vim.o.cmdheight
  fixed_wins = {}
  local released = {}
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.wo[win].winfixwidth or vim.wo[win].winfixheight then
      released[win] = { vim.wo[win].winfixwidth, vim.wo[win].winfixheight }
      vim.wo[win].winfixwidth = false
      vim.wo[win].winfixheight = false
    end
  end

  local ok, err = pcall(apply_panel_sizes)

  for win, fix in pairs(released) do
    if vim.api.nvim_win_is_valid(win) then
      vim.wo[win].winfixwidth = fix[1]
      vim.wo[win].winfixheight = fix[2]
    end
  end
  for win in pairs(fixed_wins) do
    if vim.api.nvim_win_is_valid(win) then
      vim.wo[win].winfixwidth = true
    end
  end
  if visible_window(planner_win) and current_workspace_mode == "plan" then
    vim.wo[planner_win].winfixwidth = false
  end
  -- Safety net: never let a layout change leave a giant command line behind
  if vim.o.cmdheight > base_cmdheight then
    vim.o.cmdheight = base_cmdheight
  end
  if not ok then error(err) end
end

apply_panel_sizes = function()
  calculate_panel_widths()
  local mode = current_workspace_mode
  local neo_win = find_neo_tree_win()

  set_fixed_width(neo_win, explorer_width)
  for _, win in ipairs({ threads_win, skills_win, keymaps_win }) do
    set_fixed_width(win, threads_width)
  end
  set_fixed_width(req_win, requirements_width)

  if visible_window(agent_win) then
    local width = agent_width
    if mode == "agent" and not find_editor_window() then
      -- No file buffers: the agent takes all space between threads and explorer
      width = vim.o.columns - 1
      if visible_window(threads_win) then width = width - vim.api.nvim_win_get_width(threads_win) - 1 end
      if visible_window(neo_win) then width = width - vim.api.nvim_win_get_width(neo_win) - 1 end
    end
    set_fixed_width(agent_win, math.max(panel_limits.agent.floor, width))
  end

  if visible_window(planner_win) then
    if mode == "full" then
      set_fixed_height(planner_win, clamp(vim.o.lines * 0.25, 8, 15)) -- honours minimize
    else
      -- Plan mode: the planner fills the columns left between its neighbours
      local width = vim.o.columns - 1
      for _, win in ipairs({ agent_win, req_win, neo_win }) do
        if visible_window(win) then width = width - vim.api.nvim_win_get_width(win) - 1 end
      end
      pcall(vim.api.nvim_win_set_width, planner_win, math.max(20, width))
    end
  end

  -- Agent column next to the explorer in edit mode
  set_fixed_width(agent_explorer_win, agent_width)

  if visible_window(threads_win) and visible_window(skills_win) and visible_window(keymaps_win) then
    local total_height = vim.api.nvim_win_get_height(threads_win) + vim.api.nvim_win_get_height(skills_win) + vim.api.nvim_win_get_height(keymaps_win)
    if total_height > 1 then
      local function minimized(win) return M._minimized[win] and M._minimized[win].dir == "height" end
      local skills_h = minimized(skills_win) and MINIMIZED_HEIGHT or clamp(total_height * skills_height_ratio, 4, 12)
      local keymaps_h = minimized(keymaps_win) and MINIMIZED_HEIGHT or clamp(total_height * 0.25, 5, keymaps_height)
      local threads_h = minimized(threads_win) and MINIMIZED_HEIGHT
        or math.max(6, total_height - skills_h - keymaps_h)
      -- Whatever a minimized Threads frees goes to Skills (then Keymaps)
      local spare = total_height - threads_h - skills_h - keymaps_h
      if spare > 0 then
        if not minimized(skills_win) then skills_h = skills_h + spare
        elseif not minimized(keymaps_win) then keymaps_h = keymaps_h + spare end
      end
      set_fixed_height(skills_win, skills_h)
      set_fixed_height(keymaps_win, keymaps_h)
      set_fixed_height(threads_win, threads_h)
    end
  end
end

-- ─── Minimize / restore windows ────────────────────────────────────────────
-- A minimized window collapses to a thin strip (3 columns, or 1 row when it is
-- stacked with other windows in its column). Its buffer is swapped for a small
-- placeholder, so nothing is lost: terminals keep running (and keep their size),
-- panels keep their state. Entering the strip (Alt+q, mouse, <CR>) restores it.

local function window_title(win, buf)
  if buf == threads_buf then return "Threads", nf.thread end
  if buf == skills_buf then return "Skills", nf.wrench end
  if buf == keymaps_buf then return "Keymaps", nf.search end
  if buf == agent_buf or win == agent_win or win == agent_explorer_win then
    local provider = vim.b[buf].agent_provider or current_provider
    for _, p in ipairs(providers) do
      if p.name == provider then return p.name, nf.normalize(p.icon) end
    end
    return "Agent", nf.agent or nf.generic
  end
  if win == planner_win then return "Planner", nf.task_list end
  if win == req_win then return "Requirements", nf.task_criteria end
  local ft = vim.bo[buf].filetype
  if ft == "neo-tree" then return "Explorer", nf.explorer_files end
  if vim.bo[buf].buftype == "terminal" then return "Terminal", nf.lualine_finder end
  local name = vim.api.nvim_buf_get_name(buf)
  return name ~= "" and vim.fn.fnamemodify(name, ":t") or "[No Name]", nf.file_default
end

local function placeholder_lines(state)
  if state.dir == "height" then
    return { string.format(" %s %s %s  ·  minimized  ·  <CR> restore", nf.win_minimize, state.icon, state.title) }
  end
  local lines = { " " .. state.icon, "" }
  for _, ch in ipairs(vim.fn.split(state.title, "\\zs")) do
    table.insert(lines, " " .. ch)
  end
  return lines
end

function M.is_minimized(win)
  return M._minimized[win or vim.api.nvim_get_current_win()] ~= nil
end

function M.restore_window(win, opts)
  opts = opts or {}
  win = win or vim.api.nvim_get_current_win()
  local state = M._minimized[win]
  if not state then return end
  M._minimized[win] = nil
  if vim.api.nvim_win_is_valid(win) then
    if not state.keep_buf and state.buf and vim.api.nvim_buf_is_valid(state.buf) then
      vim.api.nvim_win_set_buf(win, state.buf)
    end
    if not state.keep_buf then vim.wo[win].winbar = state.winbar or "" end
    vim.wo[win].winfixwidth = state.fixw
    vim.wo[win].winfixheight = state.fixh
    if state.dir == "width" then
      pcall(vim.api.nvim_win_set_width, win, state.size)
    else
      pcall(vim.api.nvim_win_set_height, win, state.size)
    end
  end
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    vim.bo[state.buf].bufhidden = state.bufhidden
  end
  if state.placeholder and vim.api.nvim_buf_is_valid(state.placeholder) then
    pcall(vim.api.nvim_buf_delete, state.placeholder, { force = true })
  end
  if not opts.no_resize then vim.schedule(resize_panels) end
  -- Terminals: land in insert mode, like focusing them normally
  if opts.focus ~= false and vim.api.nvim_win_is_valid(win) and vim.api.nvim_get_current_win() == win
    and vim.bo[vim.api.nvim_win_get_buf(win)].buftype == "terminal" then
    vim.cmd.startinsert()
  end
end

function M.restore_all()
  for win in pairs(vim.deepcopy(M._minimized)) do
    M.restore_window(win, { no_resize = true, focus = false })
  end
  vim.schedule(resize_panels)
end

function M.minimize_window(win)
  win = win or vim.api.nvim_get_current_win()
  if M._minimized[win] or not vim.api.nvim_win_is_valid(win) then return end
  if vim.api.nvim_win_get_config(win).relative ~= "" then return end
  local normal = vim.tbl_filter(function(w)
    return vim.api.nvim_win_get_config(w).relative == "" and not M._minimized[w]
  end, vim.api.nvim_tabpage_list_wins(0))
  if #normal <= 1 then
    vim.notify("Can't minimize the only window", vim.log.levels.WARN)
    return
  end

  local buf = vim.api.nvim_win_get_buf(win)
  local title, icon = window_title(win, buf)
  local dir = has_vertical_neighbor(win) and "height" or "width"
  local state = {
    dir = dir, buf = buf, title = title, icon = icon,
    size = dir == "width" and vim.api.nvim_win_get_width(win) or vim.api.nvim_win_get_height(win),
    winbar = vim.wo[win].winbar, fixw = vim.wo[win].winfixwidth, fixh = vim.wo[win].winfixheight,
    bufhidden = vim.bo[buf].bufhidden,
  }
  -- Neo-tree refuses foreign buffers in its window (it moves them to a new
  -- split), so it is only shrunk, keeping its own buffer.
  state.keep_buf = vim.bo[buf].filetype == "neo-tree"
  if state.keep_buf then
    M._minimized[win] = state
    if dir == "width" then
      vim.wo[win].winfixwidth = true
      pcall(vim.api.nvim_win_set_width, win, MINIMIZED_WIDTH)
    else
      vim.wo[win].winfixheight = true
      pcall(vim.api.nvim_win_set_height, win, MINIMIZED_HEIGHT)
    end
    if vim.api.nvim_get_current_win() == win then
      vim.g.lenn_minimize_switching = true
      vim.cmd("wincmd p")
      if vim.api.nvim_get_current_win() == win then vim.cmd("wincmd h") end
      vim.g.lenn_minimize_switching = false
    end
    vim.schedule(resize_panels)
    return
  end

  -- Keep the real buffer alive while it is out of the window
  vim.bo[buf].bufhidden = "hide"

  local ph = vim.api.nvim_create_buf(false, true)
  vim.bo[ph].bufhidden = "wipe"
  vim.bo[ph].filetype = "lenn-minimized"
  vim.b[ph].agent_panel_placeholder = true
  vim.api.nvim_buf_set_lines(ph, 0, -1, false, placeholder_lines(state))
  vim.bo[ph].modifiable = false
  vim.api.nvim_buf_add_highlight(ph, -1, "AgentMinimized", 0, 0, -1)
  for i = 2, vim.api.nvim_buf_line_count(ph) do
    vim.api.nvim_buf_add_highlight(ph, -1, "Comment", i - 1, 0, -1)
  end
  for _, key in ipairs({ "<CR>", "o", "l", "<2-LeftMouse>" }) do
    vim.keymap.set("n", key, function() M.restore_window(win) end, { buffer = ph, nowait = true, desc = "Restore window" })
  end
  state.placeholder = ph
  M._minimized[win] = state

  vim.api.nvim_win_set_buf(win, ph)
  local wo = vim.wo[win][0]
  wo.number, wo.relativenumber, wo.signcolumn = false, false, "no"
  wo.cursorline, wo.foldcolumn, wo.wrap = false, "0", false
  vim.wo[win].winbar = ""
  if dir == "width" then
    vim.wo[win].winfixwidth = true
    pcall(vim.api.nvim_win_set_width, win, MINIMIZED_WIDTH)
  else
    vim.wo[win].winfixheight = true
    pcall(vim.api.nvim_win_set_height, win, MINIMIZED_HEIGHT)
  end

  -- Leave the strip: go back to the previous window (or any other one)
  if vim.api.nvim_get_current_win() == win then
    local prev = vim.fn.win_getid(vim.fn.winnr("#"))
    if prev == 0 or prev == win or M._minimized[prev] or not vim.api.nvim_win_is_valid(prev) then
      prev = nil
      for _, w in ipairs(normal) do
        if w ~= win then prev = w; break end
      end
    end
    if prev then
      vim.g.lenn_minimize_switching = true
      vim.api.nvim_set_current_win(prev)
      vim.g.lenn_minimize_switching = false
    end
  end
  vim.schedule(resize_panels)
end

function M.toggle_minimize(win)
  win = win or vim.api.nvim_get_current_win()
  if M._minimized[win] then M.restore_window(win) else M.minimize_window(win) end
end

-- Entering a minimized strip restores it; closing it cleans up its state.
vim.api.nvim_create_autocmd("WinEnter", {
  group = vim.api.nvim_create_augroup("LennMinimizedWindows", { clear = true }),
  callback = function()
    if vim.g.lenn_minimize_switching then return end
    local win = vim.api.nvim_get_current_win()
    if M._minimized[win] then vim.schedule(function() M.restore_window(win) end) end
  end,
})
vim.api.nvim_create_autocmd("WinClosed", {
  group = "LennMinimizedWindows",
  callback = function(args)
    local win = tonumber(args.match)
    local state = win and M._minimized[win]
    if not state then return end
    M._minimized[win] = nil
    if state.buf and vim.api.nvim_buf_is_valid(state.buf) then vim.bo[state.buf].bufhidden = state.bufhidden end
  end,
})

function M.explorer_width()
  calculate_panel_widths()
  -- Edgy asks for the explorer width on every layout: honour a minimized tree
  for win, state in pairs(M._minimized) do
    if state.keep_buf and state.dir == "width" and vim.api.nvim_win_is_valid(win) then
      return MINIMIZED_WIDTH
    end
  end
  return explorer_width
end

local last_editor_win = nil

is_workspace_panel = function(win)
  return win == threads_win or win == skills_win or win == keymaps_win or win == agent_win or win == req_win or win == agent_explorer_win or win == planner_win
end

local function is_editor_window(win)
  if not win or not vim.api.nvim_win_is_valid(win) or is_workspace_panel(win) then
    return false
  end
  if vim.api.nvim_win_get_config(win).relative ~= "" then
    return false
  end

  local buf = vim.api.nvim_win_get_buf(win)
  if vim.b[buf].lenn_start_screen then return true end -- start screen placeholder
  return vim.bo[buf].buftype == "" and vim.bo[buf].filetype ~= "neo-tree"
end

find_editor_window = function(preferred)
  if is_editor_window(last_editor_win) then return last_editor_win end
  if is_editor_window(preferred) then return preferred end
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if is_editor_window(win) then return win end
  end
end

local function panel_restore_buffer(win)
  local buf
  if win == threads_win then
    buf = threads_buf
  elseif win == skills_win then
    buf = skills_buf
  elseif win == keymaps_win then
    buf = keymaps_buf
  elseif win == agent_win or win == agent_explorer_win then
    buf = current_term and current_term.bufnr or agent_buf
  end
  return buf and vim.api.nvim_buf_is_valid(buf) and buf or nil
end

local routing_buffers = {}

local function keep_file_out_of_panel(args)
  local buf = args.buf
  if routing_buffers[buf] or not vim.api.nvim_buf_is_valid(buf)
    or vim.bo[buf].buftype ~= "" or vim.b[buf].agent_panel then
    return
  end

  local panel_win
  for _, win in pairs({ threads_win, skills_win, keymaps_win, agent_win, agent_explorer_win }) do
    if win and vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
      panel_win = win
      break
    end
  end
  if not panel_win then return end

  routing_buffers[buf] = true
  local editor_win
  local ok, err = pcall(function()
    local restore_buf = panel_restore_buffer(panel_win)
    editor_win = find_editor_window(panel_win)
    if editor_win then
      vim.api.nvim_win_set_buf(editor_win, buf)
    else
      editor_win = open_center_window(buf)
    end
    if restore_buf and restore_buf ~= buf then
      vim.api.nvim_win_set_buf(panel_win, restore_buf)
    end
  end)
  routing_buffers[buf] = nil
  if not ok then error(err) end
  last_editor_win = editor_win
  vim.api.nvim_set_current_win(editor_win)
  vim.schedule(resize_panels)
end

vim.api.nvim_create_autocmd("WinEnter", {
  group = vim.api.nvim_create_augroup("LennAgentEditorWindow", { clear = true }),
  callback = function()
    local win = vim.api.nvim_get_current_win()
    if is_editor_window(win) then last_editor_win = win end
    refresh_focused_borders()
  end,
})

vim.api.nvim_create_autocmd("BufWinEnter", {
  group = vim.api.nvim_create_augroup("LennAgentPanelBuffers", { clear = true }),
  callback = keep_file_out_of_panel,
})

vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter", "TermOpen", "TermEnter" }, {
  group = vim.api.nvim_create_augroup("LennAgentPanelWinbar", { clear = true }),
  callback = function()
    local win = vim.api.nvim_get_current_win()
    if win ~= agent_win then return end
    vim.schedule(function()
      if visible_window(agent_win) then apply_agent_style(agent_win) end
    end)
  end,
})

-- Keep sizes consistent when the screen changes or a window closes
-- (closing a split would otherwise hand its space to a random panel).
vim.api.nvim_create_autocmd({ "VimResized", "WinClosed" }, {
  group = vim.api.nvim_create_augroup("LennAgentPanelResize", { clear = true }),
  callback = function()
    vim.schedule(resize_panels)
  end,
})

vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("LennAgentPanelColors", { clear = true }),
  callback = function()
    setup_highlights()
  end,
})

setup_highlights()

-- ─── Threads Collection ─────────────────────────────────────────────────────

local function project_name(path)
  return vim.fn.fnamemodify(path or vim.fn.getcwd(), ":t")
end

-- Helpers live in a do-block to stay under LuaJIT's 200-local limit.
local saved_projects = {}
local collect_threads
do
local uv = vim.uv or vim.loop

local function normalize_dir(path)
  if type(path) ~= "string" or path == "" then return nil end
  path = vim.fn.fnamemodify(vim.fn.expand(path), ":p")
  if #path > 1 then path = path:gsub("/+$", "") end
  return path
end

-- Convert an ISO-8601 UTC timestamp ("2026-11-15T04:39:20.523Z") to epoch seconds.
local function iso_to_epoch(value)
  if type(value) ~= "string" then return 0 end
  local y, mo, d, h, mi, s = value:match("^(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
  if not y then return 0 end
  local t = os.time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d),
    hour = tonumber(h), min = tonumber(mi), sec = tonumber(s), isdst = false })
  local utc_offset = os.time() - os.time(os.date("!*t"))
  return t + utc_offset
end

-- Read at most `max` lines of a file without loading the whole thing.
local function read_head(path, max)
  local f = io.open(path, "r")
  if not f then return {} end
  local lines = {}
  for line in f:lines() do
    table.insert(lines, line)
    if #lines >= max then break end
  end
  f:close()
  return lines
end

-- ─── Saved projects (shown even when they have no threads yet) ─────────────

local saved_projects_file = vim.fn.stdpath("data") .. "/lenn-agent-projects.json"

function saved_projects.load()
  local ok, lines = pcall(vim.fn.readfile, saved_projects_file)
  if not ok or not lines or #lines == 0 then return {} end
  local decoded_ok, list = pcall(vim.json.decode, table.concat(lines, "\n"))
  if not decoded_ok or type(list) ~= "table" then return {} end
  local result = {}
  for _, path in ipairs(list) do
    local dir = normalize_dir(path)
    if dir then table.insert(result, dir) end
  end
  return result
end

local function write_saved_projects(list)
  vim.fn.mkdir(vim.fn.fnamemodify(saved_projects_file, ":h"), "p")
  pcall(vim.fn.writefile, { vim.json.encode(list) }, saved_projects_file)
end

function saved_projects.add(path)
  local dir = normalize_dir(path)
  if not dir then return nil end
  local list = saved_projects.load()
  for _, existing in ipairs(list) do
    if existing == dir then return dir end
  end
  table.insert(list, dir)
  write_saved_projects(list)
  return dir
end

function saved_projects.remove(path)
  local dir = normalize_dir(path)
  local list, removed = {}, false
  for _, existing in ipairs(saved_projects.load()) do
    if existing == dir then removed = true else table.insert(list, existing) end
  end
  if removed then write_saved_projects(list) end
  return removed
end

-- ─── Per-provider collectors ───────────────────────────────────────────────
-- Every collector reads sessions from ALL projects (not only the current cwd)
-- and returns { provider, icon, id, cwd, title, updated } entries.

local MAX_PER_PROVIDER = 150

local function collect_codex()
  local result = {}
  local home = vim.env.CODEX_HOME or vim.fn.expand("~/.codex")
  local paths = vim.fn.globpath(home .. "/sessions", "**/rollout-*.jsonl", false, true)
  local mtimes = {}
  for _, path in ipairs(paths) do
    local st = uv.fs_stat(path)
    mtimes[path] = st and st.mtime.sec or 0
  end
  table.sort(paths, function(a, b) return mtimes[a] > mtimes[b] end)
  for _, path in ipairs(paths) do
    if #result >= MAX_PER_PROVIDER then break end
    local first = read_head(path, 1)[1]
    local ok, meta = pcall(vim.json.decode, first or "")
    local payload = ok and type(meta) == "table" and meta.payload or nil
    if type(payload) == "table" and payload.id and payload.cwd then
      table.insert(result, {
        provider = "Codex",
        icon = nf.codex,
        id = payload.id,
        cwd = normalize_dir(payload.cwd),
        title = string.format("%s · %s", project_name(payload.cwd), payload.id:sub(-8)),
        updated = mtimes[path],
      })
    end
  end
  return result
end

local function collect_junie()
  local result = {}
  local home = vim.env.JUNIE_HOME or vim.fn.expand("~/.junie")
  local ok, lines = pcall(vim.fn.readfile, home .. "/sessions/index.jsonl")
  if not ok then return result end
  for _, line in ipairs(lines) do
    if line ~= "" then
      local decoded, meta = pcall(vim.json.decode, line)
      if decoded and type(meta) == "table" and meta.sessionId and meta.projectDir and meta.projectDir ~= "" then
        table.insert(result, {
          provider = "Junie",
          icon = nf.junie,
          id = meta.sessionId,
          cwd = normalize_dir(meta.projectDir),
          title = meta.taskName or meta.sessionId,
          updated = math.floor((tonumber(meta.updatedAt) or tonumber(meta.createdAt) or 0) / 1000),
        })
      end
    end
  end
  table.sort(result, function(a, b) return a.updated > b.updated end)
  while #result > MAX_PER_PROVIDER do table.remove(result) end
  return result
end

-- Kiro: `kiro-cli chat --list-sessions` only lists the current directory (and
-- --all-cwds currently returns nothing), so read the session store directly.
local function collect_kiro()
  local result = {}
  local home = vim.env.KIRO_HOME or vim.fn.expand("~/.kiro")
  for _, path in ipairs(vim.fn.glob(home .. "/sessions/*/sess_*/session.json", false, true)) do
    local ok, lines = pcall(vim.fn.readfile, path)
    if ok and #lines > 0 then
      local decoded, s = pcall(vim.json.decode, table.concat(lines, "\n"))
      if decoded and type(s) == "table" and s.id then
        local dir = (type(s.rootPaths) == "table" and s.rootPaths[1])
          or (type(s.workspacePaths) == "table" and s.workspacePaths[1])
        dir = normalize_dir(dir)
        if dir then
          table.insert(result, {
            provider = "Kiro",
            icon = nf.kiro,
            id = s.id,
            cwd = dir,
            title = (s.title and s.title ~= "") and s.title or s.id,
            updated = iso_to_epoch(s.lastModifiedAt or s.createdAt),
          })
        end
      end
    end
  end
  table.sort(result, function(a, b) return a.updated > b.updated end)
  while #result > MAX_PER_PROVIDER do table.remove(result) end
  return result
end

-- Claude Code: ~/.claude/projects/<slug>/<session-id>.jsonl
local function claude_prompt_text(content)
  if type(content) == "string" then return content end
  if type(content) == "table" then
    for _, part in ipairs(content) do
      if type(part) == "table" and part.type == "text" and type(part.text) == "string" then
        return part.text
      end
    end
  end
  return nil
end

local function collect_claude()
  local result = {}
  local home = vim.env.CLAUDE_CONFIG_DIR or vim.fn.expand("~/.claude")
  local paths = vim.fn.glob(home .. "/projects/*/*.jsonl", false, true)
  local mtimes = {}
  for _, path in ipairs(paths) do
    local st = uv.fs_stat(path)
    mtimes[path] = st and st.mtime.sec or 0
  end
  table.sort(paths, function(a, b) return mtimes[a] > mtimes[b] end)
  for _, path in ipairs(paths) do
    if #result >= MAX_PER_PROVIDER then break end
    local id = vim.fn.fnamemodify(path, ":t:r")
    local cwd, title, prompt
    for _, line in ipairs(read_head(path, 80)) do
      local ok, entry = pcall(vim.json.decode, line)
      if ok and type(entry) == "table" then
        if not cwd and type(entry.cwd) == "string" then cwd = entry.cwd end
        if entry.type == "custom-title" and entry.customTitle then title = entry.customTitle end
        if entry.type == "ai-title" and entry.aiTitle and not title then title = entry.aiTitle end
        if entry.type == "summary" and entry.summary and not title then title = entry.summary end
        if not prompt and entry.type == "user" and not entry.isMeta and type(entry.message) == "table" then
          local text = claude_prompt_text(entry.message.content)
          if text and not text:match("^%s*<") then prompt = text end
        end
      end
      if cwd and title then break end
    end
    -- Skip empty sessions (no prompt and no title): nothing to resume.
    if cwd and (title or prompt) then
      title = (title or prompt):gsub("%s+", " ")
      if #title > 80 then title = title:sub(1, 77) .. "..." end
      table.insert(result, {
        provider = "Claude Code",
        icon = nf.claude,
        id = id,
        cwd = normalize_dir(cwd),
        title = title,
        updated = mtimes[path],
      })
    end
  end
  return result
end

-- OpenCode: `opencode session list` is scoped to the current project, so query
-- its SQLite store directly; fall back to the CLI when sqlite3 is missing.
local function collect_opencode(cb)
  local data_home = vim.env.XDG_DATA_HOME or vim.fn.expand("~/.local/share")
  local db = data_home .. "/opencode/opencode.db"
  local use_sqlite = vim.fn.executable("sqlite3") == 1 and uv.fs_stat(db) ~= nil
  local cmd
  if use_sqlite then
    cmd = { "sqlite3", "-readonly", "-json", db,
      "select id, title, directory, time_updated from session_v2 "
        .. "where parent_id is null and time_archived is null "
        .. "order by time_updated desc limit " .. MAX_PER_PROVIDER }
  elseif vim.fn.executable("opencode") == 1 then
    cmd = { "opencode", "session", "list", "--max-count", tostring(MAX_PER_PROVIDER), "--format", "json" }
  else
    return cb({})
  end
  local output = {}
  local job = vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    on_stdout = function(_, data) output = data or {} end,
    on_exit = function(_, code)
      vim.schedule(function()
        local result = {}
        local ok, sessions = pcall(vim.json.decode, table.concat(output, "\n"))
        if code == 0 and ok and type(sessions) == "table" then
          for _, s in ipairs(sessions) do
            local dir = normalize_dir(s.directory or (type(s.location) == "table" and s.location.directory))
            if dir and s.id then
              table.insert(result, {
                provider = "OpenCode",
                icon = nf.opencode,
                id = s.id,
                cwd = dir,
                title = (s.title and s.title ~= vim.NIL and s.title ~= "") and s.title or s.id,
                updated = math.floor((tonumber(s.time_updated) or tonumber(s.updated) or 0) / 1000),
              })
            end
          end
        end
        cb(result)
      end)
    end,
  })
  if job <= 0 then cb({}) end
end

collect_threads = function(cb)
  -- Collect threads from ALL projects and providers. Each thread includes
  -- `cwd` (so render_threads can group them) and `updated` (epoch seconds).
  local all_threads = {}
  for _, collector in ipairs({ collect_codex, collect_junie, collect_kiro, collect_claude }) do
    local ok, items = pcall(collector)
    if ok then vim.list_extend(all_threads, items) end
  end
  collect_opencode(function(items)
    vim.list_extend(all_threads, items)
    table.sort(all_threads, function(a, b) return (a.updated or 0) > (b.updated or 0) end)
    cb(all_threads)
  end)
end
end -- do (thread collectors)

-- ─── Threads Panel ──────────────────────────────────────────────────────────

-- Screen rows map to either a thread entry or a project directory.
local thread_row_map = {}
local project_row_map = {}
local action_row_map = {}  -- row -> "add_project"
local expanded_projects = {}

local function reset_project_expansion()
  for cwd in pairs(expanded_projects) do
    expanded_projects[cwd] = nil
  end
end

-- ─── Skills Panel ──────────────────────────────────────────────────────────

-- Maps screen row numbers to skill indices for toggle_skill_in_skills_buf().
local skills_row_map = {}

local function tabs_header()
  return " Threads    Tasks "
end

local function highlight_tabs(ns)
  local header = tabs_header()
  local label = active_threads_tab == "threads" and "Threads" or "Tasks"
  local first, last = header:find(label, 1, true)
  if not first then return end
  vim.api.nvim_buf_add_highlight(threads_buf, ns, "AgentTabActive", 0, math.max(0, first - 2), last + 1)
  local other = label == "Threads" and "Tasks" or "Threads"
  local other_first, other_last = header:find(other, 1, true)
  if other_first then
    vim.api.nvim_buf_add_highlight(threads_buf, ns, "AgentTabInactive", 0, other_first - 1, other_last)
  end
end

-- ─── Panel line builder (Threads / Tasks) ──────────────────────────────────
-- Lines are built from highlighted segments, with optional right-aligned info
-- (counts, relative times) so both tabs share the same look.
M._ui = {}

function M._ui.rel_time(epoch)
  if not epoch or epoch <= 0 then return "" end
  local diff = os.time() - epoch
  if diff < 60 then return "now" end
  if diff < 3600 then return math.floor(diff / 60) .. "m" end
  if diff < 86400 then return math.floor(diff / 3600) .. "h" end
  if diff < 86400 * 7 then return math.floor(diff / 86400) .. "d" end
  if diff < 86400 * 30 then return math.floor(diff / (86400 * 7)) .. "w" end
  return math.floor(diff / (86400 * 30)) .. "mo"
end

-- Truncate to a display width, adding an ellipsis.
function M._ui.fit(text, width)
  text = tostring(text or ""):gsub("[\r\n]+", " ")
  if width <= 0 then return "" end
  if vim.fn.strdisplaywidth(text) <= width then return text end
  local out = vim.fn.strcharpart(text, 0, math.max(0, width - 1))
  while vim.fn.strdisplaywidth(out) > width - 1 do
    out = vim.fn.strcharpart(out, 0, vim.fn.strchars(out) - 1)
  end
  return out .. "…"
end

function M._ui.panel_width(buf, fallback)
  local win = vim.fn.bufwinid(buf)
  return (win ~= -1 and vim.api.nvim_win_get_width(win) or fallback) - 1
end

-- builder:add({ {text, hl}, ... }, { text, hl } | nil, line_hl | nil) -> row
function M._ui.builder(width)
  local b = { lines = {}, marks = {}, width = width }
  function b:add(segments, right, line_hl)
    segments = segments or {}
    local text, marks = "", {}
    for _, seg in ipairs(segments) do
      local start = #text
      text = text .. seg[1]
      if seg[2] then table.insert(marks, { start, #text, seg[2] }) end
    end
    if right and right[1] ~= "" then
      local gap = self.width - vim.fn.strdisplaywidth(text) - vim.fn.strdisplaywidth(right[1])
      if gap >= 1 then
        text = text .. string.rep(" ", gap)
        local start = #text
        text = text .. right[1]
        if right[2] then table.insert(marks, { start, #text, right[2] }) end
      end
    end
    table.insert(self.lines, text)
    local row = #self.lines
    if line_hl then table.insert(self.marks, { row, 0, #text, line_hl, 90 }) end
    for _, m in ipairs(marks) do table.insert(self.marks, { row, m[1], m[2], m[3], 100 }) end
    return row
  end
  function b:apply(buf, ns)
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, self.lines)
    vim.bo[buf].modifiable = false
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    for _, m in ipairs(self.marks) do
      pcall(vim.api.nvim_buf_set_extmark, buf, ns, m[1] - 1, m[2], {
        end_col = m[3], hl_group = m[4], priority = m[5],
      })
    end
  end
  return b
end

local function render_threads(threads)
  if not threads_buf or not vim.api.nvim_buf_is_valid(threads_buf) then return end
  if active_threads_tab ~= "threads" then return end

  local project_order, project_map = {}, {}
  local function ensure_project(dir)
    if not project_map[dir] then
      local proj = { cwd = dir, name = project_name(dir), threads = {}, updated = 0 }
      project_map[dir] = proj
      table.insert(project_order, proj)
    end
    return project_map[dir]
  end
  for _, t in ipairs(threads) do
    if t.cwd and t.cwd ~= "" then
      local proj = ensure_project(t.cwd)
      table.insert(proj.threads, t)
      proj.updated = math.max(proj.updated, t.updated or 0)
    end
  end
  -- Projects added manually (A) are listed even before they have threads.
  for _, dir in ipairs(saved_projects.load()) do ensure_project(dir) end

  -- Current project first, then alphabetically
  local cwd = vim.fn.getcwd()
  table.sort(project_order, function(a, b)
    if (a.cwd == cwd) ~= (b.cwd == cwd) then return a.cwd == cwd end
    return a.name:lower() < b.name:lower()
  end)

  local running_ids = {}
  for _, sess in ipairs(get_running_project_sessions()) do
    if sess.thread_id then running_ids[sess.thread_id] = true end
  end

  local width = M._ui.panel_width(threads_buf, threads_width)
  local b = M._ui.builder(width)
  thread_row_map, project_row_map, action_row_map = {}, {}, {}

  b:add({})
  if #project_order == 0 then
    b:add({ { "  No threads found", "Comment" } })
  end
  for _, proj in ipairs(project_order) do
    if expanded_projects[proj.cwd] == nil then expanded_projects[proj.cwd] = false end
    local open = expanded_projects[proj.cwd]
    local is_current = proj.cwd == cwd
    local chevron = open and nf.ui_chevron_down or nf.ui_chevron_right
    local folder = is_current and (open and nf.ui_root_folder_open or nf.ui_root_folder)
      or (open and nf.ui_folder_open or nf.ui_folder)
    local count = #proj.threads > 0 and tostring(#proj.threads) or ""
    local name_hl = is_current and "AgentCurrentProject" or "AgentProjectName"
    local name = M._ui.fit(proj.name, width - 8 - #count)
    local row = b:add({
      { " " .. chevron .. " ", "AgentTreeGuide" },
      { folder .. " ", is_current and "AgentCurrentProject" or "AgentFolderIcon" },
      { name, name_hl },
    }, { count, "AgentBadge" })
    project_row_map[row] = proj.cwd

    if open then
      if #proj.threads == 0 then
        b:add({ { "   ╰ ", "AgentTreeGuide" }, { "No threads yet · + to start one", "Comment" } })
      end
      for i, t in ipairs(proj.threads) do
        local last = i == #proj.threads
        local guide = last and "   ╰ " or "   ├ "
        local time = M._ui.rel_time(t.updated)
        local running = running_ids[t.id]
        local active = t.id == current_thread_id
        local icon_hl = "AgentProvider" .. (t.provider or ""):gsub("%W", "")
        local title = M._ui.fit(t.title, width - 9 - #time)
        local title_hl = running and "AgentThreadRunning" or (active and "AgentActiveThread" or nil)
        local right = running and { nf.dot, "AgentThreadRunning" } or { time, "AgentThreadTime" }
        row = b:add({
          { guide, "AgentTreeGuide" },
          { (t.icon or nf.thread) .. " ", icon_hl },
          { title, title_hl },
        }, right)
        thread_row_map[row] = t
      end
      b:add({})
    end
  end

  -- Footer action: add an existing folder or create a new project
  if b.lines[#b.lines] ~= "" then b:add({}) end
  local row = b:add({ { " " .. nf.add .. " ", "AgentAddProject" }, { "Add project", "AgentAddProject" } }, { "A", "AgentBadge" })
  action_row_map[row] = "add_project"

  b:apply(threads_buf, get_threads_ns())
  update_threads_winbar()
  ensure_cursor_on_content()
end

local function shorten_task_text(value, limit)
  value = tostring(value or ""):gsub("\n", " "):gsub("%s+", " ")
  if #value > limit then return value:sub(1, limit - 3) .. "..." end
  return value
end

-- Word-wrap text to fit panel width, returning a table of lines
local function wrap_text(text, width, indent)
  indent = indent or ""
  local lines = {}
  text = tostring(text or ""):gsub("\n", " "):gsub("%s+", " ")
  local available = width - #indent
  if available <= 0 then available = 10 end
  local words = {}
  for w in text:gmatch("%S+") do table.insert(words, w) end
  local current = ""
  for _, word in ipairs(words) do
    if #current == 0 then
      current = word
    elseif #current + 1 + #word <= available then
      current = current .. " " .. word
    else
      table.insert(lines, indent .. current)
      current = word
    end
  end
  if #current > 0 then table.insert(lines, indent .. current) end
  if #lines == 0 then table.insert(lines, indent) end
  return lines
end

-- Format duration in seconds to a human-readable string
local function format_duration(seconds)
  if not seconds or seconds < 0 then return "N/A" end
  if seconds < 60 then return seconds .. "s" end
  local mins = math.floor(seconds / 60)
  local secs = seconds % 60
  if mins < 60 then return mins .. "m " .. secs .. "s" end
  local hrs = math.floor(mins / 60)
  mins = mins % 60
  return hrs .. "h " .. mins .. "m"
end

-- Find a running or recent direct session for a task
local function find_session_for_task(task_id)
  if not task_id then return nil end
  -- Search direct_agent_sessions first (most recent)
  for i = #direct_agent_sessions, 1, -1 do
    local s = direct_agent_sessions[i]
    if s.task_id == task_id then return s end
  end
  -- Search toggleterm sessions
  local Terminal = require("toggleterm.terminal")
  for _, t in ipairs(Terminal.get_all(true)) do
    local tid = vim.b[t.bufnr] and vim.b[t.bufnr].agent_task_id
    if tid == task_id then
      return {
        started_at = t.start_time or 0,
        running = t:is_open(),
        provider = vim.b[t.bufnr] and vim.b[t.bufnr].agent_provider,
        kind = "toggleterm",
      }
    end
  end
  return nil
end

-- Count changed files for a session using its change_snapshot
local function count_changed_files(session)
  if not session or not session.change_snapshot then return 0 end
  local now = project_file_stats(session.cwd)
  local count = 0
  for path in pairs(now) do
    local before = session.change_snapshot[path]
    if not before or before.size ~= now[path].size
      or before.mtime_sec ~= now[path].mtime_sec then
      count = count + 1
    end
  end
  return count
end

-- Load session details from Junie session files (summary.json + tasks.json)
-- Returns a table with model, tokens, cost, result, lifecycle, files_changed
local function load_junie_session_details(session_id)
  if not session_id then return nil end
  local home = vim.env.JUNIE_HOME or vim.fn.expand("~/.junie")
  local session_dir = home .. "/sessions/" .. session_id
  local details = {}

  -- Read summary.json for model, tokens, cost, lifecycle
  local summary_file = session_dir .. "/summary.json"
  local stat = (vim.uv or vim.loop).fs_stat(summary_file)
  if stat then
    local read_ok, lines = pcall(vim.fn.readfile, summary_file)
    if read_ok and lines and #lines > 0 then
      local ok, summary = pcall(vim.json.decode, table.concat(lines, "\n"))
      if ok and type(summary) == "table" then
        details.lifecycle = summary.lifecycle
        details.taskName = summary.taskName

        -- Extract model usage from mainAgent
        local mainAgent = summary.mainAgent
        if mainAgent and mainAgent.modelUsage and #mainAgent.modelUsage > 0 then
          local usage = mainAgent.modelUsage[1]
          details.model = usage.model
          details.tokens = {
            input = usage.inputTokens or 0,
            output = usage.outputTokens or 0,
            cache = usage.cacheInputTokens or 0,
          }
          details.cost = usage.cost
        end

        -- Duration from createdAt to updatedAt
        if summary.createdAt and summary.updatedAt then
          local created_sec = math.floor(summary.createdAt / 1000)
          local updated_sec = math.floor(summary.updatedAt / 1000)
          details.duration = updated_sec - created_sec
        end
      end
    end
  end

  -- Read tasks.json for outcome summary (result)
  local tasks_file = session_dir .. "/tasks.json"
  stat = (vim.uv or vim.loop).fs_stat(tasks_file)
  if stat then
    local read_ok, lines = pcall(vim.fn.readfile, tasks_file)
    if read_ok and lines and #lines > 0 then
      local ok, tasks = pcall(vim.json.decode, table.concat(lines, "\n"))
      if ok and type(tasks) == "table" and #tasks > 0 then
        local task = tasks[1]
        if task.outcomeSummary and task.outcomeSummary ~= "" then
          details.result = task.outcomeSummary
        end
        if task.status then
          details.task_status = task.status
        end
      end
    end
  end

  -- Read transcript.md for file changes summary
  local transcript_file = session_dir .. "/transcript.md"
  stat = (vim.uv or vim.loop).fs_stat(transcript_file)
  if stat then
    local read_ok, lines = pcall(vim.fn.readfile, transcript_file)
    if read_ok and lines and #lines > 0 then
      local file_changes = {}
      for _, line in ipairs(lines) do
        -- Match lines like "### Edited hola.py +4" or "### Read hola.py"
        local filename, action = line:match("^### (Edited|Read|Created) (.+)$")
        if filename then
          table.insert(file_changes, string.format("%s %s", action, filename))
        end
      end
      if #file_changes > 0 then
        details.files_changed = file_changes
      end
    end
  end

  -- Only return if we found at least some data
  if details.model or details.result or details.lifecycle or details.files_changed then
    return details
  end
  return nil
end

-- Load session details from Codex rollout JSONL files
-- Codex stores sessions at ~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl
-- The session_id from threads is the UUID part of the rollout filename
local function load_codex_session_details(session_id)
  if not session_id then return nil end
  local codex_home = vim.fn.expand("~/.codex")
  local sessions_dir = codex_home .. "/sessions"
  local details = {}
  local model = nil
  local total_input = 0
  local total_output = 0
  local total_cache = 0
  local last_agent_msg = ""
  local first_ts = nil
  local last_ts = nil
  local file_changes = {}

  -- Search for the rollout file containing this session_id (UUID)
  -- Session IDs in Codex are UUIDs like 01a1dd9d-4e9d-7300-b465-8c526e417b12
  local uuid_short = session_id:sub(1, 8) -- first 8 chars of UUID for matching

  -- Walk through YYYY/MM/DD directories
  local years = vim.fn.glob(sessions_dir .. "/*", true, true)
  for _, year in ipairs(years) do
    local months = vim.fn.glob(year .. "/*", true, true)
    for _, month in ipairs(months) do
      local days = vim.fn.glob(month .. "/*", true, true)
      for _, day in ipairs(days) do
        local rollouts = vim.fn.glob(day .. "/*", true, true)
        for _, rollout_file in ipairs(rollouts) do
          if rollout_file:find(uuid_short) then
            -- Parse this rollout file
            local read_ok, lines = pcall(vim.fn.readfile, rollout_file)
            if not read_ok or not lines then goto continue end
            for _, line in ipairs(lines) do
              local ok, obj = pcall(vim.json.decode, line)
              if not ok then goto continue end
              local p = obj.payload or {}
              local t = obj.type

              if t == "session_meta" then
                local provenance = p.base_instructions and p.base_instructions.provenance
                if provenance then model = provenance.model end
                first_ts = p.timestamp
              elseif t == "token_usage_record" then
                local usage = p.turn_token_usage or p.usage or {}
                total_input = total_input + (usage.input_tokens or 0)
                total_output = total_output + (usage.output_tokens or 0)
                total_cache = total_cache + (usage.cached_input_tokens or 0)
              elseif t == "event_msg" and p.type == "task_complete" then
                last_agent_msg = p.last_agent_message or ""
                last_ts = p.completed_at
              end
            end
            -- Break after finding the matching file
            break
          end
          ::continue::
        end
      end
    end
  end

  if model then details.model = model end
  if total_input > 0 or total_output > 0 then
    details.tokens = { input = total_input, output = total_output, cache = total_cache }
  end
  if last_agent_msg and last_agent_msg ~= "" then
    -- Truncate long messages
    details.result = last_agent_msg:sub(1, 500)
  end
  if first_ts and last_ts then
    -- Parse ISO timestamps roughly
    details.duration = 0 -- Would need full ISO parsing; skip for now
  end

  if details.model or details.result or details.tokens then
    return details
  end
  return nil
end

-- Load session details from OpenCode SQLite database
-- OpenCode stores sessions at ~/.local/share/opencode/opencode.db
local function load_opencode_session_details(session_id)
  if not session_id then return nil end
  local db_path = vim.fn.expand("~/.local/share/opencode/opencode.db")
  local stat = (vim.uv or vim.loop).fs_stat(db_path)
  if not stat then return nil end

  local details = {}

  -- Query session_v2 for session data
  local query = string.format(
    [[SELECT id, title, model, cost, tokens_input, tokens_output, tokens_cache_read, summary_files, summary_additions, summary_deletions, time_created, time_updated FROM session_v2 WHERE id='%s']],
    session_id
  )
  local result = vim.fn.system("sqlite3 " .. db_path .. " \"" .. query .. "\" 2>/dev/null")
  if result and result ~= "" and not result:find("Error") then
    local fields = vim.split(result, "|")
    if #fields >= 12 then
      details.title = fields[2]
      -- Model is JSON: {"id":"...","providerID":"..."}
      if fields[3] and fields[3] ~= "" then
        local ok, model_json = pcall(vim.json.decode, fields[3])
        if ok and model_json.id then
          details.model = model_json.id
        end
      end
      details.cost = tonumber(fields[4]) or 0
      details.tokens = {
        input = tonumber(fields[5]) or 0,
        output = tonumber(fields[6]) or 0,
        cache = tonumber(fields[7]) or 0,
      }
      local summary_files = tonumber(fields[8]) or 0
      if summary_files > 0 then
        details.files_count = summary_files
      end
      -- Duration from timestamps (milliseconds)
      local created = tonumber(fields[11]) or 0
      local updated = tonumber(fields[12]) or 0
      if created > 0 and updated > 0 then
        details.duration = math.floor((updated - created) / 1000)
      end
    end
  end

  -- Get last assistant message
  local msg_query = string.format(
    [[SELECT data FROM session_message WHERE session_id='%s' AND type='assistant' ORDER BY seq DESC LIMIT 1]],
    session_id
  )
  local msg_result = vim.fn.system("sqlite3 " .. db_path .. " \"" .. msg_query .. "\" 2>/dev/null")
  if msg_result and msg_result ~= "" then
    local ok, msg_obj = pcall(vim.json.decode, msg_result)
    if ok and msg_obj.content then
      for _, part in ipairs(msg_obj.content) do
        if part.type == "text" and part.text and part.text ~= "" then
          details.result = part.text:sub(1, 500)
          break
        end
      end
    end
  end

  if details.model or details.result or details.tokens then
    return details
  end
  return nil
end

-- Load session details from Kiro session files
-- Kiro stores sessions at ~/.kiro/sessions/<hash>/sess_<id>/session.json + messages.jsonl
local function load_kiro_session_details(session_id)
  if not session_id then return nil end
  local kiro_home = vim.fn.expand("~/.kiro")
  local sessions_dir = kiro_home .. "/sessions"
  local details = {}

  -- Find the session directory by searching for session.json with matching ID
  local hashes = vim.fn.glob(sessions_dir .. "/*", true, true)
  local found_session_dir = nil
  for _, hash_dir in ipairs(hashes) do
    local sess_dirs = vim.fn.glob(hash_dir .. "/*", true, true)
    for _, sess_dir in ipairs(sess_dirs) do
      local session_file = sess_dir .. "/session.json"
      local stat = (vim.uv or vim.loop).fs_stat(session_file)
      if stat then
        local read_ok, lines = pcall(vim.fn.readfile, session_file)
        if read_ok and lines and #lines > 0 then
          local ok, sess = pcall(vim.json.decode, table.concat(lines, "\n"))
          if ok and sess.id == session_id then
            found_session_dir = sess_dir
            details.title = sess.title
            details.model = sess.modelId
            details.lifecycle = sess.status
            -- Duration from timestamps
            if sess.createdAt and sess.lastModifiedAt then
              -- Simple ISO parse: extract seconds difference
              local function parse_iso(ts)
                local y, m, d, h, mi, s = ts:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
                if y then
                  return os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d),
                                   hour = tonumber(h), min = tonumber(mi), sec = tonumber(s) })
                end
                return 0
              end
              local created = parse_iso(sess.createdAt)
              local modified = parse_iso(sess.lastModifiedAt)
              if created > 0 and modified > 0 then
                details.duration = modified - created
              end
            end
            break
          end
        end
      end
    end
    if found_session_dir then break end
  end

  if not found_session_dir then return nil end

  -- Parse messages.jsonl for usage summary and last assistant message
  local messages_file = found_session_dir .. "/messages.jsonl"
  local stat = (vim.uv or vim.loop).fs_stat(messages_file)
  if stat then
    local read_ok, lines = pcall(vim.fn.readfile, messages_file)
    if read_ok and lines and #lines > 0 then
      local last_assistant = ""
      local total_usage = 0
      for _, line in ipairs(lines) do
        local ok, obj = pcall(vim.json.decode, line)
        if not ok then goto continue end
        local p = obj.payload or {}
        local t = p.type

        if t == "usage_summary" then
          -- Sum up credit usage
          local prompt_summaries = p.promptTurnSummaries or {}
          for _, ps in ipairs(prompt_summaries) do
            total_usage = total_usage + (ps.usage or 0)
          end
          if total_usage > 0 then
            details.cost = total_usage
          end
          if p.elapsedTime then
            details.duration = math.floor(p.elapsedTime / 1000)
          end
        elseif t == "assistant" and p.content and p.content ~= "" then
          last_assistant = p.content
        end
        ::continue::
      end
      if last_assistant and last_assistant ~= "" and last_assistant ~= "..." then
        details.result = last_assistant:sub(1, 500)
      end
    end
  end

  if details.model or details.result or details.cost then
    return details
  end
  return nil
end

-- Load session details from Claude Code session JSONL files
-- Claude stores sessions at ~/.claude/projects/<project>/<uuid>.jsonl
local function load_claude_session_details(session_id)
  if not session_id then return nil end
  local claude_home = vim.fn.expand("~/.claude")
  local projects_dir = claude_home .. "/projects"
  local details = {}

  -- Search all project directories for the session file
  local projects = vim.fn.glob(projects_dir .. "/*", true, true)
  local found_file = nil
  for _, project_dir in ipairs(projects) do
    local session_files = vim.fn.glob(project_dir .. "/*", true, true)
    for _, f in ipairs(session_files) do
      if f:find(session_id) then
        found_file = f
        break
      end
    end
    if found_file then break end
  end

  if not found_file then return nil end

  -- Parse the JSONL file for cost-state and assistant messages
  local read_ok, lines = pcall(vim.fn.readfile, found_file)
  if not read_ok or not lines or #lines == 0 then return nil end

  local last_cost_state = nil
  local last_assistant = ""

  for _, line in ipairs(lines) do
    local ok, obj = pcall(vim.json.decode, line)
    if not ok then goto continue end
    local t = obj.type

    if t == "cost-state" then
      last_cost_state = obj
    elseif t == "assistant" then
      local content = obj.content
      if type(content) == "string" and content ~= "" then
        last_assistant = content
      elseif type(content) == "table" then
        for _, part in ipairs(content) do
          if type(part) == "table" and part.text and part.text ~= "" then
            last_assistant = part.text
            break
          end
        end
      end
    end
    ::continue::
  end

  if last_cost_state then
    details.cost = last_cost_state.totalCostUSD or 0
    details.duration = math.floor((last_cost_state.totalDuration or 0) / 1000)
    local lines_added = last_cost_state.totalLinesAdded or 0
    local lines_removed = last_cost_state.totalLinesRemoved or 0
    if lines_added > 0 or lines_removed > 0 then
      details.files_count = string.format("+%d/-%d lines", lines_added, lines_removed)
    end
    -- Model usage
    local model_usage = last_cost_state.modelUsage or {}
    for model_name, usage in pairs(model_usage) do
      if type(usage) == "table" then
        details.model = model_name
        details.tokens = {
          input = usage.inputTokens or 0,
          output = usage.outputTokens or 0,
        }
        break -- Take first model
      end
    end
  end

  if last_assistant and last_assistant ~= "" then
    details.result = last_assistant:sub(1, 500)
  end

  if details.model or details.result or details.cost then
    return details
  end
  return nil
end

-- Cache for session details to avoid re-reading files on every hover
local session_details_cache = {}

-- Get session details, using cache if available
local function get_session_details(provider, session_id)
  if not provider or not session_id then return nil end
  local cache_key = provider .. ":" .. session_id
  if session_details_cache[cache_key] then
    return session_details_cache[cache_key]
  end

  local details = nil
  if provider == "Junie" then
    details = load_junie_session_details(session_id)
  elseif provider == "Codex" then
    details = load_codex_session_details(session_id)
  elseif provider == "OpenCode" then
    details = load_opencode_session_details(session_id)
  elseif provider == "Kiro" then
    details = load_kiro_session_details(session_id)
  elseif provider == "Claude Code" then
    details = load_claude_session_details(session_id)
  end

  if details then
    session_details_cache[cache_key] = details
  end
  return details
end

-- Namespace for task summary highlights
local task_details_ns = nil
local function get_task_details_ns()
  if task_details_ns == nil then
    task_details_ns = vim.api.nvim_create_namespace("_agent_task_details_hl")
  end
  return task_details_ns
end

-- Build detailed lines for a task (used by float details panel)
-- Returns { lines = {...}, files = { line_idx -> file_path } }
local function task_details_lines(entry, width)
  width = width or 60
  local lines = {}
  local files = {}  -- maps 1-based line index -> file path
  local sep = string.rep("─", math.min(width, 80))

  if not entry then
    return { lines = { "  Hover over a task and press K to see details" }, files = {} }
  end

  local task = entry.task

  -- Different details for GitHub issues vs local tasks
  if entry.kind == "issue" then
    local title = task.title or "Untitled issue"
    local state_icon = task.state == "open" and nf.circle or nf.check
    table.insert(lines, "  " .. nf.external .. " GitHub Issue #" .. tostring(task.number))
    table.insert(lines, "")
    for _, wl in ipairs(wrap_text("  " .. state_icon .. " " .. title, width)) do
      table.insert(lines, wl)
    end
    table.insert(lines, "")
    if task.state then table.insert(lines, "  State:    " .. task.state) end
    if task.assignee then
      local assignee = type(task.assignee) == "table" and (task.assignee.login or "") or tostring(task.assignee)
      if assignee ~= "" then table.insert(lines, "  Assignee: " .. assignee) end
    end
    if task.labels and #task.labels > 0 then
      local label_names = {}
      for _, lb in ipairs(task.labels) do
        if type(lb) == "string" then table.insert(label_names, lb)
        elseif lb and lb.name then table.insert(label_names, lb.name) end
      end
      if #label_names > 0 then table.insert(lines, "  Labels:   " .. table.concat(label_names, ", ")) end
    end
    if task.created_at then table.insert(lines, "  Created:  " .. task.created_at) end
    if task.html_url or task.url then table.insert(lines, "  URL:      " .. (task.html_url or task.url)) end
    if task.body and task.body ~= "" then
      table.insert(lines, "")
      for _, wl in ipairs(wrap_text("  Description:", width)) do
        table.insert(lines, wl)
      end
      for line in (task.body):gmatch("[^\n]+") do
        for _, wl in ipairs(wrap_text("    " .. line, width)) do
          table.insert(lines, wl)
        end
      end
    end
  else
    -- Full local task details
    local status = task.status or (task.done and "completed" or "pending")
    local status_icons = {
      pending = nf.circle, in_progress = nf.play, completed = nf.check,
      failed = nf.close, archived = nf.package,
    }
    local status_icon = status_icons[status] or nf.circle
    local title = task.title or "Untitled"

    table.insert(lines, "  " .. nf.wrench .. " Task Details")
    table.insert(lines, "")
    for _, wl in ipairs(wrap_text("  " .. title, width)) do
      table.insert(lines, wl)
    end
    table.insert(lines, "")
    table.insert(lines, "  Status:   " .. status_icon .. " " .. status)
    if task.id then table.insert(lines, "  ID:       " .. task.id) end

    -- Session details
    local sessionDetails = nil
    if task.thread then
      table.insert(lines, "  Agent:    " .. (task.thread.provider or "Unknown"))
      local thread_id = task.thread.id and tostring(task.thread.id) or "new"
      table.insert(lines, "  Thread:   " .. thread_id)
      if task.thread.started_at then
        local duration = os.time() - task.thread.started_at
        table.insert(lines, "  Duration: " .. format_duration(duration))
      end
      sessionDetails = get_session_details(task.thread.provider, task.thread.id)
    end

    if sessionDetails then
      if not task.model and sessionDetails.model then task.model = sessionDetails.model end
      if not task.tokens and sessionDetails.tokens then task.tokens = sessionDetails.tokens end
      if not task.cost and sessionDetails.cost then task.cost = sessionDetails.cost end
      if not task.result and sessionDetails.result then task.result = sessionDetails.result end
    end

    if task.model and task.model ~= "" then table.insert(lines, "  Model:    " .. task.model) end
    if task.tokens then
      local tokens = task.tokens
      local total = tokens.total or (tokens.input or 0) + (tokens.output or 0)
      if tokens.input then table.insert(lines, "  Tokens:   " .. tostring(tokens.input) .. " in + " .. tostring(tokens.output or 0) .. " out = " .. total .. " total")
      else table.insert(lines, "  Tokens:   " .. total .. " total") end
    end
    if task.cost then table.insert(lines, "  Cost:     $" .. tostring(task.cost)) end
    if sessionDetails and sessionDetails.lifecycle then
      local lc_icon = sessionDetails.lifecycle == "COMPLETED" and nf.check or sessionDetails.lifecycle == "FAILED" and nf.close or nf.circle
      table.insert(lines, "  Lifecycle: " .. lc_icon .. " " .. sessionDetails.lifecycle)
    end

    -- Files changed (clickable/navigable section)
    if sessionDetails and sessionDetails.files_changed and #sessionDetails.files_changed > 0 then
      table.insert(lines, "")
      table.insert(lines, "  " .. nf.folder_open .. " Files Changed:")
      for _, f in ipairs(sessionDetails.files_changed) do
        local action = f.action or "Modified"
        local action_icon = f.action == "Edited" and nf.diff_modified or f.action == "Created" and nf.diff_added or f.action == "Read" and nf.file_default or nf.file_default
        local file_line = "    " .. action_icon .. " " .. action .. " " .. f.file
        local line_idx = #lines + 1
        table.insert(lines, file_line)
        -- Store file path for Enter keymap (use relative path from task cwd)
        local filePath = f.file
        if entry and entry.cwd then
          -- Try relative path first, then absolute
          if not filePath:match("^/") then
            filePath = entry.cwd .. "/" .. filePath
          end
        end
        files[line_idx] = filePath
      end
    elseif sessionDetails and sessionDetails.files_count then
      local fc = sessionDetails.files_count
      table.insert(lines, "  Files:    " .. (type(fc) == "number" and (fc .. " files") or fc))
    end

    -- Criteria and verification
    if task.acceptance_criteria and task.acceptance_criteria ~= "" then
      table.insert(lines, "")
      table.insert(lines, "  Acceptance Criteria:")
      for line in (task.acceptance_criteria):gmatch("[^\n]+") do
        for _, wl in ipairs(wrap_text("    " .. line, width)) do
          table.insert(lines, wl)
        end
      end
    end
    if task.verification_command and task.verification_command ~= "" then
      table.insert(lines, "")
      table.insert(lines, "  Verification:")
      table.insert(lines, "    " .. task.verification_command)
    end
    if task.last_check then
      table.insert(lines, "")
      table.insert(lines, "  Last Check: exit " .. tostring(task.last_check.exit_code))
      table.insert(lines, "    " .. os.date("%Y-%m-%d %H:%M", task.last_check.checked_at or os.time()))
    end

    -- Result
    if task.result and task.result ~= "" then
      table.insert(lines, "")
      table.insert(lines, "  Result:")
      for line in (tostring(task.result)):gmatch("[^\n]+") do
        for _, wl in ipairs(wrap_text("    " .. line, width)) do
          table.insert(lines, wl)
        end
      end
    end
  end -- close if/else for entry.kind

  table.insert(lines, sep)
  return { lines = lines, files = files }
end

update_threads_winbar = function()
  -- Fixed winbar: Tabs + Project Title (Tasks only) + Pills (Tasks only)
  if not threads_win or not vim.api.nvim_win_is_valid(threads_win) then return end
  local items = {}
  -- Tabs
  local threadsHl = active_threads_tab == "threads" and "AgentTabActive" or "AgentTabInactive"
  local tasksHl = active_threads_tab == "tasks" and "AgentTabActive" or "AgentTabInactive"
  table.insert(items, "%#" .. threadsHl .. "# Threads %#" .. "AgentTabInactive" .. "#   %#" .. tasksHl .. "# Tasks %#" .. "AgentTabInactive" .. "#")
  -- Pills (only in Tasks tab)
  if active_threads_tab == "tasks" then
    local localPillHl = active_task_pill == "local" and "AgentPillActive" or "AgentPillInactive"
    local githubPillHl = active_task_pill == "github" and "AgentPillActive" or "AgentPillInactive"
    local localText = active_task_pill == "local" and "[Local]" or "Local"
    local githubText = active_task_pill == "github" and "[GitHub]" or "GitHub"
    table.insert(items, "   %#" .. localPillHl .. "# " .. localText .. " %#" .. "AgentPillInactive" .. "#   %#" .. githubPillHl .. "# " .. githubText .. " %#" .. "AgentPillInactive" .. "#")
  end
  vim.wo[threads_win].winbar = table.concat(items, "")
end

local function render_tasks()
  if not threads_buf or not vim.api.nvim_buf_is_valid(threads_buf) or active_threads_tab ~= "tasks" then return end
  task_row_map = {}
  local cwd = task_project_cwd or vim.fn.getcwd()
  local width = M._ui.panel_width(threads_buf, threads_width)
  local b = M._ui.builder(width)
  local tasks_module = require("lenn.agent-tasks")

  b:add({})
  b:add({ { " " .. nf.ui_root_folder_open .. " ", "AgentCurrentProject" },
    { M._ui.fit(project_name(cwd), width - 10), "AgentCurrentProject" } },
    { "[/]", "AgentBadge" })

  if active_task_pill == "local" then
    local local_tasks = tasks_module.local_tasks(cwd)
    local categories = {
      { id = "pending", title = "Pending", icon = nf.task_pending, hl = "AgentTaskPending" },
      { id = "in_progress", title = "In progress", icon = nf.task_progress, hl = "AgentTaskInProgress" },
      { id = "completed", title = "Completed", icon = nf.task_done, hl = "AgentTaskCompleted" },
      { id = "failed", title = "Failed", icon = nf.task_failed, hl = "AgentTaskFailed" },
      { id = "archived", title = "Archived", icon = nf.task_archived, hl = "AgentTaskArchived" },
    }
    local groups = {}
    for _, category in ipairs(categories) do groups[category.id] = {} end
    for _, task in ipairs(local_tasks) do
      local status = task.status or (task.done and "completed" or "pending")
      if not groups[status] then status = "pending" end
      table.insert(groups[status], task)
    end
    -- Fold state: archived folded by default
    for _, category in ipairs(categories) do
      if task_folds[category.id] == nil then task_folds[category.id] = category.id == "archived" end
    end

    b:add({})
    for _, category in ipairs(categories) do
      local folded = task_folds[category.id]
      local items = groups[category.id]
      local row = b:add({
        { " " .. (folded and nf.ui_chevron_right or nf.ui_chevron_down) .. " ", "AgentTreeGuide" },
        { category.icon .. " ", category.hl },
        { category.title, category.hl },
      }, { tostring(#items), "AgentBadge" })
      task_row_map[row] = { kind = "category", category = category.id, cwd = cwd }

      if not folded then
        if #items == 0 then
          b:add({ { "   ╰ ", "AgentTreeGuide" }, { "empty", "Comment" } })
        end
        for i, task in ipairs(items) do
          local last = i == #items
          local guide = last and "   ╰ " or "   ├ "
          local cont = last and "     " or "   │ "
          local right
          if task.thread then
            local icon = "?"
            for _, p in ipairs(providers) do
              if p.name == task.thread.provider then icon = nf.normalize(p.icon) end
            end
            right = { icon, "AgentProvider" .. (task.thread.provider or ""):gsub("%W", "") }
          end
          row = b:add({
            { guide, "AgentTreeGuide" },
            { M._ui.fit(task.title, width - 8), category.id == "archived" and "AgentTaskArchived" or "AgentTaskTitle" },
          }, right)
          task_row_map[row] = { kind = "local", task = task, cwd = cwd }

          local details = {}
          if task.acceptance_criteria and task.acceptance_criteria ~= "" then
            table.insert(details, { nf.task_criteria, task.acceptance_criteria })
          end
          if task.verification_command and task.verification_command ~= "" then
            table.insert(details, { nf.task_verify, task.verification_command })
          end
          if task.last_check then
            local passed = tonumber(task.last_check.exit_code) == 0
            table.insert(details, { nf.task_history, string.format("%s exit %s · %s",
              passed and "pass" or "fail", tostring(task.last_check.exit_code),
              M._ui.rel_time(task.last_check.checked_at)), passed and "AgentTaskCompleted" or "AgentTaskFailed" })
          end
          for _, d in ipairs(details) do
            b:add({ { cont, "AgentTreeGuide" }, { d[1] .. " ", d[3] or "AgentTaskDetailIcon" },
              { M._ui.fit(d[2], width - 9), "Comment" } })
          end
        end
      end
    end
  else
    -- GitHub issues pill
    b:add({})
    if task_issue_message then
      b:add({ { "   " .. nf.github .. " ", "Comment" }, { M._ui.fit(task_issue_message, width - 6), "Comment" } })
    elseif #task_issues == 0 then
      b:add({ { "   " .. nf.github .. " ", "Comment" }, { "No open issues", "Comment" } })
    end
    local tracked = {}
    for _, task in ipairs(tasks_module.local_tasks(cwd)) do
      if task.source_issue_url then tracked[task.source_issue_url] = true end
    end
    for _, issue in ipairs(task_issues) do
      local is_tracked = tracked[issue.html_url or issue.url]
      local number = "#" .. tostring(issue.number)
      local row = b:add({
        { " " .. (is_tracked and nf.issue_tracked or nf.issue) .. " ", is_tracked and "AgentTaskCompleted" or "AgentTaskPending" },
        { number .. " ", "AgentBadge" },
        { M._ui.fit(issue.title or "Untitled issue", width - 6 - #number - (is_tracked and 2 or 0)), "AgentTaskTitle" },
      }, is_tracked and { nf.check, "AgentTaskCompleted" } or nil)
      task_row_map[row] = { kind = "issue", task = issue, cwd = cwd }
    end
  end

  b:apply(threads_buf, get_threads_ns())
  update_threads_winbar()
  ensure_cursor_on_content()
end

local function refresh_tasks(cwd)
  task_project_cwd = cwd or task_project_cwd or vim.fn.getcwd()
  task_load_sequence = task_load_sequence + 1
  local seq = task_load_sequence
  task_issue_message = "Loading GitHub issues…"
  render_tasks()
  require("lenn.agent-tasks").issues(task_project_cwd, function(issues, err)
    if seq ~= task_load_sequence then return end
    task_issues = issues
    task_issue_message = err
    render_tasks()
  end)
end

local function selected_project_cwd()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  return project_row_map[row] or (thread_row_map[row] and thread_row_map[row].cwd) or task_project_cwd or vim.fn.getcwd()
end

local function switch_task_pill()
  if active_task_pill == "local" then
    active_task_pill = "github"
  else
    active_task_pill = "local"
  end
  render_tasks()
  render_keymaps_panel()
end

-- Toggle fold for a task category
local function toggle_task_fold()
  if active_threads_tab ~= "tasks" or active_task_pill ~= "local" then return end
  local row = vim.api.nvim_win_get_cursor(0)[1]
  -- Check if cursor is on a category header line
  local entry = task_row_map[row]
  if not entry or entry.kind ~= "category" then return end
  local id = entry.category
  -- Toggle fold state
  if task_folds[id] == nil then
    task_folds[id] = (id == "archived") -- archived folded by default
  end
  task_folds[id] = not task_folds[id]
  render_tasks()
end

local function switch_threads_tab()
  local uv = vim.uv or vim.loop
  local now = uv.now()
  if now - last_agent_tab_key_ms < 650 then
    -- Terminal key repeat has no release event; suppress repeats so a held Tab
    -- advances only once, requiring a press-and-release cycle to switch again.
    last_agent_tab_key_ms = now
    return
  end
  last_agent_tab_key_ms = now

  if active_threads_tab == "threads" then
    task_project_cwd = selected_project_cwd()
    active_threads_tab = "tasks"
    active_task_pill = "local"  -- reset to Local pill when entering Tasks
    refresh_tasks(task_project_cwd)
  else
    -- Close the details float if open
    if task_details_float and vim.api.nvim_win_is_valid(task_details_float) then
      pcall(vim.api.nvim_win_close, task_details_float, true)
      task_details_float = nil
    end
    active_threads_tab = "threads"
    if threads_win and vim.api.nvim_win_is_valid(threads_win)
      and vim.api.nvim_win_get_buf(threads_win) ~= threads_buf then
      vim.api.nvim_win_set_buf(threads_win, threads_buf)
    end
    render_threads(threads_data)
  end
  update_threads_winbar()
  render_keymaps_panel()
  if threads_win and vim.api.nvim_win_is_valid(threads_win) then
    pcall(vim.api.nvim_win_set_cursor, threads_win, { 1, 0 })
  end
end

local function cycle_task_project(direction)
  local projects, seen = {}, {}
  for _, thread in ipairs(threads_data) do
    if thread.cwd and thread.cwd ~= "" and not seen[thread.cwd] then
      seen[thread.cwd] = true
      table.insert(projects, thread.cwd)
    end
  end
  local current = vim.fn.getcwd()
  if not seen[current] then table.insert(projects, current) end
  table.sort(projects)
  if #projects < 2 then return end
  local index = 1
  for i, cwd in ipairs(projects) do
    if cwd == task_project_cwd then index = i; break end
  end
  index = ((index - 1 + direction) % #projects) + 1
  refresh_tasks(projects[index])
end

local function add_local_task()
  local cwd = task_project_cwd or selected_project_cwd()
  vim.ui.input({ prompt = "New task: " }, function(title)
    if not title or title:match("^%s*$") then return end
    vim.ui.input({ prompt = "Acceptance criteria (optional): " }, function(criteria)
      if criteria == nil then return end
      vim.ui.input({ prompt = "Verification command (optional): " }, function(command)
        if command == nil then return end
        local task = require("lenn.agent-tasks").add_local(cwd, title, criteria, command)
        if not task then
          vim.notify("Could not save task", vim.log.levels.ERROR)
          return
        end
        refresh_tasks(cwd)
      end)
    end)
  end)
end

local function get_tracked_task(entry)
  if entry.kind == "local" then return entry.task end
  return require("lenn.agent-tasks").track_issue(entry.cwd, entry.task)
end

local function set_task_status_for_id(cwd, task_id, status)
  if not require("lenn.agent-tasks").update_local(cwd, task_id, { status = status }) then
    vim.notify("Could not save task status", vim.log.levels.ERROR)
    return false
  end
  refresh_tasks(cwd)
  return true
end

local function set_task_status(status)
  local entry = task_row_map[vim.api.nvim_win_get_cursor(0)[1]]
  if not entry then return end
  local task = get_tracked_task(entry)
  if not task then
    vim.notify("Could not save this task", vim.log.levels.ERROR)
    return
  end
  set_task_status_for_id(entry.cwd, task.id, status)
end

local function open_task_thread()
  local entry = task_row_map[vim.api.nvim_win_get_cursor(0)[1]]
  if not entry then return end
  local task = entry.kind == "local" and entry.task or nil
  if not task or not task.thread then
    vim.notify("Assign this task to an agent first with >", vim.log.levels.INFO)
    return
  end
  if not task.thread.id then
    if task.thread.provider == "Claude Code" then
      M.launch_provider("Claude Code", "resume-picker", entry.cwd)
      return
    end
    vim.notify("The agent thread is starting; refresh shortly and try again", vim.log.levels.INFO)
    return
  end
  current_thread_id = task.thread.id
  M.launch_provider(task.thread.provider, task.thread.id, entry.cwd)
end

local function verify_task()
  local entry = task_row_map[vim.api.nvim_win_get_cursor(0)[1]]
  if not entry or entry.kind ~= "local" then return end
  local task = entry.task
  local command = task.verification_command
  if not command or command:match("^%s*$") then
    local criterion = task.acceptance_criteria and task.acceptance_criteria ~= ""
      and ("\n\nCriteria: " .. task.acceptance_criteria) or ""
    vim.ui.select({ "Completed", "Failed", "Cancel" }, {
      prompt = "Manual verification" .. criterion,
      format_item = function(item) return item end,
    }, function(choice)
      if choice == "Completed" then set_task_status_for_id(entry.cwd, task.id, "completed")
      elseif choice == "Failed" then set_task_status_for_id(entry.cwd, task.id, "failed") end
    end)
    return
  end

  vim.ui.select({ "Run: " .. command, "Cancel" }, {
    prompt = "Run task verification in " .. project_name(entry.cwd) .. "?",
    format_item = function(item) return item end,
  }, function(choice)
    if not choice or choice == "Cancel" then return end
    local tasks = require("lenn.agent-tasks")
    tasks.update_local(entry.cwd, task.id, { status = "in_progress" })
    refresh_tasks(entry.cwd)
    local output = {}
    local shell = vim.o.shell or "sh"
    local shell_flag = vim.o.shellcmdflag or "-c"
    local job = vim.fn.jobstart({ shell, shell_flag, command }, {
      cwd = entry.cwd,
      stdout_buffered = true,
      stderr_buffered = true,
      on_stdout = function(_, data) if data then vim.list_extend(output, data) end end,
      on_stderr = function(_, data) if data then vim.list_extend(output, data) end end,
      on_exit = function(_, code)
        vim.schedule(function()
          local status = code == 0 and "completed" or "failed"
          tasks.update_local(entry.cwd, task.id, {
            status = status,
            last_check = {
              command = command,
              exit_code = code,
              checked_at = os.time(),
              output = table.concat(output, "\n"):sub(1, 2000),
            },
          })
          refresh_tasks(entry.cwd)
          local result = code == 0 and "passed" or "failed"
          vim.notify("Task verification " .. result .. " (exit " .. tostring(code) .. ")")
        end)
      end,
    })
    if job <= 0 then
      tasks.update_local(entry.cwd, task.id, { status = "failed" })
      refresh_tasks(entry.cwd)
      vim.notify("Could not start verification command", vim.log.levels.ERROR)
    end
  end)
end

local function link_new_task_thread(cwd, task, provider_name, previous_threads, launched_session)
  local known = {}
  for _, thread in ipairs(previous_threads) do
    if thread.provider == provider_name and thread.cwd == cwd and thread.id then known[thread.id] = true end
  end
  local attempts = 0
  local function find_thread()
    attempts = attempts + 1
    collect_threads(function(threads)
      for _, thread in ipairs(threads) do
        if thread.id and thread.provider == provider_name and thread.cwd == cwd and not known[thread.id] then
          if launched_session then
            launched_session.thread_id = thread.id
            launched_session.tab_id = "task:" .. task.id
            if launched_session.bufnr then
              pcall(function() vim.b[launched_session.bufnr].agent_thread_id = thread.id end)
            end
          end
          require("lenn.agent-tasks").update_local(cwd, task.id, {
            thread = { provider = provider_name, id = thread.id, cwd = cwd, linked_at = os.time() },
          })
          refresh_tasks(cwd)
          render_agent_tabs()
          return
        end
      end
      if attempts < 30 then vim.defer_fn(find_thread, 1200) end
    end)
  end
  find_thread()
end

-- Send a task prompt to an already-running agent session
local function send_task_to_session(entry, prompt, session)
  -- Find the channel/job ID for this session
  local chanId = nil
  if session.kind == "toggleterm" and session.terminal then
    chanId = session.terminal.job_id or session.terminal.job
  elseif session.kind == "direct" then
    chanId = session.job
  end
  if not chanId then
    vim.notify("Cannot send to session: no active channel", vim.log.levels.WARN)
    return
  end
  -- Send the prompt to the running session
  local ok, err = pcall(vim.api.nvim_chan_send, chanId, prompt .. "\n")
  if ok then
    vim.notify("Task sent to active session: " .. (session.provider or "Agent"), vim.log.levels.INFO)
    -- Update task status to in_progress
    local tracked = get_tracked_task(entry)
    if tracked then
      require("lenn.agent-tasks").update_local(entry.cwd, tracked.id, {
        status = "in_progress",
      })
      refresh_tasks(entry.cwd)
    end
  else
    vim.notify("Failed to send task: " .. tostring(err), vim.log.levels.ERROR)
  end
end

local function dispatch_task()
  local entry = task_row_map[vim.api.nvim_win_get_cursor(0)[1]]
  if not entry then return end
  local task = entry.task
  local title = task.title or "Untitled task"
  local prompt = "Work on this task in the current project.\n\nTask: " .. title
  if task.acceptance_criteria and task.acceptance_criteria ~= "" then
    prompt = prompt .. "\n\nAcceptance criteria:\n" .. task.acceptance_criteria
  end
  if task.verification_command and task.verification_command ~= "" then
    prompt = prompt .. "\n\nVerification command to run when ready:\n" .. task.verification_command
  end
  if entry.kind == "issue" then
    prompt = prompt .. "\nIssue: #" .. tostring(task.number or "") .. " " .. tostring(task.html_url or task.url or "")
  end
  if task.body and task.body ~= "" then prompt = prompt .. "\n\nDetails:\n" .. task.body end

  -- Build options: active sessions first, then "New thread..."
  local options = {}
  local runningSessions = get_running_project_sessions()
  for _, sess in ipairs(runningSessions) do
    local statusIcon = sess.running and nf.play or nf.circle
    local label = string.format("%s %s — %s", statusIcon, sess.provider or "Agent", sess.task_title or sess.name or "Session")
    table.insert(options, { kind = "session", label = label, session = sess })
  end
  -- Add provider options for new threads
  for _, provider in ipairs(providers) do
    table.insert(options, { kind = "provider", label = string.format("%s %s", nf.normalize(provider.icon), provider.name), provider = provider })
  end

  vim.ui.select(options, {
    prompt = "Send task to:",
    format_item = function(opt) return opt.label end,
  }, function(chosen)
    if not chosen then return end
    if chosen.kind == "session" then
      -- Send to active session
      send_task_to_session(entry, prompt, chosen.session)
    elseif chosen.kind == "provider" then
      -- Create new thread with the selected provider
      local provider = chosen.provider
      local tracked = get_tracked_task(entry)
      if not tracked then
        vim.notify("Could not save this task", vim.log.levels.ERROR)
        return
      end
      require("lenn.agent-tasks").update_local(entry.cwd, tracked.id, {
        status = "in_progress",
        thread = { provider = provider.name, cwd = entry.cwd, started_at = os.time() },
      })
      refresh_tasks(entry.cwd)
      -- Switch to full mode so the agent terminal appears in the proper panel
      if current_workspace_mode ~= "full" then
        M.set_mode("full")
      elseif not panels_visible then
        open_panels()
      end
      collect_threads(function(previous_threads)
        launch_in_project(provider.name, entry.cwd, prompt, function()
          local launched_session = current_term
          link_new_task_thread(entry.cwd, tracked, provider.name, previous_threads, launched_session)
          render_agent_panel()
        end, {
          task_id = tracked.id,
          task_title = title,
          tab_id = "task:" .. tracked.id,
          change_snapshot = project_file_stats(entry.cwd),
        })
      end)
    end
  end)
end

-- ─── Skills Panel (separate buffer & window) ────────────────────────────────

local function render_skills()
  if not skills_buf or not vim.api.nvim_buf_is_valid(skills_buf) then return end

  local skills = require("lenn.agent-skills").get_skills()

  local lines = {
    "",
  }

  -- Reset row map
  skills_row_map = {}

  if #skills == 0 then
    table.insert(lines, "  No skills installed")
  else
    for _, skill in ipairs(skills) do
      local status = skill.enabled and nf.check or nf.circle
      local desc_preview = ""
      if skill.description and skill.description:len() > 0 then
        local desc = skill.description:gsub("\n", " "):gsub("%s+", " "):gsub("^%s+", "")
        if desc:len() > 30 then
          desc = desc:sub(1, 27) .. "..."
        end
        desc_preview = " — " .. desc
      end
      local line = string.format("  [%s] %s%s", status, skill.name, desc_preview)
      table.insert(lines, line)
      skills_row_map[#lines] = skill
    end
  end

  table.insert(lines, "")

  vim.bo[skills_buf].modifiable = true
  vim.api.nvim_buf_set_lines(skills_buf, 0, -1, false, lines)
  vim.bo[skills_buf].modifiable = false

  -- Highlight enabled skill lines in green, disabled in gray
  local ns = get_skills_ns()
  vim.api.nvim_buf_clear_namespace(skills_buf, ns, 0, -1)
  vim.api.nvim_buf_add_highlight(skills_buf, ns, "Comment", 0, 0, -1)
  for row, skill in pairs(skills_row_map) do
    local hl_group = skill.enabled and "AgentEnabledSkill" or "AgentDisabledSkill"
    vim.api.nvim_buf_add_highlight(skills_buf, ns, hl_group, row - 1, 0, -1)
  end
end

local function toggle_skill_in_skills_buf()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local skill = skills_row_map[row]
  if not skill then return end

  require("lenn.agent-skills").toggle(skill.name)
  render_skills()
  M.refresh_threads()
end

local function read_skill_doc_from_skills_buf()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local skill = skills_row_map[row]
  if not skill or not skill.path then return end

  vim.cmd("split " .. vim.fn.fnameescape(skill.path))
end

local function open_skill_market()
  require("lenn.skill-market").open()
end

function M.refresh_skills()
  render_skills()
end

-- ─── Keymaps Panel ──────────────────────────────────────────────────────────


-- Keymap definitions for each panel, grouped by section
local PANEL_KEYMAPS = {
  threads = {
    navigation = {
      { key = "j/k", desc = "Move cursor" },
      { key = "l", desc = "Expand project" },
      { key = "h", desc = "Collapse project" },
    },
    actions = {
      { key = "+", desc = "New in project" },
      { key = "<CR>", desc = "Open thread" },
      { key = "A", desc = "Add/create project" },
      { key = "D", desc = "Remove saved project" },
      { key = "r", desc = "Refresh" },
    },
    panels = {
      { key = "<Tab>", desc = "Switch Threads/Tasks" },
      { key = "M-m", desc = "Minimize/restore" },
      { key = "M-q", desc = "Pick window" },
      { key = "q", desc = "Close panels" },
    },
  },
  tasks_local = {
    navigation = {
      { key = "j/k", desc = "Move cursor" },
      { key = "p", desc = "Switch pill" },
      { key = "za", desc = "Fold/Unfold category" },
      { key = "K", desc = "Task details" },
    },
    actions = {
      { key = "+", desc = "Add task" },
      { key = ">", desc = "Send to session/thread" },
      { key = "o", desc = "Open thread" },
      { key = "v", desc = "Verify" },
    },
    status = {
      { key = "x", desc = "Done" },
      { key = "f", desc = "Fail" },
      { key = "a", desc = "Archive" },
      { key = "u", desc = "Restore" },
    },
    panels = {
      { key = "<Tab>", desc = "Switch Threads/Tasks" },
      { key = "q", desc = "Close panels" },
    },
  },
  tasks_github = {
    navigation = {
      { key = "j/k", desc = "Move cursor" },
      { key = "p", desc = "Switch pill" },
      { key = "K", desc = "Issue details" },
    },
    actions = {
      { key = "+", desc = "Track locally" },
      { key = ">", desc = "Track locally" },
      { key = "<CR>", desc = "Open in browser" },
      { key = "l", desc = "Open in browser" },
    },
    panels = {
      { key = "<Tab>", desc = "Switch Threads/Tasks" },
      { key = "q", desc = "Close panels" },
    },
  },
  skills = {
    actions = {
      { key = "s", desc = "Toggle skill" },
      { key = "<CR>", desc = "Read skill doc" },
      { key = "m", desc = "Skill Market" },
      { key = "r", desc = "Refresh" },
    },
    panels = {
      { key = "q", desc = "Close panels" },
    },
  },
  agent = {
    navigation = {
      { key = "<Tab>", desc = "Next tab" },
      { key = "<S-Tab>", desc = "Prev tab" },
    },
    actions = {
      { key = "<CR>", desc = "Select provider" },
      { key = "S-p", desc = "Pick provider" },
      { key = "S-m", desc = "Market" },
    },
    session = {
      { key = "C-n", desc = "New session" },
      { key = "C-g", desc = "Panel from terminal" },
    },
    panels = {
      { key = "q", desc = "Close panels" },
    },
  },
}

-- Detect which panel is currently focused and return the keymap group name
local function detect_focused_panel()
  local cur_win = vim.api.nvim_get_current_win()
  if cur_win == threads_win then
    if active_threads_tab == "tasks" then
      if active_task_pill == "github" then
        return "tasks_github"
      end
      return "tasks_local"
    end
    return "threads"
  elseif cur_win == skills_win then
    return "skills"
  elseif cur_win == agent_win then
    return "agent"
  end
  -- Default: show the panel that has focus or the last focused panel
  return "threads"
end

-- Show task details in a floating window (triggered by K)
show_task_details_float = function()
  if active_threads_tab ~= "tasks" then return end

  -- Close any existing float and delete its buffer
  if task_details_float and vim.api.nvim_win_is_valid(task_details_float) then
    local old_buf = vim.api.nvim_win_get_buf(task_details_float)
    pcall(vim.api.nvim_win_close, task_details_float, true)
    if old_buf and vim.api.nvim_buf_is_valid(old_buf) then
      pcall(vim.api.nvim_buf_delete, old_buf, { force = true })
    end
    task_details_float = nil
  end
  -- Also delete any leftover buffer with the same name (e.g., closed with q without deleting buffer)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_name(buf) == "Agent Task Details" then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end

  local row = vim.api.nvim_win_get_cursor(0)[1]
  local entry = task_row_map[row]
  if not entry or (entry.kind ~= "local" and entry.kind ~= "issue") then
    vim.notify("Place cursor on a task or issue first", vim.log.levels.WARN)
    return
  end

  -- Create buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, "Agent Task Details")
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "agent-task-details"

  -- Build detail lines
  local width = 60
  local result = task_details_lines(entry, width)
  local lines = result.lines
  local fileMap = result.files
  task_details_files = fileMap  -- store globally for Enter keymap
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  -- Apply highlights
  local ns = get_task_details_ns()
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for i = 1, #lines do
    local line_text = lines[i] or ""
    if line_text:find("─") and line_text:len() > 10 then
      vim.api.nvim_buf_add_highlight(buf, ns, "AgentTaskSummarySep", i - 1, 0, -1)
    elseif line_text:find("  🔧") or line_text:find("  🔗") or line_text:find("  Status:") then
      vim.api.nvim_buf_add_highlight(buf, ns, "AgentTaskSummaryTitle", i - 1, 0, -1)
    elseif line_text:find("  [A-Za-z]+:") then
      vim.api.nvim_buf_add_highlight(buf, ns, "AgentTaskSummaryLabel", i - 1, 0, -1)
    elseif fileMap[i] then
      -- File line: highlight with URI color
      vim.api.nvim_buf_add_highlight(buf, ns, "AgentTaskSummaryLabel", i - 1, 0, -1)
    else
      vim.api.nvim_buf_add_highlight(buf, ns, "AgentTaskSummary", i - 1, 0, -1)
    end
  end

  -- Calculate float dimensions
  local height = math.min(#lines + 2, vim.o.lines - 3)
  local width = math.min(70, vim.o.columns - 10)
  local row_pos = math.floor((vim.o.lines - height) / 2)
  local col_pos = math.floor((vim.o.columns - width) / 2)

  -- Create floating window
  local config = {
    relative = "editor",
    row = row_pos,
    col = col_pos,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " Task Details ",
    title_pos = "center",
  }
  task_details_float = vim.api.nvim_open_win(buf, true, config)
  vim.wo[task_details_float].number = false
  vim.wo[task_details_float].relativenumber = false
  vim.wo[task_details_float].signcolumn = "no"
  vim.wo[task_details_float].foldcolumn = "0"
  vim.wo[task_details_float].spell = false
  vim.wo[task_details_float].winhighlight = "Normal:AgentTaskSummary,NormalFloat:AgentTaskSummary,FloatBorder:AgentTaskSummaryLabel"

  -- Open file with Enter when cursor is on a file line
  vim.keymap.set("n", "<CR>", function()
    local row = vim.api.nvim_win_get_cursor(task_details_float)[1]
    local filePath = task_details_files[row]
    if filePath then
      pcall(vim.api.nvim_win_close, task_details_float, true)
      task_details_float = nil
      task_details_files = {}
      -- Try to open the file
      if vim.fn.filereadable(filePath) > 0 then
        vim.cmd("edit " .. vim.fn.fnameescape(filePath))
      else
        -- Try relative to current project
        local projectPath = (task_project_cwd or vim.fn.getcwd()) .. "/" .. filePath
        if vim.fn.filereadable(projectPath) > 0 then
          vim.cmd("edit " .. vim.fn.fnameescape(projectPath))
        else
          vim.notify("File not found: " .. filePath, vim.log.levels.WARN)
        end
      end
    end
  end, { buffer = buf, desc = "Open file" })

  -- Close with q or <Esc> (also delete buffer to avoid E95 on reopen)
  local function close_task_details()
    if task_details_float and vim.api.nvim_win_is_valid(task_details_float) then
      local d_buf = vim.api.nvim_win_get_buf(task_details_float)
      pcall(vim.api.nvim_win_close, task_details_float, true)
      if d_buf and vim.api.nvim_buf_is_valid(d_buf) then
        pcall(vim.api.nvim_buf_delete, d_buf, { force = true })
      end
      task_details_float = nil
      task_details_files = {}
    end
  end
  vim.keymap.set("n", "q", close_task_details, { buffer = buf })
  vim.keymap.set("n", "<Esc>", close_task_details, { buffer = buf })
end

render_keymaps_panel = function()
  if not keymaps_buf or not vim.api.nvim_buf_is_valid(keymaps_buf) then return end
  if not keymaps_win or not vim.api.nvim_win_is_valid(keymaps_win) then return end

  local panel = detect_focused_panel()
  local keymaps = PANEL_KEYMAPS[panel] or PANEL_KEYMAPS.threads

  -- Section display names, icons and order (LunarVim style)
  local section_order = { "navigation", "actions", "status", "session", "panels" }
  local section_info = {
    navigation = { title = "Navigation", icon = "" },
    actions = { title = "Actions", icon = "" },
    status = { title = "Status", icon = "󰥜" },
    session = { title = "Session", icon = "󰖬" },
    panels = { title = "Panels", icon = "" },
  }

  -- Panel name display
  local panel_names = {
    threads = "Threads",
    tasks_local = "Tasks (Local)",
    tasks_github = "Tasks (GitHub)",
    skills = "Skills",
    agent = "Agent",
  }
  local panelDisplay = panel_names[panel] or "Threads"

  -- Build lines in LunarVim cheatsheet style
  local lines = {}
  local hl_entries = {} -- { line_idx, hl_group, col_start, col_end }

  -- Title: centered panel name (dynamic based on focused panel)
  local box_w = vim.api.nvim_win_get_width(keymaps_win)
  local title_text = "▓ " .. panelDisplay
  local title_pad = math.max(0, math.floor((box_w - #title_text) / 2))
  table.insert(lines, string.rep(" ", title_pad) .. title_text)
  table.insert(hl_entries, { #lines, "AgentTabInactive", 0, -1 })

  -- Render each section
  for _, section in ipairs(section_order) do
    local group = keymaps[section]
    if not group or #group == 0 then goto continue end

    local info = section_info[section]
    local secTitle = info.icon .. " " .. info.title

    -- Section header
    table.insert(lines, "")
    table.insert(lines, "  " .. secTitle)
    table.insert(hl_entries, { #lines, "AgentPillActive", 2, 2 + #secTitle })

    -- Separator line under header
    table.insert(lines, "  " .. string.rep("─", #secTitle))
    table.insert(hl_entries, { #lines, "AgentPillInactive", 2, 2 + #secTitle })

    -- Find max key width for alignment in this section
    local max_key_w = 0
    for _, km in ipairs(group) do
      if #km.key > max_key_w then max_key_w = #km.key end
    end

    -- Keymap entries: key left-aligned, desc right-aligned
    for _, km in ipairs(group) do
      local key_padded = km.key .. string.rep(" ", max_key_w - #km.key + 2)
      local entry = "  " .. key_padded .. km.desc
      table.insert(lines, entry)
      -- Highlight the key part
      table.insert(hl_entries, { #lines, "AgentTaskSummaryLabel", 2, 2 + #key_padded })
      -- Highlight the desc part
      table.insert(hl_entries, { #lines, "Comment", 2 + #key_padded, -1 })
    end

    ::continue::
  end

  table.insert(lines, "")

  vim.bo[keymaps_buf].modifiable = true
  vim.api.nvim_buf_set_lines(keymaps_buf, 0, -1, false, lines)
  vim.bo[keymaps_buf].modifiable = false

  -- Apply highlights
  local ns = get_keymaps_ns()
  vim.api.nvim_buf_clear_namespace(keymaps_buf, ns, 0, -1)
  for _, hl in ipairs(hl_entries) do
    local line_idx = hl[1] - 1
    local hl_group = hl[2]
    local col_start = hl[3] or 0
    local col_end = hl[4] or -1
    if col_end == -1 then
      vim.api.nvim_buf_add_highlight(keymaps_buf, ns, hl_group, line_idx, col_start, -1)
    else
      vim.api.nvim_buf_add_highlight(keymaps_buf, ns, hl_group, line_idx, col_start, col_end)
    end
  end
end

-- Auto-refresh keymaps when window focus changes
vim.api.nvim_create_autocmd({ "WinEnter", "FocusGained" }, {
  group = vim.api.nvim_create_augroup("LennAgentKeymaps", { clear = true }),
  callback = function()
    if keymaps_buf and vim.api.nvim_buf_is_valid(keymaps_buf) then
      vim.schedule(render_keymaps_panel)
    end
  end,
})

-- Create the keymaps buffer (lazy, once)
function M.ensure_keymaps_buf()
  if keymaps_buf and vim.api.nvim_buf_is_valid(keymaps_buf) then
    return keymaps_buf
  end

  keymaps_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(keymaps_buf, "Agent Keymaps")
  vim.bo[keymaps_buf].buftype = "nofile"
  vim.bo[keymaps_buf].bufhidden = "hide"
  vim.bo[keymaps_buf].swapfile = false
  vim.bo[keymaps_buf].filetype = "agent-keymaps"

  return keymaps_buf
end

-- Create the skills buffer (lazy, once)
function M.ensure_skills_buf()
  if skills_buf and vim.api.nvim_buf_is_valid(skills_buf) then
    return skills_buf
  end

  skills_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(skills_buf, "Agent Skills")
  vim.bo[skills_buf].buftype = "nofile"
  vim.bo[skills_buf].bufhidden = "hide"
  vim.bo[skills_buf].swapfile = false
  vim.bo[skills_buf].filetype = "agent-skills"

  vim.keymap.set("n", "s", toggle_skill_in_skills_buf, { buffer = skills_buf, desc = "Toggle skill" })
  vim.keymap.set("n", "<CR>", read_skill_doc_from_skills_buf, { buffer = skills_buf, desc = "Read skill doc" })
  vim.keymap.set("n", "m", open_skill_market, { buffer = skills_buf, desc = "Open Skill Market" })
  vim.keymap.set("n", "r", function() M.refresh_skills() end, { buffer = skills_buf, desc = "Refresh skills" })
  vim.keymap.set("n", "q", function() M.toggle_threads_only() end, { buffer = skills_buf, desc = "Close panels" })

  return skills_buf
end

local function set_project_expanded(expanded)
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local project_cwd = project_row_map[row]
  if not project_cwd or expanded_projects[project_cwd] == expanded then return end

  expanded_projects[project_cwd] = expanded
  render_threads(threads_data)
  local last_line = math.max(1, vim.api.nvim_buf_line_count(threads_buf))
  vim.api.nvim_win_set_cursor(0, { math.min(row, last_line), 0 })
end

function M.refresh_threads()
  collect_threads(function(threads)
    threads_data = threads
    render_threads(threads)
  end)
  if active_threads_tab == "tasks" then refresh_tasks(task_project_cwd) end
  render_skills()
end

-- Debounced background refresh of the thread list (used by autocmds).
local schedule_threads_refresh
do
local threads_refresh_timer = nil
schedule_threads_refresh = function(delay)
  if not threads_buf or not vim.api.nvim_buf_is_valid(threads_buf) then return end
  if active_threads_tab ~= "threads" then return end
  if threads_refresh_timer then threads_refresh_timer:stop() end
  threads_refresh_timer = vim.defer_fn(function()
    threads_refresh_timer = nil
    if vim.fn.bufwinid(threads_buf) == -1 then return end
    collect_threads(function(threads)
      threads_data = threads
      -- Keep the cursor on the same line after re-rendering
      local win = vim.fn.bufwinid(threads_buf)
      local cursor = win ~= -1 and vim.api.nvim_win_get_cursor(win) or nil
      render_threads(threads)
      if cursor and vim.api.nvim_win_is_valid(win) then
        local last = vim.api.nvim_buf_line_count(threads_buf)
        pcall(vim.api.nvim_win_set_cursor, win, { math.min(cursor[1], last), cursor[2] })
      end
    end)
  end, delay or 300)
end

-- Agents write their sessions to disk while running / on exit, so refresh
-- when a terminal closes, when nvim regains focus, or when entering the panel.
vim.api.nvim_create_autocmd({ "TermClose", "FocusGained" }, {
  group = vim.api.nvim_create_augroup("LennAgentThreadsRefresh", { clear = true }),
  callback = function() schedule_threads_refresh(800) end,
})

local function open_project_dir(dir)
  if vim.fn.isdirectory(dir) ~= 1 then return end
  if dir ~= vim.fn.getcwd() then vim.cmd("cd " .. vim.fn.fnameescape(dir)) end
  if pcall(require, "neo-tree") then
    pcall(vim.api.nvim_command, "Neotree " .. vim.fn.fnameescape(dir))
  end
end

local function register_project(dir)
  dir = saved_projects.add(dir)
  if not dir then return end
  expanded_projects[dir] = true
  open_project_dir(dir)
  render_threads(threads_data)
  for row, cwd in pairs(project_row_map) do
    if cwd == dir then
      local win = vim.fn.bufwinid(threads_buf)
      if win ~= -1 then pcall(vim.api.nvim_win_set_cursor, win, { row, 0 }) end
      break
    end
  end
  vim.notify("Project added: " .. dir, vim.log.levels.INFO)
end

-- Add an existing folder as a project, or create a new one (optionally git init).
function M.add_project()
  local choices = { "Open existing folder", "Create new project folder" }
  vim.ui.select(choices, { prompt = "Add project" }, function(choice)
    if not choice then return end
    if choice == choices[1] then
      vim.ui.input({ prompt = "Folder: ", default = vim.fn.getcwd() .. "/", completion = "dir" }, function(input)
        if not input or vim.trim(input) == "" then return end
        local dir = vim.fn.fnamemodify(vim.fn.expand(vim.trim(input)), ":p"):gsub("/+$", "")
        if vim.fn.isdirectory(dir) ~= 1 then
          vim.notify("Not a directory: " .. dir, vim.log.levels.ERROR)
          return
        end
        register_project(dir)
      end)
      return
    end
    local default_parent = vim.fn.isdirectory(vim.fn.expand("~/Projects")) == 1 and "~/Projects/" or "~/"
    vim.ui.input({ prompt = "New project path: ", default = default_parent, completion = "dir" }, function(input)
      if not input or vim.trim(input) == "" then return end
      local dir = vim.fn.fnamemodify(vim.fn.expand(vim.trim(input)), ":p"):gsub("/+$", "")
      if vim.fn.isdirectory(dir) == 1 then
        vim.notify("Folder already exists, adding it: " .. dir, vim.log.levels.WARN)
        register_project(dir)
        return
      end
      if vim.fn.mkdir(dir, "p") ~= 1 then
        vim.notify("Could not create " .. dir, vim.log.levels.ERROR)
        return
      end
      vim.ui.select({ "Yes", "No" }, { prompt = "Initialize git repository?" }, function(git)
        if git == "Yes" and vim.fn.executable("git") == 1 then
          vim.fn.system({ "git", "-C", dir, "init", "-q" })
        end
        register_project(dir)
      end)
    end)
  end)
end

-- Remove a manually added project (its threads stay listed if it has any).
function M.remove_project()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local dir = project_row_map[row]
  if not dir then return end
  if saved_projects.remove(dir) then
    render_threads(threads_data)
    vim.notify("Project removed from list: " .. dir, vim.log.levels.INFO)
  else
    vim.notify("Only manually added projects can be removed", vim.log.levels.WARN)
  end
end
end -- do (project actions)

-- Skip empty lines when navigating with j/k or arrow keys
local function find_nearest_content_line()
  -- Find the last line with content in the buffer
  local max_line = vim.api.nvim_buf_line_count(0)
  for l = max_line, 1, -1 do
    local text = vim.api.nvim_buf_get_lines(0, l - 1, l, false)[1]
    if text and text:match("%S") then
      return l
    end
  end
  return 1
end

local function skip_empty_down()
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local max_line = vim.api.nvim_buf_line_count(0)
  for l = line + 1, max_line do
    local text = vim.api.nvim_buf_get_lines(0, l - 1, l, false)[1]
    if text and text:match("%S") then
      vim.api.nvim_win_set_cursor(0, { l, 0 })
      return
    end
  end
  -- No more content below; stay on current line (don't move to empty)
end

local function skip_empty_up()
  local line = vim.api.nvim_win_get_cursor(0)[1]
  for l = line - 1, 1, -1 do
    local text = vim.api.nvim_buf_get_lines(0, l - 1, l, false)[1]
    if text and text:match("%S") then
      vim.api.nvim_win_set_cursor(0, { l, 0 })
      return
    end
  end
  -- No more content above; stay on current line (don't move to empty)
end

-- After rendering, ensure cursor is on a line with content
ensure_cursor_on_content = function()
  local win = threads_win
  if not win or not vim.api.nvim_win_is_valid(win) then return end
  local buf = threads_buf
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  local max_line = vim.api.nvim_buf_line_count(buf)
  if max_line == 0 then return end
  local line = vim.api.nvim_win_get_cursor(win)[1]
  -- Clamp line to valid range first
  if line < 1 then line = 1 end
  if line > max_line then line = max_line end
  local text = vim.api.nvim_buf_get_lines(buf, line - 1, line, false)[1]
  if not text or not text:match("%S") then
    -- Current line is empty; move to nearest content line
    local nearest = find_nearest_content_line()
    -- Clamp again to be safe
    nearest = math.max(1, math.min(nearest, max_line))
    vim.api.nvim_win_set_cursor(win, { nearest, 0 })
  end
end

-- Create the threads buffer (lazy, once). Edgy will display it in its left edge.
function M.ensure_threads_buf()
  if threads_buf and vim.api.nvim_buf_is_valid(threads_buf) then
    return threads_buf
  end

  threads_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(threads_buf, "Agent Threads")
  vim.bo[threads_buf].buftype = "nofile"
  vim.bo[threads_buf].bufhidden = "hide"
  vim.bo[threads_buf].swapfile = false
  vim.bo[threads_buf].filetype = "agent-threads"

  -- Navigation with empty line skipping
  vim.keymap.set("n", "j", skip_empty_down, { buffer = threads_buf, desc = "Down (skip empty)" })
  vim.keymap.set("n", "k", skip_empty_up, { buffer = threads_buf, desc = "Up (skip empty)" })
  vim.keymap.set("n", "<Down>", skip_empty_down, { buffer = threads_buf, desc = "Down (skip empty)" })
  vim.keymap.set("n", "<Up>", skip_empty_up, { buffer = threads_buf, desc = "Up (skip empty)" })

  vim.keymap.set("n", "<Tab>", switch_threads_tab, {
    buffer = threads_buf, desc = "Switch Threads/Tasks tab", nowait = true,
  })
  vim.keymap.set("n", "<S-Tab>", switch_threads_tab, {
    buffer = threads_buf, desc = "Switch Threads/Tasks tab", nowait = true,
  })
  vim.keymap.set("n", "<CR>", function()
    if active_threads_tab == "tasks" then
      local entry = task_row_map[vim.api.nvim_win_get_cursor(0)[1]]
      if entry and entry.kind == "issue" then
        -- Open GitHub issue in browser
        local url = entry.task.html_url or entry.task.url
        if url then
          vim.fn.execute("silent! browse " .. url)
          vim.notify("Opening: " .. url, vim.log.levels.INFO)
        end
      elseif entry and entry.kind == "local" and entry.task.thread then
        open_task_thread()
      else
        dispatch_task()
      end
    else
      M.open_thread()
    end
  end, { buffer = threads_buf, desc = "Open thread / task / issue" })
  vim.keymap.set("n", "h", function() set_project_expanded(false) end, { buffer = threads_buf, desc = "Collapse project" })
  vim.keymap.set("n", "l", function()
    if active_threads_tab == "tasks" then
      if active_task_pill == "github" then
        -- Open GitHub issue in browser
        local entry = task_row_map[vim.api.nvim_win_get_cursor(0)[1]]
        if entry and entry.kind == "issue" then
          local url = entry.task.html_url or entry.task.url
          if url then vim.fn.execute("silent! browse " .. url) end
        end
      else
        dispatch_task()
      end
      return
    end
    local row = vim.api.nvim_win_get_cursor(0)[1]
    if thread_row_map[row] then
      M.open_thread()
    else
      set_project_expanded(true)
    end
  end, { buffer = threads_buf, desc = "Open thread / task / issue" })
  vim.keymap.set("n", "+", function()
    if active_threads_tab == "tasks" then
      if active_task_pill == "github" then
        -- Track the GitHub issue under cursor as a local task
        local entry = task_row_map[vim.api.nvim_win_get_cursor(0)[1]]
        if entry and entry.kind == "issue" then
          local task = require("lenn.agent-tasks").track_issue(entry.cwd, entry.task)
          if task then
            vim.notify("Issue tracked as local task: " .. task.title, vim.log.levels.INFO)
            refresh_tasks(entry.cwd)
          end
        end
      else
        add_local_task()
      end
      return
    end
    local row = vim.api.nvim_win_get_cursor(0)[1]
    local project_cwd = project_row_map[row]
      or (thread_row_map[row] and thread_row_map[row].cwd)
      or vim.fn.getcwd()
    M.new_session(project_cwd)
  end, { buffer = threads_buf, desc = "Add task / Track issue" })
  vim.keymap.set("n", "r", function()
    if active_threads_tab == "tasks" then refresh_tasks(task_project_cwd) else M.refresh_threads() end
  end, { buffer = threads_buf, desc = "Refresh current tab" })
  vim.keymap.set("n", "]", function() if active_threads_tab == "tasks" then cycle_task_project(1) end end,
    { buffer = threads_buf, desc = "Next task project" })
  vim.keymap.set("n", "[", function() if active_threads_tab == "tasks" then cycle_task_project(-1) end end,
    { buffer = threads_buf, desc = "Previous task project" })
  vim.keymap.set("n", "x", function() if active_threads_tab == "tasks" then set_task_status("completed") end end,
    { buffer = threads_buf, desc = "Mark task complete" })
  vim.keymap.set("n", "f", function() if active_threads_tab == "tasks" then set_task_status("failed") end end,
    { buffer = threads_buf, desc = "Mark task failed" })
  vim.keymap.set("n", "a", function() if active_threads_tab == "tasks" then set_task_status("archived") end end,
    { buffer = threads_buf, desc = "Archive task" })
  vim.keymap.set("n", "u", function() if active_threads_tab == "tasks" then set_task_status("pending") end end,
    { buffer = threads_buf, desc = "Restore task to pending" })
  vim.keymap.set("n", "o", function() if active_threads_tab == "tasks" then open_task_thread() end end,
    { buffer = threads_buf, desc = "Open linked task thread" })
  vim.keymap.set("n", "v", function() if active_threads_tab == "tasks" then verify_task() end end,
    { buffer = threads_buf, desc = "Verify task criteria" })
  vim.keymap.set("n", "p", switch_task_pill, { buffer = threads_buf, desc = "Switch Local/GitHub pill" })
  -- Not <Space>: a buffer-local <Space> (esp. with nowait) swallows <leader>,
  -- which broke the workspace keys (<leader>w1..w4) inside this panel.
  vim.keymap.set("n", "za", function()
    if active_threads_tab == "tasks" and active_task_pill == "local" then
      toggle_task_fold()
    end
  end, { buffer = threads_buf, desc = "Fold/Unfold task category" })
  vim.keymap.set("n", ">", function()
    if active_threads_tab == "tasks" then
      if active_task_pill == "github" then
        -- Create a local task from the GitHub issue under cursor
        local entry = task_row_map[vim.api.nvim_win_get_cursor(0)[1]]
        if entry and entry.kind == "issue" then
          local task = require("lenn.agent-tasks").track_issue(entry.cwd, entry.task)
          if task then
            vim.notify("Issue tracked as local task: " .. task.title, vim.log.levels.INFO)
            refresh_tasks(entry.cwd)
          end
        end
      else
        dispatch_task()
      end
    end
  end, { buffer = threads_buf, desc = "Send task / Track issue" })
  vim.keymap.set("n", "<C-n>", M.new_session, { buffer = threads_buf, desc = "New agent session" })
  vim.keymap.set("n", "q", function() M.toggle_threads_only() end, { buffer = threads_buf, desc = "Close Threads panel" })
  vim.keymap.set("n", "A", function()
    if active_threads_tab == "threads" then M.add_project() end
  end, { buffer = threads_buf, desc = "Add / create project" })
  vim.keymap.set("n", "D", function()
    if active_threads_tab == "threads" then M.remove_project() end
  end, { buffer = threads_buf, desc = "Remove saved project" })
  vim.api.nvim_create_autocmd("BufEnter", {
    buffer = threads_buf,
    callback = function() schedule_threads_refresh(200) end,
  })
  vim.keymap.set("n", "K", show_task_details_float, { buffer = threads_buf, desc = "Show task details" })

  -- Keep window height fixed to prevent resizing
  vim.api.nvim_create_autocmd("BufWinEnter", {
    buffer = threads_buf,
    callback = function()
      local win = vim.api.nvim_get_current_win()
      if win ~= threads_win then return end
      vim.wo[win].winfixheight = true
    end,
  })

  return threads_buf
end

function M.open_thread()
  local row = vim.api.nvim_win_get_cursor(0)[1]

  if action_row_map[row] == "add_project" then
    M.add_project()
    return
  end

  local project_cwd = project_row_map[row]
  if project_cwd then
    expanded_projects[project_cwd] = true
    local threads_window = vim.api.nvim_get_current_win()
    if vim.fn.isdirectory(project_cwd) == 1 then
      if project_cwd ~= vim.fn.getcwd() then
        vim.cmd("cd " .. vim.fn.fnameescape(project_cwd))
      end
      if pcall(require, "neo-tree") then
        vim.api.nvim_command("Neotree " .. vim.fn.fnameescape(project_cwd))
      end
    end
    render_threads(threads_data)
    local selected_row = row
    for candidate_row, candidate_cwd in pairs(project_row_map) do
      if candidate_cwd == project_cwd then selected_row = candidate_row; break end
    end
    local last_line = math.max(1, vim.api.nvim_buf_line_count(threads_buf))
    if vim.api.nvim_win_is_valid(threads_window) then
      vim.api.nvim_win_set_cursor(threads_window, { math.min(selected_row, last_line), 0 })
      vim.schedule(function()
        vim.schedule(function()
          if vim.api.nvim_win_is_valid(threads_window) then
            vim.api.nvim_set_current_win(threads_window)
            vim.api.nvim_win_set_cursor(threads_window, { math.min(selected_row, last_line), 0 })
          end
        end)
      end)
    end
    return
  end

  local thread = thread_row_map[row]
  if not thread then return end
  current_thread_id = thread.id

  -- Change directory to the thread's project if different
  local changed_dir = false
  if thread.cwd and thread.cwd ~= vim.fn.getcwd() then
    vim.cmd("cd " .. vim.fn.fnameescape(thread.cwd))
    changed_dir = true
    -- Update NeoTree to the new directory
    local neo_tree_avail = pcall(require, "neo-tree")
    if neo_tree_avail then
      vim.api.nvim_command("Neotree " .. vim.fn.fnameescape(thread.cwd))
    end
  end

  -- Refresh threads display to update the current project marker
  render_threads(threads_data)

  -- Defer launching the provider so NeoTree and directory change complete first.
  -- NeoTree is async and can take a few ms to refresh; without this delay,
  -- launch_provider grabs focus before NeoTree finishes, making the explorer
  -- appear stale most of the time.
  vim.schedule(function()
    if changed_dir then
      -- Give NeoTree one more cycle to finish its own scheduled updates
      vim.schedule(function()
        M.launch_provider(thread.provider, thread.id, thread.cwd)
      end)
    else
      M.launch_provider(thread.provider, thread.id, thread.cwd)
    end
  end)
end

-- ─── Agent Panel ────────────────────────────────────────────────────────────

local function git_nul_paths(args, cwd)
  if vim.fn.executable("git") ~= 1 then return {} end
  local ok, process = pcall(vim.system, args, { cwd = cwd, text = true })
  if not ok then return {} end
  local result = process:wait()
  if result.code ~= 0 then return {} end
  local paths = {}
  for path in (result.stdout or ""):gmatch("([^%z]+)") do paths[path] = true end
  return paths
end

project_file_stats = function(cwd)
  local paths = git_nul_paths({ "git", "diff", "--name-only", "-z" }, cwd)
  for path in pairs(git_nul_paths({ "git", "diff", "--cached", "--name-only", "-z" }, cwd)) do
    paths[path] = true
  end
  for path in pairs(git_nul_paths({ "git", "ls-files", "--others", "--exclude-standard", "-z" }, cwd)) do
    paths[path] = true
  end
  local snapshot = {}
  local uv = vim.uv or vim.loop
  for path in pairs(paths) do
    local stat = uv.fs_stat(vim.fn.fnamemodify(cwd .. "/" .. path, ":p"))
    if stat and stat.type == "file" then
      snapshot[path] = {
        size = stat.size,
        mtime_sec = stat.mtime.sec,
        mtime_nsec = stat.mtime.nsec,
      }
    end
  end
  return snapshot
end

open_task_changes = function(session)
  if not session.change_snapshot then return end
  local now = project_file_stats(session.cwd)
  local changed = {}
  local uv = vim.uv or vim.loop
  for path, stat in pairs(now) do
    local before = session.change_snapshot[path]
    if not before or before.size ~= stat.size
      or before.mtime_sec ~= stat.mtime_sec or before.mtime_nsec ~= stat.mtime_nsec then
      local full_path = vim.fn.fnamemodify(session.cwd .. "/" .. path, ":p")
      local current_stat = uv.fs_stat(full_path)
      if current_stat and current_stat.type == "file" then
        table.insert(changed, { path = full_path, mtime = current_stat.mtime.sec,
          mtime_nsec = current_stat.mtime.nsec })
      end
    end
  end
  if #changed == 0 then return end
  table.sort(changed, function(a, b)
    if a.mtime == b.mtime then return a.mtime_nsec > b.mtime_nsec end
    return a.mtime > b.mtime
  end)

  local editor_win = find_editor_window(agent_win)
  if not editor_win then
    vim.notify("Task changed files, but no editor window is available for review", vim.log.levels.WARN)
    return
  end
  local latest_buf
  for _, file in ipairs(changed) do
    local buf = vim.fn.bufadd(file.path)
    if buf > 0 then
      pcall(vim.fn.bufload, buf)
      vim.bo[buf].buflisted = true
      latest_buf = latest_buf or buf
    end
  end
  if latest_buf then
    vim.api.nvim_win_set_buf(editor_win, latest_buf)
    vim.wo[editor_win].number = true
    vim.wo[editor_win].relativenumber = true
    last_editor_win = editor_win
    vim.api.nvim_set_current_win(editor_win)
    vim.notify(string.format("Opened %d modified file%s for review", #changed, #changed == 1 and "" or "s"))
  end
end

-- Collect active toggleterm sessions for display
local function get_active_sessions()
  local sessions = {}
  local Terminal = require("toggleterm.terminal")
  for _, t in ipairs(Terminal.get_all(true)) do
    local name = t.display_name or "Agent"
    local provider = vim.b[t.bufnr] and vim.b[t.bufnr].agent_provider or "Unknown"
    local is_open = t:is_open()
    local job_status
    if type(t.job_id) == "number" then
      local wait_ok, result = pcall(vim.fn.jobwait, { t.job_id }, 0)
      if wait_ok and result then job_status = result[1] end
    end
    table.insert(sessions, {
      name = name,
      provider = provider,
      open = is_open,
      running = job_status == nil and is_open or job_status == -1,
      cwd = (vim.b[t.bufnr] and vim.b[t.bufnr].agent_project_cwd) or t.dir,
      started_at = t.start_time or 0,
      task_id = vim.b[t.bufnr] and vim.b[t.bufnr].agent_task_id,
      task_title = vim.b[t.bufnr] and vim.b[t.bufnr].agent_task_title,
      thread_id = vim.b[t.bufnr] and vim.b[t.bufnr].agent_thread_id,
      terminal = t,
      kind = "toggleterm",
    })
  end
  return sessions
end

local function normalized_project(path)
  return path and vim.fn.fnamemodify(path, ":p") or ""
end

get_running_project_sessions = function()
  local cwd = normalized_project(vim.fn.getcwd())
  local sessions = {}
  local in_progress_tasks = {}
  for _, task in ipairs(require("lenn.agent-tasks").local_tasks(vim.fn.getcwd())) do
    if task.status == "in_progress" then in_progress_tasks[task.id] = true end
  end
  for _, session in ipairs(direct_agent_sessions) do
    local task_is_active = session.task_id and in_progress_tasks[session.task_id]
    if (session.running or task_is_active) and normalized_project(session.cwd) == cwd then
      table.insert(sessions, session)
    end
  end
  for _, session in ipairs(get_active_sessions()) do
    local task_is_active = session.task_id and in_progress_tasks[session.task_id]
    if (session.running or task_is_active) and normalized_project(session.cwd) == cwd then
      table.insert(sessions, session)
    end
  end
  table.sort(sessions, function(a, b)
    return (a.started_at or 0) > (b.started_at or 0)
  end)
  return sessions
end

local function get_agent_tabs()
  local cwd = vim.fn.getcwd()
  local tabs = { { id = "providers", label = "Providers", kind = "providers" } }
  local task_ids = {}
  for _, session in ipairs(get_running_project_sessions()) do
    local id
    if session.task_id then
      id = "task:" .. session.task_id
      task_ids[session.task_id] = true
    else
      id = session.tab_id or ("session:" .. tostring(session.bufnr or session.job_id or session.job or session.name))
      session.tab_id = id
    end
    session.tab_id = id
    tabs[#tabs + 1] = {
      id = id,
      label = session.task_title
        or (session.thread_id and ((session.provider or "Agent") .. " " .. tostring(session.thread_id):sub(-8)))
        or session.name or session.provider or "Agent",
      kind = "session",
      session = session,
      provider = session.provider,
    }
  end

  for _, task in ipairs(require("lenn.agent-tasks").local_tasks(cwd)) do
    if task.status == "in_progress" and task.thread and not task_ids[task.id] then
      tabs[#tabs + 1] = {
        id = "task:" .. task.id,
        label = task.title or "Task",
        kind = "task",
        task = task,
        cwd = cwd,
        provider = task.thread.provider,
        thread_id = task.thread.id,
      }
    end
  end
  return tabs
end

render_agent_tabs = function()
  if not agent_win or not vim.api.nvim_win_is_valid(agent_win) then return end
  agent_tabs_cache = get_agent_tabs()
  local present = false
  for _, tab in ipairs(agent_tabs_cache) do
    if tab.id == selected_agent_tab then present = true end
  end
  if not present then selected_agent_tab = "providers" end
  local items = {}
  for index, tab in ipairs(agent_tabs_cache) do
    local label = tab.label:gsub("%%", "%%%%")
    if #label > 18 then label = label:sub(1, 15) .. "..." end
    if agent_tab_numbers_visible then label = tostring(index) .. " " .. label end
    local group = tab.id == selected_agent_tab and "AgentTabActive" or "AgentTabInactive"
    table.insert(items, "%#" .. group .. "# " .. label .. " %#Normal# ")
  end
  vim.wo[agent_win].winbar = table.concat(items, "  ") .. "%="
end

-- Row -> provider name for the Providers cover (used by <CR> in agent_buf).
M._provider_rows = {}

-- Providers tab: a centered "cover" listing every provider with its status
-- (installed / running / thread count for this project). <CR> on a row starts it.
M._render_providers_cover = function()
  local cwd = vim.fn.getcwd()
  local win = vim.fn.bufwinid(agent_buf)
  local width = win ~= -1 and vim.api.nvim_win_get_width(win) or agent_width
  local height = win ~= -1 and vim.api.nvim_win_get_height(win) or 30
  if win ~= -1 then
    -- The panel split inherits code-window options; the cover needs none of them
    local wo = vim.wo[win][0]
    wo.number = false
    wo.relativenumber = false
    wo.signcolumn = "no"
    wo.cursorline = false
  end

  -- Per-provider stats for the current project
  local thread_counts, running = {}, {}
  local norm_cwd = vim.fn.fnamemodify(cwd, ":p"):gsub("/+$", "")
  for _, t in ipairs(threads_data or {}) do
    if t.cwd == norm_cwd then thread_counts[t.provider] = (thread_counts[t.provider] or 0) + 1 end
  end
  local any_running = false
  for _, sess in ipairs(get_running_project_sessions()) do
    if sess.provider then running[sess.provider] = true; any_running = true end
  end

  local name_w = 0
  for _, provider in ipairs(providers) do name_w = math.max(name_w, vim.fn.strdisplaywidth(provider.name)) end

  local rows = {} -- { text = , hls = { {group, col_start, col_end} }, provider = }
  local function add(text, hls, provider) table.insert(rows, { text = text, hls = hls or {}, provider = provider }) end

  local title = any_running and "Agents" or "No agent running"
  local title_icon = nf.agent or nf.generic
  add(title_icon .. "  " .. title, { { "AgentCoverTitle", 0, -1 } })
  add("Pick a provider to start in " .. nf.project .. " " .. project_name(cwd), { { "Comment", 0, -1 } })
  add("")
  add("PROVIDERS", { { "AgentCoverSection", 0, -1 } })
  for _, provider in ipairs(providers) do
    local exe = vim.split(provider.cmd or "", " ", { trimempty = true })[1]
    local installed = exe and vim.fn.executable(exe) == 1
    local icon = nf.normalize(provider.icon)
    local marker = provider.name == current_provider and nf.active or " "
    local status, status_hl
    if not installed then
      status, status_hl = "not installed", "AgentCoverMissing"
    elseif running[provider.name] then
      status, status_hl = nf.dot .. " running", "AgentThreadRunning"
    elseif (thread_counts[provider.name] or 0) > 0 then
      local n = thread_counts[provider.name]
      status, status_hl = string.format("%d thread%s", n, n == 1 and "" or "s"), "Comment"
    else
      status, status_hl = "ready", "Comment"
    end
    local head = string.format("%s %s  ", marker, icon)
    local name = provider.name .. string.rep(" ", name_w - vim.fn.strdisplaywidth(provider.name))
    local text = head .. name .. "   " .. status
    local icon_start = #marker + 1
    local name_start = #head
    add(text, {
      { "AgentActiveThread", 0, #marker },
      { installed and ("AgentProvider" .. provider.name:gsub("%W", "")) or "AgentCoverMissing", icon_start, icon_start + #icon },
      { installed and "Normal" or "AgentCoverMissing", name_start, name_start + #name },
      { status_hl, name_start + #name + 3, -1 },
    }, provider.name)
  end
  add("")
  local hints = {
    { "<CR>", "start" }, { "C-n", "new session" }, { "S-p", "pick" },
    { "S-m", "market" }, { "Tab", "next tab" }, { "q", "close" },
  }
  local hint_line, hint_hls = "", {}
  for i, h in ipairs(hints) do
    if i > 1 then hint_line = hint_line .. "  " end
    table.insert(hint_hls, { "AgentCoverKey", #hint_line, #hint_line + #h[1] })
    hint_line = hint_line .. h[1] .. " "
    table.insert(hint_hls, { "Comment", #hint_line, #hint_line + #h[2] })
    hint_line = hint_line .. h[2]
  end
  -- Wrap hints into two lines when the panel is narrow
  if vim.fn.strdisplaywidth(hint_line) > width - 4 then
    local first, second = {}, {}
    for i, h in ipairs(hints) do table.insert(i <= 3 and first or second, h) end
    for _, group in ipairs({ first, second }) do
      local line, hls = "", {}
      for i, h in ipairs(group) do
        if i > 1 then line = line .. "  " end
        table.insert(hls, { "AgentCoverKey", #line, #line + #h[1] })
        line = line .. h[1] .. " "
        table.insert(hls, { "Comment", #line, #line + #h[2] })
        line = line .. h[2]
      end
      add(line, hls)
    end
  else
    add(hint_line, hint_hls)
  end

  -- Center the block (top-biased vertically)
  local block_w = 0
  for _, r in ipairs(rows) do block_w = math.max(block_w, vim.fn.strdisplaywidth(r.text)) end
  local left = math.max(2, math.floor((width - block_w) / 2))
  local top = math.max(1, math.floor((height - #rows) / 3))
  local pad = string.rep(" ", left)

  local lines = {}
  for _ = 1, top do table.insert(lines, "") end
  M._provider_rows = {}
  local first_provider_row
  for _, r in ipairs(rows) do
    table.insert(lines, r.text == "" and "" or (pad .. r.text))
    if r.provider then
      M._provider_rows[#lines] = r.provider
      first_provider_row = first_provider_row or #lines
    end
  end

  vim.bo[agent_buf].modifiable = true
  vim.api.nvim_buf_set_lines(agent_buf, 0, -1, false, lines)
  vim.bo[agent_buf].modifiable = false
  local ns = get_threads_ns()
  vim.api.nvim_buf_clear_namespace(agent_buf, ns, 0, -1)
  for i, r in ipairs(rows) do
    local row = top + i - 1
    for _, hl in ipairs(r.hls) do
      local col_end = hl[3] == -1 and -1 or (left + hl[3])
      pcall(vim.api.nvim_buf_add_highlight, agent_buf, ns, hl[1], row, left + hl[2], col_end)
    end
  end

  -- Keep the cursor on a provider row
  if win ~= -1 and first_provider_row then
    local cur = vim.api.nvim_win_get_cursor(win)[1]
    if not M._provider_rows[cur] then
      local target = first_provider_row
      for row, name in pairs(M._provider_rows) do
        if name == current_provider then target = row end
      end
      pcall(vim.api.nvim_win_set_cursor, win, { target, left })
    end
  end
end

render_agent_panel = function()
  if not agent_buf or not vim.api.nvim_buf_is_valid(agent_buf) then return end
  render_agent_tabs()
  local lines
  if selected_agent_tab == "providers" then
    M._render_providers_cover()
    return
  else
    local selected
    for _, tab in ipairs(agent_tabs_cache) do
      if tab.id == selected_agent_tab then selected = tab; break end
    end
    lines = {
      "",
      "Task: " .. ((selected and selected.label) or "Active agent"),
      "Agent: " .. ((selected and selected.provider) or current_provider or "Unknown"),
      "Project: " .. project_name((selected and selected.cwd)
        or (selected and selected.session and selected.session.cwd) or vim.fn.getcwd()),
      "",
    }
    local thread_id = selected and (selected.thread_id
      or (selected.session and selected.session.thread_id)
      or (selected.task and selected.task.thread and selected.task.thread.id))
    if thread_id then
      table.insert(lines, "Thread: " .. tostring(thread_id))
      table.insert(lines, "")
    end
    table.insert(lines, "This task tab stays available while its task is In progress.")
  end
  vim.bo[agent_buf].modifiable = true
  vim.api.nvim_buf_set_lines(agent_buf, 0, -1, false, lines)
  vim.bo[agent_buf].modifiable = false
  local ns = get_threads_ns()
  vim.api.nvim_buf_clear_namespace(agent_buf, ns, 0, -1)
  vim.api.nvim_buf_add_highlight(agent_buf, ns, "Comment", 0, 0, -1)
end

local select_agent_tab
select_agent_tab = function(id)
  if id == "providers" then
    selected_agent_tab = id
    local buf = M.ensure_agent_buf()
    if agent_win and vim.api.nvim_win_is_valid(agent_win) then
      vim.api.nvim_win_set_buf(agent_win, buf)
      vim.api.nvim_set_current_win(agent_win)
    end
    render_agent_panel()
    return
  end

  local tab
  for _, candidate in ipairs(get_agent_tabs()) do
    if candidate.id == id then tab = candidate; break end
  end
  if not tab then
    selected_agent_tab = "providers"
    render_agent_panel()
    return
  end
  selected_agent_tab = id
  if tab.kind == "task" then
    if not tab.thread_id then
      if tab.provider == "Claude Code" then
        M.launch_provider(tab.provider, "resume-picker", tab.cwd, false, nil, {
          task_id = tab.task.id, task_title = tab.label, tab_id = id,
        })
        return
      end
      vim.notify("The task thread is still starting or has no resumable session ID", vim.log.levels.INFO)
      render_agent_tabs()
      return
    end
    M.launch_provider(tab.provider, tab.thread_id, tab.cwd, false, nil, {
      task_id = tab.task.id, task_title = tab.label, tab_id = id,
    })
    if current_term then
      current_term.task_id = tab.task.id
      current_term.task_title = tab.label
      current_term.tab_id = id
      if current_term.bufnr then
        pcall(function()
          vim.b[current_term.bufnr].agent_task_id = tab.task.id
          vim.b[current_term.bufnr].agent_task_title = tab.label
        end)
      end
      render_agent_tabs()
    end
    return
  end

  local session = tab.session
  current_provider = session.provider
  current_thread_id = session.thread_id
  current_term = session.kind == "toggleterm" and session.terminal or session
  if session.kind == "toggleterm" then
    if not session.terminal:is_open() then session.terminal:open() end
    if session.terminal.window then vim.api.nvim_set_current_win(session.terminal.window) end
  elseif agent_win and vim.api.nvim_win_is_valid(agent_win) and vim.api.nvim_buf_is_valid(session.bufnr) then
    vim.api.nvim_win_set_buf(agent_win, session.bufnr)
    vim.api.nvim_set_current_win(agent_win)
    if session.running then vim.cmd.startinsert() end
  end
  render_agent_tabs()
end

local function reveal_agent_tab_numbers()
  local was_visible = agent_tab_numbers_visible
  agent_tab_numbers_visible = true
  agent_tab_number_generation = agent_tab_number_generation + 1
  local generation = agent_tab_number_generation
  vim.defer_fn(function()
    if generation ~= agent_tab_number_generation then return end
    agent_tab_numbers_visible = false
    render_agent_tabs()
  end, 2500)
  if not was_visible then render_agent_tabs() end
end

local function cycle_agent_tab(direction)
  local uv = vim.uv or vim.loop
  local now = uv.now()
  if now - last_agent_tab_key_ms < 650 then
    -- Terminal key repeat has no release event; keep the number strip visible
    -- while suppressing repeats so a held Tab advances only once.
    last_agent_tab_key_ms = now
    reveal_agent_tab_numbers()
    return
  end
  last_agent_tab_key_ms = now
  reveal_agent_tab_numbers()
  local tabs = get_agent_tabs()
  local index = 1
  for i, tab in ipairs(tabs) do
    if tab.id == selected_agent_tab then index = i; break end
  end
  index = ((index - 1 + direction) % #tabs) + 1
  select_agent_tab(tabs[index].id)
end

local function select_agent_tab_number(number)
  local index = number == 0 and 10 or number
  local tabs = get_agent_tabs()
  if agent_tab_numbers_visible and tabs[index] then
    agent_tab_number_generation = agent_tab_number_generation + 1
    local generation = agent_tab_number_generation
    agent_tab_numbers_visible = true
    select_agent_tab(tabs[index].id)
    vim.defer_fn(function()
      if generation ~= agent_tab_number_generation then return end
      agent_tab_numbers_visible = false
      render_agent_tabs()
    end, 2500)
    return true
  end
  return false
end

local function handle_agent_tab_number(number)
  if select_agent_tab_number(number) then return end
  vim.api.nvim_feedkeys(tostring(number), "n", false)
end

local function handle_terminal_tab_number(number, bufnr)
  if select_agent_tab_number(number) then return end
  local job = vim.b[bufnr].terminal_job_id
  if not job and current_term then job = current_term.job_id or current_term.job end
  if job then
    pcall(vim.api.nvim_chan_send, job, tostring(number))
  else
    vim.api.nvim_feedkeys(tostring(number), "n", false)
  end
end

local function install_agent_tab_number_maps(bufnr, mode)
  for _, digit in ipairs({ "1", "2", "3", "4", "5", "6", "7", "8", "9", "0" }) do
    local number = tonumber(digit)
    local handler = mode == "t"
      and function() handle_terminal_tab_number(number, bufnr) end
      or function() handle_agent_tab_number(number) end
    vim.keymap.set(mode, digit, handler, {
      buffer = bufnr,
      desc = "Select numbered agent tab",
      nowait = true,
    })
  end
end

local function show_agent_panel()
  select_agent_tab("providers")
end

-- Create the agent panel buffer (lazy, once). Edgy will display it in its left edge.
function M.ensure_agent_buf()
  if agent_buf and vim.api.nvim_buf_is_valid(agent_buf) then
    return agent_buf
  end

  agent_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(agent_buf, "Agent Panel")
  vim.bo[agent_buf].buftype = "nofile"
  vim.bo[agent_buf].bufhidden = "hide"
  vim.bo[agent_buf].swapfile = false
  vim.bo[agent_buf].filetype = "agent-panel"

  vim.keymap.set("n", "<Tab>", function() cycle_agent_tab(1) end, { buffer = agent_buf, desc = "Next agent tab", nowait = true })
  vim.keymap.set("n", "<S-Tab>", function() cycle_agent_tab(-1) end, { buffer = agent_buf, desc = "Previous agent tab", nowait = true })
  vim.keymap.set("n", "<CR>", function()
    if selected_agent_tab ~= "providers" then
      select_agent_tab(selected_agent_tab)
      return
    end
    local provider_name = M._provider_rows[vim.api.nvim_win_get_cursor(0)[1]]
    if provider_name then
      launch_in_project(provider_name, vim.fn.getcwd())
    else
      M.toggle_session()
    end
  end, { buffer = agent_buf, desc = "Start provider under cursor / open agent tab" })
  -- j/k jump between provider rows on the cover
  for _, spec in ipairs({ { "j", 1 }, { "k", -1 }, { "<Down>", 1 }, { "<Up>", -1 } }) do
    vim.keymap.set("n", spec[1], function()
      if selected_agent_tab ~= "providers" then
        vim.cmd("normal! " .. (spec[2] > 0 and "j" or "k"))
        return
      end
      local rows = vim.tbl_keys(M._provider_rows)
      table.sort(rows)
      if #rows == 0 then return end
      local cur = vim.api.nvim_win_get_cursor(0)
      local target = spec[2] > 0 and rows[#rows] or rows[1]
      for i, row in ipairs(rows) do
        if row == cur[1] then target = rows[math.max(1, math.min(#rows, i + spec[2]))] end
      end
      vim.api.nvim_win_set_cursor(0, { target, cur[2] })
    end, { buffer = agent_buf, nowait = true })
  end
  -- Keep the cover centered when the panel resizes
  vim.api.nvim_create_autocmd("WinResized", {
    callback = function()
      if not agent_buf or not vim.api.nvim_buf_is_valid(agent_buf) then return true end
      local win = vim.fn.bufwinid(agent_buf)
      if selected_agent_tab == "providers" and win ~= -1
        and vim.tbl_contains(vim.v.event.windows or {}, win) then
        render_agent_panel()
      end
    end,
  })
  vim.keymap.set("n", "r", render_agent_panel, { buffer = agent_buf, desc = "Refresh agent panel" })
  install_agent_tab_number_maps(agent_buf, "n")
  vim.keymap.set("n", "<S-p>", M.select_provider, { buffer = agent_buf, desc = "Select provider" })
  vim.keymap.set("n", "<S-m>", M.open_market, { buffer = agent_buf, desc = "Open Agent Market" })
  vim.keymap.set("n", "<C-n>", M.new_session, { buffer = agent_buf, desc = "New session" })
  vim.keymap.set("n", "<C-r>", function() M.refresh_threads() end, { buffer = agent_buf, desc = "Refresh threads" })
  vim.keymap.set("n", "q", function() M.toggle() end, { buffer = agent_buf, desc = "Close panel" })

  render_agent_panel()
  return agent_buf
end

-- ─── Provider Selection ─────────────────────────────────────────────────────

function M.toggle_session()
  local sessions = get_active_sessions()
  if #sessions == 0 then
    M.new_session()
    return
  end

  vim.ui.select(sessions, {
    prompt = "Toggle session:",
    format_item = function(s)
      local status_icon = s.open and nf.play or nf.circle
      return string.format("%s %s - %s", status_icon, s.provider, s.name)
    end,
  }, function(session)
    if session then
      if session.open then
        session.terminal:close()
      else
        session.terminal:open()
      end
      current_provider = session.provider
      current_term = session.terminal
      render_agent_panel()
    end
  end)
end

launch_in_project = function(provider_name, project_cwd, initial_prompt, on_started, session_context)
  local function launch()
    M.launch_provider(provider_name, nil, project_cwd, true, initial_prompt, session_context)
    if on_started then vim.schedule(on_started) end
  end

  if project_cwd ~= vim.fn.getcwd() then
    vim.cmd("cd " .. vim.fn.fnameescape(project_cwd))
    if pcall(require, "neo-tree") then
      vim.api.nvim_command("Neotree " .. vim.fn.fnameescape(project_cwd))
    end
    vim.schedule(function()
      vim.schedule(launch)
    end)
  else
    launch()
  end
end

function M.select_provider()
  local project_cwd = vim.fn.getcwd()
  vim.ui.select(providers, {
    prompt = "Select agent provider:",
    format_item = function(p)
      return string.format("%s %s", p.icon, p.name)
    end,
  }, function(provider)
    if provider then launch_in_project(provider.name, project_cwd) end
  end)
end

-- ─── Session Management ─────────────────────────────────────────────────────

function M.new_session(project_cwd)
  project_cwd = project_cwd or vim.fn.getcwd()
  vim.ui.select(providers, {
    prompt = "New thread in " .. project_name(project_cwd) .. ":",
    format_item = function(p)
      return string.format("%s %s", p.icon, p.name)
    end,
  }, function(provider)
    if provider then
      launch_in_project(provider.name, project_cwd)
    end
  end)
end

-- Restore the agent panel buffer after closing a terminal
local function restore_agent_panel()
  if not agent_win or not vim.api.nvim_win_is_valid(agent_win) then return end
  -- Restore the agent panel buffer in the agent window
  local buf = M.ensure_agent_buf()
  vim.api.nvim_win_set_buf(agent_win, buf)
  current_term = nil
  render_agent_panel()
end

-- Close any running agent terminal to prevent two provider panels at the same time.
-- Checks direct_agent_sessions, current_term (ToggleTerm), and agent_explorer_win.
local function close_running_agent()
  -- Close direct agent sessions in agent_win
  for i = #direct_agent_sessions, 1, -1 do
    local s = direct_agent_sessions[i]
    if s.running and s.job then
      pcall(vim.api.nvim_chan_send, s.job, "\x04")
      s.running = false
    end
    if s.bufnr and vim.api.nvim_buf_is_valid(s.bufnr) then
      -- If the buffer is displayed in a window, restore the agent panel buffer
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_buf(win) == s.bufnr then
          if win == agent_win and vim.api.nvim_win_is_valid(agent_win) then
            local panel_buf = M.ensure_agent_buf()
            vim.api.nvim_win_set_buf(win, panel_buf)
          elseif win == agent_explorer_win and vim.api.nvim_win_is_valid(agent_explorer_win) then
            local panel_buf = M.ensure_agent_buf()
            vim.api.nvim_win_set_buf(win, panel_buf)
          end
        end
      end
      pcall(vim.api.nvim_buf_delete, s.bufnr, { force = true })
    end
  end
  direct_agent_sessions = {}

  -- Close ToggleTerm agent terminal
  if current_term and current_term.close then
    pcall(function() current_term:close() end)
  elseif current_term and current_term.job then
    pcall(vim.api.nvim_chan_send, current_term.job, "\x04")
  end
  current_term = nil
end

function M.launch_provider(provider_name, thread_id, project_cwd, force_new, initial_prompt, session_context)
  -- Never allow two provider panels at the same time
  close_running_agent()

  current_provider = provider_name
  current_thread_id = thread_id
  project_cwd = project_cwd or vim.fn.getcwd()
  if agent_win and vim.api.nvim_win_is_valid(agent_win) then
    apply_agent_style(agent_win)
  end

  local provider = nil
  for _, p in ipairs(providers) do
    if p.name == provider_name then
      provider = p
      break
    end
  end
  if not provider then return end

  -- Build command from the provider definition (supports dynamic providers from market)
  local cmd = provider.cmd or provider_name
  if thread_id then
    -- Try to append session resume to the command
    if provider_name == "OpenCode" then
      cmd = "opencode mini --session " .. thread_id
    elseif provider_name == "Junie" then
      cmd = "junie junie://sessions/" .. thread_id
    elseif provider_name == "Codex" then
      cmd = "codex resume " .. thread_id
    elseif provider_name == "Kiro" then
      cmd = "kiro-cli chat --resume-id " .. thread_id
    elseif provider_name == "Claude Code" then
      cmd = thread_id == "resume-picker" and "claude --resume" or ("claude --resume " .. thread_id)
    else
      -- Generic fallback: append thread_id to command
      cmd = cmd .. " " .. thread_id
    end
  end
  if initial_prompt then
    local quoted_prompt = vim.fn.shellescape(initial_prompt)
    if provider_name == "OpenCode" then
      cmd = "opencode mini --prompt " .. quoted_prompt
    elseif provider_name == "Claude Code" then
      cmd = "claude " .. quoted_prompt
    elseif provider_name == "Codex" then
      cmd = "codex " .. quoted_prompt
    else
      cmd = cmd .. " " .. quoted_prompt
    end
  end

  -- If we have an agent window open, launch the terminal IN that window
  if agent_win and vim.api.nvim_win_is_valid(agent_win) then
    -- Open the terminal directly in the agent window using vim.termopen
    vim.api.nvim_set_current_win(agent_win)
    local term_buf = vim.api.nvim_create_buf(false, true)
    vim.b[term_buf].agent_panel = true
    vim.b[term_buf].agent_provider = provider_name
    vim.b[term_buf].agent_project_cwd = project_cwd
    vim.api.nvim_win_set_buf(agent_win, term_buf)

    -- Run the command via the shell so it handles arguments correctly
    local shell = vim.o.shell or "bash"
    local shell_arg = vim.o.shellcmdflag or "-c"

    local session = {
      name = provider_name .. " · " .. project_name(project_cwd),
      provider = provider_name,
      cwd = project_cwd,
      thread_id = thread_id,
      task_id = session_context and session_context.task_id,
      task_title = session_context and session_context.task_title,
      change_snapshot = session_context and session_context.change_snapshot,
      bufnr = term_buf,
      started_at = os.time(),
      running = true,
      kind = "direct",
    }
    session.tab_id = (session_context and session_context.tab_id)
      or ("session:" .. tostring(term_buf))
    vim.b[term_buf].agent_thread_id = thread_id
    vim.b[term_buf].agent_task_id = session.task_id
    vim.b[term_buf].agent_task_title = session.task_title
    local job = vim.fn.termopen({ shell, shell_arg, cmd }, {
      cwd = project_cwd,
      on_exit = function(_, code)
        session.running = false
        session.exit_code = code
        vim.schedule(function()
          if current_term == session then
            if agent_win and vim.api.nvim_win_is_valid(agent_win)
              and vim.api.nvim_win_get_buf(agent_win) == term_buf then
              pcall(vim.cmd.stopinsert)
              apply_agent_style(agent_win)
            end
            render_agent_tabs()
          else
            render_agent_tabs()
          end
          open_task_changes(session)
        end)
      end,
    })

    if not job then
      -- Fallback: restore panel if termopen fails
      restore_agent_panel()
      return
    end

    session.job = job
    table.insert(direct_agent_sessions, session)
    current_term = session
    selected_agent_tab = session.tab_id
    render_agent_tabs()

    -- Keymaps for the terminal
    vim.keymap.set("t", "<C-\\>", function()
      -- Close terminal and restore agent panel
      if job then
        vim.api.nvim_chan_send(job, "\x04") -- Ctrl+D to exit
      end
    end, { buffer = term_buf, desc = "Exit terminal" })

    vim.keymap.set("t", "<C-n>", function()
      -- Close current terminal and start new session
      if job then
        vim.api.nvim_chan_send(job, "\x04")
      end
      vim.schedule(M.new_session)
    end, { buffer = term_buf, desc = "New session" })
    vim.keymap.set("t", "<C-g>", show_agent_panel, { buffer = term_buf, desc = "Show running agents" })
    vim.keymap.set("t", "<C-Tab>", function() cycle_agent_tab(1) end,
      { buffer = term_buf, desc = "Next agent tab" })
    vim.keymap.set("t", "<C-S-Tab>", function() cycle_agent_tab(-1) end,
      { buffer = term_buf, desc = "Previous agent tab" })
    vim.keymap.set("t", "<Tab>", function() cycle_agent_tab(1) end,
      { buffer = term_buf, desc = "Next agent tab" })
    vim.keymap.set("t", "<S-Tab>", function() cycle_agent_tab(-1) end,
      { buffer = term_buf, desc = "Previous agent tab" })
    install_agent_tab_number_maps(term_buf, "t")
    vim.keymap.set("n", "<Tab>", function() cycle_agent_tab(1) end,
      { buffer = term_buf, desc = "Next agent tab" })
    vim.keymap.set("n", "<S-Tab>", function() cycle_agent_tab(-1) end,
      { buffer = term_buf, desc = "Previous agent tab" })
    install_agent_tab_number_maps(term_buf, "n")

    vim.api.nvim_set_current_win(agent_win)
    vim.cmd.startinsert()
    vim.schedule(function()
      if visible_window(agent_win) then apply_agent_style(agent_win) end
    end)
    return
  end

  -- In edit mode, try to use agent_explorer_win if available
  if agent_explorer_win and vim.api.nvim_win_is_valid(agent_explorer_win) then
    -- Open the terminal directly in the agent explorer window
    vim.api.nvim_set_current_win(agent_explorer_win)
    local term_buf = vim.api.nvim_create_buf(false, true)
    vim.b[term_buf].agent_panel = true
    vim.b[term_buf].agent_provider = provider_name
    vim.b[term_buf].agent_project_cwd = project_cwd
    vim.api.nvim_win_set_buf(agent_explorer_win, term_buf)

    local shell = vim.o.shell or "bash"
    local shell_arg = vim.o.shellcmdflag or "-c"

    local session = {
      name = provider_name .. " · " .. project_name(project_cwd),
      provider = provider_name,
      cwd = project_cwd,
      thread_id = thread_id,
      task_id = session_context and session_context.task_id,
      task_title = session_context and session_context.task_title,
      change_snapshot = session_context and session_context.change_snapshot,
      bufnr = term_buf,
      started_at = os.time(),
      running = true,
      kind = "direct",
    }
    session.tab_id = (session_context and session_context.tab_id)
      or ("session:" .. tostring(term_buf))
    vim.b[term_buf].agent_thread_id = thread_id
    vim.b[term_buf].agent_task_id = session.task_id
    vim.b[term_buf].agent_task_title = session.task_title
    local job = vim.fn.termopen({ shell, shell_arg, cmd }, {
      cwd = project_cwd,
      on_exit = function(_, code)
        session.running = false
        session.exit_code = code
        vim.schedule(function()
          if current_term == session then
            if agent_explorer_win and vim.api.nvim_win_is_valid(agent_explorer_win)
              and vim.api.nvim_win_get_buf(agent_explorer_win) == term_buf then
              pcall(vim.cmd.stopinsert)
              apply_neo_tree_style(agent_explorer_win)
            end
            render_agent_tabs()
          else
            render_agent_tabs()
          end
          open_task_changes(session)
        end)
      end,
    })

    if not job then
      restore_agent_panel()
      return
    end

    session.job = job
    table.insert(direct_agent_sessions, session)
    current_term = session
    selected_agent_tab = session.tab_id
    render_agent_tabs()

    vim.keymap.set("t", "<C-\\>", function()
      if job then
        vim.api.nvim_chan_send(job, "\x04")
      end
    end, { buffer = term_buf, desc = "Exit terminal" })

    vim.keymap.set("t", "<C-n>", function()
      if job then
        vim.api.nvim_chan_send(job, "\x04")
      end
      vim.schedule(M.new_session)
    end, { buffer = term_buf, desc = "New session" })
    vim.keymap.set("t", "<C-g>", show_agent_panel, { buffer = term_buf, desc = "Show running agents" })
    vim.keymap.set("t", "<C-Tab>", function() cycle_agent_tab(1) end,
      { buffer = term_buf, desc = "Next agent tab" })
    vim.keymap.set("t", "<C-S-Tab>", function() cycle_agent_tab(-1) end,
      { buffer = term_buf, desc = "Previous agent tab" })
    vim.keymap.set("t", "<Tab>", function() cycle_agent_tab(1) end,
      { buffer = term_buf, desc = "Next agent tab" })
    vim.keymap.set("t", "<S-Tab>", function() cycle_agent_tab(-1) end,
      { buffer = term_buf, desc = "Previous agent tab" })
    install_agent_tab_number_maps(term_buf, "t")
    vim.keymap.set("n", "<Tab>", function() cycle_agent_tab(1) end,
      { buffer = term_buf, desc = "Next agent tab" })
    vim.keymap.set("n", "<S-Tab>", function() cycle_agent_tab(-1) end,
      { buffer = term_buf, desc = "Previous agent tab" })
    install_agent_tab_number_maps(term_buf, "n")

    vim.api.nvim_set_current_win(agent_explorer_win)
    vim.cmd.startinsert()
    vim.schedule(function()
      if visible_window(agent_explorer_win) then apply_neo_tree_style(agent_explorer_win) end
    end)
    return
  end

  -- Fallback: use ToggleTerm if no agent window is open
  local display_name = provider_name .. (thread_id and " Thread" or " Session")
    .. " · " .. project_name(project_cwd)
  if force_new then
    new_session_sequence = new_session_sequence + 1
    display_name = display_name .. " #" .. new_session_sequence
  end
  local Terminal = require("toggleterm.terminal").Terminal

  -- Reuse existing terminal
  if not force_new then
    for _, t in ipairs(require("toggleterm.terminal").get_all(true)) do
      if t.display_name == display_name then
        current_term = t
        if not t:is_open() then t:open() end
        vim.api.nvim_set_current_win(t.window)
        render_agent_panel()
        return
      end
    end
  end

  -- Create new terminal
  current_term = Terminal:new({
    display_name = display_name,
    cmd = cmd,
    dir = project_cwd,
    direction = "vertical",
    size = math.max(40, math.floor(vim.o.columns * 0.35)),
    hidden = true,
    start_in_insert = true,
    close_on_exit = false,
  })

  current_term:open()
  vim.schedule(function()
    local bufnr = current_term.bufnr
    if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end

    vim.b[bufnr].agent_panel = true
    vim.b[bufnr].agent_provider = provider_name
    vim.b[bufnr].agent_project_cwd = project_cwd
    current_term.task_id = session_context and session_context.task_id
    current_term.task_title = session_context and session_context.task_title
    current_term.change_snapshot = session_context and session_context.change_snapshot
    current_term.tab_id = (session_context and session_context.tab_id) or ("session:" .. tostring(bufnr))
    vim.b[bufnr].agent_thread_id = thread_id
    vim.b[bufnr].agent_task_id = current_term.task_id
    vim.b[bufnr].agent_task_title = current_term.task_title
    selected_agent_tab = current_term.tab_id
    if current_term.task_id and current_term.change_snapshot then
      local review_context = { cwd = project_cwd, change_snapshot = current_term.change_snapshot }
      vim.api.nvim_create_autocmd("TermClose", {
        buffer = bufnr,
        once = true,
        callback = function()
          vim.schedule(function() open_task_changes(review_context) end)
        end,
      })
    end

    vim.keymap.set("t", "<C-n>", M.new_session, {
      buffer = bufnr,
      desc = "Agents: new session",
    })
    vim.keymap.set("t", "<C-g>", show_agent_panel, {
      buffer = bufnr,
      desc = "Show running agents",
    })
    vim.keymap.set("t", "<C-Tab>", function() cycle_agent_tab(1) end, {
      buffer = bufnr, desc = "Next agent tab",
    })
    vim.keymap.set("t", "<C-S-Tab>", function() cycle_agent_tab(-1) end, {
      buffer = bufnr, desc = "Previous agent tab",
    })
    vim.keymap.set("t", "<Tab>", function() cycle_agent_tab(1) end, {
      buffer = bufnr, desc = "Next agent tab",
    })
    vim.keymap.set("t", "<S-Tab>", function() cycle_agent_tab(-1) end, {
      buffer = bufnr, desc = "Previous agent tab",
    })
    install_agent_tab_number_maps(bufnr, "t")
    vim.keymap.set("n", "<Tab>", function() cycle_agent_tab(1) end,
      { buffer = bufnr, desc = "Next agent tab" })
    vim.keymap.set("n", "<S-Tab>", function() cycle_agent_tab(-1) end,
      { buffer = bufnr, desc = "Previous agent tab" })
    install_agent_tab_number_maps(bufnr, "n")

    render_agent_tabs()

    render_agent_panel()
  end)
end

-- ─── Public API ─────────────────────────────────────────────────────────────

-- The session prompts should go to right now. Read at send time by
-- lenn.agent-context so switching agents mid-compose targets the new one.
-- Works for both direct termopen sessions and toggleterm terminals.
function M.active_session()
  local s = current_term
  if not s then return nil end
  local bufnr = s.bufnr
  local b = (bufnr and vim.api.nvim_buf_is_valid(bufnr)) and vim.b[bufnr] or {}
  return {
    provider = b.agent_provider or s.provider or current_provider,
    job = s.job_id or s.job or b.terminal_job_id,
    bufnr = bufnr,
    cwd = b.agent_project_cwd or s.cwd or s.dir,
    thread_id = b.agent_thread_id or s.thread_id,
  }
end

-- All saved threads across providers/projects, newest first (async because
-- OpenCode is read via sqlite3). Entries: { provider, icon, id, cwd, title, updated }
function M.list_threads(cb)
  collect_threads(cb)
end

-- Edgy calls these commands when opening pinned views.
-- They create the buffers in the current window.
-- Check if our panels are currently visible
local function is_open()
  return panels_visible
end

-- Hide our panels by closing windows and resetting references.
-- This ensures open_panels() creates fresh panels instead of trying to
-- restore hidden windows (nvim_win_set_buf does not make hidden windows visible).
-- Preserves the agent terminal buffer so it can be restored in the new panel.
hide_panels = function()
  -- Put real buffers back first so the agent terminal etc. are saved correctly
  M.restore_all()
  -- Bring back minimized buffers while the panels still exist to split from
  if has_hidden_windows() or #minimized_editor_bufs > 0 then
    restore_editor_buffers()
  end

  -- Save the agent terminal buffer before closing windows
  if agent_win and vim.api.nvim_win_is_valid(agent_win) then
    local buf = vim.api.nvim_win_get_buf(agent_win)
    if buf and vim.api.nvim_buf_is_valid(buf) and vim.b[buf].agent_panel then
      saved_agent_term_buf = buf
    end
  end

  -- Close all panel windows
  for _, win_id in ipairs({ threads_win, skills_win, keymaps_win, agent_win }) do
    if win_id and vim.api.nvim_win_is_valid(win_id) then
      pcall(vim.api.nvim_win_close, win_id, true)
    end
  end

  -- Reset all window references so has_hidden_windows() returns false
  threads_win = nil
  skills_win = nil
  keymaps_win = nil
  agent_win = nil

  -- Clean up mode-specific elements (also preserves agent_explorer term buf)
  close_agent_in_explorer()
  close_requirements_panel()
  close_planner_panel()
  panels_visible = false
end

-- Check if we have hidden windows to restore
has_hidden_windows = function()
  if threads_win and vim.api.nvim_win_is_valid(threads_win) then
    return true
  end
  if skills_win and vim.api.nvim_win_is_valid(skills_win) then
    return true
  end
  if keymaps_win and vim.api.nvim_win_is_valid(keymaps_win) then
    return true
  end
  if agent_win and vim.api.nvim_win_is_valid(agent_win) then
    return true
  end
  return false
end

-- Restore hidden panels or create new ones
open_panels = function()
  calculate_panel_widths()

  -- If already visible, just refresh
  if panels_visible then
    resize_panels()
    M.refresh()
    return
  end

  reset_project_expansion()

  -- Try to restore hidden windows first
  if has_hidden_windows() then
    -- Restore threads window if hidden
    if threads_win and vim.api.nvim_win_is_valid(threads_win) then
      local buf_t = M.ensure_threads_buf()
      vim.api.nvim_win_set_buf(threads_win, buf_t)
      vim.api.nvim_win_set_width(threads_win, threads_width)
      apply_neo_tree_style(threads_win)
      M.refresh_threads()
    end

    -- Restore skills window if hidden
    if skills_win and vim.api.nvim_win_is_valid(skills_win) then
      local buf_s = M.ensure_skills_buf()
      vim.api.nvim_win_set_buf(skills_win, buf_s)
      vim.api.nvim_win_set_width(skills_win, threads_width)
      apply_neo_tree_style(skills_win, "Skills")
      render_skills()
    end

    -- Restore keymaps window if hidden
    if keymaps_win and vim.api.nvim_win_is_valid(keymaps_win) then
      local buf_k = M.ensure_keymaps_buf()
      vim.api.nvim_win_set_buf(keymaps_win, buf_k)
      vim.api.nvim_win_set_width(keymaps_win, threads_width)
      apply_neo_tree_style(keymaps_win, "Keymaps")
      vim.schedule(render_keymaps_panel)
    end

    -- Restore agent window if hidden
    if agent_win and vim.api.nvim_win_is_valid(agent_win) then
      local buf_a = M.ensure_agent_buf()
      vim.api.nvim_win_set_buf(agent_win, buf_a)
      vim.api.nvim_win_set_width(agent_win, agent_width)
      apply_agent_style(agent_win)
      -- If there was a terminal active, it's already in the buffer
      render_agent_panel()
    end

    panels_visible = true
    vim.schedule(resize_panels)
    return
  end

  -- Create new panels from scratch
  local focus_win = vim.api.nvim_get_current_win()

  -- Find the leftmost non-panel window so panels always appear on the far left,
  -- even when the user has split buffers open side by side.
  -- Include floating windows (like Edgy/NeoTree) because they are valid targets
  -- for leftabove vsplit.
  local leftmost_win = nil
  local leftmost_col = 999999
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if is_workspace_panel(win) then goto continue end
    local config = vim.api.nvim_win_get_config(win)
    local col = config.col or 0
    if col < leftmost_col then
      leftmost_col = col
      leftmost_win = win
    end
    ::continue::
  end

  -- If no window found at all (unlikely), create a new editor window
  local base_win = leftmost_win or find_editor_window(focus_win)
  if not base_win then
    -- No suitable window exists; create a temporary editor window
    vim.cmd("edit")
    base_win = vim.api.nvim_get_current_win()
  end

  -- Create Threads+Skills panel (leftmost vertical split)
  vim.api.nvim_set_current_win(base_win)
  vim.cmd("leftabove vsplit")
  threads_win = vim.api.nvim_get_current_win()
  local buf_t = M.ensure_threads_buf()
  vim.api.nvim_win_set_buf(threads_win, buf_t)
  vim.api.nvim_win_set_width(threads_win, threads_width)
  apply_neo_tree_style(threads_win)

  -- Split horizontally to create Skills panel below Threads
  -- Use rightbelow so Skills appears BELOW Threads
  vim.cmd("rightbelow split")
  skills_win = vim.api.nvim_get_current_win()
  local buf_s = M.ensure_skills_buf()
  vim.api.nvim_win_set_buf(skills_win, buf_s)
  vim.api.nvim_win_set_width(skills_win, threads_width)
  apply_neo_tree_style(skills_win, "Skills")

  -- Split horizontally to create Keymaps panel below Skills
  vim.cmd("rightbelow split")
  keymaps_win = vim.api.nvim_get_current_win()
  local buf_k = M.ensure_keymaps_buf()
  vim.api.nvim_win_set_buf(keymaps_win, buf_k)
  vim.api.nvim_win_set_width(keymaps_win, threads_width)
  apply_neo_tree_style(keymaps_win, "Keymaps")

  -- Set heights: Skills ~25%, Keymaps fixed, Threads gets the rest
  local total_height = vim.api.nvim_win_get_height(threads_win) + vim.api.nvim_win_get_height(skills_win) + vim.api.nvim_win_get_height(keymaps_win)
  local skills_h = math.max(1, math.floor(total_height * skills_height_ratio))
  local keymaps_h = math.min(keymaps_height, total_height - skills_h - 1)
  keymaps_h = math.max(1, keymaps_h)
  vim.api.nvim_win_set_height(skills_win, skills_h)
  vim.api.nvim_win_set_height(keymaps_win, keymaps_h)

  M.refresh_threads()
  render_skills()
  vim.schedule(render_keymaps_panel)

  -- Add Agent beside Threads, before the main code window.
  vim.api.nvim_set_current_win(base_win)
  vim.cmd("leftabove vsplit")
  agent_win = vim.api.nvim_get_current_win()
  local buf_a = M.ensure_agent_buf()
  vim.api.nvim_win_set_buf(agent_win, buf_a)
  vim.api.nvim_win_set_width(agent_win, agent_width)

  -- Set winfixwidth on all panels
  vim.wo[agent_win].winfixwidth = true
  apply_agent_style(agent_win)

  -- Return focus to the window from which the workspace was opened.
  if vim.api.nvim_win_is_valid(focus_win) then
    vim.api.nvim_set_current_win(focus_win)
  else
    vim.api.nvim_set_current_win(base_win)
  end

  panels_visible = true
  -- Resize panels after the layout stabilizes (buffers may have been restored/hidden)
  vim.schedule(resize_panels)
end

function M.open()
  -- Open resets to full mode (all panels visible)
  M.set_mode("full", { skip_notify = true })
end

function M.toggle()
  if is_open() then
    hide_panels()
  else
    -- Restore to current mode
    apply_workspace_mode(current_workspace_mode, { skip_notify = true })
  end
end

-- Toggle only the Threads+Skills panel independently
-- Uses close/create instead of hide/show to guarantee correct position
function M.toggle_threads_only()
  calculate_panel_widths()

  -- Check if threads window exists and is valid (visible)
  local threads_exists = threads_win and vim.api.nvim_win_is_valid(threads_win)

  if threads_exists then
    -- Close threads, skills, keymaps, and details float
    pcall(vim.api.nvim_win_close, task_details_float, true)
    task_details_float = nil
    pcall(vim.api.nvim_win_close, threads_win, true)
    pcall(vim.api.nvim_win_close, skills_win, true)
    pcall(vim.api.nvim_win_close, keymaps_win, true)
    threads_win = nil
    skills_win = nil
    keymaps_win = nil
  else
    reset_project_expansion()

    -- Find the leftmost window to create the split from.
    -- We need the Threads panel to be the FIRST panel on the left,
    -- so we split from the leftmost non-floating window.
    local leftmost_win = nil
    local leftmost_col = 999999
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local config = vim.api.nvim_win_get_config(win)
      -- Skip floating windows
      if config.relative ~= "" then goto continue end
      local col = config.col or 0
      if col < leftmost_col then
        leftmost_col = col
        leftmost_win = win
      end
      ::continue::
    end

    local orig_win = vim.api.nvim_get_current_win()
    local orig_buf = vim.api.nvim_win_get_buf(orig_win)

    -- Focus the leftmost window and split from there
    if leftmost_win then
      vim.api.nvim_set_current_win(leftmost_win)
    end
    vim.cmd("leftabove vsplit")
    threads_win = vim.api.nvim_get_current_win()
    local buf_t = M.ensure_threads_buf()
    vim.api.nvim_win_set_buf(threads_win, buf_t)
    vim.api.nvim_win_set_width(threads_win, threads_width)
    apply_neo_tree_style(threads_win)

    -- Split horizontally to create Skills panel below Threads
    -- Use rightbelow so Skills appears BELOW Threads
    vim.cmd("rightbelow split")
    skills_win = vim.api.nvim_get_current_win()
    local buf_s = M.ensure_skills_buf()
    vim.api.nvim_win_set_buf(skills_win, buf_s)
    vim.api.nvim_win_set_width(skills_win, threads_width)
    apply_neo_tree_style(skills_win, "Skills")

    -- Split horizontally to create Keymaps panel below Skills
    vim.cmd("rightbelow split")
    keymaps_win = vim.api.nvim_get_current_win()
    local buf_k = M.ensure_keymaps_buf()
    vim.api.nvim_win_set_buf(keymaps_win, buf_k)
    vim.api.nvim_win_set_width(keymaps_win, threads_width)
    apply_neo_tree_style(keymaps_win, "Keymaps")

    -- Set heights: Skills ~25%, Keymaps fixed, Threads gets the rest
    local total_height = vim.api.nvim_win_get_height(threads_win) + vim.api.nvim_win_get_height(skills_win) + vim.api.nvim_win_get_height(keymaps_win)
    local skills_h = math.max(1, math.floor(total_height * skills_height_ratio))
    local keymaps_h = math.min(keymaps_height, total_height - skills_h - 1)
    keymaps_h = math.max(1, keymaps_h)
    vim.api.nvim_win_set_height(skills_win, skills_h)
    vim.api.nvim_win_set_height(keymaps_win, keymaps_h)

    M.refresh_threads()
    render_skills()
    vim.schedule(render_keymaps_panel)

    -- Restore focus to original window/buffer
    vim.api.nvim_set_current_win(orig_win)
    if not vim.api.nvim_win_is_valid(orig_win) then
      orig_win = vim.api.nvim_get_current_win()
    end
    vim.api.nvim_win_set_buf(orig_win, orig_buf)
  end
end

function M._is_left_open()
  return is_open()
end

-- Create commands for Edgy compatibility (in case Edgy tries to call them)
local function setup_commands()
  vim.api.nvim_create_user_command("LagentThreads", function()
    local buf = M.ensure_threads_buf()
    M.refresh_threads()
    vim.api.nvim_win_set_buf(0, buf)
  end, { force = true, bang = false })

  vim.api.nvim_create_user_command("LagentPanel", function()
    local buf = M.ensure_agent_buf()
    vim.api.nvim_win_set_buf(0, buf)
  end, { force = true, bang = false })
end

setup_commands()

function M.refresh()
  M.refresh_threads()
  render_skills()
  vim.schedule(render_keymaps_panel)
  render_agent_panel()
end

function M.get_threads_buf()
  return threads_buf
end

function M.get_threads_win()
  return threads_win
end

-- Open the Agent Market floating window
function M.open_market()
  market.open()
end

-- Open the Skill Market floating window
function M.open_skill_market()
  require("lenn.skill-market").open()
end

-- ─── Workspace Mode Public API ──────────────────────────────────────────────

function M.get_mode()
  return current_workspace_mode
end

function M.get_mode_info()
  return workspace_modes[current_workspace_mode]
end

function M.set_mode(mode, opts)
  if not workspace_modes[mode] then
    vim.notify("Unknown workspace mode: " .. mode, vim.log.levels.ERROR)
    return
  end
  apply_workspace_mode(mode, opts)
end

-- Rebuild the current workspace layout from scratch (e.g. after closing panels)
function M.rebuild()
  apply_workspace_mode(current_workspace_mode, { force = true })
end

vim.api.nvim_create_user_command("PanelMinimize", function() M.toggle_minimize() end,
  { force = true, desc = "Minimize / restore the current window" })
vim.api.nvim_create_user_command("PanelRestoreAll", function() M.restore_all() end,
  { force = true, desc = "Restore every minimized window" })

vim.api.nvim_create_user_command("LagentRebuild", function() M.rebuild() end,
  { force = true, desc = "Rebuild the current agent workspace layout" })

function M.next_mode()
  local mode_keys = { "agent", "edit", "full", "plan" }
  local idx = 1
  for i, k in ipairs(mode_keys) do
    if k == current_workspace_mode then
      idx = i
      break
    end
  end
  local next_idx = (idx % #mode_keys) + 1
  M.set_mode(mode_keys[next_idx])
end

function M.prev_mode()
  local mode_keys = { "agent", "edit", "full", "plan" }
  local idx = 1
  for i, k in ipairs(mode_keys) do
    if k == current_workspace_mode then
      idx = i
      break
    end
  end
  local prev_idx = ((idx - 2 + #mode_keys) % #mode_keys) + 1
  M.set_mode(mode_keys[prev_idx])
end

-- Cycle through modes with a selector
function M.select_mode()
  local mode_keys = { "agent", "edit", "full", "plan" }
  local choices = {}
  for _, k in ipairs(mode_keys) do
    local info = workspace_modes[k]
    table.insert(choices, string.format("%s %s — %s", info.icon, info.name, info.desc))
  end
  vim.ui.select(choices, {
    prompt = "Select workspace mode:",
    fmt_item = function(item)
      return item
    end,
  }, function(choice)
    if not choice then return end
    for _, k in ipairs(mode_keys) do
      local info = workspace_modes[k]
      local label = string.format("%s %s — %s", info.icon, info.name, info.desc)
      if choice == label then
        M.set_mode(k)
        break
      end
    end
  end)
end

return M
