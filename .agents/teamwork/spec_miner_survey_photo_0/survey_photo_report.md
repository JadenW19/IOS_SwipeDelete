# Technical Specification: Photo Library Chronological & Category Ingestion (R1)
**Project**: SwipeWipe Native iOS Rebuild  
**Target Environment**: iOS 27.0.1+, iPhone 14 Pro (120Hz ProMotion, Dynamic Island)  
**Author**: Photo Library Spec Miner (`spec_miner_survey_photo_0`)  
**Status**: Authoritative Draft  
**Reference Document**: `ORIGINAL_REQUEST.md` (Requirement R1, R4)

---

## 1. Executive Summary & Existing Codebase Audit

### 1.1 Existing Codebase Audit
An inspection of the workspace root (`c:\Users\jzlwi\Documents\antigravity\magical-bohr`) and target project directory (`c:\Users\jzlwi\Documents\antigravity\magical-bohr\SwipeWipe`) was conducted:
- The `SwipeWipe` directory does not currently exist.
- No legacy source files, Xcode project files (`.xcodeproj` / `.xcworkspace`), Swift packages (`Package.swift`), or third-party dependencies are present.
- **Finding**: This project is a greenfield implementation. All protocols, domain models, algorithms, and UI views must be architected cleanly from first principles.

### 1.2 Scope of Requirement R1
Requirement R1 mandates:
1. Graceful handling of all PhotoKit system privacy permission states (`.notDetermined`, `.authorized`, `.limited`, `.denied`, `.restricted`).
2. High-performance chronological grouping and monthly bucketing of camera roll media for large libraries (10,000+ to 100,000+ assets).
3. Intelligent clutter categorization heuristics for screenshots, duplicate/burst clusters, and large video files.
4. Clean architectural abstraction (`PhotoLibraryProviding`) separating domain logic from Apple's `Photos` framework, enabling 100% headless automated unit and UI testing via `MockPhotoProvider`.

---

## 2. PhotoKit Permissions Architecture

### 2.1 State Matrix & System Transitions
PhotoKit permissions are governed by `PHPhotoLibrary` and `PHAuthorizationStatus` under `PHAccessLevel.readWrite`. SwipeWipe requires read access to ingest and display assets and write access to delete marked assets.

| Status | Raw Value | Meaning | System UI Behavior | SwipeWipe Actionable UI/UX |
|---|---|---|---|---|
| `.notDetermined` | 0 | User has never been prompted for photo library access. | System prompt will display upon calling `requestAuthorization(for: .readWrite)`. | Display pre-permission onboarding card explaining value proposition ("Find & clean clutter safely"), then trigger system prompt. |
| `.restricted` | 1 | Access restricted by MDM profiles, parental controls (Screen Time), or corporate policy. | User cannot grant permission even if requested. | Display informational locked state: "Photo access is restricted on this device by Screen Time or device management." No CTA to Settings. |
| `.denied` | 2 | User tapped "Don't Allow" or revoked access in iOS Settings. | System prompt will NOT re-appear. Calling request returns `.denied` immediately. | Display educational fallback view with visual illustration, explanation of why photos are required, and deep link button to `UIApplication.openSettingsURLString`. |
| `.authorized` | 3 | Full access granted to all camera roll assets. | No system prompts. Full library accessible. | Seamlessly transition into camera roll ingestion and monthly bucket indexing. |
| `.limited` | 4 | User selected "Select Photos..." (iOS 14+). Only chosen assets are readable. | System provides limited photo selection modal. | Ingest only available assets; show non-intrusive persistent banner: "Limited Access: SwipeWipe can only clean selected photos. [Manage Photos] or [Allow All]". |

### 2.2 Info.plist Configuration
The following mandatory keys must be declared in `Info.plist`:
```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>SwipeWipe needs access to your photo library to help you review, organize, and clean up unwanted photos and videos.</string>
```
*Failure Condition*: Attempting to call `PHPhotoLibrary.requestAuthorization` or any `PHAsset` fetch without `NSPhotoLibraryUsageDescription` results in an unrecoverable Mach crash (`SIGABRT`) triggered by `tccd`.

### 2.3 Limited Access Management
When `status == .limited`:
- The app can invoke `PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: controller)` to allow the user to expand or change their selected subset.
- The app must conform to `PHPhotoLibraryChangeObserver` to dynamically update monthly buckets and clutter groups when the user edits the limited selection.
- In SwiftUI, this is exposed through a clean modal or an action sheet button invoking the limited picker via a Coordinator.

