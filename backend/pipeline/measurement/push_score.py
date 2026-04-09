"""PUSH (Pressure Ulcer Scale for Healing) Tool 3.0 score computation.

Matches the iOS PUSHScore.swift scoring ranges exactly.
Total score = areaScore (0-10) + exudateScore (0-3) + surfaceTypeScore (0-4)
Maximum = 17
"""


def compute_area_score(area_cm2: float) -> int:
    """PUSH area sub-score (0-10).

    Ranges match iOS PUSHScore.swift:32-46 exactly.
    """
    if area_cm2 <= 0:
        return 0
    elif area_cm2 < 0.3:
        return 1
    elif area_cm2 < 0.7:
        return 2
    elif area_cm2 < 1.0:
        return 3
    elif area_cm2 < 2.0:
        return 4
    elif area_cm2 < 3.0:
        return 5
    elif area_cm2 < 4.0:
        return 6
    elif area_cm2 < 8.0:
        return 7
    elif area_cm2 < 12.0:
        return 8
    elif area_cm2 < 24.0:
        return 9
    else:
        return 10


def compute_surface_type_score(tissue_composition: dict) -> int:
    """PUSH surface type sub-score (0-4).

    Based on worst tissue type present:
    4 = necrotic tissue
    3 = slough
    2 = granulation tissue
    1 = epithelial tissue
    0 = closed/resurfaced

    Args:
        tissue_composition: Dict with keys like granulation_pct, slough_pct,
            necrotic_pct, epithelial_pct (values 0.0-1.0).
    """
    necrotic = tissue_composition.get("necrotic_pct", 0.0)
    slough = tissue_composition.get("slough_pct", 0.0)
    granulation = tissue_composition.get("granulation_pct", 0.0)
    epithelial = tissue_composition.get("epithelial_pct", 0.0)

    if necrotic > 0.05:
        return 4
    elif slough > 0.10:
        return 3
    elif granulation > 0.0:
        return 2
    elif epithelial > 0.0:
        return 1
    else:
        return 0


def compute_push_score(
    area_cm2: float,
    tissue_composition: dict,
    exudate_level: int | None = None,
) -> dict:
    """Compute complete PUSH score.

    Args:
        area_cm2: Wound surface area in cm^2.
        tissue_composition: Dict of tissue type percentages.
        exudate_level: Nurse-provided exudate level (0-3).
            0=none, 1=light, 2=moderate, 3=heavy.
            If None, defaults to 1 (light).

    Returns:
        Dict with areaScore, exudateScore, surfaceTypeScore matching
        the iOS PUSHScore struct.
    """
    area_score = compute_area_score(area_cm2)
    surface_type_score = compute_surface_type_score(tissue_composition)
    exudate_score = exudate_level if exudate_level is not None else 1

    # Clamp to valid ranges
    exudate_score = max(0, min(3, exudate_score))

    return {
        "areaScore": area_score,
        "exudateScore": exudate_score,
        "surfaceTypeScore": surface_type_score,
    }
