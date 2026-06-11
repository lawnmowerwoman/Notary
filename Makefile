# ----------------------------
# Project
# ----------------------------
APP_NAME        := notary
APP_BUNDLE_NAME := Notary.app
APP_EXECUTABLE  := Notary
PKG_ID          := de.twocent.notary
APP_BUNDLE_ID   := de.twocent.notary.app
SERVICE_ID      := de.twocent.notary.service
VERSION         ?= 0.1.0
-include .version/version.mk
BUILD_LABEL     = $(shell sed -n 's/^BUILD_LABEL := //p' .version/version.mk 2>/dev/null)

# Install locations on target Macs
APP_INSTALL_DIR     := /Applications
SERVICE_INSTALL_DIR := /usr/local/libexec

# ----------------------------
# Signing identities (set these)
# ----------------------------
# Example:
# DEV_ID_APP      := Developer ID Application: Firma GmbH (TEAMID12345)
# DEV_ID_INSTALL  := Developer ID Installer: Firma GmbH (TEAMID12345)
DEV_ID_APP      ?= Developer ID Application: Stefanie Ramroth (KP5T66DWT2)
DEV_ID_INSTALL  ?= Developer ID Installer: Stefanie Ramroth (KP5T66DWT2)

# Team ID for runtime self-check (optional, but recommended)
TEAM_ID         ?= KP5T66DWT2

# ----------------------------
# Notarization (optional)
# ----------------------------
# Use Apple "notarytool" keychain profile:
# xcrun notarytool store-credentials "AC_PROFILE" --apple-id ... --team-id ... --password ...
NOTARY_PROFILE  ?= notary-profile

# ----------------------------
# Paths
# ----------------------------
BUILD_DIR       := .build
RELEASE_DIR     := $(BUILD_DIR)/release
BIN_PATH        := $(RELEASE_DIR)/$(APP_NAME)
SERVICE_BUILD_BIN := $(RELEASE_DIR)/notary
APP_BUILD_BIN     := $(RELEASE_DIR)/NotaryApp

OUT_DIR         := dist
ROOT_DIR        := $(OUT_DIR)/root
PKG_SCRIPTS_DIR := $(OUT_DIR)/pkg-scripts
APP_BUNDLE_DIR  := $(ROOT_DIR)$(APP_INSTALL_DIR)/$(APP_BUNDLE_NAME)
APP_CONTENTS_DIR:= $(APP_BUNDLE_DIR)/Contents
APP_MACOS_DIR   := $(APP_CONTENTS_DIR)/MacOS
APP_RES_DIR     := $(APP_CONTENTS_DIR)/Resources
APP_INFO_PLIST  := $(APP_CONTENTS_DIR)/Info.plist
APP_BIN         := $(APP_MACOS_DIR)/$(APP_EXECUTABLE)
SERVICE_BIN     := $(ROOT_DIR)$(SERVICE_INSTALL_DIR)/$(APP_NAME)
APP_ICON_SOURCE := Dokumentation/Notary-App-Icon-Concept.svg
CONFIG_SCHEMA_SOURCE := Config-Schema-1.2.json
CONFIG_SCHEMA_NAME := Config-Schema-1.2.json
APP_ICON_PREVIEW_DIR := $(OUT_DIR)/icon-preview
APP_ICON_PREVIEW_PNG := $(APP_ICON_PREVIEW_DIR)/Notary-App-Icon-Concept.svg.png
APP_ICONSET_DIR := $(OUT_DIR)/AppIcon.iconset
APP_ICON_BUILD_ICNS := $(OUT_DIR)/AppIcon.icns
APP_ICON_ICNS   := $(APP_RES_DIR)/AppIcon.icns
APP_SCHEMA_JSON := $(APP_RES_DIR)/$(CONFIG_SCHEMA_NAME)

PKG_BASENAME    = $(APP_NAME)-$(VERSION)$(if $(BUILD_LABEL),-$(BUILD_LABEL),)
PKG_UNSIGNED    = $(OUT_DIR)/$(PKG_BASENAME)-unsigned.pkg
PKG_SIGNED      = $(OUT_DIR)/$(PKG_BASENAME).pkg
SCHEMA_JSON := Config-Schema-1.2.json
GEN_SWIFT   := Sources/NotaryRunner/GeneratedKeys.swift

VERSION_SWIFT   := Sources/NotaryRunner/Version.generated.swift
VERSION_DIR     := .version


# ----------------------------
# Defaults
# ----------------------------
.PHONY: all clean build gen-version prepare-root gen-app-icon sign-bin pkg pkg-sign pkg-verify notarize staple release help

all: release