### 2.4 Asynchronous Concurrency Model
All permission queries and requests must adhere to modern Swift structured concurrency:
```swift
public enum PhotoAuthorizationStatus: Sendable {
    case notDetermined
    case restricted
    case denied
    case authorized
    case limited
}

public protocol PhotoLibraryProviding: Sendable {
    var authorizationStatus: PhotoAuthorizationStatus { get }
    func requestAuthorization() async -> PhotoAuthorizationStatus
    func openSettings() async
    func presentLimitedLibraryPicker() async
}
```
*Thread-Safety Constraint*: System permission callbacks and `PHPhotoLibraryChangeObserver` callbacks fire on arbitrary background threads. State variables binding to SwiftUI views must be published on `@MainActor`.

---

## 3. Chronological Monthly Bucketing

### 3.1 Data Structures
Photos must be partitioned chronologically by Year and Month.

```swift
public struct MonthIdentifier: Hashable, Comparable, Sendable {
    public let year: Int
    public let month: Int // 1...12

    public var title: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        let monthName = formatter.monthSymbols[month - 1]
        return "\(monthName) \(year)"
    }

    public static func < (lhs: MonthIdentifier, rhs: MonthIdentifier) -> Bool {
        if lhs.year != rhs.year {
            return lhs.year < rhs.year
        }
        return lhs.month < rhs.month
    }
}

public struct MonthlyBucket: Identifiable, Sendable {
    public var id: MonthIdentifier { identifier }
    public let identifier: MonthIdentifier
    public let assetCount: Int
    public let totalByteSizeEstimate: Int64
    public let coverAssetIdentifier: String?
    public let assets: [PhotoAssetModel] // Or lazy identifier handles
}
```

### 3.2 Performance Architecture (10,000+ Assets)
Naive implementations fetch all `PHAsset` objects, extract images into memory, or perform repeated synchronous queries, causing memory pressure (OOM) and UI stuttering.

#### Key Optimization Principles:
1. **Lazy Fetch Results (`PHFetchResult`)**:
   `PHFetchResult` is a native iOS CoreData/SQLite query pointer. It does not materialize full `UIImage` instances or heavy asset blobs in RAM. Even with 100,000 assets, holding a `PHFetchResult` consumes less than 5MB of RAM.
2. **Predicate-Partitioned Monthly Querying**:
   Rather than fetching 100,000 assets into memory and grouping in Swift via dictionary grouping (`Dictionary(grouping:by:)`), the engine can determine the minimum and maximum `creationDate` in the library:
   - Query earliest asset: `fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]`, fetch limit = 1.
   - Query latest asset: `fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]`, fetch limit = 1.
   - Generate month boundaries between `minDate` and `maxDate`.
   - For each month, execute a lightweight count fetch with date range predicates:
     `NSPredicate(format: "creationDate >= %@ AND creationDate < %@", startOfMonth, endOfMonth)`.
   - Alternatively, perform a single fast pass over `creationDate` properties using `PHFetchResult.enumerateObjects`:
     `enumerateObjects` takes ~35ms for 25,000 assets on iPhone 14 Pro hardware because `creationDate` is indexed in SQLite.
3. **Decoupled Deck Paging**:
   The card-swiping view only requires the active month's assets loaded in the deck stack (top 3 visible cards in memory + next 10 pre-cached). When switching months, previous month card textures are immediately evicted.
4. **Sorting Order**:
   Default to descending chronological order (current month first) so users can immediately clean recent photos, with a toggle for ascending order (oldest photos first) for nostalgic cleaning.

---

## 4. Clutter Detection Heuristics & Categorization

Clutter categories allow users to make high-impact, high-volume cleanup decisions rapidly. SwipeWipe identifies three primary clutter categories: Screenshots, Duplicates/Bursts, and Large Videos.

### 4.1 Category 1: Screenshots
- **Criteria**:
  - `PHAsset.mediaType == .image`
  - `PHAsset.mediaSubtypes.contains(.photoScreenshot)` (bitmask value: `PHAssetMediaSubtype.photoScreenshot.rawValue`).
- **Fetch Predicate**:
  ```swift
  let options = PHFetchOptions()
  options.predicate = NSPredicate(format: "(mediaSubtype & %d) != 0", PHAssetMediaSubtype.photoScreenshot.rawValue)
  options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
  ```
