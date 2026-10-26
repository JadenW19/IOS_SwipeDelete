# Milestone 1 Remediation Plan: Exact Line-Level Specification

- **Target Milestone**: Milestone 1 — Photo Ingestion & Categorization Engine
- **Author**: Milestone 1 Remediation Explorer (`explorer_m1_remediation_0`)
- **Review Source**: Reviewer 1 Handoff Report (`.agents/teamwork/reviewer_m1_1/handoff.md`)
- **Target Files**:
  1. `SwipeWipe/Sources/SwipeWipeCore/Services/PhotoLibraryService.swift`
  2. `SwipeWipe/Sources/SwipeWipeCore/Services/MockPhotoProvider.swift`
  3. `SwipeWipe/Sources/SwipeWipeCore/Protocols/PhotoLibraryProviding.swift`
  4. `SwipeWipe/Sources/SwipeWipeCore/ViewModels/LibraryViewModel.swift`
  5. `SwipeWipe/Sources/SwipeWipeCore/Models/ClutterCategory.swift`
- **Integrity Level**: Production-grade Swift 6.0 Strict Concurrency

---

## Executive Summary

An adversarial audit of Milestone 1 identified 4 primary issues:
1. **Critical: Fatal Continuation Double-Resume Crash** in `PhotoLibraryService.swift:287-300` when `PHImageManager.requestImage` invokes the result handler multiple times (degraded preview then high-quality asset).
2. **Major: Strong Retain Cycle** in `MockPhotoProvider.swift:60` and `PhotoLibraryService.swift` where stored observers strongly retain `LibraryViewModel`, causing permanent memory leaks.
3. **Major: Error 3072 User Cancellation Contract Mismatch** between `MockPhotoProvider.swift:209-214` (throws `NSError(code: 3072)`) and `PhotoLibraryService.swift:240-248` (swallows error and returns non-throwing failure struct).
4. **Minor: Burst Predicate Query Typo** in `PhotoLibraryService.swift:196` fetching screenshots or omitting burst member photos instead of `representsBurst == YES OR burstIdentifier != nil`.

Additionally, this plan provides line-level remediation for the 2 secondary defects surfaced during review:
5. **Minor: Explicit nil masking** in `ClutterCluster.init` (`ClutterCategory.swift:104`) which distorted screenshot and video clusters.
6. **Minor: Unsynchronized stored property** in `MockPhotoProvider.swift:35` (`deletionMode`) in an `@unchecked Sendable` class.

---

## Detailed Remediation Specifications

### Remediation Item 1: Continuation Once-Resume Guard & Degraded Filter
**Severity**: CRITICAL (Fatal Runtime Crash `SIGABRT`)  
**Target File**: `SwipeWipe/Sources/SwipeWipeCore/Services/PhotoLibraryService.swift`  
**Target Lines**: 281–308  

#### 1. Root Cause
In `PhotoLibraryService.swift`, `loadThumbnail` wraps `PHImageManager.default().requestImage` inside `withCheckedContinuation`:
```swift
let options = PHImageRequestOptions()
options.isNetworkAccessAllowed = true
options.deliveryMode = .highQualityFormat
options.isSynchronous = false

return await withCheckedContinuation { continuation in
    PHImageManager.default().requestImage(...) { image, _ in
        #if canImport(UIKit)
        continuation.resume(returning: image?.cgImage)
        #else
        continuation.resume(returning: nil)
        #endif
    }
}
```
Per Apple's PhotoKit specification, when `options.isSynchronous = false`, `requestImage` frequently calls the `resultHandler` twice: first with a degraded, low-resolution thumbnail preview (`info[PHImageResultIsDegradedKey] == true`), and then with the final full-quality image. In Swift 6 Concurrency, calling `continuation.resume` twice triggers an immediate fatal runtime abort:
`Fatal error: SWIFT TASK CONTINUATION MISUSE: tried to resume its continuation more than once!`

Furthermore, if a simple `if isDegraded { return }` is used without an atomic guard, network failures or iCloud timeouts that never deliver the second callback would leak the continuation and hang the calling Task permanently.

