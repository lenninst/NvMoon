-- Skill Repository — catalog of downloadable Agent Skills from external sources
-- Provides a built-in catalog of popular skills and supports installing from GitHub URLs.
--
-- Usage: require("lenn.skill-repo").get_catalog()
--        require("lenn.skill-repo").install(skill_entry, callback)

local M = {}

local SKILLS_DIR = vim.fn.expand("~/.junie/skills")

-- ─── Built-in Catalog ───────────────────────────────────────────────────────
-- Popular Agent Skills from GitHub repositories that users can install.
-- Format: { name, description, repo, path (subfolder in repo), author }

local CATALOG = {
  -- Vercel Labs skills (stored under skills/ subdirectory)
  {
    name = "react-best-practices",
    description = "React best practices for Vercel projects",
    repo = "vercel-labs/agent-skills",
    path = "skills/react-best-practices",
    author = "Vercel",
  },
  {
    name = "web-design-guidelines",
    description = "Web design guidelines and accessibility",
    repo = "vercel-labs/agent-skills",
    path = "skills/web-design-guidelines",
    author = "Vercel",
  },
  {
    name = "writing-guidelines",
    description = "Writing guidelines for documentation",
    repo = "vercel-labs/agent-skills",
    path = "skills/writing-guidelines",
    author = "Vercel",
  },
  {
    name = "react-view-transitions",
    description = "React view transitions patterns",
    repo = "vercel-labs/agent-skills",
    path = "skills/react-view-transitions",
    author = "Vercel",
  },
  {
    name = "vercel-optimize",
    description = "Vercel optimization patterns",
    repo = "vercel-labs/agent-skills",
    path = "skills/vercel-optimize",
    author = "Vercel",
  },
  {
    name = "deploy-to-vercel",
    description = "Deploy to Vercel guidance",
    repo = "vercel-labs/agent-skills",
    path = "skills/deploy-to-vercel",
    author = "Vercel",
  },
  {
    name = "composition-patterns",
    description = "Component composition patterns",
    repo = "vercel-labs/agent-skills",
    path = "skills/composition-patterns",
    author = "Vercel",
  },
  -- Anthropic official skills (stored under skills/ subdirectory)
  {
    name = "skill-creator",
    description = "Create new Agent Skills with proper structure",
    repo = "anthropics/skills",
    path = "skills/skill-creator",
    author = "Anthropic",
  },
  -- Remotion skills (stored under skills/ subdirectory)
  {
    name = "remotion-best-practices",
    description = "Remotion video creation best practices",
    repo = "remotion-dev/skills",
    path = "skills/remotion-best-practices",
    author = "Remotion",
  },
  {
    name = "remotion-captions",
    description = "Remotion captions and subtitles",
    repo = "remotion-dev/skills",
    path = "skills/remotion-captions",
    author = "Remotion",
  },
  {
    name = "remotion-render",
    description = "Remotion rendering best practices",
    repo = "remotion-dev/skills",
    path = "skills/remotion-render",
    author = "Remotion",
  },
  -- Anthropic additional skills
  {
    name = "frontend-design",
    description = "Frontend design guidelines",
    repo = "anthropics/skills",
    path = "skills/frontend-design",
    author = "Anthropic",
  },
  {
    name = "pdf",
    description = "PDF document handling",
    repo = "anthropics/skills",
    path = "skills/pdf",
    author = "Anthropic",
  },
  {
    name = "docx",
    description = "Word document handling",
    repo = "anthropics/skills",
    path = "skills/docx",
    author = "Anthropic",
  },
  {
    name = "xlsx",
    description = "Excel spreadsheet handling",
    repo = "anthropics/skills",
    path = "skills/xlsx",
    author = "Anthropic",
  },
  {
    name = "pptx",
    description = "PowerPoint presentation handling",
    repo = "anthropics/skills",
    path = "skills/pptx",
    author = "Anthropic",
  },
  {
    name = "webapp-testing",
    description = "Web application testing",
    repo = "anthropics/skills",
    path = "skills/webapp-testing",
    author = "Anthropic",
  },
  {
    name = "mcp-builder",
    description = "Build MCP servers",
    repo = "anthropics/skills",
    path = "skills/mcp-builder",
    author = "Anthropic",
  },
}

-- ─── Public API ─────────────────────────────────────────────────────────────

function M.get_catalog()
  return CATALOG
end

-- Search catalog by query string (matches name, description, author)
function M.search(query)
  if not query or query == "" then
    return CATALOG
  end
  local q = query:lower()
  local results = {}
  for _, skill in ipairs(CATALOG) do
    local match = false
    if skill.name:lower():find(q) then match = true end
    if (skill.description or ""):lower():find(q) then match = true end
    if (skill.author or ""):lower():find(q) then match = true end
    if match then
      table.insert(results, skill)
    end
  end
  return results
end

-- Check if a skill is already installed
function M.is_installed(skill_name)
  local skill_dir = SKILLS_DIR .. "/" .. skill_name
  return vim.fn.isdirectory(skill_dir) == 1
end

-- Get the GitHub raw URL for a skill's SKILL.md
local function github_raw_url(repo, path)
  return "https://raw.githubusercontent.com/" .. repo .. "/main/" .. path .. "/SKILL.md"
end

-- Get the GitHub tree URL for browsing
local function github_tree_url(repo, path)
  return "https://github.com/" .. repo .. "/tree/main/" .. path
end

