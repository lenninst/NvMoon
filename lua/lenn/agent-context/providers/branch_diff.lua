-- Branch Diff provider: working tree vs the merge-base with main/master.
-- Includes uncommitted changes so the agent sees everything this branch adds.
local nf = require("lenn.icons")
local resolve = require("lenn.agent-context.resolve")

local M = {
  name = "Branch Diff",
  icon = nf.explorer_git,
}

local function git(args, cwd)
  if vim.fn.executable("git") ~= 1 then return nil end
  local cmd = vim.list_extend({ "git", "-C", cwd }, args)
  local ok, proc = pcall(vim.system, cmd, { text = true })
  if not ok then return nil end
  local res = proc:wait(5000)
  if res.code ~= 0 then return nil end
  return res.stdout or ""
end

-- Base branch: origin/HEAD target if it exists, else main/master (local, then remote).
function M.base_branch(cwd)
  local head = git({ "symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD" }, cwd)
  local candidates = {}
  if head and vim.trim(head) ~= "" then
    local remote = vim.trim(head)
    candidates[#candidates + 1] = (remote:gsub("^origin/", ""))
    candidates[#candidates + 1] = remote
  end
  vim.list_extend(candidates, { "main", "master", "origin/main", "origin/master" })
  for _, ref in ipairs(candidates) do
    if git({ "rev-parse", "--verify", "--quiet", ref .. "^{commit}" }, cwd) then return ref end
  end
end

local function current_branch(cwd)
  local out = git({ "rev-parse", "--abbrev-ref", "HEAD" }, cwd)
  return out and vim.trim(out) or nil
end

local function info(cwd)
  if not git({ "rev-parse", "--is-inside-work-tree" }, cwd) then return nil, "not a git repo" end
  local base = M.base_branch(cwd)
  if not base then return nil, "no main/master branch" end
  local branch = current_branch(cwd)
  if branch == base or ("origin/" .. tostring(branch)) == base then return nil, "on " .. branch end
  local merge_base = git({ "merge-base", "HEAD", base }, cwd)
  if not merge_base then return nil, "no common ancestor with " .. base end
  return { base = base, branch = branch, merge_base = vim.trim(merge_base) }
end

function M.available(ctx)
  local i, why = info(ctx.cwd)
  if not i then return false, why end
  -- exit code 1 means there are differences
  local res = vim.system({ "git", "-C", ctx.cwd, "diff", "--quiet", i.merge_base }):wait(5000)
  if res.code == 0 then return false, "no changes vs " .. i.base end
  return true
end

function M.items(ctx, cb)
  local i = info(ctx.cwd)
  if not i then return cb(nil) end
  cb({
    provider = "branch_diff",
    key = "branch_diff:" .. ctx.cwd,
    label = "@BranchDiff:" .. i.base,
    cwd = ctx.cwd,
  })
end

function M.resolve(item, _, limits)
  local i, why = info(item.cwd)
  if not i then return nil, why end
  local stat = git({ "diff", "--stat", "--no-color", i.merge_base }, item.cwd) or ""
  local patch = git({ "diff", "--no-color", "--no-ext-diff", i.merge_base }, item.cwd)
  if not patch then return nil, "git diff failed" end
  if patch == "" then return nil, "no changes vs " .. i.base end

  local body, cut = resolve.truncate(patch, limits.diff_bytes)
  local attrs = { base = i.base, branch = i.branch }
  if cut then
    attrs.truncated = "true"
    body = body .. "\n… diff truncated; see the stat above for all changed files"
  end
  return { tag = "branch_diff", attrs = attrs, body = vim.trim(stat) .. "\n\n" .. body }
end

return M
