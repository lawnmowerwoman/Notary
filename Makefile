# ----------------------------
# Project
# ----------------------------
APP_NAME        := notary
APP_BUNDLE_NAME := Notary.app
APP_EXECUTABLE  := Notary
PKG_ID          := de.twocent.notary
APP_BUNDLE_ID   := de.twocent.notary.app
SERVICE_ID      := de.twocent.notary.service
STATUS_ID       := de.twocent.notary.status
-include .version/version.mk
VERSION_FROM_FILES = $(shell major=$$(cat .version/major_index 2>/dev/null || echo 1); minor=$$(cat .version/minor_letter 2>/dev/null || echo A); patch=$$(cat .version/patch 2>/dev/null || echo 0); minor_num=$$(printf '%s\n' "$$minor" | awk '{ print index("ABCDEFGHIJKLMNOPQRSTUVWXYZ", $$0) - 1 }'); if [ "$$minor_num" -lt 0 ]; then minor_num=0; fi; if [ "$$patch" = "0" ]; then printf '%s.%s\n' "$$((major + 1))" "$$minor_num"; else printf '%s.%s.%s\n' "$$((major + 1))" "$$minor_num" "$$patch"; fi)
BUILD_LABEL_FROM_FILES = $(shell major=$$(cat .version/major_index 2>/dev/null || echo 1); minor=$$(cat .version/minor_letter 2>/dev/null || echo A); build=$$(cat .version/build_number 2>/dev/null || true); channel=$$(cat .version/channel 2>/dev/null || true); if [ -n "$$build" ]; then printf '%s%s%s%s\n' "$$major" "$$minor" "$$build" "$$channel"; fi)
VERSION         ?= $(VERSION_FROM_FILES)
BUILD_LABEL     = $(or $(BUILD_LABEL_FROM_FILES),$(shell sed -n 's/^BUILD_LABEL := //p' .version/version.mk 2>/dev/null))

# Install locations on target Macs
APP_INSTALL_DIR     := /Applications
SERVICE_INSTALL_DIR := /usr/local/libexec
LAUNCH_AGENT_DIR    := /Library/LaunchAgents

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
# Transport implementation
# ----------------------------
# Public builds use the safe no-network dummy. Confidential builds must pass an
# explicit local Ministry package path and fail fast if it is missing.
TRANSPORT_IMPLEMENTATION ?= public
CONFIDENTIAL_TRANSPORT_PATH ?=
MINISTRY_CONFIDENTIAL_TRANSPORT_PATH := $(CURDIR)/Sources.local/NotaryConfidentialTransport
MINISTRY_APP_TOKEN_GENERATOR_PATH := $(CURDIR)/Sources.local/AppTokenGenerator
SWIFT_BUILD_ENV := NOTARY_TRANSPORT_IMPLEMENTATION="$(TRANSPORT_IMPLEMENTATION)" NOTARY_CONFIDENTIAL_TRANSPORT_PATH="$(CONFIDENTIAL_TRANSPORT_PATH)"

# ----------------------------
# Paths
# ----------------------------
BUILD_DIR       := .build
RELEASE_DIR     := $(BUILD_DIR)/release
BIN_PATH        := $(RELEASE_DIR)/$(APP_NAME)
SERVICE_BUILD_BIN := $(RELEASE_DIR)/notary
APP_BUILD_BIN     := $(RELEASE_DIR)/NotaryApp
STATUS_BUILD_BIN  := $(RELEASE_DIR)/notarystatus

OUT_DIR         := dist
ROOT_DIR        := $(OUT_DIR)/root
PKG_ROOT_DIR    := $(OUT_DIR)/pkg-root
PKG_SCRIPTS_DIR := $(OUT_DIR)/pkg-scripts
APP_BUNDLE_DIR  := $(ROOT_DIR)$(APP_INSTALL_DIR)/$(APP_BUNDLE_NAME)
APP_CONTENTS_DIR:= $(APP_BUNDLE_DIR)/Contents
APP_MACOS_DIR   := $(APP_CONTENTS_DIR)/MacOS
APP_RES_DIR     := $(APP_CONTENTS_DIR)/Resources
APP_INFO_PLIST  := $(APP_CONTENTS_DIR)/Info.plist
APP_BIN         := $(APP_MACOS_DIR)/$(APP_EXECUTABLE)
SERVICE_BIN     := $(ROOT_DIR)$(SERVICE_INSTALL_DIR)/$(APP_NAME)
STATUS_BIN      := $(APP_MACOS_DIR)/notarystatus
STATUS_AGENT    := $(ROOT_DIR)$(LAUNCH_AGENT_DIR)/$(STATUS_ID).plist
APP_ICON_SOURCE := Dokumentation/Notary-App-Icon-Concept.svg
CONFIG_SCHEMA_SOURCE := Config-Schema-1.2.json
CONFIG_SCHEMA_NAME := Config-Schema-1.2.json
APP_ICON_PREVIEW_DIR := $(OUT_DIR)/icon-preview
APP_ICON_PREVIEW_PNG := $(APP_ICON_PREVIEW_DIR)/Notary-App-Icon-Concept.svg.png
APP_ICONSET_DIR := $(OUT_DIR)/AppIcon.iconset
APP_ICON_BUILD_ICNS := $(OUT_DIR)/AppIcon.icns
APP_ICON_ICNS   := $(APP_RES_DIR)/AppIcon.icns
APP_SCHEMA_JSON := $(APP_RES_DIR)/$(CONFIG_SCHEMA_NAME)
COMPONENT_PLIST := $(OUT_DIR)/components.plist

