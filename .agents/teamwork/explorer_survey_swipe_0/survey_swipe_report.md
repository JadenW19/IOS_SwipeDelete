# Technical Architecture & Survey Report: Requirement R2 — High-Performance Card-Swiping Interaction

- **Author**: Swiping Interaction Explorer (`explorer_survey_swipe_0`)
- **Date**: 2026-10-26
- **Target Platform**: iOS 27.0.1+ / iPhone 14 Pro (120Hz ProMotion, Dynamic Island)
- **Target Project Directory**: `c:\Users\jzlwi\Documents\antigravity\magical-bohr\SwipeWipe`
- **Integrity Mode**: Read-Only Survey & Technical Architecture

---

## 1. Executive Summary & Problem Scope

Requirement **R2 (High-Performance Card-Swiping Interaction)** specifies a fluid, full-screen card swipe interface optimized for the **iPhone 14 Pro** hardware profile:
- 120Hz ProMotion display with zero-stutter gesture tracking (8.33ms frame budget).
- Dynamic Island hardware cutout and safe area integration (59pt top, 34pt bottom safe area).
- Interactive card deck state machine: swipe right to keep, swipe left to stage for deletion, flick/velocity escape commit, and proportional dynamic rotation.
- Visual stacking depth rendering up to 3 cards with real-time scale and Y-offset interpolation.
- Full LIFO Undo mechanics with reverse spring card entrance animations.
- Coordinated tactile haptics via `UIImpactFeedbackGenerator` and `UINotificationFeedbackGenerator`.
- 100% headless mock capability for automated unit and state machine verification.

This report establishes the complete architectural blueprints, mathematical physics formulas, memory optimization guidelines, and concrete Swift implementation protocols.

---

## 2. Workspace & Existing Repository Analysis

A complete audit of the workspace was conducted:
1. **Workspace Root**: `c:\Users\jzlwi\Documents\antigravity\magical-bohr`
2. **Git Commit History**: Verified commit `779c96b` ("Initial commit") is an empty repository.
3. **Files Present**: Only `.git/`, `.agents/teamwork/`, and `ORIGINAL_REQUEST.md` currently exist.
4. **Target Subdirectory**: `SwipeWipe/` has not yet been populated.
5. **Environment Assessment**: The Windows development host lacks a local native Swift toolchain (`swift : CommandNotFoundException`). Consequently, all Swift architecture must be designed with clean protocol abstractions, mock interfaces, and explicit file boundaries so that automated test suites and downstream implementation subagents can assemble and verify the code deterministically.

---

## 3. 120Hz ProMotion Performance Optimization in SwiftUI

### 3.1 Frame Budget & Hitch Avoidance
- **ProMotion Variable Refresh Rate**: iPhone 14 Pro dynamically scales refresh rate from 10Hz to 120Hz. During active continuous touch tracking, the display pipeline requires consistent **120 frames per second (fps)**.
- **Budget**: Exactly **8.33 ms** per frame. Any main-thread stall (e.g. disk I/O, synchronous image decoding, or heavy SwiftUI view tree invalidation) drops frames and triggers hitching.
- **SwiftUI View Invalidation Isolation**:
  - The deck must **not** re-render all cards on every touch displacement change.
  - The gesture state (`translation: CGSize`) must be encapsulated within the top `InteractiveCardView` or driven via isolated subview bindings.
  - Background cards (Index 1 and Index 2) must only consume normalized progress values `t = clamp(|dx| / threshold, 0...1)` without triggering costly redraws of their interior image content.

### 3.2 Drag Gesture Handling & Physics Tuning
- **Gesture Configuration**:
  `DragGesture(minimumDistance: 0, coordinateSpace: .global)`
- **Velocity Tracking**:
  Utilize `value.velocity` (provided natively by SwiftUI `DragGesture.Value`). If the user executes a fast flick, the card must commit even if the drag distance hasn't crossed the static distance threshold.
- **Spring Animation Parameters**:
  - **Commit / Exit Animation** (flying off screen):
    `Animation.spring(response: 0.36, dampingFraction: 0.82, blendDuration: 0)`
    Preserves user throw momentum by injecting initial touch release velocity (`velocity.width`).
  - **Rebound / Snapback Animation** (returning to center when release is below threshold):
    `Animation.spring(response: 0.32, dampingFraction: 0.68, blendDuration: 0)`
    A damping fraction of `0.68` produces a slight, natural elastic overshoot before resting at `(0, 0)`.
  - **Undo Reverse Animation** (card returning from offscreen to top of deck):
    `Animation.spring(response: 0.40, dampingFraction: 0.78, blendDuration: 0)`

