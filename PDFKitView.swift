//
//  PDFKitView.swift
//  TakeoffApp
//
//  Created by Work on 10/10/25.
//
//  A SwiftUI wrapper for PDFKit's PDFView to display PDF documents with optional page selection and smooth zooming support.
//

import SwiftUI
import PDFKit
import AppKit

// MARK: - Notifications

extension Notification.Name {
    static let PDFPageRotationChanged = Notification.Name("PDFPageRotationChanged")
    static let overlayLayerReady = Notification.Name("overlayLayerReady")
}

// MARK: - LockingPDFView Subclass

/// A PDFView subclass that can lock scrolling and gestures except for zooming.
class LockingPDFView: PDFView {
    /// When true, disables scroll, swipe, and gesture events (except magnify/zoom).
    var isScrollLocked = false

    override func scrollWheel(with event: NSEvent) {
        if isScrollLocked {
            // Ignore scroll events when locked.
            return
        }
        super.scrollWheel(with: event)
    }

    override func beginGesture(with event: NSEvent) {
        if isScrollLocked {
            // Ignore gesture events when locked.
            return
        }
        super.beginGesture(with: event)
    }

    override func magnify(with event: NSEvent) {
        if isScrollLocked {
            // Allow zoom/magnify even when locked.
            super.magnify(with: event)
            return
        }
        super.magnify(with: event)
    }

    override func swipe(with event: NSEvent) {
        if isScrollLocked {
            // Ignore swipe events when locked.
            return
        }
        super.swipe(with: event)
    }
}

// MARK: - PDFKitView Representable

struct PDFKitView: NSViewRepresentable {
    let url: URL
    let pageIndex: Int?
    @Binding var pdfTransform: CGAffineTransform
    var overlayLayerProvider: (() -> CALayer?)?

    class Coordinator {
        var overlayLayerProvider: (() -> CALayer?)?
    }
    
    // MARK: - Initialization
    
    /// Initializes the PDFKitView with a PDF URL and an optional page index to display.
    /// - Parameters:
    ///   - url: The URL of the PDF document.
    ///   - pageIndex: Optional index of the page to display initially.
    init(url: URL, pageIndex: Int? = nil, pdfTransform: Binding<CGAffineTransform>, overlayLayerProvider: (() -> CALayer?)? = nil) {
        self.url = url
        self.pageIndex = pageIndex
        self._pdfTransform = pdfTransform
        self.overlayLayerProvider = overlayLayerProvider
    }
    
