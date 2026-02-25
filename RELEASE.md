# YapYap Release Checklist

Guide for creating and publishing YapYap releases.

## Pre-Release Checklist

### 1. Version Bump

Update version in:
- [ ] `project.yml` → `CFBundleShortVersionString` and `CFBundleVersion`
- [ ] `YapYap/Info.plist` (if separate from project.yml)
- [ ] `README.md` → Installation instructions
- [ ] Settings sidebar → "v0.1.0" display

### 2. Code Freeze & Testing

- [ ] All unit tests pass (`make test`)
- [ ] Manual integration tests complete (see TESTING.md)
- [ ] UI validation complete (all 7 settings tabs, popover, floating bar)
- [ ] Test on clean macOS 14.0+ system
- [ ] Verify all permissions requests work (microphone, accessibility)

### 3. Documentation

- [ ] Update CHANGELOG.md with release notes
- [ ] Verify README.md is up-to-date
- [ ] Check all links in docs work (GitHub URLs, external links)
- [ ] Update screenshots if UI changed

### 4. Privacy & Compliance

- [ ] Privacy manifest (`PrivacyInfo.xcprivacy`) lists all API usage
- [ ] No telemetry/tracking code
- [ ] License headers correct (MIT)
- [ ] Third-party licenses acknowledged in About tab

## Build Process

### 1. Clean Build

```bash
# Clean all derived data
make clean
rm -rf ~/Library/Developer/Xcode/DerivedData/YapYap-*

# Regenerate project
make generate

# Build release archive
make archive
```

This creates: `build/YapYap.xcarchive`

### 2. Export Archive (No Code Signing)

Since we're not using an Apple Developer account, export without signing:

```bash
xcodebuild -exportArchive \
  -archivePath build/YapYap.xcarchive \
  -exportPath build/release \
  -exportOptionsPlist ExportOptions.plist
```

**ExportOptions.plist**:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>mac-application</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>stripSwiftSymbols</key>
    <true/>
</dict>
</plist>
```

### 3. Create DMG Installer

```bash
make dmg
```

This creates: `build/YapYap-v0.1.0.dmg`

**DMG Contents**:
- YapYap.app (drag target)
- Applications folder symlink (drop target)
- Custom background image (optional)
- Volume icon (YapYap creature)

**Manual DMG Creation** (if make dmg fails):

```bash
# Install create-dmg
brew install create-dmg

# Create DMG with custom settings
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
```

### 4. Verify DMG

```bash
# Mount DMG
hdiutil attach build/YapYap-v0.1.0.dmg

# Test installation
cp -R /Volumes/YapYap/YapYap.app ~/Desktop/
open ~/Desktop/YapYap.app

# Verify:
# - App launches
# - Onboarding appears
# - Permissions requests work
# - Recording works after setup

# Unmount
hdiutil detach /Volumes/YapYap
```

## GitHub Release

### 1. Create Git Tag

```bash
git tag -a v0.1.0 -m "Release v0.1.0 - Initial public release"
git push origin v0.1.0
```

### 2. Create GitHub Release

Go to https://github.com/sunboy/yapyap/releases/new

**Release Title**: `v0.1.0 - Initial Release`

**Release Notes Template**:

```markdown
## 🎉 YapYap v0.1.0

**You yap. It writes.**

First public release of YapYap — an open-source, offline macOS voice-to-text app with AI-powered cleanup.

### ✨ What's New

- 🎙 **Offline Speech-to-Text**: Whisper (Large/Medium/Small v3) + Parakeet TDT v3
- ✨ **AI Text Cleanup**: Qwen 2.5, Llama 3.2, Gemma 2 — all running locally
- 🎯 **Context-Aware Formatting**: Auto-detects your app and adjusts style
- 🖱 **Push-to-Talk**: Hold Option+Space, speak, release — clean text appears
- 🎨 **Cozy Creature Companion**: Lives in your menu bar, animates while you yap
- 📊 **Local Analytics**: Track your words, time saved, daily stats
- ⚙️ **Highly Configurable**: Custom styles, hotkeys, per-app overrides

### 📦 Installation

