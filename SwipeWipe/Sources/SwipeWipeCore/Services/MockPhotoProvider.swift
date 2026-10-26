//
//  MockPhotoProvider.swift
//  SwipeWipeCore
//
//  Production-grade mock photo provider with synthetic asset generation,
//  state simulation (denial, limited, cancellation code 3072, system failure),
//  and comprehensive telemetry spy probes.
//

import Foundation
import CoreGraphics

/// Configurable simulation mode for mock deletion operations.
public enum MockDeletionMode: Sendable, Equatable {
    case automaticSuccess
    case simulateUserCancelled
    case simulatePermissionDenied
    case simulateSystemError(code: Int, description: String)
}

/// Backward compatibility alias
public typealias MockDeletionOutcome = MockDeletionMode

/// In-memory mock conforming to `PhotoLibraryProviding` for headless verification and XCTest suites.
public final class MockPhotoProvider: PhotoLibraryProviding, @unchecked Sendable {

    private let lock = NSLock()

    // MARK: - Configurable State Stubs

    public var stubbedAuthorizationStatus: PhotoAuthorizationStatus
    public var stubbedBuckets: [MonthlyBucket] = []
    public var stubbedAssets: [String: [PhotoAssetModel]] = [:] // bucketId.id -> assets
    public var stubbedClutter: [ClutterCategoryType: [ClutterCluster]] = [:]
    private var _deletionMode: MockDeletionMode = .automaticSuccess

