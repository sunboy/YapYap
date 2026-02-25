.PHONY: build run test archive sign notarize staple dmg release clean generate bench-build bench

VERSION := $(shell /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" YapYap/Info.plist 2>/dev/null || echo "0.1.0")
APPLE_ID ?= sandeeptnvs@gmail.com
TEAM_ID  := C4HCL432GF
DMG_NAME := YapYap-v$(VERSION).dmg

# Generate Xcode project from project.yml (requires XcodeGen)
generate:
	xcodegen generate

build:
	xcodebuild -project YapYap.xcodeproj -scheme YapYap -configuration Debug build

run: build
	@APP_PATH=$$(find ~/Library/Developer/Xcode/DerivedData/YapYap-*/Build/Products/Debug/YapYap.app -type d 2>/dev/null | head -1); \
	if [ -z "$$APP_PATH" ]; then \
		echo "Error: YapYap.app not found in DerivedData"; \
		exit 1; \
	fi; \
	echo "Opening $$APP_PATH"; \
	open "$$APP_PATH"

test:
	xcodebuild -project YapYap.xcodeproj -scheme YapYap -configuration Debug test

archive:
	@mkdir -p build
	xcodebuild -project YapYap.xcodeproj -scheme YapYap \
		-configuration Release archive \
		-archivePath build/YapYap.xcarchive

	xcodebuild -exportArchive \
		-archivePath build/YapYap.xcarchive \
		-exportPath build/release \
		-exportOptionsPlist ExportOptions.plist

# Sign the exported app with Developer ID (automatic via ExportOptions.plist but can be run standalone)
sign:
	@echo "Verifying code signature..."
	codesign --verify --deep --strict --verbose=2 build/release/YapYap.app
	spctl --assess --type exec --verbose build/release/YapYap.app
	@echo "✅ Signature valid"

dmg: archive
	@echo "Creating DMG installer (v$(VERSION))..."
	@if ! command -v create-dmg &> /dev/null; then \
		echo "Installing create-dmg..."; \
		brew install create-dmg; \
	fi
	@rm -f build/$(DMG_NAME)
	create-dmg \
		--volname "YapYap" \
		--window-pos 400 300 \
		--window-size 640 480 \
		--icon-size 80 \
		--icon "YapYap.app" 160 240 \
		--app-drop-link 480 240 \
		--no-internet-enable \
		build/$(DMG_NAME) \
		build/release/YapYap.app
	@echo "✅ DMG created: build/$(DMG_NAME)"

# Notarize the DMG with Apple's notary service.
# Requires APP_SPECIFIC_PASSWORD env var (create at appleid.apple.com → App-Specific Passwords)
# Usage: make notarize APP_SPECIFIC_PASSWORD=xxxx-xxxx-xxxx-xxxx
notarize:
	@if [ -z "$(APP_SPECIFIC_PASSWORD)" ]; then \
		echo "❌ APP_SPECIFIC_PASSWORD is required"; \
		echo "   Create one at: https://appleid.apple.com → Sign-In and Security → App-Specific Passwords"; \
		echo "   Usage: make notarize APP_SPECIFIC_PASSWORD=xxxx-xxxx-xxxx-xxxx"; \
		exit 1; \
	fi
	@echo "Submitting build/$(DMG_NAME) for notarization..."
	xcrun notarytool submit build/$(DMG_NAME) \
		--apple-id "$(APPLE_ID)" \
		--team-id "$(TEAM_ID)" \
		--password "$(APP_SPECIFIC_PASSWORD)" \
		--wait \
		--output-format json
	@echo "✅ Notarization complete"

# Staple the notarization ticket to the DMG so it works offline
staple:
	@echo "Stapling notarization ticket to build/$(DMG_NAME)..."
	xcrun stapler staple build/$(DMG_NAME)
	xcrun stapler validate build/$(DMG_NAME)
	@echo "✅ Stapled"

# Full release pipeline: archive → DMG → notarize → staple
# Usage: make release APP_SPECIFIC_PASSWORD=xxxx-xxxx-xxxx-xxxx
release: dmg notarize staple
	@echo ""
	@echo "🎉 Release ready: build/$(DMG_NAME)"
	@echo ""
	@SIZE=$$(stat -f%z build/$(DMG_NAME)); \
	SHA=$$(shasum -a 256 build/$(DMG_NAME) | awk '{print $$1}'); \
	echo "   File size: $$SIZE bytes"; \
	echo "   SHA-256:   $$SHA"; \
	echo ""; \
	echo "Next steps:"; \
	echo "  1. Create GitHub release: gh release create v$(VERSION) build/$(DMG_NAME)"; \
	echo "  2. Update Distribution/appcast.xml with the release item"; \
	echo "  3. Sign the appcast entry with: sign_update build/$(DMG_NAME)"; \
	echo "  4. Push appcast.xml to GitHub (Sparkle reads it from main branch)"; \

clean:
	xcodebuild -project YapYap.xcodeproj -scheme YapYap clean
	rm -rf build/ DerivedData/

bench-build:
	xcodebuild -project YapYap.xcodeproj -scheme YapYapBench -configuration Debug build

bench:
	@BIN=$$(xcodebuild -project YapYap.xcodeproj -scheme YapYapBench -configuration Debug -showBuildSettings 2>/dev/null | grep -m1 BUILT_PRODUCTS_DIR | awk '{print $$3}')/YapYapBench; \
	"$$BIN" $(ARGS)