**Download**: [YapYap-v0.1.0.dmg](https://github.com/sunboy/yapyap/releases/download/v0.1.0/YapYap-v0.1.0.dmg)

**Homebrew** (coming soon):
```bash
brew install --cask yapyap
```

**From Source**:
```bash
git clone https://github.com/sunboy/yapyap.git
cd yapyap
make build
```

### 💻 Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon (M1 or later)
- 8GB RAM minimum (16GB recommended)
- ~2-4GB disk space for models

### 🔒 Privacy

- 100% offline — your voice never leaves your Mac
- No telemetry, no tracking, no accounts
- All data stored locally in `~/Library/Application Support/YapYap/`
- Open source (MIT License)

### 📚 Documentation

- [README](https://github.com/sunboy/yapyap#readme)
- [Testing Guide](TESTING.md)
- [Architecture](docs/ARCHITECTURE.md)

### 🙏 Acknowledgments

- [WhisperKit](https://github.com/argmaxinc/WhisperKit) — On-device Whisper inference
- [FluidAudio](https://github.com/FluidInference/FluidAudio) — Parakeet CoreML models
- [MLX Swift](https://github.com/ml-explore/mlx-swift) — Apple's ML framework

### 🐛 Known Issues

- First model download may take 5-10 minutes
- Whisper Large v3 Turbo requires 16GB RAM
- Command Mode requires pre-selecting text (no automatic selection yet)

Report issues: https://github.com/sunboy/yapyap/issues

---

*Made with 💜 and too much coffee*
```

**Assets**:
- [ ] Upload `YapYap-v0.1.0.dmg`
- [ ] Upload source code (GitHub auto-generates)

### 3. Update Appcast (for Sparkle)

Edit `Distribution/appcast.xml`:

```xml
<item>
    <title>Version 0.1.0</title>
    <link>https://github.com/sunboy/yapyap/releases/tag/v0.1.0</link>
    <sparkle:version>0.1.0</sparkle:version>
    <sparkle:shortVersionString>0.1.0</sparkle:shortVersionString>
    <description><![CDATA[
        <h2>What's New</h2>
        <ul>
            <li>Initial public release</li>
            <li>Offline speech-to-text with Whisper and Parakeet</li>
            <li>AI-powered cleanup with Qwen, Llama, and Gemma</li>
            <li>Context-aware formatting for different apps</li>
        </ul>
    ]]></description>
    <pubDate>Thu, 13 Feb 2026 12:00:00 +0000</pubDate>
    <enclosure
        url="https://github.com/sunboy/yapyap/releases/download/v0.1.0/YapYap-v0.1.0.dmg"
        sparkle:version="0.1.0"
        sparkle:shortVersionString="0.1.0"
        length="FILE_SIZE_IN_BYTES"
        type="application/octet-stream"
    />
    <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
</item>
```

Get file size:
```bash
ls -l build/YapYap-v0.1.0.dmg | awk '{print $5}'
```

Commit and push appcast.xml to repo.

## Homebrew Cask (Optional)

After GitHub release is published:

1. Fork [homebrew-cask](https://github.com/Homebrew/homebrew-cask)
2. Create cask file: `Casks/yapyap.rb`

```ruby
cask "yapyap" do
  version "0.1.0"
  sha256 "DMG_SHA256_HERE"

  url "https://github.com/sunboy/yapyap/releases/download/v#{version}/YapYap-v#{version}.dmg"
  name "YapYap"
  desc "Offline macOS voice-to-text with AI cleanup"
  homepage "https://github.com/sunboy/yapyap"

  depends_on macos: ">= :sonoma"
  depends_on arch: :arm64

  app "YapYap.app"

  zap trash: [
    "~/Library/Application Support/YapYap",
    "~/Library/Preferences/dev.yapyap.app.plist",
  ]
end
```

Get SHA256:
```bash
shasum -a 256 build/YapYap-v0.1.0.dmg
```

3. Submit PR to homebrew-cask

## Post-Release

### 1. Announce

- [ ] Post to Reddit r/macapps
- [ ] Post to Hacker News
- [ ] Post to MacRumors forums
- [ ] Update personal website/blog

### 2. Monitor

- [ ] Watch GitHub issues for bug reports
- [ ] Monitor crash reports (if enabled)
- [ ] Engage with users in discussions

### 3. Plan Next Release

- [ ] Create GitHub milestone for v0.2.0
- [ ] Triage issues into milestone
- [ ] Update roadmap in README

## Rollback Procedure

If critical bug discovered:

1. **Yanking Release**:
   - Edit GitHub release → Mark as pre-release
   - Update README with warning
   - Post issue explaining problem

2. **Hotfix Release**:
   - Create `hotfix/v0.1.1` branch from `v0.1.0` tag
   - Fix critical bug
   - Test thoroughly
   - Release v0.1.1 following this guide
   - Merge hotfix back to main

## Code Signing (Future)

When Apple Developer account is available:

1. **Get Developer ID Application certificate**
2. **Update project.yml**:
   ```yaml
   settings:
     base:
       DEVELOPMENT_TEAM: "YOUR_TEAM_ID"
       CODE_SIGN_IDENTITY: "Developer ID Application"
       CODE_SIGN_STYLE: Automatic
   ```

3. **Sign app**:
   ```bash
   codesign --deep --force --verify --verbose \
     --sign "Developer ID Application" \
     build/release/YapYap.app
   ```

4. **Notarize DMG**:
   ```bash
   xcrun notarytool submit build/YapYap-v0.1.0.dmg \
     --apple-id YOUR_APPLE_ID \
     --team-id YOUR_TEAM_ID \
     --password APP_SPECIFIC_PASSWORD \
     --wait
   ```

5. **Staple notarization**:
   ```bash
   xcrun stapler staple build/YapYap-v0.1.0.dmg
   ```

## Release Cadence

Recommended schedule:

- **Major releases** (1.0, 2.0): Every 6-12 months
- **Minor releases** (1.1, 1.2): Every 1-2 months
- **Patch releases** (1.1.1): As needed for critical bugs

## Versioning

Follow Semantic Versioning (semver.org):

- **Major** (1.0.0 → 2.0.0): Breaking changes, major features
- **Minor** (1.0.0 → 1.1.0): New features, backward compatible
- **Patch** (1.0.0 → 1.0.1): Bug fixes, no new features

---

*Last updated: 2026-02-13*
