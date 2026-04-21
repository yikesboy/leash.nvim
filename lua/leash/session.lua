local config = require("leash.config")
local persist = require("leash.persist")

local M = {}

local statuses = {
  idle = true,
  running = true,
  review = true,
  done = true,
  failed = true,
  aborted = true,
}

local transitions = {
  idle = { running = true, review = true, done = true, failed = true, aborted = true },
  running = { review = true, done = true, failed = true, aborted = true },
  review = { running = true, done = true, failed = true, aborted = true },
  done = {},
  failed = {},
  aborted = {},
}

local function now()
  return os.time()
end

local function uv()
  return vim.uv or vim.loop
end

local function root_or_cwd(root)
  return root or uv().cwd()
end

local function generate_id()
  local random = math.random(0, 0xffffff)
  local hrtime = tostring(uv().hrtime()):sub(-8)

  return ("%s-%s-%06x"):format(os.date("!%Y%m%dT%H%M%SZ"), hrtime, random)
end

local function touch(session)
  session.updated_at = now()
end

local function copy_array(value)
  if type(value) ~= "table" then
    return {}
  end

  local out = {}
  for index, item in ipairs(value) do
    out[index] = item
  end
  return out
end

local function snapshot_metadata(snapshot)
  if type(snapshot) ~= "table" then
    return nil
  end

  return {
    path = snapshot.path,
    relpath = snapshot.relpath,
    sha256 = snapshot.sha256,
  }
end

local function hunk_metadata(hunk)
  return {
    id = hunk.id,
    start_a = hunk.start_a,
    count_a = hunk.count_a,
    start_b = hunk.start_b,
    count_b = hunk.count_b,
    status = hunk.status or "pending",
  }
end

