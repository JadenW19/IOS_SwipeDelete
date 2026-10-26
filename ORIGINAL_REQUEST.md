# Original User Request

## Initial Request — 2026-10-26T15:36:33Z

The user requested a full multi-agent team to delegate research, frontend, backend, and QA verification job roles to build a clean native iOS rebuild of the SwipeWipe photo management app, targeted for iPhone 14 Pro and iOS 27.0.1+.

Working directory: c:/Users/jzlwi/Documents/antigravity/magical-bohr/SwipeWipe
Integrity mode: development

## Requirements

### R1. Photo Library Chronological & Category Ingestion
The app must ingest photos from the user's camera roll, segmenting the media chronologically by month/year as well as clustering clutter categories (such as screenshots, duplicates, and large videos), while gracefully handling all system privacy permission states.

### R2. High-Performance Card-Swiping Interaction
The app must provide a responsive full-screen card swipe interface optimized for iPhone 14 Pro (120Hz ProMotion display and Dynamic Island layout) with gesture-driven actions: swipe right to keep, swipe left to stage for deletion, immediate undo for accidental swipes, and tactile feedback.

### R3. Non-Destructive Staging & Batch Deletion Safety
The app must stage all marked items in a dedicated review queue without deleting them immediately, showing total space to be reclaimed, and requiring explicit batch user confirmation before executing native system-level deletions via the OS photo framework.

### R4. Automated Verification Suite & Mock Photo Provider
The app must include a self-contained test harness and automated test suite verifying state transitions, swipe queue operations, month bucketing, and deletion confirmation flows without requiring an interactive physical device.

## Acceptance Criteria

### Library & Ingestion
- [ ] Photo asset ingestion handles Authorized, Limited, and Denied permission states without crashing.
- [ ] Assets are bucketed correctly by month and year in chronological order.
- [ ] Clutter detection correctly isolates screenshot and duplicate asset types.

### Swiping & State Machine
- [ ] Swiping right marks an asset as retained and advances the deck.
- [ ] Swiping left stages an asset into the deletion queue and advances the deck.
- [ ] The undo operation reverses the most recent swipe action and restores the asset to the top of the deck.
- [ ] Empty state is displayed when all items in a month/category are processed.

### Safety & Deletion
- [ ] Staged deletion queue accurately reflects the count and estimated file size of pending deletions.
- [ ] Assets in the review queue can be unstaged individually before final commit.
- [ ] Final deletion call invokes the native system confirmation batch operation.

### Programmatic Verification
- [ ] An automated test suite runs with 100% pass rate covering deck stack manipulation, swipe undo history, and batch queue state.
