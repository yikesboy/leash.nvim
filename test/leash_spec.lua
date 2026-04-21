local leash = require("leash")
local adapters = require("leash.adapters")
local codex = require("leash.adapters.codex")
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

test("adapter detection follows registration order", function()
  local first = {
    name = "zeta",
    start = function() end,
    parse_line = function()
      return {}
    end,
    detect = function()
      return true
    end,
  }
  local second = {
    name = "alpha",
    start = function() end,
    parse_line = function()
      return {}
    end,
    detect = function()
      return true
    end,
  }

  adapters.clear()
  adapters.register(first)
  adapters.register(second)

  assert_eq(adapters.detect("/tmp").name, "zeta", "detection priority")
  assert_eq(adapters.list({ preserve_order = true })[1].name, "zeta", "preserved list order")
  assert_eq(table.concat(adapters.names(), ","), "alpha,zeta", "display names remain sorted")
end)

test("builtin adapter lazy loading ignores name mismatches", function()
  adapters.clear()

  local original = package.loaded["leash.adapters.fake"]
  package.loaded["leash.adapters.fake"] = {
    name = "wrong",
    start = function() end,
    parse_line = function()
      return {}
    end,
  }

  local ok, loaded = pcall(adapters.get, "fake")
  package.loaded["leash.adapters.fake"] = original
  adapters.clear()
  adapters.register(fake)

  assert_true(ok, "mismatched builtin load should not error")
  assert_eq(loaded, nil, "mismatched builtin is not registered")
end)

test("codex adapter builds start command", function()
  local session = session_api.create({ adapter = "codex", root = "/tmp/root", cwd = "/tmp/root" })
  local spec = codex.start({
    config = {
      command = "codex",
      sandbox = "workspace-write",
      approval_policy = "never",
      extra_args = { "--skip-git-repo-check" },
    },
    cwd = session.cwd,
    prompt = "implement feature",
    root = session.root,
    session = session,
  })

  assert_eq(spec.cmd, "codex", "codex command")
  assert_eq(spec.cwd, "/tmp/root", "codex cwd")
  assert_eq(table.concat(spec.args, " "), "--ask-for-approval never exec --json --color never --sandbox workspace-write --skip-git-repo-check implement feature", "codex args")
end)

test("codex adapter builds resume command", function()
  local session = session_api.create({
    adapter = "codex",
    root = "/tmp/root",
    cwd = "/tmp/root",
    vendor_session_id = "thread-123",
  })

  local spec = codex.resume(session, "continue work", {
    config = {
      command = "codex",
      sandbox = "read-only",
    },
  })

  assert_eq(table.concat(spec.args, " "), "--sandbox read-only exec resume --json thread-123 continue work", "resume args with id")

  session.vendor_session_id = nil
  local last = codex.resume(session, "continue work", {
    config = {
      command = "codex",
    },
  })

  assert_eq(table.concat(last.args, " "), "exec resume --json --last continue work", "resume args with --last")
end)

test("codex adapter parses structured events", function()
  local session = session_api.create({ adapter = "codex", root = "/tmp/root", cwd = "/tmp/root" })

  local started = codex.parse_line(session, "stdout", '{"type":"thread.started","thread_id":"thread-abc"}')
  assert_eq(session.vendor_session_id, "thread-abc", "codex vendor id")
  assert_eq(started[1].type, "session.started", "thread.started map")

  local item = codex.parse_line(session, "stdout", '{"type":"item.completed","item":{"type":"tool_call","text":"ran tool"}}')
  assert_eq(item[1].type, "agent.tool_call", "tool item map")
  assert_eq(item[1].message, "ran tool", "tool item message")

  local failed = codex.parse_line(session, "stdout", '{"type":"turn.failed","error":{"message":"bad"}}')
  assert_eq(failed[1].type, "session.failed", "turn.failed map")
  assert_eq(failed[1].message, "bad", "turn.failed message")

  local raw = codex.parse_line(session, "stdout", "not json")
  assert_eq(raw[1].type, "adapter.raw", "invalid JSON maps to raw event")

  local unknown = codex.parse_line(session, "stdout", '{"type":"new.event","value":1}')
  assert_eq(unknown[1].type, "adapter.raw", "unknown JSON event is preserved")
end)

test("codex adapter can be selected safely before worktree capture", function()
  leash._state.reset()
  adapters.clear()
  leash.setup({
    adapter = "codex",
    adapters = {
      codex = {
        command = "codex",
        sandbox = "workspace-write",
      },
    },
  })

  local root = tmpdir("leash-codex-safe")
  vim.cmd("cd " .. vim.fn.fnameescape(root))
  local session = leash.start({ fargs = { "codex", "do not run yet" } })

  assert_eq(session.adapter, "codex", "codex session adapter")
  assert_eq(session.status, "idle", "codex is deferred without worktree")
  assert_true(adapters.get("codex") ~= nil, "codex adapter autoloaded")
end)

test("non-table capabilities do not trigger isolation deferral", function()
  local odd = {
    name = "odd",
    capabilities = function()
      return true
    end,
    start = function(opts)
      return {
        cmd = vim.v.progpath,
        args = { "--headless", "-u", "NONE", "-i", "NONE", "-c", "qa" },
        cwd = opts.cwd,
      }
    end,
    parse_line = function()
      return {}
    end,
  }

  leash._state.reset()
  adapters.clear()
  adapters.register(odd)
  leash.setup({
    adapter = "odd",
    adapters = {
      odd = {
        command = vim.v.progpath,
      },
    },
    review = {
      use_worktree = true,
    },
  })

  local root = tmpdir("leash-odd-capabilities")
  vim.cmd("cd " .. vim.fn.fnameescape(root))
  local session = leash.start({ fargs = { "odd", "run" } })

  assert_true(vim.wait(1000, function()
    return session.status == "review"
  end), "non-table capabilities should not defer")
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

test("adapter summary persistence failures are emitted", function()
  local root = tmpdir("leash-summary-fail")
  local original_save_summary = leash._persist.save_summary
  local ok, err = pcall(function()
    reset_runtime()
    leash._persist.save_summary = function()
      return nil, "summary blocked"
    end

    vim.cmd("cd " .. vim.fn.fnameescape(root))
    local session = leash.start({ fargs = { "fake", "summary failure" } })

    assert_true(vim.wait(1000, function()
      return session.status == "review"
    end), "session should reach review")

    local events = assert(leash._persist.read_events(session.id))
    assert_true(event_seen(events, function(event)
      return event.type == "adapter.finalize_error" and event.message == "summary blocked"
    end), "summary save failure event persisted")
  end)
  leash._persist.save_summary = original_save_summary

  if not ok then
    error(err, 0)
  end
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

test("aborting idle session does not emit runner aborted event", function()
  local root = tmpdir("leash-idle-abort")

  reset_runtime()
  local session = session_api.create({ adapter = "fake", root = root, cwd = root })
  leash._state.register(session)
  assert_true(leash._session.save(session), "session persisted")

  local stopped = leash._job_runner.stop(session)
  assert_eq(stopped, false, "idle stop return value")
  assert_eq(session.status, "aborted", "idle session status")

  local events = assert(leash._persist.read_events(session.id))
  assert_true(not event_seen(events, function(event)
    return event.type == "runner.aborted"
  end), "idle stop should not emit runner.aborted")
end)

if failures > 0 then
  io.stderr:write(failures, " test(s) failed\n")
  vim.cmd("cquit")
end

io.stdout:write("all tests passed\n")
