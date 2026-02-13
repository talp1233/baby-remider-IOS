import SwiftUI
import UserNotifications
import Combine
import AVFoundation
import ExternalAccessory

// MARK: - Drive Status

enum DriveStatus: String {
    case idle               // No car connected
    case waitingForResponse // Car connected, waiting for user to confirm children
    case driveMode          // Children confirmed in car, monitoring
    case reminding          // Car disconnected, reminding user to check children
}

// MARK: - App State (shared between notification delegate and views)

class AppState: ObservableObject {
    static let shared = AppState()

    @Published var driveStatus: DriveStatus = .idle

    private init() {}
}

// MARK: - Models

struct AutoResponseTimeWindow: Identifiable, Codable, Equatable {
    let id: UUID
    var weekday: Int // 1=Sunday ... 7=Saturday
    var startHour: Int
    var startMinute: Int
    var endHour: Int
    var endMinute: Int
}

struct BluetoothDevice: Identifiable, Equatable, Codable {
    let id: UUID
    var name: String
}

// MARK: - Audio Route Monitor

class AudioRouteMonitor: ObservableObject {
    @Published var deviceConnected: String? = nil
    @Published var isCarPlayConnected: Bool = false
    private var userDeviceNames: [String]
    private var routeObserver: NSObjectProtocol?
    private var carPlayConnectObserver: NSObjectProtocol?
    private var carPlayDisconnectObserver: NSObjectProtocol?
    private var accessoryObserver: NSObjectProtocol?
    private weak var appState: AppState?
    private weak var settingsStore: SettingsStore?

    init(deviceNames: [String], appState: AppState, settingsStore: SettingsStore) {
        self.userDeviceNames = deviceNames
        self.appState = appState
        self.settingsStore = settingsStore

        // Configure and activate audio session so we receive route change notifications
        configureAudioSession()

        updateCurrentRoute()

        // Monitor audio route changes (BT connect/disconnect)
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.updateCurrentRoute()
        }

        // Monitor CarPlay scene connections
        carPlayConnectObserver = NotificationCenter.default.addObserver(
            forName: UIScene.willConnectNotification,
            object: nil, queue: .main
        ) { [weak self] notification in
            if let scene = notification.object as? UIScene,
               scene.session.role == .carTemplateApplication {
                self?.isCarPlayConnected = true
                self?.handleCarPlayConnection()
            }
        }

        carPlayDisconnectObserver = NotificationCenter.default.addObserver(
            forName: UIScene.didDisconnectNotification,
            object: nil, queue: .main
        ) { [weak self] notification in
            if let scene = notification.object as? UIScene,
               scene.session.role == .carTemplateApplication {
                self?.isCarPlayConnected = false
                self?.handleCarPlayDisconnection()
            }
        }

        // Monitor external accessories (some car systems appear as accessories)
        accessoryObserver = NotificationCenter.default.addObserver(
            forName: .EAAccessoryDidConnect,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.updateCurrentRoute()
        }

