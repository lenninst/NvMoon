-- Kiro agent browser & creator
-- <leader>ka  →  browse agents (picker)
-- <leader>kA  →  create new agent (wizard)
--
-- Loaded by lazy.nvim as a "virtual" spec (no plugin to install).
-- The module logic lives below and is exposed via a lazy `config` callback.

local M = {}

-- ─── helpers ────────────────────────────────────────────────────────────────

--- Strip ANSI escape sequences from a string
local function strip_ansi(s)
  return s:gsub("\27%[[%d;]*m", "")
end

--- Parse the output of `kiro-cli agent list` into a table of agent entries.
--- Each entry: { name, description, builtin, default, scope }
local function parse_agent_list(raw_lines)
  local agents = {}
  local current = nil

  for _, line in ipairs(raw_lines) do
    line = strip_ansi(line)

    -- Header lines like "Workspace: ..." / "Global: ..."  → skip
    if line:match("^Workspace:") or line:match("^Global:") or line == "" then
      goto continue
    end

    -- Agent line:  "* name   (Built-in)   description"
    --              "  name   (Built-in)   description"
    local is_default, name, rest = line:match("^(%*?)%s+(%S+)%s+(.*)")
    if name then
      -- Detect (Built-in) tag and strip it from rest
      local builtin = rest:match("%(Built%-in%)") ~= nil
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
      local continuation = line:match("^%s+(.*%S)")
      if continuation and current then
        current.description = current.description .. " " .. continuation
      end
    end

    ::continue::
  end

  return agents
end

--- Run `kiro-cli agent list` and return parsed entries (async, calls cb(agents))
local function fetch_agents(cb)
  local output = {}
  vim.fn.jobstart({ "kiro-cli", "agent", "list" }, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      vim.list_extend(output, data or {})
    end,
    on_stderr = function(_, data)
      vim.list_extend(output, data or {})
    end,
    on_exit = function(_, _)
      vim.schedule(function()
        cb(parse_agent_list(output))
      end)
    end,
  })
end

--- Launch a Kiro agent session via toggleterm
local function launch_agent(agent_name)
  local Terminal = require("toggleterm.terminal").Terminal
  local display = "Kiro Agent: " .. agent_name
  -- Reuse an existing terminal for the same agent if already open
  for _, t in ipairs(require("toggleterm.terminal").get_all(true)) do
    if t.display_name == display then
      if not t:is_open() then t:open() end
      vim.api.nvim_set_current_win(t.window)
      return
    end
  end
  local term = Terminal:new({
    display_name = display,
    cmd = "kiro-cli chat --agent " .. agent_name,
    direction = "vertical",
    size = math.max(18, math.min(42, math.floor(vim.o.columns * 0.3))),
    hidden = true,
    start_in_insert = true,
    close_on_exit = false,
  })
  term:open()
  vim.b[term.bufnr].agent_panel   = true
  vim.b[term.bufnr].agent_provider = "Kiro"
  vim.keymap.set("t", "<C-n>", function()
    require("lenn.agent-sessions").new()
  end, { buffer = term.bufnr, desc = "Agents: new session" })
  require("edgy.layout").update()
end

-- ─── Snacks picker ──────────────────────────────────────────────────────────

