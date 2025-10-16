
import SwiftUI
import PDFKit

// ============================================================
// MARK: - Codable Extension for CGPoint
// Enables encoding/decoding of CGPoint for persistence.
// ============================================================
extension CGPoint: Codable {
    enum CodingKeys: String, CodingKey { case x, y }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Double(x), forKey: .x)
        try container.encode(Double(y), forKey: .y)
    }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(x: try container.decode(Double.self, forKey: .x),
                  y: try container.decode(Double.self, forKey: .y))
    }
}

// ============================================================
// MARK: - Models
// Data models for takeoff items and projects.
// ============================================================
struct TakeoffItem: Identifiable, Codable, Equatable, Hashable {
    var id = UUID()
    var name: String
    var type: String
    var color: ColorCodable
    var pageIndex: Int?
    var drawings: [CGPoint] = []

    // Live calculation fields
    var quantity: Double = 0.0
    var unit: String = "ft" // could be "ft", "yd²", "ct"
    var pricePerUnit: Double? = nil

    var totalCost: Double? {
        guard let price = pricePerUnit else { return nil }
        return quantity * price
    }
}

struct TakeoffProject: Identifiable, Codable, Equatable, Hashable {
    var id = UUID()
    var name: String
    var pdfURL: URL
    var takeoffs: [TakeoffItem] = []
}

// ============================================================
// MARK: - Color Wrapper
// Codable wrapper for Color to persist color selections.
// ============================================================
struct ColorCodable: Codable, Hashable {
    var red: Double
    var green: Double
    var blue: Double
    var opacity: Double

    init(_ color: Color) {
        if let cgColor = color.cgColor,
           let nsColor = NSColor(cgColor: cgColor)?.usingColorSpace(.deviceRGB) {
            red = Double(nsColor.redComponent)
            green = Double(nsColor.greenComponent)
            blue = Double(nsColor.blueComponent)
            opacity = Double(nsColor.alphaComponent)
        } else {
            red = 0.0
            green = 0.0
            blue = 1.0
            opacity = 1.0
        }
    }

    var swiftUIColor: Color {
        Color(red: red, green: green, blue: blue, opacity: opacity)
    }
}

// ============================================================
// MARK: - Helper for Page Thumbnails
// Generates thumbnails for each PDF page for quick selection.
// ============================================================
func generatePageThumbnails(from document: PDFDocument) -> [NSImage] {
    var thumbnails: [NSImage] = []
    for i in 0..<document.pageCount {
        if let page = document.page(at: i) {
            let thumbnail = page.thumbnail(of: CGSize(width: 800, height: 1040), for: .cropBox)
            thumbnails.append(thumbnail)
        }
    }
    return thumbnails
}

// ============================================================
// MARK: - Geometry Calculations
// Utility functions for calculating quantities from points.
// ============================================================
func calculateTakeoffQuantity(for points: [CGPoint], type: String, scale: String) -> (quantity: Double, unit: String) {
    guard !points.isEmpty else { return (0.0, "") }

    switch type {
    case "Linear":
        var totalLength: CGFloat = 0
        for i in 1..<points.count {
            let dx = points[i].x - points[i - 1].x
            let dy = points[i].y - points[i - 1].y
            totalLength += sqrt(dx * dx + dy * dy)
        }
        let factor = scaleConversion(for: scale)
        return (Double(totalLength * factor), "ft")

    case "Area":
        guard points.count > 2 else { return (0.0, "yd²") }
        var area: CGFloat = 0
        for i in 0..<points.count {
            let j = (i + 1) % points.count
            area += points[i].x * points[j].y
            area -= points[j].x * points[i].y
        }
        area = abs(area) / 2.0
        let factor = scaleConversion(for: scale)
        return (Double(area * factor * factor), "yd²")

    case "Count":
        return (Double(points.count), "ct")

    default:
        return (0.0, "")
    }
}

