-- Local task persistence and GitHub issue loading for the agent workspace.
local M = {}

local function data_path()
  return vim.fn.stdpath("data") .. "/nvm-task-list.json"
end

local function read_store()
  local path = data_path()
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or not lines then return {} end
  local decoded_ok, value = pcall(vim.json.decode, table.concat(lines, "\n"))
  return decoded_ok and type(value) == "table" and value or {}
end

local function write_store(store)
  local path = data_path()
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  local tmp = path .. ".tmp"
  local ok, encoded = pcall(vim.json.encode, store)
  if not ok then return false end
  local write_ok = pcall(vim.fn.writefile, { encoded }, tmp)
  if not write_ok then return false end
  return vim.fn.rename(tmp, path) == 0
end

function M.repository(cwd)
  if vim.fn.executable("git") ~= 1 then return nil end
  local result = vim.system({ "git", "remote", "get-url", "origin" }, { cwd = cwd, text = true }):wait()
  if result.code ~= 0 then return nil end
  local remote = (result.stdout or ""):gsub("%s+$", "")
  local slug = remote:match("github%.com[:/]([^/]+/[^/]+)%.git$")
    or remote:match("github%.com[:/]([^/]+/[^/]+)$")
  return slug and slug:gsub("%.git$", "") or nil
end

function M.project_key(cwd)
  return M.repository(cwd) or vim.fn.fnamemodify(cwd, ":p")
end

function M.local_tasks(cwd)
  local store = read_store()
  local tasks = store[M.project_key(cwd)]
  return type(tasks) == "table" and tasks or {}
end

function M.update_local(cwd, task_id, fields)
  local store = read_store()
  local tasks = store[M.project_key(cwd)] or {}
  for _, task in ipairs(tasks) do
    if task.id == task_id then
      for key, value in pairs(fields) do task[key] = value end
      if fields.status then task.done = fields.status == "completed" end
      return write_store(store)
    end
  end
  return false
end

function M.track_issue(cwd, issue)
  local store = read_store()
  local key = M.project_key(cwd)
  store[key] = type(store[key]) == "table" and store[key] or {}
  local issue_url = issue.html_url or issue.url
  for _, task in ipairs(store[key]) do
    if task.source_issue_url == issue_url then return task end
  end
  local task = {
    id = "github-" .. tostring(issue.number),
    title = issue.title or "Untitled issue",
    body = issue.body,
    status = "pending",
    created_at = os.time(),
    source_issue_url = issue_url,
    source_issue_number = issue.number,
  }
  table.insert(store[key], task)
  if write_store(store) then return task end
  return nil
end

function M.add_local(cwd, title, acceptance_criteria, verification_command)
  local store = read_store()
  local key = M.project_key(cwd)
  store[key] = type(store[key]) == "table" and store[key] or {}
  local task = {
    id = tostring(os.time()) .. "-" .. tostring(math.random(1000, 9999)),
    title = title,
    acceptance_criteria = acceptance_criteria,
    verification_command = verification_command,
    status = "pending",
    done = false,
    created_at = os.time(),
  }
  table.insert(store[key], task)
  if write_store(store) then return task end
  return nil
end

function M.toggle_local(cwd, task_id)
  local store = read_store()
  local tasks = store[M.project_key(cwd)] or {}
  for _, task in ipairs(tasks) do
    if task.id == task_id then
      task.done = not task.done
      return write_store(store)
    end
  end
  return false
end

function M.delete_local(cwd, task_id)
  local store = read_store()
  local key = M.project_key(cwd)
  local tasks = store[key] or {}
  for index, task in ipairs(tasks) do
    if task.id == task_id then
      table.remove(tasks, index)
      store[key] = tasks
      return write_store(store)
    end
  end
  return false
end

function M.issues(cwd, callback)
  local repo = M.repository(cwd)
  if not repo then
    callback({}, "No GitHub origin configured for this project")
    return
  end
  if vim.fn.executable("gh") ~= 1 then
    callback({}, "GitHub CLI (gh) is not installed")
    return
  end

  local output = {}
  vim.fn.jobstart({ "gh", "issue", "list", "--repo", repo, "--state", "open", "--limit", "100", "--json", "number,title,body,url,labels" }, {
    cwd = cwd,
    stdout_buffered = true,
    on_stdout = function(_, data) output = data or {} end,
    on_exit = function(_, code)
      vim.schedule(function()
        if code ~= 0 then
          callback({}, "Could not load GitHub issues; check gh auth status")
          return
        end
        local ok, issues = pcall(vim.json.decode, table.concat(output, "\n"))
        callback(ok and type(issues) == "table" and issues or {}, nil)
      end)
    end,
  })
end

return M
