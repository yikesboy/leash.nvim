local M = {}

local config = require("leash.config")
local adapters = require("leash.adapters")
local job_runner = require("leash.runner.job")
local session = require("leash.session")
local state = require("leash.state")
local persist = require("leash.persist")

local function notify_pending(action)
  vim.notify(
    ("leash.nvim: %s. Agent execution and review UI are implemented by later work packages."):format(action),
    vim.log.levels.INFO
  )
end

local function join_args(args, start)
  local out = {}

  for index = start or 1, #args do
    out[#out + 1] = args[index]
  end

  return table.concat(out, " ")
end

local function parse_start_opts(opts)
  opts = opts or {}

  local cfg = config.get()
  local adapter = opts.adapter
  local prompt = opts.prompt
  local args = opts.fargs or opts.args

  if type(args) == "string" then
    prompt = prompt or args
  elseif type(args) == "table" and #args > 0 then
    if cfg.adapters[args[1]] then
      adapter = adapter or args[1]
      prompt = prompt or join_args(args, 2)
    else
      prompt = prompt or join_args(args, 1)
    end
  end

  adapter = adapter or cfg.adapter

  if not cfg.adapters[adapter] then
    error(('leash.nvim: unknown adapter "%s"'):format(adapter), 3)
  end

  return {
    adapter = adapter,
    prompt = prompt or "",
    range = opts.range,
    line1 = opts.line1,
    line2 = opts.line2,
  }
end

local function run_adapter(adapter, current_session, parsed)
  local adapter_config = config.get().adapters[parsed.adapter] or {}
  local spec = adapter.start({
    adapter = parsed.adapter,
    config = adapter_config,
    cwd = current_session.cwd,
    prompt = parsed.prompt,
    root = current_session.root,
    session = current_session,
  })

  if type(spec) ~= "table" then
    error(("leash.nvim: adapter %s did not return a command spec"):format(parsed.adapter), 3)
  end

  local job_id, err = job_runner.start(current_session, spec, {
    on_line = function(stream, line)
      local ok, events = pcall(adapter.parse_line, current_session, stream, line)
      if not ok then
        session.append_event(current_session, {
          type = "adapter.parse_error",
          adapter = parsed.adapter,
          level = "error",
          message = events,
          raw = line,
        })
        return
      end

      for _, event in ipairs(events or {}) do
        event.adapter = event.adapter or parsed.adapter
        session.append_event(current_session, event)
      end
    end,
    on_exit = function()
      if adapter.finalize then
        local ok, summary = pcall(adapter.finalize, current_session)
        if ok and summary then
          persist.save_summary(current_session.id, summary)
        elseif not ok then
          session.append_event(current_session, {
            type = "adapter.finalize_error",
            adapter = parsed.adapter,
            level = "error",
            message = summary,
          })
        end
      end
    end,
  })

  if not job_id then
    error("leash.nvim: failed to start adapter job: " .. err, 3)
  end

  return job_id
end

function M.setup(opts)
  return config.setup(opts)
end

function M.start(opts)
  local parsed = parse_start_opts(opts)
  local cwd = vim.fn.getcwd()
  local current_session = session.create({
    adapter = parsed.adapter,
    prompt = parsed.prompt,
    root = cwd,
    cwd = cwd,
  })

  state.register(current_session)

  local ok, err = session.save(current_session)
  if not ok then
    error("leash.nvim: failed to persist session: " .. err, 2)
  end

  local adapter = adapters.get(parsed.adapter)
  if adapter then
    run_adapter(adapter, current_session, parsed)
    vim.notify(("leash.nvim: started session %s with %s"):format(current_session.id, parsed.adapter), vim.log.levels.INFO)
  else
    notify_pending(
      ("created session %s with %s; adapter %s is not registered yet")
        :format(current_session.id, parsed.adapter, parsed.adapter)
    )
  end

  return current_session
end

function M.open()
  config.get()
  local current_session = state.current()
  notify_pending(current_session and ("open review for " .. current_session.id) or "open review")
end

function M.files()
  config.get()
  local current_session = state.current()
  notify_pending(current_session and ("focus changed files for " .. current_session.id) or "focus changed files")
end

function M.accept_file()
  config.get()
  notify_pending("accept file")
end

function M.reject_file()
  config.get()
  notify_pending("reject file")
end

function M.abort()
  config.get()
  local current_session = state.current()
  if current_session then
    job_runner.stop(current_session)
  end
  notify_pending(current_session and ("marked session " .. current_session.id .. " aborted") or "abort session")
end

function M.resume(session_id)
  config.get()
  local target_id = session_id

  if not target_id then
    local sessions = persist.list_sessions()
    target_id = sessions[1] and sessions[1].id or nil
  end

  if not target_id then
    error("leash.nvim: no persisted sessions found", 2)
  end

  local loaded, err = session.load(target_id)
  if not loaded then
    error("leash.nvim: failed to resume session: " .. err, 2)
  end

  state.register(loaded)
  notify_pending("loaded session " .. loaded.id)
  return loaded
end

function M.prompt(opts)
  local parsed = parse_start_opts(opts)
  local current_session = state.current()

  if current_session and parsed.prompt ~= "" then
    session.add_prompt(current_session, parsed.prompt)
    session.save(current_session)
  end

  notify_pending("prompt with selection context")
  return parsed
end

M._parse_start_opts = parse_start_opts
M._state = state
M._session = session
M._persist = persist
M._adapters = adapters
M._job_runner = job_runner

return M
