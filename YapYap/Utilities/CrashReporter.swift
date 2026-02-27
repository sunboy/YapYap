// CrashReporter.swift
// YapYap — Anonymous crash reporting via Sentry
// Only initialised if the user has opted in (default: opted in, can be disabled in Settings)
import Sentry
import Foundation

struct CrashReporter {

    static func start() {
        guard isEnabled else { return }

        SentrySDK.start { options in
            options.dsn = "https://a142ba3a2433c88ee0f499ae57e47847@o4510955938250752.ingest.us.sentry.io/4510955944673280"

            // Release tagging for grouping errors by version
            options.releaseName = "yapyap@\(appVersion)"

            // Only capture crashes and errors — no performance tracing, no sessions
            options.enableTracing = false
            options.enableAutoSessionTracking = false

            // Strip all personal identifiers
            options.sendDefaultPii = false

            // Keep breadcrumbs minimal — no HTTP, no UI, no file system
            options.enableNetworkBreadcrumbs = false
            options.enableAutoBreadcrumbTracking = false

            // Don't report in debug builds
            #if DEBUG
            options.enabled = false
            #endif

            // Before-send hook: strip any remaining user/device identifiers
            options.beforeSend = { event in
                event.user = nil
                event.request = nil
                return event
            }
        }
    }

    // MARK: - Manual error capture

    static func capture(_ error: Error, context: [String: Any]? = nil) {
        guard isEnabled else { return }
        SentrySDK.capture(error: error) { scope in
            if let context {
                scope.setContext(value: context, key: "details")
            }
        }
    }

    static func capture(message: String, level: SentryLevel = .error, context: [String: Any]? = nil) {
        guard isEnabled else { return }
        SentrySDK.capture(message: message) { scope in
            scope.setLevel(level)
            if let context {
                scope.setContext(value: context, key: "details")
            }
        }
    }

    // MARK: - Breadcrumbs (non-PII pipeline events for crash context)

    static func breadcrumb(_ message: String, category: String = "pipeline") {
        guard isEnabled else { return }
        let crumb = Breadcrumb(level: .info, category: category)
        crumb.message = message
        SentrySDK.addBreadcrumb(crumb)
    }

    // MARK: - Opt-in/out

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "crashReportingEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "crashReportingEnabled") }
    }

    // MARK: - Private

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }
}
