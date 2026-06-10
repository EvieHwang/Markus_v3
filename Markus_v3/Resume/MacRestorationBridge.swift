import Foundation
import UIKit

/// Mac single-window state-restoration bridge (mac-catalyst-shell-14, design
/// Component D — `MacRestorationBridge`). The Mac scene-restoration entry hands
/// control to the EXISTING resume decision: the OS-driven scene wakeup routes
/// into `host.initialResumeAction` → `LaunchResumeBranch.resume(into:)` →
/// `LastFileStore.resolveLastOpened()` (security-scoped bookmark, path
/// fallback).
///
/// **No new persistence store and no new recovery UI.** The OS may persist
/// window/scene chrome, but the DOCUMENT IDENTITY is always resolved by the
/// existing `LastFileStore` bookmark/path resolution — never a new Mac-only
/// store (FM-3, S-6). The bridge restores a single window/document (C-5.2,
/// FM-8), the same file resolved the same way as iOS/iPad resume (C-5.3).
///
/// Edge cases inherit the existing fail-closed behavior unchanged: a moved
/// file retargets via the bookmark; a deleted file (or first-ever launch)
/// resolves nothing and the app lands on the browser with NO error UI (C-5.4,
/// C-5.5). A restored document enters the unchanged conflict/deletion/save
/// lifecycle (C-5.6, FM-7).
///
/// On iOS/iPadOS the existing inline `LaunchResumeBranch.resume(into:)` call
/// in `SceneDelegate` is the resume path; on Mac Catalyst it is routed through
/// this bridge so the seam name matches the architectural decision and the
/// "single static entry, no state" shape is structurally enforced (`enum` is
/// caseless / non-instantiable).
enum MacRestorationBridge {

    /// S-6 — the bridge declares that the document choice is made by
    /// `LaunchResumeBranch.resume(into:)`, not by a Mac-only store.
    static let documentChoiceSource: DocumentChoiceSource = .launchResumeBranch

    /// FM-3 — the bridge persists no Mac-only document identity. Window/scene
    /// chrome is the OS's concern; document identity is `LastFileStore`'s.
    static let persistsDocumentIdentity = false

    /// Mac scene-restoration entry point. Defers entirely to the existing
    /// `LaunchResumeBranch.resume(into:)` decision (which reads `LastFileStore`
    /// — bookmark, path fallback). Returns true if a document was restored;
    /// false if the app lands on the browser (first launch / moved / deleted /
    /// unresolvable — fail-closed, no error UI).
    @MainActor
    @discardableResult
    static func restore(into host: BrowserHostController,
                        store: LastFileStore = LastFileStore()) -> Bool {
        LaunchResumeBranch.resume(into: host, store: store)
    }

    /// S-6 / FM-3 — names the single architectural fact the bridge enforces:
    /// the document choice comes from `LaunchResumeBranch`, never from a
    /// Mac-only identity store.
    enum DocumentChoiceSource: Equatable {
        case launchResumeBranch
    }
}
