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
final class UpdateChecker: NSObject, ObservableObject {
    /// Version of a scheduled update that the app shows as a gentle reminder
    /// instead of Sparkle's alert. Always nil in the App Store build.
    @Published private(set) var pendingUpdateVersion: String?

    #if SPARKLE
    private var controller: SPUStandardUpdaterController!
    #endif

    override init() {
        super.init()
        #if SPARKLE
        // Created after super.init so the controller can take self as its
        // user-driver delegate.
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: self
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

#if SPARKLE
/// Gentle reminders. Mou Sugu has no window, so a scheduled update alert would
/// either steal focus or open behind other apps. Sparkle shows its alert only
/// when it can take focus anyway (recent launch, idle system). Otherwise the
/// menu bar shows a quiet indicator, and the alert opens when the user clicks it.
extension UpdateChecker: SPUStandardUserDriverDelegate {
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        immediateFocus
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        guard !handleShowingUpdate else { return }
        let version = update.displayVersionString
        MainActor.assumeIsolated { pendingUpdateVersion = version }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        MainActor.assumeIsolated { pendingUpdateVersion = nil }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated { pendingUpdateVersion = nil }
    }
}
#endif
