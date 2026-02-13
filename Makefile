.PHONY: build run test archive clean generate

# Generate Xcode project from project.yml (requires XcodeGen)
generate:
	xcodegen generate

build:
	xcodebuild -project YapYap.xcodeproj -scheme YapYap -configuration Debug build

run: build
	open build/Debug/YapYap.app

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
	create-dmg build/release/YapYap.app build/YapYap.dmg

clean:
	xcodebuild -project YapYap.xcodeproj -scheme YapYap clean
	rm -rf build/ DerivedData/

homebrew:
	@echo "After release: brew install --cask yapyap"
