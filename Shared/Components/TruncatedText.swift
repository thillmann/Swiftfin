//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

// TODO: only allow `view` selection when truncated?
// TODO: fix when also using `lineLimit(reserveSpace > 1)`
// TODO: some false positives for showing see more?
// TODO: allow removing empty lines

struct TruncatedText: View {

    enum SeeMoreType {
        case button
        case pill
        case view
    }

    @Default(.accentColor)
    private var accentColor

    @State
    private var isTruncated: Bool = false
    @State
    private var fullheight: CGFloat = 0

    private var isTruncatedBinding: Binding<Bool>
    private var onSeeMore: () -> Void
    private var seeMoreType: SeeMoreType
    private let text: String
    private var prefix: String?

    private var displayedText: Text {
        guard let prefix else { return Text(text) }

        return Text(prefix).fontWeight(.bold) + Text(text)
    }

    private var seeMoreText: String {
        switch seeMoreType {
        case .pill:
            // swiftlint:disable:next hard_coded_display_string
            "MORE"
        case .button, .view:
            .ellipsis + L10n.seeMore
        }
    }

    private var maskedSeeMoreText: String {
        if seeMoreType == .pill {
            return "  " + seeMoreText
        }

        return .tab + seeMoreText
    }

    @ViewBuilder
    private var textView: some View {
        ZStack(alignment: .bottomTrailing) {
            displayedText
                .inverseMask(alignment: .bottomTrailing) {
                    VStack {
                        Spacer()

                        HStack {
                            Spacer()

                            Text(maskedSeeMoreText)
                                .background {
                                    LinearGradient(
                                        stops: [
                                            .init(color: .clear, location: 0),
                                            .init(color: .black, location: 0.1),
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                }
                        }
                    }
                    .isVisible(isTruncated)
                }

            if isTruncated {
                #if os(tvOS)
                Text(seeMoreText)
                    .foregroundColor(accentColor)
                #else
                switch seeMoreType {
                case .button:
                    Button {
                        onSeeMore()
                    } label: {
                        Text(seeMoreText)
                            .foregroundColor(accentColor)
                    }

                case .pill:
                    Button {
                        onSeeMore()
                    } label: {
                        Text(seeMoreText)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.white.opacity(0.2), in: Capsule())
                    }
                    .buttonStyle(.plain)

                case .view:
                    Text(seeMoreText)
                        .foregroundColor(accentColor)
                }
                #endif
            }
        }
        .background {
            ZStack {
                if !isTruncated {
                    if fullheight != 0 {
                        displayedText
                            .onSizeChanged { newSize, _ in
                                if fullheight > newSize.height {
                                    isTruncated = true
                                }
                            }
                    }

                    displayedText
                        .lineLimit(10)
                        .fixedSize(horizontal: false, vertical: true)
                        .onSizeChanged { newSize, _ in
                            fullheight = newSize.height
                        }
                }
            }
            .hidden()
        }
        .onChange(of: isTruncated) { newValue in
            isTruncatedBinding.wrappedValue = newValue
        }
    }

    var body: some View {
        if seeMoreType == .view {
            Button {
                onSeeMore()
            } label: {
                textView
            }
            .buttonStyle(.plain)
        } else {
            textView
        }
    }
}

extension TruncatedText {

    init(_ text: String) {
        self.init(
            isTruncatedBinding: .constant(false),
            onSeeMore: {},
            seeMoreType: .button,
            text: text
        )
    }

    init(prefix: String?, _ text: String) {
        self.init(text)
        self.prefix = prefix
    }

    func isTruncated(_ isTruncated: Binding<Bool>) -> Self {
        copy(modifying: \.isTruncatedBinding, with: isTruncated)
    }

    func onSeeMore(_ action: @escaping () -> Void) -> Self {
        copy(modifying: \.onSeeMore, with: action)
    }

    func seeMoreType(_ type: SeeMoreType) -> Self {
        copy(modifying: \.seeMoreType, with: type)
    }
}
