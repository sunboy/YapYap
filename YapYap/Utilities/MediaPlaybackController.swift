// MediaPlaybackController.swift
// YapYap — Pause/resume media playback during recording
import Foundation

/// Controls system media playback using MediaRemote private framework (via dlopen).
/// Used to auto-pause music/podcasts during voice recording and resume after.
class MediaPlaybackController {
    static let shared = MediaPlaybackController()

    private var wasPlayingBeforePause = false
    private var mediaRemoteHandle: UnsafeMutableRawPointer?

    // MediaRemote command constants
    private static let kMRMediaRemoteCommandPause: UInt32 = 1
    private static let kMRMediaRemoteCommandPlay: UInt32 = 0
    private static let kMRMediaRemoteCommandTogglePlayPause: UInt32 = 2

    // Function type for MRMediaRemoteSendCommand
    private typealias MRMediaRemoteSendCommandFunc = @convention(c) (UInt32, UnsafeMutableRawPointer?) -> Bool
    // Function type for MRMediaRemoteGetNowPlayingInfo
    private typealias MRMediaRemoteGetNowPlayingInfoFunc = @convention(c) (
        DispatchQueue, @escaping (CFDictionary) -> Void
    ) -> Void

    private var sendCommandFunc: MRMediaRemoteSendCommandFunc?
    private var getNowPlayingInfoFunc: MRMediaRemoteGetNowPlayingInfoFunc?

    private init() {
        loadMediaRemote()
    }

    private func loadMediaRemote() {
        let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
        guard let handle = dlopen(path, RTLD_LAZY) else {
            NSLog("[MediaPlaybackController] ⚠️ Could not load MediaRemote framework")
            return
        }
        mediaRemoteHandle = handle

        if let sym = dlsym(handle, "MRMediaRemoteSendCommand") {
            sendCommandFunc = unsafeBitCast(sym, to: MRMediaRemoteSendCommandFunc.self)
        }

        if let sym = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") {
            getNowPlayingInfoFunc = unsafeBitCast(sym, to: MRMediaRemoteGetNowPlayingInfoFunc.self)
        }

        NSLog("[MediaPlaybackController] ✅ MediaRemote loaded (send: \(sendCommandFunc != nil), info: \(getNowPlayingInfoFunc != nil))")
    }

    /// Pause media playback if currently playing. Remembers state for resume.
    func pauseIfPlaying() {
        guard let sendCommand = sendCommandFunc else { return }

        // Check if something is currently playing via NowPlaying info
        checkNowPlaying { [weak self] isPlaying in
            guard let self = self else { return }
            if isPlaying {
                self.wasPlayingBeforePause = true
                let _ = sendCommand(Self.kMRMediaRemoteCommandPause, nil)
                NSLog("[MediaPlaybackController] ⏸ Media paused")
            } else {
                self.wasPlayingBeforePause = false
                NSLog("[MediaPlaybackController] No media playing, skip pause")
            }
        }
    }

    /// Resume media playback if it was playing before we paused it.
    func resumeIfWasPaused() {
        guard wasPlayingBeforePause, let sendCommand = sendCommandFunc else { return }
        wasPlayingBeforePause = false

        // Small delay to let the processing sound effect finish
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let _ = sendCommand(Self.kMRMediaRemoteCommandPlay, nil)
            NSLog("[MediaPlaybackController] ▶️ Media resumed")
        }
    }

    private func checkNowPlaying(completion: @escaping (Bool) -> Void) {
        guard let getInfo = getNowPlayingInfoFunc else {
            completion(false)
            return
        }

        getInfo(DispatchQueue.main) { info in
            let dict = info as NSDictionary
            // kMRMediaRemoteNowPlayingInfoPlaybackRate key
            let playbackRate = dict["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double ?? 0
            completion(playbackRate > 0)
        }
    }

    deinit {
        if let handle = mediaRemoteHandle {
            dlclose(handle)
        }
    }
}
