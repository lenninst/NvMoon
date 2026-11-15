-- Agent Skills manager — reads Junie skills from ~/.junie/skills/
-- and persists enabled/disabled state in ~/.junie/skills.json
--
-- Each skill is a directory containing SKILL.md with YAML frontmatter:
--   ---
--   name: <skill-name>
--   description: >
--     <description text>
--   ---

local M = {}

local SKILLS_DIR = vim.fn.expand("~/.junie/skills")
local STATE_FILE = vim.fn.expand("~/.junie/skills.json")
local GUIDELINE_FILE = vim.fn.expand("~/.config/NvMoon/.junie/guidelines/skills.md")

-- ─── State ──────────────────────────────────────────────────────────────────

local function load_state()
  local ok, content = pcall(vim.fn.readfile, STATE_FILE)
  if ok and #content > 0 then
    local decode_ok, data = pcall(vim.json.decode, table.concat(content, "\n"))
    if decode_ok and type(data) == "table" then
      return data
    end
  end
  return { enabled = {} }
end

local function save_state(state)
  local dir = vim.fn.fnamemodify(STATE_FILE, ":h")
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, "p")
  end
  local lines = vim.json.encode(state, { indent = "  " })
  vim.fn.writefile(vim.split(lines, "\n"), STATE_FILE)
end

local function regenerate_guideline()
  local skills = M.get_skills()
  local enabled = {}
  for _, s in ipairs(skills) do
    if s.enabled then
      table.insert(enabled, s)
    end
  end

  local guideline_dir = vim.fn.fnamemodify(GUIDELINE_FILE, ":h")
  if vim.fn.isdirectory(guideline_dir) == 0 then
    vim.fn.mkdir(guideline_dir, "p")
  end

  local content = { "# Active Agent Skills", "" }
  if #enabled == 0 then
    table.insert(content, "No skills are currently enabled.")
  else
    table.insert(content, "The following Agent Skills are enabled by the user and should be used when relevant:")
    table.insert(content, "")
    for _, s in ipairs(enabled) do
      local desc = s.description:gsub("\n", " "):gsub("%s+", " "):gsub("^%s+", "")
      table.insert(content, string.format("- **%s**: %s", s.name, desc))
    end
  end
  table.insert(content, "")

  vim.fn.writefile(content, GUIDELINE_FILE)
end

-- ─── Skill Discovery ────────────────────────────────────────────────────────

local function parse_frontmatter(skill_md_path)
  local ok, lines = pcall(vim.fn.readfile, skill_md_path)
  if not ok or #lines == 0 then
    return nil
  end

  -- Read until closing ---
  local frontmatter = {}
  if lines[1] == "---" then
    for i = 2, #lines do
      if lines[i] == "---" then
        break
      end
      table.insert(frontmatter, lines[i])
    end
  end

  local name, description = nil, ""
  local in_multiline_desc = false

  for _, line in ipairs(frontmatter) do
    if in_multiline_desc then
      -- Multi-line description continuation (indented lines after `description: >`)
      if line:match("^%s+%S") then
        local cont = line:gsub("^%s+", "")
        if description ~= "" then
          description = description .. " " .. cont
        else
          description = cont
        end
      else
        in_multiline_desc = false
        -- Re-process this line as a new key
        if line:match("^name:%s*(.+)") then
          name = line:gsub("^name:%s*", ""):gsub("^%s*(.-)%s*$", "%1")
        elseif line:match("^description:%s*>") then
          in_multiline_desc = true
        elseif line:match("^description:%s*(.+)") then
          description = line:gsub("^description:%s*", ""):gsub("^%s*(.-)%s*$", "%1")
        end
      end
    elseif line:match("^name:%s*(.+)") then
      name = line:gsub("^name:%s*", ""):gsub("^%s*(.-)%s*$", "%1")
    elseif line:match("^description:%s*>") then
      -- Multi-line description block (check BEFORE generic description match)
      in_multiline_desc = true
    elseif line:match("^description:%s*(.+)") then
      description = line:gsub("^description:%s*", ""):gsub("^%s*(.-)%s*$", "%1")
    end
  end

  -- Truncate description to one line for display
  if description:len() > 100 then
    description = description:sub(1, 97) .. "..."
  end

  return { name = name, description = description }
end

function M.get_skills()
  local state = load_state()
  local enabled_set = {}
  for _, s in ipairs(state.enabled or {}) do
    enabled_set[s] = true
  end

  local skills = {}
  local uv = vim.uv or vim.loop
  local dir_handle = uv.fs_opendir(SKILLS_DIR)
  if not dir_handle then
    return skills
  end

  -- fs_readdir returns entries in batches; loop until nil
  local entries = uv.fs_readdir(dir_handle)
  while entries do
    for _, entry in ipairs(entries) do
      if entry.type == "directory" then
        local skill_md = SKILLS_DIR .. "/" .. entry.name .. "/SKILL.md"
        local info = parse_frontmatter(skill_md)
        if info and info.name then
          table.insert(skills, {
            name = info.name,
            description = info.description or "",
            enabled = enabled_set[info.name] or false,
            path = skill_md,
          })
        end
      end
    end
    entries = uv.fs_readdir(dir_handle)
  end
  uv.fs_closedir(dir_handle)

  -- Sort: enabled first, then alphabetically
  table.sort(skills, function(a, b)
    if a.enabled ~= b.enabled then
      return a.enabled
    end
    return a.name < b.name
  end)

  return skills
end

-- ─── Toggle ─────────────────────────────────────────────────────────────────

function M.toggle(skill_name)
  local state = load_state()
  local enabled_list = state.enabled or {}

  local idx = nil
  for i, s in ipairs(enabled_list) do
    if s == skill_name then
      idx = i
      break
    end
  end

  if idx then
    table.remove(enabled_list, idx)
    vim.notify("Skill disabled: " .. skill_name, vim.log.levels.INFO)
  else
    table.insert(enabled_list, skill_name)
    vim.notify("Skill enabled: " .. skill_name, vim.log.levels.INFO)
  end

  state.enabled = enabled_list
  save_state(state)
  regenerate_guideline()
end

function M.is_enabled(skill_name)
  local state = load_state()
  for _, s in ipairs(state.enabled or {}) do
    if s == skill_name then
      return true
    end
  end
  return false
end

return M