#### 2. Exact Remediation
1. Define a thread-safe helper class `ThumbnailContinuationGuard` conforming to `@unchecked Sendable` with an `NSLock` protecting a `didResume` boolean flag.
2. In `loadThumbnail(for:targetSize:)`, instantiate `ThumbnailContinuationGuard` for the request.
3. In the `resultHandler`, inspect `info` for:
   - `PHImageResultIsDegradedKey`
   - `PHImageErrorKey`
   - `PHImageCancelledKey`
4. If `isDegraded == true` AND neither `hasError` nor `isCancelled` is true, return early and await the final high-quality delivery.
5. If `!isDegraded`, OR if an error/cancellation occurred, invoke `continuationGuard.resumeOnce(continuation, returning: image?.cgImage)`.
6. The atomic guard ensures that regardless of how many times or on which background threads PhotoKit calls `resultHandler`, `continuation.resume` is executed **exactly once**.

#### 3. Line-Level Diff
```diff
--- a/SwipeWipe/Sources/SwipeWipeCore/Services/PhotoLibraryService.swift
+++ b/SwipeWipe/Sources/SwipeWipeCore/Services/PhotoLibraryService.swift
@@ -278,6 +278,18 @@
 
     // MARK: - Thumbnail Loading
 
+    private final class ThumbnailContinuationGuard: @unchecked Sendable {
+        private let lock = NSLock()
+        private var didResume = false
+
+        func resumeOnce(_ continuation: CheckedContinuation<CGImage?, Never>, returning image: CGImage?) {
+            lock.lock()
+            defer { lock.unlock() }
+            guard !didResume else { return }
+            didResume = true
+            continuation.resume(returning: image)
+        }
+    }
+
     public func loadThumbnail(for assetId: String, targetSize: CGSize) async throws -> CGImage? {
         #if canImport(Photos)
         let assets = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil)
@@ -288,17 +300,28 @@
         let options = PHImageRequestOptions()
         options.isNetworkAccessAllowed = true
         options.deliveryMode = .highQualityFormat
         options.isSynchronous = false
 
+        let continuationGuard = ThumbnailContinuationGuard()
+
         return await withCheckedContinuation { continuation in
             PHImageManager.default().requestImage(
                 for: phAsset,
                 targetSize: targetSize,
                 contentMode: .aspectFill,
                 options: options
-            ) { image, _ in
+            ) { image, info in
+                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
+                let hasError = info?[PHImageErrorKey] != nil
+                let isCancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
+
+                // If degraded preview is delivered and request is actively pending, wait for final pass
+                if isDegraded && !hasError && !isCancelled {
+                    return
+                }
+
                 #if canImport(UIKit)
-                continuation.resume(returning: image?.cgImage)
+                continuationGuard.resumeOnce(continuation, returning: image?.cgImage)
                 #else
-                continuation.resume(returning: nil)
+                continuationGuard.resumeOnce(continuation, returning: nil)
                 #endif
             }
         }
```

---

### Remediation Item 2: Observer Retain Cycle & Memory Leak Elimination
**Severity**: MAJOR (Memory Leak & Retain Cycle)  
**Target Files**:
- `SwipeWipe/Sources/SwipeWipeCore/Services/MockPhotoProvider.swift` (lines 60, 238–258)
- `SwipeWipe/Sources/SwipeWipeCore/Services/PhotoLibraryService.swift` (lines 28–32, 312–323, 396–405)
- `SwipeWipe/Sources/SwipeWipeCore/Protocols/PhotoLibraryProviding.swift` (lines 51–55)

#### 1. Root Cause
In `LibraryViewModel.swift`:
```swift
public init(photoProvider: PhotoLibraryProviding) {
    self.photoProvider = photoProvider // Strong: LibraryViewModel -> photoProvider
    photoProvider.addObserver(self)
}
```
In `MockPhotoProvider.swift` line 60:
```swift
private var registeredObservers: [PhotoLibraryObserving] = []
```
Because `PhotoLibraryObserving` is an `AnyObject` protocol and `registeredObservers` is a standard Swift array, `MockPhotoProvider` stores strong references to all registered observers. When `LibraryViewModel` registers itself, a strong reference cycle (`LibraryViewModel <---> photoProvider`) is formed. ARC reference count never drops to 0, `LibraryViewModel.deinit` is never invoked, and the entire view model remains permanently allocated in RAM.

