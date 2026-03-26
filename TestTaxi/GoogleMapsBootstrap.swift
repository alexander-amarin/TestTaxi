import Foundation
import GoogleMaps

/// Вызовите до создания любой карты. Ключ: в Xcode → Target → Info → Custom iOS Target Properties
/// добавьте `GMSApiKey` (String) или задайте `INFOPLIST_KEY_GMSApiKey` в Build Settings.
enum GoogleMapsBootstrap {
    static func configure() {
        // 1) Info.plist / сгенерированный plist: ключ GMSApiKey
        let fromPlist = (Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // 2) Схема Run → Arguments → Environment Variables (для отладки)
        let fromEnv = ProcessInfo.processInfo.environment["GOOGLE_MAPS_IOS_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let key = [fromPlist, fromEnv].compactMap { $0 }.first { !$0.isEmpty } ?? ""

        // Без ключа приложение не должно падать: карта покажет ошибку Google, пока не вставишь ключ.
        let resolved = key.isEmpty ? "MISSING_GMS_API_KEY_REPLACE_IN_INFO" : key

        #if DEBUG
        let source: String
        if let p = fromPlist, !p.isEmpty {
            source = "Info.plist (GMSApiKey)"
        } else if let e = fromEnv, !e.isEmpty {
            source = "env GOOGLE_MAPS_IOS_API_KEY"
        } else {
            source = "fallback (ключ в plist/env не найден — подставлена заглушка)"
        }
        print("[Google Maps] configure: источник ключа = \(source)")
        print("[Google Maps] configure: ключ (маска) = \(maskKeyForLog(resolved))")
        if key.isEmpty {
            print("""
            [Google Maps] ⚠️ Реальный ключ не найден.
            • Target → Info → Custom Property **GMSApiKey** (String)
            • или Run → Environment **GOOGLE_MAPS_IOS_API_KEY**
            """)
        }
        print("[Google Maps] configure: вызов GMSServices.provideAPIKey — OK. Дальше: при успехе в консоли будет «[Google Maps] тайлы отрисованы…».")
        #endif

        GMSServices.provideAPIKey(resolved)
    }

    #if DEBUG
    /// В лог не выводим полный ключ — только длину и края для проверки, что подставился нужный.
    private static func maskKeyForLog(_ key: String) -> String {
        guard key.count > 14 else { return "«\(key)» — слишком короткий или заглушка" }
        return "\(key.prefix(10))…\(key.suffix(4)) (\(key.count) символов)"
    }
    #endif
}
