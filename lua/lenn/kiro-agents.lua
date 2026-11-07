-- Kiro agent browser & creator
-- Called from lua/lenn/plugins/kiro-agents.lua via lazy config callback.
--
--   <leader>ka  →  browse agents (Snacks picker)
--   <leader>kA  →  create new agent (step-by-step wizard)

local M = {}

-- ─── helpers ────────────────────────────────────────────────────────────────

--- Strip ANSI escape sequences
local function strip_ansi(s)
  return s:gsub("\27%[[%d;]*m", "")
end

--- Parse `kiro-cli agent list` output into a list of agent tables:
---   { name, description, builtin, default }
local function parse_agent_list(raw_lines)
  local agents = {}
  local current = nil

  for _, line in ipairs(raw_lines) do
    line = strip_ansi(line)

    -- Skip header / blank lines
    if line:match("^Workspace:") or line:match("^Global:") or line == "" then
      goto continue
    end

    -- Agent line:  "* name   (Built-in)   description"
    --              "  name   (Built-in)   description"
    local is_default, name, rest = line:match("^(%*?)%s+(%S+)%s+(.*)")
    if name then
      local builtin     = rest:match("%(Built%-in%)") ~= nil
      local description = rest:gsub("%(Built%-in%)%s*", ""):match("^%s*(.-)%s*$")
      current = {
        name        = name,
        description = description,
        builtin     = builtin,
        default     = is_default == "*",
      }
      table.insert(agents, current)
    else
      -- Continuation line for a multi-line description
      local cont = line:match("^%s+(.*%S)")
      if cont and current then
        current.description = current.description .. " " .. cont
      end
    end

    ::continue::
  end

  return agents
end

--- Async: run `kiro-cli agent list`, call cb(agents)
local function fetch_agents(cb)
  local out = {}
  vim.fn.jobstart({ "kiro-cli", "agent", "list" }, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data) vim.list_extend(out, data or {}) end,
    on_stderr = function(_, data) vim.list_extend(out, data or {}) end,
    on_exit   = function()
      vim.schedule(function() cb(parse_agent_list(out)) end)
    end,
  })
end

--- Open a Kiro agent in a vertical toggleterm panel (reuses existing terminal)
local function launch_agent(agent_name)
  local Terminal = require("toggleterm.terminal").Terminal
  local display  = "Kiro Agent: " .. agent_name

  for _, t in ipairs(require("toggleterm.terminal").get_all(true)) do
    if t.display_name == display then
      if not t:is_open() then t:open() end
      vim.api.nvim_set_current_win(t.window)
      return
    end
  end

  local term = Terminal:new({
    display_name    = display,
    cmd             = "kiro-cli chat --agent " .. agent_name,
    direction       = "vertical",
    size            = math.max(18, math.min(42, math.floor(vim.o.columns * 0.3))),
    hidden          = true,
    start_in_insert = true,
    close_on_exit   = false,
  })
  term:open()
  vim.b[term.bufnr].agent_panel    = true
  vim.b[term.bufnr].agent_provider = "Kiro"
  vim.keymap.set("t", "<C-n>", function()
    require("lenn.agent-sessions").new()
  end, { buffer = term.bufnr, desc = "Agents: new session" })
  require("edgy.layout").update()
end

-- ─── Snacks picker ──────────────────────────────────────────────────────────