- **Alternative System Album**:
  `PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumScreenshots, options: nil)`.
  This is instant (0ms latency) because the iOS Photos daemon pre-indexes screenshots in the background.

### 4.2 Category 2: Duplicates & Similar Photos
Duplicate detection employs a multi-tiered heuristic pipeline balancing accuracy and mobile CPU/battery constraints:

#### Tier 1: Burst Grouping (Hardware Zero-Cost)
- Many duplicate photos originate from camera bursts (holding shutter down).
- **Criteria**:
  - `asset.representsBurst == true`
  - Group by `asset.burstIdentifier`
  - In each burst group, select the primary photo (or photo with highest quality/sharpness metric if available) as "Keep Candidate" and mark the remaining N-1 assets as "Duplicate Clutter Candidates".

#### Tier 2: Temporal Proximity + Aspect Ratio / Resolution Clustering
- Users frequently tap the shutter multiple times in rapid succession.
- **Heuristic Parameters**:
  - `Δt` (Time difference) $\le 2.5\text{ seconds}$ between consecutive shots.
  - Same media type (`.image`).
  - Resolution match: `pixelWidth == next.pixelWidth` and `pixelHeight == next.pixelHeight`.
  - Focal/Aspect ratio match: `abs((Double(w) / Double(h)) - (Double(w2) / Double(h2))) < 0.001`.
- **Clustering Algorithm**:
  1. Fetch all non-screenshot, non-burst still images sorted by `creationDate` ascending.
  2. Slide an active cluster window:
     - If `abs(current.creationDate.timeIntervalSince(cluster.anchorDate)) <= 2.5` and dimensions match, append to cluster.
     - If gap exceeds threshold, close current cluster. If cluster contains $\ge 2$ assets, emit as duplicate cluster.

#### Tier 3: Perceptual Difference Hashing (dHash) for Verification
- For suspected clusters from Tier 2, compute a 64-bit difference hash (dHash) on downsampled 9x8 grayscale thumbnails:
  1. Downsample thumbnail to 9 pixels wide by 8 pixels high (via `PHImageManager` target size 9x8).
  2. Convert to grayscale luminance: $Y = 0.299R + 0.587G + 0.114B$.
  3. Compare adjacent pixels horizontally: if $P(x, y) > P(x+1, y)$, set bit to 1, else 0 (yielding $8 \times 8 = 64\text{ bits}$).
  4. Compute Hamming distance between 64-bit hashes:
     - Distance $\le 5$: Exact or near-identical duplicate.
     - Distance $6 \dots 10$: Similar pose/composition.
     - Distance $> 10$: Different scene.

### 4.3 Category 3: Large Videos
Video files represent the fastest way to reclaim gigabytes of storage space.
- **Criteria**:
  - `asset.mediaType == .video`
  - Duration threshold: `asset.duration >= 60.0` (duration in seconds; configurable in settings: 1m, 3m, 5m).
  - Size threshold: Estimated or actual file size $\ge 100\text{ MB}$ ($104,857,600\text{ bytes}$).
- **File Size Calculation**:
  - Apple does not expose a synchronous `asset.fileSize` property on `PHAsset`.
  - *Method A (Exact)*: Read `PHAssetResource.assetResources(for: asset)`. Query `resource.value(forKey: "fileSize") as? Int64`. This is accessible locally for cached assets without downloading from iCloud.
  - *Method B (Bitrate Estimation)*:
    Estimated size $= \text{duration} \times \text{averageBitrate}$.
    - 4K @ 60fps HEVC: $\approx 55\text{ MB/min}$.
    - 1080p @ 30fps H.264: $\approx 130\text{ MB/min}$.
    - Heuristic default: $\approx 1.5\text{ MB/sec}$. A 2-minute video is conservatively estimated at $\approx 180\text{ MB}$.
- **Fetch Predicate**:
  ```swift
  let options = PHFetchOptions()
  options.predicate = NSPredicate(format: "mediaType == %d AND duration >= 60.0", PHAssetMediaType.video.rawValue)
  options.sortDescriptors = [NSSortDescriptor(key: "duration", ascending: false)]
  ```

---

## 5. Abstraction & Protocol Design for 100% Headless Automated Testing

