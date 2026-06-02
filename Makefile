APP_NAME      := MeetingScribe
BUNDLE_ID     := com.tyleryannes.MeetingScribe
BUILD_DIR     := .build/release
APP_DIR       := build/$(APP_NAME).app
INSTALL_DIR   := /Applications
SIGN_IDENTITY := MeetingScribe Local Signer
KEYCHAIN      := $(HOME)/Library/Keychains/login.keychain-db
# Designated requirement: TCC identifies the app by (bundle ID + cert CN),
# both stable across rebuilds. Without this, TCC falls back to the binary
# hash and re-prompts for every permission after every build.
DESIGNATED_REQ := designated => identifier "$(BUNDLE_ID)" and certificate leaf[subject.CN] = "$(SIGN_IDENTITY)"

SCRIBECORE_NAME     := ScribeCore
SCRIBECORE_BUNDLE_ID := com.tyleryannes.ScribeCore
SCRIBECORE_APP_DIR  := build/$(SCRIBECORE_NAME).app

.PHONY: all build app scribecore sign sign-scribecore install run dmg clean cert check-sparkle-key check-version

all: app

build:
	swift build -c release

cert:
	@./scripts/create-signing-cert.sh

# Hard-stop if the Sparkle EdDSA public key is still the placeholder. A
# placeholder key either silently breaks every update check (Sparkle ≥ 2)
# or — worse, in older Sparkle — disables signature verification. Either
# way it's not something we want shipped accidentally.
check-sparkle-key:
	@if grep -q 'REPLACE_WITH_SPARKLE_PUBLIC_ED_KEY' Resources/Info.plist; then \
		echo ""; \
		echo "✗ Sparkle public key is still the placeholder in Resources/Info.plist."; \
		echo "  Auto-updates won't verify. Run the one-time setup in RELEASING.md:"; \
		echo "    1. ./bin/generate_keys           # from Sparkle's tarball"; \
		echo "    2. paste the printed public key into Resources/Info.plist"; \
		echo "    3. add the private key as the SPARKLE_PRIVATE_KEY repo secret"; \
		echo ""; \
		echo "  If you're intentionally building without auto-updates,"; \
		echo "  set ALLOW_PLACEHOLDER_KEY=1 to bypass this check."; \
		echo ""; \
		if [ "$$ALLOW_PLACEHOLDER_KEY" != "1" ]; then exit 1; fi; \
		echo "⚠  ALLOW_PLACEHOLDER_KEY=1 set — proceeding without Sparkle verification."; \
	fi

# Stamp the marketing version + build number from `git describe` so local
# `make app` builds are uniquely identifiable in bug reports. CI overrides
# both via PlistBuddy in .github/workflows/release.yml.
check-version:
	@if [ -z "$$CI" ]; then \
		V=$$(git describe --tags --always --dirty 2>/dev/null || echo "dev"); \
		echo "→ Stamping build version: $$V"; \
		/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $$V" Resources/Info.plist 2>/dev/null || true; \
	fi

scribecore: build
	@echo "→ Bundling $(SCRIBECORE_NAME).app"
	@rm -rf $(SCRIBECORE_APP_DIR)
	@mkdir -p $(SCRIBECORE_APP_DIR)/Contents/MacOS
	@cp $(BUILD_DIR)/$(SCRIBECORE_NAME) $(SCRIBECORE_APP_DIR)/Contents/MacOS/$(SCRIBECORE_NAME)
	@cp Sources/ScribeCore/Info.plist $(SCRIBECORE_APP_DIR)/Contents/Info.plist
	@$(MAKE) sign-scribecore

