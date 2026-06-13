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
	@printf '%s\n' \
	  '<?xml version="1.0" encoding="UTF-8"?>' \
	  '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
	  '<plist version="1.0">' \
	  '<dict>' \
	  '    <key>CFBundleName</key>               <string>NavbarMonit</string>' \
	  '    <key>CFBundleDisplayName</key>        <string>NavbarMonit</string>' \
	  '    <key>CFBundleIdentifier</key>         <string>com.sukria.navbarmonit</string>' \
	  '    <key>CFBundleVersion</key>            <string>1.0</string>' \
	  '    <key>CFBundleShortVersionString</key> <string>1.0</string>' \
	  '    <key>CFBundleExecutable</key>         <string>NavbarMonit</string>' \
	  '    <key>CFBundlePackageType</key>        <string>APPL</string>' \
	  '    <key>LSMinimumSystemVersion</key>     <string>13.0</string>' \
	  '    <key>LSUIElement</key>                <true/>' \
	  '</dict>' \
	  '</plist>' > $(APP)/Contents/Info.plist
	@codesign --force --deep --sign - $(APP) 2>/dev/null || true
	@echo "==> Done: $(CURDIR)/$(APP)"

## run: build the bundle and launch it
run: app
	open $(APP)

## clean: remove build artifacts
clean:
	swift package clean
	rm -rf .build $(APP)
