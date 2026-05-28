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

.PHONY: all build app sign install run clean cert check-sparkle-key check-version

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

app: build check-sparkle-key check-version
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
	for bin in MeetingScribeMCP NotionMCP; do \
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
	@rm -rf $(INSTALL_DIR)/$(APP_NAME).app
	@cp -R $(APP_DIR) $(INSTALL_DIR)/
	@# Register the freshly-signed bundle with LaunchServices. Without this, a
	@# re-signed copy can leave `bundleProxyForCurrentProcess` nil, which makes
	@# `UNUserNotificationCenter.current()` assert and crash the app at launch.
	@/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f $(INSTALL_DIR)/$(APP_NAME).app || true
	@echo "  + registered with LaunchServices"

run: app
	/usr/bin/open $(APP_DIR)

clean:
	swift package clean
	rm -rf build .build
