// NotchWindowModel.swift
// DynamicNotch / Core / Window
//
// Value-type snapshot of the notch window's geometric and interactive state.

import Foundation
import CoreGraphics

struct NotchWindowModel: Equatable {
    var frame: NSRect
    var isInteractive: Bool
    var isExpanded: Bool
    var cornerRadius: CGFloat

    static let initial = NotchWindowModel(
        frame: .zero,
        isInteractive: false,
        isExpanded: false,
        cornerRadius: 10.0
    )
}
