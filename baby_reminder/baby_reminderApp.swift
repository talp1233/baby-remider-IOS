import SwiftUI
import SwiftData
import UserNotifications

class AppNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
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

    // Show notifications even when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

@main
struct baby_reminderApp: App {
    private let notificationDelegate = AppNotificationDelegate()
    @State private var showLaunchScreen = true
    @Environment(\.scenePhase) private var scenePhase

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([Item.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .opacity(showLaunchScreen ? 0 : 1)

                if showLaunchScreen {
                    LaunchScreenView()
                        .transition(.opacity)
                }
            }
            .onAppear {
                UNUserNotificationCenter.current().delegate = notificationDelegate
                // Dismiss launch screen after 2.5 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    withAnimation(.easeOut(duration: 0.5)) {
                        showLaunchScreen = false
                    }
                }
            }
        }
        .modelContainer(sharedModelContainer)
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .background:
                // Schedule force-quit warning when app goes to background
                NotificationManager.scheduleForceQuitWarning()
            case .active:
                // Cancel force-quit warning when app returns to foreground
                NotificationManager.cancelForceQuitWarning()
            default:
                break
            }
        }
    }
}
