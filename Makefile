BIN := menubar-guard
LABEL ?= local.menubar-guard
PREFIX ?= $(HOME)/local/bin
MARGIN ?= 8

# zsh passes `PREFIX=~/bin` through without expanding the tilde.
override PREFIX := $(patsubst ~/%,$(HOME)/%,$(PREFIX))

AGENT = $(HOME)/Library/LaunchAgents/$(LABEL).plist
LOG = $(HOME)/Library/Logs/$(BIN).log
DOMAIN = gui/$$(id -u)
BOOTSTRAP_TRIES := 5
UNLOAD = @if launchctl print $(DOMAIN)/$(LABEL) >/dev/null 2>&1; then launchctl bootout $(DOMAIN)/$(LABEL); fi

BUILD := .build
PLATFORM := Sources/Platform.swift Sources/main.swift
CORE := $(filter-out $(PLATFORM),$(wildcard Sources/*.swift))
SWIFTFLAGS := -O -swift-version 6 -warnings-as-errors

.PHONY: all build test check settings agent install uninstall stop status logs rotate-log restart clean help

all: test build

help:
	@echo "make build       compile $(BUILD)/$(BIN)"
	@echo "make test        compile and run the unit tests"
	@echo "make check       print what the program sees right now (needs the permission for your terminal)"
	@echo "make agent       build and lint the login agent file in $(BUILD)/ without installing it"
	@echo "make install     test, build, copy to PREFIX, load the login agent, wait for the permission"
	@echo "make uninstall   unload the login agent and remove the installed files"
	@echo "make stop        unload the login agent until the next install or login"
	@echo "make status      show the login agent state and recent log lines"
	@echo "make logs        follow the log"
	@echo "make rotate-log  move the log to $(BIN).log.1 and restart the agent"
	@echo "make restart     restart the login agent"
	@echo "make clean       remove $(BUILD)/"
	@echo ""
	@echo "Settings: PREFIX=$(PREFIX) LABEL=$(LABEL) MARGIN=$(MARGIN)"
	@echo "Pass the same PREFIX and LABEL to every target that you passed to install."

build: $(BUILD)/$(BIN)

$(BUILD)/$(BIN): $(CORE) $(PLATFORM) Makefile | $(BUILD)
	swiftc $(SWIFTFLAGS) -o $@ $(CORE) $(PLATFORM)

$(BUILD)/tests: $(CORE) Tests/main.swift Makefile | $(BUILD)
	swiftc $(SWIFTFLAGS) -o $@ $(CORE) Tests/main.swift

$(BUILD):
	mkdir -p $@

test: $(BUILD)/tests
	./$(BUILD)/tests

check: $(BUILD)/$(BIN)
	./$(BUILD)/$(BIN) --check --margin '$(MARGIN)'

# Values end up in shell commands, a sed replacement and XML, so only plain
# path characters are allowed.
settings:
	@for value in '$(PREFIX)' '$(HOME)'; do \
		printf '%s\n' "$$value" | LC_ALL=C grep -Eq '^/[A-Za-z0-9._/+-]+$$' \
			|| { echo "error: '$$value' must be an absolute path of letters, digits and . _ / + -" >&2; exit 2; }; \
	done
	@printf '%s\n' '$(LABEL)' | LC_ALL=C grep -Eq '^[A-Za-z0-9._-]+$$' \
		|| { echo "error: LABEL '$(LABEL)' may contain only letters, digits and . _ -" >&2; exit 2; }

agent: settings build
	./$(BUILD)/$(BIN) --margin '$(MARGIN)' --version >/dev/null
	sed -e 's|@BIN@|$(PREFIX)/$(BIN)|' -e 's|@LABEL@|$(LABEL)|' -e 's|@LOG@|$(LOG)|' -e 's|@MARGIN@|$(MARGIN)|' \
		launchd/$(BIN).plist.in > $(BUILD)/agent.plist
	plutil -lint $(BUILD)/agent.plist

install: settings test agent
	install -d "$(PREFIX)" "$(dir $(AGENT))" "$(dir $(LOG))"
	$(UNLOAD)
	install -m 755 $(BUILD)/$(BIN) "$(PREFIX)/$(BIN)"
	install -m 644 $(BUILD)/agent.plist "$(AGENT)"
	@first_line=$$(( $$(cat "$(LOG)" 2>/dev/null | wc -l) + 1 )); \
	is_loaded=; \
	for try in $$(seq $(BOOTSTRAP_TRIES)); do \
		if launchctl bootstrap $(DOMAIN) "$(AGENT)" 2>/dev/null; then is_loaded=1; break; fi; \
		sleep 1; \
	done; \
	[ -n "$$is_loaded" ] || launchctl bootstrap $(DOMAIN) "$(AGENT)" || exit 1; \
	sh scripts/await-permission.sh "$(DOMAIN)/$(LABEL)" "$(LOG)" "$(PREFIX)/$(BIN)" "$$first_line"

uninstall: settings
	$(UNLOAD)
	rm -f "$(AGENT)" "$(PREFIX)/$(BIN)"

stop: settings
	$(UNLOAD)

status: settings
	@if launchctl print $(DOMAIN)/$(LABEL) >/dev/null 2>&1; then \
		launchctl print $(DOMAIN)/$(LABEL) | grep -E "^$$(printf '\t')(state|pid|last exit code|runs) =" || true; \
	else \
		echo "$(LABEL) is not loaded"; \
	fi
	@tail -n 5 "$(LOG)" 2>/dev/null || true

logs: settings
	tail -n 50 -f "$(LOG)"

rotate-log: settings
	-mv -f "$(LOG)" "$(LOG).1"
	launchctl kickstart -k $(DOMAIN)/$(LABEL)

restart: settings
	launchctl kickstart -k $(DOMAIN)/$(LABEL)

clean:
	rm -rf $(BUILD)
