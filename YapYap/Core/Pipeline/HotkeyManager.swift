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
        print("[HotkeyManager] configure() called")
        self.pipeline = pipeline
        self.appState = appState

        // Check PostEvent permission silently — uses sandbox-compatible API.
        // Onboarding step 2 handles the system prompt on first launch.
        // Post-onboarding, the app works without this (clipboard fallback, user pastes manually).
        let canPost = CGPreflightPostEventAccess()
        NSLog("[HotkeyManager] PostEvent access: %@", canPost ? "YES" : "NO")

        if !canPost {
            NSLog("[HotkeyManager] ⚠️ PostEvent NOT granted — paste will require manual Cmd+V")
        }

        registerHotkeys()
    }

    private func registerHotkeys() {
        print("[HotkeyManager] registerHotkeys() called")
        NSLog("[HotkeyManager] registerHotkeys() called - NSLog version")

        // Push-to-Talk: hold to record, release to process
        print("[HotkeyManager] Registering pushToTalk handlers...")
        KeyboardShortcuts.onKeyDown(for: .pushToTalk) { [weak self] in
            print("[HotkeyManager] Push-to-talk KEY DOWN")
            self?.handlePushToTalkDown()
        }
        KeyboardShortcuts.onKeyUp(for: .pushToTalk) { [weak self] in
            print("[HotkeyManager] Push-to-talk KEY UP")
            self?.handlePushToTalkUp()
        }
        print("[HotkeyManager] pushToTalk handlers registered")
        NSLog("[HotkeyManager] pushToTalk handlers registered - NSLog version")

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
        print("🎹 handlePushToTalkDown called")

        guard let appState = appState else {
            print("⚠️ appState is nil!")
            showError("appState is nil")
            return
        }

        guard appState.masterToggle else {
            print("⚠️ masterToggle is off! Current value: \(appState.masterToggle)")
            showError("Master toggle is off")
            return
        }

        guard let pipeline = pipeline else {
            print("⚠️ pipeline is nil!")
            showError("Pipeline is nil")
            return
        }

        print("✅ Starting recording...")
        Task { @MainActor in
            do {
                try await pipeline.startRecording()
                print("✅ Recording started")
            } catch {
                print("❌ Failed to start recording: \(error)")
                showError("Recording failed: \(error.localizedDescription)")
            }
        }
    }

    private func showError(_ message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Hotkey Error"
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    private func handlePushToTalkUp() {
        guard let pipeline = pipeline else { return }
        guard let appState = appState else { return }

        // If recording hasn't started yet (still loading models), set pendingStop
        // so startRecording() aborts after the load completes instead of recording.
        if !appState.isRecording {
            pipeline.pendingStop = true
            NSLog("[HotkeyManager] Key released before recording started — set pendingStop")
            return
        }

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
