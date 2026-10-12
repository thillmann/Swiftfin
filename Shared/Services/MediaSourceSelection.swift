//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

enum MediaSourceSelectionOrigin: Equatable {
    case automatic
    case serverDefault
    case userSelected
}

enum MediaSourceSelectionIntent {
    case automatic
    case userSelected(MediaSourceInfo)
}

struct MediaSourceSelectionPolicy {

    let maximumHeight: Int
    let minimumBitrate: Int64
    let targetBitrate: Int64

    static let balancedDownload = MediaSourceSelectionPolicy(
        maximumHeight: 1080,
        minimumBitrate: 1_500_000,
        targetBitrate: 2_500_000
    )
    static let balancedPlayback = MediaSourceSelectionPolicy(
        maximumHeight: 1080,
        minimumBitrate: 1_500_000,
        targetBitrate: 2_500_000
    )
}

struct MediaSourceSelectionResult {

    let selected: MediaSourceInfo
    let fallbacks: [MediaSourceInfo]
    let origin: MediaSourceSelectionOrigin
}

/// Pure, reusable media-source selection. Callers decide which sources are
/// eligible, then provide a policy appropriate to downloading or playback.
enum MediaSourceSelection {

    /// Best trustworthy byte estimate available without resolving the source.
    /// Some plugins populate `Size` with a tiny resolver payload length, so
    /// implausible structured values fall back to the human-readable label.
    static func estimatedSize(for source: MediaSourceInfo) -> Int64? {
        structuredSize(for: source) ?? parsedSize(from: searchText(for: source))
    }

    static func resolve(
        intent: MediaSourceSelectionIntent,
        candidates: [MediaSourceInfo],
        policy: MediaSourceSelectionPolicy
    ) -> MediaSourceSelectionResult? {
        switch intent {
        case let .userSelected(requested):
            let selected = matchingSource(requested, in: candidates) ?? requested
            return MediaSourceSelectionResult(
                selected: selected,
                fallbacks: [],
                origin: .userSelected
            )

        case .automatic:
            guard candidates.isNotEmpty else { return nil }
            let ranked = rankedAutomaticCandidates(
                candidates: candidates,
                policy: policy
            )
            guard let selected = ranked.first else { return nil }

            let hasRankingEvidence = ranked.contains {
                $0.audioAvailability != .unknown
                    || $0.height != nil
                    || $0.size != nil
                    || $0.bitrate != nil
            }
            return MediaSourceSelectionResult(
                selected: selected.source,
                fallbacks: ranked.dropFirst().map(\.source),
                origin: hasRankingEvidence ? .automatic : .serverDefault
            )
        }
    }

    private enum AudioAvailability: Int {
        case embedded = 0
        case unknown = 1
        case externalOnly = 2
        case absent = 3

        /// Unknown means the provider did not supply stream metadata, not that
        /// the source has no audio. Treat it like embedded audio for ranking;
        /// only explicitly external-only or absent audio should be penalized.
        var rankingGroup: Int {
            switch self {
            case .embedded, .unknown: 0
            case .externalOnly: 1
            case .absent: 2
            }
        }
    }

    private enum SourceAvailability {
        case immediate
        case unknown
        case delayed

        /// Missing provider-specific availability metadata is neutral. Only
        /// sources explicitly marked as delayed/uncached receive a penalty.
        var rankingGroup: Int {
            switch self {
            case .immediate, .unknown: 0
            case .delayed: 1
            }
        }
    }

    private struct Candidate {

        let source: MediaSourceInfo
        let originalIndex: Int
        let sourceAvailability: SourceAvailability
        let audioAvailability: AudioAvailability
        let height: Int?
        let size: Int64?
        let bitrate: Int64?

        init(source: MediaSourceInfo, originalIndex: Int) {
            self.source = source
            self.originalIndex = originalIndex
            self.sourceAvailability = MediaSourceSelection.sourceAvailability(for: source)
            self.audioAvailability = MediaSourceSelection.audioAvailability(for: source)
            self.height = MediaSourceSelection.height(for: source)
            self.size = MediaSourceSelection.estimatedSize(for: source)
            self.bitrate = MediaSourceSelection.bitrate(for: source)
        }
    }

    private static func rankedAutomaticCandidates(
        candidates: [MediaSourceInfo],
        policy: MediaSourceSelectionPolicy
    ) -> [Candidate] {
        let described = candidates.enumerated()
            .map { Candidate(source: $0.element, originalIndex: $0.offset) }
        let hasAudioCapableCandidate = described.contains {
            [.embedded, .unknown].contains($0.audioAvailability)
        }
        let audioViable = hasAudioCapableCandidate
            ? described.filter { [.embedded, .unknown].contains($0.audioAvailability) }
            : described
        let viable = audioViable.filter { candidate in
            guard let bitrate = candidate.bitrate else { return true }
            return bitrate >= policy.minimumBitrate
        }
        return viable.sorted { precedes($0, $1, policy: policy) }
    }