PKG_BASENAME    = $(APP_NAME)-$(VERSION)$(if $(BUILD_LABEL),-$(BUILD_LABEL),)
PKG_UNSIGNED    = $(OUT_DIR)/$(PKG_BASENAME)-unsigned.pkg
PKG_SIGNED      = $(OUT_DIR)/$(PKG_BASENAME).pkg
SCHEMA_JSON := Config-Schema-1.2.json
GEN_SWIFT   := Sources/NotaryRunner/GeneratedKeys.swift
APP_TOKEN_PUBLIC_KEYS_SWIFT := Sources/AppTokenKit/PublicKeyRegistry.generated.swift

VERSION_SWIFT   := Sources/NotaryRunner/Version.generated.swift
VERSION_DIR     := .version


# ----------------------------
# Defaults
# ----------------------------
.PHONY: all clean build gen-version gen-app-token-public-keys check-confidential-release check-app-token-generator app-token-generator prepare-root prepare-payload-root gen-app-icon prepare-component-plist sign-bin pkg pkg-sign pkg-verify notarize staple release release-public release-internal release-confidential help

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
	@echo "  make release-confidential - build signed internal package with confidential Transporter"
	@echo "  make app-token-generator - build local confidential App Token Generator.app"
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

build: gen-version gen-app-token-public-keys
	$(SWIFT_BUILD_ENV) swift build -c release

gen-keys:
	./Tools/schema_gen.swift "$(SCHEMA_JSON)" "$(GEN_SWIFT)"

gen-app-token-public-keys:
	./Tools/gen_app_token_public_keys.swift "$(APP_TOKEN_PUBLIC_KEYS_SWIFT)"

check-confidential-release:
	@test -d "$(MINISTRY_CONFIDENTIAL_TRANSPORT_PATH)" || (echo "Missing confidential Transporter: $(MINISTRY_CONFIDENTIAL_TRANSPORT_PATH)" >&2; exit 2)
	@test -f "$(MINISTRY_CONFIDENTIAL_TRANSPORT_PATH)/Package.swift" || (echo "Missing confidential Transporter package manifest." >&2; exit 2)
	@test -f "$(MINISTRY_CONFIDENTIAL_TRANSPORT_PATH)/Sources/NotaryTransportImplementation/TransportImplementation.swift" || (echo "Missing confidential Transporter implementation source." >&2; exit 2)

check-app-token-generator:
	@test -d "$(MINISTRY_APP_TOKEN_GENERATOR_PATH)" || (echo "Missing local App Token Generator sources: $(MINISTRY_APP_TOKEN_GENERATOR_PATH)" >&2; exit 2)
	@test -f "$(MINISTRY_APP_TOKEN_GENERATOR_PATH)/App/main.swift" || (echo "Missing App Token Generator GUI source." >&2; exit 2)
	@test -f "$(MINISTRY_APP_TOKEN_GENERATOR_PATH)/CLI/main.swift" || (echo "Missing App Token Generator CLI source." >&2; exit 2)
	@test -f "$(MINISTRY_APP_TOKEN_GENERATOR_PATH)/Tools/build_app_token_generator_app.sh" || (echo "Missing App Token Generator bundle build script." >&2; exit 2)
	@test -d "$(MINISTRY_APP_TOKEN_GENERATOR_PATH)/Assets/AppIcon.appiconset" || (echo "Missing App Token Generator AppIcon assets." >&2; exit 2)

