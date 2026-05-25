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

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)
        let host = BrowserHostController()
        Self.activeHost = host
        window.rootViewController = host
        self.window = window
        window.makeKeyAndVisible()

        // T-006 hook: opportunity to make the resume decision before the
        // browser becomes the visible top view controller (DC-3). Default
        // is a no-op, so the browser is the natural landing.
        host.willPresentInitialContent?(host, connectionOptions)
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        Self.activeHost?.flushPendingSaves()
    }

    func sceneWillResignActive(_ scene: UIScene) {
        Self.activeHost?.flushPendingSaves()
    }
}