#### 2. Exact Remediation
1. In `PhotoLibraryProviding.swift`, define a shared `WeakPhotoLibraryObserver` wrapper:
   ```swift
   public struct WeakPhotoLibraryObserver: @unchecked Sendable {
       public private(set) weak var value: (any PhotoLibraryObserving)?
       public init(_ value: any PhotoLibraryObserving) {
           self.value = value
       }
   }
   ```
2. In `MockPhotoProvider.swift`, update `registeredObservers` from `[PhotoLibraryObserving]` to `[WeakPhotoLibraryObserver]`.
3. In `MockPhotoProvider.addObserver`, `removeObserver`, and `simulateExternalChange`:
   - Mutate the array under `lock`.
   - Remove stale observers (`$0.value == nil`).
   - Append `WeakPhotoLibraryObserver(observer)`.
   - Compact nil references before broadcasting change events.
4. In `PhotoLibraryService.swift`, ensure `observers` uses `WeakPhotoLibraryObserver` (or its internal `WeakObserver`), filtering dead references under lock.

#### 3. Line-Level Diff

##### For `PhotoLibraryProviding.swift`:
```diff
--- a/SwipeWipe/Sources/SwipeWipeCore/Protocols/PhotoLibraryProviding.swift
+++ b/SwipeWipe/Sources/SwipeWipeCore/Protocols/PhotoLibraryProviding.swift
@@ -53,6 +53,16 @@ public protocol PhotoLibraryObserving: AnyObject, Sendable {
     func photoLibraryDidChange()
 }
 
+/// Thread-safe weak reference wrapper for `PhotoLibraryObserving` to prevent retain cycles.
+public struct WeakPhotoLibraryObserver: @unchecked Sendable {
+    public private(set) weak var value: (any PhotoLibraryObserving)?
+
+    public init(_ value: any PhotoLibraryObserving) {
+        self.value = value
+    }
+}
+
 /// Primary abstraction for photo library ingestion, bucketing, clutter analysis, and batch deletion.
```

##### For `MockPhotoProvider.swift`:
```diff
--- a/SwipeWipe/Sources/SwipeWipeCore/Services/MockPhotoProvider.swift
+++ b/SwipeWipe/Sources/SwipeWipeCore/Services/MockPhotoProvider.swift
@@ -59,7 +59,7 @@ public final class MockPhotoProvider: PhotoLibraryProviding, @unchecked Sendable
     public private(set) var openSettingsCallCount: Int = 0
     public private(set) var presentPickerCallCount: Int = 0
-    private var registeredObservers: [PhotoLibraryObserving] = []
+    private var registeredObservers: [WeakPhotoLibraryObserver] = []
 
     public init(status: PhotoAuthorizationStatus = .authorized) {
         self.stubbedAuthorizationStatus = status
@@ -238,20 +238,22 @@ public final class MockPhotoProvider: PhotoLibraryProviding, @unchecked Sendable
     public func addObserver(_ observer: PhotoLibraryObserving) {
         lock.lock()
         defer { lock.unlock() }
-        registeredObservers.append(observer)
+        registeredObservers.removeAll { $0.value == nil || $0.value === observer }
+        registeredObservers.append(WeakPhotoLibraryObserver(observer))
     }
 
     public func removeObserver(_ observer: PhotoLibraryObserving) {
         lock.lock()
         defer { lock.unlock() }
-        registeredObservers.removeAll { $0 === observer }
+        registeredObservers.removeAll { $0.value == nil || $0.value === observer }
     }
 
     public func simulateExternalChange() {
         lock.lock()
-        let currentObservers = registeredObservers
+        registeredObservers.removeAll { $0.value == nil }
+        let currentObservers = registeredObservers.compactMap(\.value)
         lock.unlock()
 
         for observer in currentObservers {
             observer.photoLibraryDidChange()
         }
```