app-token-generator: check-app-token-generator
	"$(MINISTRY_APP_TOKEN_GENERATOR_PATH)/Tools/build_app_token_generator_app.sh"

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
	mkdir -p $(ROOT_DIR)$(LAUNCH_AGENT_DIR)
	cp -f $(APP_BUILD_BIN) $(APP_BIN)
	cp -f $(SERVICE_BUILD_BIN) $(SERVICE_BIN)
	cp -f $(STATUS_BUILD_BIN) $(STATUS_BIN)
	cp -f $(APP_ICON_BUILD_ICNS) $(APP_ICON_ICNS)
	cp -f $(CONFIG_SCHEMA_SOURCE) $(APP_SCHEMA_JSON)
	chmod 755 $(APP_BIN)
	chmod 755 $(SERVICE_BIN)
	chmod 755 $(STATUS_BIN)
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
	  '  <key>CFBundleURLTypes</key>' \
	  '  <array>' \
	  '    <dict>' \
	  '      <key>CFBundleURLName</key>' \
	  '      <string>de.twocent.notary.url</string>' \
	  '      <key>CFBundleURLSchemes</key>' \
	  '      <array>' \
	  '        <string>notary</string>' \
	  '      </array>' \
	  '    </dict>' \
	  '  </array>' \
	  '</dict>' \
	  '</plist>' > "$(APP_INFO_PLIST)"
	@printf '%s\n' \
	  '<?xml version="1.0" encoding="UTF-8"?>' \
	  '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
	  '<plist version="1.0">' \
	  '<dict>' \
	  '  <key>Label</key>' \
	  '  <string>$(STATUS_ID)</string>' \
	  '  <key>ProgramArguments</key>' \
	  '  <array>' \
	  '    <string>$(APP_INSTALL_DIR)/$(APP_BUNDLE_NAME)/Contents/MacOS/notarystatus</string>' \
	  '  </array>' \
	  '  <key>RunAtLoad</key>' \
	  '  <true/>' \
	  '  <key>LimitLoadToSessionType</key>' \
	  '  <string>Aqua</string>' \
	  '</dict>' \
	  '</plist>' > "$(STATUS_AGENT)"
	# Ownership is set by installer at install time; pkgbuild handles it.

prepare-pkg-scripts:
	rm -rf "$(PKG_SCRIPTS_DIR)"
	mkdir -p "$(PKG_SCRIPTS_DIR)"
	@printf '%s\n' \
	  '#!/bin/zsh --no-rcs' \
	  'set -u' \
	  'LABEL="de.twocent.notary"' \
	  'DAEMON="/Library/LaunchDaemons/$${LABEL}.plist"' \
	  'STATUS_AGENT="/Library/LaunchAgents/de.twocent.notary.status.plist"' \
	  'console_uid() {' \
	  '  local user' \
	  '  user="$$(/usr/bin/stat -f %Su /dev/console 2>/dev/null || true)"' \
	  '  [[ -z "$${user}" || "$${user}" == "root" || "$${user}" == "loginwindow" ]] && return 1' \
	  '  /usr/bin/id -u "$${user}" 2>/dev/null' \
	  '}' \
	  'if [[ -f "$${DAEMON}" ]]; then' \
	  '  /bin/launchctl bootout system "$${DAEMON}" >/dev/null 2>&1 || true' \
	  'fi' \
	  'uid="$$(console_uid || true)"' \
	  'if [[ -n "$${uid}" ]]; then' \
	  '  /bin/launchctl bootout "gui/$${uid}" "$${STATUS_AGENT}" >/dev/null 2>&1 || true' \
	  'fi' \
	  'exit 0' > "$(PKG_SCRIPTS_DIR)/preinstall"
	@printf '%s\n' \
	  '#!/bin/zsh --no-rcs' \
	  'set -u' \
	  'LABEL="de.twocent.notary"' \
	  'DAEMON="/Library/LaunchDaemons/$${LABEL}.plist"' \
	  'STATUS_AGENT="/Library/LaunchAgents/de.twocent.notary.status.plist"' \
	  'console_uid() {' \
	  '  local user' \
	  '  user="$$(/usr/bin/stat -f %Su /dev/console 2>/dev/null || true)"' \
	  '  [[ -z "$${user}" || "$${user}" == "root" || "$${user}" == "loginwindow" ]] && return 1' \
	  '  /usr/bin/id -u "$${user}" 2>/dev/null' \
	  '}' \
	  'if [[ -f "$${DAEMON}" ]]; then' \
	  '  /bin/launchctl bootstrap system "$${DAEMON}" >/dev/null 2>&1 || true' \
	  'fi' \
	  'uid="$$(console_uid || true)"' \
	  'if [[ -n "$${uid}" && -f "$${STATUS_AGENT}" ]]; then' \
	  '  /bin/launchctl enable "gui/$${uid}/de.twocent.notary.status" >/dev/null 2>&1 || true' \
	  '  /bin/launchctl bootout "gui/$${uid}" "$${STATUS_AGENT}" >/dev/null 2>&1 || true' \
	  '  /bin/launchctl bootstrap "gui/$${uid}" "$${STATUS_AGENT}" >/dev/null 2>&1 || true' \
	  '  /bin/launchctl kickstart -k "gui/$${uid}/de.twocent.notary.status" >/dev/null 2>&1 || true' \
	  'fi' \
	  'exit 0' > "$(PKG_SCRIPTS_DIR)/postinstall"
	chmod 755 "$(PKG_SCRIPTS_DIR)/preinstall" "$(PKG_SCRIPTS_DIR)/postinstall"

