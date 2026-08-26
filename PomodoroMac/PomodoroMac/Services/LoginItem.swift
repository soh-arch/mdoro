import Foundation
import ServiceManagement

// 常駐アプリの標準的な設定項目（Decision 0016）。
// メニューバーに常駐する道具は、ログイン時に立ち上がっていないと使われない。
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    // 失敗しても致命的ではないので、成否だけ返して UI が実態を映せるようにする。
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            return false
        }
    }
}
