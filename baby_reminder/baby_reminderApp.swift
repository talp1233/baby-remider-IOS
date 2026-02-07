import SwiftUI
import SwiftData
import UserNotifications

// MARK: - Notification Delegate

class AppNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {

    // Called when user taps on a notification action
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let category = response.notification.request.content.categoryIdentifier
        let action = response.actionIdentifier

        if category == "CHILDREN_IN_CAR" {
            if action == "YES_CHILDREN" {
                // User confirmed children are in the car -> enter drive mode
                AppState.shared.driveStatus = .driveMode
            } else if action == "NO_CHILDREN" {
                // User said no children -> go back to idle
                AppState.shared.driveStatus = .idle
            }

        } else if category == "REMINDER" {
            if action == "CONFIRM_CHILDREN_OUT" {
                // User confirmed children are out -> cancel all reminders, back to idle
                NotificationManager.cancelAllReminders()
                AppState.shared.driveStatus = .idle
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

// MARK: - App Entry Point

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
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    withAnimation(.easeOut(duration: 0.5)) {
                        showLaunchScreen = false
                    }
                }
            }
        }
        .modelContainer(sharedModelContainer)
        .onChange(of: scenePhase) { oldPhase, newPhase in
            switch newPhase {
            case .background:
                NotificationManager.scheduleForceQuitWarning()
            case .active:
                NotificationManager.cancelForceQuitWarning()
            default:
                break
            }
        }
    }
}