sign-scribecore:
	@if security find-identity -p basic "$(KEYCHAIN)" 2>/dev/null | grep -q "$(SIGN_IDENTITY)"; then \
		ID="$(SIGN_IDENTITY)"; \
	else \
		ID="-"; \
		echo "⚠  No stable signing identity found for ScribeCore — using ad-hoc."; \
	fi; \
	if [ "$$ID" = "-" ]; then \
		codesign --force --options runtime --sign - $(SCRIBECORE_APP_DIR); \
	else \
		codesign --force \
			--options runtime \
			--sign "$$ID" \
			--identifier $(SCRIBECORE_BUNDLE_ID) \
			--entitlements Sources/ScribeCore/ScribeCore.entitlements \
			$(SCRIBECORE_APP_DIR); \
	fi
	@echo "→ Built $(SCRIBECORE_APP_DIR)"

app: scribecore check-sparkle-key check-version
	@echo "→ Bundling $(APP_NAME).app"
	@rm -rf $(APP_DIR)
	@mkdir -p $(APP_DIR)/Contents/MacOS
	@mkdir -p $(APP_DIR)/Contents/Resources
	@cp $(BUILD_DIR)/$(APP_NAME) $(APP_DIR)/Contents/MacOS/$(APP_NAME)
	@if [ -f $(BUILD_DIR)/MeetingScribeMCP ]; then \
		cp $(BUILD_DIR)/MeetingScribeMCP $(APP_DIR)/Contents/MacOS/MeetingScribeMCP; \
		echo "  + bundled MeetingScribeMCP"; \
	else \
		echo "  ! MeetingScribeMCP not built (run 'swift build -c release' first)"; \
	fi
	@if [ -f $(BUILD_DIR)/NotionMCP ]; then \
		cp $(BUILD_DIR)/NotionMCP $(APP_DIR)/Contents/MacOS/NotionMCP; \
		echo "  + bundled NotionMCP"; \
	else \
		echo "  ! NotionMCP not built"; \
	fi
	@if [ -f $(BUILD_DIR)/MeetingScribeSync ]; then \
		cp $(BUILD_DIR)/MeetingScribeSync $(APP_DIR)/Contents/MacOS/MeetingScribeSync; \
		echo "  + bundled MeetingScribeSync"; \
	else \
		echo "  ! MeetingScribeSync not built"; \
	fi
	@cp Resources/Info.plist $(APP_DIR)/Contents/Info.plist
	@SPARKLE_FW=$$(find .build -iname Sparkle.framework -type d 2>/dev/null | head -1); \
	if [ -n "$$SPARKLE_FW" ]; then \
		mkdir -p $(APP_DIR)/Contents/Frameworks; \
		rm -rf $(APP_DIR)/Contents/Frameworks/Sparkle.framework; \
		cp -R "$$SPARKLE_FW" $(APP_DIR)/Contents/Frameworks/; \
		install_name_tool -add_rpath "@executable_path/../Frameworks" \
			$(APP_DIR)/Contents/MacOS/$(APP_NAME) 2>/dev/null || true; \
		echo "  + embedded Sparkle.framework"; \
	else \
		echo "  ! Sparkle.framework not found in .build (auto-update disabled)"; \
	fi
	@echo "→ Embedding ScribeCore.app as LoginItem"
	@mkdir -p $(APP_DIR)/Contents/Library/LoginItems
	@rm -rf $(APP_DIR)/Contents/Library/LoginItems/$(SCRIBECORE_NAME).app
	@cp -R $(SCRIBECORE_APP_DIR) $(APP_DIR)/Contents/Library/LoginItems/$(SCRIBECORE_NAME).app
	@echo "  + embedded $(SCRIBECORE_NAME).app in LoginItems"
	@$(MAKE) sign