##### For `PhotoLibraryService.swift`:
```diff
--- a/SwipeWipe/Sources/SwipeWipeCore/Services/PhotoLibraryService.swift
+++ b/SwipeWipe/Sources/SwipeWipeCore/Services/PhotoLibraryService.swift
@@ -28,5 +28,2 @@
-    private struct WeakObserver {
-        weak var value: (any PhotoLibraryObserving)?
-    }
-    private var observers: [WeakObserver] = []
+    private var observers: [WeakPhotoLibraryObserver] = []
@@ -315,2 +312,2 @@
-        observers.removeAll { $0.value == nil || $0.value === observer }
-        observers.append(WeakObserver(value: observer))
+        observers.removeAll { $0.value == nil || $0.value === observer }
+        observers.append(WeakPhotoLibraryObserver(observer))
```

---

### Remediation Item 3: Error 3072 User Cancellation Contract Unification
**Severity**: MAJOR (Inter-Milestone Contract Mismatch)  
**Target Files**:
- `SwipeWipe/Sources/SwipeWipeCore/Protocols/PhotoLibraryProviding.swift` (lines 28–49)
- `SwipeWipe/Sources/SwipeWipeCore/Services/PhotoLibraryService.swift` (lines 242–262)
- `SwipeWipe/Sources/SwipeWipeCore/Services/MockPhotoProvider.swift` (lines 209–215)

#### 1. Root Cause
In `MockPhotoProvider.swift:209-214`:
```swift
case .simulateUserCancelled:
    throw NSError(
        domain: "PHPhotosErrorDomain",
        code: 3072,
        userInfo: [NSLocalizedDescriptionKey: "User cancelled system deletion prompt"]
    )
```
In `PhotoLibraryService.swift:242-253`:
```swift
if nsError.domain == "PHPhotosErrorDomain" && nsError.code == 3072 {
    self.logger.notice("User cancelled native PhotoKit deletion modal (Error code 3072).")
    continuation.resume(returning: BatchDeletionResult(
        success: false,
        deletedCount: 0,
        reclaimedBytes: 0,
        failedIdentifiers: ids,
        errorMessage: "User cancelled system deletion prompt"
    ))
}
```
`MockPhotoProvider` throws an `NSError(domain: "PHPhotosErrorDomain", code: 3072)`, whereas `PhotoLibraryService` catches error code 3072 and resumes returning a failure `BatchDeletionResult` without throwing.
In `StagingSafetyTests.swift` (F17) and `tests/verify_suite.py` (`t1_f17_5`), the harness specifically tests that `delete_assets` raises error 3072. When Milestone 3's `NativeBatchDeletionService` is implemented, catching `3072` will work in unit tests against `MockPhotoProvider` but fail on real iOS hardware because `PhotoLibraryService` swallowed the throw.

#### 2. Exact Remediation
1. Update `BatchDeletionResult` in `PhotoLibraryProviding.swift` to include `public let isUserCancelled: Bool = false`, with a backward-compatible default initializer and factory helper `.userCancelled(failedIdentifiers:)`.
2. In `PhotoLibraryService.swift:242-262`, instead of swallowing `nsError` and returning a struct, invoke `continuation.resume(throwing: nsError)`.
   Notice that `deleteAssets(withIdentifiers:)` is already declared `async throws -> BatchDeletionResult` using `withCheckedThrowingContinuation`. Throwing `nsError` ensures that real iOS PhotoKit errors (including `PHPhotosErrorDomain` code `3072`) propagate uniformly to callers.
3. Both `MockPhotoProvider` and `PhotoLibraryService` now share the exact same behavior: when user cancellation occurs, both throw `NSError(domain: "PHPhotosErrorDomain", code: 3072, ...)`.
4. Consumer service (`NativeBatchDeletionService` in M3) can catch `NSError` with code `3072` and map it cleanly to `DeletionOutcome.cancelledByUser`, with 100% parity across mocks and physical devices.

