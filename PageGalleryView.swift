//
//  PageGalleryView.swift
//  Bluprint Takeoff
//
//  Created by Work on 10/16/25.
//

//
//  PageGalleryView.swift
//  Bluprint Takeoff
//
//  Created as a dedicated, modular SwiftUI view to display PDF page thumbnails.
//  - Shows all pages in a grid.
//  - Tapping a page selects it and opens it for takeoff.
//  - Future-ready: can show takeoff indicators or per-page metadata.
//

import SwiftUI
import PDFKit

struct PageGalleryView: View {
    let document: PDFDocument
    @Binding var selectedPageIndex: Int?

    private let columns = [GridItem(.adaptive(minimum: 300), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(0..<document.pageCount, id: \.self) { i in
                    if let page = document.page(at: i) {
                        let thumbnail = page.thumbnail(of: CGSize(width: 600, height: 800), for: .mediaBox)

                        VStack(spacing: 6) {
                            Image(nsImage: thumbnail)
                                .resizable()
                                .scaledToFit()
                                .cornerRadius(8)
                                .shadow(radius: 2)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(selectedPageIndex == i ? Color.accentColor : Color.clear, lineWidth: 3)
                                )
                                .onTapGesture {
                                    withAnimation(.easeInOut) {
                                        selectedPageIndex = i
                                    }
                                }

                            Text("Page \(i + 1)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(6)
                    }
                }
            }
            .padding(16)
        }
    }
}
