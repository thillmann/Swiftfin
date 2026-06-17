//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

struct PosterVGrid<Element: Poster>: View {

    private let data: [Element]

    private let layout: LibraryDisplayType
    private let columnCount: Int
    private let posterType: PosterDisplayType
    private let onNeedsNextPage: (Element) -> Void
    private let onSelect: (Element) -> Void

    private var gridSpacing: CGFloat {
        if layout == .grid {
            40.0
        } else {
            20.0
        }
    }

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: gridSpacing),
            count: columnCount
        )
    }

    init(
        data: [Element],
        layout: LibraryDisplayType = .grid,
        posterType: PosterDisplayType = .portrait,
        onNeedsNextPage: @escaping (Element) -> Void = { _ in },
        onSelect: @escaping (Element) -> Void
    ) {
        self.data = data
        self.layout = layout
        self.posterType = posterType
        self.columnCount = 1
        self.onNeedsNextPage = onNeedsNextPage
        self.onSelect = onSelect
    }

    init(
        data: [Element],
        layout: LibraryDisplayType = .grid,
        posterType: PosterDisplayType = .portrait,
        columnCount: Int,
        onNeedsNextPage: @escaping (Element) -> Void = { _ in },
        onSelect: @escaping (Element) -> Void
    ) {
        self.data = data
        self.layout = layout
        self.posterType = posterType
        self.columnCount = columnCount
        self.onNeedsNextPage = onNeedsNextPage
        self.onSelect = onSelect
    }

    private func gridCell(for item: Element) -> some View {
        PosterButton(
            item: item,
            type: posterType
        ) {
            onSelect(item)
        }
    }

    private func listCell(for item: Element) -> some View {
        Button {
            onSelect(item)
        } label: {
            HStack(spacing: 20) {
                PosterImage(
                    item: item,
                    type: .landscape
                )
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .frame(maxWidth: 160)

                VStack(spacing: 8) {
                    Text(item.displayTitle)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }

                Spacer()
            }
        }
    }

    @ViewBuilder
    private func cell(for item: Element) -> some View {
        if layout == .grid {
            gridCell(for: item)
        } else {
            listCell(for: item)
        }
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: gridSpacing) {
                ForEach(data, id: \.unwrappedIDHashOrZero) { item in
                    cell(for: item)
                        .onAppear {
                            onNeedsNextPage(item)
                        }
                }
            }
            .padding(80)
            .padding(.top, 120)
        }
    }
}
