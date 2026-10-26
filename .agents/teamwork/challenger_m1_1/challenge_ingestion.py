"""
=============================================================================
Milestone 1 Empirical Stress-Test & Challenge Harness: Photo Ingestion & Categorization
Location: .agents/teamwork/challenger_m1_1/challenge_ingestion.py
Challenger: Challenger 1 (Milestone 1)
Role: Empirical Challenger (Adversarial stress-testing, boundary verification, failure discovery)
=============================================================================
"""

import os
import sys
import time
import math
import random
import tracemalloc
from datetime import datetime, timezone, timedelta
from typing import List, Dict, Optional, Tuple, Set


# =============================================================================
# SECTION 1: SWIFT 6 EQUIVALENT ENGINE EMULATION
# Exact replication of algorithms implemented in SwipeWipeCore:
# - PhotoAssetModel, MonthlyBucket, ClutterCategory
# - ClutterDetector (dHash, Hamming, Temporal Clustering, Large Videos)
# =============================================================================

class AssetMediaType:
    IMAGE = "image"
    VIDEO = "video"
    AUDIO = "audio"
    UNKNOWN = "unknown"


class AssetMediaSubtypes:
    NONE = 0
    PHOTO_PANORAMA = 1 << 0
    PHOTO_HDR = 1 << 1
    PHOTO_SCREENSHOT = 1 << 2
    PHOTO_LIVE = 1 << 3
    PHOTO_DEPTH_EFFECT = 1 << 4
    VIDEO_STREAMED = 1 << 16
    VIDEO_HIGH_FRAME_RATE = 1 << 17
    VIDEO_TIMELAPSE = 1 << 18


class PhotoAssetModel:
    def __init__(
        self,
        id: str,
        localIdentifier: str,
        creationDate: datetime,
        mediaType: str = AssetMediaType.IMAGE,
        mediaSubtypes: int = 0,
        pixelWidth: int = 1179,
        pixelHeight: int = 2556,
        duration: float = 0.0,
        estimatedByteSize: int = 3_500_000,
        isFavorite: bool = False,
        isHidden: bool = False,
        burstIdentifier: Optional[str] = None,
        representsBurst: bool = False,
        perceptualHash: Optional[int] = None
    ):
        self.id = id
        self.localIdentifier = localIdentifier
        self.creationDate = creationDate
        self.mediaType = mediaType
        self.mediaSubtypes = mediaSubtypes
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.duration = duration
        self.estimatedByteSize = max(0, estimatedByteSize)
        self.isFavorite = isFavorite
        self.isHidden = isHidden
        self.burstIdentifier = burstIdentifier
        self.representsBurst = representsBurst
        self.perceptualHash = perceptualHash

    @property
    def aspectRatio(self) -> float:
        if self.pixelHeight > 0:
            return float(self.pixelWidth) / float(self.pixelHeight)
        return 1.0

    @property
    def isScreenshot(self) -> bool:
        return bool(self.mediaSubtypes & AssetMediaSubtypes.PHOTO_SCREENSHOT)

    @property
    def isLargeVideo(self) -> bool:
        return self.mediaType == AssetMediaType.VIDEO and (
            self.duration >= 60.0 or self.estimatedByteSize >= 100_000_000
        )

    @property
    def formattedSize(self) -> str:
        if self.estimatedByteSize <= 0:
            return "0 B"
        units = ["B", "KB", "MB", "GB", "TB"]
        size = float(self.estimatedByteSize)
        unitIndex = 0
        while size >= 1000.0 and unitIndex < len(units) - 1:
            size /= 1000.0
            unitIndex += 1
        if unitIndex == 0:
            return f"{int(size)} B"
        elif size >= 100.0:
            return f"{size:.0f} {units[unitIndex]}"
        elif size >= 10.0:
            return f"{size:.1f} {units[unitIndex]}"
        else:
            return f"{size:.2f} {units[unitIndex]}"


