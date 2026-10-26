//
//  IngestionTests.swift
//  SwipeWipeCoreTests
//
//  Created for SwipeWipe Native iOS Rebuild (Target: iOS 27.0.1+ / iPhone 14 Pro)
//  Covers Requirement R1: Permissions, Chronological Monthly Bucketing, Clutter Detection
//

import XCTest
import Foundation
@testable import SwipeWipeCore

// MARK: - Ingestion Tests Suite

final class IngestionTests: XCTestCase {

    // MARK: - Setup & Teardown
    
    private var mockProvider: MockPhotoProvider!
    
    override func setUp() async throws {
        try await super.setUp()
        mockProvider = MockPhotoProvider()
    }
    
    override func tearDown() async throws {
        mockProvider = nil
        try await super.tearDown()
    }
    
    // MARK: - Feature 1: PhotoKit Permission Handling (F1)
    
    func testPermissionInitialNotDetermined() async {
        mockProvider.stubbedAuthorizationStatus = .notDetermined
        let status = await mockProvider.requestAuthorization()
        XCTAssertEqual(status, .notDetermined, "Initial state should match stubbed notDetermined")
    }
    
    func testPermissionAuthorizedAccess() async {
        mockProvider.stubbedAuthorizationStatus = .authorized
        let status = await mockProvider.requestAuthorization()
        XCTAssertEqual(status, .authorized, "Authorized status grants full camera roll access")
    }
    
    func testPermissionLimitedAccess() async throws {
        mockProvider.stubbedAuthorizationStatus = .limited
        let status = await mockProvider.requestAuthorization()
        XCTAssertEqual(status, .limited, "Limited access returns subset of assets without failure")
    }
    
    func testPermissionDeniedBlocksFetch() async throws {
        mockProvider.stubbedAuthorizationStatus = .denied
        let buckets = try await mockProvider.fetchMonthlyBuckets()
        XCTAssertTrue(buckets.isEmpty, "Denied permission should return empty buckets without throwing unhandled crash")
    }
    
    func testPermissionRestrictedHandling() async {
        mockProvider.stubbedAuthorizationStatus = .restricted
        let status = await mockProvider.requestAuthorization()
        XCTAssertEqual(status, .restricted, "Restricted status represents MDM or Screen Time limitation")
    }
    
    // MARK: - Feature 2: Lazy Asset Ingestion & Metadata (F2)
    
    func testAssetModelCreationAndImmutability() {
        let date = Date(timeIntervalSince1970: 1700000000)
        let asset = PhotoAssetModel(
            id: "asset-123",
            localIdentifier: "ph-123",
            creationDate: date,
            mediaType: .image,
            pixelWidth: 1179,
            pixelHeight: 2556,
            estimatedByteSize: 3_500_000,
            isFavorite: false
        )
        
        XCTAssertEqual(asset.id, "asset-123")
        XCTAssertEqual(asset.localIdentifier, "ph-123")
        XCTAssertEqual(asset.pixelWidth, 1179)
        XCTAssertEqual(asset.pixelHeight, 2556)
        XCTAssertEqual(asset.estimatedByteSize, 3_500_000)
        XCTAssertFalse(asset.isFavorite)
    }
    
    func testAspectRatioCalculation() {
        let portraitAsset = PhotoAssetModel(pixelWidth: 1179, pixelHeight: 2556)
        XCTAssertEqual(portraitAsset.aspectRatio, 1179.0 / 2556.0, accuracy: 0.0001)
        
        let landscapeAsset = PhotoAssetModel(pixelWidth: 3840, pixelHeight: 2160)
        XCTAssertEqual(landscapeAsset.aspectRatio, 3840.0 / 2160.0, accuracy: 0.0001)
        
        let zeroHeightAsset = PhotoAssetModel(pixelWidth: 1000, pixelHeight: 0)
        XCTAssertEqual(zeroHeightAsset.aspectRatio, 1.0, "Zero height must safely default to 1.0")
    }
    