    private static func matchingSource(
        _ requested: MediaSourceInfo,
        in candidates: [MediaSourceInfo]
    ) -> MediaSourceInfo? {
        if let eTag = requested.eTag?.nilIfBlank {
            let matches = candidates.filter { $0.eTag?.nilIfBlank == eTag }
            if matches.count == 1 { return matches[0] }
            if let exact = matches.first(where: { $0 == requested }) { return exact }
        }

        if let id = requested.id?.nilIfBlank {
            let matches = candidates.filter { $0.id?.nilIfBlank == id }
            if matches.count == 1 { return matches[0] }
            if let exact = matches.first(where: { $0 == requested }) { return exact }
        }

        return candidates.first(where: { $0 == requested })
    }

    private static func precedes(
        _ lhs: Candidate,
        _ rhs: Candidate,
        policy: MediaSourceSelectionPolicy
    ) -> Bool {
        if lhs.sourceAvailability.rankingGroup != rhs.sourceAvailability.rankingGroup {
            return lhs.sourceAvailability.rankingGroup < rhs.sourceAvailability.rankingGroup
        }

        if lhs.audioAvailability.rankingGroup != rhs.audioAvailability.rankingGroup {
            return lhs.audioAvailability.rankingGroup < rhs.audioAvailability.rankingGroup
        }

        let lhsResolutionGroup = resolutionGroup(height: lhs.height, maximumHeight: policy.maximumHeight)
        let rhsResolutionGroup = resolutionGroup(height: rhs.height, maximumHeight: policy.maximumHeight)
        if lhsResolutionGroup != rhsResolutionGroup {
            return lhsResolutionGroup < rhsResolutionGroup
        }

        let lhsBitrateGroup = bitrateGroup(lhs.bitrate, target: policy.targetBitrate)
        let rhsBitrateGroup = bitrateGroup(rhs.bitrate, target: policy.targetBitrate)
        if lhsBitrateGroup != rhsBitrateGroup {
            return lhsBitrateGroup < rhsBitrateGroup
        }

        // Once a source is known to be at or below the target, retain the
        // provider's relevance order rather than chasing the absolute minimum.
        if lhsBitrateGroup == 0 {
            return lhs.originalIndex < rhs.originalIndex
        }

        // If every option exceeds the target, use the closest known bitrate
        // before considering resolution or estimated file size.
        if lhsBitrateGroup == 1,
           let comparison = compareOptionalAscending(lhs.bitrate, rhs.bitrate)
        {
            return comparison
        }

        if let lhsHeight = lhs.height, let rhsHeight = rhs.height, lhsHeight != rhsHeight {
            return lhsResolutionGroup == 0 ? lhsHeight > rhsHeight : lhsHeight < rhsHeight
        }

        if let comparison = compareOptionalAscending(lhs.size, rhs.size) {
            return comparison
        }

        return lhs.originalIndex < rhs.originalIndex
    }

    /// Known resolutions at or below the target are preferred, followed by
    /// unknown resolutions, then known resolutions above the target.
    private static func resolutionGroup(height: Int?, maximumHeight: Int) -> Int {
        guard let height else { return 1 }
        return height <= maximumHeight ? 0 : 2
    }

    /// Bitrates at or below the target are all considered acceptable. Known
    /// values above the target remain better fallbacks than unknown values.
    private static func bitrateGroup(_ bitrate: Int64?, target: Int64) -> Int {
        guard let bitrate else { return 2 }
        return bitrate <= target ? 0 : 1
    }