    public var deletionMode: MockDeletionMode {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _deletionMode
        }
        set {
            lock.lock()
            _deletionMode = newValue
            lock.unlock()
        }
    }

    public var deletionOutcome: MockDeletionMode {
        get { deletionMode }
        set { deletionMode = newValue }
    }
    public var simulatedLatencyNanoseconds: UInt64 = 0

    // MARK: - Telemetry & Spy Tracking

    public private(set) var totalDeletionCalls: Int = 0
    public private(set) var recordedDeletionBatches: [[String]] = []
    public private(set) var deletedAssetIdentifiers: [String] = []
    public private(set) var fetchBucketsCallCount: Int = 0
    public private(set) var fetchAssetsCallCount: Int = 0
    public private(set) var fetchClutterCallCount: Int = 0
    public private(set) var openSettingsCallCount: Int = 0
    public private(set) var presentPickerCallCount: Int = 0
    private var registeredObservers: [WeakPhotoLibraryObserver] = []

    public init(status: PhotoAuthorizationStatus = .authorized) {
        self.stubbedAuthorizationStatus = status
    }

    // MARK: - PhotoLibraryProviding Conformance

    public var authorizationStatus: PhotoAuthorizationStatus {
        lock.lock()
        defer { lock.unlock() }
        return stubbedAuthorizationStatus
    }

    public func requestAuthorizationStatus() async -> PhotoAuthorizationStatus {
        await applySimulatedLatency()
        lock.lock()
        defer { lock.unlock() }
        return stubbedAuthorizationStatus
    }

    public func requestAuthorization() async -> PhotoAuthorizationStatus {
        await requestAuthorizationStatus()
    }

    public func openSettings() async {
        lock.lock()
        openSettingsCallCount += 1
        lock.unlock()
    }

    public func presentLimitedLibraryPicker() async {
        lock.lock()
        presentPickerCallCount += 1
        lock.unlock()
    }

    public func fetchMonthlyBuckets() async throws -> [MonthlyBucket] {
        await applySimulatedLatency()
        lock.lock()
        defer { lock.unlock() }

        fetchBucketsCallCount += 1
        guard stubbedAuthorizationStatus.canReadPhotos else {
            return []
        }

        return stubbedBuckets
    }

    public func fetchAssets(for bucketId: MonthIdentifier) async throws -> [PhotoAssetModel] {
        await applySimulatedLatency()
        lock.lock()
        defer { lock.unlock() }

        fetchAssetsCallCount += 1
        guard stubbedAuthorizationStatus.canReadPhotos else {
            return []
        }

        if let explicit = stubbedAssets[bucketId.id] {
            return explicit
        }

        let keyAlt = "\(bucketId.year)-\(bucketId.month)"
        if let explicitAlt = stubbedAssets[keyAlt] {
            return explicitAlt
        }

        let keyTitle = bucketId.title
        if let explicitTitle = stubbedAssets[keyTitle] {
            return explicitTitle
        }

        // Fallback to searching stubbedBuckets
        if let matchingBucket = stubbedBuckets.first(where: { $0.identifier == bucketId }) {
            return matchingBucket.assets
        }

        return []
    }

    public func fetchClutterClusters(_ category: ClutterCategoryType) async throws -> [ClutterCluster] {
        await applySimulatedLatency()
        lock.lock()
        defer { lock.unlock() }

        fetchClutterCallCount += 1
        guard stubbedAuthorizationStatus.canReadPhotos else {
            return []
        }

        return stubbedClutter[category] ?? []
    }

    public func fetchClutterCategory(_ category: ClutterCategoryType) async throws -> [PhotoAssetModel] {
        let clusters = try await fetchClutterClusters(category)
        return clusters.flatMap(\.assets)
    }

    @discardableResult
    public func deleteAssets(withIdentifiers ids: [String]) async throws -> Bool {
        let result = try await deleteAssetsBatch(withIdentifiers: ids)
        return result.success
    }

    public func deleteAssets(withIdentifiers ids: [String]) async throws -> BatchDeletionResult {
        try await deleteAssetsBatch(withIdentifiers: ids)
    }

    public func deleteAssetsBatch(withIdentifiers ids: [String]) async throws -> BatchDeletionResult {
        await applySimulatedLatency()
        lock.lock()
        defer { lock.unlock() }

        totalDeletionCalls += 1
        recordedDeletionBatches.append(ids)

        guard !ids.isEmpty else {
            return BatchDeletionResult(success: true, deletedCount: 0, reclaimedBytes: 0)
        }

        switch _deletionMode {
        case .automaticSuccess:
            deletedAssetIdentifiers.append(contentsOf: ids)

            // Remove deleted assets from internal storage
            for (key, assets) in stubbedAssets {
                stubbedAssets[key] = assets.filter { !ids.contains($0.localIdentifier) }
            }

            stubbedBuckets = stubbedBuckets.map { bucket in
                let remaining = bucket.assets.filter { !ids.contains($0.localIdentifier) }
                return MonthlyBucket(
                    identifier: bucket.identifier,
                    assetCount: remaining.count,
                    totalByteSizeEstimate: remaining.reduce(0) { $0 + $1.estimatedByteSize },
                    coverAssetIdentifier: remaining.first?.localIdentifier,
                    assets: remaining
                )
            }.filter { $0.assetCount > 0 }

            return BatchDeletionResult(
                success: true,
                deletedCount: ids.count,
                reclaimedBytes: 0,
                failedIdentifiers: []
            )

        case .simulateUserCancelled:
            throw NSError(
                domain: "PHPhotosErrorDomain",
                code: 3072,
                userInfo: [NSLocalizedDescriptionKey: "User cancelled system deletion prompt"]
            )

        case .simulatePermissionDenied:
            throw NSError(
                domain: "PHPhotosErrorDomain",
                code: 3303,
                userInfo: [NSLocalizedDescriptionKey: "Photo library write permission denied"]
            )

        case .simulateSystemError(let code, let description):
            throw NSError(
                domain: "SwipeWipeMockDomain",
                code: code,
                userInfo: [NSLocalizedDescriptionKey: description]
            )
        }
    }

    public func loadThumbnail(for assetId: String, targetSize: CGSize) async throws -> CGImage? {
        await applySimulatedLatency()
        // Headless environment returns nil or mock CGImage
        return nil
    }

    public func addObserver(_ observer: PhotoLibraryObserving) {
        lock.lock()
        defer { lock.unlock() }
        registeredObservers.removeAll { $0.value == nil || $0.value === observer }
        registeredObservers.append(WeakPhotoLibraryObserver(observer))
    }

    public func removeObserver(_ observer: PhotoLibraryObserving) {
        lock.lock()
        defer { lock.unlock() }
        registeredObservers.removeAll { $0.value == nil || $0.value === observer }
    }

    public func simulateExternalChange() {
        lock.lock()
        registeredObservers.removeAll { $0.value == nil }
        let currentObservers = registeredObservers.compactMap(\.value)
        lock.unlock()

        for observer in currentObservers {
            observer.photoLibraryDidChange()
        }
    }

    private func applySimulatedLatency() async {
        if simulatedLatencyNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: simulatedLatencyNanoseconds)
        }
    }

    // MARK: - Synthetic Asset Generator

    /// Generates realistic synthetic assets across multiple months, with genuine screenshots,
    /// burst groups, temporal duplicate clusters, and large videos.
    public static func generateSyntheticAssets(
        count: Int = 100,
        monthsBack: Int = 6,
        baseDate: Date = Date()
    ) -> [PhotoAssetModel] {
        var assets: [PhotoAssetModel] = []
        let calendar = Calendar(identifier: .gregorian)

        // 1. Generate Screenshots (approx 15% of count)
        let screenshotCount = max(2, Int(Double(count) * 0.15))
        for i in 1...screenshotCount {
            let daysAgo = i * 2
            let date = calendar.date(byAdding: .day, value: -daysAgo, to: baseDate) ?? baseDate
            assets.append(PhotoAssetModel(
                id: "mock-screenshot-\(i)",
                localIdentifier: "ph-screenshot-\(i)",
                creationDate: date,
                mediaType: .image,
                mediaSubtypes: [.photoScreenshot],
                pixelWidth: 1179,
                pixelHeight: 2556,
                estimatedByteSize: 1_850_000,
                isFavorite: false
            ))
        }

        // 2. Generate Large Videos (approx 5% of count)
        let videoCount = max(2, Int(Double(count) * 0.05))
        for i in 1...videoCount {
            let daysAgo = i * 5
            let date = calendar.date(byAdding: .day, value: -daysAgo, to: baseDate) ?? baseDate
            let duration: TimeInterval = 65.0 + Double(i * 45)
            let byteSize: Int64 = 110_000_000 + Int64(i * 80_000_000)

            assets.append(PhotoAssetModel(
                id: "mock-video-\(i)",
                localIdentifier: "ph-video-\(i)",
                creationDate: date,
                mediaType: .video,
                mediaSubtypes: [],
                pixelWidth: 3840,
                pixelHeight: 2160,
                duration: duration,
                estimatedByteSize: byteSize,
                isFavorite: false
            ))
        }

        // 3. Generate Burst Group (e.g. 5 shots taken in a burst)
        let burstDate = calendar.date(byAdding: .day, value: -7, to: baseDate) ?? baseDate
        let burstId = "burst-group-alpha"
        for i in 1...5 {
            let shotDate = burstDate.addingTimeInterval(Double(i) * 0.1)
            assets.append(PhotoAssetModel(
                id: "mock-burst-\(i)",
                localIdentifier: "ph-burst-\(i)",
                creationDate: shotDate,
                mediaType: .image,
                mediaSubtypes: [],
                pixelWidth: 4032,
                pixelHeight: 3024,
                estimatedByteSize: 3_200_000,
                isFavorite: (i == 1), // First shot is favorited
                burstIdentifier: burstId,
                representsBurst: true
            ))
        }

        // 4. Generate Temporal Duplicate Set (3 shots taken with dt = 0.8s)
        let dupBaseDate = calendar.date(byAdding: .day, value: -12, to: baseDate) ?? baseDate
        let sharedDHash: UInt64 = 0xAA55AA55AA55AA55
        for i in 1...3 {
            let shotDate = dupBaseDate.addingTimeInterval(Double(i) * 0.8)
            assets.append(PhotoAssetModel(
                id: "mock-dup-\(i)",
                localIdentifier: "ph-dup-\(i)",
                creationDate: shotDate,
                mediaType: .image,
                mediaSubtypes: [],
                pixelWidth: 4032,
                pixelHeight: 3024,
                estimatedByteSize: 3_100_000,
                isFavorite: false,
                perceptualHash: sharedDHash
            ))
        }

        // 5. Fill remaining quota with regular photos spread across months
        let remaining = max(0, count - assets.count)
        for i in 1...remaining {
            let monthOffset = (i % monthsBack)
            let dayOffset = (i * 3) % 28
            var comp = calendar.dateComponents([.year, .month, .day], from: baseDate)
            comp.month = (comp.month ?? 1) - monthOffset
            comp.day = max(1, dayOffset)
            let date = calendar.date(from: comp) ?? baseDate.addingTimeInterval(Double(-i * 86400))

            assets.append(PhotoAssetModel(
                id: "mock-photo-\(i)",
                localIdentifier: "ph-photo-\(i)",
                creationDate: date,
                mediaType: .image,
                mediaSubtypes: [],
                pixelWidth: 4032,
                pixelHeight: 3024,
                estimatedByteSize: 3_400_000,
                isFavorite: (i % 7 == 0)
            ))
        }

        return assets.sorted(by: { $0.creationDate > $1.creationDate })
    }

    /// Factory method creating a fully pre-populated mock provider with realistic monthly buckets and clutter.
    public static func createPrepopulated(
        assetCount: Int = 120,
        status: PhotoAuthorizationStatus = .authorized
    ) -> MockPhotoProvider {
        let provider = MockPhotoProvider(status: status)
        let assets = generateSyntheticAssets(count: assetCount)

        // Partition into monthly buckets
        let grouped = Dictionary(grouping: assets) { MonthIdentifier(date: $0.creationDate) }
        var buckets: [MonthlyBucket] = []

        for monthId in grouped.keys.sorted(by: >) {
            let monthAssets = grouped[monthId] ?? []
            let bucket = MonthlyBucket(
                identifier: monthId,
                assetCount: monthAssets.count,
                totalByteSizeEstimate: monthAssets.reduce(0) { $0 + $1.estimatedByteSize },
                coverAssetIdentifier: monthAssets.first?.localIdentifier,
                assets: monthAssets
            )
            buckets.append(bucket)
            provider.stubbedAssets[monthId.id] = monthAssets
        }

        provider.stubbedBuckets = buckets

        // Run ClutterDetector to compute clutter clusters
        let detector = ClutterDetector()
        provider.stubbedClutter = detector.detectAllClutter(in: assets)

        return provider
    }
}