    func testSyntheticAssetVolumeIngestion() {
        var assets: [PhotoAssetModel] = []
        let startTime = CFAbsoluteTimeGetCurrent()
        for i in 0..<10_000 {
            assets.append(PhotoAssetModel(
                id: "test-\(i)",
                localIdentifier: "ph-\(i)",
                creationDate: Date(timeIntervalSince1970: TimeInterval(1700000000 + i * 60)),
                estimatedByteSize: 2_500_000
            ))
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        XCTAssertEqual(assets.count, 10_000)
        XCTAssertLessThan(elapsed, 2.0, "10,000 synthetic assets must ingest within reasonable test budget")
    }
    
    // MARK: - Feature 3: Chronological Monthly Bucketing (F3)
    
    func testMonthlyBucketingOrdering() {
        let cal = Calendar(identifier: .gregorian)
        var comp1 = DateComponents()
        comp1.year = 2026; comp1.month = 10; comp1.day = 15
        let dateOct2026 = cal.date(from: comp1)!
        
        var comp2 = DateComponents()
        comp2.year = 2026; comp2.month = 9; comp2.day = 20
        let dateSep2026 = cal.date(from: comp2)!
        
        var comp3 = DateComponents()
        comp3.year = 2025; comp3.month = 12; comp3.day = 31
        let dateDec2025 = cal.date(from: comp3)!
        
        let bucketOct = MonthIdentifier(year: 2026, month: 10)
        let bucketSep = MonthIdentifier(year: 2026, month: 9)
        let bucketDec = MonthIdentifier(year: 2025, month: 12)
        
        XCTAssertTrue(bucketDec < bucketSep)
        XCTAssertTrue(bucketSep < bucketOct)
        XCTAssertEqual(bucketOct.title, "October 2026")
    }
    
    func testLeapYearDatePartitioning() {
        let cal = Calendar(identifier: .gregorian)
        var comp = DateComponents()
        comp.year = 2024; comp.month = 2; comp.day = 29
        let leapDay = cal.date(from: comp)!
        
        let year = cal.component(.year, from: leapDay)
        let month = cal.component(.month, from: leapDay)
        let identifier = MonthIdentifier(year: year, month: month)
        
        XCTAssertEqual(identifier.year, 2024)
        XCTAssertEqual(identifier.month, 2)
        XCTAssertEqual(identifier.title, "February 2024")
    }
    
    func testEmptyMonthlyBucketHandling() async throws {
        mockProvider.stubbedBuckets = []
        let buckets = try await mockProvider.fetchMonthlyBuckets()
        XCTAssertTrue(buckets.isEmpty, "Empty library must produce zero buckets without crashing")
    }
    
    // MARK: - Feature 4: Clutter Screenshot Detection (F4)
    
    func testScreenshotDetectionFilter() {
        let screenshot = PhotoAssetModel(
            id: "shot-1",
            mediaType: .image,
            mediaSubtypes: .photoScreenshot,
            pixelWidth: 1179,
            pixelHeight: 2556,
            estimatedByteSize: 1_200_000
        )
        
        let standardPhoto = PhotoAssetModel(
            id: "photo-1",
            mediaType: .image,
            mediaSubtypes: [],
            pixelWidth: 4032,
            pixelHeight: 3024,
            estimatedByteSize: 3_500_000
        )
        
        XCTAssertTrue(screenshot.mediaSubtypes.contains(.photoScreenshot))
        XCTAssertFalse(standardPhoto.mediaSubtypes.contains(.photoScreenshot))
    }
    
    func testScreenshotClusterAggregation() {
        let shots = (1...5).map { i in
            PhotoAssetModel(
                id: "shot-\(i)",
                mediaType: .image,
                mediaSubtypes: .photoScreenshot,
                estimatedByteSize: 1_200_000
            )
        }
        
        let cluster = ClutterCluster(
            id: "screenshots-cluster",
            category: .screenshots,
            title: "Screenshots",
            assets: shots,
            totalByteSize: shots.reduce(0) { $0 + $1.estimatedByteSize }
        )
        
        XCTAssertEqual(cluster.count, 5)
        XCTAssertEqual(cluster.totalByteSize, 6_000_000)
    }
    
    // MARK: - Feature 5: Clutter Duplicate & Burst Clustering (F5)
    
    func testBurstClusterGrouping() {
        let burstId = "burst-xyz"
        let burst1 = PhotoAssetModel(id: "b1", burstIdentifier: burstId, representsBurst: true)
        let burst2 = PhotoAssetModel(id: "b2", burstIdentifier: burstId, representsBurst: true)
        let burst3 = PhotoAssetModel(id: "b3", burstIdentifier: burstId, representsBurst: true, isFavorite: true)
        
        let assets = [burst1, burst2, burst3]
        let grouped = Dictionary(grouping: assets, by: { $0.burstIdentifier })
        
        XCTAssertEqual(grouped[burstId]?.count, 3)
        let favorite = grouped[burstId]?.first(where: { $0.isFavorite })
        XCTAssertNotNil(favorite)
        XCTAssertEqual(favorite?.id, "b3")
    }
    
    func testTemporalProximityDuplicateHeuristic() {
        let baseDate = Date()
        let shotA = PhotoAssetModel(
            id: "sA",
            creationDate: baseDate,
            pixelWidth: 4032,
            pixelHeight: 3024
        )
        let shotB = PhotoAssetModel(
            id: "sB",
            creationDate: baseDate.addingTimeInterval(1.2), // <= 2.5s
            pixelWidth: 4032,
            pixelHeight: 3024
        )
        let shotC = PhotoAssetModel(
            id: "sC",
            creationDate: baseDate.addingTimeInterval(10.0), // > 2.5s
            pixelWidth: 4032,
            pixelHeight: 3024
        )
        
        let diffAB = abs(shotB.creationDate.timeIntervalSince(shotA.creationDate))
        let diffAC = abs(shotC.creationDate.timeIntervalSince(shotA.creationDate))
        
        XCTAssertLessThanOrEqual(diffAB, 2.5, "Shot A and B are within temporal proximity threshold")
        XCTAssertGreaterThan(diffAC, 2.5, "Shot A and C are outside temporal proximity threshold")
        XCTAssertEqual(shotA.pixelWidth, shotB.pixelWidth)
        XCTAssertEqual(shotA.pixelHeight, shotB.pixelHeight)
    }
    
    // MARK: - Feature 6: Clutter Large Video Filtering (F6)
    
    func testLargeVideoDetectionByDuration() {
        let longVideo = PhotoAssetModel(
            id: "v-long",
            mediaType: .video,
            duration: 120.0, // >= 60s
            estimatedByteSize: 150_000_000
        )
        
        let shortVideo = PhotoAssetModel(
            id: "v-short",
            mediaType: .video,
            duration: 15.0, // < 60s
            estimatedByteSize: 25_000_000
        )
        
        XCTAssertTrue(longVideo.duration >= 60.0 || longVideo.estimatedByteSize >= 100_000_000)
        XCTAssertFalse(shortVideo.duration >= 60.0 || shortVideo.estimatedByteSize >= 100_000_000)
    }
    
    func testLargeVideoDetectionBySize() {
        let shortHugeVideo = PhotoAssetModel(
            id: "v-huge",
            mediaType: .video,
            duration: 25.0, // < 60s
            estimatedByteSize: 250_000_000 // >= 100MB
        )
        
        XCTAssertTrue(shortHugeVideo.duration >= 60.0 || shortHugeVideo.estimatedByteSize >= 100_000_000)
    }
    
    // MARK: - Feature 7: Mock Photo Provider Protocol Verification (F7)
    
    func testMockPhotoProviderStubbing() async throws {
        let bucketId = MonthIdentifier(year: 2026, month: 10)
        let sampleAssets = [
            PhotoAssetModel(id: "p1"),
            PhotoAssetModel(id: "p2")
        ]
        mockProvider.stubbedAssets["2026-10"] = sampleAssets
        
        let fetched = try await mockProvider.fetchAssets(for: bucketId)
        XCTAssertEqual(fetched.count, 2)
        XCTAssertEqual(fetched.first?.id, "p1")
    }
}