### 3.3 Eliminating Off-Screen GPU Rendering Bottlenecks
To guarantee 120Hz rasterization on the Apple A16 Bionic GPU:
1. **Continuous Corner Clipping**:
   - Use `.clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))` with pre-clipped content. Continuous curvature conforms to Apple hardware squircle standards and leverages hardware fast-paths.
2. **Shadow Optimization**:
   - Avoid applying dynamic blur shadows directly to moving cards during 120Hz drag.
   - Instead, place a static underlying shadow shape or use `.shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 5)` with a pre-baked background geometry.
3. **Avoid `.drawingGroup()`**:
   - Using Metal rasterization (`.drawingGroup()`) on high-resolution image views causes per-frame texture upload latency. Native CoreAnimation layer rendering performs better for image transforms.
4. **Image Downsampling & Caching Pipeline**:
   - Never render full camera sensor assets (e.g. 48MP ProRAW or 12MP HEIC photos = 4000x3000 to 8000x6000 pixels).
   - Downsample images during ingestion / background preloading to the exact display point size at 3x scale:
     - Target size: `393 pt * 3 = 1179 px` width by `540 pt * 3 = 1620 px` height.
     - Decode using `CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceCreateThumbnailWithTransform: true` and `kCGImageSourceThumbnailMaxPixelSize: 1620`.
   - Sliding 3-Card Preload Window:
     - **Index 0 (Active Top Card)**: High-resolution downsampled bitmap pre-loaded into memory.
     - **Index 1 (Next Card)**: High-resolution downsampled bitmap pre-loaded into memory.
     - **Index 2 (Upcoming Card)**: Fast low-resolution thumbnail pre-warmed.
     - **Index 3+**: Identifiers only; zero texture allocation.

---

## 4. iPhone 14 Pro Hardware Specifics & Dynamic Island Integration

### 4.1 Screen & Cutout Geometry
| Parameter | Measurement (Points) | Native Pixels (@3x) | Notes |
| :--- | :--- | :--- | :--- |
| **Screen Width** | `393 pt` | `1179 px` | Logical screen width |
| **Screen Height** | `852 pt` | `2556 px` | Logical screen height |
| **Dynamic Island Width** | `126 pt` | `378 px` | Pill cutout width |
| **Dynamic Island Height** | `36.67 pt` | `110 px` | Pill cutout height |
| **Dynamic Island Top Margin** | `11 pt` | `33 px` | From top glass bezel |
| **Dynamic Island Bottom Y** | `47.67 pt` | `143 px` | Lowest edge of island cutout |
| **Top Safe Area Inset** | `59 pt` | `177 px` | Guarantees clear clearance below Dynamic Island |
| **Bottom Safe Area Inset**| `34 pt` | `102 px` | Home indicator safety margin |
| **Usable Vertical Canvas** | `759 pt` | `2277 px` | `852 - 59 - 34` |

### 4.2 Compact Status Presentation
- **Header Bar**:
  - Placed immediately below the 59pt top safe area (`padding(.top, 8)`).
  - Left: Chronological bucket title (e.g. `"October 2026"` in `.headline.weight(.bold)`).
  - Center: Deck progress indicator (`"38 / 142"` in `.subheadline.monospacedDigit()`).
  - Right: Live Staged Deletion Pill (`"🗑️ 18 · 340 MB"` with accent color `Color.red.opacity(0.15)` and red foreground, signaling reclaimable storage in real time).
- **Control Bar**:
  - Sits directly above the 34pt bottom safe area.
  - Left: Undo button (rotational arrow icon, disabled when undo stack empty).
  - Center-Left: Delete button (red tint, executes stage deletion).
  - Center-Right: Keep button (green tint, executes retain action).
  - Right: Review Staged Deletions action.

---

## 5. Card Deck State Machine & Stacking Physics

### 5.1 Card Deck State Machine
The interaction lifecycle is modeled as a deterministic finite state machine (FSM):
- `.idle`: Deck at rest, waiting for touch input.
- `.dragging(translation, progress, direction)`: Real-time interactive drag tracking.
- `.animatingCommit(direction)`: Card flying off-screen towards right (`.keep`) or left (`.stageDelete`).
- `.animatingUndo(action)`: Card flying in from off-screen back to index 0.
- `.empty(reviewedCount, stagedCount, stagedBytes)`: All items in bucket processed.

