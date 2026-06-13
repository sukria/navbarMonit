APP      := NavbarMonit.app
BIN_NAME := NavbarMonit
BIN_PATH := $(shell swift build -c release --show-bin-path)/$(BIN_NAME)

.PHONY: all build app run clean

all: app

## build: compile the release binary
build:
	swift build -c release

## app: assemble NavbarMonit.app (menu bar bundle)
app: build
	@echo "==> Assembling $(APP)…"
	@rm -rf $(APP)
	@mkdir -p $(APP)/Contents/MacOS
	@cp "$(BIN_PATH)" $(APP)/Contents/MacOS/$(BIN_NAME)
	@cp Resources/Info.plist $(APP)/Contents/Info.plist
	@codesign --force --deep --sign - $(APP) 2>/dev/null || true
	@echo "==> Done: $(CURDIR)/$(APP)"

## run: build the bundle and launch it
run: app
	open $(APP)

## clean: remove build artifacts
clean:
	swift package clean
	rm -rf .build $(APP)