        // Also re-activate audio session when app becomes active (in case it was deactivated)
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.configureAudioSession()
        }

        // Check if CarPlay is already connected at launch
        checkExistingCarPlaySessions()
    }

    func updateDeviceNames(_ names: [String]) {
        self.userDeviceNames = names
        updateCurrentRoute()
    }

    deinit {
        if let o = routeObserver { NotificationCenter.default.removeObserver(o) }
        if let o = carPlayConnectObserver { NotificationCenter.default.removeObserver(o) }
        if let o = carPlayDisconnectObserver { NotificationCenter.default.removeObserver(o) }
        if let o = accessoryObserver { NotificationCenter.default.removeObserver(o) }
    }

    // MARK: - Audio Session Configuration

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            // Use .playback category with BT options to receive route change notifications
            // .mixWithOthers prevents interrupting other audio apps
            try session.setCategory(
                .playback,
                mode: .default,
                options: [.allowBluetooth, .allowBluetoothA2DP, .mixWithOthers]
            )
            try session.setActive(true, options: [.notifyOthersOnDeactivation])
        } catch {
            // Silently fail - route monitoring may still work via notifications
        }
    }

    // MARK: - CarPlay Helpers

    private func checkExistingCarPlaySessions() {
        for session in UIApplication.shared.openSessions {
            if session.role == .carTemplateApplication {
                isCarPlayConnected = true
                break
            }
        }
    }

    private func handleCarPlayConnection() {
        if deviceConnected == nil {
            let oldValue = deviceConnected
            deviceConnected = "CarPlay"
            handleDeviceConnectionChange(from: oldValue, to: "CarPlay")
        }
    }

    private func handleCarPlayDisconnection() {
        if deviceConnected == "CarPlay" {
            let oldValue = deviceConnected
            deviceConnected = nil
            // Check if there's still a BT audio device connected
            updateCurrentRoute()
            if deviceConnected == nil {
                handleDeviceConnectionChange(from: oldValue, to: nil)
            }
        }
    }

    // MARK: - Route Detection

    private func updateCurrentRoute() {
        let session = AVAudioSession.sharedInstance()
        let outputs = session.currentRoute.outputs
        let oldValue = deviceConnected

        // First, check if any output matches user's listed device names
        if let match = outputs.first(where: { userDeviceNames.contains($0.portName) }) {
            deviceConnected = match.portName
        } else if let carPlayOutput = outputs.first(where: { $0.portType == .carAudio }) {
            // Always detect CarPlay / car audio connections
            deviceConnected = carPlayOutput.portName
        } else if isCarPlayConnected {
            // CarPlay scene is connected even if no audio route yet
            deviceConnected = "CarPlay"
        } else if userDeviceNames.isEmpty, let specialOutput = outputs.first(where: {
            // Only detect any BT audio when user hasn't listed specific devices
            $0.portType == .usbAudio ||
            $0.portType == .bluetoothA2DP ||
            $0.portType == .bluetoothHFP ||
            $0.portType == .bluetoothLE
        }) {
            deviceConnected = specialOutput.portName
        } else {
            deviceConnected = nil
        }

        // Trigger connection change logic if device status changed
        if oldValue != deviceConnected {
            handleDeviceConnectionChange(from: oldValue, to: deviceConnected)
        }
    }

    // MARK: - Connection State Machine (runs in background too)

    private func handleDeviceConnectionChange(from oldValue: String?, to newValue: String?) {
        guard let appState = appState else { return }

        if oldValue == nil && newValue != nil {
            // --- DEVICE CONNECTED ---
            // Cancel any active reminders from a previous trip
            if appState.driveStatus == .reminding {
                NotificationManager.cancelAllReminders()
            }
            DispatchQueue.main.async {
                appState.driveStatus = .waitingForResponse
            }
            NotificationManager.scheduleChildrenInCarNotification()

        } else if oldValue != nil && newValue == nil {
            // --- DEVICE DISCONNECTED ---
            NotificationManager.cancelChildrenInCarNotification()

            switch appState.driveStatus {
            case .driveMode:
                // User confirmed children in car -> now disconnected -> send reminders
                DispatchQueue.main.async {
                    appState.driveStatus = .reminding
                }
                NotificationManager.scheduleAllReminders()

            case .waitingForResponse:
                // User didn't respond -> use auto-response
                if settingsStore?.shouldAutoRespondYes() == true {
                    DispatchQueue.main.async {
                        appState.driveStatus = .reminding
                    }
                    NotificationManager.scheduleAllReminders()
                } else {
                    DispatchQueue.main.async {
                        appState.driveStatus = .idle
                    }
                }

            default:
                // idle or already reminding -> just go idle
                DispatchQueue.main.async {
                    appState.driveStatus = .idle
                }
            }
        }
    }
}

// MARK: - Notification Manager

