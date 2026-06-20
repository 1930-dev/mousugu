import SwiftUI
import Combine
#if canImport(Sparkle)
import Sparkle
#endif

/// Wrapper around Sparkle's `SPUStandardUpdaterController` so the rest of the
/// app can ask for updates without conditional-compilation noise.
///
/// The whole class compiles unconditionally — when the Sparkle SPM package
/// isn't present yet, `canCheckForUpdates` returns `false` and the UI hides
/// the "Check for updates…" entry. After running
/// File → Add Package Dependencies… and pulling in
/// `https://github.com/sparkle-project/Sparkle`, the `#if canImport(Sparkle)`
/// blocks activate and the updater is fully wired up — no code changes
/// elsewhere.
///
/// To actually ship updates, also set these keys in the target's Info.plist:
///   • `SUFeedURL` — URL of your appcast XML
///   • `SUPublicEDKey` — base64 public Ed25519 key (generate via Sparkle's
///     bundled `generate_keys` tool when you cut your first release).
@MainActor
final class UpdateChecker: ObservableObject {
    // Required because the class has no `@Published` storage to drive the
    // default synthesized publisher; `isAvailable` is static-by-compilation
    // (set by `#if canImport`) so it never actually emits, but conforming to
    // `ObservableObject` lets us use `@StateObject` for lifecycle.
    let objectWillChange = ObservableObjectPublisher()

    #if canImport(Sparkle)
    private let controller: SPUStandardUpdaterController
    #endif

    init() {
        #if canImport(Sparkle)
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        #endif
    }

    /// `true` once Sparkle is linked. Drives the visibility of the
    /// "Check for updates…" menu entry.
    var isAvailable: Bool {
        #if canImport(Sparkle)
        return true
        #else
        return false
        #endif
    }

    /// Triggers Sparkle's standard "Check for Updates…" dialog.
    func checkForUpdates() {
        #if canImport(Sparkle)
        controller.checkForUpdates(nil)
        #endif
    }
}