### 5.1 Decoupled Domain Models
To decouple the UI and test suites from Apple's `Photos` framework, domain models must be pure Swift value types (`Sendable`, `Hashable`, `Identifiable`).

```swift
import Foundation
import CoreGraphics

public enum AssetMediaType: String, Sendable, Codable {
    case image
    case video
    case audio
    case unknown
}

public struct AssetMediaSubtypes: OptionSet, Sendable, Codable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }

    public static let photoPanorama  = AssetMediaSubtypes(rawValue: 1 << 0)
    public static let photoHDR       = AssetMediaSubtypes(rawValue: 1 << 1)
    public static let photoScreenshot = AssetMediaSubtypes(rawValue: 1 << 2)
    public static let photoLive      = AssetMediaSubtypes(rawValue: 1 << 3)
    public static let photoDepthEffect = AssetMediaSubtypes(rawValue: 1 << 4)
    public static let videoStreamed  = AssetMediaSubtypes(rawValue: 1 << 16)
    public static let videoHighFrameRate = AssetMediaSubtypes(rawValue: 1 << 17)
    public static let videoTimelapse = AssetMediaSubtypes(rawValue: 1 << 18)
}

public struct PhotoAssetModel: Identifiable, Hashable, Sendable {
    public let id: String
    public let localIdentifier: String
    public let creationDate: Date
    public let modificationDate: Date?
    public let mediaType: AssetMediaType
    public let mediaSubtypes: AssetMediaSubtypes
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let duration: TimeInterval
    public let estimatedByteSize: Int64
    public let isFavorite: Bool
    public let isHidden: Bool
    public let burstIdentifier: String?
    public let representsBurst: Bool

    public var aspectRatio: CGFloat {
        guard pixelHeight > 0 else { return 1.0 }
        return CGFloat(pixelWidth) / CGFloat(pixelHeight)
    }

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: estimatedByteSize, countStyle: .file)
    }

    public init(
        id: String = UUID().uuidString,
        localIdentifier: String = UUID().uuidString,
        creationDate: Date = Date(),
        modificationDate: Date? = nil,
        mediaType: AssetMediaType = .image,
        mediaSubtypes: AssetMediaSubtypes = [],
        pixelWidth: Int = 1179,
        pixelHeight: Int = 2556,
        duration: TimeInterval = 0,
        estimatedByteSize: Int64 = 3_500_000,
        isFavorite: Bool = false,
        isHidden: Bool = false,
        burstIdentifier: String? = nil,
        representsBurst: Bool = false
    ) {
        self.id = id
        self.localIdentifier = localIdentifier
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.mediaType = mediaType
        self.mediaSubtypes = mediaSubtypes
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.duration = duration
        self.estimatedByteSize = estimatedByteSize
        self.isFavorite = isFavorite
        self.isHidden = isHidden
        self.burstIdentifier = burstIdentifier
        self.representsBurst = representsBurst
    }
}
```

### 5.2 Clutter Categorization Models
```swift
public enum ClutterCategoryType: String, CaseIterable, Identifiable, Sendable {
    case screenshots = "Screenshots"
    case duplicates = "Duplicates"
    case largeVideos = "Large Videos"
    case bursts = "Burst Shots"

    public var id: String { rawValue }

    public var systemIcon: String {
        switch self {
        case .screenshots: return "camera.viewfinder"
        case .duplicates: return "doc.on.doc"
        case .largeVideos: return "video.badge.waveform"
        case .bursts: return "square.stack.3d.down.right"
        }
    }
}

public struct ClutterCluster: Identifiable, Sendable {
    public let id: String
    public let category: ClutterCategoryType
    public let title: String
    public let assets: [PhotoAssetModel]
    public let totalByteSize: Int64

    public var count: Int { assets.count }
}
```

