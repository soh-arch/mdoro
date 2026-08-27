import WidgetKit
import SwiftUI

// この拡張が提供するのは **Live Activity だけ** である（8.3）。
//
// ホーム画面ウィジェットは第15章 FUT-003、コントロールウィジェットは仕様に無い。
// Xcode のテンプレートが生成した2つ（「My Widget」と Start Timer）をここに残していたため、
// **ウィジェットギャラリーに 😀 の例が出ていた**（2026-08-27 に削除）。
// 仕様が求めていないものを、置いたまま出荷しない。
@main
struct MdoroWidgetBundle: WidgetBundle {
    var body: some Widget {
        MdoroWidgetLiveActivity()
    }
}
