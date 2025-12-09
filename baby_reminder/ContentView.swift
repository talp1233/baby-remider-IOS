import SwiftUI
import UserNotifications
import Combine
import AVFoundation

private var manualResponseOverride: Bool {
    get { UserDefaults.standard.bool(forKey: "manualResponseOverride") }
    set { UserDefaults.standard.set(newValue, forKey: "manualResponseOverride") }
}

struct AutoResponseTimeWindow: Identifiable, Codable, Equatable {
    let id: UUID
    var weekday: Int // 1-7, ראשון-שבת
    var startHour: Int // 0-23
    var startMinute: Int // 0-59
    var endHour: Int // 0-23
    var endMinute: Int // 0-59
}

class AudioRouteMonitor: ObservableObject {
    @Published var deviceConnected: String? = nil
    private var userDeviceNames: [String]
    private var observer: NSObjectProtocol?
    
    init(deviceNames: [String]) {
        self.userDeviceNames = deviceNames
        updateCurrentRoute()
        observer = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
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
        
        for output in outputs {
            print("Detected output port: \(output.portName) (\(output.portType.rawValue))")
        }
        
        if let match = outputs.first(where: { userDeviceNames.contains($0.portName) }) {
            deviceConnected = match.portName
        } else if let specialOutput = outputs.first(where: {
            $0.portType == AVAudioSession.Port.carAudio ||
            $0.portType == AVAudioSession.Port.usbAudio ||
            $0.portType == AVAudioSession.Port.bluetoothA2DP ||
            $0.portType == AVAudioSession.Port.bluetoothHFP ||
            $0.portType == AVAudioSession.Port.bluetoothLE
        }) {
            deviceConnected = specialOutput.portName
        } else {
            deviceConnected = nil
        }
    }
}

struct NotificationManager {
    static var isMuted: Bool = false
    
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            // ניתן להציג alert אם לא granted
        }
        registerCategories()
    }
    
    static func scheduleChildrenInCarNotification(repeats: Int = 0) {
        let content = UNMutableNotificationContent()
        content.title = "האם הילדים ברכב?"
        content.body = "אנא אשר/י האם יש ילדים ברכב."
        content.categoryIdentifier = "CHILDREN_IN_CAR"
        
        // Add userInfo to track repeats count
        content.userInfo = ["repeats": repeats]
        
        if isMuted {
            content.sound = nil // שקט
        } else {
            content.sound = UNNotificationSound.default
        }
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "children_in_car", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
    
    static func scheduleReminderNotification(repeats: Int) {
        if repeats == 0 {
            // Schedule 10 reminders, spaced by 1 minute each, first after 1 second delay.
            for i in 0..<10 {
                let content = UNMutableNotificationContent()
                content.title = "הוצאת את הילדים מהרכב?"
                content.body = "זוהי תזכורת לוודא שהילדים יצאו מהרכב."
                content.categoryIdentifier = "REMINDER"
                content.userInfo = ["repeats": i]
                
                if isMuted {
                    content.sound = nil // שקט
                } else {
                    content.sound = UNNotificationSound.default
                }
                
                // First notification after 1 second, next after 1 minute, 2 minutes, ...
                let timeInterval = (i == 0) ? 1.0 : TimeInterval(i * 60)
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)
                let request = UNNotificationRequest(identifier: "reminder_\(i)", content: content, trigger: trigger)
                UNUserNotificationCenter.current().add(request)
            }
        } else {
            guard repeats < 10 else { return }
            
            let content = UNMutableNotificationContent()
            content.title = "הוצאת את הילדים מהרכב?"
            content.body = "זוהי תזכורת לוודא שהילדים יצאו מהרכב."
            content.categoryIdentifier = "REMINDER"
            content.userInfo = ["repeats": repeats]
            
            if isMuted {
                content.sound = nil // שקט
            } else {
                content.sound = UNNotificationSound.default
            }
            
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false) // Changed to 1 second
            
            let request = UNNotificationRequest(identifier: "reminder_\(repeats)", content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request)
        }
    }
    
    static func cancelAllReminderNotifications() {
        let identifiers = (0..<10).map { "reminder_\($0)" }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }
    
    static func registerCategories() {
        let yes = UNNotificationAction(identifier: "YES_CHILDREN", title: "כן, הילדים ברכב", options: [])
        let no = UNNotificationAction(identifier: "NO_CHILDREN", title: "לא", options: [])
        let childrenCategory = UNNotificationCategory(identifier: "CHILDREN_IN_CAR", actions: [yes, no], intentIdentifiers: [], options: [])
        
        let yesReminder = UNNotificationAction(identifier: "YES_CHILDREN", title: "כן", options: [])
        let reminderCategory = UNNotificationCategory(identifier: "REMINDER", actions: [yesReminder], intentIdentifiers: [], options: [])
        
        UNUserNotificationCenter.current().setNotificationCategories([childrenCategory, reminderCategory])
    }
}

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
        autoResponse = UserDefaults.standard.string(forKey: "autoResponse") ?? "כן"
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