func scaleConversion(for scale: String) -> CGFloat {
    // Expect formats like: `1/16" = 1'`, `3/8" = 1'`, `1/4" = 1'`, or `1" = 1'`
    // We return FEET PER PDF POINT.
    // 1 point = 1/72 inch; if X inches on paper = 1 ft real, then feet/point = 1 / (72 * X).
    let left = scale.components(separatedBy: "=").first?
        .trimmingCharacters(in: .whitespaces) ?? "1/8\""
    
    // Strip the trailing quote
    let inchesToken = left.replacingOccurrences(of: "\"", with: "")
                          .trimmingCharacters(in: .whitespaces)
    
    let inchesPerFoot: Double
    if inchesToken.contains("/") {
        let parts = inchesToken.split(separator: "/").map { String($0) }
        if parts.count == 2, let num = Double(parts[0]), let den = Double(parts[1]), den != 0 {
            inchesPerFoot = num / den
        } else {
            inchesPerFoot = 0.125 // fallback to 1/8"
        }
    } else {
        inchesPerFoot = Double(inchesToken) ?? 1.0 // e.g., "1" -> 1.0 inch per foot
    }
    
    guard inchesPerFoot > 0 else { return 1.0 } // safe fallback
    
    let feetPerPoint = 1.0 / (72.0 * inchesPerFoot)
    return CGFloat(feetPerPoint)
}

// ============================================================
// MARK: - ContentView
// Main view: project sidebar, takeoff list, and drawing canvas.
// ============================================================
struct ContentView: View {
    @State private var selectedScale = "1/8\" = 1'"
    @State private var pdfURL: URL?
    @State private var projects: [TakeoffProject] = []
    @State private var selectedProject: TakeoffProject?
    @State private var showNewTakeoffSheet = false
    @State private var newTakeoffName = ""
    @State private var newTakeoffType = "Area"
    @State private var newTakeoffColor = Color.blue
    @State private var editingTakeoff: TakeoffItem?
    @State private var isEditingTakeoff = false
    @State private var showPageSelector = false
    @State private var pageCount = 0
    @State private var selectedPageIndex: Int?
    @State private var isDrawing = false
    @State private var currentPoints: [CGPoint] = []
    @State private var selectedTakeoff: TakeoffItem?
    @State private var pdfViewRef: PDFView? = nil

