if vim.g.loaded_leash_nvim == 1 then
  return
end

vim.g.loaded_leash_nvim = 1

vim.api.nvim_create_user_command("LeashStart", function(opts)
  require("leash").start(opts)
end, {
  nargs = "*",
  desc = "Start a leash.nvim agent session",
})

vim.api.nvim_create_user_command("LeashOpen", function()
  require("leash").open()
end, {
  desc = "Open the current leash.nvim review",
})

vim.api.nvim_create_user_command("LeashFiles", function()
  require("leash").files()
end, {
  desc = "Focus the leash.nvim changed-files list",
})

vim.api.nvim_create_user_command("LeashAcceptFile", function()
  require("leash").accept_file()
end, {
  desc = "Accept the current leash.nvim file",
})

vim.api.nvim_create_user_command("LeashRejectFile", function()
  require("leash").reject_file()
end, {
  desc = "Reject the current leash.nvim file",
})

vim.api.nvim_create_user_command("LeashAbort", function()
  require("leash").abort()
end, {
  desc = "Abort the current leash.nvim agent session",
})

vim.api.nvim_create_user_command("LeashResume", function(opts)
  local session_id = opts.args ~= "" and opts.args or nil
  require("leash").resume(session_id)
end, {
  nargs = "?",
  desc = "Resume a persisted leash.nvim session",
})

vim.api.nvim_create_user_command("LeashPrompt", function(opts)
  require("leash").prompt(opts)
end, {
  nargs = "*",
  range = true,
  desc = "Prompt using the current visual selection as context",
})
