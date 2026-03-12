// swift-tools-version: 5.9
// This Package.swift is provided as a reference for SPM dependencies.
// The actual project uses XcodeGen (project.yml) to generate the Xcode project.
// Run: xcodegen generate

import PackageDescription

let package = Package(
    name: "YapYap",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        // STT Backends
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.7.9"),

        // LLM Inference
        .package(url: "https://github.com/ml-explore/mlx-swift.git", from: "0.21.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", from: "0.2.0"),

        // macOS Utilities
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", from: "2.0.0"),
        .package(url: "https://github.com/sindresorhus/LaunchAtLogin-Modern.git", from: "1.0.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.0.0"),
        .package(url: "https://github.com/tisfeng/SelectedTextKit.git", from: "0.3.0"),
    ]
)
