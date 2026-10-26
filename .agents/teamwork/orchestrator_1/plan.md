# Master Execution Plan: SwipeWipe Native iOS Rebuild

## Target Environment & Stack
- Platform: iOS 27.0.1+
- Device Target: iPhone 14 Pro (120Hz ProMotion display, Dynamic Island)
- Architecture: Modular Swift / SwiftUI / PhotoKit architecture with mock-capable protocol abstractions for 100% headless automated verification.
- Target Directory: `c:\Users\jzlwi\Documents\antigravity\magical-bohr\SwipeWipe`

## Execution Phases

### Phase 0: Survey & Scope Mapping
- Dispatch 3 parallel Explorers / Spec Miners:
  1. `explorer_survey_photo`: Investigate PhotoKit APIs, permissions (Authorized, Limited, Denied), chronological grouping, and clutter clustering (screenshots, duplicates, videos).
  2. `explorer_survey_swipe`: Investigate 120Hz ProMotion gesture card deck swiping, undo stack, tactile haptics, and Dynamic Island layout geometry.
  3. `explorer_survey_safety_test`: Investigate non-destructive staging, batch deletion safety, and self-contained mock photo provider / automated test harness architecture.
- Synthesize findings into `PROJECT.md` and `TEST_INFRA.md`.

### Phase 1: Dual Track Launch
- **Track A (E2E Testing Track)**:
  - E2E Test Suite Orchestrator building Tier 1 (Feature Coverage), Tier 2 (Boundary & Corner Cases), Tier 3 (Cross-Feature Combinations), Tier 4 (Real-World Application Scenarios).
  - Produces `TEST_READY.md`.
- **Track B (Implementation Track)**:
  - Milestone 1: Photo Library Ingestion & Categorization Engine (R1).
  - Milestone 2: Swiping State Machine & Gesture Interaction Engine (R2).
  - Milestone 3: Staging Queue & Batch Deletion Safety Module (R3).
  - Milestone 4: Native SwiftUI Views & Dynamic Island Integration (R2).

### Phase 2: Final Integration & Verification
- Milestone 5 (Final Milestone):
  - Phase 1: Pass 100% of E2E tests (Tiers 1-4).
  - Phase 2: Adversarial Coverage Hardening (Tier 5) with Challengers & Forensic Auditor.

### Phase 3: Delivery & Human Report
- Synthesize all artifacts, audit logs, test execution proofs.
- Deliver comprehensive human-facing report to Parent orchestrator.
