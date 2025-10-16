import SwiftUI
import AppKit

struct DrawingOverlayView: NSViewRepresentable {
    @Binding var points: [CGPoint]
    var color: Color
    var isDrawing: Bool
    var takeoffType: String
    var pdfTransform: CGAffineTransform?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> DrawingNSView {
        let view = DrawingNSView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: DrawingNSView, context: Context) {
        nsView.points = points
        nsView.color = color
        nsView.isDrawing = isDrawing
        nsView.takeoffType = takeoffType
        nsView.pdfTransform = pdfTransform
        nsView.needsDisplay = true
    }

    class Coordinator: NSObject {
        var parent: DrawingOverlayView
        init(_ parent: DrawingOverlayView) {
            self.parent = parent
        }
    }

    class DrawingNSView: NSView {
        weak var coordinator: Coordinator?
        var points: [CGPoint] = []
        var color: Color = .blue
        var isDrawing: Bool = false
        var takeoffType: String = "Linear"
        var pdfTransform: CGAffineTransform? = nil

        private var currentPoint: CGPoint? = nil
        private var firstClick: CGPoint? = nil

        override var acceptsFirstResponder: Bool { true }

        override func mouseDown(with event: NSEvent) {
            guard isDrawing else { return }
            let location = convert(event.locationInWindow, from: nil)

            if firstClick == nil {
                firstClick = location
            } else {
                var updated = points
                updated.append(firstClick!)
                updated.append(location)
                coordinator?.parent.points = updated
                // ✅ Continue from this point instead of resetting
                firstClick = location
                currentPoint = nil
            }
            needsDisplay = true
        }

        override func mouseMoved(with event: NSEvent) {
            guard isDrawing, firstClick != nil else { return }
            currentPoint = convert(event.locationInWindow, from: nil)
            needsDisplay = true // ✅ Always refresh while drawing
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach { removeTrackingArea($0) }
            let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
            addTrackingArea(area)
        }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            guard let context = NSGraphicsContext.current?.cgContext else { return }

            // ✅ Prevent stale preview
            if firstClick == nil {
                currentPoint = nil
            }

            context.setLineWidth(2)
            context.setStrokeColor((color.cgColor).flatMap { NSColor(cgColor: $0)?.cgColor } ?? NSColor.systemBlue.cgColor)
            context.setLineCap(.round)

            // Draw finalized lines
            for i in stride(from: 0, to: points.count, by: 2) {
                if i + 1 < points.count {
                    context.move(to: points[i])
                    context.addLine(to: points[i + 1])
                }
            }
            context.strokePath()

            // Draw preview line
            if let start = firstClick, let current = currentPoint {
                context.setStrokeColor(NSColor.systemBlue.withAlphaComponent(0.5).cgColor)
                context.move(to: start)
                context.addLine(to: current)
                context.strokePath()
            }
        }
    }
}