--- Open the Snacks picker with all Kiro agents.
--- Confirm → launch agent.  <C-c> → create new agent.
function M.browse()
  fetch_agents(function(agents)
    if #agents == 0 then
      vim.notify("No Kiro agents found", vim.log.levels.WARN)
      return
    end

    local items = vim.tbl_map(function(a)
      return {
        text  = a.name .. "  " .. a.description,
        -- fields used in the picker display
        _name = a.name,
        _desc = a.description,
        _meta = (a.default and "● default" or "")
               .. (a.builtin and "  built-in" or ""),
      }
    end, agents)

    Snacks.picker({
      title   = "Kiro Agents  (enter=launch · <C-n>=new agent)",
      items   = items,
      format  = function(item)
        -- Three columns: name (bold), description, meta
        local name_w = 18
        local name   = item._name
        local pad    = string.rep(" ", math.max(1, name_w - #name))
        return {
          { name,       "Title"   },
          { pad,        "Normal"  },
          { item._desc, "Comment" },
          { "  ",       "Normal"  },
          { item._meta, "Special" },
        }
      end,
      actions = {
        -- Default confirm: launch
        confirm = function(picker, sel)
          picker:close()
          if sel then launch_agent(sel._name) end
        end,
        -- <C-n>: open the create-new wizard
        new_agent = function(picker, _)
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

--- Sequential vim.ui.input prompts → write a JSON config → optionally validate.
function M.create()
  local fields = {}

  local function ask(prompt, default, cb)
    vim.ui.input({ prompt = prompt, default = default or "" }, function(val)
      if val == nil then
        vim.notify("Agent creation cancelled", vim.log.levels.INFO)
        return
      end
      cb(val)
    end)
  end

  -- Step 1: name
  ask("Agent name (no spaces): ", "", function(name)
    if name == "" then
      vim.notify("Name is required", vim.log.levels.WARN)
      return
    end
    name = name:gsub("%s+", "_"):lower()
    fields.name = name

    -- Step 2: description
    ask("Description: ", "", function(desc)
      fields.description = desc ~= "" and desc or ("Custom agent " .. name)

      -- Step 3: system prompt
      ask("System prompt (leave blank for none): ", "", function(prompt_text)
        fields.prompt = prompt_text ~= "" and prompt_text or vim.NIL

        -- Step 4: scope
        vim.ui.select(
          { "global (~/.kiro/agents/)", "workspace (.kiro/agents/)" },
          { prompt = "Save location:" },
          function(choice)
            if not choice then
              vim.notify("Agent creation cancelled", vim.log.levels.INFO)
              return
            end

            local is_workspace = choice:match("workspace") ~= nil
            local dir
            if is_workspace then
              dir = vim.fn.getcwd() .. "/.kiro/agents"
              vim.fn.mkdir(dir, "p")
            else
              dir = vim.fn.expand("~/.kiro/agents")
            end

            local path = dir .. "/" .. fields.name .. ".json"

            -- Step 5: model (optional)
            ask("Model (leave blank for default): ", "", function(model)
              fields.model = model ~= "" and model or vim.NIL

              -- Build config table
              local config = {
                name        = fields.name,
                description = fields.description,
                prompt      = fields.prompt,
                model       = fields.model,
                tools       = { "read", "write", "shell", "grep", "glob" },
                mcpServers  = vim.empty_dict(),
                allowedTools = {},
                resources   = {},
                toolsSettings = vim.empty_dict(),
                includeMcpJson = true,
              }

              -- Write the JSON file
              local ok, encoded = pcall(vim.json.encode, config)
              if not ok then
                vim.notify("Failed to encode config: " .. encoded, vim.log.levels.ERROR)
                return
              end

              -- Pretty-print via jq if available, otherwise write as-is
              local write_ok = false
              if vim.fn.executable("jq") == 1 then
                local tmp = path .. ".tmp"
                vim.fn.writefile({ encoded }, tmp)
                local result = vim.fn.system("jq . " .. vim.fn.shellescape(tmp) .. " > " .. vim.fn.shellescape(path))
                vim.fn.delete(tmp)
                write_ok = vim.v.shell_error == 0
              end
              if not write_ok then
                vim.fn.writefile({ encoded }, path)
                write_ok = true
              end

              vim.notify(
                string.format("Agent '%s' created at %s", fields.name, path),
                vim.log.levels.INFO
              )

              -- Validate
              vim.fn.jobstart({ "kiro-cli", "agent", "validate", "--path", path }, {
                stdout_buffered = true,
                stderr_buffered = true,
                on_exit = function(_, code)
                  vim.schedule(function()
                    if code == 0 then
                      vim.notify("Agent config is valid ✓", vim.log.levels.INFO)
                    else
                      vim.notify(
                        "Validation warnings (agent still saved): " .. path,
                        vim.log.levels.WARN
                      )
                    end

                    -- Ask if they want to launch it right away
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
            end) -- model
          end
        ) -- scope
      end) -- prompt
    end) -- description
  end) -- name
end

-- ─── Module keymaps (registered when this file is require'd) ────────────────

return {} -- logic moved to lua/lenn/kiro-agents.lua
