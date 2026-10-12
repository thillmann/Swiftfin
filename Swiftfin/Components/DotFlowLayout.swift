//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

struct DotFlowLayout: View {

    enum RowAlignment {
        case leading
        case center
    }

    let items: [String]
    let rowAlignment: RowAlignment

    init(items: [String], rowAlignment: RowAlignment = .center) {
        self.items = items
        self.rowAlignment = rowAlignment
    }

    var body: some View {
        DotFlowLayoutContainer(rowAlignment: rowAlignment) {
            ForEach(items.indices, id: \.self) { index in
                Text(items[index])
                    .fixedSize()

                if index != items.indices.last {
                    Circle()
                        .frame(width: 2, height: 2)
                        .padding(.horizontal, 5)
                }
            }
        }
    }
}

private struct DotFlowLayoutContainer: Layout {

    let rowAlignment: DotFlowLayout.RowAlignment

    struct Cache {}

    private struct Row {
        let itemIndices: [Int]
        let width: CGFloat
        let height: CGFloat
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache()
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache = Cache()
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) -> CGSize {
        let rows = rows(for: subviews, maxWidth: proposal.width ?? .infinity)

        return CGSize(
            width: min(rows.map(\.width).max() ?? 0, proposal.width ?? .infinity),
            height: rows.map(\.height).reduce(0, +)
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) {
        let rows = rows(for: subviews, maxWidth: bounds.width)
        var y = bounds.minY

        // Separators at a row boundary are intentionally not displayed.
        for separatorIndex in stride(from: 1, to: subviews.count, by: 2) {
            subviews[separatorIndex].place(
                at: CGPoint(x: -10000, y: -10000),
                anchor: .topLeading,
                proposal: .zero
            )
        }

        for row in rows {
            var x = switch rowAlignment {
            case .leading:
                bounds.minX
            case .center:
                bounds.midX - row.width / 2
            }

            for (position, itemIndex) in row.itemIndices.enumerated() {
                if position > 0 {
                    let separatorIndex = itemIndex - 1
                    let separatorSize = subviews[separatorIndex].sizeThatFits(.unspecified)

                    subviews[separatorIndex].place(
                        at: CGPoint(x: x, y: y + (row.height - separatorSize.height) / 2),
                        anchor: .topLeading,
                        proposal: ProposedViewSize(separatorSize)
                    )

                    x += separatorSize.width
                }

                let itemSize = subviews[itemIndex].sizeThatFits(.unspecified)
                subviews[itemIndex].place(
                    at: CGPoint(x: x, y: y + (row.height - itemSize.height) / 2),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(itemSize)
                )

                x += itemSize.width
            }

            y += row.height
        }
    }

    private func rows(for subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        guard !subviews.isEmpty else { return [] }

        var rows: [Row] = []
        var itemIndices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0

        for itemIndex in stride(from: 0, to: subviews.count, by: 2) {
            let itemSize = subviews[itemIndex].sizeThatFits(.unspecified)
            let separatorSize = itemIndices.isEmpty
                ? .zero
                : subviews[itemIndex - 1].sizeThatFits(.unspecified)
            let additionalWidth = separatorSize.width + itemSize.width

            if !itemIndices.isEmpty, width + additionalWidth > maxWidth {
                rows.append(Row(itemIndices: itemIndices, width: width, height: height))
                itemIndices = []
                width = 0
                height = 0
            }

            itemIndices.append(itemIndex)
            width += itemIndices.count == 1 ? itemSize.width : additionalWidth
            height = max(height, itemSize.height)
        }

        rows.append(Row(itemIndices: itemIndices, width: width, height: height))
        return rows
    }
}
