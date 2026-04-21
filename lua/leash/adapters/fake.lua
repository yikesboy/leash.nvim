local M = {
  name = "fake",
}

local function joinpath(...)
  if vim.fs and vim.fs.joinpath then
    return vim.fs.joinpath(...)
  end

  return table.concat({ ... }, "/")
end

local function plugin_root()
  local source = debug.getinfo(1, "S").source
  local path = source:sub(1, 1) == "@" and source:sub(2) or source

  return vim.fn.fnamemodify(path, ":p:h:h:h:h")
end

local function fixture_path(config)
  if config.fixture and config.fixture ~= "" then
    return config.fixture
  end

  return joinpath(plugin_root(), "test", "fixtures", "fake-agent.lua")
end

local function add_pair_args(args, flag, entries)
  if type(entries) ~= "table" then
    return
  end

  for _, entry in ipairs(entries) do
    if type(entry) == "table" and entry[1] and entry[2] then
      args[#args + 1] = flag
      args[#args + 1] = tostring(entry[1])
      args[#args + 1] = tostring(entry[2])
    end
  end
end

local function add_list_args(args, flag, entries)
  if type(entries) ~= "table" then
    return
  end

  for _, entry in ipairs(entries) do
    args[#args + 1] = flag
    args[#args + 1] = tostring(entry)
  end
end

local function decode_json(line)
  local ok, decoded = pcall(vim.json.decode, line)
  if ok then
    return decoded
  end

  return nil
end

local function raw_event(stream, line)
  return {
    type = "adapter.raw",
    stream = stream,
    message = line,
    raw = line,
  }
end

local function map_event(session, stream, payload)
  local event_type = payload.type

  if event_type == "thread.started" then
    session.vendor_session_id = payload.session_id
    return {
      type = "session.started",
      stream = stream,
      vendor_session_id = payload.session_id,
      raw = payload,
    }
  end

  if event_type == "turn.started" then
    return {
      type = "agent.turn_started",
      stream = stream,
      raw = payload,
    }
  end

  if event_type == "turn.completed" then
    return {
      type = "session.completed",
      stream = stream,
      raw = payload,
    }
  end

  if event_type == "turn.failed" then
    return {
      type = "session.failed",
      stream = stream,
      level = "error",
      message = payload.message,
      raw = payload,
    }
  end

  if event_type == "item.message" then
    return {
      type = "agent.message",
      stream = stream,
      message = payload.message,
      raw = payload,
    }
  end

  if event_type == "file.write" then
    return {
      type = "fake.file_write",
      stream = stream,
      path = payload.path,
      raw = payload,
    }
  end

  if event_type == "file.delete" then
    return {
      type = "fake.file_delete",
      stream = stream,
      path = payload.path,
      raw = payload,
    }
  end

  return {
    type = "adapter.raw",
    stream = stream,
    raw = payload,
  }
end

function M.capabilities()
  return {
    structured_events = true,
    fixture = true,
  }
end

function M.detect()
  return false
end

function M.start(opts)
  local config = opts.config or {}
  local actions = config.actions or {}
  local args = {
    "--headless",
    "-u",
    "NONE",
    "-i",
    "NONE",
    "-l",
    fixture_path(config),
    "--scenario",
    config.scenario or "success",
    "--session-id",
    config.session_id or "fake-thread",
  }

  if config.split_lines then
    args[#args + 1] = "--split-lines"
  end

  if config.sleep_ms then
    args[#args + 1] = "--sleep-ms"
    args[#args + 1] = tostring(config.sleep_ms)
  end

  if config.exit_code then
    args[#args + 1] = "--exit-code"
    args[#args + 1] = tostring(config.exit_code)
  end

  if opts.prompt and opts.prompt ~= "" then
    args[#args + 1] = "--message"
    args[#args + 1] = opts.prompt
  end

  add_pair_args(args, "--write", actions.write)
  add_list_args(args, "--delete", actions.delete)

  for _, extra_arg in ipairs(config.extra_args or {}) do
    args[#args + 1] = extra_arg
  end

  return {
    cmd = config.command or vim.v.progpath,
    args = args,
    cwd = opts.cwd,
    env = config.env,
  }
end

function M.resume(session, prompt, ctx)
  return M.start({
    config = ctx and ctx.config or {},
    cwd = session.cwd,
    prompt = prompt,
    root = session.root,
    session = session,
  })
end

function M.parse_line(session, stream, line)
  local payload = decode_json(line)
  if not payload then
    return { raw_event(stream, line) }
  end

  return { map_event(session, stream, payload) }
end

function M.finalize(session)
  return {
    adapter = M.name,
    status = session.status,
    vendor_session_id = session.vendor_session_id,
  }
end

return M
