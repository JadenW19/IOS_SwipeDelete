# Project: SwipeWipe Native iOS Rebuild

## Architecture
SwipeWipe is built as a high-performance, modular Swift application optimized for iPhone 14 Pro (120Hz ProMotion display, Dynamic Island) and iOS 27.0.1+.
The architecture enforces strict separation of concerns, protocol-oriented dependency injection, thread-safe state management, and 100% headless testability.

### Key Architectural Layers:
1. **Core Domain & Models (`SwipeWipeCore/Models`)**:
   - Pure Swift, `Sendable`, immutable models: `PhotoAssetModel`, `MonthlyBucket`, `MonthIdentifier`, `ClutterCategory`, `SwipeAction`, `StagedAssetItem`.
2. **Service Abstractions & Protocols (`SwipeWipeCore/Protocols`)**:
   - `PhotoLibraryProviding`: Decouples all camera roll queries, permissions, and batch deletions from `Photos.framework`.
   - `HapticFeedbackServiceProtocol`: Decouples tactile impacts (`UIImpactFeedbackGenerator`) for headless execution.
   - `BatchDeletionServiceProtocol`: Encapsulates OS photo deletion requests, double-confirmation gating, and error handling.
3. **Core Engines & Services (`SwipeWipeCore/Services`)**:
   - `MockPhotoProvider`: Full synthetic asset generation, customizable latency, error injection (permission denial, user cancellation code 3072, system failure).
   - `PhotoLibraryService`: Production PhotoKit bridge handling `.authorized`, `.limited`, `.denied` states and lazy batch fetch.
   - `ClutterDetector`: Algorithmic clustering for Screenshots (`.photoScreenshot`), Duplicates (hardware burst + temporal proximity $\Delta t \le 2.5\text{s}$ + resolution clustering + dHash), and Large Videos ($\ge 60\text{s}$ or $\ge 100\text{MB}$).
   - `StagedQueueStore`: Thread-safe $O(1)$ staging store with running count, running byte calculations, and dictionary indexing for 120Hz swiping.
   - `NativeBatchDeletionService`: Manages deletion execution, favorite photo safeguards, and error code 3072 safe recovery.
   - `HapticFeedbackService`: Debounced tactile feedback driver.
4. **Interactive ViewModels (`SwipeWipeCore/ViewModels`)**:
   - `CardDeckViewModel`: 120Hz ProMotion swipe gesture physics ($X_{threshold} = 137.5\text{pt}$, $V_{threshold} = 800\text{pt/s}$), 3-card sliding window, dynamic rotation $\theta = (dx/393) \times 20^\circ$, and LIFO undo stack.
   - `LibraryViewModel`: Permission coordinator, monthly chronological bucketing, clutter segment manager.
   - `ReviewQueueViewModel`: Staging drawer view model, individual unstaging (to Retained or Deck), bulk clearance, and deletion flow.
5. **Native UI Layer (`SwipeWipeApp/Views`)**:
   - iPhone 14 Pro layout: Top safe area 59pt (Dynamic Island clearance), bottom safe area 34pt.
   - Smooth continuous squircle clipping (`RoundedRectangle(cornerRadius: 24, style: .continuous)`), avoiding dynamic shadows or off-screen GPU passes to sustain 8.33ms frame budgets.
6. **Dual-Track Verification (`Tests/`)**:
   - Native XCTest test suite for Xcode / macOS CI.
   - Standalone Python 3.13 verification test runner (`tests/verify_suite.py`) validating 100% of state transitions, math, deck operations, and mock error flows headlessly on Windows.

---

## Feature Inventory
Every feature identified during Phase 0 Survey is mapped to a milestone below:

| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| F1 | PhotoKit Permission Handling | Complete lifecycle for `.notDetermined`, `.authorized`, `.limited`, `.denied`, `.restricted` without crashing | M1 | Survey R1 |
| F2 | Lazy Asset Ingestion | Single-pass metadata enumeration over `PHFetchResult` indexing 50,000+ assets in < 50ms | M1 | Survey R1 |
| F3 | Chronological Monthly Bucketing | Grouping assets into `MonthlyBucket` with year/month sorting | M1 | Survey R1 |
| F4 | Clutter: Screenshot Detection | Identification via `PHAssetMediaSubtype.photoScreenshot` and smart albums | M1 | Survey R1 |
| F5 | Clutter: Duplicate Detection | Clustering via burst identifiers, temporal proximity $\Delta t \le 2.5\text{s}$, resolution match, and dHash | M1 | Survey R1 |
| F6 | Clutter: Large Video Detection | Isolating video assets with duration $\ge 60\text{s}$ or estimated size $\ge 100\text{MB}$ | M1 | Survey R1 |
| F7 | PhotoLibraryProviding & Mock Provider | Protocol abstraction and configurable `MockPhotoProvider` for synthetic asset generation and error injection | M1 | Survey R1/R4 |
| F8 | 120Hz ProMotion Frame Budgeting | Isolated drag bindings, continuous squircles, 8.33ms rendering budget | M2 | Survey R2 |
| F9 | Card Deck Stacking & Visual Depth | Sliding 3-card window with scale ($1.0 \to 0.94 \to 0.88$) and offset interpolation | M2 | Survey R2 |
| F10 | Bi-Directional Decision Engine | Swipe right (Retain), Swipe left (Stage Delete), distance threshold (137.5pt) and velocity escape ($800\text{pt/s}$) | M2 | Survey R2 |
| F11 | Dynamic Rotation Physics | Rotation angle $\theta = (dx/393) \times 20^\circ$ anchored at bottom center | M2 | Survey R2 |
| F12 | LIFO Undo Stack | History of `SwipeAction`, reversing keep/delete state, restoring top of deck with entrance animation | M2 | Survey R2 |
| F13 | Tactile Haptic System | Debounced threshold impacts, commit haptics, error warning, and mock protocol | M2 | Survey R2 |
| F14 | Staged Deletion Queue Store | Thread-safe $O(1)$ enqueue/dequeue, running count, and running byte aggregation | M3 | Survey R3 |
| F15 | Non-Destructive Review UI Model | Dedicated staging queue, total space formatting, individual unstaging to Retained/Deck, bulk reset | M3 | Survey R3 |
| F16 | Batch Deletion Safety Bridge | Native deletion execution via `PHAssetChangeRequest.deleteAssets` with confirmation modal trigger | M3 | Survey R3 |
| F17 | System Dialog Cancellation Guard | Handling PhotoKit error code 3072 (`PHPhotosError.userCancelled`) without queue loss | M3 | Survey R3 |
| F18 | Favorite Asset Warning Guard | Warning before staging or deleting user-favorited photos | M3 | Survey R3 |
| F19 | iPhone 14 Pro Native UI Layout | Dynamic Island clearance (59pt top safe area, 34pt bottom safe area, 393x852pt canvas) | M4 | Survey R2 |
| F20 | SwiftUI Card Views & Gestures | `CardStackView`, `PhotoCardView`, gesture handlers, progress indicators | M4 | Survey R2 |
| F21 | Staged Review Drawer & Grid | `ReviewQueueSheet`, thumbnail grid, unstage buttons, delete confirmation button | M4 | Survey R3 |
| F22 | Empty State & Completion Views | Celebration screen, statistics summary, navigation back to monthly buckets | M4 | Survey R2 |
| F23 | E2E Headless Test Harness (Tiers 1-4) | Automated test harness running Tier 1-4 suites on Windows with 100% pass rate | E2E Track | Survey R4 |
| F24 | Native XCTest Test Suite | Full Swift unit/integration test suite for macOS CI / Xcode | E2E Track | Survey R4 |
| F25 | Adversarial Coverage Hardening (Tier 5) | White-box stress testing, memory leak checks, concurrency race checks, audit | M5 Phase 2 | Project Pattern |

---

## Milestones

| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| E2E | E2E Testing Track | Build Test Harness, Mock Data Generators, Tiers 1-4 Test Suites; publish `TEST_READY.md` | Survey | DONE |
| M1 | Photo Ingestion & Categorization Engine | Models, `PhotoLibraryProviding`, `MockPhotoProvider`, permissions, monthly bucketing, clutter detection | Survey | DONE |
| M2 | Swiping Engine & State Machine | `CardDeckViewModel`, 120Hz physics, thresholds, LIFO undo stack, haptic protocol | M1 | DONE |
| M3 | Staging Queue & Batch Deletion Safety | `StagedQueueStore`, non-destructive review logic, batch deletion bridge, error 3072 safety guard | M1 | DONE |
| M4 | Native SwiftUI Views & Dynamic Island Shell | `SwipeWipeApp`, `CardStackView`, `PhotoCardView`, `ReviewQueueSheet`, Dynamic Island layout | M2, M3 | DONE |
| M5 | Final Milestone: Full Verification & Hardening | Phase 1: 100% pass on Tiers 1-4 E2E tests. Phase 2: Tier 5 Adversarial Coverage Hardening with Challengers & Forensic Auditor | M4, E2E | DONE |

