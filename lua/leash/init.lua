local M = {}

local config = require("leash.config")

local function notify_pending(action)
  vim.notify(
    ("leash.nvim: %s is not implemented yet; this command is registered for the current work package."):format(action),
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

function M.setup(opts)
  return config.setup(opts)
end

function M.start(opts)
  local parsed = parse_start_opts(opts)
  notify_pending(("start session with %s"):format(parsed.adapter))
  return parsed
end

function M.open()
  config.get()
  notify_pending("open review")
end

function M.files()
  config.get()
  notify_pending("focus changed files")
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
  notify_pending("abort session")
end

function M.resume(session_id)
  config.get()
  notify_pending(session_id and ("resume session " .. session_id) or "resume latest session")
  return session_id
end

function M.prompt(opts)
  local parsed = parse_start_opts(opts)
  notify_pending("prompt with selection context")
  return parsed
end

M._parse_start_opts = parse_start_opts

return M
