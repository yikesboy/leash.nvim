local source = debug.getinfo(1, "S").source
local init_path = source:sub(1, 1) == "@" and source:sub(2) or source
local root = vim.fn.fnamemodify(init_path, ":p:h:h")

vim.opt.runtimepath:prepend(root)
vim.opt.packpath:prepend(root)

local leash = require("leash")
local adapters = require("leash.adapters")

leash.setup({
  adapter = "fake",
  adapters = {
    fake = {
      command = vim.v.progpath,
    },
  },
})

adapters.register(require("leash.adapters.fake"))