help:
	@echo "Targets:"
	@echo "  make build            - SwiftPM release build"
	@echo "  make sign-bin         - codesign app bundle and service binary"
	@echo "  make pkg              - build unsigned pkg with app + service payload"
	@echo "  make pkg-sign         - sign pkg (requires DEV_ID_INSTALL)"
	@echo "  make pkg-verify       - verify pkg signature"
	@echo "  make notarize         - notarize signed pkg (requires NOTARY_PROFILE)"
	@echo "  make staple           - staple notarization ticket to signed pkg"
	@echo "  make release          - build -> sign bin -> pkg -> pkg-sign -> (optional) notarize+staple"
	@echo ""
	@echo "Variables (examples):"
	@echo "  DEV_ID_APP='Developer ID Application: ... (TEAMID)'"
	@echo "  DEV_ID_INSTALL='Developer ID Installer: ... (TEAMID)'"
	@echo "  TEAM_ID='ABCDE12345'"

clean:
	rm -rf $(OUT_DIR)
	rm -rf $(BUILD_DIR)

gen-version:
	@mkdir -p "$(VERSION_DIR)"
	@./Tools/gen_version.sh "$(VERSION_DIR)" "$(VERSION_SWIFT)"

build: gen-version
	swift build -c release

gen-keys:
	./Tools/schema_gen.swift "$(SCHEMA_JSON)" "$(GEN_SWIFT)"

# Generate a proper macOS app icon from the design SVG reference.
gen-app-icon:
	rm -rf "$(APP_ICON_PREVIEW_DIR)" "$(APP_ICONSET_DIR)"
	mkdir -p "$(APP_ICON_PREVIEW_DIR)" "$(APP_ICONSET_DIR)"
	qlmanage -t -s 1024 -o "$(APP_ICON_PREVIEW_DIR)" "$(APP_ICON_SOURCE)" >/dev/null 2>&1
	sips -z 16 16 "$(APP_ICON_PREVIEW_PNG)" --out "$(APP_ICONSET_DIR)/icon_16x16.png" >/dev/null
	sips -z 32 32 "$(APP_ICON_PREVIEW_PNG)" --out "$(APP_ICONSET_DIR)/icon_16x16@2x.png" >/dev/null
	sips -z 32 32 "$(APP_ICON_PREVIEW_PNG)" --out "$(APP_ICONSET_DIR)/icon_32x32.png" >/dev/null
	sips -z 64 64 "$(APP_ICON_PREVIEW_PNG)" --out "$(APP_ICONSET_DIR)/icon_32x32@2x.png" >/dev/null
	sips -z 128 128 "$(APP_ICON_PREVIEW_PNG)" --out "$(APP_ICONSET_DIR)/icon_128x128.png" >/dev/null
	sips -z 256 256 "$(APP_ICON_PREVIEW_PNG)" --out "$(APP_ICONSET_DIR)/icon_128x128@2x.png" >/dev/null
	sips -z 256 256 "$(APP_ICON_PREVIEW_PNG)" --out "$(APP_ICONSET_DIR)/icon_256x256.png" >/dev/null
	sips -z 512 512 "$(APP_ICON_PREVIEW_PNG)" --out "$(APP_ICONSET_DIR)/icon_256x256@2x.png" >/dev/null
	sips -z 512 512 "$(APP_ICON_PREVIEW_PNG)" --out "$(APP_ICONSET_DIR)/icon_512x512.png" >/dev/null
	cp "$(APP_ICON_PREVIEW_PNG)" "$(APP_ICONSET_DIR)/icon_512x512@2x.png"
	iconutil -c icns "$(APP_ICONSET_DIR)" -o "$(APP_ICON_BUILD_ICNS)"

# Create payload root with visible app bundle plus stable service binary.
prepare-root: build gen-app-icon
	rm -rf $(ROOT_DIR)
	mkdir -p $(APP_MACOS_DIR)
	mkdir -p $(APP_RES_DIR)
	mkdir -p $(ROOT_DIR)$(SERVICE_INSTALL_DIR)
	cp -f $(APP_BUILD_BIN) $(APP_BIN)
	cp -f $(SERVICE_BUILD_BIN) $(SERVICE_BIN)
	cp -f $(APP_ICON_BUILD_ICNS) $(APP_ICON_ICNS)
	cp -f $(CONFIG_SCHEMA_SOURCE) $(APP_SCHEMA_JSON)
	chmod 755 $(APP_BIN)
	chmod 755 $(SERVICE_BIN)
	@printf '%s\n' \
	  '<?xml version="1.0" encoding="UTF-8"?>' \
	  '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
	  '<plist version="1.0">' \
	  '<dict>' \
	  '  <key>CFBundleDevelopmentRegion</key>' \
	  '  <string>en</string>' \
	  '  <key>CFBundleDisplayName</key>' \
	  '  <string>Notary</string>' \
	  '  <key>CFBundleExecutable</key>' \
	  '  <string>$(APP_EXECUTABLE)</string>' \
	  '  <key>CFBundleIconFile</key>' \
	  '  <string>AppIcon.icns</string>' \
	  '  <key>CFBundleIdentifier</key>' \
	  '  <string>$(APP_BUNDLE_ID)</string>' \
	  '  <key>CFBundleInfoDictionaryVersion</key>' \
	  '  <string>6.0</string>' \
	  '  <key>CFBundleName</key>' \
	  '  <string>Notary</string>' \
	  '  <key>CFBundlePackageType</key>' \
	  '  <string>APPL</string>' \
	  '  <key>CFBundleShortVersionString</key>' \
	  '  <string>$(VERSION)</string>' \
	  '  <key>CFBundleVersion</key>' \
	  '  <string>$(if $(BUILD_LABEL),$(BUILD_LABEL),$(VERSION))</string>' \
	  '  <key>LSMinimumSystemVersion</key>' \
	  '  <string>12.0</string>' \
	  '  <key>NSPrincipalClass</key>' \
	  '  <string>NSApplication</string>' \
	  '  <key>NSHumanReadableCopyright</key>' \
	  '  <string>Copyright © 2024-2026 Apfelwerk GmbH &amp; Co. KG and TwoCent Labs, Stefanie Ramroth.</string>' \
	  '  <key>NSHighResolutionCapable</key>' \
	  '  <true/>' \
	  '</dict>' \
	  '</plist>' > "$(APP_INFO_PLIST)"
	# Ownership is set by installer at install time; pkgbuild handles it.