struct BluetoothDevice: Identifiable, Equatable, Codable {
    let id: UUID
    var name: String
}

struct ContentView: View {
    @State private var showSettings = false
    @State private var showLegal = false
    @StateObject private var settingsStore = SettingsStore()
    @StateObject private var audioRouteMonitor: AudioRouteMonitor
    @State private var inDriveMode: Bool = false
    
    init() {
        let settingsStore = SettingsStore()
        _settingsStore = StateObject(wrappedValue: settingsStore)
        _audioRouteMonitor = StateObject(wrappedValue: AudioRouteMonitor(deviceNames: settingsStore.devices.map(\.name)))
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()
                if let connected = audioRouteMonitor.deviceConnected {
                    Text("מכשיר מחובר: \(connected)")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                // Added drive mode status display
                HStack(spacing: 8) {
                    if inDriveMode {
                        Image(systemName: "car.fill")
                            .foregroundColor(.green)
                        Text("מצב נסיעה")
                            .foregroundColor(.green)
                            .font(.headline)
                    } else {
                        Image(systemName: "parkingsign.circle")
                            .foregroundColor(.gray)
                        Text("לא במצב נסיעה")
                            .foregroundColor(.gray)
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                
                Text("ברוך הבא לאפליקציית תזכורת ילדים ברכב")
                    .font(.title2).multilineTextAlignment(.trailing)
                Spacer()
                
                Button {
                    showSettings = true
                } label: {
                    Label("הגדרות", systemImage: "gearshape")
                        .font(.title3.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                
                Button("תנאי שימוש ומדיניות פרטיות") {
                    showLegal = true
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .trailing)
            .navigationDestination(isPresented: $showSettings) {
                SettingsView(settingsStore: settingsStore)
            }
            .navigationDestination(isPresented: $showLegal) {
                LegalView()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("הגדרות")
                }
            }
            .onAppear {
                NotificationManager.requestAuthorization()
                // Add observer for notification responses to cancel reminders when needed
                UNUserNotificationCenter.current().delegate = NotificationCenterDelegate.shared
            }
            .onChange(of: audioRouteMonitor.deviceConnected) { newValue in
                if newValue == nil {
                    // device disconnected
                    if inDriveMode {
                        print("Device disconnected while inDriveMode")
                        // Evaluate if autoResponse == "כן" or if any time window matches current time
                        let now = Date()
                        let calendar = Calendar.current
                        let currentWeekday = calendar.component(.weekday, from: now)
                        let currentHour = calendar.component(.hour, from: now)
                        let currentMinute = calendar.component(.minute, from: now)
                        
                        var isInTimeWindow = false
                        for window in settingsStore.autoResponseTimeWindows {
                            if window.weekday == currentWeekday {
                                let startTotalMinutes = window.startHour * 60 + window.startMinute
                                let endTotalMinutes = window.endHour * 60 + window.endMinute
                                let currentTotalMinutes = currentHour * 60 + currentMinute
                                if currentTotalMinutes >= startTotalMinutes && currentTotalMinutes <= endTotalMinutes {
                                    isInTimeWindow = true
                                    break
                                }
                            }
                        }
                        
                        if manualResponseOverride || settingsStore.autoResponse == "כן" || isInTimeWindow {
                            print("Sending reminder notification because manual override or autoResponse is 'כן' or current time is within a time window.")
                            NotificationManager.scheduleReminderNotification(repeats: 0)
                        } else {
                            print("Auto-response is 'לא' and current time not in any time window - skipping reminder notification.")
                        }
                        // Always reset inDriveMode after handling disconnection
                        inDriveMode = false
                    }
                } else {
                    // device connected
                    manualResponseOverride = false // reset override at new session
                    if !inDriveMode {
                        print("Device connected and not inDriveMode - sending first notification and setting inDriveMode = true")
                        NotificationManager.scheduleChildrenInCarNotification()
                        inDriveMode = true
                    } else {
                        print("Device connected and already inDriveMode - no notification sent")
                    }
                }
            }
        }
    }
}

// MARK: - NotificationCenter Delegate to handle responses

class NotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationCenterDelegate()
    
    private override init() {
        super.init()
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, 
                                didReceive response: UNNotificationResponse, 
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let identifier = response.notification.request.identifier
        let category = response.notification.request.content.categoryIdentifier
        
        if category == "REMINDER" {
            // Upon any response to REMINDER, cancel all future reminder notifications
            NotificationManager.cancelAllReminderNotifications()
        }
        
        // Call completion handler
        completionHandler()
    }
}

struct SettingsView: View {
    @StateObject var settingsStore: SettingsStore
    @State private var newDeviceName: String = ""
    
    // For adding/editing time windows inline
    @State private var newTimeWindow: AutoResponseTimeWindow? = nil
    
    private let weekdays = [
        (1, "ראשון"),
        (2, "שני"),
        (3, "שלישי"),
        (4, "רביעי"),
        (5, "חמישי"),
        (6, "שישי"),
        (7, "שבת")
    ]
    
    var body: some View {
        Form {
            Section {
                Toggle("השתק התראות", isOn: $settingsStore.isMuted)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .font(.headline)
                    .tint(.blue)
            } header: {
                Text("השתק התראות")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } footer: {
                Text("כאשר כפתור זה פועל, ההתראות יוצגו ללא צליל, אך עדיין יופיעו.")
                    .font(.footnote)
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            
            Section(header:
                        VStack(alignment: .trailing) {
                Text("מכשירי רכב")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Text("רשימת מכשירי הבלוטות' לזיהוי חיבור במערכת השמע של הרכב")
                    .font(.footnote)
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }) {
                ForEach(settingsStore.devices) { device in
                    HStack {
                        Text(device.name)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        Button(role: .destructive) {
                            if let index = settingsStore.devices.firstIndex(of: device) {
                                settingsStore.devices.remove(at: index)
                            }
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(8)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(8)
                }
                .onDelete { indexSet in
                    settingsStore.devices.remove(atOffsets: indexSet)
                }
                HStack {
                    TextField("שם מכשיר חדש", text: $newDeviceName)
                        .multilineTextAlignment(.trailing)
                    Button("הוסף") {
                        let name = newDeviceName.trimmingCharacters(in: .whitespaces)
                        guard !name.isEmpty else { return }
                        settingsStore.devices.append(BluetoothDevice(id: UUID(), name: name))
                        newDeviceName = ""
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            
            Section(header:
                        VStack(alignment: .trailing, spacing: 4) {
                Text("תגובה אוטומטית")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Text("קבע את ברירת המחדל לתגובה אוטומטית בעת זיהוי חיבור הרכב ונהל חלונות זמן במידת הצורך")
                    .font(.footnote)
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }) {
                Picker("ברירת מחדל", selection: $settingsStore.autoResponse) {
                    Text("כן").tag("כן")
                    Text("לא").tag("לא")
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: .infinity, alignment: .trailing)
                
                if settingsStore.autoResponse == "לא" {
                    VStack(alignment: .trailing, spacing: 12) {
                        Text("חלונות הזמן בהם התגובה האוטומטית תיהיה \"כן\" למרות שברירת המחדל היא \"לא\".\nלדוגמה: ראשון 8:00–14:00.")
                            .font(.footnote)
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.bottom, 2)
                        
                        // Existing time windows list
                        ForEach(settingsStore.autoResponseTimeWindows) { window in
                            VStack(alignment: .trailing) {
                                HStack {
                                    VStack(alignment: .trailing) {
                                        Text(weekdays.first(where: { $0.0 == window.weekday })?.1 ?? "")
                                            .font(.headline)
                                        Text(String(format: "התחלה: %02d:%02d", window.startHour, window.startMinute))
                                            .font(.subheadline)
                                        Text(String(format: "סיום: %02d:%02d", window.endHour, window.endMinute))
                                            .font(.subheadline)
                                    }
                                    Spacer()
                                    Button(role: .destructive) {
                                        if let index = settingsStore.autoResponseTimeWindows.firstIndex(of: window) {
                                            settingsStore.autoResponseTimeWindows.remove(at: index)
                                        }
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                            .padding(8)
                            .background(Color(UIColor.secondarySystemBackground))
                            .cornerRadius(8)
                        }
                        
                        // Inline new window editor
                        if let newWindow = newTimeWindow {
                            VStack(alignment: .trailing) {
                                HStack {
                                    Text("חלון חדש")
                                        .font(.headline)
                                        .frame(maxWidth: .infinity, alignment: .trailing)
                                    Spacer()
                                    Button(role: .destructive) {
                                        newTimeWindow = nil
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.bordered)
                                }
                                Picker("יום", selection: Binding(
                                    get: { newWindow.weekday },
                                    set: { newTimeWindow?.weekday = $0 }
                                )) {
                                    ForEach(weekdays, id: \.0) { day in
                                        Text(day.1).tag(day.0)
                                    }
                                }
                                .pickerStyle(.wheel)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .clipped()
                                DatePicker("שעת התחלה", selection: Binding(
                                    get: {
                                        dateFrom(hour: newWindow.startHour, minute: newWindow.startMinute)
                                    },
                                    set: { newDate in
                                        let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                                        newTimeWindow?.startHour = comps.hour ?? 0
                                        newTimeWindow?.startMinute = comps.minute ?? 0
                                    }
                                ), displayedComponents: [.hourAndMinute])
                                .datePickerStyle(.wheel)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .clipped()
                                DatePicker("שעת סיום", selection: Binding(
                                    get: {
                                        dateFrom(hour: newWindow.endHour, minute: newWindow.endMinute)
                                    },
                                    set: { newDate in
                                        let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                                        newTimeWindow?.endHour = comps.hour ?? 0
                                        newTimeWindow?.endMinute = comps.minute ?? 0
                                    }
                                ), displayedComponents: [.hourAndMinute])
                                .datePickerStyle(.wheel)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .clipped()
                                
                                Button("שמור חלון זמן") {
                                    if let newWindow = newTimeWindow {
                                        settingsStore.autoResponseTimeWindows.append(newWindow)
                                        self.newTimeWindow = nil
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .padding(.top, 4)
                            }
                            .padding(8)
                            .background(Color(UIColor.secondarySystemBackground))
                            .cornerRadius(8)
                        } else {
                            Button("הוסף חלון זמן") {
                                newTimeWindow = AutoResponseTimeWindow(id: UUID(), weekday: 1, startHour: 8, startMinute: 0, endHour: 9, endMinute: 0)
                            }
                            .buttonStyle(.borderedProminent)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, 4)
                }
            }
        }
        .navigationTitle("הגדרות")
        .navigationBarTitleDisplayMode(.inline)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
    
    private func dateFrom(hour: Int, minute: Int) -> Date {
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        return Calendar.current.date(from: comps) ?? Date()
    }
}

struct EditTimeWindowView: View {
    @Binding var window: AutoResponseTimeWindow
    let weekdays: [(Int, String)]
    var onDismiss: () -> Void
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("יום")) {
                    Picker("יום", selection: $window.weekday) {
                        ForEach(weekdays, id: \.0) { day in
                            Text(day.1).tag(day.0)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                Section(header: Text("שעת התחלה")) {
                    DatePicker("התחלה", selection: Binding(
                        get: {
                            dateFrom(hour: window.startHour, minute: window.startMinute)
                        },
                        set: { newDate in
                            let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                            window.startHour = comps.hour ?? 0
                            window.startMinute = comps.minute ?? 0
                        }
                    ), displayedComponents: [.hourAndMinute])
                    .datePickerStyle(.wheel)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                Section(header: Text("שעת סיום")) {
                    DatePicker("סיום", selection: Binding(
                        get: {
                            dateFrom(hour: window.endHour, minute: window.endMinute)
                        },
                        set: { newDate in
                            let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                            window.endHour = comps.hour ?? 0
                            window.endMinute = comps.minute ?? 0
                        }
                    ), displayedComponents: [.hourAndMinute])
                    .datePickerStyle(.wheel)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .navigationTitle("ערוך חלון זמן")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("בטל") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("סיום") {
                        dismiss()
                        onDismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
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
