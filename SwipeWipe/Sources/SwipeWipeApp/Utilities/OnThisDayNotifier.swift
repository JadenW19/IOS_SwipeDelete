//
//  OnThisDayNotifier.swift
//  SwipeWipeApp
//
//  Schedules daily local notifications such as "50 photos to look back on today".
//  Local notifications can't compute counts at delivery time, so the next two weeks are
//  scheduled with precomputed counts each time the library loads.
//

import Foundation
import SwipeWipeCore

#if canImport(UserNotifications)
import UserNotifications

enum OnThisDayNotifier {

    private static let idPrefix = "swipewipe.onthisday."
    private static let daysAhead = 14

    static func scheduleUpcoming(buckets: [MonthlyBucket]) async {
        let center = UNUserNotificationCenter.current()

        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
        let granted = await center.notificationSettings().authorizationStatus
        guard granted == .authorized || granted == .provisional else { return }

        // Remove previously scheduled reminders, then rebuild.
        let pending = await center.pendingNotificationRequests()
        let old = pending.map(\.identifier).filter { $0.hasPrefix(idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: old)

        let calendar = Calendar.current
        let now = Date()

        for offset in 0..<daysAhead {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)) else { continue }

            var fire = calendar.dateComponents([.year, .month, .day], from: day)
            fire.hour = 9
            fire.minute = 0
            guard let fireDate = calendar.date(from: fire), fireDate > now else { continue }

            let count = OnThisDay.assets(in: buckets, on: day, calendar: calendar).count
            guard count > 0 else { continue }

            let content = UNMutableNotificationContent()
            content.title = "On This Day"
            content.body = count == 1
                ? "1 photo to look back on today."
                : "\(count) photos to look back on today."
            content.sound = .default

            let trigger = UNCalendarNotificationTrigger(dateMatching: fire, repeats: false)
            let request = UNNotificationRequest(
                identifier: idPrefix + OnThisDay.completionKey(for: day, calendar: calendar),
                content: content,
                trigger: trigger
            )
            try? await center.add(request)
        }
    }
}
#else
enum OnThisDayNotifier {
    static func scheduleUpcoming(buckets: [MonthlyBucket]) async {}
}
#endif
