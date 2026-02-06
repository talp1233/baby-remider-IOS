import SwiftUI
import UserNotifications
import Combine
import AVFoundation

// MARK: - Global Helpers

private var manualResponseOverride: Bool {
    get { UserDefaults.standard.bool(forKey: "manualResponseOverride") }
    set { UserDefaults.standard.set(newValue, forKey: "manualResponseOverride") }
}

// MARK: - Models

struct AutoResponseTimeWindow: Identifiable, Codable, Equatable {
    let id: UUID
    var weekday: Int // 1-7
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
    private var userDeviceNames: [String]
    private var observer: NSObjectProtocol?

    init(deviceNames: [String]) {
        self.userDeviceNames = deviceNames
        updateCurrentRoute()
        observer = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.updateCurrentRoute()
        }
    }

    deinit {
        if let observer = observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func updateCurrentRoute() {
        let session = AVAudioSession.sharedInstance()
        let outputs = session.currentRoute.outputs

        if let match = outputs.first(where: { userDeviceNames.contains($0.portName) }) {
            deviceConnected = match.portName
        } else if let specialOutput = outputs.first(where: {
            $0.portType == .carAudio ||
            $0.portType == .usbAudio ||
            $0.portType == .bluetoothA2DP ||
            $0.portType == .bluetoothHFP ||
            $0.portType == .bluetoothLE
        }) {
            deviceConnected = specialOutput.portName
        } else {
            deviceConnected = nil
        }
    }
}

// MARK: - Notification Manager

