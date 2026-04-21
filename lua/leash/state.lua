local M = {}

local sessions = {}
local current_id
local active_jobs = {}
local views = {}

function M.reset()
  sessions = {}
  current_id = nil
  active_jobs = {}
  views = {}
end

function M.register(session)
  if type(session) ~= "table" or type(session.id) ~= "string" then
    error("leash.nvim state: session must include string id", 2)
  end

  sessions[session.id] = session
  current_id = session.id

  return session
end

function M.unregister(session_id)
  sessions[session_id] = nil
  active_jobs[session_id] = nil
  views[session_id] = nil

  if current_id == session_id then
    current_id = nil
  end
end

function M.get(session_id)
  return sessions[session_id]
end

function M.current()
  if not current_id then
    return nil
  end

  return sessions[current_id]
end

function M.current_id()
  return current_id
end

function M.set_current(session_or_id)
  local session_id = type(session_or_id) == "table" and session_or_id.id or session_or_id

  if type(session_id) ~= "string" then
    error("leash.nvim state: current session id must be a string", 2)
  end

  if not sessions[session_id] then
    error("leash.nvim state: unknown session " .. session_id, 2)
  end

  current_id = session_id
  return sessions[session_id]
end

function M.all()
  local out = {}

  for _, session in pairs(sessions) do
    out[#out + 1] = session
  end

  table.sort(out, function(left, right)
    return (left.updated_at or left.created_at or 0) > (right.updated_at or right.created_at or 0)
  end)

  return out
end

function M.set_job(session_id, job_id)
  active_jobs[session_id] = job_id
end

function M.get_job(session_id)
  return active_jobs[session_id]
end

function M.clear_job(session_id)
  active_jobs[session_id] = nil
end

function M.set_view(session_id, view)
  views[session_id] = view
end

function M.get_view(session_id)
  return views[session_id]
end

function M.clear_view(session_id)
  views[session_id] = nil
end

return M
