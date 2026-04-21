# leash.nvim

`leash.nvim` is a review-first Neovim plugin for coding-agent sessions.

The current implementation provides the plugin skeleton, configuration, command
registration, session state, and local persistence. Agent execution, worktree
capture, diff review, and accept/reject behavior are not implemented yet.

## Current Status

What works now:

- `require("leash").setup({})` loads and validates configuration.
- User commands are registered lazily by `plugin/leash.lua`.
- `:LeashStart [adapter] {prompt}` creates a persisted session.
- `:LeashResume [session_id]` loads a persisted session and makes it current.
- `:LeashResume` without an ID loads the most recently updated session.
- `:LeashAbort` marks the current session as `aborted` and persists that status.
- `:'<,'>LeashPrompt {prompt}` appends prompt text to the current session history.
- Session metadata is persisted under `stdpath("state")/leash`.
- Events can be appended to `events.jsonl`.
- File and hunk review decisions can be represented and saved.
- Secret-like keys such as `env`, `token`, `secret`, `authorization`, and
  `api_key` are redacted before persistence.

What is intentionally still pending:

- Running Codex or Claude.
- Creating isolated Git worktrees.
- Scanning changed files from a worktree.
- Opening the review UI.
- Showing side-by-side diffs.
- Applying accepted file or hunk changes.

## Local Review

The easiest way to review the current branch is the included minimal Neovim
config:

```sh
sh scripts/review.sh
```

This starts Neovim with `dev/minimal.lua`, prepends this checkout to
`runtimepath`, runs `require("leash").setup({})`, and opens a small dev buffer
with commands to try.

Inside that Neovim instance:

```vim
:LeashStart codex inspect the current file
:LeashResume
:LeashAbort
:LeashDevSmoke
```

These commands currently create, load, and update session state. They will show
notifications explaining that agent execution and review UI are implemented by
later packages.

Run headless validation:

```sh
sh scripts/smoke.sh
```

That checks session create/save/load, event redaction, and whitespace.

If `make` is installed, these wrappers are also available:

```sh
make review
make smoke
```

## lazy.nvim Install

For local development with lazy.nvim, add this plugin spec:

```lua
{
  dir = "/home/lukas/projects/leash.nvim",
  name = "leash.nvim",
  lazy = false,
  config = function()
    require("leash").setup({})
  end,
}
```

Then restart Neovim and run:

```vim
:LeashStart codex inspect this plugin
```

For a remote branch install after pushing, use the normal lazy.nvim repository
form and pin the feature branch:

```lua
{
  "OWNER/leash.nvim",
  branch = "feature/session-state-and-persistence",
  lazy = false,
  config = function()
    require("leash").setup({})
  end,
}
```

Replace `OWNER/leash.nvim` with the actual repository path.

## Troubleshooting

If `require("leash")` says `module 'leash' not found`, your Neovim process does
not have this checkout on `runtimepath`. The `make review` flow avoids that. To
check manually:

```vim
:set runtimepath?
:lua print(vim.fn.filereadable("/home/lukas/projects/leash.nvim/lua/leash/init.lua"))
```

The first command should include `/home/lukas/projects/leash.nvim`. The second
command should print `1`.

## Inspect Persisted Sessions

In Neovim, check the state directory:

```vim
:lua print(vim.fn.stdpath("state") .. "/leash")
```

You should see session data under:

```text
stdpath("state")/leash/sessions/{session_id}/
  session.json
  decisions.json
  events.jsonl
```

## Headless Review Commands

These commands exercise the current implementation without using your normal
Neovim state directory.

Check command registration and lazy loading:

```sh
env XDG_STATE_HOME=/tmp/leash-review-state XDG_RUNTIME_DIR=/tmp NVIM_LOG_FILE=/tmp/leash-review.log \
  nvim --headless -u NONE -i NONE --cmd 'set rtp^=.' \
  -c 'runtime plugin/leash.lua' \
  -c 'lua assert(package.loaded["leash"] == nil)' \
  -c 'lua local commands = vim.api.nvim_get_commands({}); for _, name in ipairs({"LeashStart", "LeashOpen", "LeashFiles", "LeashAcceptFile", "LeashRejectFile", "LeashAbort", "LeashResume", "LeashPrompt"}) do assert(commands[name], name) end' \
  -c 'qa'
```

Check session create, save, and load:

```sh
env XDG_STATE_HOME=/tmp/leash-review-state XDG_RUNTIME_DIR=/tmp NVIM_LOG_FILE=/tmp/leash-review.log \
  nvim --headless -u NONE -i NONE --cmd 'set rtp^=.' \
  -c 'runtime plugin/leash.lua' \
  -c 'lua local leash = require("leash"); leash.setup({}); local s = leash.start({ fargs = {"codex", "hello", "world"} }); local loaded = leash._session.load(s.id); assert(loaded.id == s.id); assert(loaded.prompt_history[1] == "hello world")' \
  -c 'qa'
```

Check event redaction:

```sh
env XDG_STATE_HOME=/tmp/leash-review-state XDG_RUNTIME_DIR=/tmp NVIM_LOG_FILE=/tmp/leash-review.log \
  nvim --headless -u NONE -i NONE --cmd 'set rtp^=.' \
  -c 'lua local leash = require("leash"); leash.setup({}); local s = leash._session.create({ adapter = "codex", root = "/tmp/root" }); assert(leash._session.save(s)); assert(leash._session.append_event(s, { type = "test", env = { A = "B" }, raw = { token = "abc", value = 1 } })); local events = assert(leash._persist.read_events(s.id)); assert(events[1].env == "[REDACTED]"); assert(events[1].raw.token == "[REDACTED]"); assert(events[1].raw.value == 1)' \
  -c 'qa'
```

Check whitespace:

```sh
git diff --check
```

## Configuration

Minimal setup:

```lua
require("leash").setup()
```

Example setup:

```lua
require("leash").setup({
  adapter = "codex",
  ui = {
    file_list_width = 32,
    log_height = 12,
  },
  persistence = {
    enabled = true,
    cleanup_worktrees = "manual",
  },
})
```

Unsafe agent options are rejected by default when passed through adapter
configuration. Users must explicitly opt in with:

```lua
require("leash").setup({
  safety = {
    allow_unsafe_agent_options = true,
  },
})
```

## Development Notes

Feature work should happen on `feature/<workpackage-name>` branches. The current
session-state work is on:

```text
feature/session-state-and-persistence
```
