import SwiftUI
import Combine
#if SPARKLE
import Sparkle
#endif

/// Wrapper around Sparkle's `SPUStandardUpdaterController` so the rest of the
/// app can ask for updates without conditional-compilation noise.
///
/// Sparkle only ships in the direct/DMG channel — the Mac App Store rejects
/// apps that bundle their own updater. The `SPARKLE` condition is set in
/// `Config/App-Direct.xcconfig`; the App Store target never defines it, so this
/// class compiles down to `isAvailable == false` and the "Check for updates…"
/// entry disappears.
///
/// The condition is an explicit flag rather than `canImport(Sparkle)` on
/// purpose: `canImport` resolves against the framework search path, and
/// `BUILT_PRODUCTS_DIR` is on every target's path. It would answer `true` in the
/// App Store target whenever the direct target had been built first, silently
/// linking a framework that is never embedded.
@MainActor
final class UpdateChecker: ObservableObject {
    // Required because the class has no `@Published` storage to drive the
    // default synthesized publisher; `isAvailable` is static-by-compilation
    // so it never actually emits, but conforming to `ObservableObject` lets us
    // use `@StateObject` for lifecycle.
    let objectWillChange = ObservableObjectPublisher()

    #if SPARKLE
    private let controller: SPUStandardUpdaterController
    #endif

    init() {
        #if SPARKLE
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
        #if SPARKLE
        return true
        #else
        return false
        #endif
    }

    /// Triggers Sparkle's standard "Check for Updates…" dialog.
    func checkForUpdates() {
        #if SPARKLE
        controller.checkForUpdates(nil)
        #endif
    }
}
