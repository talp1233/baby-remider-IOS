//
//  baby_reminderApp.swift
//  baby_reminder
//
//  Created by Tal Peretz on 09/12/2025.
//

import SwiftUI
import SwiftData
import UserNotifications

class AppNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let category = response.notification.request.content.categoryIdentifier
        let action = response.actionIdentifier
        
        if category == "CHILDREN_IN_CAR" {
            if action == "YES_CHILDREN" {
                UserDefaults.standard.set(true, forKey: "manualResponseOverride")
            } else if action == "NO_CHILDREN" {
                UserDefaults.standard.set(false, forKey: "manualResponseOverride")
            }
        } else if category == "REMINDER" {
            if action == "YES_CHILDREN" {
                center.removeAllPendingNotificationRequests()
                UserDefaults.standard.set(false, forKey: "manualResponseOverride")
            } else if action == UNNotificationDefaultActionIdentifier {
                if let repeats = response.notification.request.content.userInfo["repeats"] as? Int {
                    let newRepeats = repeats + 1
                    if newRepeats < 10 {
                        NotificationManager.scheduleReminderNotification(repeats: newRepeats)
                    }
                }
            }
        }
        
        completionHandler()
    }
}

@main
struct baby_reminderApp: App {
    private let notificationDelegate = AppNotificationDelegate()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    UNUserNotificationCenter.current().delegate = notificationDelegate
                }
        }
        .modelContainer(sharedModelContainer)
    }
}