#### 3. Line-Level Diff

##### For `PhotoLibraryProviding.swift`:
```diff
--- a/SwipeWipe/Sources/SwipeWipeCore/Protocols/PhotoLibraryProviding.swift
+++ b/SwipeWipe/Sources/SwipeWipeCore/Protocols/PhotoLibraryProviding.swift
@@ -29,17 +29,32 @@ public enum PhotoAuthorizationStatus: String, Sendable, Codable, CaseIterable {
 public struct BatchDeletionResult: Sendable, Equatable, Codable {
     public let success: Bool
+    public let isUserCancelled: Bool
     public let deletedCount: Int
     public let reclaimedBytes: Int64
     public let failedIdentifiers: [String]
     public let errorMessage: String?
 
     public init(
         success: Bool,
+        isUserCancelled: Bool = false,
         deletedCount: Int,
         reclaimedBytes: Int64,
         failedIdentifiers: [String] = [],
         errorMessage: String? = nil
     ) {
         self.success = success
+        self.isUserCancelled = isUserCancelled
         self.deletedCount = deletedCount
         self.reclaimedBytes = reclaimedBytes
         self.failedIdentifiers = failedIdentifiers
         self.errorMessage = errorMessage
     }
+
+    public static func userCancelled(failedIdentifiers: [String] = []) -> BatchDeletionResult {
+        BatchDeletionResult(
+            success: false,
+            isUserCancelled: true,
+            deletedCount: 0,
+            reclaimedBytes: 0,
+            failedIdentifiers: failedIdentifiers,
+            errorMessage: "User cancelled system deletion prompt"
+        )
+    }
 }
```

##### For `PhotoLibraryService.swift`:
```diff
--- a/SwipeWipe/Sources/SwipeWipeCore/Services/PhotoLibraryService.swift
+++ b/SwipeWipe/Sources/SwipeWipeCore/Services/PhotoLibraryService.swift
@@ -242,22 +242,12 @@ public final class PhotoLibraryService: NSObject, PhotoLibraryProviding, @uncheck
                 } else if let nsError = error as NSError? {
                     // Check for user cancellation error code 3072 (PHPhotosError.userCancelled)
                     if nsError.domain == "PHPhotosErrorDomain" && nsError.code == 3072 {
                         self.logger.notice("User cancelled native PhotoKit deletion modal (Error code 3072).")
-                        continuation.resume(returning: BatchDeletionResult(
-                            success: false,
-                            deletedCount: 0,
-                            reclaimedBytes: 0,
-                            failedIdentifiers: ids,
-                            errorMessage: "User cancelled system deletion prompt"
-                        ))
+                        continuation.resume(throwing: nsError)
                     } else {
                         self.logger.error("PhotoKit batch deletion failed: \(nsError.localizedDescription, privacy: .public)")
-                        continuation.resume(returning: BatchDeletionResult(
-                            success: false,
-                            deletedCount: 0,
-                            reclaimedBytes: 0,
-                            failedIdentifiers: ids,
-                            errorMessage: nsError.localizedDescription
-                        ))
+                        continuation.resume(throwing: nsError)
                     }
                 } else {
-                    continuation.resume(returning: BatchDeletionResult(
-                        success: false,
-                        deletedCount: 0,
-                        reclaimedBytes: 0,
-                        failedIdentifiers: ids,
-                        errorMessage: "Unknown deletion error occurred"
-                    ))
+                    let unknownError = NSError(
+                        domain: "com.swipewipe.PhotoLibraryService",
+                        code: -1,
+                        userInfo: [NSLocalizedDescriptionKey: "Unknown deletion error occurred"]
+                    )
+                    continuation.resume(throwing: unknownError)
                 }
```

---

### Remediation Item 4: Burst Query Predicate Typo Fix
**Severity**: MINOR (Query Optimization & Completeness)  
**Target File**: `SwipeWipe/Sources/SwipeWipeCore/Services/PhotoLibraryService.swift`  
**Target Lines**: 194–198  