### 5.2 Mathematical Physics & Gesture Thresholds
1. **Commit Distance Cutoff ($X_{threshold}$)**:
   - Screen width $W = 393\text{ pt}$.
   - Distance threshold: $35\%$ of screen width:
     $$X_{threshold} = 393 \times 0.35 \approx 137.5\text{ pt}$$
2. **Velocity Escape Threshold ($V_{threshold}$)**:
   - Touch release velocity cutoff: $V_{threshold} = 800\text{ pt/s}$.
   - If $|v_x| \ge 800\text{ pt/s}$ AND $\text{sign}(v_x) == \text{sign}(dx)$ with minimum translation $|dx| \ge 35\text{ pt}$, trigger commit immediately.
3. **Commit Rule**:
   $$\text{Commit} = (|dx| \ge 137.5\text{ pt}) \lor \left(|v_x| \ge 800\text{ pt/s} \land \text{sign}(v_x) \cdot dx > 35\text{ pt}\right)$$
4. **Dynamic Rotation Angle**:
   - The card tilts organically around a bottom pivot point (`UnitPoint(x: 0.5, y: 0.9)`):
     $$\theta = \left(\frac{dx}{W}\right) \times \theta_{max}$$
   - Where $\theta_{max} = 20^\circ$ ($0.349\text{ radians}$).
   - Swiping right produces clockwise rotation ($+20^\circ$ max); swiping left produces counter-clockwise rotation ($-20^\circ$ max).
5. **Real-time Badge Opacity & Tint Interpolation**:
   - Normalized progress: $p = \text{clamp}\left(\frac{|dx|}{X_{threshold}}, 0.0, 1.0\right)$.
   - Right swipe ($dx > 0$): `"KEEP"` badge opacity $p$, green ambient border overlay.
   - Left swipe ($dx < 0$): `"DELETE"` badge opacity $p$, red ambient border overlay.

### 5.3 3-Card Visual Depth Interpolation
Only the top 3 cards are rendered in the visual hierarchy:
- **Card 0 (Top / Active)**:
  - $Offset = (dx, dy \times 0.25)$ (dampened vertical drag).
  - $Rotation = \theta$.
  - $Scale = 1.0$, $ZIndex = 3$.
- **Card 1 (Next in Stack)**:
  - At rest ($dx = 0$): $Y_1 = +14\text{ pt}$, $Scale_1 = 0.94$, $Opacity_1 = 0.90$, $ZIndex = 2$.
  - When dragging Card 0 ($p = \text{clamp}(|dx| / X_{threshold}, 0, 1)$):
    $$Y_1(p) = 14 \cdot (1 - p)$$
    $$Scale_1(p) = 0.94 + 0.06 \cdot p$$
    $$Opacity_1(p) = 0.90 + 0.10 \cdot p$$
- **Card 2 (Bottom in Stack)**:
  - At rest ($dx = 0$): $Y_2 = +26\text{ pt}$, $Scale_2 = 0.88$, $Opacity_2 = 0.70$, $ZIndex = 1$.
  - When dragging Card 0:
    $$Y_2(p) = 26 - 12 \cdot p$$
    $$Scale_2(p) = 0.88 + 0.06 \cdot p$$
    $$Opacity_2(p) = 0.70 + 0.20 \cdot p$$

---

## 6. Undo Mechanics & Reverse Animation Physics

### 6.1 LIFO Undo Stack Data Structure
```swift
public struct SwipeAction: Identifiable, Codable, Equatable {
    public let id: UUID
    public let assetId: String
    public let direction: SwipeDirection   // .keep or .stageDelete
    public let timestamp: Date
    public let bucketId: String
    public let estimatedSizeBytes: Int64
}
```

### 6.2 Undo Execution Lifecycle
1. **Validation**: Check `undoStack.isEmpty == false`. If empty, trigger warning haptic and no-op.
2. **Pop Action**: `let lastAction = undoStack.removeLast()`.
3. **State Reversal**:
   - If `lastAction.direction == .stageDelete`: remove from `stagedDeletionAssets`.
   - If `lastAction.direction == .keep`: remove from `retainedAssets`.
