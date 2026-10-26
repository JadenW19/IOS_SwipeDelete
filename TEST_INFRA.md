# E2E Test Infra: SwipeWipe Native iOS Rebuild

## Test Philosophy
- **Requirement-Driven & Opaque-Box**: Derived strictly from `ORIGINAL_REQUEST.md` (R1-R4) and user specifications.
- **Methodology**: Systematic 4-tier testing hierarchy (Category-Partition, Boundary Value Analysis, Pairwise Combinatorial, Real-World Workloads).
- **Environment Agnostic**: Full automated verification runner (`tests/verify_suite.py`) executing headlessly on the host (Python 3.13) paired with native Swift XCTest suites for macOS/Xcode.

---

## Feature Inventory & Test Mapping

| # | Feature | Source | Tier 1 (Coverage) | Tier 2 (Boundary) | Tier 3 (Pairwise) |
|---|---------|--------|:-----------------:|:-----------------:|:-----------------:|
| F1 | PhotoKit Permission Handling | R1 | 5 test cases | 5 test cases | ✓ |
| F2 | Asset Ingestion & Performance | R1 | 5 test cases | 5 test cases | ✓ |
| F3 | Chronological Monthly Bucketing | R1 | 5 test cases | 5 test cases | ✓ |
| F4 | Clutter: Screenshot Detection | R1 | 5 test cases | 5 test cases | ✓ |
| F5 | Clutter: Duplicate & Burst Clustering | R1 | 5 test cases | 5 test cases | ✓ |
| F6 | Clutter: Large Video Filtering | R1 | 5 test cases | 5 test cases | ✓ |
| F7 | Mock Photo Provider Protocol | R1, R4 | 5 test cases | 5 test cases | ✓ |
| F8 | ProMotion 120Hz Gesture Budget | R2 | 5 test cases | 5 test cases | ✓ |
| F9 | Card Deck Stacking & Visual Depth | R2 | 5 test cases | 5 test cases | ✓ |
| F10 | Bi-Directional Decision Engine (Retain / Delete) | R2 | 5 test cases | 5 test cases | ✓ |
| F11 | Dynamic Rotation Physics | R2 | 5 test cases | 5 test cases | ✓ |
| F12 | LIFO Undo Stack & State Recovery | R2 | 5 test cases | 5 test cases | ✓ |
| F13 | Tactile Haptic System | R2 | 5 test cases | 5 test cases | ✓ |
| F14 | Thread-Safe Staged Queue Store | R3 | 5 test cases | 5 test cases | ✓ |
| F15 | Non-Destructive Review & Space Display | R3 | 5 test cases | 5 test cases | ✓ |
| F16 | Native Batch Deletion Bridge | R3 | 5 test cases | 5 test cases | ✓ |
| F17 | System Error 3072 Cancellation Safety | R3 | 5 test cases | 5 test cases | ✓ |
| F18 | Favorite Asset Safeguards | R3 | 5 test cases | 5 test cases | ✓ |
| F19 | Dynamic Island & Screen Safe Areas | R2 | 5 test cases | 5 test cases | ✓ |
| F20 | Empty State & Completion Transitions | R2 | 5 test cases | 5 test cases | ✓ |

Total identified features: 20  
Minimum threshold calculations:
- Tier 1: $20 \times 5 = 100$ test cases minimum.
- Tier 2: $20 \times 5 = 100$ test cases minimum.
- Tier 3: $\ge 20$ pairwise combination test cases.
- Tier 4: $\max(5, 20/2) = 10$ real-world application workload scenarios.
- Total Target: $> 230$ automated test cases.

---

## Real-World Application Scenarios (Tier 4)
| # | Scenario | Features Exercised | Complexity |
|---|----------|--------------------|------------|
| S1 | End-to-End Camera Roll Ingestion (50,000 photos, 36 months) | F1, F2, F3 | High |
| S2 | High-Speed 120Hz ProMotion Cleaning Marathon (100 rapid swipes, 20 undos) | F8, F9, F10, F11, F12, F13 | High |
| S3 | Heavy Clutter Purge (1,000 screenshots + 500 burst duplicates + 20GB large videos) | F4, F5, F6, F14, F15 | High |
| S4 | System Deletion Cancellation Recovery (User taps "Cancel" / error 3072 on native prompt) | F16, F17, F14, F15 | High |
| S5 | Review Queue Granular Unstaging & Selective Batch Commit | F14, F15, F16 | Medium |
| S6 | Dynamic Permission Downgrade Mid-Session (Authorized -> Limited / Denied) | F1, F2, F3, F7 | High |
| S7 | Favorite Photo Protection during Deletion Sweep | F18, F14, F16 | Medium |
| S8 | Complete Month Clearance to Empty State Celebration | F10, F20 | Medium |
| S9 | Out-of-Order Undo across Multiple Buckets | F3, F10, F12, F14 | High |
| S10 | Zero-Byte & Corrupted Asset Handling in Ingestion & Deletion | F2, F14, F15, F16 | Medium |

---

## Test Architecture
- **Headless Test Runner**:
  - Invocation: `python tests/verify_suite.py`
  - Output: Structured TAP/JUnit test summary reporting 100% pass rate, zero regressions, and exit code 0.
- **Native XCTest Runner**:
  - Directory: `SwipeWipe/Tests/SwipeWipeCoreTests/`
  - Targets: `IngestionTests`, `SwipingDeckTests`, `StagingSafetyTests`, `IntegrationFlowTests`.
- **Completion Signal**:
  - Publication of `TEST_READY.md` at project root with test coverage breakdown and execution commands.
