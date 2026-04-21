local M = {}

local defaults = {
  adapter = "codex",
  adapters = {
    codex = {
      command = "codex",
      extra_args = {},
      sandbox = "workspace-write",
      approval_policy = nil,
    },
    claude = {
      command = "claude",
      extra_args = {},
      permission_mode = nil,
      allowed_tools = nil,
    },
  },
  review = {
    use_worktree = true,
    accept_hunks = false,
    auto_open = true,
    diffopt = "filler,context:3,linematch:60,inline:word",
  },
  limits = {
    max_file_size = 1024 * 1024,
    max_file_lines = 20000,
  },
  ui = {
    file_list_width = 32,
    log_height = 12,
    keymaps = true,
  },
  persistence = {
    enabled = true,
    cleanup_worktrees = "manual",
  },
  safety = {
    allow_unsafe_agent_options = false,
  },
}

local current

local function fail(message)
  error("leash.nvim config: " .. message, 3)
end

local function expect_type(value, expected, path)
  if type(value) ~= expected then
    fail(("%s must be %s, got %s"):format(path, expected, type(value)))
  end
end

local function expect_optional_type(value, expected, path)
  if value ~= nil then
    expect_type(value, expected, path)
  end
end

local function expect_string_list(value, path)
  expect_type(value, "table", path)

  for index, item in ipairs(value) do
    if type(item) ~= "string" then
      fail(("%s[%d] must be string, got %s"):format(path, index, type(item)))
    end
  end
end

local function expect_positive_number(value, path)
  expect_type(value, "number", path)

  if value <= 0 then
    fail(("%s must be greater than 0"):format(path))
  end
end

local unsafe_args = {
  "--dangerously-bypass-approvals-and-sandbox",
  "--dangerously-skip-permissions",
  "--permission-mode=bypassPermissions",
  "bypassPermissions",
}

local function validate_unsafe_args(cfg)
  if cfg.safety.allow_unsafe_agent_options then
    return
  end

  for adapter_name, adapter in pairs(cfg.adapters) do
    local extra_args = adapter.extra_args or {}

    if adapter.permission_mode == "bypassPermissions" then
      fail(
        ("adapters.%s.permission_mode uses unsafe mode %q; set safety.allow_unsafe_agent_options=true to opt in")
          :format(adapter_name, adapter.permission_mode)
      )
    end

    for _, arg in ipairs(extra_args) do
      for _, unsafe in ipairs(unsafe_args) do
        if arg == unsafe then
          fail(
            ("adapters.%s.extra_args contains unsafe option %q; set safety.allow_unsafe_agent_options=true to opt in")
              :format(adapter_name, arg)
          )
        end
      end
    end
  end
end

local function validate_adapter(adapter_name, adapter)
  expect_type(adapter, "table", "adapters." .. adapter_name)
  expect_type(adapter.command, "string", "adapters." .. adapter_name .. ".command")

  if adapter.command == "" then
    fail("adapters." .. adapter_name .. ".command must not be empty")
  end

  expect_optional_type(adapter.extra_args, "table", "adapters." .. adapter_name .. ".extra_args")
  if adapter.extra_args then
    expect_string_list(adapter.extra_args, "adapters." .. adapter_name .. ".extra_args")
  end
end

local function validate(cfg)
  expect_type(cfg, "table", "config")
  expect_type(cfg.adapter, "string", "adapter")
  expect_type(cfg.adapters, "table", "adapters")

  for adapter_name, adapter in pairs(cfg.adapters) do
    if type(adapter_name) ~= "string" then
      fail("adapter names must be strings")
    end
    validate_adapter(adapter_name, adapter)
  end

  if not cfg.adapters[cfg.adapter] then
    fail(('adapter "%s" has no matching adapters.%s config'):format(cfg.adapter, cfg.adapter))
  end

  expect_type(cfg.review, "table", "review")
  expect_type(cfg.review.use_worktree, "boolean", "review.use_worktree")
  expect_type(cfg.review.accept_hunks, "boolean", "review.accept_hunks")
  expect_type(cfg.review.auto_open, "boolean", "review.auto_open")
  expect_type(cfg.review.diffopt, "string", "review.diffopt")

  expect_type(cfg.limits, "table", "limits")
  expect_positive_number(cfg.limits.max_file_size, "limits.max_file_size")
  expect_positive_number(cfg.limits.max_file_lines, "limits.max_file_lines")

  expect_type(cfg.ui, "table", "ui")
  expect_positive_number(cfg.ui.file_list_width, "ui.file_list_width")
  expect_positive_number(cfg.ui.log_height, "ui.log_height")
  expect_type(cfg.ui.keymaps, "boolean", "ui.keymaps")

  expect_type(cfg.persistence, "table", "persistence")
  expect_type(cfg.persistence.enabled, "boolean", "persistence.enabled")
  expect_type(cfg.persistence.cleanup_worktrees, "string", "persistence.cleanup_worktrees")

  local cleanup_modes = {
    manual = true,
    never = true,
    on_done = true,
  }

  if not cleanup_modes[cfg.persistence.cleanup_worktrees] then
    fail('persistence.cleanup_worktrees must be one of "manual", "never", or "on_done"')
  end

  expect_type(cfg.safety, "table", "safety")
  expect_type(cfg.safety.allow_unsafe_agent_options, "boolean", "safety.allow_unsafe_agent_options")

  validate_unsafe_args(cfg)
end

function M.defaults()
  return vim.deepcopy(defaults)
end

function M.setup(opts)
  expect_optional_type(opts, "table", "setup opts")

  local cfg = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  validate(cfg)
  current = cfg

  return current
end

function M.get()
  if not current then
    return M.setup({})
  end

  return current
end

return M