    private static func compareOptionalAscending<T: Comparable>(_ lhs: T?, _ rhs: T?) -> Bool? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?) where lhs != rhs:
            lhs < rhs
        case (_?, nil):
            true
        case (nil, _?):
            false
        default:
            nil
        }
    }

    private static func audioAvailability(for source: MediaSourceInfo) -> AudioAvailability {
        guard let streams = source.mediaStreams, streams.isNotEmpty else { return .unknown }
        let audioStreams = streams.filter { $0.type == .audio }
        if audioStreams.contains(where: { $0.isExternal != true }) { return .embedded }
        if audioStreams.isNotEmpty { return .externalOnly }
        return .absent
    }

    private static func sourceAvailability(for source: MediaSourceInfo) -> SourceAvailability {
        let text = searchText(for: source)
        if text.contains("⏳")
            || regularExpression(pattern: #"(?i)\b(uncached|pending|delayed)\b"#)
            .firstMatch(in: text, range: text.fullNSRange) != nil
        {
            return .delayed
        }
        if text.contains("⚡")
            || regularExpression(pattern: #"(?i)\b(cached|instant)\b"#)
            .firstMatch(in: text, range: text.fullNSRange) != nil
        {
            return .immediate
        }
        return .unknown
    }

    private static func bitrate(for source: MediaSourceInfo) -> Int64? {
        if let bitrate = source.bitrate, bitrate > 0 {
            return Int64(bitrate)
        }

        let streamBitrates: [Int64] = (source.mediaStreams ?? []).compactMap { stream in
            guard let bitrate = stream.bitRate, bitrate > 0 else { return nil }
            return Int64(bitrate)
        }
        if let bitrate = streamBitrates.max() {
            return bitrate
        }

        return parsedBitrate(from: searchText(for: source))
    }

    private static func parsedBitrate(from text: String) -> Int64? {
        guard let match = regularExpression(
            pattern: #"(?i)([0-9]+(?:[.,][0-9]+)?)\s*(gbps|mbps|kbps)\b"#
        ).firstMatch(in: text, range: text.fullNSRange),
            let valueText = capture(1, from: match, in: text),
            let unit = capture(2, from: match, in: text)?.lowercased(),
            let value = Double(valueText.replacingOccurrences(of: ",", with: "."))
        else { return nil }

        let multiplier: Double = switch unit {
        case "gbps": 1_000_000_000
        case "mbps": 1_000_000
        case "kbps": 1000
        default: 0
        }
        guard multiplier > 0, value > 0, value <= Double(Int64.max) / multiplier else { return nil }
        return Int64(value * multiplier)
    }

    private static func height(for source: MediaSourceInfo) -> Int? {
        if let structuredHeight = source.mediaStreams?
            .filter({ $0.type == .video })
            .compactMap(\.height)
            .filter({ $0 > 0 })
            .max()
        {
            return structuredHeight
        }

        let text = searchText(for: source)
        if let match = regularExpression(
            pattern: #"(?i)(?<![0-9])(2160|1440|1080|720|576|480)\s*p\b"#
        ).firstMatch(in: text, range: text.fullNSRange),
            let parsedHeight = capture(1, from: match, in: text).flatMap(Int.init)
        {
            return parsedHeight
        }

        if regularExpression(pattern: #"(?i)\b(4k|uhd)\b"#)
            .firstMatch(in: text, range: text.fullNSRange) != nil
        {
            return 2160
        }

        if let match = regularExpression(pattern: #"(?i)(?<![0-9])([0-9]{3,4})\s*[x×]\s*([0-9]{3,4})(?![0-9])"#)
            .firstMatch(in: text, range: text.fullNSRange),
            let parsedHeight = capture(2, from: match, in: text).flatMap(Int.init)
        {
            return parsedHeight
        }

        return nil
    }

    private static func parsedSize(from text: String) -> Int64? {
        guard let match = regularExpression(
            pattern: #"(?i)([0-9]+(?:[.,][0-9]+)?)\s*(tib|tb|gib|gb|mib|mb)\b"#
        ).firstMatch(in: text, range: text.fullNSRange),
            let valueText = capture(1, from: match, in: text),
            let unit = capture(2, from: match, in: text)?.lowercased(),
            let value = Double(valueText.replacingOccurrences(of: ",", with: "."))
        else { return nil }

        let multiplier: Double = switch unit {
        case "tib": 1_099_511_627_776
        case "tb": 1_000_000_000_000
        case "gib": 1_073_741_824
        case "gb": 1_000_000_000
        case "mib": 1_048_576
        case "mb": 1_000_000
        default: 0
        }
        guard multiplier > 0, value >= 0, value <= Double(Int64.max) / multiplier else { return nil }
        return Int64(value * multiplier)
    }

    private static func structuredSize(for source: MediaSourceInfo) -> Int64? {
        guard let size = source.size.map(Int64.init), size >= 1_000_000 else { return nil }
        return size
    }

    private static func searchText(for source: MediaSourceInfo) -> String {
        [source.name, source.path]
            .compacted()
            .joined(separator: " ")
    }

    private static func regularExpression(pattern: String) -> NSRegularExpression {
        // Patterns are compile-time constants owned by this utility.
        try! NSRegularExpression(pattern: pattern)
    }

    private static func capture(
        _ index: Int,
        from match: NSTextCheckingResult,
        in value: String
    ) -> String? {
        guard index < match.numberOfRanges,
              let range = Range(match.range(at: index), in: value)
        else { return nil }
        return String(value[range])
    }
}

private extension String {

    var fullNSRange: NSRange {
        NSRange(startIndex ..< endIndex, in: self)
    }
}