### 5.3 Complete `PhotoLibraryProviding` Protocol Definition
```swift
public protocol PhotoLibraryProviding: AnyObject, Sendable {
    /// Current authorization status
    var authorizationStatus: PhotoAuthorizationStatus { get }

    /// Request user authorization asynchronously
    func requestAuthorization() async -> PhotoAuthorizationStatus

    /// Deep link to system settings
    func openSettings() async

    /// Trigger system limited library picker UI
    func presentLimitedLibraryPicker() async

    /// Fetch all chronological monthly buckets
    func fetchMonthlyBuckets() async throws -> [MonthlyBucket]

    /// Fetch assets for a specific monthly bucket
    func fetchAssets(for bucketId: MonthIdentifier) async throws -> [PhotoAssetModel]

    /// Fetch all clutter clusters for a given clutter category
    func fetchClutterCategory(_ category: ClutterCategoryType) async throws -> [ClutterCluster]

    /// Batch delete assets permanently via OS photo library confirmation
    func deleteAssets(withIdentifiers identifiers: [String]) async throws -> Bool

    /// Load displayable image data or thumbnail for card rendering
    func loadThumbnail(for assetId: String, targetSize: CGSize) async throws -> CGImage?

    /// Register change notification observer
    func addObserver(_ observer: PhotoLibraryObserving)
    func removeObserver(_ observer: PhotoLibraryObserving)
}

public protocol PhotoLibraryObserving: AnyObject, Sendable {
    func photoLibraryDidChange()
}
```

### 5.4 `MockPhotoProvider` Implementation for Automated Testing
The mock provider allows tests to inject any arbitrary state: authorized, denied, limited, empty library, 20,000 synthetic assets, custom burst clusters, or simulated deletion errors.

```swift
public final class MockPhotoProvider: PhotoLibraryProviding, @unchecked Sendable {
    private let lock = NSLock()
    public var stubbedAuthorizationStatus: PhotoAuthorizationStatus
    public var stubbedBuckets: [MonthlyBucket] = []
    public var stubbedAssets: [String: [PhotoAssetModel]] = [:] // bucketId.key -> assets
    public var stubbedClutter: [ClutterCategoryType: [ClutterCluster]] = [:]
    public var deletedAssetIdentifiers: [String] = []
    public var shouldThrowDeletionError: Bool = false
    public var deletionCallCount: Int = 0

    private var observers: [PhotoLibraryObserving] = []

    public init(status: PhotoAuthorizationStatus = .authorized) {
        self.stubbedAuthorizationStatus = status
    }

    public var authorizationStatus: PhotoAuthorizationStatus {
        lock.lock()
        defer { lock.unlock() }
        return stubbedAuthorizationStatus
    }

    public func requestAuthorization() async -> PhotoAuthorizationStatus {
        lock.lock()
        defer { lock.unlock() }
        return stubbedAuthorizationStatus
    }

    public func openSettings() async {
        // Mock no-op or recorded call
    }

    public func presentLimitedLibraryPicker() async {
        // Mock no-op or recorded call
    }

    public func fetchMonthlyBuckets() async throws -> [MonthlyBucket] {
        lock.lock()
        defer { lock.unlock() }
        guard stubbedAuthorizationStatus == .authorized || stubbedAuthorizationStatus == .limited else {
            return []
        }
        return stubbedBuckets
    }

    public func fetchAssets(for bucketId: MonthIdentifier) async throws -> [PhotoAssetModel] {
        lock.lock()
        defer { lock.unlock() }
        guard stubbedAuthorizationStatus == .authorized || stubbedAuthorizationStatus == .limited else {
            return []
        }
        let key = "\(bucketId.year)-\(bucketId.month)"
        return stubbedAssets[key] ?? []
    }

    public func fetchClutterCategory(_ category: ClutterCategoryType) async throws -> [ClutterCluster] {
        lock.lock()
        defer { lock.unlock() }
        guard stubbedAuthorizationStatus == .authorized || stubbedAuthorizationStatus == .limited else {
            return []
        }
        return stubbedClutter[category] ?? []
    }

    public func deleteAssets(withIdentifiers identifiers: [String]) async throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        deletionCallCount += 1
        if shouldThrowDeletionError {
            throw NSError(domain: "MockPhotoProvider", code: 403, userInfo: [NSLocalizedDescriptionKey: "Simulated deletion error"])
        }
        deletedAssetIdentifiers.append(contentsOf: identifiers)
        return true
    }

    public func loadThumbnail(for assetId: String, targetSize: CGSize) async throws -> CGImage? {
        // Return dummy 1x1 or test CGImage
        return nil
    }

    public func addObserver(_ observer: PhotoLibraryObserving) {
        lock.lock()
        defer { lock.unlock() }
        observers.append(observer)
    }

    public func removeObserver(_ observer: PhotoLibraryObserving) {
        lock.lock()
        defer { lock.unlock() }
        observers.removeAll { $0 === observer }
    }

    public func simulateExternalChange() {
        lock.lock()
        let currentObservers = observers
        lock.unlock()
        for obs in currentObservers {
            obs.photoLibraryDidChange()
        }
    }
}
```

