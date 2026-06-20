import SwiftUI

/// Apple HIG-aligned design tokens.
///
/// Single source of truth for spacing, sizing, corner radii, and other layout
/// constants used across the app. Always reference these tokens from views
/// instead of using raw literal values, so the UI stays consistent with
/// Apple's 4pt-grid conventions and adapts in one place.
///
/// References:
/// - macOS HIG — Layout: <https://developer.apple.com/design/human-interface-guidelines/layout>
/// - macOS HIG — The menu bar: <https://developer.apple.com/design/human-interface-guidelines/the-menu-bar>
/// - AppKit default layout margin is 8pt; widgets use 16pt (11pt compact).
///   Menu bar popovers and Notification Center widgets favor the compact end
///   of that range to keep information density high.
enum DesignSystem {
    /// 4pt-grid spacing tokens.
    ///
    /// All vertical/horizontal padding and stack spacing must come from here.
    enum Spacing {
        /// 2pt — separates tightly coupled labels (e.g. title/subtitle in a row).
        static let xxs: CGFloat = 2
        /// 4pt — base grid unit.
        static let xs: CGFloat = 4
        /// 6pt — compact vertical row padding (menu-bar idiomatic).
        static let sm: CGFloat = 6
        /// 8pt — AppKit's default layout margin; standard horizontal row inset.
        static let md: CGFloat = 8
        /// 12pt — section header padding and grouped element spacing.
        static let lg: CGFloat = 12
        /// 16pt — standard widget margin (per HIG).
        static let xl: CGFloat = 16
        /// 20pt — large window margin / generous vertical padding.
        static let xxl: CGFloat = 20
    }

    /// Corner radii tuned to match Apple's small-control rounding.
    enum Radius {
        /// 4pt — accent bars, pills.
        static let xs: CGFloat = 4
        /// 6pt — row hover backgrounds.
        static let sm: CGFloat = 6
        /// 8pt — small containers.
        static let md: CGFloat = 8
        /// 12pt — Control-Center-style cards.
        static let lg: CGFloat = 12
    }

    /// Layout dimensions specific to this app's chrome.
    enum Layout {
        /// Width of the menu bar popover.
        static let popoverWidth: CGFloat = 300
        /// Height of the Settings pane.
        static let settingsHeight: CGFloat = 400
        /// Max height of the event list before scrolling kicks in.
        static let eventListMaxHeight: CGFloat = 360
        /// Width of the calendar-color accent bar in an event row.
        static let eventAccentWidth: CGFloat = 3
        /// Diameter of the calendar-color dot in Settings rows.
        static let calendarDotSize: CGFloat = 8
    }
}