# Sign the service binary and GUI app bundle.
sign-bin: prepare-root
ifeq ($(strip $(DEV_ID_APP)),)
	$(error DEV_ID_APP is not set. Example: DEV_ID_APP='Developer ID Application: ... (TEAMID)')
endif
	@if [[ "$(TRANSPORT_IMPLEMENTATION)" == "confidential" ]]; then \
	  echo "CONFIDENTIAL RELEASE BUILD"; \
	  echo "Transport implementation: confidential"; \
	  echo "Public keys embedded: $$(grep -c '": Data' "$(APP_TOKEN_PUBLIC_KEYS_SWIFT)" 2>/dev/null || echo 0)"; \
	fi
	codesign --force --options runtime --timestamp \
	  --identifier "$(SERVICE_ID)" \
	  --sign "$(DEV_ID_APP)" \
	  "$(SERVICE_BIN)"
	codesign --force --options runtime --timestamp \
	  --identifier "$(STATUS_ID)" \
	  --sign "$(DEV_ID_APP)" \
	  "$(STATUS_BIN)"
	codesign --force --options runtime --timestamp \
	  --sign "$(DEV_ID_APP)" \
	  "$(APP_BUNDLE_DIR)"
	# Verify signatures
	codesign --verify --strict --verbose=2 "$(SERVICE_BIN)"
	codesign --verify --strict --verbose=2 "$(STATUS_BIN)"
	codesign --verify --strict --verbose=2 "$(APP_BUNDLE_DIR)"

prepare-payload-root: sign-bin
	rm -rf "$(PKG_ROOT_DIR)"
	mkdir -p "$(PKG_ROOT_DIR)"
	ditto --norsrc --noextattr --noqtn --noacl "$(ROOT_DIR)" "$(PKG_ROOT_DIR)"
	find "$(PKG_ROOT_DIR)" -name '._*' -delete
	xattr -cr "$(PKG_ROOT_DIR)"

prepare-component-plist: prepare-payload-root
	pkgbuild --analyze --root "$(PKG_ROOT_DIR)" "$(COMPONENT_PLIST)"
	/usr/libexec/PlistBuddy -c "Set :0:BundleIsRelocatable false" "$(COMPONENT_PLIST)"
	/usr/libexec/PlistBuddy -c "Set :0:BundleHasStrictIdentifier true" "$(COMPONENT_PLIST)"
	/usr/libexec/PlistBuddy -c "Set :0:BundleOverwriteAction upgrade" "$(COMPONENT_PLIST)"

# Build an (unsigned) component pkg from payload
pkg: prepare-payload-root prepare-pkg-scripts prepare-component-plist
	mkdir -p $(OUT_DIR)
	find "$(PKG_ROOT_DIR)" -name '._*' -delete
	xattr -cr "$(PKG_ROOT_DIR)"
	COPYFILE_DISABLE=1 pkgbuild \
	  --root "$(PKG_ROOT_DIR)" \
	  --component-plist "$(COMPONENT_PLIST)" \
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
release:
	@$(MAKE) release-public TRANSPORT_IMPLEMENTATION=public CONFIDENTIAL_TRANSPORT_PATH=

release-public: pkg-sign pkg-verify
	@echo "Built: $(PKG_SIGNED)"
	@echo "Tip: run 'make staple' if you want notarization stapled."

release-confidential: check-confidential-release
	@$(MAKE) release-internal \
	  TRANSPORT_IMPLEMENTATION=confidential \
	  CONFIDENTIAL_TRANSPORT_PATH="$(MINISTRY_CONFIDENTIAL_TRANSPORT_PATH)"

release-internal: pkg-sign pkg-verify
	@echo "Built: $(PKG_SIGNED)"
	@echo "Tip: run 'make staple' if you want notarization stapled."
