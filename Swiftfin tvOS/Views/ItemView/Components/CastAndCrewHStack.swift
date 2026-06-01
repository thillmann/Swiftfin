//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import BlurHashKit
import JellyfinAPI
import SwiftUI

private let castAndCrewFocusedScale: CGFloat = 1.16
private let castAndCrewLabelSpacing: CGFloat = 10
private let castAndCrewPosterLength: CGFloat = 208

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
                CastAndCrewLabel(person: person)
            } posterButton: { person, action, label in
                CastAndCrewButton(
                    person: person,
                    action: action
                ) {
                    label()
                }
                .eraseToAnyView()
            }
        }
    }
}

private struct CastAndCrewButton: View {

    @EnvironmentTypeValue<BaseItemPerson>(\.posterOverlayRegistry)
    private var posterOverlayRegistry
    @Environment(\.isFocused)
    private var isEnvironmentFocused

    @State
    private var posterSize: CGSize = .zero
    @FocusState
    private var isFocused: Bool

    let person: BaseItemPerson
    let action: () -> Void
    let label: any View

    init(
        person: BaseItemPerson,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> any View
    ) {
        self.person = person
        self.action = action
        self.label = label()
    }

    private var effectiveFocus: Bool {
        isFocused || isEnvironmentFocused
    }

    private var effectiveLabelSpacing: CGFloat {
        let posterLength = min(posterSize.width, posterSize.height)
        let focusedGrowth = posterLength * (castAndCrewFocusedScale - 1)
        let focusedBottomGrowth = focusedGrowth / 2

        return castAndCrewLabelSpacing + (effectiveFocus ? focusedBottomGrowth : 0)
    }

    @ViewBuilder
    private var posterImage: some View {
        CastAndCrewPosterImage(person: person)
    }

    @ViewBuilder
    private func poster(overlay: some View) -> some View {
        ZStack {
            posterImage
                .overlay { overlay }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(.contextMenuPreview, Circle())
        .containerShape(.circle)
        .compositingGroup()
        .glassLift(
            in: Circle(),
            isFocused: effectiveFocus,
            scale: castAndCrewFocusedScale,
            shadowOpacity: 0.32,
            shadowRadius: 10,
            shadowY: 6,
            highlightOpacity: 0.9
        )
    }

    var body: some View {
        Button(action: action) {
            let overlay = posterOverlayRegistry?(person) ??
                PosterButton<BaseItemPerson>.DefaultOverlay(item: person)
                .eraseToAnyView()

            VStack(spacing: effectiveLabelSpacing) {
                poster(overlay: overlay)
                    .trackingSize($posterSize)

                label
                    .eraseToAnyView()
            }
            .animation(.easeInOut(duration: 0.15), value: effectiveFocus)
        }
        .buttonStyle(.focusNeutral)
        .focused($isFocused)
        .focusedValue(\.focusedPoster, AnyPoster(person))
        .accessibilityLabel(person.displayTitle)
        .matchedContextMenu(for: person) {
            EmptyView()
        }
    }
}

private struct CastAndCrewPosterImage: View {

    let person: BaseItemPerson

    private var imageSources: [ImageSource] {
        person.portraitImageSources(maxWidth: castAndCrewPosterLength, quality: 90)
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.complexSecondary)

            AlternateLayoutView {
                Color.clear
            } content: { size in
                ImageView(imageSources)
                    .image { image in
                        person.transform(image: image)
                            .aspectRatio(contentMode: .fill)
                            .frame(width: size.width, height: size.height)
                            .clipped()
                    }
                    .placeholder { imageSource in
                        if let blurHash = imageSource.blurHash {
                            BlurHashView(blurHash: blurHash)
                        } else {
                            SystemImageContentView(
                                systemName: person.systemImage
                            )
                        }
                    }
                    .failure {
                        SystemImageContentView(
                            systemName: person.systemImage
                        )
                    }
                    .frame(width: size.width, height: size.height)
                    .clipped()
            }
        }
        .aspectRatio(1, contentMode: .fill)
    }
}

private struct CastAndCrewLabel: View {

    @Environment(\.isFocused)
    private var isFocused

    let person: BaseItemPerson

    var body: some View {
        VStack(spacing: 2) {
            Text(person.displayTitle)
                .font(.caption.weight(.regular))
                .foregroundColor(.primary)
                .lineLimit(1, reservesSpace: true)

            Text(person.subtitle ?? "")
                .font(.caption2.weight(.medium))
                .foregroundColor(isFocused ? .white : .secondary)
                .lineLimit(1, reservesSpace: true)
        }
        .frame(width: castAndCrewPosterLength)
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
    }
}