struct NotificationManager {
    static var isMuted: Bool = false
    private static let loc = LocalizationManager.shared

    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        registerCategories()
    }

    // MARK: First notification - "Are children in the car?"
    static func scheduleChildrenInCarNotification() {
        let content = UNMutableNotificationContent()
        content.title = loc.s("childrenInCarTitle")
        content.subtitle = loc.s("notificationSubtitle")
        content.body = loc.s("childrenInCarBody")
        content.categoryIdentifier = "CHILDREN_IN_CAR"
        content.sound = isMuted ? nil : UNNotificationSound.default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "children_in_car", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    static func cancelChildrenInCarNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["children_in_car"])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["children_in_car"])
    }

    // MARK: Reminder notifications - "Did you take the children out?"
    static func scheduleAllReminders() {
        for i in 0..<10 {
            let content = UNMutableNotificationContent()
            content.title = loc.s("reminderTitle")
            content.subtitle = loc.s("notificationSubtitle")
            content.body = loc.s("reminderBody")
            content.categoryIdentifier = "REMINDER"
            content.userInfo = ["reminderIndex": i]
            content.sound = isMuted ? nil : UNNotificationSound.default

            // First one after 1 second, then every 60 seconds
            let timeInterval = (i == 0) ? 1.0 : TimeInterval(i * 60)
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)
            let request = UNNotificationRequest(identifier: "reminder_\(i)", content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request)
        }
    }

    static func cancelAllReminders() {
        let identifiers = (0..<10).map { "reminder_\($0)" }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    // MARK: Force-quit warning
    static func scheduleForceQuitWarning(delay: TimeInterval = 20) {
        // Cancel previous one before rescheduling
        cancelForceQuitWarning()

        let content = UNMutableNotificationContent()
        content.title = loc.s("forceQuitTitle")
        content.subtitle = loc.s("notificationSubtitle")
        content.body = loc.s("forceQuitBody")
        content.sound = UNNotificationSound.default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        let request = UNNotificationRequest(identifier: "force_quit_warning", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    static func cancelForceQuitWarning() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["force_quit_warning"])
    }

    // MARK: Register notification categories with action buttons
    static func registerCategories() {
        // Category: "Are children in the car?" -> Yes / No
        let yesAction = UNNotificationAction(
            identifier: "YES_CHILDREN",
            title: loc.s("yesChildrenAction"),
            options: []
        )
        let noAction = UNNotificationAction(
            identifier: "NO_CHILDREN",
            title: loc.s("noChildrenAction"),
            options: []
        )
        let childrenCategory = UNNotificationCategory(
            identifier: "CHILDREN_IN_CAR",
            actions: [yesAction, noAction],
            intentIdentifiers: [],
            options: []
        )

        // Category: "Did you take children out?" -> Yes
        let confirmAction = UNNotificationAction(
            identifier: "CONFIRM_CHILDREN_OUT",
            title: loc.s("yesAction"),
            options: []
        )
        let reminderCategory = UNNotificationCategory(
            identifier: "REMINDER",
            actions: [confirmAction],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([childrenCategory, reminderCategory])
    }
}

// MARK: - Settings Store

class SettingsStore: ObservableObject {
    @Published var devices: [BluetoothDevice] {
        didSet { saveDevices() }
    }
    @Published var isMuted: Bool {
        didSet {
            UserDefaults.standard.set(isMuted, forKey: "isMuted")
            NotificationManager.isMuted = isMuted
        }
    }
    @Published var autoResponse: String {
        didSet { UserDefaults.standard.set(autoResponse, forKey: "autoResponse") }
    }
    @Published var autoResponseTimeWindows: [AutoResponseTimeWindow] {
        didSet { saveTimeWindows() }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: "devices"),
           let decoded = try? JSONDecoder().decode([BluetoothDevice].self, from: data) {
            devices = decoded
        } else {
            devices = []
        }
        isMuted = UserDefaults.standard.bool(forKey: "isMuted")

        // Migration from Hebrew values
        let storedResponse = UserDefaults.standard.string(forKey: "autoResponse") ?? "yes"
        if storedResponse == "כן" {
            autoResponse = "yes"
        } else if storedResponse == "לא" {
            autoResponse = "no"
        } else {
            autoResponse = storedResponse
        }

        if let data = UserDefaults.standard.data(forKey: "autoResponseTimeWindows"),
           let decoded = try? JSONDecoder().decode([AutoResponseTimeWindow].self, from: data) {
            autoResponseTimeWindows = decoded
        } else {
            autoResponseTimeWindows = []
        }
        NotificationManager.isMuted = isMuted
    }

    /// Check if auto-response should be "yes" based on settings and current time
    func shouldAutoRespondYes() -> Bool {
        if autoResponse == "yes" { return true }

        // Default is "no" - check time windows
        let now = Date()
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: now)
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let currentMinutes = hour * 60 + minute

        for window in autoResponseTimeWindows {
            if window.weekday == weekday {
                let start = window.startHour * 60 + window.startMinute
                let end = window.endHour * 60 + window.endMinute
                if currentMinutes >= start && currentMinutes <= end {
                    return true
                }
            }
        }
        return false
    }

    private func saveDevices() {
        if let data = try? JSONEncoder().encode(devices) {
            UserDefaults.standard.set(data, forKey: "devices")
        }
    }

    private func saveTimeWindows() {
        if let data = try? JSONEncoder().encode(autoResponseTimeWindows) {
            UserDefaults.standard.set(data, forKey: "autoResponseTimeWindows")
        }
    }
}

