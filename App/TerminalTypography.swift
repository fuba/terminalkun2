import UIKit

@MainActor
enum TerminalTypography {
    static let tracking: CGFloat = -0.2
    static func font(name: String, size: CGFloat) -> UIFont {
        let base = UIFont(name: name, size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
        // Let SwiftTerm measure the compact font so rendering and hit testing share one grid.
        let descriptor = base.fontDescriptor.withMatrix(CGAffineTransform(scaleX: 0.94, y: 1))
        return UIFont(descriptor: descriptor, size: size)
    }
}
