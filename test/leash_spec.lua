local leash = require("leash")
local adapters = require("leash.adapters")
local fake = require("leash.adapters.fake")
local session_api = require("leash.session")

local failures = 0

local function inspect(value)
  return vim.inspect(value)
end

local function assert_eq(actual, expected, context)
  if actual ~= expected then
    error(("%s\nexpected: %s\nactual: %s"):format(context or "assertion failed", inspect(expected), inspect(actual)), 2)
  end
end

local function assert_true(value, context)
  if not value then
    error(context or "expected truthy value", 2)
  end
end

local function test(name, fn)
  io.stdout:write("test: ", name, "\n")

  local ok, err = pcall(fn)
  if ok then
    io.stdout:write("ok:   ", name, "\n")
  else
    failures = failures + 1
    io.stderr:write("fail: ", name, "\n", err, "\n")
  end
end

local function tmpdir(name)
  local path = vim.fn.tempname() .. "-" .. name
  vim.fn.mkdir(path, "p")
  return path
end

local function write_file(path, text)
  local parent = vim.fn.fnamemodify(path, ":h")
  vim.fn.mkdir(parent, "p")

  local handle = assert(io.open(path, "w"))
  handle:write(text)
  handle:close()
end

local function read_file(path)
  local handle = assert(io.open(path, "r"))
  local text = handle:read("*a")
  handle:close()
  return text
end

local function reset_runtime(config)
  leash._state.reset()
  adapters.clear()
  adapters.register(fake)
  leash.setup(vim.tbl_deep_extend("force", {
    adapter = "fake",
    adapters = {
      fake = {
        command = vim.v.progpath,
      },
    },
  }, config or {}))
end

local function event_seen(events, predicate)
  for _, event in ipairs(events) do
    if predicate(event) then
      return true
    end
  end

  return false
end

test("fake adapter parses structured events", function()
  local session = session_api.create({ adapter = "fake", root = "/tmp" })
  local events = fake.parse_line(session, "stdout", '{"type":"thread.started","session_id":"fake-thread"}')

  assert_eq(session.vendor_session_id, "fake-thread", "vendor session id")
  assert_eq(events[1].type, "session.started", "mapped event type")
  assert_eq(events[1].vendor_session_id, "fake-thread", "mapped vendor session id")

  local raw = fake.parse_line(session, "stdout", "not json")
  assert_eq(raw[1].type, "adapter.raw", "invalid JSON maps to raw event")
end)

test("successful fake run mutates files and persists events", function()
  local root = tmpdir("leash-success")
  write_file(root .. "/existing.txt", "before")
  write_file(root .. "/delete-me.txt", "delete")

  reset_runtime({
    adapters = {
      fake = {
        command = vim.v.progpath,
        actions = {
          write = {
            { "existing.txt", "after" },
            { "created.txt", "new" },
          },
          delete = {
            "delete-me.txt",
          },
        },
      },
    },
  })

  vim.cmd("cd " .. vim.fn.fnameescape(root))
  local session = leash.start({ fargs = { "fake", "change files" } })

  assert_true(vim.wait(1000, function()
    return session.status == "review"
  end), "session should reach review")

  assert_eq(read_file(root .. "/existing.txt"), "after", "modified file")
  assert_eq(read_file(root .. "/created.txt"), "new", "created file")
  assert_eq(vim.fn.filereadable(root .. "/delete-me.txt"), 0, "deleted file")

  local events = assert(leash._persist.read_events(session.id))
  assert_true(event_seen(events, function(event)
    return event.type == "session.started" and event.vendor_session_id == "fake-thread"
  end), "session.started event persisted")
  assert_true(event_seen(events, function(event)
    return event.type == "fake.file_write" and event.path == "existing.txt"
  end), "file write event persisted")
  assert_true(event_seen(events, function(event)
    return event.type == "fake.file_delete" and event.path == "delete-me.txt"
  end), "file delete event persisted")
  assert_true(event_seen(events, function(event)
    return event.type == "runner.exit" and event.code == 0
  end), "runner exit event persisted")
end)

test("failed fake run marks session failed", function()
  local root = tmpdir("leash-fail")

  reset_runtime({
    adapters = {
      fake = {
        command = vim.v.progpath,
        scenario = "fail",
        exit_code = 9,
      },
    },
  })

  vim.cmd("cd " .. vim.fn.fnameescape(root))
  local session = leash.start({ fargs = { "fake", "fail" } })

  assert_true(vim.wait(1000, function()
    return session.status == "failed"
  end), "session should fail")

  local loaded = assert(leash._session.load(session.id))
  assert_eq(loaded.status, "failed", "persisted failed status")

  local events = assert(leash._persist.read_events(session.id))
  assert_true(event_seen(events, function(event)
    return event.type == "runner.exit" and event.code == 9
  end), "failed exit code persisted")
  assert_true(event_seen(events, function(event)
    return event.type == "session.failed"
  end), "adapter failure event persisted")
end)

test("split JSON line is reassembled", function()
  local root = tmpdir("leash-split")

  reset_runtime({
    adapters = {
      fake = {
        command = vim.v.progpath,
        split_lines = true,
      },
    },
  })

  vim.cmd("cd " .. vim.fn.fnameescape(root))
  local session = leash.start({ fargs = { "fake", "split" } })

  assert_true(vim.wait(1000, function()
    return session.status == "review"
  end), "session should reach review")

  local events = assert(leash._persist.read_events(session.id))
  assert_true(event_seen(events, function(event)
    return event.type == "session.started" and event.vendor_session_id == "fake-thread"
  end), "split event should be parsed after reassembly")
end)

test("abort stops fake run", function()
  local root = tmpdir("leash-abort")

  reset_runtime({
    adapters = {
      fake = {
        command = vim.v.progpath,
        scenario = "sleep",
        sleep_ms = 5000,
      },
    },
  })

  vim.cmd("cd " .. vim.fn.fnameescape(root))
  local session = leash.start({ fargs = { "fake", "sleep" } })

  assert_true(vim.wait(1000, function()
    return session.status == "running"
  end), "session should start running")

  leash.abort()

  assert_true(vim.wait(1000, function()
    return session.status == "aborted"
  end), "session should abort")

  local loaded = assert(leash._session.load(session.id))
  assert_eq(loaded.status, "aborted", "persisted aborted status")
end)

if failures > 0 then
  io.stderr:write(failures, " test(s) failed\n")
  vim.cmd("cquit")
end

io.stdout:write("all tests passed\n")
