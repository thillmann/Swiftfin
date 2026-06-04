//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

private let castAndCrewFocusedScale: CGFloat = 1.1
private let castAndCrewLabelSpacing: CGFloat = 10
private let castAndCrewRowAspectRatio: CGFloat = 0.75
private let castAndCrewPosterImageMaxWidth: CGFloat = 500
private let castAndCrewFocusAnimation = Animation.easeInOut(duration: 0.18)

extension ItemView {

    struct CastAndCrewHStack: View {

        @Router
        private var router

        let people: [BaseItemPerson]

        var body: some View {
            PosterHStack(
                title: L10n.castAndCrew.localizedCapitalized,
                type: .portrait,
                items: people.filter { person in
                    person.type?.isSupported ?? false
                }
            ) { person in
                router.route(to: .item(item: .init(person: person)))
            } label: { person in
                CastAndCrewLabel(person: person, isFocused: false)
            } posterButton: { person, action, _ in
                CastAndCrewButton(
                    person: person,
                    action: action
                )
                .eraseToAnyView()
            }
            .itemContentAspectRatio(castAndCrewRowAspectRatio)
        }
    }
}

private struct CastAndCrewButton: View {

    @EnvironmentTypeValue<BaseItemPerson>(\.posterOverlayRegistry)
    private var posterOverlayRegistry

    @FocusState
    private var isFocused: Bool

    let person: BaseItemPerson
    let action: () -> Void

    private func effectiveLabelSpacing(posterLength: CGFloat) -> CGFloat {
        let focusedBottomGrowth = posterLength * (castAndCrewFocusedScale - 1) / 2

        return castAndCrewLabelSpacing + (isFocused ? focusedBottomGrowth : 0)
    }

    @ViewBuilder
    private func poster(
        overlay: some View,
        length: CGFloat
    ) -> some View {
        PosterImage(
            item: CastAndCrewSquarePoster(person: person),
            type: .square,
            maxWidth: castAndCrewPosterImageMaxWidth
        )
        .frame(width: length, height: length)
        .overlay { overlay }
        .contentShape(.contextMenuPreview, Circle())
        .clipShape(Circle())
        .containerShape(.circle)
        .compositingGroup()
        .if(isFocused) { view in
            if #available(tvOS 26.0, *) {
                view
                    .glassEffect(.regular.interactive(), in: Circle())
            } else {
                view
            }
        }
    }

    @ViewBuilder
    private func posterButton(
        overlay: some View,
        length: CGFloat
    ) -> some View {
        Button(action: action) {
            poster(overlay: overlay, length: length)
        }
        .buttonStyle(.castAndCrewNeutral)
        .scaleEffect(isFocused ? castAndCrewFocusedScale : 1, anchor: .center)
        .animation(castAndCrewFocusAnimation, value: isFocused)
    }

    var body: some View {
        let overlay = posterOverlayRegistry?(person) ??
            PosterButton<BaseItemPerson>.DefaultOverlay(item: person)
            .eraseToAnyView()

        GeometryReader { proxy in
            VStack(spacing: effectiveLabelSpacing(posterLength: proxy.size.width)) {
                posterButton(overlay: overlay, length: proxy.size.width)
                    .focused($isFocused)
                    .focusedValue(\.focusedPoster, AnyPoster(person))
                    .accessibilityLabel(person.displayTitle)
                    .matchedContextMenu(for: person)

                CastAndCrewLabel(person: person, isFocused: isFocused)
            }
            .animation(castAndCrewFocusAnimation, value: isFocused)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
    }
}

private struct CastAndCrewNeutralButtonStyle: ButtonStyle {

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

fileprivate extension ButtonStyle where Self == CastAndCrewNeutralButtonStyle {

    static var castAndCrewNeutral: CastAndCrewNeutralButtonStyle {
        CastAndCrewNeutralButtonStyle()
    }
}

private struct CastAndCrewSquarePoster: Poster {

    let person: BaseItemPerson

    var id: String {
        person.id ?? ""
    }

    var unwrappedIDHashOrZero: Int {
        person.unwrappedIDHashOrZero
    }

    var displayTitle: String {
        person.displayTitle
    }

    var preferredPosterDisplayType: PosterDisplayType {
        .square
    }

    var subtitle: String? {
        person.subtitle
    }

    var systemImage: String {
        person.systemImage
    }

    func squareImageSources(maxWidth: CGFloat?, quality: Int?) -> [ImageSource] {
        person.portraitImageSources(maxWidth: maxWidth, quality: quality)
    }

    func transform(image: Image) -> some View {
        image
            .resizable()
            .aspectRatio(contentMode: .fill)
    }
}

private struct CastAndCrewLabel: View {

    let person: BaseItemPerson
    let isFocused: Bool

    var body: some View {
        VStack(spacing: 2) {
            Text(person.displayTitle)
                .font(.caption.weight(.regular))
                .foregroundColor(.primary)
                .lineLimit(1, reservesSpace: true)

            Text(person.subtitle ?? "")
                .font(.caption2.weight(.medium))
                .foregroundColor(.white)
                .opacity(isFocused ? 1 : 0.6)
                .lineLimit(1, reservesSpace: true)
        }
        .animation(castAndCrewFocusAnimation, value: isFocused)
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
    }
}
