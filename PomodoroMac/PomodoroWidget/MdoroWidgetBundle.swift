import WidgetKit
import SwiftUI

// 8.3: この拡張が提供するのは **Live Activity だけ**。
// ホーム画面ウィジェットは第15章 FUT-003、コントロールウィジェットは仕様に無い。
// **仕様が求めていないものを、置いたまま出荷しない。**
@main
struct MdoroWidgetBundle: WidgetBundle {
    var body: some Widget {
        MdoroWidgetLiveActivity()
    }
}
