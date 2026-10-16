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

BUILD := .build
PLATFORM := Sources/Platform.swift Sources/main.swift
CORE := $(filter-out $(PLATFORM),$(wildcard Sources/*.swift))
SWIFTFLAGS := -O -swift-version 6 -warnings-as-errors

.PHONY: all build test check settings install uninstall stop status logs rotate-log restart clean help

all: test build

help:
	@echo "make build       compile $(BUILD)/$(BIN)"
	@echo "make test        compile and run the unit tests"
	@echo "make check       print what the program sees right now (needs the permission for your terminal)"
	@echo "make install     test, build, copy to PREFIX, load the login agent"
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

install: settings test build
	./$(BUILD)/$(BIN) --margin '$(MARGIN)' --version >/dev/null
	sed -e 's|@BIN@|$(PREFIX)/$(BIN)|' -e 's|@LABEL@|$(LABEL)|' -e 's|@LOG@|$(LOG)|' -e 's|@MARGIN@|$(MARGIN)|' \
		launchd/$(BIN).plist.in > $(BUILD)/agent.plist
	plutil -lint $(BUILD)/agent.plist
	install -d "$(PREFIX)" "$(dir $(AGENT))" "$(dir $(LOG))"
	-launchctl bootout $(DOMAIN)/$(LABEL) 2>/dev/null
	install -m 755 $(BUILD)/$(BIN) "$(PREFIX)/$(BIN)"
	install -m 644 $(BUILD)/agent.plist "$(AGENT)"
	@for try in $$(seq $(BOOTSTRAP_TRIES)); do \
		launchctl bootstrap $(DOMAIN) "$(AGENT)" 2>/dev/null && exit 0; \
		sleep 1; \
	done; \
	launchctl bootstrap $(DOMAIN) "$(AGENT)"
	@echo "Allow $(PREFIX)/$(BIN) under Privacy & Security > Device Control and Data Access."
	@echo "Then: make status"

uninstall: settings
	-launchctl bootout $(DOMAIN)/$(LABEL) 2>/dev/null
	rm -f "$(AGENT)" "$(PREFIX)/$(BIN)"

stop: settings
	launchctl bootout $(DOMAIN)/$(LABEL)

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