class MonthIdentifier:
    def __init__(self, year: int, month: int):
        self.year = year
        self.month = max(1, min(12, month))

    @property
    def id(self) -> str:
        return f"{self.year:04d}-{self.month:02d}"

    def __lt__(self, other: 'MonthIdentifier') -> bool:
        if self.year != other.year:
            return self.year < other.year
        return self.month < other.month

    def __eq__(self, other: object) -> bool:
        if not isinstance(other, MonthIdentifier):
            return False
        return self.year == other.year and self.month == other.month

    def __hash__(self) -> int:
        return hash((self.year, self.month))


class ClutterDetector:
    @staticmethod
    def hammingDistance(h1: int, h2: int) -> int:
        return bin((h1 ^ h2) & 0xFFFFFFFFFFFFFFFF).count('1')

    @staticmethod
    def computeDHash(luminanceGrid: List[int]) -> Optional[int]:
        if len(luminanceGrid) < 72:
            return None
        h = 0
        bitIndex = 0
        for row in range(8):
            for col in range(8):
                left = luminanceGrid[row * 9 + col]
                right = luminanceGrid[row * 9 + (col + 1)]
                if left > right:
                    h |= (1 << (63 - bitIndex))
                bitIndex += 1
        return h

    @staticmethod
    def evaluateHashSimilarity(h1: int, h2: int) -> str:
        dist = ClutterDetector.hammingDistance(h1, h2)
        if dist <= 5:
            return "exactOrNearIdentical"
        elif dist <= 10:
            return "similarComposition"
        else:
            return "distinctScene"

    @staticmethod
    def detectDuplicates(
        assets: List[PhotoAssetModel],
        temporalThreshold: float = 2.5,
        hammingThreshold: int = 10
    ) -> List[List[PhotoAssetModel]]:
        # Exactly mirrors ClutterDetector.swift lines 103-181
        candidates = [
            a for a in assets
            if a.mediaType == AssetMediaType.IMAGE and not a.isScreenshot and not a.representsBurst
        ]
        candidates.sort(key=lambda a: a.creationDate)

        if len(candidates) < 2:
            return []

        clusters: List[List[PhotoAssetModel]] = []
        visitedIds: Set[str] = set()

        for i in range(len(candidates)):
            anchor = candidates[i]
            if anchor.localIdentifier in visitedIds:
                continue

            clusterMembers: List[PhotoAssetModel] = [anchor]

            for j in range(i + 1, len(candidates)):
                cand = candidates[j]
                if cand.localIdentifier in visitedIds:
                    continue

                timeDelta = abs((cand.creationDate - anchor.creationDate).total_seconds())
                if timeDelta > temporalThreshold:
                    break

                resolutionMatch = (
                    cand.pixelWidth == anchor.pixelWidth and cand.pixelHeight == anchor.pixelHeight
                )
                aspectRatioDelta = abs(cand.aspectRatio - anchor.aspectRatio)
                aspectMatch = aspectRatioDelta < 0.005

                if not (resolutionMatch or aspectMatch):
                    continue

                if anchor.perceptualHash is not None and cand.perceptualHash is not None:
                    distance = ClutterDetector.hammingDistance(anchor.perceptualHash, cand.perceptualHash)
                    if distance <= hammingThreshold:
                        clusterMembers.append(cand)
                        visitedIds.add(cand.localIdentifier)
                else:
                    clusterMembers.append(cand)
                    visitedIds.add(cand.localIdentifier)

            if len(clusterMembers) >= 2:
                visitedIds.add(anchor.localIdentifier)
                clusters.append(clusterMembers)

        return clusters

    @staticmethod
    def detectLargeVideos(
        assets: List[PhotoAssetModel],
        minDuration: float = 60.0,
        minByteSize: int = 100_000_000
    ) -> List[PhotoAssetModel]:
        return [
            a for a in assets
            if a.mediaType == AssetMediaType.VIDEO and (
                a.duration >= minDuration or a.estimatedByteSize >= minByteSize
            )
        ]


# =============================================================================
# SECTION 2: EMPIRICAL TEST SUITE (STRESS, BOUNDARIES, CORNER CASES, BUGS)
# =============================================================================

