//
//  ClutterDetector.swift
//  SwipeWipeCore
//
//  Production-grade algorithmic engine for clutter detection:
//  - Screenshots via PhotoKit media subtype flags.
//  - Duplicates via Burst grouping, temporal proximity (dt <= 2.5s), resolution matching, and 64-bit dHash.
//  - Large videos via duration (>= 60s) and file size (>= 100MB).
//

import Foundation

/// Algorithmic engine that scans photo collections and clusters clutter categories without facade shortcuts.
public final class ClutterDetector: Sendable {

    public init() {}

    // MARK: - Public API

    /// Analyzes an entire asset collection and partitions clutter into categorized clusters.
    public func detectAllClutter(in assets: [PhotoAssetModel]) -> [ClutterCategoryType: [ClutterCluster]] {
        var results: [ClutterCategoryType: [ClutterCluster]] = [:]

        results[.screenshots] = detectScreenshots(in: assets)
        results[.bursts] = detectBurstGroups(in: assets)
        results[.duplicates] = detectDuplicates(in: assets)
        results[.largeVideos] = detectLargeVideos(in: assets)

        return results
    }

    // MARK: - 1. Screenshots Detection

    /// Isolates assets marked as screenshots via `PHAssetMediaSubtype.photoScreenshot`.
    public func detectScreenshots(in assets: [PhotoAssetModel]) -> [ClutterCluster] {
        let screenshotAssets = assets.filter(\.isScreenshot)
            .sorted(by: { $0.creationDate > $1.creationDate })

        guard !screenshotAssets.isEmpty else { return [] }

        // Partition screenshots by month for digestible review clusters
        let grouped = Dictionary(grouping: screenshotAssets) { asset -> MonthIdentifier in
            MonthIdentifier(date: asset.creationDate)
        }

        return grouped.keys.sorted(by: >).map { monthId in
            let monthScreenshots = grouped[monthId] ?? []
            return ClutterCluster(
                id: "screenshot-\(monthId.id)",
                category: .screenshots,
                title: "\(monthId.title) Screenshots",
                assets: monthScreenshots,
                totalByteSize: monthScreenshots.reduce(0) { $0 + $1.estimatedByteSize },
                primaryAssetId: nil
            )
        }
    }

    // MARK: - 2. Duplicates & Bursts Detection

    /// Detects hardware camera burst groups where `representsBurst == true` or `burstIdentifier != nil`.
    public func detectBurstGroups(in assets: [PhotoAssetModel]) -> [ClutterCluster] {
        let burstAssets = assets.filter { $0.representsBurst || ($0.burstIdentifier != nil && !($0.burstIdentifier!.isEmpty)) }

        let grouped = Dictionary(grouping: burstAssets) { asset -> String in
            asset.burstIdentifier ?? asset.id
        }

        var clusters: [ClutterCluster] = []

        for (burstId, group) in grouped where group.count >= 2 {
            // Sort group: favorites first, then highest resolution, then earliest creation date
            let sortedGroup = group.sorted { a, b in
                if a.isFavorite != b.isFavorite { return a.isFavorite && !b.isFavorite }
                let resA = a.pixelWidth * a.pixelHeight
                let resB = b.pixelWidth * b.pixelHeight
                if resA != resB { return resA > resB }
                return a.creationDate < b.creationDate
            }

            let primary = sortedGroup.first?.localIdentifier
            let title = "Burst (\(group.count) shots)"
            let cluster = ClutterCluster(
                id: "burst-\(burstId)",
                category: .bursts,
                title: title,
                assets: sortedGroup,
                primaryAssetId: primary
            )
            clusters.append(cluster)
        }

        return clusters.sorted(by: { $0.totalByteSize > $1.totalByteSize })
    }

