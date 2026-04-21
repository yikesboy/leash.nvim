local session_api = require("leash.session")
local state = require("leash.state")

local M = {}

local function now()
  return os.time()
end

local function schedule(fn)
  vim.schedule(fn)
end

local function emit(session, opts, event)
  event.timestamp = event.timestamp or now()

  local ok, err = session_api.append_event(session, event)
  if not ok then
    vim.schedule(function()
      vim.notify("leash.nvim runner: failed to persist event: " .. err, vim.log.levels.WARN)
    end)
  end

  if opts and opts.on_event then
    opts.on_event(event)
  end
end

local function validate_session(session)
  if type(session) ~= "table" or type(session.id) ~= "string" then
    error("leash.nvim runner: session must include string id", 3)
  end
end

local function validate_spec(spec)
  if type(spec) ~= "table" then
    error("leash.nvim runner: command spec must be a table", 3)
  end

  if type(spec.cmd) ~= "string" or spec.cmd == "" then
    error("leash.nvim runner: command spec cmd must be a non-empty string", 3)
  end

  if spec.args ~= nil and type(spec.args) ~= "table" then
    error("leash.nvim runner: command spec args must be a table", 3)
  end

  if spec.cwd ~= nil and type(spec.cwd) ~= "string" then
    error("leash.nvim runner: command spec cwd must be a string", 3)
  end

  if spec.env ~= nil and type(spec.env) ~= "table" then
    error("leash.nvim runner: command spec env must be a table", 3)
  end
end

local function argv_for(spec)
  local argv = { spec.cmd }

  for _, arg in ipairs(spec.args or {}) do
    argv[#argv + 1] = arg
  end

  return argv
end

local function make_line_assembler(session, opts)
  local partial = {
    stdout = "",
    stderr = "",
  }

  local function dispatch_line(stream, line)
    schedule(function()
      emit(session, opts, {
        type = stream == "stderr" and "runner.stderr" or "runner.stdout",
        stream = stream,
        message = line,
      })

      if opts and opts.on_line then
        opts.on_line(stream, line)
      end
    end)
  end

  local function feed(stream, data)
    if not data or #data == 0 then
      return
    end

    if #data == 1 and data[1] == "" then
      return
    end

    partial[stream] = partial[stream] .. (data[1] or "")

    for index = 2, #data do
      dispatch_line(stream, partial[stream])
      partial[stream] = data[index] or ""
    end
  end

  local function flush()
    for _, stream in ipairs({ "stdout", "stderr" }) do
      if partial[stream] ~= "" then
        dispatch_line(stream, partial[stream])
        partial[stream] = ""
      end
    end
  end

  return {
    feed = feed,
    flush = flush,
  }
end

local function set_status_if_allowed(session, status)
  if session.status == status then
    return true
  end

  local ok, err = pcall(session_api.set_status, session, status)
  if not ok then
    return nil, err
  end

  return true
end

function M.start(session, spec, opts)
  opts = opts or {}
  validate_session(session)
  validate_spec(spec)

  local assembler = make_line_assembler(session, opts)
  local argv = argv_for(spec)

  local job_id = vim.fn.jobstart(argv, {
    cwd = spec.cwd,
    env = spec.env,
    pty = spec.pty == true,
    stdout_buffered = false,
    stderr_buffered = false,
    on_stdout = function(_, data)
      assembler.feed("stdout", data)
    end,
    on_stderr = function(_, data)
      assembler.feed("stderr", data)
    end,
    on_exit = function(_, code, event_type)
      assembler.flush()

      schedule(function()
        state.clear_job(session.id)
        session.job_id = nil

        if session.status ~= "aborted" then
          set_status_if_allowed(session, code == 0 and "review" or "failed")
        end

        session_api.save(session)

        emit(session, opts, {
          type = "runner.exit",
          code = code,
          event = event_type,
          status = session.status,
        })

        if opts.on_exit then
          opts.on_exit(code, event_type)
        end
      end)
    end,
  })

  if job_id <= 0 then
    local message = job_id == 0 and "invalid arguments" or "executable not found"

    set_status_if_allowed(session, "failed")
    session_api.save(session)

    emit(session, opts, {
      type = "runner.failed_to_start",
      level = "error",
      message = message,
      cmd = spec.cmd,
    })

    return nil, message
  end

  session.job_id = job_id
  state.set_job(session.id, job_id)
  set_status_if_allowed(session, "running")
  session_api.save(session)

  emit(session, opts, {
    type = "runner.started",
    job_id = job_id,
    cmd = spec.cmd,
    cwd = spec.cwd,
  })

  return job_id
end

function M.stop(session_or_id)
  local session = type(session_or_id) == "table" and session_or_id or state.get(session_or_id)
  if not session then
    return nil, "session not found"
  end

  local job_id = state.get_job(session.id) or session.job_id

  if job_id then
    vim.fn.jobstop(job_id)
  end

  state.clear_job(session.id)
  session.job_id = nil

  if session.status ~= "done" and session.status ~= "failed" and session.status ~= "aborted" then
    set_status_if_allowed(session, "aborted")
  end

  session_api.save(session)

  emit(session, nil, {
    type = "runner.aborted",
    job_id = job_id,
    status = session.status,
  })

  return job_id ~= nil
end

M._make_line_assembler = make_line_assembler

return M