prepare-pkg-scripts:
	rm -rf "$(PKG_SCRIPTS_DIR)"
	mkdir -p "$(PKG_SCRIPTS_DIR)"
	@printf '%s\n' \
	  '#!/bin/zsh --no-rcs' \
	  'set -u' \
	  'LABEL="de.twocent.notary"' \
	  'DAEMON="/Library/LaunchDaemons/$${LABEL}.plist"' \
	  'if [[ -f "$${DAEMON}" ]]; then' \
	  '  /bin/launchctl bootout system "$${DAEMON}" >/dev/null 2>&1 || true' \
	  'fi' \
	  'exit 0' > "$(PKG_SCRIPTS_DIR)/preinstall"
	@printf '%s\n' \
	  '#!/bin/zsh --no-rcs' \
	  'set -u' \
	  'LABEL="de.twocent.notary"' \
	  'DAEMON="/Library/LaunchDaemons/$${LABEL}.plist"' \
	  'if [[ -f "$${DAEMON}" ]]; then' \
	  '  /bin/launchctl bootstrap system "$${DAEMON}" >/dev/null 2>&1 || true' \
	  'fi' \
	  'exit 0' > "$(PKG_SCRIPTS_DIR)/postinstall"
	chmod 755 "$(PKG_SCRIPTS_DIR)/preinstall" "$(PKG_SCRIPTS_DIR)/postinstall"

# Sign the service binary and GUI app bundle.
sign-bin: prepare-root
ifeq ($(strip $(DEV_ID_APP)),)
	$(error DEV_ID_APP is not set. Example: DEV_ID_APP='Developer ID Application: ... (TEAMID)')
endif
	codesign --force --options runtime --timestamp \
	  --identifier "$(SERVICE_ID)" \
	  --sign "$(DEV_ID_APP)" \
	  "$(SERVICE_BIN)"
	codesign --force --options runtime --timestamp \
	  --sign "$(DEV_ID_APP)" \
	  "$(APP_BUNDLE_DIR)"
	# Verify signatures
	codesign --verify --strict --verbose=2 "$(SERVICE_BIN)"
	codesign --verify --strict --verbose=2 "$(APP_BUNDLE_DIR)"

# Build an (unsigned) component pkg from payload
pkg: sign-bin prepare-pkg-scripts
	mkdir -p $(OUT_DIR)
	pkgbuild \
	  --root "$(ROOT_DIR)" \
	  --scripts "$(PKG_SCRIPTS_DIR)" \
	  --identifier "$(PKG_ID)" \
	  --version "$(VERSION)" \
	  --install-location "/" \
	  "$(PKG_UNSIGNED)"

# Sign the pkg (Jamf-friendly)
pkg-sign: pkg
ifeq ($(strip $(DEV_ID_INSTALL)),)
	$(error DEV_ID_INSTALL is not set. Example: DEV_ID_INSTALL='Developer ID Installer: ... (TEAMID)')
endif
	productsign --sign "$(DEV_ID_INSTALL)" "$(PKG_UNSIGNED)" "$(PKG_SIGNED)"
	rm -f "$(PKG_UNSIGNED)"

pkg-verify:
	@echo "=== pkgutil --check-signature ==="
	pkgutil --check-signature "$(PKG_SIGNED)" || true
	@echo ""
	@echo "=== spctl --assess ==="
	spctl --assess --type install --verbose "$(PKG_SIGNED)" || true

# Notarize signed pkg
notarize: pkg-sign
	xcrun notarytool submit "$(PKG_SIGNED)" --keychain-profile "$(NOTARY_PROFILE)" --wait

# Staple ticket to pkg
staple: notarize
	xcrun stapler staple "$(PKG_SIGNED)"
	xcrun stapler validate "$(PKG_SIGNED)"

# Full release (without forcing notarize/staple; you can run make staple explicitly)
release: pkg-sign pkg-verify
	@echo "Built: $(PKG_SIGNED)"
	@echo "Tip: run 'make staple' if you want notarization stapled."
