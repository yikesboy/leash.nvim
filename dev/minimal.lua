local source = debug.getinfo(1, "S").source
local init_path = source:sub(1, 1) == "@" and source:sub(2) or source
local plugin_root = vim.fn.fnamemodify(init_path, ":p:h:h")

vim.opt.runtimepath:prepend(plugin_root)
vim.opt.packpath:prepend(plugin_root)

vim.g.mapleader = " "

require("leash").setup({
  adapter = "fake",
  adapters = {
    fake = {
      command = vim.v.progpath,
    },
  },
})

require("leash.adapters").register(require("leash.adapters.fake"))

vim.api.nvim_create_user_command("LeashDevSmoke", function()
  local leash = require("leash")
  local session = leash.start({
    fargs = { "fake", "dev", "smoke" },
  })

  vim.notify("leash.nvim dev smoke created session " .. session.id, vim.log.levels.INFO)
end, {
  desc = "Create a persisted leash.nvim smoke-test session",
})

vim.api.nvim_create_autocmd("VimEnter", {
  once = true,
  callback = function()
    local lines = {
      "# leash.nvim dev",
      "",
      "Commands to try:",
      "",
      "  :LeashStart fake inspect this plugin",
      "  :LeashStart codex inspect this plugin",
      "  :LeashResume",
      "  :LeashAbort",
      "  :LeashDevSmoke",
      "",
      "State path:",
      "",
      "  " .. vim.fn.stdpath("state") .. "/leash",
    }

    local buf = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_buf_set_name(buf, "leash.nvim-dev")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].filetype = "markdown"
    vim.bo[buf].bufhidden = "wipe"
    vim.api.nvim_set_current_buf(buf)
  end,
})
