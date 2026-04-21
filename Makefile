NVIM ?= nvim
DEV_INIT := dev/minimal.lua
DEV_STATE ?= /tmp/leash-nvim-state
DEV_RUNTIME ?= /tmp
DEV_LOG ?= /tmp/leash-nvim.log

.PHONY: review smoke smoke-session smoke-redaction check

review:
	DEV_STATE="$(DEV_STATE)" DEV_RUNTIME="$(DEV_RUNTIME)" DEV_LOG="$(DEV_LOG)" NVIM="$(NVIM)" \
		sh scripts/review.sh

smoke:
	sh scripts/smoke.sh

smoke-session:
	XDG_STATE_HOME="$(DEV_STATE)-session" XDG_RUNTIME_DIR="$(DEV_RUNTIME)" NVIM_LOG_FILE="$(DEV_LOG)" \
		$(NVIM) --headless -u "$(DEV_INIT)" \
		-c 'lua local leash = require("leash"); local session = leash.start({ fargs = {"codex", "hello", "world"} }); local loaded = assert(leash._session.load(session.id)); assert(loaded.id == session.id); assert(loaded.prompt_history[1] == "hello world")' \
		-c 'qa'

smoke-redaction:
	XDG_STATE_HOME="$(DEV_STATE)-redaction" XDG_RUNTIME_DIR="$(DEV_RUNTIME)" NVIM_LOG_FILE="$(DEV_LOG)" \
		$(NVIM) --headless -u "$(DEV_INIT)" \
		-c 'lua local leash = require("leash"); local session = leash._session.create({ adapter = "codex", root = "/tmp/root" }); assert(leash._session.save(session)); assert(leash._session.append_event(session, { type = "test", env = { A = "B" }, raw = { token = "abc", value = 1 } })); local events = assert(leash._persist.read_events(session.id)); assert(events[1].env == "[REDACTED]"); assert(events[1].raw.token == "[REDACTED]"); assert(events[1].raw.value == 1)' \
		-c 'qa'

check:
	git diff --check