struct NotificationManager {
    static var isMuted: Bool = false
    private static let loc = LocalizationManager.shared

    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        registerCategories()
    }

    static func scheduleChildrenInCarNotification(repeats: Int = 0) {
        let content = UNMutableNotificationContent()
        content.title = loc.s("childrenInCarTitle")
        content.subtitle = loc.s("notificationSubtitle")
        content.body = loc.s("childrenInCarBody")
        content.categoryIdentifier = "CHILDREN_IN_CAR"
        content.userInfo = ["repeats": repeats]
        content.sound = isMuted ? nil : UNNotificationSound.default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "children_in_car", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    static func scheduleReminderNotification(repeats: Int) {
        if repeats == 0 {
            for i in 0..<10 {
                let content = UNMutableNotificationContent()
                content.title = loc.s("reminderTitle")
                content.subtitle = loc.s("notificationSubtitle")
                content.body = loc.s("reminderBody")
                content.categoryIdentifier = "REMINDER"
                content.userInfo = ["repeats": i]
                content.sound = isMuted ? nil : UNNotificationSound.default

                let timeInterval = (i == 0) ? 1.0 : TimeInterval(i * 60)
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)
                let request = UNNotificationRequest(identifier: "reminder_\(i)", content: content, trigger: trigger)
                UNUserNotificationCenter.current().add(request)
            }
        } else {
            guard repeats < 10 else { return }

            let content = UNMutableNotificationContent()
            content.title = loc.s("reminderTitle")
            content.subtitle = loc.s("notificationSubtitle")
            content.body = loc.s("reminderBody")
            content.categoryIdentifier = "REMINDER"
            content.userInfo = ["repeats": repeats]
            content.sound = isMuted ? nil : UNNotificationSound.default

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            let request = UNNotificationRequest(identifier: "reminder_\(repeats)", content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request)
        }
    }

    static func cancelAllReminderNotifications() {
        let identifiers = (0..<10).map { "reminder_\($0)" }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    static func scheduleForceQuitWarning() {
        let content = UNMutableNotificationContent()
        content.title = loc.s("forceQuitTitle")
        content.subtitle = loc.s("notificationSubtitle")
        content.body = loc.s("forceQuitBody")
        content.sound = UNNotificationSound.default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 10, repeats: false)
        let request = UNNotificationRequest(identifier: "force_quit_warning", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    static func cancelForceQuitWarning() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["force_quit_warning"])
    }

    static func registerCategories() {
        let yes = UNNotificationAction(identifier: "YES_CHILDREN", title: loc.s("yesChildrenAction"), options: [])
        let no = UNNotificationAction(identifier: "NO_CHILDREN", title: loc.s("noChildrenAction"), options: [])
        let childrenCategory = UNNotificationCategory(
            identifier: "CHILDREN_IN_CAR",
            actions: [yes, no],
            intentIdentifiers: [],
            options: []
        )

        let yesReminder = UNNotificationAction(identifier: "YES_CHILDREN", title: loc.s("yesAction"), options: [])
        let reminderCategory = UNNotificationCategory(
            identifier: "REMINDER",
            actions: [yesReminder],
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
    @State private var inDriveMode: Bool = false
    @ObservedObject private var loc = LocalizationManager.shared

    init() {
        let store = SettingsStore()
        _settingsStore = StateObject(wrappedValue: store)
        _audioRouteMonitor = StateObject(wrappedValue: AudioRouteMonitor(deviceNames: store.devices.map(\.name)))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // MARK: App Header
                    headerSection

                    // MARK: Warning Banner
                    warningBanner

                    // MARK: Status Card
                    statusCard

                    // MARK: Language Selector
                    languageCard

                    // MARK: Action Buttons
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
                UNUserNotificationCenter.current().delegate = NotificationCenterDelegate.shared
            }
            .onChange(of: audioRouteMonitor.deviceConnected) { newValue in
                handleDeviceConnectionChange(newValue)
            }
        }
        .environment(\.layoutDirection, loc.layoutDirection)
    }

    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 8) {
            // App Icon
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

    // MARK: - Status Card
    private var statusCard: some View {
        VStack(spacing: 16) {
            // Protection status
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(inDriveMode ? Color.safeGreen.opacity(0.15) : Color.gray.opacity(0.10))
                        .frame(width: 50, height: 50)

                    Image(systemName: inDriveMode ? "shield.checkmark.fill" : "shield.slash.fill")
                        .font(.system(size: 24))
                        .foregroundColor(inDriveMode ? .safeGreen : .gray)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(inDriveMode ? loc.s("protectionActive") : loc.s("protectionInactive"))
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(inDriveMode ? .safeGreen : .gray)

                    Text(inDriveMode ? loc.s("driveMode") : loc.s("notInDriveMode"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Animated indicator
                Circle()
                    .fill(inDriveMode ? Color.safeGreen : Color.gray.opacity(0.3))
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle()
                            .stroke(inDriveMode ? Color.safeGreen.opacity(0.4) : Color.clear, lineWidth: 4)
                            .scaleEffect(inDriveMode ? 2.0 : 1.0)
                            .opacity(inDriveMode ? 0 : 1)
                            .animation(
                                inDriveMode
                                    ? .easeOut(duration: 1.5).repeatForever(autoreverses: false)
                                    : .default,
                                value: inDriveMode
                            )
                    )
            }

            Divider()

            // Connected device
            HStack(spacing: 10) {
                Image(systemName: audioRouteMonitor.deviceConnected != nil ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
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
                            // Re-register notification categories with new language
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
            // Settings Button
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

            // Legal Button
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

    // MARK: - Device Connection Handler
    private func handleDeviceConnectionChange(_ newValue: String?) {
        if newValue == nil {
            if inDriveMode {
                let now = Date()
                let calendar = Calendar.current
                let currentWeekday = calendar.component(.weekday, from: now)
                let currentHour = calendar.component(.hour, from: now)
                let currentMinute = calendar.component(.minute, from: now)

                var isInTimeWindow = false
                for window in settingsStore.autoResponseTimeWindows {
                    if window.weekday == currentWeekday {
                        let startTotal = window.startHour * 60 + window.startMinute
                        let endTotal = window.endHour * 60 + window.endMinute
                        let currentTotal = currentHour * 60 + currentMinute
                        if currentTotal >= startTotal && currentTotal <= endTotal {
                            isInTimeWindow = true
                            break
                        }
                    }
                }

                if manualResponseOverride || settingsStore.autoResponse == "yes" || isInTimeWindow {
                    NotificationManager.scheduleReminderNotification(repeats: 0)
                }
                inDriveMode = false
            }
        } else {
            manualResponseOverride = false
            if !inDriveMode {
                NotificationManager.scheduleChildrenInCarNotification()
                inDriveMode = true
            }
        }
    }
}

// MARK: - Notification Center Delegate

class NotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationCenterDelegate()

    private override init() { super.init() }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let category = response.notification.request.content.categoryIdentifier

        if category == "REMINDER" {
            NotificationManager.cancelAllReminderNotifications()
        }

        completionHandler()
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @StateObject var settingsStore: SettingsStore
    @EnvironmentObject var loc: LocalizationManager
    @State private var newDeviceName: String = ""
    @State private var newTimeWindow: AutoResponseTimeWindow? = nil

    var body: some View {
        Form {
            // MARK: Mute Section
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

            // MARK: Devices Section
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
                                withAnimation {
                                    settingsStore.devices.remove(at: index)
                                }
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

            // MARK: Auto Response Section
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
                            withAnimation {
                                settingsStore.autoResponseTimeWindows.remove(at: index)
                            }
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

            if let newWindow = newTimeWindow {
                newTimeWindowEditor(newWindow)
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
                set: { newDate in
                    let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                    newTimeWindow?.startHour = comps.hour ?? 0
                    newTimeWindow?.startMinute = comps.minute ?? 0
                }
            ), displayedComponents: [.hourAndMinute])
            .datePickerStyle(.compact)

            DatePicker(loc.s("endTime"), selection: Binding(
                get: { dateFrom(hour: window.endHour, minute: window.endMinute) },
                set: { newDate in
                    let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                    newTimeWindow?.endHour = comps.hour ?? 0
                    newTimeWindow?.endMinute = comps.minute ?? 0
                }
            ), displayedComponents: [.hourAndMinute])
            .datePickerStyle(.compact)

            Button(loc.s("saveTimeWindow")) {
                if let w = newTimeWindow {
                    withAnimation {
                        settingsStore.autoResponseTimeWindows.append(w)
                    }
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
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        return Calendar.current.date(from: comps) ?? Date()
    }
}

// MARK: - Edit Time Window View

struct EditTimeWindowView: View {
    @Binding var window: AutoResponseTimeWindow
    let weekdays: [(Int, String)]
    var onDismiss: () -> Void
    @EnvironmentObject var loc: LocalizationManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(loc.s("day"))) {
                    Picker(loc.s("day"), selection: $window.weekday) {
                        ForEach(weekdays, id: \.0) { day in
                            Text(day.1).tag(day.0)
                        }
                    }
                    .pickerStyle(.wheel)
                }
                Section(header: Text(loc.s("startTime"))) {
                    DatePicker(loc.s("startTime"), selection: Binding(
                        get: { dateFrom(hour: window.startHour, minute: window.startMinute) },
                        set: { newDate in
                            let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                            window.startHour = comps.hour ?? 0
                            window.startMinute = comps.minute ?? 0
                        }
                    ), displayedComponents: [.hourAndMinute])
                    .datePickerStyle(.wheel)
                }
                Section(header: Text(loc.s("endTime"))) {
                    DatePicker(loc.s("endTime"), selection: Binding(
                        get: { dateFrom(hour: window.endHour, minute: window.endMinute) },
                        set: { newDate in
                            let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                            window.endHour = comps.hour ?? 0
                            window.endMinute = comps.minute ?? 0
                        }
                    ), displayedComponents: [.hourAndMinute])
                    .datePickerStyle(.wheel)
                }
            }
            .navigationTitle(loc.s("editTimeWindow"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(loc.s("cancel")) { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(loc.s("done")) {
                        dismiss()
                        onDismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.babyOrange)
                }
            }
        }
        .environment(\.layoutDirection, loc.layoutDirection)
    }

    private func dateFrom(hour: Int, minute: Int) -> Date {
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        return Calendar.current.date(from: comps) ?? Date()
    }
}

#Preview {
    ContentView()
}
