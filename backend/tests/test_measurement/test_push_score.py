"""Tests for PUSH score computation — must match iOS PUSHScore.swift exactly."""

import pytest

from pipeline.measurement.push_score import (
    compute_area_score,
    compute_surface_type_score,
    compute_push_score,
)


class TestAreaScore:
    """Must match iOS PUSHScore.swift:32-46."""

    def test_zero_area(self):
        assert compute_area_score(0) == 0

    def test_tiny_wound(self):
        assert compute_area_score(0.1) == 1
        assert compute_area_score(0.29) == 1

    def test_score_2(self):
        assert compute_area_score(0.3) == 2
        assert compute_area_score(0.69) == 2

    def test_score_3(self):
        assert compute_area_score(0.7) == 3
        assert compute_area_score(0.99) == 3

    def test_score_4(self):
        assert compute_area_score(1.0) == 4
        assert compute_area_score(1.99) == 4

    def test_score_5(self):
        assert compute_area_score(2.0) == 5

    def test_score_6(self):
        assert compute_area_score(3.0) == 6

    def test_score_7(self):
        assert compute_area_score(4.0) == 7
        assert compute_area_score(7.99) == 7

    def test_score_8(self):
        assert compute_area_score(8.0) == 8

    def test_score_9(self):
        assert compute_area_score(12.0) == 9
        assert compute_area_score(23.99) == 9

    def test_score_10(self):
        assert compute_area_score(24.0) == 10
        assert compute_area_score(100.0) == 10


class TestSurfaceTypeScore:
    def test_necrotic(self):
        """Necrotic > 5% → score 4."""
        assert compute_surface_type_score({"necrotic_pct": 0.10}) == 4

    def test_slough(self):
        """Slough > 10% → score 3."""
        assert compute_surface_type_score({"slough_pct": 0.20}) == 3

    def test_granulation(self):
        """Granulation present → score 2."""
        assert compute_surface_type_score({"granulation_pct": 0.80}) == 2

    def test_epithelial(self):
        """Epithelial only → score 1."""
        assert compute_surface_type_score({"epithelial_pct": 0.50}) == 1

    def test_closed(self):
        """No tissue → score 0 (closed)."""
        assert compute_surface_type_score({}) == 0


class TestPUSHScoreTotal:
    def test_complete_score(self):
        """Example: 12.4 cm², granulation+slough, moderate exudate."""
        result = compute_push_score(
            area_cm2=12.4,
            tissue_composition={"granulation_pct": 0.70, "slough_pct": 0.25, "necrotic_pct": 0.03, "epithelial_pct": 0.02},
            exudate_level=2,
        )
        assert result["areaScore"] == 9
        assert result["exudateScore"] == 2
        assert result["surfaceTypeScore"] == 3  # Slough > 10%
        total = result["areaScore"] + result["exudateScore"] + result["surfaceTypeScore"]
        assert total == 14

    def test_default_exudate(self):
        """No exudate level → default to 1."""
        result = compute_push_score(area_cm2=1.0, tissue_composition={})
        assert result["exudateScore"] == 1

    def test_healed_wound(self):
        """Zero area, no tissue → all zeros."""
        result = compute_push_score(area_cm2=0, tissue_composition={})
        assert result["areaScore"] == 0
        assert result["surfaceTypeScore"] == 0