---

## Interface Contracts

### 1. Photo Ingestion (M1) ↔ Swiping Engine (M2)
```swift
public protocol PhotoLibraryProviding: Sendable {
    func requestAuthorizationStatus() async -> PhotoAuthorizationStatus
    func fetchMonthlyBuckets() async throws -> [MonthlyBucket]
    func fetchClutterCategory(_ category: ClutterCategoryType) async throws -> [PhotoAssetModel]
    func deleteAssets(withIdentifiers ids: [String]) async throws -> BatchDeletionResult
}
```

### 2. Swiping Engine (M2) ↔ Staging Safety Queue (M3)
```swift
public enum SwipeDirection: Sendable {
    case retain
    case stageDelete
}

public struct SwipeAction: Sendable, Equatable {
    public let assetId: String
    public let direction: SwipeDirection
    public let timestamp: Date
}

public protocol StagedQueueStoreProtocol: Sendable {
    var stagedCount: Int { get }
    var totalReclaimedBytes: Int64 { get }
    func enqueue(asset: PhotoAssetModel)
    func remove(assetId: String) -> PhotoAssetModel?
    func clear()
    func allStagedAssets() -> [PhotoAssetModel]
}
```

### 3. Core Engine (M1-M3) ↔ Native UI Views (M4)
```swift
@MainActor
public final class CardDeckViewModel: ObservableObject {
    @Published public private(set) var visibleCards: [PhotoAssetModel]
    @Published public private(set) var activeDragOffset: CGSize
    @Published public private(set) var canUndo: Bool
    public func handleDragChanged(offset: CGSize, velocity: CGSize)
    public func handleDragEnded(offset: CGSize, velocity: CGSize)
    public func undoLastSwipe()
}
```

---

## Code Layout
```
SwipeWipe/
├── Package.swift
├── Sources/
│   ├── SwipeWipeCore/
│   │   ├── Models/
│   │   │   ├── PhotoAssetModel.swift          (Worker M1)
│   │   │   ├── MonthlyBucket.swift            (Worker M1)
│   │   │   ├── ClutterCategory.swift          (Worker M1)
│   │   │   ├── SwipeAction.swift              (Worker M2)
│   │   │   └── StagedAssetItem.swift          (Worker M3)
│   │   ├── Protocols/
│   │   │   ├── PhotoLibraryProviding.swift    (Worker M1)
│   │   │   ├── HapticFeedbackProtocol.swift   (Worker M2)
│   │   │   └── StagedQueueStoreProtocol.swift (Worker M3)
│   │   ├── Services/
│   │   │   ├── MockPhotoProvider.swift        (Worker M1)
│   │   │   ├── PhotoLibraryService.swift      (Worker M1)
│   │   │   ├── ClutterDetector.swift          (Worker M1)
│   │   │   ├── StagedQueueStore.swift         (Worker M3)
│   │   │   ├── NativeBatchDeletionService.swift (Worker M3)
│   │   │   └── HapticFeedbackService.swift    (Worker M2)
│   │   └── ViewModels/
│   │       ├── LibraryViewModel.swift         (Worker M1)
│   │       ├── CardDeckViewModel.swift        (Worker M2)
│   │       └── ReviewQueueViewModel.swift     (Worker M3)
│   └── SwipeWipeApp/
│       ├── App/
│       │   └── SwipeWipeApp.swift             (Worker M4)
│       ├── Views/
│       │   ├── CardStackView.swift            (Worker M4)
│       │   ├── PhotoCardView.swift            (Worker M4)
│       │   ├── DynamicIslandHeaderView.swift  (Worker M4)
│       │   ├── ReviewQueueSheet.swift         (Worker M4)
│       │   └── EmptyStateView.swift           (Worker M4)
│       └── Utilities/
│           └── SizeFormatter.swift            (Worker M3)
├── Tests/
│   ├── SwipeWipeCoreTests/                    (Worker Track A)
│   │   ├── IngestionTests.swift
│   │   ├── SwipingDeckTests.swift
│   │   ├── StagingSafetyTests.swift
│   │   └── IntegrationFlowTests.swift
│   └── HeadlessHarness/                       (Worker Track A)
│       ├── verify_suite.py
│       └── test_cases.json
└── README.md
```
