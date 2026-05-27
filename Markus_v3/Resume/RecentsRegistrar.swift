import Foundation
import UIKit

/// Best-effort registration of a file with the system document browser's
/// Recents on bookmark-based opens (design C7 / NP-10).
///
/// No public UIKit API exists for non-`UIDocument` apps to explicitly register
/// Recents with `UIDocumentBrowserViewController` for files presented
/// programmatically. The closest available signal is to touch the file under
/// its security-scoped resource, which nudges the system's Spotlight /
/// metadata indexing toward registering the file as recently accessed. Whether
/// the file actually appears in Recents depends on OS behavior for
/// security-scoped external files opened outside the browser delegate;
/// appearance is not guaranteed (per requirements NP-10.1 / NP-10.2 best-effort
/// framing, adversarial F-002).
///
/// Failures are silently swallowed (NPC-16): a failed registration never
/// crashes the app, never surfaces an error, and never prevents the file from
/// opening.
@MainActor
final class RecentsRegistrar {

    /// Number of times `register(url:)` has been called on this instance.
    /// Test instrumentation; not used in production.
    private(set) var registerCallCount: Int = 0

    /// URLs passed to `register(url:)`, in call order.
    /// Test instrumentation; not used in production.
    private(set) var registeredURLs: [URL] = []

    /// When non-nil, the registration default mechanism is bypassed and this
    /// handler is invoked instead. Test injection seam.
    var overrideHandler: ((URL) -> Void)?

    /// When true, the default mechanism step is skipped (simulating a failure
    /// in the underlying UIKit / FileManager call). Call recording still
    /// happens. NPC-16: no propagation regardless.
    var shouldFail: Bool = false

    private weak var host: UIDocumentBrowserViewController?

    init(host: UIDocumentBrowserViewController? = nil) {
        self.host = host
    }

    func register(url: URL) {
        registerCallCount += 1
        registeredURLs.append(url)

        if shouldFail {
            return
        }
        if let overrideHandler {
            overrideHandler(url)
            return
        }
        Self.bestEffortRegister(url: url)
    }

    /// Touch the file under its security scope. This is the closest available
    /// public-API signal for the system Spotlight/Recents index for
    /// security-scoped external files opened programmatically. Any error is
    /// silently swallowed.
    private static func bestEffortRegister(url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        _ = try? FileManager.default.attributesOfItem(atPath: url.path)
    }
}