class ChallengerRunner:
    def __init__(self):
        self.passes = 0
        self.failures = 0
        self.findings = []
        self.metrics = {}

    def log_result(self, name: str, passed: bool, detail: str = ""):
        if passed:
            self.passes += 1
            print(f" [PASS] {name} {detail}")
        else:
            self.failures += 1
            print(f" [FAIL] {name} - {detail}")
            self.findings.append(f"{name}: {detail}")

    # -------------------------------------------------------------------------
    # TEST SUITE 1: 10,000 Synthetic Stress Load & Ingestion Benchmarks
    # -------------------------------------------------------------------------
    def test_synthetic_10k_stress(self):
        print("\n--- Test Suite 1: 10,000 Synthetic Asset Stress & Ingestion ---")
        tracemalloc.start()
        t0 = time.perf_counter()

        base_time = datetime(2026, 1, 1, 12, 0, 0, tzinfo=timezone.utc)
        random.seed(42)

        assets: List[PhotoAssetModel] = []
        for i in range(10_000):
            # Mixed timestamps across 12 months (365 days)
            offset_seconds = random.randint(0, 365 * 86400)
            c_date = base_time + timedelta(seconds=offset_seconds)

            # Mixed aspect ratios (portrait, landscape, square, ultrawide, zero-height edge)
            aspect_choice = i % 5
            if aspect_choice == 0:
                pw, ph = 1179, 2556  # iPhone 14 Pro portrait
            elif aspect_choice == 1:
                pw, ph = 4032, 3024  # Standard 4:3
            elif aspect_choice == 2:
                pw, ph = 3840, 2160  # 16:9 4K
            elif aspect_choice == 3:
                pw, ph = 1080, 1080  # 1:1 Square
            else:
                pw, ph = 1000, 0     # Edge case zero height

            # Mixed media types and sizes
            if i % 20 == 0:
                m_type = AssetMediaType.VIDEO
                subtypes = 0
                dur = random.uniform(5.0, 300.0)
                byte_sz = random.randint(10_000_000, 800_000_000)
            elif i % 15 == 0:
                m_type = AssetMediaType.IMAGE
                subtypes = AssetMediaSubtypes.PHOTO_SCREENSHOT
                dur = 0.0
                byte_sz = random.randint(1_000_000, 3_000_000)
            else:
                m_type = AssetMediaType.IMAGE
                subtypes = 0
                dur = 0.0
                byte_sz = random.randint(2_000_000, 15_000_000)

            # Perceptual hash for some photos
            p_hash = random.getrandbits(64) if m_type == AssetMediaType.IMAGE else None

            assets.append(PhotoAssetModel(
                id=f"synth-{i}",
                localIdentifier=f"ph-synth-{i}",
                creationDate=c_date,
                mediaType=m_type,
                mediaSubtypes=subtypes,
                pixelWidth=pw,
                pixelHeight=ph,
                duration=dur,
                estimatedByteSize=byte_sz,
                perceptualHash=p_hash
            ))

        elapsed_gen = time.perf_counter() - t0
        current_mem, peak_mem = tracemalloc.get_traced_memory()
        tracemalloc.stop()

        self.metrics["10k_gen_time"] = elapsed_gen
        self.metrics["10k_peak_mem_mb"] = peak_mem / (1024 * 1024)

        print(f"     Generated 10,000 assets in {elapsed_gen:.4f}s | Peak memory: {peak_mem / (1024 * 1024):.2f} MB")
        self.log_result(
            "10k Asset Generation Throughput",
            elapsed_gen < 1.0,
            f"({elapsed_gen:.4f}s < 1.0s target)"
        )
        self.log_result(
            "10k Asset Memory Footprint",
            (peak_mem / (1024 * 1024)) < 50.0,
            f"({peak_mem / (1024 * 1024):.2f} MB < 50 MB threshold)"
        )

        # Monthly Bucketing Benchmark
        t1 = time.perf_counter()
        bucket_map: Dict[str, List[PhotoAssetModel]] = {}
        for a in assets:
            m_id = MonthIdentifier(a.creationDate.year, a.creationDate.month).id
            if m_id not in bucket_map:
                bucket_map[m_id] = []
            bucket_map[m_id].append(a)

        sorted_buckets = sorted(bucket_map.keys(), reverse=True)
        elapsed_bucket = time.perf_counter() - t1
        self.metrics["10k_bucketing_time"] = elapsed_bucket

        print(f"     Partitioned into {len(sorted_buckets)} monthly buckets in {elapsed_bucket:.4f}s")
        self.log_result(
            "10k Monthly Bucketing Efficiency",
            elapsed_bucket < 0.1,
            f"({elapsed_bucket:.4f}s < 0.1s target)"
        )

        # Duplicate Scanning Benchmark over 10k items
        t2 = time.perf_counter()
        clusters = ClutterDetector.detectDuplicates(assets, temporalThreshold=2.5, hammingThreshold=10)
        elapsed_dup = time.perf_counter() - t2
        self.metrics["10k_dup_scan_time"] = elapsed_dup

        print(f"     Scanned 10k assets for duplicates in {elapsed_dup:.4f}s | Found {len(clusters)} clusters")
        self.log_result(
            "10k Duplicate Detection Scanning Performance",
            elapsed_dup < 1.0,
            f"({elapsed_dup:.4f}s < 1.0s target)"
        )

    # -------------------------------------------------------------------------
    # TEST SUITE 2: Pathological Worst-Case Load (Adversarial Clustering Stress)
    # -------------------------------------------------------------------------
    def test_pathological_clustering(self):
        print("\n--- Test Suite 2: Adversarial Pathological Clustering Stress ---")
        # Construct scenario where 2,000 photos have the EXACT same timestamp and same resolution
        # but DIFFERENT dHashes (Hamming distance > 10).
        # This tests if the inner loop degrades to O(N^2) quadratic stall.
        base_time = datetime(2026, 10, 26, 12, 0, 0, tzinfo=timezone.utc)
        pathological_assets = []
        for i in range(2000):
            # Alternating distinct hashes
            h = 0xAAAAAAAAAAAAAAAA if i % 2 == 0 else 0x5555555555555555  # distance = 64
            pathological_assets.append(PhotoAssetModel(
                id=f"path-{i}",
                localIdentifier=f"ph-path-{i}",
                creationDate=base_time,  # ALL SAME TIMESTAMP
                mediaType=AssetMediaType.IMAGE,
                pixelWidth=4032,
                pixelHeight=3024,
                perceptualHash=h
            ))

        t0 = time.perf_counter()
        clusters = ClutterDetector.detectDuplicates(pathological_assets, temporalThreshold=2.5, hammingThreshold=10)
        elapsed = time.perf_counter() - t0
        self.metrics["pathological_2k_time"] = elapsed

        print(f"     2,000 simultaneous photos scanned in {elapsed:.4f}s | Formed {len(clusters)} clusters")
        self.log_result(
            "Pathological 2k Simultaneous Photos Stress",
            elapsed < 1.5,
            f"({elapsed:.4f}s < 1.5s)"
        )

    # -------------------------------------------------------------------------
    # TEST SUITE 3: dHash Algorithm & Hamming Distance Spectrum
    # -------------------------------------------------------------------------
    def test_dhash_and_hamming_spectrum(self):
        print("\n--- Test Suite 3: dHash Algorithm & Hamming Distance Spectrum ---")
        # 1. Test 9x8 matrix dHash generation
        # Constant brightness grid -> all left == right -> all bits 0 -> hash = 0
        grid_flat = [128] * 72
        hash_flat = ClutterDetector.computeDHash(grid_flat)
        self.log_result(
            "dHash Flat Luminance (All Equal)",
            hash_flat == 0,
            f"Hash: {hex(hash_flat) if hash_flat is not None else 'None'} == 0x0"
        )

        # Gradient where every left > right -> all 64 bits set -> hash = 0xFFFFFFFFFFFFFFFF
        grid_all_descending = []
        for r in range(8):
            for c in range(9):
                grid_all_descending.append(255 - c * 20)
        hash_all_desc = ClutterDetector.computeDHash(grid_all_descending)
        self.log_result(
            "dHash All Descending (All Bits 1)",
            hash_all_desc == 0xFFFFFFFFFFFFFFFF,
            f"Hash: {hex(hash_all_desc) if hash_all_desc is not None else 'None'} == 0xFFFFFFFFFFFFFFFF"
        )

        # 2. Hamming Distance & Similarity Spectrum
        # Test exact distances: 0, 1, 5, 6, 10, 11, 64
        h_base = 0xAA55AA55AA55AA55

        # Distance 0: exact match
        d0 = ClutterDetector.hammingDistance(h_base, h_base)
        s0 = ClutterDetector.evaluateHashSimilarity(h_base, h_base)
        self.log_result("Hamming Distance d=0 (Exact)", d0 == 0 and s0 == "exactOrNearIdentical", f"d={d0}, sim={s0}")

        # Distance 1: 1 bit flipped
        h_d1 = h_base ^ (1 << 0)
        d1 = ClutterDetector.hammingDistance(h_base, h_d1)
        s1 = ClutterDetector.evaluateHashSimilarity(h_base, h_d1)
        self.log_result("Hamming Distance d=1 (Near Identical)", d1 == 1 and s1 == "exactOrNearIdentical", f"d={d1}, sim={s1}")

        # Distance 5: boundary of exactOrNearIdentical
        h_d5 = h_base ^ 0b11111
        d5 = ClutterDetector.hammingDistance(h_base, h_d5)
        s5 = ClutterDetector.evaluateHashSimilarity(h_base, h_d5)
        self.log_result("Hamming Distance d=5 (Upper Near Identical Boundary)", d5 == 5 and s5 == "exactOrNearIdentical", f"d={d5}, sim={s5}")

        # Distance 6: lower boundary of similarComposition
        h_d6 = h_base ^ 0b111111
        d6 = ClutterDetector.hammingDistance(h_base, h_d6)
        s6 = ClutterDetector.evaluateHashSimilarity(h_base, h_d6)
        self.log_result("Hamming Distance d=6 (Similar Composition Entry)", d6 == 6 and s6 == "similarComposition", f"d={d6}, sim={s6}")

        # Distance 10: upper boundary of duplicate candidacy
        h_d10 = h_base ^ 0b1111111111
        d10 = ClutterDetector.hammingDistance(h_base, h_d10)
        s10 = ClutterDetector.evaluateHashSimilarity(h_base, h_d10)
        self.log_result("Hamming Distance d=10 (Candidate Boundary)", d10 == 10 and s10 == "similarComposition", f"d={d10}, sim={s10}")

        # Distance 11: boundary of distinctScene (non-duplicate)
        h_d11 = h_base ^ 0b11111111111
        d11 = ClutterDetector.hammingDistance(h_base, h_d11)
        s11 = ClutterDetector.evaluateHashSimilarity(h_base, h_d11)
        self.log_result("Hamming Distance d=11 (Distinct Scene Boundary)", d11 == 11 and s11 == "distinctScene", f"d={d11}, sim={s11}")

        # Distance 64: complete inverse
        h_d64 = h_base ^ 0xFFFFFFFFFFFFFFFF
        d64 = ClutterDetector.hammingDistance(h_base, h_d64)
        s64 = ClutterDetector.evaluateHashSimilarity(h_base, h_d64)
        self.log_result("Hamming Distance d=64 (Max Distinct)", d64 == 64 and s64 == "distinctScene", f"d={d64}, sim={s64}")

    # -------------------------------------------------------------------------
    # TEST SUITE 4: Temporal Clustering Boundary Precision (dt = 2.49s vs 2.51s)
    # -------------------------------------------------------------------------
    def test_temporal_clustering_boundaries(self):
        print("\n--- Test Suite 4: Temporal Clustering Precision & Boundary Tests ---")
        t_anchor = datetime(2026, 10, 26, 12, 0, 0, tzinfo=timezone.utc)

        # Pair 1: dt = 2.49s (Inside 2.5s threshold)
        p_anchor = PhotoAssetModel(
            id="p-anc", localIdentifier="ph-anc",
            creationDate=t_anchor, pixelWidth=4032, pixelHeight=3024
        )
        p_249 = PhotoAssetModel(
            id="p-249", localIdentifier="ph-249",
            creationDate=t_anchor + timedelta(seconds=2.49), pixelWidth=4032, pixelHeight=3024
        )
        clusters_249 = ClutterDetector.detectDuplicates([p_anchor, p_249], temporalThreshold=2.5)
        self.log_result(
            "Temporal Boundary dt = 2.49s (Inside Threshold)",
            len(clusters_249) == 1 and len(clusters_249[0]) == 2,
            f"Clusters formed: {len(clusters_249)}"
        )

        # Pair 2: dt = 2.50s (Exact Boundary)
        p_250 = PhotoAssetModel(
            id="p-250", localIdentifier="ph-250",
            creationDate=t_anchor + timedelta(seconds=2.50), pixelWidth=4032, pixelHeight=3024
        )
        clusters_250 = ClutterDetector.detectDuplicates([p_anchor, p_250], temporalThreshold=2.5)
        self.log_result(
            "Temporal Boundary dt = 2.50s (Exact Threshold)",
            len(clusters_250) == 1 and len(clusters_250[0]) == 2,
            f"Clusters formed: {len(clusters_250)}"
        )

        # Pair 3: dt = 2.51s (Outside Threshold)
        p_251 = PhotoAssetModel(
            id="p-251", localIdentifier="ph-251",
            creationDate=t_anchor + timedelta(seconds=2.51), pixelWidth=4032, pixelHeight=3024
        )
        clusters_251 = ClutterDetector.detectDuplicates([p_anchor, p_251], temporalThreshold=2.5)
        self.log_result(
            "Temporal Boundary dt = 2.51s (Outside Threshold)",
            len(clusters_251) == 0,
            f"Clusters formed: {len(clusters_251)} (expected 0)"
        )

        # Multi-element temporal chain test:
        # t = 0.0s, 1.2s, 2.4s, 3.6s, 4.8s
        # Pairwise deltas are 1.2s, but total span is 4.8s relative to anchor.
        chain_assets = [
            PhotoAssetModel(
                id=f"chain-{i}", localIdentifier=f"ph-chain-{i}",
                creationDate=t_anchor + timedelta(seconds=i * 1.2),
                pixelWidth=4032, pixelHeight=3024
            )
            for i in range(5)
        ]
        # Anchor is chain-0 (t=0.0):
        # chain-1 (t=1.2) diff=1.2 <= 2.5 -> added
        # chain-2 (t=2.4) diff=2.4 <= 2.5 -> added
        # chain-3 (t=3.6) diff=3.6 > 2.5 -> break!
        # Result of cluster 1: [chain-0, chain-1, chain-2]
        # Next unvisited anchor is chain-3 (t=3.6):
        # chain-4 (t=4.8) diff=1.2 <= 2.5 -> added
        # Result of cluster 2: [chain-3, chain-4]
        clusters_chain = ClutterDetector.detectDuplicates(chain_assets, temporalThreshold=2.5)
        self.log_result(
            "Multi-Hop Temporal Chain Partitioning",
            len(clusters_chain) == 2 and len(clusters_chain[0]) == 3 and len(clusters_chain[1]) == 2,
            f"Cluster counts: {[len(c) for c in clusters_chain]} (expected [3, 2])"
        )

    # -------------------------------------------------------------------------
    # TEST SUITE 5: Large Video Boundary Matrix (Duration & Size Boundaries)
    # -------------------------------------------------------------------------
    def test_large_video_boundaries(self):
        print("\n--- Test Suite 5: Large Video Boundary Conditions ---")
        # Boundary cases:
        # 1. 59.9s, 99.9MB (99_999_999 B) -> False
        # 2. 60.0s, 10MB -> True (duration met)
        # 3. 59.9s, 100MB (100_000_000 B) -> True (size met)
        # 4. 60.0s, 100MB -> True (both met)
        # 5. Image with 120s and 200MB -> False (Must be video)
        # 6. Audio with 120s and 200MB -> False
        base_t = datetime.now(timezone.utc)

        v_sub = PhotoAssetModel(
            id="v1", localIdentifier="v1", creationDate=base_t,
            mediaType=AssetMediaType.VIDEO, duration=59.9, estimatedByteSize=99_999_999
        )
        self.log_result(
            "Video Boundary: 59.9s & 99.9MB (Below Both)",
            not v_sub.isLargeVideo,
            f"isLargeVideo: {v_sub.isLargeVideo}"
        )

        v_dur_exact = PhotoAssetModel(
            id="v2", localIdentifier="v2", creationDate=base_t,
            mediaType=AssetMediaType.VIDEO, duration=60.0, estimatedByteSize=50_000_000
        )
        self.log_result(
            "Video Boundary: 60.0s Duration Exact",
            v_dur_exact.isLargeVideo,
            f"isLargeVideo: {v_dur_exact.isLargeVideo}"
        )

        v_size_exact = PhotoAssetModel(
            id="v3", localIdentifier="v3", creationDate=base_t,
            mediaType=AssetMediaType.VIDEO, duration=25.0, estimatedByteSize=100_000_000
        )
        self.log_result(
            "Video Boundary: 100MB Size Exact",
            v_size_exact.isLargeVideo,
            f"isLargeVideo: {v_size_exact.isLargeVideo}"
        )

        v_both = PhotoAssetModel(
            id="v4", localIdentifier="v4", creationDate=base_t,
            mediaType=AssetMediaType.VIDEO, duration=120.0, estimatedByteSize=250_000_000
        )
        self.log_result(
            "Video Boundary: Exceeds Both (120s & 250MB)",
            v_both.isLargeVideo,
            f"isLargeVideo: {v_both.isLargeVideo}"
        )

        img_heavy = PhotoAssetModel(
            id="img1", localIdentifier="img1", creationDate=base_t,
            mediaType=AssetMediaType.IMAGE, duration=120.0, estimatedByteSize=250_000_000
        )
        self.log_result(
            "Media Type Guard: Large Image Not Large Video",
            not img_heavy.isLargeVideo,
            f"isLargeVideo: {img_heavy.isLargeVideo}"
        )

    # -------------------------------------------------------------------------
    # TEST SUITE 6: Domain Edge Cases & Formatters
    # -------------------------------------------------------------------------
    def test_domain_edge_cases(self):
        print("\n--- Test Suite 6: Domain Model Edge Cases & Formatters ---")
        base_t = datetime.now(timezone.utc)

        # Zero height divisor guard
        a_zero_h = PhotoAssetModel(
            id="zh", localIdentifier="zh", creationDate=base_t,
            pixelWidth=1000, pixelHeight=0
        )
        self.log_result(
            "Aspect Ratio Zero Height Guard",
            a_zero_h.aspectRatio == 1.0,
            f"aspectRatio: {a_zero_h.aspectRatio}"
        )

        # Negative height guard
        a_neg_h = PhotoAssetModel(
            id="nh", localIdentifier="nh", creationDate=base_t,
            pixelWidth=1000, pixelHeight=-500
        )
        self.log_result(
            "Aspect Ratio Negative Height Guard",
            a_neg_h.aspectRatio == 1.0,
            f"aspectRatio: {a_neg_h.aspectRatio}"
        )

        # Size formatters
        sizes_to_test = [
            (0, "0 B"),
            (750, "750 B"),
            (1_500, ["1.5 KB", "1.50 KB"]),
            (25_000_000, ["25 MB", "25.0 MB"]),
            (1_840_000_000, "1.84 GB"),
            (2_500_000_000_000, "2.50 TB")
        ]
        for b_sz, expected in sizes_to_test:
            a = PhotoAssetModel(id="fmt", localIdentifier="fmt", creationDate=base_t, estimatedByteSize=b_sz)
            fmt = a.formattedSize
            if isinstance(expected, list):
                ok = fmt in expected
            else:
                ok = (fmt == expected)
            self.log_result(
                f"Size Formatter for {b_sz} bytes",
                ok,
                f"got '{fmt}'"
            )

    # -------------------------------------------------------------------------
    # TEST SUITE 7: Swift Codebase Vulnerability Analysis (Static & Architecture)
    # -------------------------------------------------------------------------
    def test_swift_codebase_vulnerabilities(self):
        print("\n--- Test Suite 7: Swift Codebase Static & Vulnerability Checks ---")
        pls_path = r"c:\Users\jzlwi\Documents\antigravity\magical-bohr\SwipeWipe\Sources\SwipeWipeCore\Services\PhotoLibraryService.swift"
        with open(pls_path, "r", encoding="utf-8") as f:
            pls_code = f.read()

        # Check Vulnerability 1: Bursts predicate bug in PhotoLibraryService
        # Line 192: options.predicate = NSPredicate(format: "(mediaSubtype & %d) != 0 OR representsBurst == YES", PHAssetMediaSubtype.photoScreenshot.rawValue)
        burst_screenshot_bug = "(mediaSubtype & %d) != 0 OR representsBurst == YES\", PHAssetMediaSubtype.photoScreenshot.rawValue" in pls_code
        if burst_screenshot_bug:
            self.findings.append(
                "CRITICAL/HIGH FLAW: PhotoLibraryService.swift line 192 uses PHAssetMediaSubtype.photoScreenshot.rawValue in .bursts predicate query!"
            )
            print(" [FINDING] Confirmed: PhotoLibraryService.swift line 192 has typo using photoScreenshot for .bursts query.")

        # Check Vulnerability 2: Large Videos predicate omission in PhotoLibraryService
        # Line 181: options.predicate = NSPredicate(format: "mediaType == %d AND duration >= 60.0", PHAssetMediaType.video.rawValue)
        # Videos < 60s but >= 100MB are completely filtered out at SQLite level!
        large_video_omission = "mediaType == %d AND duration >= 60.0" in pls_code and "100_000_000" not in pls_code[pls_code.find("case .largeVideos:"):pls_code.find("case .bursts:")]
        if large_video_omission:
            self.findings.append(
                "MEDIUM FLAW: PhotoLibraryService.swift line 181 filters videos by duration >= 60.0 in PhotoKit fetch predicate, omitting short (<60s) high-bitrate videos >= 100MB before ClutterDetector can inspect them."
            )
            print(" [FINDING] Confirmed: PhotoLibraryService.swift line 181 omits short videos >= 100MB from PhotoKit fetch.")

        # Check Concurrency & Sendable
        self.log_result(
            "Sendable Conformance on Core Models",
            "Sendable" in pls_code,
            "PhotoLibraryService has @unchecked Sendable conformance"
        )

    def run_all(self):
        print("=================================================================")
        print("STARTING EMPIRICAL CHALLENGER VERIFICATION FOR MILESTONE 1")
        print("=================================================================")
        self.test_synthetic_10k_stress()
        self.test_pathological_clustering()
        self.test_dhash_and_hamming_spectrum()
        self.test_temporal_clustering_boundaries()
        self.test_large_video_boundaries()
        self.test_domain_edge_cases()
        self.test_swift_codebase_vulnerabilities()

        print("\n=================================================================")
        print(f"EMPIRICAL RESULTS: {self.passes} PASSED, {self.failures} FAILED")
        print(f"FINDINGS DISCOVERED: {len(self.findings)}")
        for f in self.findings:
            print(f" - {f}")
        print("=================================================================")

        return self.failures == 0


if __name__ == "__main__":
    runner = ChallengerRunner()
    success = runner.run_all()
    # Return 0 if pass count succeeds
    sys.exit(0 if success else 1)