#### 1. Root Cause
In `PhotoLibraryService.swift` line 196:
```swift
case .bursts:
    let options = PHFetchOptions()
    options.predicate = NSPredicate(format: "representsBurst == YES")
```
In PhotoKit:
- `representsBurst == YES` matches only the primary representative asset of a burst sequence.
- Individual member shots in a burst have `representsBurst == NO`, but have `burstIdentifier != nil`.
If the query predicate only includes `representsBurst == YES`, PhotoKit returns only 1 photo per burst sequence. When passed downstream to `clutterDetector.detectBurstGroups`, the grouping condition `where group.count >= 2` evaluates to false, causing all bursts to be omitted!
Conversely, querying `representsBurst == YES OR burstIdentifier != nil` fetches all burst candidates so `detectBurstGroups` can cluster them into complete groups.

#### 2. Exact Remediation
Update line 196 of `PhotoLibraryService.swift` to:
`options.predicate = NSPredicate(format: "representsBurst == YES OR burstIdentifier != nil")`

#### 3. Line-Level Diff
```diff
--- a/SwipeWipe/Sources/SwipeWipeCore/Services/PhotoLibraryService.swift
+++ b/SwipeWipe/Sources/SwipeWipeCore/Services/PhotoLibraryService.swift
@@ -194,5 +194,5 @@ public final class PhotoLibraryService: NSObject, PhotoLibraryProviding, @uncheck
         case .bursts:
             let options = PHFetchOptions()
-            options.predicate = NSPredicate(format: "representsBurst == YES")
+            options.predicate = NSPredicate(format: "representsBurst == YES OR burstIdentifier != nil")
             let result = PHAsset.fetchAssets(with: options)
             var models: [PhotoAssetModel] = []
```

---

### Remediation Item 5 (Secondary): `ClutterCluster.init` Primary Asset ID Masking
**Severity**: MINOR (Cluster Staging Semantics)  
**Target File**: `SwipeWipe/Sources/SwipeWipeCore/Models/ClutterCategory.swift`  
**Target Lines**: 60–66, 104  

#### 1. Root Cause
In `ClutterCategory.swift` line 104:
`self.primaryAssetId = primaryAssetId ?? assets.first?.localIdentifier`
When `detectScreenshots` or `detectLargeVideos` creates a cluster, `primaryAssetId: nil` is passed because screenshots do not have a "primary" to retain. The nil-coalescing operator forced the first screenshot to become `primaryAssetId`, causing `duplicateAssetIds` (line 60) to incorrectly flag all remaining screenshots as duplicates.

#### 2. Exact Remediation
1. In `ClutterCluster.init`, change line 104 to `self.primaryAssetId = primaryAssetId`.
2. In `ClutterCluster.duplicateAssetIds`, guard on `category == .duplicates || category == .bursts`. For `.screenshots` and `.largeVideos`, return `[]`.

#### 3. Line-Level Diff
```diff
--- a/SwipeWipe/Sources/SwipeWipeCore/Models/ClutterCategory.swift
+++ b/SwipeWipe/Sources/SwipeWipeCore/Models/ClutterCategory.swift
@@ -60,6 +60,9 @@ public struct ClutterCluster: Identifiable, Sendable, Hashable, Codable {
     /// Assets recommended to stage for deletion.
     public var duplicateAssetIds: [String] {
+        guard category == .duplicates || category == .bursts else {
+            return []
+        }
         guard let primary = primaryAssetId else {
             return assets.dropFirst().map(\.localIdentifier)
         }
@@ -104,2 +107,2 @@ public struct ClutterCluster: Identifiable, Sendable, Hashable, Codable {
-        self.primaryAssetId = primaryAssetId ?? assets.first?.localIdentifier
+        self.primaryAssetId = primaryAssetId
```

---

