//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

// TODO: scroll if description too long

struct MediaInfoSupplement: MediaPlayerSupplement {

    let displayTitle: String = L10n.info
    let item: BaseItemDto

    var id: String {
        "MediaInfo-\(item.id ?? "any")"
    }

    var videoPlayerBody: some PlatformView {
        InfoOverlay(item: item)
    }
}

extension MediaInfoSupplement {

    private struct InfoOverlay: PlatformView {

        private enum ActionFocus: Hashable {
            case fromBeginning
            case goToShow
        }

        @Environment(\.safeAreaInsets)
        private var safeAreaInsets: EdgeInsets

        @FocusState
        private var focusedAction: ActionFocus?

        @Router
        private var router

        @EnvironmentObject
        private var containerState: VideoPlayerContainerState
        @EnvironmentObject
        private var manager: MediaPlayerManager

        let item: BaseItemDto

        private var contentVerticalAlignment: VerticalAlignment {
            #if os(tvOS)
            .center
            #else
            .bottom
            #endif
        }

        private var posterDisplayType: PosterDisplayType {
            #if os(tvOS)
            .landscape
            #else
            item.preferredPosterDisplayType
            #endif
        }

        private var posterWidth: CGFloat? {
            #if os(tvOS)
            300
            #else
            nil
            #endif
        }

        private var posterImageSources: [ImageSource]? {
            #if os(tvOS)
            guard item.type == .episode else { return nil }
            return [item.imageSource(.primary, maxWidth: 300, quality: 90)]
            #else
            nil
            #endif
        }

        private var overviewFont: Font {
            #if os(tvOS)
            item.type == .episode ? .caption : .subheadline
            #else
            .subheadline
            #endif
        }

        @ViewBuilder
        private var accessoryView: some View {
            VStack(alignment: .leading) {
                DotHStack {
                    if item.type == .episode {
                        if let premiereDateLabel = item.premiereDateLabel {
                            Text(premiereDateLabel)
                        }
                        if let seasonEpisodeLocator = item.seasonEpisodeLabel {
                            Text(seasonEpisodeLocator)
                        }
                    } else if let premiereYear = item.premiereDateYear {
                        Text(premiereYear)
                    }

                    if let runtime = item.runTimeLabel {
                        Text(runtime)
                    }

                    if let officialRating = item.officialRating {
                        Text(officialRating)
                    }
                }
            }
        }

        @ViewBuilder
        private var fromBeginningButton: some View {
            Button {
                manager.proxy?.setSeconds(.zero)
                manager.setPlaybackRequestStatus(status: .playing)
                containerState.select(supplement: nil)
            } label: {
                #if os(tvOS)
                Label(L10n.fromBeginning, systemImage: "play.fill")
                #else
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .foregroundStyle(.white)

                    Label(L10n.fromBeginning, systemImage: "play.fill")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.black)
                }
                #endif
            }
            #if os(tvOS)
            .focused($focusedAction, equals: .fromBeginning)
            .buttonStyle(
                SeasonButtonStyle(
                    isFocused: focusedAction == .fromBeginning,
                    isSelected: true,
                    width: 320
                )
            )
            .focusEffectDisabled()
            #else
            .buttonStyle(.card)
            .frame(height: 40)
            #endif
        }

        #if os(tvOS)
        @ViewBuilder
        private var goToShowButton: some View {
            if item.type == .episode, let seriesID = item.seriesID {
                Button {
                    let series = BaseItemDto(
                        id: seriesID,
                        name: item.seriesName,
                        type: .series
                    )
                    router.route(to: .item(item: series))
                } label: {
                    Label(L10n.goToShow, systemImage: "info.circle")
                }
                .focused($focusedAction, equals: .goToShow)
                .buttonStyle(
                    SeasonButtonStyle(
                        isFocused: focusedAction == .goToShow,
                        isSelected: true,
                        width: 320
                    )
                )
                .focusEffectDisabled()
            }
        }
        #endif

        // TODO: may need to be a layout for correct overview frame
        //       with scrolling if too long
        var iOSView: some View {
            CompactOrRegularView(
                isCompact: containerState.isCompact
            ) {
                iOSCompactView
            } regularView: {
                regularContent
                    .edgePadding()
            }
            .padding(.leading, safeAreaInsets.leading)
            .padding(.trailing, safeAreaInsets.trailing)
        }

        @ViewBuilder
        private var iOSCompactView: some View {
            VStack(alignment: .leading) {
                Text(item.displayTitle)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let overview = item.overview {
                    Text(overview)
                        .font(.subheadline)
                        .fontWeight(.regular)
                }

                accessoryView
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !manager.item.isLiveStream {
                    fromBeginningButton
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .padding(.vertical)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .edgePadding()
        }

        @ViewBuilder
        private var regularContent: some View {
            HStack(alignment: contentVerticalAlignment, spacing: EdgeInsets.edgePadding / 2) {
                PosterImage(
                    item: item,
                    type: posterDisplayType,
                    contentMode: .fit,
                    imageSources: posterImageSources
                )
                .frame(width: posterWidth)
                .posterCornerRadius(posterDisplayType)
                .environment(\.isOverComplexContent, true)

                VStack(alignment: .leading, spacing: 12) {
                    Text(item.displayTitle)
                        .font(.callout.weight(.semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if let overview = item.overview {
                        Text(overview)
                            .font(overviewFont)
                            .fontWeight(.regular)
                            .lineLimit(4)
                    }

                    accessoryView
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if !manager.item.isLiveStream {
                    #if os(tvOS)
                    VStack(spacing: 12) {
                        fromBeginningButton

                        if item.type == .episode, item.seriesID != nil {
                            goToShowButton
                        }
                    }
                    #else
                    AlternateLayoutView {
                        Label(L10n.fromBeginning, systemImage: "play.fill")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .padding()
                            .edgePadding(.horizontal)
                            .frame(height: UIDevice.isTV ? 80 : 50)
                    } content: {
                        fromBeginningButton
                    }
                    #endif
                }
            }
        }

        #if os(tvOS)
        @ViewBuilder
        var tvOSView: some View {
            Group {
                if #available(tvOS 26.0, *) {
                    regularContent
                        .edgePadding(.horizontal)
                        .padding(.vertical, EdgeInsets.edgePadding / 2)
                        .glassEffect(
                            .clear,
                            in: RoundedRectangle(cornerRadius: 32, style: .continuous)
                        )
                } else {
                    regularContent
                        .edgePadding(.horizontal)
                        .padding(.vertical, EdgeInsets.edgePadding / 2)
                        .background {
                            RoundedRectangle(cornerRadius: 32, style: .continuous)
                                .fill(Material.thin)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                }
            }
            .padding(.horizontal, EdgeInsets.edgePadding)
            .padding(.bottom, EdgeInsets.edgePadding / 4)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .focusSection()
            .backport
            .defaultFocus(
                $focusedAction,
                .fromBeginning,
                priority: .userInitiated
            )
        }
        #else
        var tvOSView: some View {
            EmptyView()
        }
        #endif
    }
}
