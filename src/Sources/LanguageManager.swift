import Foundation

class LanguageManager: ObservableObject {
    static let shared = LanguageManager()

    private let key = "diapason_language"

    @Published var currentLanguage: String {
        didSet { UserDefaults.standard.set(currentLanguage, forKey: key) }
    }

    private init() {
        if let stored = UserDefaults.standard.string(forKey: "diapason_language") {
            currentLanguage = stored
        } else {
            let sysLang = Locale.current.language.languageCode?.identifier ?? "en"
            currentLanguage = ["fr"].contains(sysLang) ? sysLang : "en"
        }
    }

    func setLanguage(_ lang: String) { currentLanguage = lang }
}