    var body: some View {
        HStack(spacing: 0) {
            // ============================================================
            // MARK: - Sidebar UI
            // Project and takeoff list, new project/takeoff buttons.
            // ============================================================
            VStack(alignment: .leading, spacing: 16) {
                Text("📁 Takeoff Projects")
                    .font(.headline)
                Button("➕ New Project") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.pdf]
                    panel.allowsMultipleSelection = false
                    panel.canChooseDirectories = false
                    panel.title = "Select a PDF Plan Set"
                    if panel.runModal() == .OK {
                        if let url = panel.url {
                            let name = url.deletingPathExtension().lastPathComponent
                            let documentsURL = getDocumentsDirectory()
                            let destinationURL = documentsURL.appendingPathComponent(url.lastPathComponent)
                            do {
                                if !FileManager.default.fileExists(atPath: destinationURL.path) {
                                    try FileManager.default.copyItem(at: url, to: destinationURL)
                                }
                                let newProject = TakeoffProject(name: name, pdfURL: destinationURL)
                                projects.append(newProject)
                                selectedProject = newProject
                                pdfURL = destinationURL
                                selectedPageIndex = nil
                                isDrawing = false
                                selectedTakeoff = nil
                                print("Created new takeoff and copied PDF to Documents: \(destinationURL.path)")
                            } catch {
                                print("❌ Failed to copy PDF: \(error)")
                            }
                        }
                    }
                }
                Divider()
                List(selection: $selectedProject) {
                    ForEach(projects) { project in
                        // DisclosureGroup for each project
                        DisclosureGroup(
                            isExpanded: Binding(
                                get: {
                                    selectedProject?.id == project.id
                                },
                                set: { expanded in
                                    if expanded {
                                        selectedProject = project
                                        pdfURL = project.pdfURL
                                        selectedPageIndex = nil
                                        isDrawing = false
                                        selectedTakeoff = nil
                                    }
                                }
                            )
                        ) {
                            // Highlight the active page in the sidebar when in single-page mode.
                            if let doc = PDFDocument(url: project.pdfURL) {
                                ForEach(0..<doc.pageCount, id: \.self) { idx in
                                    Button(action: {
                                        // Trigger single-page focus mode: set selectedProject, pdfURL, and selectedPageIndex.
                                        selectedProject = project
                                        pdfURL = project.pdfURL
                                        selectedPageIndex = idx
                                    }) {
                                        HStack(spacing: 6) {
                                            if project.takeoffs.contains(where: { $0.pageIndex == idx }) {
                                                Circle()
                                                    .fill(Color.red)
                                                    .frame(width: 8, height: 8)
                                            }
                                            Text("Page \(idx + 1)")
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .padding(.leading, 12)
                                        .background(
                                            (selectedProject?.id == project.id && selectedPageIndex == idx)
                                            ? Color.blue.opacity(0.01)
                                            : Color.clear
                                        )
                                        .cornerRadius(4)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .listRowBackground(
                                        (selectedProject?.id == project.id && selectedPageIndex == idx)
                                            ? AnyView(
                                                RoundedRectangle(cornerRadius: 4)
                                                    .fill(Color.blue.opacity(0.18))
                                            )
                                            : AnyView(Color.clear)
                                    )
                                }
                            }
                        } label: {
                            Text(project.name)
                                .fontWeight(selectedProject?.id == project.id ? .bold : .regular)
                                .tag(project as TakeoffProject?)
                                .onTapGesture {
                                    selectedProject = project
                                    pdfURL = project.pdfURL
                                    selectedPageIndex = nil
                                    isDrawing = false
                                    selectedTakeoff = nil
                                }
                        }
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(
                                    selectedProject?.id == project.id
                                        ? Color.blue.opacity(1)
                                        : Color.clear
                                )
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                        )
                        .contextMenu {
                            Button("Rename") { renameProject(project) }
                            Button("Delete", role: .destructive) { deleteProject(project) }
                        }
                    }
                }
                .listStyle(.automatic)
                .frame(minHeight: 200)
                Divider()
                HStack {
                    Text("Takeoffs")
                        .font(.headline)
                    Spacer()
                    Button("➕ New Takeoff") {
                        newTakeoffName = ""
                        newTakeoffType = "Area"
                        editingTakeoff = nil
                        isEditingTakeoff = false
                        showNewTakeoffSheet = true
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .cornerRadius(6)
                    .font(.system(size: 13))
                }
                if let project = selectedProject {
                    List(selection: $selectedTakeoff) {
                        ForEach(project.takeoffs) { takeoff in
                            // Highlight the active takeoff in the sidebar list when selected.
                            HStack {
                                TakeoffRowView(
                                    takeoff: takeoff,
                                    project: project,
                                    projects: $projects,
                                    selectedProject: $selectedProject,
                                    selectedTakeoff: $selectedTakeoff,
                                    editingTakeoff: $editingTakeoff,
                                    isEditingTakeoff: $isEditingTakeoff,
                                    newTakeoffName: $newTakeoffName,
                                    newTakeoffType: $newTakeoffType,
                                    newTakeoffColor: $newTakeoffColor,
                                    showNewTakeoffSheet: $showNewTakeoffSheet
                                )
                            }
                            .padding(.vertical, 2)
                            .padding(.horizontal, 4)
                            .background(
                                (selectedTakeoff?.id == takeoff.id)
                                    ? Color.blue.opacity(0.18)
                                    : Color.clear
                            )
                            .cornerRadius(4)
                            .tag(takeoff as TakeoffItem?)
                            .onTapGesture {
                                selectedTakeoff = takeoff
                            }
                        }
                    }
                    .frame(minHeight: 100, maxHeight: 200)
                } else {
                    List {
                        Text("")
                    }
                    .frame(minHeight: 100, maxHeight: 200)
                }
            }
            .padding()
            .frame(width: 250)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // ============================================================
            // MARK: - Main Canvas
            // Displays PDF page thumbnails or the drawing canvas view.
            // ============================================================
            VStack {
                if let project = selectedProject,
                   let document = PDFDocument(url: project.pdfURL) {
                    if let pageIndex = selectedPageIndex {
                        PageCanvasView(
                            project: project,
                            pageIndex: pageIndex,
                            selectedTakeoff: $selectedTakeoff,
                            isDrawing: $isDrawing,
                            selectedScale: selectedScale,
                            projects: $projects,
                            selectedProject: $selectedProject,
                            pdfViewRef: $pdfViewRef,
                            selectedPageIndex: $selectedPageIndex
                        )
                    } else {
                        // Show thumbnails for all pages
                        ScrollView {
                            let thumbnails = generatePageThumbnails(from: document)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 860), spacing: 8)], spacing: 8) {
                                ForEach(Array(thumbnails.enumerated()), id: \.offset) { idx, thumb in
                                    Button(action: {
                                        selectedPageIndex = idx
                                    }) {
                                        VStack {
                                            Image(nsImage: thumb)
                                                .resizable()
                                                .aspectRatio(contentMode: .fit)
                                                .frame(width: 560, height: 720)
                                                .cornerRadius(8)
                                            HStack(spacing: 6) {
                                                if let project = selectedProject, project.takeoffs.contains(where: { $0.pageIndex == idx }) {
                                                    Circle()
                                                        .fill(Color.red)
                                                        .frame(width: 8, height: 8)
                                                }
                                                Text("Page \(idx + 1)")
                                                    .font(.caption)
                                                    .padding(.top, 0)
                                                Spacer()
                                            }
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                            .padding(0)
                        }
                    }
                } else {
                    VStack {
                        Text("Drawing Canvas Area")
                            .font(.largeTitle)
                            .foregroundColor(.gray)
                        Text("(Upload a PDF to begin)")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: CGFloat.infinity, maxHeight: CGFloat.infinity)
                }
            }
        }
        // ============================================================
        // MARK: - Takeoff Sheet
        // Sheet for creating or editing a takeoff.
        // ============================================================
        .sheet(isPresented: $showNewTakeoffSheet) {
            VStack(alignment: .leading, spacing: 20) {
                Text(isEditingTakeoff ? "Edit Takeoff" : "New Takeoff")
                    .font(.title2)
                    .padding(.bottom, 10)
                // Takeoff Name
                HStack {
                    Text("Takeoff Name")
                        .frame(width: 110, alignment: .leading)
                    TextField("Name", text: $newTakeoffName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                // Type Picker
                HStack {
                    Text("Type")
                        .frame(width: 110, alignment: .leading)
                    Picker("Type", selection: $newTakeoffType) {
                        ForEach(["Area", "Linear", "Count"], id: \.self) { type in
                            Text(type).tag(type)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                // Color Picker
                HStack {
                    Text("Color")
                        .frame(width: 110, alignment: .leading)
                    ColorPicker("Color", selection: $newTakeoffColor)
                        .labelsHidden()
                }
                // Scale Picker
                HStack {
                    Text("Scale")
                        .frame(width: 110, alignment: .leading)
                    Picker("Scale", selection: $selectedScale) {
                        ForEach([
                            "1/16\" = 1'",
                            "1/8\" = 1'",
                            "1/4\" = 1'",
                            "1/2\" = 1'",
                            "1\" = 1'"
                        ], id: \.self) { scale in
                            Text(scale).tag(scale)
                        }
                    }
                    .labelsHidden()
                }
                Spacer()
                HStack {
                    Spacer()
                    Button("Cancel") {
                        showNewTakeoffSheet = false
                    }
                    Button(isEditingTakeoff ? "Save" : "Add") {
                        guard let project = selectedProject,
                              let projectIndex = projects.firstIndex(where: { $0.id == project.id }) else {
                            showNewTakeoffSheet = false
                            return
                        }
                        if isEditingTakeoff, let editing = editingTakeoff,
                           let takeoffIndex = projects[projectIndex].takeoffs.firstIndex(where: { $0.id == editing.id }) {
                            // Update existing takeoff
                            projects[projectIndex].takeoffs[takeoffIndex].name = newTakeoffName
                            projects[projectIndex].takeoffs[takeoffIndex].type = newTakeoffType
                            projects[projectIndex].takeoffs[takeoffIndex].color = ColorCodable(newTakeoffColor)
                            // Optionally update scale if you want scale per-takeoff
                            // projects[projectIndex].takeoffs[takeoffIndex].scale = selectedScale
                            // If you want to update selectedTakeoff, do so:
                            selectedTakeoff = projects[projectIndex].takeoffs[takeoffIndex]
                        } else {
                            // Create new takeoff
                            let newTakeoff = TakeoffItem(
                                name: newTakeoffName.isEmpty ? "Untitled" : newTakeoffName,
                                type: newTakeoffType,
                                color: ColorCodable(newTakeoffColor),
                                pageIndex: nil
                            )
                            projects[projectIndex].takeoffs.append(newTakeoff)
                            // Optionally select new takeoff
                            selectedTakeoff = projects[projectIndex].takeoffs.last
                        }
                        saveProjects()
                        showNewTakeoffSheet = false
                        editingTakeoff = nil
                        isEditingTakeoff = false
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
            .frame(width: 400, height: 320)
        }
        .onAppear { loadProjects() }
        .onChange(of: projects) { _ in saveProjects() }
    }

    // ============================================================
    // MARK: - Persistence
    // Helpers for loading and saving projects to disk.
    // ============================================================
    func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    func saveProjects() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(projects)
            let url = getDocumentsDirectory().appendingPathComponent("projects.json")
            try data.write(to: url)
            print("✅ Projects saved to \(url.path)")
        } catch {
            print("❌ Failed to save projects: \(error)")
        }
    }

    func loadProjects() {
        let url = getDocumentsDirectory().appendingPathComponent("projects.json")
        guard let data = try? Data(contentsOf: url) else { return }
        do {
            let decoder = JSONDecoder()
            let decoded = try decoder.decode([TakeoffProject].self, from: data)
            projects = decoded
            print("✅ Loaded \(projects.count) projects")
        } catch {
            print("❌ Failed to load projects: \(error)")
        }
    }

    // ============================================================
    // MARK: - PDFKitView
    // NSViewRepresentable wrapper for displaying a PDF page.
    // ============================================================
    struct PDFKitView: NSViewRepresentable {
        let url: URL
        let pageIndex: Int
        @Binding var pdfViewRef: PDFView?

        func makeNSView(context: Context) -> PDFView {
            let pdfView = PDFView()
            pdfView.autoScales = true
            if let doc = PDFDocument(url: url) {
                pdfView.document = doc
                if let page = doc.page(at: min(max(0, pageIndex), doc.pageCount - 1)) {
                    pdfView.go(to: page)
                }
            }
            DispatchQueue.main.async {
                self.pdfViewRef = pdfView
            }
            return pdfView
        }

        func updateNSView(_ nsView: PDFView, context: Context) {
            if nsView.document?.documentURL != url {
                if let doc = PDFDocument(url: url) {
                    nsView.document = doc
                }
            }
            if let doc = nsView.document {
                let safeIndex = min(max(0, pageIndex), max(0, doc.pageCount - 1))
                if let page = doc.page(at: safeIndex), nsView.currentPage != page {
                    nsView.go(to: page)
                }
            }
            nsView.autoScales = true
            DispatchQueue.main.async {
                self.pdfViewRef = nsView
            }
        }
    }
}

// ============================================================
// MARK: - PageCanvasView
// Displays the PDF page canvas and handles drawing overlays.
// ============================================================
struct PageCanvasView: View {
    let project: TakeoffProject
    let pageIndex: Int
    @Binding var selectedTakeoff: TakeoffItem?
    @Binding var isDrawing: Bool
    let selectedScale: String
    @Binding var projects: [TakeoffProject]
    @Binding var selectedProject: TakeoffProject?
    @Binding var pdfViewRef: PDFView?
    @Binding var selectedPageIndex: Int?

    // --- Live quantity preview state ---
    @State private var liveQuantity: Double = 0
    @State private var liveUnit: String = ""

    // --- Helper to recalculate live quantity and unit preview ---
    private func recalcLiveQuantity() {
        guard isDrawing,
              let activeTakeoff = selectedTakeoff,
              let projectIndex = projects.firstIndex(where: { $0.id == selectedProject?.id }),
              let takeoffIndex = projects[projectIndex].takeoffs.firstIndex(where: { $0.id == selectedTakeoff?.id }),
              let pdfView = pdfViewRef,
              let page = pdfView.currentPage else {
            // If we can't compute live quantity safely, clear the preview
            liveQuantity = 0
            liveUnit = ""
            return
        }

        let rawPoints = projects[projectIndex].takeoffs[takeoffIndex].drawings
        // Minimum points needed depending on takeoff type
        switch activeTakeoff.type {
        case "Linear":
            guard rawPoints.count >= 2 else { liveQuantity = 0; liveUnit = "ft"; return }
        case "Area":
            guard rawPoints.count >= 3 else { liveQuantity = 0; liveUnit = "yd²"; return }
        case "Count":
            guard !rawPoints.isEmpty else { liveQuantity = 0; liveUnit = "ct"; return }
        default:
            break
        }

        // Convert to PDF page space (consistent with Finish Takeoff)
        let converted = rawPoints.map { pdfView.convert($0, to: page) }
        let (qty, unit) = calculateTakeoffQuantity(for: converted, type: activeTakeoff.type, scale: selectedScale)
        liveQuantity = qty
        liveUnit = unit
    }

    // MARK: - Computed subviews
    var pdfLayer: some View {
        // Use the new single-page lock behavior in PDFKitView.
        ContentView.PDFKitView(url: project.pdfURL, pageIndex: pageIndex, pdfViewRef: $pdfViewRef)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var savedDrawingsLayer: some View {
        Group {
            if let activeTakeoff = selectedTakeoff,
               let projectIndex = projects.firstIndex(where: { $0.id == selectedProject?.id }),
               let takeoffIndex = projects[projectIndex].takeoffs.firstIndex(where: { $0.id == activeTakeoff.id }) {
                let transform = pdfViewRef?.currentPage?.transform(for: .cropBox) ?? .identity
                DrawingOverlayView(
                    points: $projects[projectIndex].takeoffs[takeoffIndex].drawings,
                    color: activeTakeoff.color.swiftUIColor,
                    isDrawing: false,
                    takeoffType: activeTakeoff.type,
                    pdfTransform: transform
                )
            }
        }
    }

    var activeDrawingLayer: some View {
        Group {
            if isDrawing, let _ = selectedTakeoff {
                if let projectIndex = projects.firstIndex(where: { $0.id == selectedProject?.id }),
                   let takeoffIndex = projects[projectIndex].takeoffs.firstIndex(where: { $0.id == selectedTakeoff?.id }) {
                    let transform = pdfViewRef?.currentPage?.transform(for: .cropBox) ?? .identity
                    DrawingOverlayView(
                        points: $projects[projectIndex].takeoffs[takeoffIndex].drawings,
                        color: projects[projectIndex].takeoffs[takeoffIndex].color.swiftUIColor,
                        isDrawing: isDrawing,
                        takeoffType: projects[projectIndex].takeoffs[takeoffIndex].type,
                        pdfTransform: transform
                    )
                    .opacity(1)
                }
            }
        }
    }

    var toolbarLayer: some View {
        VStack {
            HStack(spacing: 12) {
                Button("🔙 Back to All Pages") {
                    selectedPageIndex = nil
                }
                .padding(8)
                .background(.thinMaterial)
                .cornerRadius(6)

                if !isDrawing {
                    Button("✏️ Start Takeoff") {
                        isDrawing = true
                        // No need to reset points, handled by direct binding now
                    }
                    .padding(8)
                    .background(.green.opacity(0.2))
                    .cornerRadius(6)
                } else {
                    Button("✅ Finish Takeoff") {
                        print("✅ Finish Takeoff button tapped")
                        guard let projectIndex = projects.firstIndex(where: { $0.id == selectedProject?.id }),
                              let takeoffIndex = projects[projectIndex].takeoffs.firstIndex(where: { $0.id == selectedTakeoff?.id }) else {
                            print("❌ Project or takeoff index not found.")
                            return
                        }

                        var updatedTakeoff = projects[projectIndex].takeoffs[takeoffIndex]
                        let livePoints = updatedTakeoff.drawings
                        if let pdfView = pdfViewRef, let page = pdfView.currentPage {
                            let convertedPoints = livePoints.map { pdfView.convert($0, to: page) }
                            let (qty, unit) = calculateTakeoffQuantity(for: convertedPoints, type: updatedTakeoff.type, scale: selectedScale)
                            updatedTakeoff.quantity = qty
                            updatedTakeoff.unit = unit
                            updatedTakeoff.pageIndex = pageIndex
                            print("📏 Calculated quantity: \(qty) \(unit)")
                            projects[projectIndex].takeoffs[takeoffIndex] = updatedTakeoff
                            selectedTakeoff = projects[projectIndex].takeoffs[takeoffIndex]
                            selectedProject = projects[projectIndex]
                        } else {
                            print("❌ Could not find PDFView or current page.")
                        }

                        isDrawing = false
                    }
                    .padding(8)
                    .background(.blue.opacity(0.2))
                    .cornerRadius(6)

                    Button("🗑 Reset") {
                        if let projectIndex = projects.firstIndex(where: { $0.id == selectedProject?.id }),
                           let takeoffIndex = projects[projectIndex].takeoffs.firstIndex(where: { $0.id == selectedTakeoff?.id }) {
                            projects[projectIndex].takeoffs[takeoffIndex].drawings = []
                        }
                    }
                    .padding(8)
                    .background(.red.opacity(0.2))
                    .cornerRadius(6)
                }

                Spacer()
            }
            Spacer()
        }
        .padding()
    }

    var quantityPreviewLayer: some View {
        VStack {
            HStack {
                Spacer()
                if isDrawing, liveUnit.isEmpty == false {
                    Text("📏 " + (liveQuantity >= 1000 ? String(format: "%.0f %@", liveQuantity, liveUnit) : String(format: "%.2f %@", liveQuantity, liveUnit)))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThickMaterial)
                        .cornerRadius(8)
                }
            }
            Spacer()
        }
        .padding()
    }

    var body: some View {
        ZStack {
            pdfLayer
            savedDrawingsLayer
            activeDrawingLayer
            toolbarLayer
            quantityPreviewLayer
        }
        .onAppear { recalcLiveQuantity() }
        .onChange(of: projects) { _ in recalcLiveQuantity() }
        .onChange(of: selectedTakeoff) { _ in recalcLiveQuantity() }
        .onChange(of: isDrawing) { _ in recalcLiveQuantity() }
        .onChange(of: selectedScale) { _ in recalcLiveQuantity() }
    }
}

// ============================================================
// MARK: - DrawingOverlayView
// (Assume DrawingOverlayView is defined elsewhere in your codebase)
// Handles user drawing overlays for takeoff items.
// ============================================================
// (See implementation note for persistence in DrawingOverlayView.)

// ============================================================
// MARK: - TakeoffRowView
// Renders a single row in the takeoff list.
// ============================================================
struct TakeoffRowView: View {
    let takeoff: TakeoffItem
    let project: TakeoffProject
    @Binding var projects: [TakeoffProject]
    @Binding var selectedProject: TakeoffProject?
    @Binding var selectedTakeoff: TakeoffItem?
    @Binding var editingTakeoff: TakeoffItem?
    @Binding var isEditingTakeoff: Bool
    @Binding var newTakeoffName: String
    @Binding var newTakeoffType: String
    @Binding var newTakeoffColor: Color
    @Binding var showNewTakeoffSheet: Bool

    var body: some View {
        HStack {
            Circle()
                .fill(takeoff.color.swiftUIColor)
                .frame(width: 12, height: 12)
            VStack(alignment: .leading) {
                HStack {
                    Text(takeoff.name)
                    if takeoff.quantity > 0 {
                        Text(String(format: "%.1f %@", takeoff.quantity, takeoff.unit))
                            .foregroundColor(.secondary)
                        if let total = takeoff.totalCost {
                            Text(String(format: "($%.2f)", total))
                                .foregroundColor(.gray)
                        }
                    }
                }
                Text(takeoff.type)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .contextMenu {
            Button("Edit") {
                editingTakeoff = takeoff
                newTakeoffName = takeoff.name
                newTakeoffType = takeoff.type
                newTakeoffColor = takeoff.color.swiftUIColor
                isEditingTakeoff = true
                showNewTakeoffSheet = true
            }
            Button("Delete", role: .destructive) {
                if let projectIndex = projects.firstIndex(where: { $0.id == project.id }) {
                    withAnimation {
                        projects[projectIndex].takeoffs.removeAll { $0.id == takeoff.id }
                    }
                    // 🧠 Reset selectedTakeoff if it was the one deleted
                    if selectedTakeoff?.id == takeoff.id {
                        selectedTakeoff = nil
                    }
                    // Also ensure editing state resets
                    if editingTakeoff?.id == takeoff.id {
                        editingTakeoff = nil
                        isEditingTakeoff = false
                    }
                    // Refresh selected project for UI consistency
                    selectedProject = projects[projectIndex]
                }
            }
        }
    }
}

// ============================================================
// MARK: - Project Context Menu Helpers
// Functions for renaming and deleting projects.
// ============================================================
extension ContentView {
    func renameProject(_ project: TakeoffProject) {
        let alert = NSAlert()
        alert.messageText = "Rename Project"
        alert.informativeText = "Enter a new project name:"
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        input.stringValue = project.name
        alert.accessoryView = input
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            if let index = projects.firstIndex(where: { $0.id == project.id }) {
                projects[index].name = input.stringValue
                selectedProject = projects[index]
            }
        }
    }

    func deleteProject(_ project: TakeoffProject) {
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects.remove(at: index)
            if selectedProject?.id == project.id {
                selectedProject = nil
                pdfURL = nil
            }
        }
    }
}
