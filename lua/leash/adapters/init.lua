local M = {}

local registry = {}
local registration_order = {}
local builtin_names = {
  codex = true,
  fake = true,
}

local required_methods = {
  "start",
  "parse_line",
}

local optional_methods = {
  "detect",
  "capabilities",
  "resume",
  "finalize",
}

local function validate(adapter)
  if type(adapter) ~= "table" then
    error("leash.nvim adapters: adapter must be a table", 3)
  end

  if type(adapter.name) ~= "string" or adapter.name == "" then
    error("leash.nvim adapters: adapter.name must be a non-empty string", 3)
  end

  for _, method in ipairs(required_methods) do
    if type(adapter[method]) ~= "function" then
      error(("leash.nvim adapters: adapter %s must implement %s()"):format(adapter.name, method), 3)
    end
  end

  for _, method in ipairs(optional_methods) do
    if adapter[method] ~= nil and type(adapter[method]) ~= "function" then
      error(("leash.nvim adapters: adapter %s field %s must be a function"):format(adapter.name, method), 3)
    end
  end
end

function M.register(adapter)
  validate(adapter)
  if not registry[adapter.name] then
    registration_order[#registration_order + 1] = adapter.name
  end
  registry[adapter.name] = adapter
  return adapter
end

function M.unregister(name)
  registry[name] = nil

  for index, registered_name in ipairs(registration_order) do
    if registered_name == name then
      table.remove(registration_order, index)
      break
    end
  end
end

function M.clear()
  registry = {}
  registration_order = {}
end

function M.get(name)
  if not registry[name] and builtin_names[name] then
    local ok, adapter = pcall(require, "leash.adapters." .. name)
    if ok and type(adapter) == "table" and adapter.name == name then
      M.register(adapter)
    end
  end

  return registry[name]
end

function M.require(name)
  local adapter = M.get(name)
  if not adapter then
    error(("leash.nvim adapters: adapter %q is not registered"):format(tostring(name)), 2)
  end

  return adapter
end

function M.names()
  local names = {}

  for name in pairs(registry) do
    names[#names + 1] = name
  end

  table.sort(names)
  return names
end

function M.list(opts)
  local out = {}
  local names = opts and opts.preserve_order and registration_order or M.names()

  for _, name in ipairs(names) do
    out[#out + 1] = registry[name]
  end

  return out
end

function M.capabilities(name)
  local adapter = M.require(name)

  if adapter.capabilities then
    local capabilities = adapter.capabilities()
    if type(capabilities) == "table" then
      return capabilities
    end
  end

  return {}
end

function M.detect(root)
  for _, adapter in ipairs(M.list({ preserve_order = true })) do
    if adapter.detect then
      local ok, detected = pcall(adapter.detect, root)
      if ok and detected then
        return adapter
      end
    end
  end

  return nil
end

return M