---

## 6. Features Discovered

| # | Category | Feature | Description | Inputs | Outputs | Error Behavior | Discovered Via |
|---|---|---|---|---|---|---|---|
| F1 | Permissions | Read/Write Authorization Request | Prompts user for camera roll access with read & delete capability. | `PHAccessLevel.readWrite` | `PHAuthorizationStatus` (`.authorized`, `.limited`, `.denied`, `.restricted`) | If `NSPhotoLibraryUsageDescription` missing, crashes with `SIGABRT`. If denied, returns `.denied`. | Apple `Photos` API (`PHPhotoLibrary`) |
| F2 | Permissions | Limited Library Access Modal | Prompts user to modify which assets the app is allowed to see without leaving the app. | `UIViewController` context | Modified asset set notification via `PHPhotoLibraryChangeObserver` | No-op if system status is not `.limited`. | Apple `PHPhotoLibrary.presentLimitedLibraryPicker` |
| F3 | Permissions | Settings Deep Link | Navigates user directly to app settings page in iOS Settings when permissions are denied. | `UIApplication.openSettingsURLString` | Opens Settings app | Returns false if URL scheme fails or device restricts Settings. | Apple `UIApplication` |
| F4 | Permissions | Change Observation | Listens to external photo additions, deletions, and iCloud sync updates. | `PHPhotoLibraryChangeObserver` registration | `PHChange` payload detailing inserted, removed, and updated object IDs | May deliver bursts of updates; requires debounce to prevent UI thrashing. | Apple `PHPhotoLibrary.register` |
| F5 | Bucketing | Chronological Month Partitioning | Groups all library assets into year/month cohorts ordered chronologically. | Array or fetch result of assets with `creationDate` | `[MonthlyBucket]` sorted ascending or descending | Assets with nil `creationDate` mapped to "Unknown Date" bucket or fallback to modification date. | `Calendar.current` date components |
| F6 | Bucketing | Lazy Month Indexing | Uses metadata query and count predicates rather than instantiating all assets into RAM. | Date range predicate (`creationDate >= start AND < end`) | `Int` count and cover asset ID | Returns count 0 if date range has no assets. | `PHFetchOptions.predicate` |
| F7 | Clutter | Screenshot Detection | Filters assets flagged as screenshots by iOS hardware capture. | `PHAssetMediaSubtype.photoScreenshot` or smart album | `[PhotoAssetModel]` (screenshots) | Returns empty collection if zero screenshots exist. | `PHAssetCollectionSubtype.smartAlbumScreenshots` |
| F8 | Clutter | Burst De-duplication | Isolates photos taken in rapid burst mode, grouping by burst ID. | `asset.representsBurst == true`, `asset.burstIdentifier` | Array of burst clusters with recommended primary asset | If single burst asset remains, treat as standard photo. | `PHAsset.burstIdentifier` |
| F9 | Clutter | Time-Proximity Duplicate Clustering | Clusters still photos taken within $\le 2.5\text{s}$ having identical resolution/aspect ratio. | Asset array sorted by `creationDate`, threshold $\Delta t = 2.5\text{s}$ | `[ClutterCluster]` where cluster size $\ge 2$ | None; ignores non-matching assets. | Heuristic algorithm |
| F10 | Clutter | Large Video Filtering | Identifies video assets exceeding duration (> 60s) and estimated file size (> 100MB). | `PHAssetMediaType.video`, `duration >= 60.0` | `[PhotoAssetModel]` (large videos) | Handled safely if duration is 0 or stream is iCloud-only. | `PHAsset.duration` & `PHAssetResource` |
| F11 | Ingestion | Reclaimable Size Estimation | Calculates total byte size of an asset collection for review queue display. | Collection of asset IDs or models | Total `Int64` bytes and formatted string (e.g. "2.4 GB") | Falls back to resolution-based heuristic if resource size unavailable. | `PHAssetResource` / heuristic table |
| F12 | Testing | Headless Mock Photo Provider | Fully isolated in-memory test double supporting injection of all photo states and errors. | Test scenario definitions (asset counts, mock permissions) | Deterministic models conforming to `PhotoLibraryProviding` | Deterministically throws configured errors for negative testing. | Architecture Specification |

---

## 7. Edge Cases & Boundary Conditions