    // MARK: - NSView Lifecycle
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> PDFView {
        let pdfView = LockingPDFView()
        
        // Automatically scale the PDF to fit the view bounds
        pdfView.autoScales = true
        
        // Display one page at a time
        pdfView.displayMode = .singlePage
        
        // Do not display pages as a book (no page spreads)
        pdfView.displaysAsBook = false
        
        // Disable page breaks display
        pdfView.displaysPageBreaks = false
        
        // Disable scrolling in NSScrollView (no direct isScrollEnabled property in AppKit).
        // Instead, disable scrollers and elasticity to prevent scrolling.
        if let scrollView = pdfView.subviews.compactMap({ $0 as? NSScrollView }).first {
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
            scrollView.verticalScrollElasticity = .none
            scrollView.horizontalScrollElasticity = .none
        }
        
        // Allow dragging (panning)
        pdfView.allowsDragging = true
        
        // Use the crop box for page display
        pdfView.displayBox = .cropBox
        
        // Set background color to clear for seamless UI integration
        pdfView.backgroundColor = .clear
        
        // Load the PDF document from the provided URL
        pdfView.document = PDFDocument(url: url)
        
        // Enable smooth zooming with scroll via scale factors
        pdfView.minScaleFactor = 0.25
        pdfView.maxScaleFactor = 8.0
        
        // Automatically go to the selected page if specified
        if let pageIndex = pageIndex,
           let page = pdfView.document?.page(at: pageIndex) {
            pdfView.go(to: page)
        }
        
        // Compute initial transform + rotation notification
        if let page = pdfView.currentPage {
            let pageBounds = page.bounds(for: .cropBox)
            let pageRect = pdfView.convert(pageBounds, from: page)
            let scaleX = pageRect.width / pageBounds.width
            let scaleY = pageRect.height / pageBounds.height
            let translationX = pageRect.minX - pageBounds.minX * scaleX
            let translationY = pageRect.minY - pageBounds.minY * scaleY
            DispatchQueue.main.async {
                self.pdfTransform = CGAffineTransform(a: scaleX, b: 0, c: 0, d: scaleY, tx: translationX, ty: translationY)
            }
            let rotation = page.rotation
            let radians = CGFloat(rotation) * (.pi / 180)
            NotificationCenter.default.post(name: .PDFPageRotationChanged, object: radians)
            print("📐 Posted PDF rotation angle: \(rotation)° (\(radians) radians)")
        }
        
        // Add listener for zoom changes to perform rerasterization
        NotificationCenter.default.addObserver(forName: .PDFViewScaleChanged, object: pdfView, queue: .main) { _ in
            guard let page = pdfView.currentPage else { return }
            
            // Get the bounds of the page in the crop box coordinate space
            let pageBounds = page.bounds(for: .cropBox)
            
            // Convert page bounds to view coordinates
            let pageRect = pdfView.convert(pageBounds, from: page)
            
            // Calculate scale factors and translation for current transform
            let scaleX = pageRect.width / pageBounds.width
            let scaleY = pageRect.height / pageBounds.height
            let translationX = pageRect.minX - pageBounds.minX * scaleX
            let translationY = pageRect.minY - pageBounds.minY * scaleY
            
            // Update the pdfTransform binding
            self.pdfTransform = CGAffineTransform(a: scaleX, b: 0, c: 0, d: scaleY, tx: translationX, ty: translationY)
            
            // Post rotation notification
            let rotation = page.rotation
            let radians = CGFloat(rotation) * (.pi / 180)
            NotificationCenter.default.post(name: .PDFPageRotationChanged, object: radians)
            print("📐 Posted PDF rotation angle: \(rotation)° (\(radians) radians)")
            
            // Begin rasterization of the current visible page
            
            // Create bitmap context with correct scale and size
            let scale = NSScreen.main?.backingScaleFactor ?? 2.0
            let bitmapSize = NSSize(width: pageBounds.width * scaleX * scale,
                                    height: pageBounds.height * scaleY * scale)
            
            guard let bitmapRep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                                   pixelsWide: Int(bitmapSize.width),
                                                   pixelsHigh: Int(bitmapSize.height),
                                                   bitsPerSample: 8,
                                                   samplesPerPixel: 4,
                                                   hasAlpha: true,
                                                   isPlanar: false,
                                                   colorSpaceName: .calibratedRGB,
                                                   bytesPerRow: 0,
                                                   bitsPerPixel: 0) else {
                return
            }
            
            bitmapRep.size = NSSize(width: pageBounds.width * scaleX, height: pageBounds.height * scaleY)
            
            NSGraphicsContext.saveGraphicsState()
            guard let nsGraphicsContext = NSGraphicsContext(bitmapImageRep: bitmapRep) else { return }
            NSGraphicsContext.current = nsGraphicsContext
            
            // Clear the context
            nsGraphicsContext.cgContext.clear(CGRect(origin: .zero, size: bitmapSize))
            
            // Apply transform to context to scale and translate drawing
            nsGraphicsContext.cgContext.concatenate(CGAffineTransform(scaleX: scale * scaleX, y: scale * scaleY))
            nsGraphicsContext.cgContext.translateBy(x: -pageBounds.minX, y: -pageBounds.minY)
            
            // Draw the PDF page into the context
            page.draw(with: .cropBox, to: nsGraphicsContext.cgContext)
            
            // Access overlay layer through context.coordinator instead of NSGraphicsContext
            if let overlayLayer = context.coordinator.overlayLayerProvider?() {
                overlayLayer.render(in: nsGraphicsContext.cgContext)
            }
            
            nsGraphicsContext.flushGraphics()
            NSGraphicsContext.restoreGraphicsState()
            
            // Create image from bitmapRep
            let rasterizedImage = NSImage(size: bitmapRep.size)
            rasterizedImage.addRepresentation(bitmapRep)
            
            // Set the rasterized image as a layer content to redraw the view
            DispatchQueue.main.async {
                if pdfView.layer == nil {
                    pdfView.wantsLayer = true
                }
                pdfView.layer?.contents = rasterizedImage
            }
        }
        
