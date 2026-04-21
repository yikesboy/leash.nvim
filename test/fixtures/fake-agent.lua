local uv = vim.uv or vim.loop

local opts = {
  scenario = "success",
  session_id = "fake-thread",
  message = "editing files",
  writes = {},
  deletes = {},
  split_lines = false,
  sleep_ms = nil,
  exit_code = nil,
}

local function parse_args(argv)
  local index = 1

  while index <= #argv do
    local item = argv[index]

    if item == "--scenario" then
      opts.scenario = argv[index + 1] or opts.scenario
      index = index + 2
    elseif item == "--session-id" then
      opts.session_id = argv[index + 1] or opts.session_id
      index = index + 2
    elseif item == "--message" then
      opts.message = argv[index + 1] or opts.message
      index = index + 2
    elseif item == "--write" then
      opts.writes[#opts.writes + 1] = {
        path = argv[index + 1],
        text = argv[index + 2] or "",
      }
      index = index + 3
    elseif item == "--delete" then
      opts.deletes[#opts.deletes + 1] = argv[index + 1]
      index = index + 2
    elseif item == "--split-lines" then
      opts.split_lines = true
      index = index + 1
    elseif item == "--sleep-ms" then
      opts.sleep_ms = tonumber(argv[index + 1])
      index = index + 2
    elseif item == "--exit-code" then
      opts.exit_code = tonumber(argv[index + 1])
      index = index + 2
    else
      index = index + 1
    end
  end
end

local function encode(value)
  return vim.json.encode(value)
end

local function emit(value)
  local line = encode(value)

  if opts.split_lines and value.type == "thread.started" then
    local midpoint = math.floor(#line / 2)
    io.stdout:write(line:sub(1, midpoint))
    io.stdout:flush()
    uv.sleep(20)
    io.stdout:write(line:sub(midpoint + 1), "\n")
  else
    io.stdout:write(line, "\n")
  end

  io.stdout:flush()
end

local function write_file(path, text)
  local parent = vim.fn.fnamemodify(path, ":h")
  if parent and parent ~= "" and parent ~= "." then
    vim.fn.mkdir(parent, "p")
  end

  local handle = assert(io.open(path, "w"))
  handle:write(text)
  handle:close()
end

parse_args(_G.arg or {})

emit({ type = "thread.started", session_id = opts.session_id })
emit({ type = "turn.started" })
emit({ type = "item.message", message = opts.message })

for _, write in ipairs(opts.writes) do
  write_file(write.path, write.text)
  emit({ type = "file.write", path = write.path })
end

for _, path in ipairs(opts.deletes) do
  os.remove(path)
  emit({ type = "file.delete", path = path })
end

if opts.scenario == "sleep" then
  uv.sleep(opts.sleep_ms or 5000)
  emit({ type = "turn.completed" })
  os.exit(0)
end

if opts.scenario == "fail" then
  emit({ type = "turn.failed", message = "fake failure" })
  os.exit(opts.exit_code or 7)
end

emit({ type = "turn.completed" })
os.exit(opts.exit_code or 0)
