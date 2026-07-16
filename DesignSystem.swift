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

    /// Opacity levels for de-emphasized content and glass-friendly highlights.
    enum Opacity {
        /// Neutral hover wash for controls on glass (day cells, toolbar
        /// icons): a translucent veil of `primary`, so it brightens on dark
        /// and shades on light without going opaque.
        static let hoverWash: Double = 0.1
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
        /// Floor for the event list's max height. The popover grows past this
        /// to fill the screen's visible height before scrolling kicks in.
        static let eventListMaxHeight: CGFloat = 360
        /// Vertical space reserved for the popover's fixed chrome (month
        /// calendar, header, toolbar, margins) when sizing the event list to
        /// the screen.
        static let popoverChromeAllowance: CGFloat = 400
        /// Width of the calendar-color accent bar in an event row.
        static let eventAccentWidth: CGFloat = 3
        /// Height of one row in the month grid — the today circle plus the
        /// dot row and its gap, with even slack above and below so the dots
        /// never kiss the next row.
        static let monthDayCellHeight: CGFloat = 28
        /// Diameter of an event dot under a day number in the month grid.
        static let monthEventDotSize: CGFloat = 3
        /// Max event dots rendered per day in the month grid.
        static let monthMaxDotsPerDay: Int = 3
        /// Diameter of the filled circle behind today's day number.
        static let monthTodayCircleSize: CGFloat = 18
        /// Point size of the go-to-today dot icon in the month header.
        static let monthTodayDotIconSize: CGFloat = 8
        /// Point size of a toolbar SF Symbol.
        static let toolbarIconSize: CGFloat = 14
        /// Square hit area of a toolbar icon button.
        static let toolbarButtonSize: CGFloat = 26
        /// Diameter of the dot on the current-time indicator line.
        static let nowDotSize: CGFloat = 5
        /// Thickness of the current-time indicator line.
        static let nowLineHeight: CGFloat = 1
        /// Diameter of the calendar-color dot in Settings rows.
        static let calendarDotSize: CGFloat = 8
    }
}
