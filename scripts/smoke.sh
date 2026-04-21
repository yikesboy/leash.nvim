#!/usr/bin/env sh
set -eu

NVIM="${NVIM:-nvim}"
DEV_STATE="${DEV_STATE:-/tmp/leash-nvim-state}"
DEV_RUNTIME="${DEV_RUNTIME:-/tmp}"
DEV_LOG="${DEV_LOG:-/tmp/leash-nvim.log}"

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
DEV_INIT="${DEV_INIT:-$ROOT_DIR/dev/minimal.lua}"

cd "$ROOT_DIR"

XDG_STATE_HOME="${DEV_STATE}-session" \
XDG_RUNTIME_DIR="$DEV_RUNTIME" \
NVIM_LOG_FILE="$DEV_LOG" \
"$NVIM" --headless -u "$DEV_INIT" \
  -c 'lua local leash = require("leash"); leash.setup({ adapter = "noop", adapters = { noop = { command = "noop" } } }); local session = leash.start({ fargs = {"noop", "hello", "world"} }); local loaded = assert(leash._session.load(session.id)); assert(loaded.id == session.id); assert(loaded.prompt_history[1] == "hello world")' \
  -c 'qa'

XDG_STATE_HOME="${DEV_STATE}-redaction" \
XDG_RUNTIME_DIR="$DEV_RUNTIME" \
NVIM_LOG_FILE="$DEV_LOG" \
"$NVIM" --headless -u "$DEV_INIT" \
  -c 'lua local leash = require("leash"); local session = leash._session.create({ adapter = "codex", root = "/tmp/root" }); assert(leash._session.save(session)); assert(leash._session.append_event(session, { type = "test", env = { A = "B" }, raw = { token = "abc", value = 1 } })); local events = assert(leash._persist.read_events(session.id)); assert(events[1].env == "[REDACTED]"); assert(events[1].raw.token == "[REDACTED]"); assert(events[1].raw.value == 1)' \
  -c 'qa'

git diff --check

XDG_STATE_HOME="${DEV_STATE}-test" \
XDG_RUNTIME_DIR="$DEV_RUNTIME" \
NVIM_LOG_FILE="$DEV_LOG" \
"$NVIM" --headless -u "$ROOT_DIR/test/minimal_init.lua" \
  -c "luafile $ROOT_DIR/test/leash_spec.lua" \
  -c 'qa'