sign:
	@if security find-identity -p basic "$(KEYCHAIN)" 2>/dev/null | grep -q "$(SIGN_IDENTITY)"; then \
		ID="$(SIGN_IDENTITY)"; \
		echo "→ Signing with stable identity '$(SIGN_IDENTITY)' (TCC permissions persist across rebuilds)"; \
	else \
		ID="-"; \
		echo "⚠  No stable signing identity found. Falling back to ad-hoc."; \
		echo "   Run 'make cert' once to fix — that stops TCC re-prompting on every rebuild."; \
	fi; \
	if [ -d "$(APP_DIR)/Contents/Frameworks/Sparkle.framework" ]; then \
		codesign --force --deep --sign "$$ID" \
			--options runtime \
			"$(APP_DIR)/Contents/Frameworks/Sparkle.framework"; \
		echo "  + signed Sparkle.framework"; \
	fi; \
	for bin in MeetingScribeMCP NotionMCP MeetingScribeSync; do \
		if [ -f $(APP_DIR)/Contents/MacOS/$$bin ]; then \
			codesign --force --options runtime --sign "$$ID" $(APP_DIR)/Contents/MacOS/$$bin; \
		fi; \
	done; \
	if [ "$$ID" = "-" ]; then \
		codesign --force --options runtime --sign - $(APP_DIR); \
	else \
		codesign --force \
			--options runtime \
			--sign "$$ID" \
			--identifier $(BUNDLE_ID) \
			--entitlements Resources/Entitlements.plist \
			--requirements '=$(DESIGNATED_REQ)' \
			$(APP_DIR); \
	fi
	@echo "→ Built $(APP_DIR)"

install: app
	@echo "→ Installing to $(INSTALL_DIR)"
	@# Quit any running instance before replacing — avoids "file busy" errors
	@osascript -e 'tell application "$(APP_NAME)" to quit' 2>/dev/null || true
	@sleep 1
	@# rm -rf first: cp -R into an existing .app merges instead of replacing,
	@# leaving stale old files. Always delete then copy.
	@rm -rf $(INSTALL_DIR)/$(APP_NAME).app
	@cp -R $(APP_DIR) $(INSTALL_DIR)/$(APP_NAME).app
	@# Register the freshly-signed bundle with LaunchServices so the Dock
	@# and Spotlight pick up the new version immediately.
	@/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -f $(INSTALL_DIR)/$(APP_NAME).app 2>/dev/null || \
		/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f $(INSTALL_DIR)/$(APP_NAME).app || true
	@echo "  + registered with LaunchServices"
	@echo "✓ Installed $(INSTALL_DIR)/$(APP_NAME).app"

# dev: build, install, and relaunch in one command.
# Use this instead of 'make app' for day-to-day development.
dev: install
	@echo "→ Launching $(APP_NAME)"
	@sleep 0.5
	@/usr/bin/open $(INSTALL_DIR)/$(APP_NAME).app
	@echo "✓ $(APP_NAME) launched"

run: app
	/usr/bin/open $(APP_DIR)

# No-Terminal installer (U5-1): a double-click .dmg with the app + a
# drag-to-Applications symlink. Signed with the local identity (self-signed,
# NOT notarized) — installs cleanly on this Mac; other Macs will warn at first
# open until a real Developer ID + notarization is wired up.
DMG_STAGE := build/dmg-stage
DMG_PATH  := build/$(APP_NAME).dmg

dmg: app
	@echo "→ Building $(DMG_PATH)"
	@rm -rf "$(DMG_STAGE)" "$(DMG_PATH)"
	@mkdir -p "$(DMG_STAGE)"
	@cp -R "$(APP_DIR)" "$(DMG_STAGE)/$(APP_NAME).app"
	@ln -s /Applications "$(DMG_STAGE)/Applications"
	@hdiutil create -volname "$(APP_NAME)" -srcfolder "$(DMG_STAGE)" \
		-ov -format UDZO "$(DMG_PATH)" >/dev/null
	@codesign --force --sign "$(SIGN_IDENTITY)" "$(DMG_PATH)" 2>/dev/null || \
		echo "  (dmg left unsigned — local identity unavailable)"
	@rm -rf "$(DMG_STAGE)"
	@echo "✓ Built $(DMG_PATH) — double-click it, then drag $(APP_NAME) to Applications"

clean:
	swift package clean
	rm -rf build .build