--- Browse all available Kiro agents.
--- <CR>   → launch the selected agent
--- <C-n>  → open the create-new wizard
function M.browse()
  fetch_agents(function(agents)
    if #agents == 0 then
      vim.notify("No Kiro agents found", vim.log.levels.WARN)
      return
    end

    local items = vim.tbl_map(function(a)
      local tags = {}
      if a.default then table.insert(tags, "● default") end
      if a.builtin then table.insert(tags, "built-in")  end
      return {
        text  = a.name .. "  " .. a.description,
        _name = a.name,
        _desc = a.description,
        _meta = table.concat(tags, "  "),
      }
    end, agents)

    Snacks.picker({
      title = "Kiro Agents  [enter=launch · <C-n>=new]",
      items = items,
      format = function(item)
        local name_w = 20
        local pad    = string.rep(" ", math.max(1, name_w - #item._name))
        return {
          { item._name, "Title"   },
          { pad,        "Normal"  },
          { item._desc, "Comment" },
          { "  ",       "Normal"  },
          { item._meta, "Special" },
        }
      end,
      actions = {
        confirm = function(picker, sel)
          picker:close()
          if sel then launch_agent(sel._name) end
        end,
        new_agent = function(picker)
          picker:close()
          vim.schedule(M.create)
        end,
      },
      win = {
        input = {
          keys = {
            ["<C-n>"] = { "new_agent", mode = { "i", "n" }, desc = "New agent" },
          },
        },
      },
    })
  end)
end

-- ─── Create-agent wizard ────────────────────────────────────────────────────

--- Sequential vim.ui.input / vim.ui.select prompts → writes a JSON config
--- → validates it → offers to launch or open the file.
function M.create()
  local fields = {}

  -- Helper: ask a question and call cb(value). Cancels the whole chain on nil.
  local function ask(prompt, default, cb)
    vim.ui.input({ prompt = prompt, default = default or "" }, function(val)
      if val == nil then
        vim.notify("Agent creation cancelled", vim.log.levels.INFO)
      else
        cb(val)
      end
    end)
  end

  -- 1 · Name
  ask("Agent name (no spaces): ", "", function(name)
    if name == "" then
      vim.notify("Name is required", vim.log.levels.WARN)
      return
    end
    fields.name = name:gsub("%s+", "_"):lower()

    -- 2 · Description
    ask("Description: ", "", function(desc)
      fields.description = desc ~= "" and desc or ("Custom agent " .. fields.name)

      -- 3 · System prompt
      ask("System prompt (blank = none): ", "", function(prompt_text)
        fields.prompt = prompt_text ~= "" and prompt_text or vim.NIL

        -- 4 · Model
        ask("Model (blank = default): ", "", function(model)
          fields.model = model ~= "" and model or vim.NIL

          -- 5 · Save location
          vim.ui.select(
            { "global  → ~/.kiro/agents/", "workspace  → .kiro/agents/" },
            { prompt = "Save location:" },
            function(choice)
              if not choice then
                vim.notify("Agent creation cancelled", vim.log.levels.INFO)
                return
              end

              local is_ws = choice:match("workspace") ~= nil
              local dir
              if is_ws then
                dir = vim.fn.getcwd() .. "/.kiro/agents"
                vim.fn.mkdir(dir, "p")
              else
                dir = vim.fn.expand("~/.kiro/agents")
              end

              local path = dir .. "/" .. fields.name .. ".json"

              -- Build + write JSON
              local config = {
                name           = fields.name,
                description    = fields.description,
                prompt         = fields.prompt,
                model          = fields.model,
                tools          = { "read", "write", "shell", "grep", "glob" },
                mcpServers     = vim.empty_dict(),
                allowedTools   = {},
                resources      = {},
                toolsSettings  = vim.empty_dict(),
                includeMcpJson = true,
              }

              local ok, encoded = pcall(vim.json.encode, config)
              if not ok then
                vim.notify("JSON encode error: " .. encoded, vim.log.levels.ERROR)
                return
              end

              -- Pretty-print with jq when available
              if vim.fn.executable("jq") == 1 then
                local tmp = path .. ".tmp"
                vim.fn.writefile({ encoded }, tmp)
                vim.fn.system("jq . " .. vim.fn.shellescape(tmp) .. " > " .. vim.fn.shellescape(path))
                vim.fn.delete(tmp)
                if vim.v.shell_error ~= 0 then
                  vim.fn.writefile({ encoded }, path)
                end
              else
                vim.fn.writefile({ encoded }, path)
              end

              vim.notify(
                ("Agent '%s' saved → %s"):format(fields.name, path),
                vim.log.levels.INFO
              )

              -- Validate
              vim.fn.jobstart({ "kiro-cli", "agent", "validate", "--path", path }, {
                stdout_buffered = true,
                stderr_buffered = true,
                on_exit = function(_, code)
                  vim.schedule(function()
                    if code == 0 then
                      vim.notify("Agent config valid ✓", vim.log.levels.INFO)
                    else
                      vim.notify("Validation warnings — check " .. path, vim.log.levels.WARN)
                    end

                    vim.ui.select(
                      { "Launch now", "Open config file", "Done" },
                      { prompt = "Agent created — what next?" },
                      function(action)
                        if action == "Launch now" then
                          launch_agent(fields.name)
                        elseif action == "Open config file" then
                          vim.cmd("edit " .. vim.fn.fnameescape(path))
                        end
                      end
                    )
                  end)
                end,
              })
            end -- scope select
          )
        end) -- model
      end) -- prompt
    end) -- description
  end) -- name
end

return M
