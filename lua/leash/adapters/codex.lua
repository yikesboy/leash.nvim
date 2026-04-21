local M = {
  name = "codex",
}

local dangerous_args = {
  ["--dangerously-bypass-approvals-and-sandbox"] = true,
}

local function decode_json(line)
  local ok, decoded = pcall(vim.json.decode, line)
  if ok and type(decoded) == "table" then
    return decoded
  end

  return nil
end

local function event_type(payload)
  return payload.type or payload.event or payload.name
end

local function vendor_id(payload)
  return payload.session_id
    or payload.thread_id
    or payload.conversation_id
    or payload.id
    or (type(payload.thread) == "table" and (payload.thread.id or payload.thread.session_id))
end

local function message_from(payload)
  if type(payload.message) == "string" then
    return payload.message
  end

  if type(payload.text) == "string" then
    return payload.text
  end

  if type(payload.item) == "table" then
    return payload.item.text or payload.item.message or payload.item.content
  end

  if type(payload.error) == "string" then
    return payload.error
  end

  if type(payload.error) == "table" then
    return payload.error.message or payload.error.type
  end

  return nil
end

local function item_kind(payload)
  if type(payload.item) == "table" then
    return payload.item.type or payload.item.kind
  end

  return payload.item_type or payload.kind
end

local function raw_event(stream, line)
  return {
    type = "adapter.raw",
    stream = stream,
    message = line,
    raw = line,
  }
end

local function mapped_event(session, stream, payload)
  local typ = event_type(payload)

  if typ == "thread.started" then
    local id = vendor_id(payload)
    session.vendor_session_id = id or session.vendor_session_id

    return {
      type = "session.started",
      stream = stream,
      vendor_session_id = id,
      raw = payload,
    }
  end

  if typ == "turn.started" then
    return {
      type = "agent.turn_started",
      stream = stream,
      raw = payload,
    }
  end

  if typ == "turn.completed" then
    return {
      type = "session.completed",
      stream = stream,
      raw = payload,
    }
  end

  if typ == "turn.failed" then
    return {
      type = "session.failed",
      stream = stream,
      level = "error",
      message = message_from(payload),
      raw = payload,
    }
  end

  if typ == "error" then
    return {
      type = "session.failed",
      stream = stream,
      level = "error",
      message = message_from(payload),
      raw = payload,
    }
  end

  if type(typ) == "string" and typ:sub(1, 5) == "item." then
    local kind = item_kind(payload)
    local mapped = "agent.message"

    if kind and tostring(kind):find("tool", 1, true) then
      mapped = "agent.tool_call"
    elseif typ:find("tool", 1, true) then
      mapped = "agent.tool_call"
    end

    return {
      type = mapped,
      stream = stream,
      message = message_from(payload),
      item_type = kind,
      raw = payload,
    }
  end

  return {
    type = "adapter.raw",
    stream = stream,
    raw = payload,
  }
end

local function append_global_args(args, config, opts)
  opts = opts or {}

  if config.approval_policy then
    args[#args + 1] = "--ask-for-approval"
    args[#args + 1] = config.approval_policy
  end

  if opts.include_sandbox and config.sandbox then
    args[#args + 1] = "--sandbox"
    args[#args + 1] = config.sandbox
  end

  if config.model then
    args[#args + 1] = "--model"
    args[#args + 1] = config.model
  end

  if config.profile then
    args[#args + 1] = "--profile"
    args[#args + 1] = config.profile
  end
end

local function append_extra_args(args, config)
  for _, arg in ipairs(config.extra_args or {}) do
    if dangerous_args[arg] and not config.allow_unsafe_agent_options then
      error("leash.nvim codex adapter: unsafe Codex argument requires allow_unsafe_agent_options", 4)
    end

    args[#args + 1] = arg
  end
end

local function append_exec_args(args, config)
  args[#args + 1] = "--json"
  args[#args + 1] = "--color"
  args[#args + 1] = "never"

  if config.sandbox then
    args[#args + 1] = "--sandbox"
    args[#args + 1] = config.sandbox
  end

  if config.skip_git_repo_check then
    args[#args + 1] = "--skip-git-repo-check"
  end

  if config.output_schema then
    args[#args + 1] = "--output-schema"
    args[#args + 1] = config.output_schema
  end

  append_extra_args(args, config)
end

local function append_resume_args(args, config)
  args[#args + 1] = "--json"

  if config.skip_git_repo_check then
    args[#args + 1] = "--skip-git-repo-check"
  end

  append_extra_args(args, config)
end

local function command_for(config, command_args, cwd)
  return {
    cmd = config.command or "codex",
    args = command_args,
    cwd = cwd,
    env = config.env,
  }
end

function M.capabilities()
  return {
    structured_events = true,
    resume = true,
    requires_isolation = true,
  }
end

function M.detect()
  return vim.fn.executable("codex") == 1
end

function M.start(opts)
  local config = opts.config or {}
  local args = {}

  append_global_args(args, config)

  args[#args + 1] = "exec"
  append_exec_args(args, config)

  if opts.prompt and opts.prompt ~= "" then
    args[#args + 1] = opts.prompt
  end

  return command_for(config, args, opts.cwd)
end

function M.resume(session, prompt, ctx)
  local config = ctx and ctx.config or {}
  local args = {}

  append_global_args(args, config, { include_sandbox = true })

  args[#args + 1] = "exec"
  args[#args + 1] = "resume"
  append_resume_args(args, config)

  if session.vendor_session_id and session.vendor_session_id ~= "" then
    args[#args + 1] = session.vendor_session_id
  else
    args[#args + 1] = "--last"
  end

  if prompt and prompt ~= "" then
    args[#args + 1] = prompt
  end

  return command_for(config, args, session.cwd)
end

function M.parse_line(session, stream, line)
  local payload = decode_json(line)
  if not payload then
    return { raw_event(stream, line) }
  end

  return { mapped_event(session, stream, payload) }
end

function M.finalize(session)
  return {
    adapter = M.name,
    status = session.status,
    vendor_session_id = session.vendor_session_id,
  }
end

return M
