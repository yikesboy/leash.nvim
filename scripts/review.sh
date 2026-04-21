#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

NVIM="${NVIM:-nvim}"
DEV_STATE="${DEV_STATE:-/tmp/leash-nvim-state}"
DEV_RUNTIME="${DEV_RUNTIME:-/tmp}"
DEV_LOG="${DEV_LOG:-/tmp/leash-nvim.log}"

cd "$ROOT_DIR"

XDG_STATE_HOME="$DEV_STATE" \
XDG_RUNTIME_DIR="$DEV_RUNTIME" \
NVIM_LOG_FILE="$DEV_LOG" \
"$NVIM" -u dev/minimal.lua