### Remediation Item 6 (Secondary): Thread-Safe Stored Property in `@unchecked Sendable` Mock
**Severity**: MINOR (Thread Sanitizer Race Prevention)  
**Target File**: `SwipeWipe/Sources/SwipeWipeCore/Services/MockPhotoProvider.swift`  
**Target Lines**: 35–47, 180–190  

#### 1. Root Cause
In `MockPhotoProvider.swift:35`, `public var deletionMode: MockDeletionMode` is an exposed public stored property accessed directly without locking, while `deletionOutcome` is synchronized. Concurrent test executions mutating `deletionMode` while another thread calls `deleteAssetsBatch` trigger data race warnings.

#### 2. Exact Remediation
1. Make the backing property `private var _deletionMode: MockDeletionMode = .automaticSuccess`.
2. Synchronize getter and setter for both `deletionMode` and `deletionOutcome` using `lock`.
3. In `deleteAssets(withIdentifiers:)`, read `_deletionMode` under `lock` into a local constant before switching.

#### 3. Line-Level Diff
```diff
--- a/SwipeWipe/Sources/SwipeWipeCore/Services/MockPhotoProvider.swift
+++ b/SwipeWipe/Sources/SwipeWipeCore/Services/MockPhotoProvider.swift
@@ -34,14 +34,22 @@ public final class MockPhotoProvider: PhotoLibraryProviding, @unchecked Sendable
     public var stubbedClutter: [ClutterCategoryType: [ClutterCluster]] = [:]
-    public var deletionMode: MockDeletionMode = .automaticSuccess
-    public var deletionOutcome: MockDeletionMode {
+    private var _deletionMode: MockDeletionMode = .automaticSuccess
+
+    public var deletionMode: MockDeletionMode {
         get {
             lock.lock()
             defer { lock.unlock() }
-            return deletionMode
+            return _deletionMode
         }
         set {
             lock.lock()
-            deletionMode = newValue
+            _deletionMode = newValue
             lock.unlock()
         }
     }
+    public var deletionOutcome: MockDeletionMode {
+        get { deletionMode }
+        set { deletionMode = newValue }
+    }
@@ -183,3 +191,6 @@ public final class MockPhotoProvider: PhotoLibraryProviding, @unchecked Sendable
     public func deleteAssets(withIdentifiers ids: [String]) async throws -> BatchDeletionResult {
         await applySimulatedLatency()
 
+        lock.lock()
+        let currentMode = _deletionMode
+        lock.unlock()
+
-        switch deletionOutcome {
+        switch currentMode {
```

---

## Verification & Test Plan

1. **Static Analysis & Swift 6 Strict Concurrency Compliance**:
   - Verify `ContinuationOnceGuard` is `@unchecked Sendable` and encapsulates `NSLock`.
   - Verify `WeakPhotoLibraryObserver` prevents strong observer references to `LibraryViewModel`.
   - Verify all protocol signatures in `PhotoLibraryProviding` match `PROJECT.md` interface contracts.

2. **Automated Verification Harness Execution**:
   - Run Milestone 1 verification suite:
     ```powershell
     python c:\Users\jzlwi\Documents\antigravity\magical-bohr\.agents\teamwork\worker_m1_ingestion_0\test_m1_verification.py
     ```
     Requirement: 8/8 tests pass (100%).
   - Run Project E2E verification suite:
     ```powershell
     python c:\Users\jzlwi\Documents\antigravity\magical-bohr\tests\verify_suite.py
     ```
     Requirement: 232/232 test cases pass (100%).
   - Run Headless Harness verification suite:
     ```powershell
     python c:\Users\jzlwi\Documents\antigravity\magical-bohr\SwipeWipe\Tests\HeadlessHarness\verify_suite.py
     ```
     Requirement: 232/232 test cases pass (100%).

3. **Scenario S4 & Error 3072 Invalidation Checks**:
   - Ensure `t1_f17_1` through `t1_f17_5` pass with exit code 0.
   - Verify `mock.delete_assets(["x"])` throws code 3072 when in `.simulateUserCancelled` mode.
   - Verify `PhotoLibraryService.deleteAssets` rethrows `NSError(code: 3072)` when native modal is cancelled.