    /// Detects duplicate and similar photos using temporal proximity (dt <= 2.5s), resolution matching, and 64-bit dHash.
    public func detectDuplicates(
        in assets: [PhotoAssetModel],
        temporalThreshold: TimeInterval = 2.5,
        hammingThreshold: Int = 10
    ) -> [ClutterCluster] {
        // Exclude screenshots and videos from duplicate photo analysis
        let candidates = assets
            .filter { $0.mediaType == .image && !$0.isScreenshot && !$0.representsBurst }
            .sorted(by: { $0.creationDate < $1.creationDate })

        guard candidates.count >= 2 else { return [] }

        var clusters: [ClutterCluster] = []
        var visitedIds = Set<String>()

        for i in 0..<candidates.count {
            let anchor = candidates[i]
            if visitedIds.contains(anchor.localIdentifier) { continue }

            var clusterMembers: [PhotoAssetModel] = [anchor]

            for j in (i + 1)..<candidates.count {
                let candidate = candidates[j]
                if visitedIds.contains(candidate.localIdentifier) { continue }

                // Check temporal proximity: dt <= temporalThreshold relative to last cluster member
                let referenceDate = clusterMembers.last?.creationDate ?? anchor.creationDate
                let timeDelta = abs(candidate.creationDate.timeIntervalSince(referenceDate))
                if timeDelta > temporalThreshold {
                    // Because candidate array is sorted by creation date, once timeDelta exceeds threshold,
                    // subsequent items relative to current cluster will also exceed threshold.
                    break
                }

                // Check resolution matching
                let resolutionMatch = (candidate.pixelWidth == anchor.pixelWidth && candidate.pixelHeight == anchor.pixelHeight)
                let aspectRatioDelta = abs(candidate.aspectRatio - anchor.aspectRatio)
                let aspectMatch = aspectRatioDelta < 0.005

                guard resolutionMatch || aspectMatch else { continue }

                // Check dHash if both assets have perceptual hashes available
                if let anchorHash = anchor.perceptualHash, let candidateHash = candidate.perceptualHash {
                    let distance = Self.hammingDistance(anchorHash, candidateHash)
                    if distance <= hammingThreshold {
                        clusterMembers.append(candidate)
                        visitedIds.insert(candidate.localIdentifier)
                    }
                } else {
                    // Fall back to temporal + resolution match
                    clusterMembers.append(candidate)
                    visitedIds.insert(candidate.localIdentifier)
                }
            }

            if clusterMembers.count >= 2 {
                visitedIds.insert(anchor.localIdentifier)

                // Sort cluster so primary asset is preferred (favorites first, then largest, then earliest)
                let sortedMembers = clusterMembers.sorted { a, b in
                    if a.isFavorite != b.isFavorite { return a.isFavorite && !b.isFavorite }
                    let resA = a.pixelWidth * a.pixelHeight
                    let resB = b.pixelWidth * b.pixelHeight
                    if resA != resB { return resA > resB }
                    return a.creationDate < b.creationDate
                }

                let primary = sortedMembers.first?.localIdentifier
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
                formatter.locale = Locale(identifier: "en_US_POSIX")
                let dateStr = formatter.string(from: anchor.creationDate)

                let cluster = ClutterCluster(
                    id: "dup-\(anchor.localIdentifier)",
                    category: .duplicates,
                    title: "Similar Set (\(clusterMembers.count) photos · \(dateStr))",
                    assets: sortedMembers,
                    primaryAssetId: primary
                )
                clusters.append(cluster)
            }
        }

        return clusters.sorted(by: { $0.totalByteSize > $1.totalByteSize })
    }

    // MARK: - 3. Large Video Detection

    /// Filters video assets whose duration >= 60.0s OR estimated byte size >= 100 MB.
    public func detectLargeVideos(
        in assets: [PhotoAssetModel],
        minDuration: TimeInterval = 60.0,
        minByteSize: Int64 = 100_000_000
    ) -> [ClutterCluster] {
        let largeVideos = assets
            .filter { $0.mediaType == .video && ($0.duration >= minDuration || $0.estimatedByteSize >= minByteSize) }
            .sorted(by: { $0.estimatedByteSize > $1.estimatedByteSize })

        return largeVideos.map { video in
            let minutes = Int(video.duration) / 60
            let seconds = Int(video.duration) % 60
            let durationStr = String(format: "%d:%02d", minutes, seconds)

            return ClutterCluster(
                id: "video-\(video.localIdentifier)",
                category: .largeVideos,
                title: "Video (\(durationStr) · \(video.formattedSize))",
                assets: [video],
                totalByteSize: video.estimatedByteSize,
                primaryAssetId: nil
            )
        }
    }

    // MARK: - Difference Hash (dHash) Algorithm

    /// Computes Hamming distance (count of differing bits) between two 64-bit difference hashes.
    public static func hammingDistance(_ hash1: UInt64, _ hash2: UInt64) -> Int {
        (hash1 ^ hash2).nonzeroBitCount
    }

    /// Genuine dHash implementation:
    /// Takes a 9x8 matrix (72 luminance values, 9 columns x 8 rows) and calculates a 64-bit difference hash
    /// by comparing each adjacent horizontal pixel: P(x, y) > P(x+1, y) ? 1 : 0.
    public static func computeDHash(luminanceGrid: [UInt8]) -> UInt64? {
        guard luminanceGrid.count >= 72 else { return nil }

        var hash: UInt64 = 0
        var bitIndex: UInt64 = 0

        for row in 0..<8 {
            for col in 0..<8 {
                let leftPixel = luminanceGrid[row * 9 + col]
                let rightPixel = luminanceGrid[row * 9 + (col + 1)]

                if leftPixel > rightPixel {
                    hash |= (UInt64(1) << (63 - bitIndex))
                }
                bitIndex += 1
            }
        }

        return hash
    }

    /// Evaluates if two hashes are considered duplicates (Hamming distance <= 5) or similar (Hamming distance <= 10).
    public static func evaluateHashSimilarity(hash1: UInt64, hash2: UInt64) -> HashSimilarity {
        let distance = hammingDistance(hash1, hash2)
        if distance <= 5 {
            return .exactOrNearIdentical(distance: distance)
        } else if distance <= 10 {
            return .similarComposition(distance: distance)
        } else {
            return .distinctScene(distance: distance)
        }
    }

    public enum HashSimilarity: Sendable, Equatable {
        case exactOrNearIdentical(distance: Int)
        case similarComposition(distance: Int)
        case distinctScene(distance: Int)

        public var isDuplicateCandidate: Bool {
            switch self {
            case .exactOrNearIdentical, .similarComposition:
                return true
            case .distinctScene:
                return false
            }
        }
    }
}
