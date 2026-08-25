//
//  PomodoroWidgetBundle.swift
//  PomodoroWidget
//
//  Created by Sohta Uchiyama on 8/25/26.
//

import WidgetKit
import SwiftUI

@main
struct PomodoroWidgetBundle: WidgetBundle {
    var body: some Widget {
        PomodoroWidget()
        PomodoroWidgetControl()
        PomodoroWidgetLiveActivity()
    }
}