        return pdfView
    }
    
    func updateNSView(_ nsView: PDFView, context: Context) {
        // If using LockingPDFView, control scroll locking based on page selection
        if let lockingPDFView = nsView as? LockingPDFView {
            lockingPDFView.isScrollLocked = (pageIndex != nil)
        }
        // Enforce single-page mode and disable scrolling when a page is selected
        if let _ = pageIndex {
            nsView.displayMode = .singlePage
            nsView.displaysAsBook = false
            nsView.displaysPageBreaks = false
            nsView.autoScales = true
            if let scrollView = nsView.subviews.compactMap({ $0 as? NSScrollView }).first {
                scrollView.hasVerticalScroller = false
                scrollView.hasHorizontalScroller = false
                scrollView.verticalScrollElasticity = .none
                scrollView.horizontalScrollElasticity = .none
            }
            nsView.allowsDragging = true
        }
        
        // Update the displayed page if the pageIndex changes
        if let pageIndex = pageIndex,
           let page = nsView.document?.page(at: pageIndex) {
            nsView.go(to: page)
            nsView.autoScales = true
            // After changing page, post rotation notification
            let rotation = page.rotation
            let radians = CGFloat(rotation) * (.pi / 180)
            NotificationCenter.default.post(name: .PDFPageRotationChanged, object: radians)
            print("📐 Posted PDF rotation angle: \(rotation)° (\(radians) radians)")
        } else if let page = nsView.currentPage {
            // If pageIndex didn't change but page is current, post rotation
            let rotation = page.rotation
            let radians = CGFloat(rotation) * (.pi / 180)
            NotificationCenter.default.post(name: .PDFPageRotationChanged, object: radians)
            print("📐 Posted PDF rotation angle: \(rotation)° (\(radians) radians)")
        }
        
        // Keep pdfTransform in sync on zoom changes initiated after creation
        NotificationCenter.default.addObserver(forName: .PDFViewScaleChanged, object: nsView, queue: .main) { _ in
            if let page = nsView.currentPage {
                let pageBounds = page.bounds(for: .cropBox)
                let pageRect = nsView.convert(pageBounds, from: page)
                let scaleX = pageRect.width / pageBounds.width
                let scaleY = pageRect.height / pageBounds.height
                let translationX = pageRect.minX - pageBounds.minX * scaleX
                let translationY = pageRect.minY - pageBounds.minY * scaleY
                self.pdfTransform = CGAffineTransform(a: scaleX, b: 0, c: 0, d: scaleY, tx: translationX, ty: translationY)
                // Post rotation notification on scale
                let rotation = page.rotation
                let radians = CGFloat(rotation) * (.pi / 180)
                NotificationCenter.default.post(name: .PDFPageRotationChanged, object: radians)
                print("📐 Posted PDF rotation angle: \(rotation)° (\(radians) radians)")
            }
        }
        
        // Connect the live overlay layer from DrawingOverlayView to the PDFView for unified rasterization on zoom/scale updates
        NotificationCenter.default.addObserver(forName: .overlayLayerReady, object: nil, queue: .main) { notification in
            guard let overlayLayer = notification.object as? CALayer else { return }
            // Replace any existing overlayLayerProvider with a provider returning this layer
            context.coordinator.overlayLayerProvider = { overlayLayer }
            // Trigger a re-render pass to sync PDF and overlay
            nsView.needsDisplay = true
        }
    }
}
