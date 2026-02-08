import SwiftUI
import SwiftData
import UserNotifications
import UIKit

// MARK: - Force-Quit Detector
// Uses a background task to keep rescheduling the notification while the app is alive.
// Only when the app is truly killed (force-quit), the notification fires.

class ForceQuitDetector {
    static let shared = ForceQuitDetector()

    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var timer: Timer?

    private init() {}

    func appDidEnterBackground() {
        // Start background task to keep the app alive briefly
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            // Background time expiring - app will be suspended soon
            // Schedule a final notification with longer delay
            // This only fires if the app is killed while suspended
            NotificationManager.scheduleForceQuitWarning(delay: 30)
            self?.endBackgroundTask()
        }

        // While alive in background, keep rescheduling the notification
        // so it never fires as long as the app is running
        startReschedulingLoop()
    }

    func appDidBecomeActive() {
        // User came back - cancel everything
        NotificationManager.cancelForceQuitWarning()
        stopReschedulingLoop()
        endBackgroundTask()
    }

    private func startReschedulingLoop() {
        // Schedule notification 20 seconds from now
        NotificationManager.scheduleForceQuitWarning(delay: 20)

        // Every 10 seconds, push the notification further into the future
        // As long as this timer runs, the notification never fires
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
            NotificationManager.scheduleForceQuitWarning(delay: 20)
        }
    }

    private func stopReschedulingLoop() {
        timer?.invalidate()
        timer = nil
    }

    private func endBackgroundTask() {
        stopReschedulingLoop()
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }
}

// MARK: - Notification Delegate

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
                AppState.shared.driveStatus = .driveMode
            } else if action == "NO_CHILDREN" {
                AppState.shared.driveStatus = .idle
            }
        } else if category == "REMINDER" {
            if action == "CONFIRM_CHILDREN_OUT" {
                NotificationManager.cancelAllReminders()
                AppState.shared.driveStatus = .idle
            }
        }

        completionHandler()
    }

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
                ForceQuitDetector.shared.appDidEnterBackground()
            case .active:
                ForceQuitDetector.shared.appDidBecomeActive()
            default:
                break
            }
        }
    }
}
