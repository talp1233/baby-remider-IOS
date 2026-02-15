import SwiftUI
import SwiftData
import UserNotifications
import UIKit
import AVFoundation

// MARK: - Background Audio Manager
// Plays silent audio to keep the app alive in background.
// This allows routeChangeNotification to fire when BT connects/disconnects.

class BackgroundAudioManager {
    static let shared = BackgroundAudioManager()
    private var audioPlayer: AVAudioPlayer?

    private init() {}

    func startBackgroundAudio() {
        // Don't restart if already playing
        if audioPlayer?.isPlaying == true { return }

        let silentWAV = generateSilentWAV(durationSeconds: 1, sampleRate: 8000)
        do {
            audioPlayer = try AVAudioPlayer(data: silentWAV)
            audioPlayer?.numberOfLoops = -1 // Loop forever
            audioPlayer?.volume = 0.01      // Near-silent
            audioPlayer?.play()
        } catch {
            // Silently fail
        }
    }

    func stopBackgroundAudio() {
        audioPlayer?.stop()
        audioPlayer = nil
    }

    /// Generate a minimal WAV file with silence
    private func generateSilentWAV(durationSeconds: Double, sampleRate: Int) -> Data {
        let numSamples = Int(Double(sampleRate) * durationSeconds)
        let dataSize = numSamples * 2 // 16-bit = 2 bytes per sample
        let fileSize = 36 + dataSize

        var data = Data()

        // RIFF header
        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        data.append(contentsOf: withUnsafeBytes(of: UInt32(fileSize).littleEndian) { Array($0) })
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"

        // fmt chunk
        data.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) }) // chunk size
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })  // PCM format
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })  // 1 channel (mono)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Array($0) }) // sample rate
        data.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate * 2).littleEndian) { Array($0) }) // byte rate
        data.append(contentsOf: withUnsafeBytes(of: UInt16(2).littleEndian) { Array($0) })  // block align
        data.append(contentsOf: withUnsafeBytes(of: UInt16(16).littleEndian) { Array($0) }) // bits per sample

        // data chunk
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        data.append(contentsOf: withUnsafeBytes(of: UInt32(dataSize).littleEndian) { Array($0) })
        data.append(Data(count: dataSize)) // silence = all zeros

        return data
    }
}

// MARK: - Force-Quit Detector
// Uses a background task to keep rescheduling the notification while the app is alive.
// Only when the app is truly killed (force-quit), the notification fires.

class ForceQuitDetector {
    static let shared = ForceQuitDetector()

    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var timer: Timer?

    private init() {}

    func appDidEnterBackground() {
        // Start silent audio to keep the app alive in background
        BackgroundAudioManager.shared.startBackgroundAudio()

        // Also start a background task as fallback
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            NotificationManager.scheduleForceQuitWarning(delay: 30)
            self?.endBackgroundTask()
        }

        // While alive in background, keep rescheduling the force-quit notification
        startReschedulingLoop()
    }

    func appDidBecomeActive() {
        // User came back - cancel everything
        NotificationManager.cancelForceQuitWarning()
        stopReschedulingLoop()
        endBackgroundTask()
        // Note: don't stop background audio - we want it always running
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
                // Start silent audio to keep app alive for BT monitoring
                BackgroundAudioManager.shared.startBackgroundAudio()
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
