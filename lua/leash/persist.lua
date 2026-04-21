local M = {}

local function joinpath(...)
  if vim.fs and vim.fs.joinpath then
    return vim.fs.joinpath(...)
  end

  return table.concat({ ... }, "/")
end

local function json_encode(value)
  if vim.json and vim.json.encode then
    return vim.json.encode(value)
  end

  return vim.fn.json_encode(value)
end

local function json_decode(text)
  if vim.json and vim.json.decode then
    return vim.json.decode(text)
  end

  return vim.fn.json_decode(text)
end

local function read_file(path)
  local handle, open_err = io.open(path, "r")
  if not handle then
    return nil, open_err
  end

  local content = handle:read("*a")
  handle:close()
  return content
end

local function write_file(path, content)
  local handle, open_err = io.open(path, "w")
  if not handle then
    return nil, open_err
  end

  local ok, write_err = handle:write(content)
  handle:close()

  if not ok then
    return nil, write_err
  end

  return true
end

local function append_file(path, content)
  local handle, open_err = io.open(path, "a")
  if not handle then
    return nil, open_err
  end

  local ok, write_err = handle:write(content)
  handle:close()

  if not ok then
    return nil, write_err
  end

  return true
end

local function ensure_dir(path)
  local ok = vim.fn.mkdir(path, "p")
  if ok == 0 and vim.fn.isdirectory(path) == 0 then
    return nil, "failed to create directory: " .. path
  end

  return true
end

local function is_secret_key(key)
  if type(key) ~= "string" then
    return false
  end

  local lowered = key:lower()

  return lowered == "env"
    or lowered == "environment"
    or lowered:find("token", 1, true) ~= nil
    or lowered:find("secret", 1, true) ~= nil
    or lowered:find("authorization", 1, true) ~= nil
    or lowered:find("api_key", 1, true) ~= nil
    or lowered:find("apikey", 1, true) ~= nil
end

local function sanitize(value, seen)
  if type(value) ~= "table" then
    return value
  end

  seen = seen or {}
  if seen[value] then
    return "<cycle>"
  end
  seen[value] = true

  local out = {}

  for key, item in pairs(value) do
    if is_secret_key(key) then
      out[key] = "[REDACTED]"
    else
      out[key] = sanitize(item, seen)
    end
  end

  seen[value] = nil
  return out
end

local function decode_json_file(path)
  local content, read_err = read_file(path)
  if not content then
    return nil, read_err
  end

  if content == "" then
    return nil, "empty JSON file: " .. path
  end

  local ok, decoded = pcall(json_decode, content)
  if not ok then
    return nil, ("failed to decode JSON file %s: %s"):format(path, decoded)
  end

  return decoded
end

local function encode_json_file(path, value)
  local ok, encoded = pcall(json_encode, value)
  if not ok then
    return nil, ("failed to encode JSON for %s: %s"):format(path, encoded)
  end

  return write_file(path, encoded .. "\n")
end

function M.base_dir()
  return joinpath(vim.fn.stdpath("state"), "leash")
end

function M.sessions_dir()
  return joinpath(M.base_dir(), "sessions")
end

function M.session_dir(session_id)
  return joinpath(M.sessions_dir(), session_id)
end

function M.session_path(session_id)
  return joinpath(M.session_dir(session_id), "session.json")
end

function M.events_path(session_id)
  return joinpath(M.session_dir(session_id), "events.jsonl")
end

function M.decisions_path(session_id)
  return joinpath(M.session_dir(session_id), "decisions.json")
end

function M.summary_path(session_id)
  return joinpath(M.session_dir(session_id), "summary.json")
end

function M.ensure_session_dir(session_id)
  if type(session_id) ~= "string" or session_id == "" then
    return nil, "session_id must be a non-empty string"
  end

  return ensure_dir(M.session_dir(session_id))
end

function M.save_session(session_metadata)
  if type(session_metadata) ~= "table" or type(session_metadata.id) ~= "string" then
    return nil, "session metadata must include string id"
  end

  local ok, err = M.ensure_session_dir(session_metadata.id)
  if not ok then
    return nil, err
  end

  return encode_json_file(M.session_path(session_metadata.id), sanitize(session_metadata))
end

function M.load_session(session_id)
  if type(session_id) ~= "string" or session_id == "" then
    return nil, "session_id must be a non-empty string"
  end

  local path = M.session_path(session_id)
  if vim.fn.filereadable(path) == 0 then
    return nil, "session not found: " .. session_id
  end

  return decode_json_file(path)
end

function M.append_event(session_id, event)
  if type(event) ~= "table" then
    return nil, "event must be a table"
  end

  local ok, err = M.ensure_session_dir(session_id)
  if not ok then
    return nil, err
  end

  local encoded_ok, encoded = pcall(json_encode, sanitize(event))
  if not encoded_ok then
    return nil, ("failed to encode event for %s: %s"):format(session_id, encoded)
  end

  return append_file(M.events_path(session_id), encoded .. "\n")
end

function M.read_events(session_id)
  local path = M.events_path(session_id)
  if vim.fn.filereadable(path) == 0 then
    return {}
  end

  local content, read_err = read_file(path)
  if not content then
    return nil, read_err
  end

  local events = {}
  local line_number = 0

  for line in content:gmatch("([^\n]*)\n?") do
    if line ~= "" then
      line_number = line_number + 1

      local ok, event = pcall(json_decode, line)
      if not ok then
        return nil, ("failed to decode event line %d in %s: %s"):format(line_number, path, event)
      end

      events[#events + 1] = event
    end
  end

  return events
end

function M.save_decisions(session_id, decisions)
  local ok, err = M.ensure_session_dir(session_id)
  if not ok then
    return nil, err
  end

  return encode_json_file(M.decisions_path(session_id), sanitize(decisions or {}))
end

function M.load_decisions(session_id)
  local path = M.decisions_path(session_id)
  if vim.fn.filereadable(path) == 0 then
    return {}
  end

  return decode_json_file(path)
end

function M.save_summary(session_id, summary)
  local ok, err = M.ensure_session_dir(session_id)
  if not ok then
    return nil, err
  end

  return encode_json_file(M.summary_path(session_id), sanitize(summary or {}))
end

function M.load_summary(session_id)
  local path = M.summary_path(session_id)
  if vim.fn.filereadable(path) == 0 then
    return {}
  end

  return decode_json_file(path)
end

function M.list_sessions()
  local dir = M.sessions_dir()
  if vim.fn.isdirectory(dir) == 0 then
    return {}
  end

  local out = {}
  local entries = vim.fn.readdir(dir)

  for _, session_id in ipairs(entries) do
    if session_id ~= "." and session_id ~= ".." and vim.fn.filereadable(M.session_path(session_id)) == 1 then
      local metadata = M.load_session(session_id)
      if metadata then
        out[#out + 1] = metadata
      end
    end
  end

  table.sort(out, function(left, right)
    return (left.updated_at or left.created_at or 0) > (right.updated_at or right.created_at or 0)
  end)

  return out
end

return M
