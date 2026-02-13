# Building YapYap from Source

## Prerequisites

- macOS 14.0 (Sonoma) or later
- Xcode 15.0 or later
- Apple Silicon Mac (M1 or later)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) for project generation

## Setup

1. **Install XcodeGen:**
   ```bash
   brew install xcodegen
   ```

2. **Clone the repository:**
   ```bash
   git clone https://github.com/yapyap-app/yapyap.git
   cd yapyap
   ```

3. **Generate the Xcode project:**
   ```bash
   xcodegen generate
   ```

4. **Open in Xcode:**
   ```bash
   open YapYap.xcodeproj
   ```

5. **Resolve packages:** Xcode will automatically fetch Swift Package Manager dependencies.

6. **Build and run:** Press Cmd+R or use the Makefile:
   ```bash
   make build
   make run
   ```

## Makefile Commands

| Command | Description |
|---------|-------------|
| `make generate` | Generate Xcode project from project.yml |
| `make build` | Build debug configuration |
| `make run` | Build and launch the app |
| `make test` | Run unit tests |
| `make archive` | Create release archive |
| `make clean` | Clean build artifacts |

## Permissions

On first launch, YapYap will request:
1. **Microphone Access** — required for voice capture
2. **Accessibility Access** — required for auto-paste and context detection

Grant these in System Settings > Privacy & Security.

## Models

AI models are downloaded on first use (~600MB-2GB each). They are stored in:
```
~/Library/Application Support/YapYap/Models/
```

## Troubleshooting

- **Build fails with package errors**: Delete `Package.resolved` and let Xcode re-resolve
- **Models won't download**: Check network connection; models come from HuggingFace
- **Paste doesn't work**: Ensure Accessibility permission is granted in System Settings
