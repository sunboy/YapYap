// HotkeyManager.swift
// YapYap — Global hotkey registration using KeyboardShortcuts
import AppKit
import KeyboardShortcuts
import Combine

extension KeyboardShortcuts.Name {
    static let pushToTalk = Self("pushToTalk", default: .init(.space, modifiers: .option))
    static let handsFreeMode = Self("handsFreeMode", default: .init(.space, modifiers: [.option, .shift]))
    static let commandMode = Self("commandMode", default: .init(.space, modifiers: [.option, .command]))
    static let cancelRecording = Self("cancelRecording", default: .init(.escape))
}

class HotkeyManager {
    static let shared = HotkeyManager()

    private weak var pipeline: TranscriptionPipeline?
    private weak var appState: AppState?
    private var isHandsFreeActive = false

    private init() {}

    func configure(pipeline: TranscriptionPipeline, appState: AppState) {
        self.pipeline = pipeline
        self.appState = appState
        registerHotkeys()
    }

    private func registerHotkeys() {
        // Push-to-Talk: hold to record, release to process
        KeyboardShortcuts.onKeyDown(for: .pushToTalk) { [weak self] in
            self?.handlePushToTalkDown()
        }
        KeyboardShortcuts.onKeyUp(for: .pushToTalk) { [weak self] in
            self?.handlePushToTalkUp()
        }

        // Hands-Free Mode: toggle recording on/off
        KeyboardShortcuts.onKeyDown(for: .handsFreeMode) { [weak self] in
            self?.handleHandsFreeToggle()
        }

        // Command Mode: separate hotkey for voice commands on selected text
        KeyboardShortcuts.onKeyDown(for: .commandMode) { [weak self] in
            self?.handleCommandMode()
        }

        // Cancel Recording
        KeyboardShortcuts.onKeyDown(for: .cancelRecording) { [weak self] in
            self?.handleCancel()
        }
    }

    // MARK: - Push-to-Talk

    private func handlePushToTalkDown() {
        guard let appState = appState, appState.masterToggle else { return }
        guard let pipeline = pipeline else { return }

        Task { @MainActor in
            do {
                try await pipeline.startRecording()
            } catch {
                print("Failed to start recording: \(error)")
            }
        }
    }

    private func handlePushToTalkUp() {
        guard let pipeline = pipeline else { return }
        guard let appState = appState, appState.isRecording else { return }

        Task { @MainActor in
            do {
                _ = try await pipeline.stopRecordingAndProcess()
            } catch {
                print("Failed to process recording: \(error)")
            }
        }
    }

    // MARK: - Hands-Free Mode

    private func handleHandsFreeToggle() {
        guard let appState = appState, appState.masterToggle else { return }
        guard let pipeline = pipeline else { return }

        if isHandsFreeActive {
            isHandsFreeActive = false
            Task { @MainActor in
                do {
                    _ = try await pipeline.stopRecordingAndProcess()
                } catch {
                    print("Failed to process recording: \(error)")
                }
            }
        } else {
            isHandsFreeActive = true
            Task { @MainActor in
                do {
                    try await pipeline.startRecording()
                } catch {
                    print("Failed to start recording: \(error)")
                    isHandsFreeActive = false
                }
            }
        }
    }

    // MARK: - Command Mode

    private func handleCommandMode() {
        guard let appState = appState, appState.masterToggle else { return }
        guard let pipeline = pipeline else { return }

        Task { @MainActor in
            do {
                try await pipeline.startRecording(isCommandMode: true)
            } catch {
                print("Failed to start command mode: \(error)")
            }
        }
    }

    // MARK: - Cancel

    private func handleCancel() {
        guard let pipeline = pipeline else { return }
        pipeline.cancelRecording()
        isHandsFreeActive = false
    }
}
