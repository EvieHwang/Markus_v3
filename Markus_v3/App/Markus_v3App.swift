import UIKit

/// `UIApplicationDelegate` replacing the previous SwiftUI `@main struct
/// Markus_v3App: App` host. The swap is structural: `UIDocumentBrowserViewController`
/// must be the window's root view controller (per Apple's docs) and SwiftUI
/// `DocumentGroup` did not expose the three control points the
/// resume-and-create-2 feature requires (deferred-write create, last-
/// directory-targeted create, zero-browser-flash resume). See
/// `features/resume-and-create-2/design.md` "Architectural decision" for
/// the full reasoning and the adversarial findings F-001/F-002/F-003 the
/// swap resolves.
///
/// Scene configuration is supplied programmatically (no Info.plist change
/// needed): the AppDelegate's `configurationForConnecting` method vends a
/// `UISceneConfiguration` pointed at `SceneDelegate`, which in turn
/// installs `BrowserHostController` as the window root.
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        true
    }

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: "Default Configuration",
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }

    #if targetEnvironment(macCatalyst)
    /// mac-catalyst-shell-14 T-002 — Catalyst menu-bar reshape (Component A).
    /// Defers to `CatalystMenuBuilder` to construct the File / Edit / View
    /// structure; each Markus item is a UIKeyCommand whose action resolves on
    /// the responder chain (S-1: enablement is structural).
    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        CatalystMenuBuilder.build(with: builder)
    }
    #endif
}
