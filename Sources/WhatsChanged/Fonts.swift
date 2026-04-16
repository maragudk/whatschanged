import SwiftUI
import AppKit

enum AppFont {
    private static let preferredFamily = "MonoLisa"

    private static var isAvailable: Bool {
        NSFontManager.shared.availableMembers(ofFontFamily: preferredFamily) != nil
    }

    static let body: Font = isAvailable
        ? .custom(preferredFamily, size: NSFont.systemFontSize)
        : .system(.body, design: .monospaced)

    static let bodySemibold: Font = isAvailable
        ? .custom(preferredFamily, size: NSFont.systemFontSize).weight(.semibold)
        : .system(.body, design: .monospaced, weight: .semibold)

    static let caption: Font = isAvailable
        ? .custom(preferredFamily, size: NSFont.smallSystemFontSize)
        : .system(.caption, design: .monospaced)
}