-- Install a skill from GitHub by cloning the specific directory
-- Uses a temporary clone, then extracts only the needed skill directory
function M.install(skill_entry, callback)
  local skill_name = skill_entry.name
  local repo = skill_entry.repo
  local subpath = skill_entry.path or skill_name

  if M.is_installed(skill_name) then
    vim.notify("Skill ya instalado: " .. skill_name, vim.log.levels.WARN)
    if callback then callback(false, "ya instalado") end
    return
  end

  local install_dir = SKILLS_DIR .. "/" .. skill_name
  local repo_url = "https://github.com/" .. repo .. ".git"
  local tmp_dir = SKILLS_DIR .. "/.tmp_" .. skill_name

  vim.notify("Instalando skill: " .. skill_name .. " desde " .. repo, vim.log.levels.INFO)

  -- Ensure skills directory exists
  if vim.fn.isdirectory(SKILLS_DIR) == 0 then
    vim.fn.mkdir(SKILLS_DIR, "p")
  end

  -- Clean up any previous failed install
  vim.fn.delete(install_dir, "rf")
  vim.fn.delete(tmp_dir, "rf")

  -- Write a shell script for reliable execution
  local script_path = SKILLS_DIR .. "/.install_" .. skill_name .. ".sh"
  local f = io.open(script_path, "w")
  if f then
    f:write("#!/bin/sh\n")
    f:write("set -e\n")
    f:write("git clone --depth 1 --filter=blob:none " .. repo_url .. " " .. tmp_dir .. "\n")
    f:write("mkdir -p " .. install_dir .. "\n")
    f:write("cp -r " .. tmp_dir .. "/" .. subpath .. "/* " .. install_dir .. "/\n")
    f:write("cp -r " .. tmp_dir .. "/" .. subpath .. "/.* " .. install_dir .. "/ 2>/dev/null || true\n")
    f:write("rm -rf " .. tmp_dir .. "\n")
    f:close()
    os.execute("chmod +x " .. script_path)
  end

  vim.fn.jobstart(script_path, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_exit = function(_, exit_code)
      -- Clean up script
      vim.fn.delete(script_path, "rf")
      -- Clean up temp directory if it still exists
      vim.fn.delete(tmp_dir, "rf")

      if exit_code == 0 then
        -- Verify SKILL.md exists in install_dir
        local skill_md = install_dir .. "/SKILL.md"
        if vim.fn.filereadable(skill_md) == 1 then
          vim.notify("Skill instalado: " .. skill_name, vim.log.levels.INFO)
          if callback then callback(true, nil) end
        else
          -- SKILL.md not found - check what we actually got
          local files = vim.fn.glob(install_dir .. "/*", true, true)
          if #files > 0 then
            vim.notify(
              "Error: se clonó " .. skill_name .. " pero no se encontró SKILL.md. " ..
              "Verifica que el path del skill sea correcto.",
              vim.log.levels.ERROR
            )
          else
            vim.notify(
              "Error: no se pudo instalar " .. skill_name ..
              ", el directorio del skill está vacío o no existe.",
              vim.log.levels.ERROR
            )
          end
          vim.fn.delete(install_dir, "rf")
          if callback then callback(false, "no se encontró SKILL.md") end
        end
      else
        vim.notify(
          "Error: falló la instalación de " .. skill_name ..
          " (código de salida: " .. exit_code .. ").",
          vim.log.levels.ERROR
        )
        vim.fn.delete(install_dir, "rf")
        if callback then callback(false, "falló git clone") end
      end
    end,
  })
end

-- Uninstall a skill
function M.uninstall(skill_name, callback)
  if not M.is_installed(skill_name) then
    vim.notify("Skill no instalado: " .. skill_name, vim.log.levels.WARN)
    if callback then callback(false, "no instalado") end
    return
  end

  local install_dir = SKILLS_DIR .. "/" .. skill_name
  vim.fn.delete(install_dir, "rf")
  vim.notify("Skill desinstalado: " .. skill_name, vim.log.levels.INFO)
  if callback then callback(true, nil) end
end

-- Install from a custom GitHub URL (e.g., "user/repo/path/to/skill")
function M.install_from_url(url, callback)
  -- Parse GitHub URL formats:
  -- https://github.com/user/repo/tree/main/path/to/skill
  -- user/repo/path/to/skill
  -- https://github.com/user/repo

  local repo, subpath, skill_name

  -- Full GitHub URL with tree path
  local match = url:match("github.com/([^/]+/[^/]+)/tree/[^/]+/(.+)")
  if match then
    repo = url:match("github.com/([^/]+/[^/]+)")
    subpath = url:match("tree/[^/]+/(.+)")
    skill_name = subpath:match("([^/]+)$") -- last component as name
  else
    -- Simple user/repo or user/repo/path format
    local parts = {}
    for part in url:gmatch("([^/]+)") do
      table.insert(parts, part)
    end
    if #parts >= 2 then
      repo = parts[1] .. "/" .. parts[2]
      if #parts > 2 then
        subpath = table.concat(parts, "/", 3)
        skill_name = parts[#parts]
      else
        subpath = parts[2]
        skill_name = parts[2]
      end
    else
      vim.notify("Formato de URL inválido: " .. url, vim.log.levels.ERROR)
      if callback then callback(false, "URL inválida") end
      return
    end
  end

  local skill_entry = {
    name = skill_name,
    description = "Custom skill from " .. repo,
    repo = repo,
    path = subpath,
    author = repo:match("([^/]+)/"),
  }

  M.install(skill_entry, callback)
end

return M
