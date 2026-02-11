import SwiftUI
import Combine

enum AppLanguage: String, CaseIterable, Identifiable {
    case hebrew = "he"
    case english = "en"
    case arabic = "ar"
    case russian = "ru"
    case spanish = "es"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hebrew: return "עברית"
        case .english: return "English"
        case .arabic: return "العربية"
        case .russian: return "Русский"
        case .spanish: return "Español"
        }
    }

    var layoutDirection: LayoutDirection {
        switch self {
        case .hebrew, .arabic: return .rightToLeft
        case .english, .russian, .spanish: return .leftToRight
        }
    }

    var textAlignment: TextAlignment {
        switch self {
        case .hebrew, .arabic: return .trailing
        case .english, .russian, .spanish: return .leading
        }
    }

    var horizontalAlignment: HorizontalAlignment {
        switch self {
        case .hebrew, .arabic: return .trailing
        case .english, .russian, .spanish: return .leading
        }
    }

    var frameAlignment: Alignment {
        switch self {
        case .hebrew, .arabic: return .trailing
        case .english, .russian, .spanish: return .leading
        }
    }
}

class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    @Published var currentLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(currentLanguage.rawValue, forKey: "appLanguage")
        }
    }

    var layoutDirection: LayoutDirection { currentLanguage.layoutDirection }
    var textAlignment: TextAlignment { currentLanguage.textAlignment }
    var alignment: HorizontalAlignment { currentLanguage.horizontalAlignment }
    var frameAlignment: Alignment { currentLanguage.frameAlignment }

    private init() {
        let stored = UserDefaults.standard.string(forKey: "appLanguage") ?? "he"
        currentLanguage = AppLanguage(rawValue: stored) ?? .hebrew
    }

    func s(_ key: String) -> String {
        return Self.translations[currentLanguage.rawValue]?[key]
            ?? Self.translations["en"]?[key]
            ?? key
    }

    // MARK: - Weekdays helper
    func weekdays() -> [(Int, String)] {
        return [
            (1, s("sunday")),
            (2, s("monday")),
            (3, s("tuesday")),
            (4, s("wednesday")),
            (5, s("thursday")),
            (6, s("friday")),
            (7, s("saturday"))
        ]
    }

    // MARK: - All Translations
    static let translations: [String: [String: String]] = [
        // MARK: Hebrew
        "he": [
            // App
            "appName": "Baby Reminder",
            "appSubtitle": "אפליקציית בטיחות לילדים ברכב",
            "loadingMessage": "שומרים על הילדים שלך...",

            // Home
            "warningTitle": "חשוב!",
            "warningMessage": "אל תסגור את האפליקציה! היא חייבת לרוץ ברקע כדי להגן על ילדיך.",
            "protectionActive": "ההגנה פעילה",
            "protectionInactive": "ההגנה לא פעילה",
            "driveMode": "מצב נסיעה",
            "notInDriveMode": "לא במצב נסיעה",
            "connectedDevice": "מכשיר מחובר:",
            "noDeviceConnected": "אין מכשיר מחובר",
            "settings": "הגדרות",
            "legalButton": "תנאי שימוש ומדיניות פרטיות",
            "language": "שפה",
            "selectLanguage": "בחר שפה",
            "waitingForResponse": "ממתין לתגובה",
            "connectedToCar": "מחובר לרכב",
            "carPlayConnected": "CarPlay מחובר",
            "childrenInCarMonitoring": "ילדים ברכב - ניטור פעיל",
            "reminderActive": "תזכורת פעילה",
            "confirmChildrenOut": "אנא אשר/י שהילדים יצאו מהרכב",

            // Settings
            "muteNotifications": "השתק התראות",
            "muteNotificationsDesc": "כאשר כפתור זה פועל, ההתראות יוצגו ללא צליל, אך עדיין יופיעו.",
            "carDevices": "מכשירי רכב",
            "carDevicesDesc": "רשימת מכשירי הבלוטות' לזיהוי חיבור במערכת השמע של הרכב",
            "newDeviceName": "שם מכשיר חדש",
            "add": "הוסף",
            "autoResponse": "תגובה אוטומטית",
            "autoResponseDefault": "ברירת מחדל",
            "autoResponseDesc": "קבע את ברירת המחדל לתגובה אוטומטית בעת זיהוי חיבור הרכב ונהל חלונות זמן במידת הצורך",
            "yes": "כן",
            "no": "לא",
            "timeWindowDesc": "חלונות הזמן בהם התגובה האוטומטית תיהיה \"כן\" למרות שברירת המחדל היא \"לא\".\nלדוגמה: ראשון 8:00–14:00.",
            "newWindow": "חלון חדש",
            "addTimeWindow": "הוסף חלון זמן",
            "saveTimeWindow": "שמור חלון זמן",
            "startTime": "שעת התחלה",
            "endTime": "שעת סיום",
            "start": "התחלה:",
            "end": "סיום:",
            "day": "יום",
            "editTimeWindow": "ערוך חלון זמן",
            "cancel": "בטל",
            "done": "סיום",

            // Weekdays
            "sunday": "ראשון",
            "monday": "שני",
            "tuesday": "שלישי",
            "wednesday": "רביעי",
            "thursday": "חמישי",
            "friday": "שישי",
            "saturday": "שבת",

            // Notifications
            "childrenInCarTitle": "האם הילדים ברכב?",
            "childrenInCarBody": "אנא אשר/י האם יש ילדים ברכב.",
            "reminderTitle": "הוצאת את הילדים מהרכב?",
            "reminderBody": "זוהי תזכורת לוודא שהילדים יצאו מהרכב.",
            "notificationSubtitle": "שמור/י על האפליקציה פתוחה לבטיחות ילדיך",
            "yesChildrenAction": "כן, הילדים ברכב",
            "noChildrenAction": "לא",
            "yesAction": "כן",
            "forceQuitTitle": "אזהרה! האפליקציה לא פעילה",
            "forceQuitBody": "Baby Reminder חייבת לרוץ ברקע כדי להגן על ילדיך. אנא פתח/י את האפליקציה מחדש.",

            // Legal
            "legalNavTitle": "תנאים והצהרות",
            "termsOfUse": "תנאי שימוש",
            "termsOfUseContent": "כאן יוצגו תנאי השימוש. עדכן טקסט זה בהתאם למדיניות שלך.",
            "privacyPolicy": "מדיניות פרטיות",
            "privacyPolicyContent": "כאן תוצג מדיניות הפרטיות. עדכן טקסט זה בהתאם למדיניות שלך.",
            "eula": "הסכם רישיון משתמש קצה (EULA)",
            "eulaContent": "כאן יוצג הסכם הרישיון למשתמש הקצה. עדכן טקסט זה בהתאם למדיניות שלך.",
            "disclaimer": "הצהרת אחריות",
            "disclaimerContent": "כאן תופיע הצהרת אחריות. עדכן טקסט זה בהתאם למדיניות שלך.",
        ],

        // MARK: English
        "en": [
            // App
            "appName": "Baby Reminder",
            "appSubtitle": "Child Vehicle Safety App",
            "loadingMessage": "Keeping your children safe...",

            // Home
            "warningTitle": "Important!",
            "warningMessage": "Do not close this app! It must run in the background to protect your children.",
            "protectionActive": "Protection Active",
            "protectionInactive": "Protection Inactive",
            "driveMode": "Drive Mode",
            "notInDriveMode": "Not in Drive Mode",
            "connectedDevice": "Connected Device:",
            "noDeviceConnected": "No device connected",
            "settings": "Settings",
            "legalButton": "Terms of Use & Privacy Policy",
            "language": "Language",
            "selectLanguage": "Select Language",
            "waitingForResponse": "Waiting for Response",
            "connectedToCar": "Connected to Car",
            "carPlayConnected": "CarPlay Connected",
            "childrenInCarMonitoring": "Children in car - active monitoring",
            "reminderActive": "Reminder Active",
            "confirmChildrenOut": "Please confirm children have left the vehicle",

            // Settings
            "muteNotifications": "Mute Notifications",
            "muteNotificationsDesc": "When enabled, notifications will appear without sound but will still be displayed.",
            "carDevices": "Car Devices",
            "carDevicesDesc": "List of Bluetooth devices to detect connection with car audio system",
            "newDeviceName": "New device name",
            "add": "Add",
            "autoResponse": "Auto Response",
            "autoResponseDefault": "Default",
            "autoResponseDesc": "Set the default auto response when car connection is detected and manage time windows as needed",
            "yes": "Yes",
            "no": "No",
            "timeWindowDesc": "Time windows where the auto response will be \"Yes\" even though the default is \"No\".\nExample: Sunday 8:00–14:00.",
            "newWindow": "New Window",
            "addTimeWindow": "Add Time Window",
            "saveTimeWindow": "Save Time Window",
            "startTime": "Start Time",
            "endTime": "End Time",
            "start": "Start:",
            "end": "End:",
            "day": "Day",
            "editTimeWindow": "Edit Time Window",
            "cancel": "Cancel",
            "done": "Done",

            // Weekdays
            "sunday": "Sunday",
            "monday": "Monday",
            "tuesday": "Tuesday",
            "wednesday": "Wednesday",
            "thursday": "Thursday",
            "friday": "Friday",
            "saturday": "Saturday",

            // Notifications
            "childrenInCarTitle": "Are children in the car?",
            "childrenInCarBody": "Please confirm if children are in the car.",
            "reminderTitle": "Did you take the children out?",
            "reminderBody": "This is a reminder to make sure children have left the vehicle.",
            "notificationSubtitle": "Keep the app open for your children's safety",
            "yesChildrenAction": "Yes, children in car",
            "noChildrenAction": "No",
            "yesAction": "Yes",
            "forceQuitTitle": "Warning! App is not running",
            "forceQuitBody": "Baby Reminder must run in the background to protect your children. Please reopen the app.",

            // Legal
            "legalNavTitle": "Terms & Policies",
            "termsOfUse": "Terms of Use",
            "termsOfUseContent": "Terms of use will be displayed here. Update this text according to your policy.",
            "privacyPolicy": "Privacy Policy",
            "privacyPolicyContent": "Privacy policy will be displayed here. Update this text according to your policy.",
            "eula": "End User License Agreement (EULA)",
            "eulaContent": "End user license agreement will be displayed here. Update this text according to your policy.",
            "disclaimer": "Disclaimer",
            "disclaimerContent": "Disclaimer will be displayed here. Update this text according to your policy.",
        ],

        // MARK: Arabic
        "ar": [
            // App
            "appName": "Baby Reminder",
            "appSubtitle": "تطبيق سلامة الأطفال في السيارة",
            "loadingMessage": "نحافظ على سلامة أطفالك...",

            // Home
            "warningTitle": "مهم!",
            "warningMessage": "لا تغلق هذا التطبيق! يجب أن يعمل في الخلفية لحماية أطفالك.",
            "protectionActive": "الحماية فعّالة",
            "protectionInactive": "الحماية غير فعّالة",
            "driveMode": "وضع القيادة",
            "notInDriveMode": "ليس في وضع القيادة",
            "connectedDevice": "الجهاز المتصل:",
            "noDeviceConnected": "لا يوجد جهاز متصل",
            "settings": "الإعدادات",
            "legalButton": "شروط الاستخدام وسياسة الخصوصية",
            "language": "اللغة",
            "selectLanguage": "اختر اللغة",
            "waitingForResponse": "في انتظار الرد",
            "connectedToCar": "متصل بالسيارة",
            "carPlayConnected": "CarPlay متصل",
            "childrenInCarMonitoring": "أطفال في السيارة - مراقبة نشطة",
            "reminderActive": "تذكير نشط",
            "confirmChildrenOut": "يرجى التأكيد أن الأطفال غادروا السيارة",

            // Settings
            "muteNotifications": "كتم الإشعارات",
            "muteNotificationsDesc": "عند التفعيل، ستظهر الإشعارات بدون صوت ولكنها ستظل معروضة.",
            "carDevices": "أجهزة السيارة",
            "carDevicesDesc": "قائمة أجهزة البلوتوث للكشف عن الاتصال بنظام صوت السيارة",
            "newDeviceName": "اسم جهاز جديد",
            "add": "إضافة",
            "autoResponse": "الرد التلقائي",
            "autoResponseDefault": "الافتراضي",
            "autoResponseDesc": "حدد الرد التلقائي الافتراضي عند اكتشاف اتصال السيارة وإدارة النوافذ الزمنية حسب الحاجة",
            "yes": "نعم",
            "no": "لا",
            "timeWindowDesc": "النوافذ الزمنية التي سيكون فيها الرد التلقائي \"نعم\" على الرغم من أن الافتراضي هو \"لا\".\nمثال: الأحد 8:00–14:00.",
            "newWindow": "نافذة جديدة",
            "addTimeWindow": "إضافة نافذة زمنية",
            "saveTimeWindow": "حفظ النافذة الزمنية",
            "startTime": "وقت البدء",
            "endTime": "وقت الانتهاء",
            "start": "البدء:",
            "end": "الانتهاء:",
            "day": "اليوم",
            "editTimeWindow": "تعديل النافذة الزمنية",
            "cancel": "إلغاء",
            "done": "تم",

            // Weekdays
            "sunday": "الأحد",
            "monday": "الاثنين",
            "tuesday": "الثلاثاء",
            "wednesday": "الأربعاء",
            "thursday": "الخميس",
            "friday": "الجمعة",
            "saturday": "السبت",

            // Notifications
            "childrenInCarTitle": "هل الأطفال في السيارة؟",
            "childrenInCarBody": "يرجى التأكيد إذا كان الأطفال في السيارة.",
            "reminderTitle": "هل أخرجت الأطفال من السيارة؟",
            "reminderBody": "هذا تذكير للتأكد من خروج الأطفال من السيارة.",
            "notificationSubtitle": "أبقِ التطبيق مفتوحاً لسلامة أطفالك",
            "yesChildrenAction": "نعم، الأطفال في السيارة",
            "noChildrenAction": "لا",
            "yesAction": "نعم",
            "forceQuitTitle": "تحذير! التطبيق لا يعمل",
            "forceQuitBody": "يجب أن يعمل Baby Reminder في الخلفية لحماية أطفالك. يرجى إعادة فتح التطبيق.",

            // Legal
            "legalNavTitle": "الشروط والسياسات",
            "termsOfUse": "شروط الاستخدام",
            "termsOfUseContent": "سيتم عرض شروط الاستخدام هنا. قم بتحديث هذا النص وفقاً لسياستك.",
            "privacyPolicy": "سياسة الخصوصية",
            "privacyPolicyContent": "سيتم عرض سياسة الخصوصية هنا. قم بتحديث هذا النص وفقاً لسياستك.",
            "eula": "اتفاقية ترخيص المستخدم النهائي (EULA)",
            "eulaContent": "سيتم عرض اتفاقية الترخيص هنا. قم بتحديث هذا النص وفقاً لسياستك.",
            "disclaimer": "إخلاء المسؤولية",
            "disclaimerContent": "سيتم عرض إخلاء المسؤولية هنا. قم بتحديث هذا النص وفقاً لسياستك.",
        ],

        // MARK: Russian
        "ru": [
            // App
            "appName": "Baby Reminder",
            "appSubtitle": "Приложение безопасности детей в автомобиле",
            "loadingMessage": "Защищаем ваших детей...",

            // Home
            "warningTitle": "Важно!",
            "warningMessage": "Не закрывайте приложение! Оно должно работать в фоновом режиме для защиты ваших детей.",
            "protectionActive": "Защита активна",
            "protectionInactive": "Защита неактивна",
            "driveMode": "Режим вождения",
            "notInDriveMode": "Не в режиме вождения",
            "connectedDevice": "Подключённое устройство:",
            "noDeviceConnected": "Устройство не подключено",
            "settings": "Настройки",
            "legalButton": "Условия использования и политика конфиденциальности",
            "language": "Язык",
            "selectLanguage": "Выберите язык",
            "waitingForResponse": "Ожидание ответа",
            "connectedToCar": "Подключён к автомобилю",
            "carPlayConnected": "CarPlay подключён",
            "childrenInCarMonitoring": "Дети в машине - активный мониторинг",
            "reminderActive": "Напоминание активно",
            "confirmChildrenOut": "Пожалуйста, подтвердите, что дети вышли из машины",

            // Settings
            "muteNotifications": "Отключить звук уведомлений",
            "muteNotificationsDesc": "При включении уведомления будут отображаться без звука, но по-прежнему будут показываться.",
            "carDevices": "Автомобильные устройства",
            "carDevicesDesc": "Список Bluetooth-устройств для обнаружения подключения к аудиосистеме автомобиля",
            "newDeviceName": "Имя нового устройства",
            "add": "Добавить",
            "autoResponse": "Автоматический ответ",
            "autoResponseDefault": "По умолчанию",
            "autoResponseDesc": "Установите автоматический ответ по умолчанию при обнаружении подключения автомобиля и управляйте временными окнами по мере необходимости",
            "yes": "Да",
            "no": "Нет",
            "timeWindowDesc": "Временные окна, в которых автоматический ответ будет \"Да\", несмотря на то, что по умолчанию \"Нет\".\nПример: Воскресенье 8:00–14:00.",
            "newWindow": "Новое окно",
            "addTimeWindow": "Добавить временное окно",
            "saveTimeWindow": "Сохранить временное окно",
            "startTime": "Время начала",
            "endTime": "Время окончания",
            "start": "Начало:",
            "end": "Конец:",
            "day": "День",
            "editTimeWindow": "Редактировать временное окно",
            "cancel": "Отмена",
            "done": "Готово",

            // Weekdays
            "sunday": "Воскресенье",
            "monday": "Понедельник",
            "tuesday": "Вторник",
            "wednesday": "Среда",
            "thursday": "Четверг",
            "friday": "Пятница",
            "saturday": "Суббота",

            // Notifications
            "childrenInCarTitle": "Дети в машине?",
            "childrenInCarBody": "Пожалуйста, подтвердите, есть ли дети в машине.",
            "reminderTitle": "Вы забрали детей из машины?",
            "reminderBody": "Это напоминание убедиться, что дети вышли из машины.",
            "notificationSubtitle": "Держите приложение открытым для безопасности ваших детей",
            "yesChildrenAction": "Да, дети в машине",
            "noChildrenAction": "Нет",
            "yesAction": "Да",
            "forceQuitTitle": "Внимание! Приложение не работает",
            "forceQuitBody": "Baby Reminder должен работать в фоновом режиме для защиты ваших детей. Пожалуйста, откройте приложение снова.",

            // Legal
            "legalNavTitle": "Условия и политики",
            "termsOfUse": "Условия использования",
            "termsOfUseContent": "Здесь будут отображаться условия использования. Обновите этот текст в соответствии с вашей политикой.",
            "privacyPolicy": "Политика конфиденциальности",
            "privacyPolicyContent": "Здесь будет отображаться политика конфиденциальности. Обновите этот текст в соответствии с вашей политикой.",
            "eula": "Лицензионное соглашение (EULA)",
            "eulaContent": "Здесь будет отображаться лицензионное соглашение. Обновите этот текст в соответствии с вашей политикой.",
            "disclaimer": "Отказ от ответственности",
            "disclaimerContent": "Здесь будет отображаться отказ от ответственности. Обновите этот текст в соответствии с вашей политикой.",
        ],

        // MARK: Spanish
        "es": [
            // App
            "appName": "Baby Reminder",
            "appSubtitle": "Aplicación de seguridad infantil en vehículos",
            "loadingMessage": "Protegiendo a tus hijos...",

            // Home
            "warningTitle": "¡Importante!",
            "warningMessage": "¡No cierres esta aplicación! Debe ejecutarse en segundo plano para proteger a tus hijos.",
            "protectionActive": "Protección activa",
            "protectionInactive": "Protección inactiva",
            "driveMode": "Modo de conducción",
            "notInDriveMode": "No en modo de conducción",
            "connectedDevice": "Dispositivo conectado:",
            "noDeviceConnected": "Ningún dispositivo conectado",
            "settings": "Configuración",
            "legalButton": "Términos de uso y política de privacidad",
            "language": "Idioma",
            "selectLanguage": "Seleccionar idioma",
            "waitingForResponse": "Esperando respuesta",
            "connectedToCar": "Conectado al vehículo",
            "carPlayConnected": "CarPlay conectado",
            "childrenInCarMonitoring": "Niños en el vehículo - monitoreo activo",
            "reminderActive": "Recordatorio activo",
            "confirmChildrenOut": "Por favor confirma que los niños salieron del vehículo",

            // Settings
            "muteNotifications": "Silenciar notificaciones",
            "muteNotificationsDesc": "Cuando está activado, las notificaciones se mostrarán sin sonido pero seguirán apareciendo.",
            "carDevices": "Dispositivos del vehículo",
            "carDevicesDesc": "Lista de dispositivos Bluetooth para detectar la conexión con el sistema de audio del vehículo",
            "newDeviceName": "Nombre del nuevo dispositivo",
            "add": "Agregar",
            "autoResponse": "Respuesta automática",
            "autoResponseDefault": "Predeterminado",
            "autoResponseDesc": "Establece la respuesta automática predeterminada al detectar la conexión del vehículo y gestiona las ventanas de tiempo según sea necesario",
            "yes": "Sí",
            "no": "No",
            "timeWindowDesc": "Ventanas de tiempo en las que la respuesta automática será \"Sí\" aunque el predeterminado sea \"No\".\nEjemplo: Domingo 8:00–14:00.",
            "newWindow": "Nueva ventana",
            "addTimeWindow": "Agregar ventana de tiempo",
            "saveTimeWindow": "Guardar ventana de tiempo",
            "startTime": "Hora de inicio",
            "endTime": "Hora de fin",
            "start": "Inicio:",
            "end": "Fin:",
            "day": "Día",
            "editTimeWindow": "Editar ventana de tiempo",
            "cancel": "Cancelar",
            "done": "Listo",

            // Weekdays
            "sunday": "Domingo",
            "monday": "Lunes",
            "tuesday": "Martes",
            "wednesday": "Miércoles",
            "thursday": "Jueves",
            "friday": "Viernes",
            "saturday": "Sábado",

            // Notifications
            "childrenInCarTitle": "¿Hay niños en el vehículo?",
            "childrenInCarBody": "Por favor confirma si hay niños en el vehículo.",
            "reminderTitle": "¿Sacaste a los niños del vehículo?",
            "reminderBody": "Este es un recordatorio para asegurarte de que los niños hayan salido del vehículo.",
            "notificationSubtitle": "Mantén la aplicación abierta para la seguridad de tus hijos",
            "yesChildrenAction": "Sí, niños en el vehículo",
            "noChildrenAction": "No",
            "yesAction": "Sí",
            "forceQuitTitle": "¡Advertencia! La aplicación no está funcionando",
            "forceQuitBody": "Baby Reminder debe ejecutarse en segundo plano para proteger a tus hijos. Por favor, vuelve a abrir la aplicación.",

            // Legal
            "legalNavTitle": "Términos y políticas",
            "termsOfUse": "Términos de uso",
            "termsOfUseContent": "Los términos de uso se mostrarán aquí. Actualiza este texto según tu política.",
            "privacyPolicy": "Política de privacidad",
            "privacyPolicyContent": "La política de privacidad se mostrará aquí. Actualiza este texto según tu política.",
            "eula": "Acuerdo de licencia de usuario final (EULA)",
            "eulaContent": "El acuerdo de licencia se mostrará aquí. Actualiza este texto según tu política.",
            "disclaimer": "Descargo de responsabilidad",
            "disclaimerContent": "El descargo de responsabilidad se mostrará aquí. Actualiza este texto según tu política.",
        ],
    ]
}