4. **Re-insertion into Deck**: Insert asset at `index 0` of active deck cards.
5. **Reverse Entrance Animation**:
   - Position card offscreen: $+490\text{ pt}$ if previously kept, $-490\text{ pt}$ if previously deleted.
   - Spring animate back to center `(0, 0)` with `.spring(response: 0.38, dampingFraction: 0.76)`.
   - Cards below animate down in sync.

---

## 7. Tactile & Haptic Feedback System

### 7.1 Sensory Coordination Matrix
| Event | Generator Class | Style / Type | Condition & Debouncing |
| :--- | :--- | :--- | :--- |
| **Cross Commit Threshold** | `UIImpactFeedbackGenerator` | `.light` | Fired once when $|dx| \ge X_{threshold}$. Debounced via boolean. |
| **Commit Keep (Right)** | `UIImpactFeedbackGenerator` | `.medium` | Fired upon touch release when commit right criteria is met. |
| **Commit Stage Delete (Left)**| `UIImpactFeedbackGenerator` | `.rigid` / `.heavy` | Fired upon touch release when commit left criteria is met. |
| **Undo Executed** | `UIImpactFeedbackGenerator` | `.medium` | Fired when undo action pops and card flies back onto deck. |
| **Batch Deletion Complete** | `UINotificationFeedbackGenerator` | `.success` | Fired upon completing permanent batch deletion. |
| **Invalid Action / Empty Undo**| `UINotificationFeedbackGenerator` | `.warning` | Fired if user taps Undo with empty history. |

### 7.2 Headless-Safe Haptic Protocol
```swift
public protocol HapticFeedbackServiceProtocol: AnyObject {
    func prepare()
    func triggerThresholdCrossed()
    func triggerCommit(direction: SwipeDirection)
    func triggerUndo()
    func triggerSuccess()
    func triggerWarning()
}
```
- Production uses UIKit generators wrapped in `CoreHapticsService`.
- Unit tests use `MockHapticFeedbackService` recording `[HapticEvent]` for automated assertions.

---

## 8. Concrete Architecture & File Organization

The following modular Swift layout is specified for `SwipeWipe/`:
```
SwipeWipe/
├── Core/
│   ├── Haptics/
│   │   ├── HapticFeedbackServiceProtocol.swift
│   │   ├── CoreHapticsService.swift
│   │   └── MockHapticFeedbackService.swift
│   ├── Layout/
│   │   └── DeviceGeometry.swift       // iPhone 14 Pro constants (393x852, Dynamic Island)
│   └── Performance/
│       └── ImageDownsampler.swift     // Downsampled CGImageSource pipeline
├── Models/
│   ├── PhotoCardModel.swift           // ID, thumbnail, dimensions, byte size, date
│   ├── SwipeDirection.swift           // .keep, .stageDelete
│   ├── SwipeAction.swift              // LIFO undo history entity
│   └── CardDeckState.swift            // State machine enum
├── ViewModels/
│   ├── CardDeckViewModel.swift        // Deck FSM, gesture math, sliding window, undo
│   └── CardDeckViewModelProtocol.swift// Protocol for headless testability
└── Views/
    ├── CardDeckView.swift             // Top-level container, 3-card stack, gestures
    ├── CardView.swift                 // Card presentation with continuous squircle corners
    ├── CardOverlayBadgeView.swift     // KEEP / DELETE dynamic stamps
    ├── DynamicIslandHeaderView.swift  // Header below 59pt safe area
    ├── DeckBottomBarView.swift        // Undo, quick action buttons, staged count
    └── DeckEmptyView.swift            // Completion summary & review call to action
```

---

## 9. Verification & Automated Test Strategy

The architecture supports 100% headless testability:
1. **Swipe Right (Keep)**: Advances deck, populates `retainedAssets`, records action in `undoStack`, fires `.commit(.keep)` haptic.
2. **Swipe Left (Stage Deletion)**: Advances deck, populates `stagedDeletionAssets`, updates byte counters, records in `undoStack`, fires `.commit(.stageDelete)` haptic.
3. **Threshold and Velocity**: Commit triggers when $|dx| \ge 137.5\text{ pt}$ OR $(|v_x| \ge 800\text{ pt/s} \land |dx| \ge 35\text{ pt})$; rebounds otherwise.
4. **LIFO Undo Stack**: Multi-level undo correctly restores card stack in reverse chronological order and reverts deletion queue counters.
5. **Empty State Transition**: Transition to `.empty` occurs when last card is processed, triggering `.success` feedback.
