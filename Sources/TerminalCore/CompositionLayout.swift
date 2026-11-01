import Foundation
import CoreGraphics

public struct CompositionState {
    public struct Segment {
        public let text: String
        public init(_ text: String) { self.text = text }
    }
    public let reading: String
    public let segments: [Segment]
    public let selectedSegment: Int
    public let candidates: [String]
    public let selectedCandidate: Int
    public let converting: Bool
    public init(reading: String, segments: [Segment], selectedSegment: Int, candidates: [String], selectedCandidate: Int, converting: Bool) {
        self.reading = reading; self.segments = segments; self.selectedSegment = selectedSegment
        self.candidates = candidates; self.selectedCandidate = selectedCandidate; self.converting = converting
    }
    public static let empty = Self(reading: "", segments: [], selectedSegment: 0, candidates: [], selectedCandidate: 0, converting: false)
}

public enum CompositionLayout {
    public static func frame(viewport: CGRect, caret: CGRect, desired: CGSize) -> CGRect {
        let inset: CGFloat = 6
        guard viewport.width > inset * 2, viewport.height > inset * 2 else { return .zero }
        let width = max(0, min(desired.width, viewport.width - inset * 2))
        let height = max(0, min(desired.height, viewport.height - inset * 2))
        let x = max(viewport.minX + inset, min(caret.minX, viewport.maxX - inset - width))
        let below = caret.maxY + inset
        let proposedY = below + height <= viewport.maxY - inset ? below : caret.minY - inset - height
        let y = max(viewport.minY + inset, min(proposedY, viewport.maxY - inset - height))
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
