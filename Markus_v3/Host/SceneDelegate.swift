import UIKit

/// The scene's `UIWindowSceneDelegate`. Sets `BrowserHostController` as the
/// window's root view controller — the structural prerequisite for
/// `UIDocumentBrowserViewController` (which "appears as the root view
/// controller of the window," per Apple docs) and for the C2 / DC-3 zero-
/// browser-flash resume path (Wave 4 T-006).
///
/// Wave-4 plug-in points:
/// - `BrowserHostController.willPresentInitialContent` is invoked here in
///   `scene(_:willConnectTo:options:)`, *before* the browser is visible. T-006
///   binds this to make the resume decision and present the editor as the
///   scene's first content.
/// - `sceneDidEnterBackground` flushes any pending save so unsaved typing is
///   not lost when the user backgrounds the app (compensating for the lost
///   `DocumentGroup` background-save plumbing).
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    /// Globally accessible reference to the active host. Lets Wave-4
    /// components (e.g. T-006 LaunchResumeBranch) inspect / present without
    /// having to thread the delegate through SwiftUI.
    static weak var activeHost: BrowserHostController?

    private var openObserver: DocumentOpenObserver?

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        // Apply UI-test launch-state overrides BEFORE constructing the
        // host so the resume decision below sees the intended store state
        // (T-006 deterministic-launch contract).
        LaunchResumeBranch.applyTestOverrides(ProcessInfo.processInfo.arguments)

        let window = UIWindow(windowScene: windowScene)
        let host = BrowserHostController()
        Self.activeHost = host

        // Wire Wave-4 components onto the host's exposed hooks.
        let openObserver = DocumentOpenObserver(host: host)
        openObserver.install()
        self.openObserver = openObserver

        window.rootViewController = host
        self.window = window
        window.makeKeyAndVisible()

        // T-006 resume decision: defer to the host's first
        // `viewDidAppear` so the present has a fully-on-screen presenter.
        // For zero-flash semantics (DC-3) we want this to happen at the
        // earliest point the host can actually present a modal — earlier
        // call sites (synchronously from `willConnectTo`, or via a single
        // `DispatchQueue.main.async`) race window-becomeKeyAndVisible and
        // silently no-op the `present(_:animated:)`. If no resolvable
        // reference exists the closure is a no-op (browser is the
        // natural landing, DC-4). The build-time DC-3 escalation trigger
        // recorded in design.md applies if even this is observed to
        // flash the browser.
        host.initialResumeAction = { host in
            #if targetEnvironment(macCatalyst)
            // mac-catalyst-shell-14 T-006 — the Mac scene-restoration entry
            // routes through MacRestorationBridge, which defers entirely to
            // LaunchResumeBranch.resume(into:). No new identity store; the
            // bridge name makes the design Component-D seam explicit (S-6).
            MacRestorationBridge.restore(into: host)
            #else
            LaunchResumeBranch.resume(into: host)
            #endif
        }

        // Optional external hook (kept for future T-006 variants); fired
        // after the standard resume decision so a custom override can
        // run on top.
        host.willPresentInitialContent?(host, connectionOptions)
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        Self.activeHost?.flushPendingSaves()
    }

    func sceneWillResignActive(_ scene: UIScene) {
        Self.activeHost?.flushPendingSaves()
    }
}