// MARK: - Theme Colors

extension Color {
    static let babyOrange = Color(red: 1.0, green: 0.55, blue: 0.10)
    static let babyAmber = Color(red: 1.0, green: 0.65, blue: 0.15)
    static let babyRed = Color(red: 0.90, green: 0.22, blue: 0.20)
    static let safeGreen = Color(red: 0.18, green: 0.75, blue: 0.35)
    static let cardBackground = Color(UIColor.secondarySystemGroupedBackground)
    static let screenBackground = Color(UIColor.systemGroupedBackground)
}

// MARK: - Content View

struct ContentView: View {
    @State private var showSettings = false
    @State private var showLegal = false
    @StateObject private var settingsStore = SettingsStore()
    @StateObject private var audioRouteMonitor: AudioRouteMonitor
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var loc = LocalizationManager.shared

    init() {
        let store = SettingsStore()
        _settingsStore = StateObject(wrappedValue: store)
        _audioRouteMonitor = StateObject(wrappedValue: AudioRouteMonitor(
            deviceNames: store.devices.map(\.name),
            appState: AppState.shared,
            settingsStore: store
        ))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    headerSection
                    warningBanner
                    statusCard
                    languageCard
                    actionButtons
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(Color.screenBackground)
            .navigationDestination(isPresented: $showSettings) {
                SettingsView(settingsStore: settingsStore)
                    .environmentObject(loc)
            }
            .navigationDestination(isPresented: $showLegal) {
                LegalView()
                    .environmentObject(loc)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .foregroundColor(.babyOrange)
                    }
                    .accessibilityLabel(loc.s("settings"))
                }
            }
            .onAppear {
                NotificationManager.requestAuthorization()
            }
            .onChange(of: settingsStore.devices) { _, newDevices in
                audioRouteMonitor.updateDeviceNames(newDevices.map(\.name))
            }
        }
        .environment(\.layoutDirection, loc.layoutDirection)
    }

    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.babyOrange, .babyAmber],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                    .shadow(color: .babyOrange.opacity(0.3), radius: 10, y: 5)

                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundColor(.white)
            }

            Text("Baby Reminder")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            Text(loc.s("appSubtitle"))
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    // MARK: - Warning Banner
    private var warningBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 24))
                .foregroundColor(.white)

            VStack(alignment: loc.alignment, spacing: 4) {
                Text(loc.s("warningTitle"))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text(loc.s("warningMessage"))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.95))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [.babyRed, Color(red: 0.80, green: 0.15, blue: 0.15)],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .cornerRadius(16)
        .shadow(color: .babyRed.opacity(0.3), radius: 8, y: 4)
    }

    // MARK: - Status Card (4 states)
    private var statusCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                // Status icon
                ZStack {
                    Circle()
                        .fill(statusIconBackgroundColor.opacity(0.15))
                        .frame(width: 50, height: 50)

                    Image(systemName: statusIconName)
                        .font(.system(size: 24))
                        .foregroundColor(statusIconBackgroundColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(statusTitle)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(statusIconBackgroundColor)

                    Text(statusSubtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Animated pulse indicator
                if appState.driveStatus == .driveMode || appState.driveStatus == .reminding {
                    Circle()
                        .fill(statusIconBackgroundColor)
                        .frame(width: 12, height: 12)
                        .overlay(
                            Circle()
                                .stroke(statusIconBackgroundColor.opacity(0.4), lineWidth: 4)
                                .scaleEffect(2.0)
                                .opacity(0)
                                .animation(
                                    .easeOut(duration: 1.5).repeatForever(autoreverses: false),
                                    value: appState.driveStatus
                                )
                        )
                }
            }

            Divider()

            // Connected device row
            HStack(spacing: 10) {
                Image(systemName: audioRouteMonitor.deviceConnected != nil
                    ? "antenna.radiowaves.left.and.right"
                    : "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: 16))
                    .foregroundColor(audioRouteMonitor.deviceConnected != nil ? .babyOrange : .gray)

                Text(loc.s("connectedDevice"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)

                Spacer()

                Text(audioRouteMonitor.deviceConnected ?? loc.s("noDeviceConnected"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(audioRouteMonitor.deviceConnected != nil ? .primary : .secondary)
            }
        }
        .padding(20)
        .background(Color.cardBackground)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 8, y: 2)
    }

    // MARK: Status card helpers
    private var statusIconName: String {
        switch appState.driveStatus {
        case .idle: return "shield.slash.fill"
        case .waitingForResponse: return "questionmark.circle.fill"
        case .driveMode: return "shield.checkmark.fill"
        case .reminding: return "exclamationmark.triangle.fill"
        }
    }

    private var statusIconBackgroundColor: Color {
        switch appState.driveStatus {
        case .idle: return .gray
        case .waitingForResponse: return .babyOrange
        case .driveMode: return .safeGreen
        case .reminding: return .babyRed
        }
    }

    private var statusTitle: String {
        switch appState.driveStatus {
        case .idle: return loc.s("protectionInactive")
        case .waitingForResponse: return loc.s("waitingForResponse")
        case .driveMode: return loc.s("protectionActive")
        case .reminding: return loc.s("reminderActive")
        }
    }

    private var statusSubtitle: String {
        switch appState.driveStatus {
        case .idle: return loc.s("notInDriveMode")
        case .waitingForResponse: return loc.s("connectedToCar")
        case .driveMode: return loc.s("childrenInCarMonitoring")
        case .reminding: return loc.s("confirmChildrenOut")
        }
    }

    // MARK: - Language Card
    private var languageCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "globe")
                .font(.system(size: 20))
                .foregroundColor(.babyOrange)

            Text(loc.s("language"))
                .font(.system(size: 15, weight: .medium))

            Spacer()

            Menu {
                ForEach(AppLanguage.allCases) { lang in
                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            loc.currentLanguage = lang
                            NotificationManager.registerCategories()
                        }
                    } label: {
                        HStack {
                            Text(lang.displayName)
                            if loc.currentLanguage == lang {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(loc.currentLanguage.displayName)
                        .font(.system(size: 14, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(.babyOrange)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.babyOrange.opacity(0.12))
                .cornerRadius(10)
            }
        }
        .padding(16)
        .background(Color.cardBackground)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 8, y: 2)
    }

    // MARK: - Action Buttons
    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button {
                showSettings = true
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.babyOrange.opacity(0.15))
                            .frame(width: 44, height: 44)

                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.babyOrange)
                    }

                    Text(loc.s("settings"))
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)

                    Spacer()

                    Image(systemName: "chevron.forward")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding(16)
                .background(Color.cardBackground)
                .cornerRadius(16)
                .shadow(color: Color.black.opacity(0.05), radius: 8, y: 2)
            }
            .buttonStyle(.plain)

            Button {
                showLegal = true
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.gray.opacity(0.10))
                            .frame(width: 44, height: 44)

                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.gray)
                    }

                    Text(loc.s("legalButton"))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.secondary)

                    Spacer()

                    Image(systemName: "chevron.forward")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.5))
                }
                .padding(16)
                .background(Color.cardBackground)
                .cornerRadius(16)
                .shadow(color: Color.black.opacity(0.03), radius: 4, y: 1)
            }
            .buttonStyle(.plain)
        }
    }

}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var settingsStore: SettingsStore
    @EnvironmentObject var loc: LocalizationManager
    @State private var newDeviceName: String = ""
    @State private var newTimeWindow: AutoResponseTimeWindow? = nil

    var body: some View {
        Form {
            // Mute
            Section {
                Toggle(isOn: $settingsStore.isMuted) {
                    HStack(spacing: 10) {
                        Image(systemName: settingsStore.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .foregroundColor(.babyOrange)
                        Text(loc.s("muteNotifications"))
                            .font(.system(size: 15, weight: .medium))
                    }
                }
                .tint(.babyOrange)
            } footer: {
                Text(loc.s("muteNotificationsDesc"))
                    .font(.footnote)
                    .foregroundColor(.gray)
            }

            // Devices
            Section {
                ForEach(settingsStore.devices) { device in
                    HStack {
                        Image(systemName: "car.fill")
                            .foregroundColor(.babyOrange)
                        Text(device.name)
                            .font(.system(size: 15))
                        Spacer()
                        Button(role: .destructive) {
                            if let index = settingsStore.devices.firstIndex(of: device) {
                                withAnimation { settingsStore.devices.remove(at: index) }
                            }
                        } label: {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.babyRed)
                        }
                        .buttonStyle(.bordered)
                        .tint(.babyRed.opacity(0.1))
                    }
                    .padding(.vertical, 4)
                }
                .onDelete { indexSet in
                    settingsStore.devices.remove(atOffsets: indexSet)
                }

                HStack(spacing: 10) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.babyOrange)
                    TextField(loc.s("newDeviceName"), text: $newDeviceName)
                        .textFieldStyle(.plain)
                    Button(loc.s("add")) {
                        let name = newDeviceName.trimmingCharacters(in: .whitespaces)
                        guard !name.isEmpty else { return }
                        withAnimation {
                            settingsStore.devices.append(BluetoothDevice(id: UUID(), name: name))
                        }
                        newDeviceName = ""
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.babyOrange)
                    .disabled(newDeviceName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                VStack(alignment: loc.alignment, spacing: 4) {
                    Label(loc.s("carDevices"), systemImage: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 14, weight: .semibold))
                    Text(loc.s("carDevicesDesc"))
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }

            // Auto Response
            Section {
                VStack(alignment: loc.alignment, spacing: 12) {
                    Picker(loc.s("autoResponseDefault"), selection: $settingsStore.autoResponse) {
                        Text(loc.s("yes")).tag("yes")
                        Text(loc.s("no")).tag("no")
                    }
                    .pickerStyle(.segmented)

                    if settingsStore.autoResponse == "no" {
                        timeWindowsSection
                    }
                }
            } header: {
                VStack(alignment: loc.alignment, spacing: 4) {
                    Label(loc.s("autoResponse"), systemImage: "clock.arrow.circlepath")
                        .font(.system(size: 14, weight: .semibold))
                    Text(loc.s("autoResponseDesc"))
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }
        }
        .navigationTitle(loc.s("settings"))
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, loc.layoutDirection)
    }

    // MARK: Time Windows
    @ViewBuilder
    private var timeWindowsSection: some View {
        VStack(alignment: loc.alignment, spacing: 12) {
            Text(loc.s("timeWindowDesc"))
                .font(.caption)
                .foregroundColor(.gray)
                .padding(.bottom, 2)

            ForEach(settingsStore.autoResponseTimeWindows) { window in
                HStack {
                    VStack(alignment: loc.alignment, spacing: 2) {
                        Text(loc.weekdays().first(where: { $0.0 == window.weekday })?.1 ?? "")
                            .font(.system(size: 14, weight: .semibold))
                        Text(String(format: "%@ %02d:%02d", loc.s("start"), window.startHour, window.startMinute))
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                        Text(String(format: "%@ %02d:%02d", loc.s("end"), window.endHour, window.endMinute))
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        if let index = settingsStore.autoResponseTimeWindows.firstIndex(of: window) {
                            withAnimation { settingsStore.autoResponseTimeWindows.remove(at: index) }
                        }
                    } label: {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.bordered)
                    .tint(.babyRed.opacity(0.1))
                }
                .padding(12)
                .background(Color(UIColor.tertiarySystemGroupedBackground))
                .cornerRadius(10)
            }

            if let tw = newTimeWindow {
                newTimeWindowEditor(tw)
            } else {
                Button {
                    newTimeWindow = AutoResponseTimeWindow(
                        id: UUID(), weekday: 1,
                        startHour: 8, startMinute: 0,
                        endHour: 9, endMinute: 0
                    )
                } label: {
                    Label(loc.s("addTimeWindow"), systemImage: "plus.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.babyOrange)
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func newTimeWindowEditor(_ window: AutoResponseTimeWindow) -> some View {
        VStack(alignment: loc.alignment, spacing: 10) {
            HStack {
                Text(loc.s("newWindow"))
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button(role: .destructive) {
                    newTimeWindow = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
            }

            Picker(loc.s("day"), selection: Binding(
                get: { window.weekday },
                set: { newTimeWindow?.weekday = $0 }
            )) {
                ForEach(loc.weekdays(), id: \.0) { day in
                    Text(day.1).tag(day.0)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 100)
            .clipped()

            DatePicker(loc.s("startTime"), selection: Binding(
                get: { dateFrom(hour: window.startHour, minute: window.startMinute) },
                set: { date in
                    let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                    newTimeWindow?.startHour = c.hour ?? 0
                    newTimeWindow?.startMinute = c.minute ?? 0
                }
            ), displayedComponents: [.hourAndMinute])
            .datePickerStyle(.compact)

            DatePicker(loc.s("endTime"), selection: Binding(
                get: { dateFrom(hour: window.endHour, minute: window.endMinute) },
                set: { date in
                    let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                    newTimeWindow?.endHour = c.hour ?? 0
                    newTimeWindow?.endMinute = c.minute ?? 0
                }
            ), displayedComponents: [.hourAndMinute])
            .datePickerStyle(.compact)

            Button(loc.s("saveTimeWindow")) {
                if let w = newTimeWindow {
                    withAnimation { settingsStore.autoResponseTimeWindows.append(w) }
                    newTimeWindow = nil
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.babyOrange)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
        }
        .padding(12)
        .background(Color(UIColor.tertiarySystemGroupedBackground))
        .cornerRadius(10)
    }

    private func dateFrom(hour: Int, minute: Int) -> Date {
        var c = DateComponents()
        c.hour = hour
        c.minute = minute
        return Calendar.current.date(from: c) ?? Date()
    }
}

#Preview {
    ContentView()
}
