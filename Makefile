.PHONY: build run test archive clean generate

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
	xcodebuild -project YapYap.xcodeproj -scheme YapYap \
		-configuration Release archive \
		-archivePath build/YapYap.xcarchive

	xcodebuild -exportArchive \
		-archivePath build/YapYap.xcarchive \
		-exportPath build/release \
		-exportOptionsPlist ExportOptions.plist

dmg: archive
	@echo "Creating DMG installer..."
	@if ! command -v create-dmg &> /dev/null; then \
		echo "Installing create-dmg..."; \
		brew install create-dmg; \
	fi
	create-dmg \
		--volname "YapYap" \
		--window-pos 400 300 \
		--window-size 640 480 \
		--icon-size 80 \
		--icon "YapYap.app" 160 240 \
		--app-drop-link 480 240 \
		--no-internet-enable \
		build/YapYap-v0.1.0.dmg \
		build/release/YapYap.app

clean:
	xcodebuild -project YapYap.xcodeproj -scheme YapYap clean
	rm -rf build/ DerivedData/

homebrew:
	@echo "After release: brew install --cask yapyap"
