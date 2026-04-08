"""Clinical summary generation via Claude API.

Uses Claude 3.5 Haiku for fast, cheap, medically coherent wound
assessment notes suitable for medical records.
"""

import logging

import anthropic

from app.config import settings

logger = logging.getLogger("woundos.clinical.summary")


CLINICAL_PROMPT = """You are a clinical wound assessment AI. Based on the following wound measurements and tissue analysis, write a 2-4 sentence clinical wound assessment note suitable for a medical record.

Wound measurements:
- Area: {area_cm2:.1f} cm²
- Maximum depth: {max_depth_mm:.1f} mm
- Average depth: {avg_depth_mm:.1f} mm
- Volume: {volume_ml:.2f} mL
- Dimensions: {length_mm:.1f} × {width_mm:.1f} mm
- Perimeter: {perimeter_mm:.1f} mm
- Tissue composition: {granulation:.0f}% granulation, {slough:.0f}% slough, {necrotic:.0f}% necrotic, {epithelial:.0f}% epithelial
- PUSH score: {push_total}/17 (area={area_score}, exudate={exudate_score}, surface={surface_score})

Include: wound stage assessment, tissue bed description, periwound condition assessment, and one treatment recommendation. Use standard wound care terminology."""


def generate_clinical_summary(
    measurements: dict,
    tissue_composition: dict,
    push_score: dict,
) -> str:
    """Generate a clinical wound assessment summary using Claude.

    Args:
        measurements: Dict with areaCm2, maxDepthMm, etc.
        tissue_composition: Dict with granulation_pct, slough_pct, etc.
        push_score: Dict with areaScore, exudateScore, surfaceTypeScore.

    Returns:
        Clinical summary string (2-4 sentences).
    """
    if not settings.anthropic_api_key:
        logger.warning("No Anthropic API key configured, returning placeholder summary")
        return _generate_placeholder_summary(measurements, push_score)

    prompt = CLINICAL_PROMPT.format(
        area_cm2=measurements.get("areaCm2", 0),
        max_depth_mm=measurements.get("maxDepthMm", 0),
        avg_depth_mm=measurements.get("avgDepthMm", 0),
        volume_ml=measurements.get("volumeMl", 0),
        length_mm=measurements.get("lengthMm", 0),
        width_mm=measurements.get("widthMm", 0),
        perimeter_mm=measurements.get("perimeterMm", 0),
        granulation=tissue_composition.get("granulation_pct", 0) * 100,
        slough=tissue_composition.get("slough_pct", 0) * 100,
        necrotic=tissue_composition.get("necrotic_pct", 0) * 100,
        epithelial=tissue_composition.get("epithelial_pct", 0) * 100,
        push_total=push_score.get("areaScore", 0) + push_score.get("exudateScore", 0) + push_score.get("surfaceTypeScore", 0),
        area_score=push_score.get("areaScore", 0),
        exudate_score=push_score.get("exudateScore", 0),
        surface_score=push_score.get("surfaceTypeScore", 0),
    )

    try:
        client = anthropic.Anthropic(api_key=settings.anthropic_api_key)
        message = client.messages.create(
            model=settings.anthropic_model,
            max_tokens=300,
            messages=[{"role": "user", "content": prompt}],
        )
        summary = message.content[0].text.strip()
        logger.info("Clinical summary generated (%d chars)", len(summary))
        return summary
    except Exception as e:
        logger.error("Claude API call failed: %s", e)
        return _generate_placeholder_summary(measurements, push_score)


def _generate_placeholder_summary(measurements: dict, push_score: dict) -> str:
    """Generate a basic template summary when Claude API is unavailable."""
    area = measurements.get("areaCm2", 0)
    depth = measurements.get("maxDepthMm", 0)
    total = push_score.get("areaScore", 0) + push_score.get("exudateScore", 0) + push_score.get("surfaceTypeScore", 0)

    if depth > 3:
        stage = "Stage III"
    elif depth > 0:
        stage = "Stage II"
    else:
        stage = "Stage I"

    return (
        f"{stage} wound measuring {area:.1f} cm² with maximum depth of {depth:.1f} mm. "
        f"PUSH score {total}/17. "
        f"Continue current wound care protocol and reassess in 1 week."
    )