local function file_metadata(change)
  local hunks = {}

  for _, hunk in ipairs(change.hunks or {}) do
    hunks[#hunks + 1] = hunk_metadata(hunk)
  end

  return {
    relpath = change.relpath,
    status = change.status,
    original = snapshot_metadata(change.original),
    proposed_path = change.proposed_path,
    proposed_sha256 = change.proposed_sha256,
    hunks = hunks,
    accepted = change.accepted == true,
    rejected = change.rejected == true,
    conflict = change.conflict == true,
  }
end

local function normalized_event(event)
  local out = vim.deepcopy(event)

  out.type = out.type or "adapter.raw"
  out.timestamp = out.timestamp or now()

  return out
end

function M.is_valid_status(status)
  return statuses[status] == true
end

function M.create(opts)
  opts = opts or {}

  local created_at = now()
  local id = opts.id or generate_id()
  local root = root_or_cwd(opts.root)
  local prompt_history = copy_array(opts.prompt_history)

  if opts.prompt and opts.prompt ~= "" then
    prompt_history[#prompt_history + 1] = opts.prompt
  end

  local out = {
    id = id,
    adapter = opts.adapter or config.get().adapter,
    root = root,
    worktree_dir = opts.worktree_dir,
    cwd = opts.cwd or root,
    job_id = opts.job_id,
    vendor_session_id = opts.vendor_session_id,
    status = opts.status or "idle",
    prompt_history = prompt_history,
    log_path = opts.log_path or persist.events_path(id),
    files = opts.files or {},
    selection_context = opts.selection_context,
    created_at = opts.created_at or created_at,
    updated_at = opts.updated_at or created_at,
  }

  return M.validate(out)
end

function M.validate(session)
  if type(session) ~= "table" then
    error("leash.nvim session: session must be a table", 2)
  end

  if type(session.id) ~= "string" or session.id == "" then
    error("leash.nvim session: session id must be a non-empty string", 2)
  end

  if type(session.adapter) ~= "string" or session.adapter == "" then
    error("leash.nvim session: adapter must be a non-empty string", 2)
  end

  if not M.is_valid_status(session.status) then
    error("leash.nvim session: invalid status " .. tostring(session.status), 2)
  end

  return session
end

function M.set_status(session, status)
  if not M.is_valid_status(status) then
    error("leash.nvim session: invalid status " .. tostring(status), 2)
  end

  if session.status == status then
    return session
  end

  local allowed = transitions[session.status] or {}
  if not allowed[status] then
    error(("leash.nvim session: cannot transition from %s to %s"):format(session.status, status), 2)
  end

  session.status = status
  touch(session)

  return session
end

function M.add_prompt(session, prompt)
  if type(prompt) ~= "string" or prompt == "" then
    return session
  end

  session.prompt_history = session.prompt_history or {}
  session.prompt_history[#session.prompt_history + 1] = prompt
  touch(session)

  return session
end

function M.add_file_change(session, change)
  if type(change) ~= "table" or type(change.relpath) ~= "string" or change.relpath == "" then
    error("leash.nvim session: file change must include relpath", 2)
  end

  session.files = session.files or {}
  change.hunks = change.hunks or {}
  change.accepted = change.accepted == true
  change.rejected = change.rejected == true
  change.conflict = change.conflict == true
  session.files[change.relpath] = change
  touch(session)

  return change
end

function M.record_file_decision(session, relpath, decision)
  if decision ~= "accepted" and decision ~= "rejected" and decision ~= "conflict" then
    error("leash.nvim session: invalid file decision " .. tostring(decision), 2)
  end

  session.files = session.files or {}

  local change = session.files[relpath] or {
    relpath = relpath,
    status = "unknown",
    hunks = {},
  }

  change.accepted = decision == "accepted"
  change.rejected = decision == "rejected"
  change.conflict = decision == "conflict"
  session.files[relpath] = change
  touch(session)

  return change
end

function M.record_hunk_decision(session, relpath, hunk_id, decision)
  if decision ~= "accepted" and decision ~= "rejected" and decision ~= "conflict" then
    error("leash.nvim session: invalid hunk decision " .. tostring(decision), 2)
  end

  local change = session.files and session.files[relpath]
  if not change then
    error("leash.nvim session: unknown file " .. tostring(relpath), 2)
  end

  for _, hunk in ipairs(change.hunks or {}) do
    if hunk.id == hunk_id then
      hunk.status = decision
      touch(session)
      return hunk
    end
  end

  error("leash.nvim session: unknown hunk " .. tostring(hunk_id), 2)
end

function M.to_metadata(session)
  local files = {}

  for relpath, change in pairs(session.files or {}) do
    files[relpath] = file_metadata(change)
  end

  return {
    id = session.id,
    adapter = session.adapter,
    root = session.root,
    worktree_dir = session.worktree_dir,
    cwd = session.cwd,
    job_id = session.job_id,
    vendor_session_id = session.vendor_session_id,
    status = session.status,
    prompt_history = copy_array(session.prompt_history),
    log_path = session.log_path,
    files = files,
    selection_context = session.selection_context,
    created_at = session.created_at,
    updated_at = session.updated_at,
  }
end

function M.to_decisions(session)
  local files = {}

  for relpath, change in pairs(session.files or {}) do
    local hunks = {}

    for _, hunk in ipairs(change.hunks or {}) do
      if hunk.id and hunk.status and hunk.status ~= "pending" then
        hunks[hunk.id] = hunk.status
      end
    end

    if change.accepted or change.rejected or change.conflict or next(hunks) ~= nil then
      files[relpath] = {
        accepted = change.accepted == true,
        rejected = change.rejected == true,
        conflict = change.conflict == true,
        hunks = hunks,
      }
    end
  end

  return {
    session_id = session.id,
    files = files,
    updated_at = session.updated_at,
  }
end

function M.save(session)
  if not config.get().persistence.enabled then
    return true
  end

  local ok, err = persist.save_session(M.to_metadata(session))
  if not ok then
    return nil, err
  end

  return persist.save_decisions(session.id, M.to_decisions(session))
end

function M.load(session_id)
  local metadata, err = persist.load_session(session_id)
  if not metadata then
    return nil, err
  end

  local session = M.create(metadata)
  local decisions = persist.load_decisions(session_id)

  if type(decisions) == "table" and type(decisions.files) == "table" then
    for relpath, decision in pairs(decisions.files) do
      local change = session.files[relpath]
      if change then
        change.accepted = decision.accepted == true
        change.rejected = decision.rejected == true
        change.conflict = decision.conflict == true

        for _, hunk in ipairs(change.hunks or {}) do
          if decision.hunks and decision.hunks[hunk.id] then
            hunk.status = decision.hunks[hunk.id]
          end
        end
      end
    end
  end

  return session
end

function M.append_event(session, event)
  local out = normalized_event(event)

  if config.get().persistence.enabled then
    local ok, err = persist.append_event(session.id, out)
    if not ok then
      return nil, err
    end
  end

  return out
end

return M
