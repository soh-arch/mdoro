import WidgetKit
import SwiftUI

// 8.3: what this extension provides is **the Live Activity only**.
// A home screen widget is chapter 15's FUT-003; a control widget is not in the spec at all.
// **Do not ship with something the spec does not ask for left in place.**
@main
struct MdoroWidgetBundle: WidgetBundle {
    var body: some Widget {
        MdoroWidgetLiveActivity()
    }
}
