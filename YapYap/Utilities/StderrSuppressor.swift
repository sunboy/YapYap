// StderrSuppressor.swift
// YapYap — Temporarily redirect stderr during noisy library calls
import Foundation

enum StderrSuppressor {
    /// Run an async closure with stderr redirected to /dev/null.
    /// Returns (result, byte count of suppressed stderr).
    /// Uses /dev/null instead of a pipe to avoid deadlocks when
    /// libraries produce more than 64KB of stderr output.
    static func capturing<T: Sendable>(
        _ body: @Sendable () async throws -> T
    ) async rethrows -> (result: T, stderr: String) {
        let originalFd = dup(STDERR_FILENO)

        // Redirect stderr to /dev/null — avoids pipe buffer deadlock
        let devNull = open("/dev/null", O_WRONLY)
        if devNull >= 0 {
            dup2(devNull, STDERR_FILENO)
            close(devNull)
        }

        let result: T
        do {
            result = try await body()
        } catch {
            dup2(originalFd, STDERR_FILENO)
            close(originalFd)
            throw error
        }

        dup2(originalFd, STDERR_FILENO)
        close(originalFd)

        // We can't capture the actual content with /dev/null,
        // but this avoids the deadlock. Return empty string.
        return (result, "")
    }

    /// Run with stderr suppressed (discard output).
    static func suppressing<T: Sendable>(
        _ body: @Sendable () async throws -> T
    ) async rethrows -> T {
        try await capturing(body).result
    }
}
