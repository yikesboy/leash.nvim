local M = {}

local registry = {}
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
  registry[adapter.name] = adapter
  return adapter
end

function M.unregister(name)
  registry[name] = nil
end

function M.clear()
  registry = {}
end

function M.get(name)
  if not registry[name] and builtin_names[name] then
    local ok, adapter = pcall(require, "leash.adapters." .. name)
    if ok and type(adapter) == "table" then
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

function M.list()
  local out = {}

  for _, name in ipairs(M.names()) do
    out[#out + 1] = registry[name]
  end

  return out
end

function M.capabilities(name)
  local adapter = M.require(name)

  if adapter.capabilities then
    return adapter.capabilities() or {}
  end

  return {}
end

function M.detect(root)
  for _, adapter in ipairs(M.list()) do
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