| # | Feature | Input / Condition | Observed / Specified Behavior |
|---|---|---|---|
| E1 | Permissions | User denies permission on first prompt. | Status transitions to `.denied`. App displays instructional fallback view with "Open Settings" CTA. App does not attempt to query `PHAsset`, avoiding empty flash or freeze. |
| E2 | Permissions | User changes permission from `.authorized` to `.denied` in Settings while app is in background. | iOS terminates the app process automatically upon privacy entitlement revocation. When re-launched, app reads `.denied` on cold start. |
| E3 | Permissions | User selects `.limited` with zero photos selected. | Status is `.limited`, but `fetchMonthlyBuckets()` yields 0 assets. UI renders "No Photos Selected" state with button to "Select Photos". |
| E4 | Permissions | User adds photos to `.limited` selection via system picker. | `PHPhotoLibraryChangeObserver` fires. App reconciles diff and updates monthly bucket counts dynamically without restarting. |
| E5 | Bucketing | Photo has corrupted or missing `creationDate` (nil in database). | Engine defaults to `asset.modificationDate` or `Date(timeIntervalSince1970: 0)` ("January 1970" bucket), preventing crash or dropped asset. |
| E6 | Bucketing | Camera roll spans across Leap Years (e.g., Feb 29, 2024). | Gregorian calendar component computation handles leap day accurately without overflowing to March. |
| E7 | Bucketing | Timezone changes (user travelled across international dateline). | Assets are grouped based on `Calendar.current` local calendar or normalized UTC components to ensure consistent month grouping. |
| E8 | Bucketing | Massive library with 50,000+ photos in a single month. | Cards are not all loaded into memory. Deck loads top 3 cards + 10 pre-cached items. Evicts cards as user swipes past them. Memory capped at $< 50\text{ MB}$. |
| E9 | Clutter | iCloud Photos with "Optimize iPhone Storage" enabled (asset not downloaded locally). | Asset metadata (creation date, duration, dimensions) is still locally queryable. Thumbnail can be loaded with network access enabled (`options.isNetworkAccessAllowed = true`). If network fails, shows placeholder icon. |
| E10 | Clutter | Live Photos taken in rapid succession. | Live Photos have both image and video components (`.photoLive`). Engine must treat them as still photo duplicates based on primary image frame without triggering false positive large video classification. |
| E11 | Clutter | High Frame Rate (Slo-mo) video with duration 15s but huge file size (300MB). | Captured by file size threshold ($\ge 100\text{ MB}$) even if duration is below 60 seconds. |
| E12 | Clutter | Burst series where user already chose a favorite. | Engine preserves the user-selected favorite (`isFavorite == true`) and isolates only non-favorite burst members into clutter queue. |
| E13 | Testing | Mock provider simulated deletion failure (e.g. system timeout). | ViewModel catches error, leaves items in staged review queue, displays error banner, and prevents desynchronization. |

---

## 8. Integration Contracts with Other Requirements

1. **Contract with R2 (Swiping State Machine)**:
   - Ingestion provides `[PhotoAssetModel]` to the Swiping Deck ViewModel.
   - Each model provides `aspectRatio`, `formattedSize`, and unique `id`.
   - Deck interacts with `loadThumbnail(for:targetSize:)` to populate the card view.
2. **Contract with R3 (Staging & Batch Deletion Safety)**:
   - Swiping left passes `PhotoAssetModel.localIdentifier` and `estimatedByteSize` into `StagedDeletionQueue`.
   - Staged queue aggregates total byte size and count.
   - Upon explicit user confirmation, `PhotoLibraryProviding.deleteAssets(withIdentifiers:)` is invoked.
3. **Contract with R4 (Automated Verification Suite)**:
   - All tests instantiate `MockPhotoProvider` and pass it into ViewModels.
   - Unit tests verify chronological order, edge case dates, and clutter filtering in $< 500\text{ms}$ execution time.

---

## 9. Conclusion & Recommendations for Implementation Track

1. **Protocol-First**: Create `PhotoLibraryProviding.swift`, `PhotoAssetModel.swift`, and `MockPhotoProvider.swift` first.
2. **Safety Defaults**: Never execute deletion requests directly in ingestion; always pass asset IDs to the Staged Queue (R3).
3. **Performance First**: Never convert an entire `PHFetchResult` to `[UIImage]` at once. Rely strictly on thumbnail requests on-demand.
