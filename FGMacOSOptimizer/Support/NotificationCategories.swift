import Foundation
import UserNotifications

/// Registers every notification category in one call. `setNotificationCategories`
/// replaces the whole set, so separate per-engine registrations used to wipe each other.
enum NotificationCategories {
    static let smartRAMCategoryID = "FG_SMART_RAM"

    @MainActor
    static func registerAll() {
        let review = UNNotificationAction(
            identifier: SmartCareScheduler.reviewActionID,
            title: "Review in Cleaner",
            options: [.foreground]
        )
        let smartCare = UNNotificationCategory(
            identifier: SmartCareScheduler.categoryID,
            actions: [review],
            intentIdentifiers: [],
            options: []
        )

        let kill = UNNotificationAction(
            identifier: WatchdogEngine.killActionID,
            title: "Kill Now",
            options: [.destructive, .authenticationRequired]
        )
        let hog = UNNotificationCategory(
            identifier: WatchdogEngine.killCategoryID,
            actions: [kill],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        let smartRAM = UNNotificationCategory(
            identifier: smartRAMCategoryID,
            actions: [],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([smartCare, hog, smartRAM])
    }
}
