"""Clinical summary generation endpoint using Claude Haiku or template fallback."""

from __future__ import annotations

import logging
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, status

from app.auth import verify_token
from app.config import Settings, get_settings
from app.models.schemas import (
    ClinicalSummaryRequest,
    ClinicalSummaryResponse,
    ErrorResponse,
    Measurements,
)

logger = logging.getLogger(__name__)
router = APIRouter()


# ---------------------------------------------------------------------------
# POST /clinical-summary
# ---------------------------------------------------------------------------


@router.post(
    "/clinical-summary",
    response_model=ClinicalSummaryResponse,
    responses={401: {"model": ErrorResponse}},
    tags=["clinical"],
    summary="Generate a clinical narrative note",
)
async def generate_clinical_summary(
    body: ClinicalSummaryRequest,
    _token: str = Depends(verify_token),
    settings: Settings = Depends(get_settings),
) -> ClinicalSummaryResponse:
    """Generate a clinical note from scan measurements.

    Uses Claude Haiku when an Anthropic API key is configured.
    Otherwise falls back to a deterministic template.
    """
    if settings.anthropic_api_key:
        summary_text = await _generate_with_haiku(body, settings.anthropic_api_key)
        generated_by = "claude-haiku"
    else:
        summary_text = _generate_template(body)
        generated_by = "template"

    return ClinicalSummaryResponse(
        scan_id=body.scan_id,
        summary=summary_text,
        generated_by=generated_by,
        generated_at=datetime.now(timezone.utc),
    )


# ---------------------------------------------------------------------------
# Claude Haiku generation
# ---------------------------------------------------------------------------


async def _generate_with_haiku(body: ClinicalSummaryRequest, api_key: str) -> str:
    """Call the Anthropic API to generate a clinical summary."""
    try:
        import anthropic

        client = anthropic.Anthropic(api_key=api_key)

        prompt = _build_prompt(body)

        message = client.messages.create(
            model="claude-haiku-4-20250414",
            max_tokens=512,
            messages=[{"role": "user", "content": prompt}],
            system=(
                "You are a clinical documentation assistant for wound care. "
                "Generate a concise, professional wound assessment note suitable "
                "for inclusion in a patient's medical record. Use objective medical "
                "terminology. Include all measurements provided. If previous measurements "
                "are given, note trends (improving, stable, worsening). Keep the note "
                "to one paragraph."
            ),
        )
        return message.content[0].text  # type: ignore[union-attr]
    except Exception:
        logger.exception("Claude Haiku generation failed, falling back to template")
        return _generate_template(body)


def _build_prompt(body: ClinicalSummaryRequest) -> str:
    """Construct the user prompt for Claude Haiku."""
    m = body.measurements
    parts = [
        f"Generate a clinical wound assessment note with these details:",
        f"- Wound type: {body.wound_type or 'unspecified'}",
        f"- Location: {body.wound_location or 'unspecified'}",
        f"- Area: {m.area_cm2} cm2",
        f"- Maximum depth: {m.max_depth_mm} mm",
        f"- Volume: {m.volume_cm3} cm3",
        f"- Length: {m.length_cm} cm, Width: {m.width_cm} cm",
        f"- Perimeter: {m.perimeter_cm} cm",
    ]
    if m.push_score is not None:
        parts.append(f"- PUSH score: {m.push_score}")
    if body.clinical_notes:
        parts.append(f"- Clinical notes: {body.clinical_notes}")

    if body.previous_measurements:
        prev = body.previous_measurements
        parts.append(f"\nPrevious measurements for comparison:")
        parts.append(f"- Previous area: {prev.area_cm2} cm2")
        parts.append(f"- Previous max depth: {prev.max_depth_mm} mm")
        parts.append(f"- Previous volume: {prev.volume_cm3} cm3")

    return "\n".join(parts)


# ---------------------------------------------------------------------------
# Template fallback
# ---------------------------------------------------------------------------


def _generate_template(body: ClinicalSummaryRequest) -> str:
    """Generate a deterministic clinical summary from a template."""
    m = body.measurements
    wound_type = body.wound_type or "wound"
    wound_location = body.wound_location or "unspecified location"

    summary_parts = [
        f"Wound assessment: {wound_type.replace('_', ' ').title()} on {wound_location}.",
        f"Current measurements: area {m.area_cm2} cm2, maximum depth {m.max_depth_mm} mm, "
        f"volume {m.volume_cm3} cm3, length {m.length_cm} cm x width {m.width_cm} cm, "
        f"perimeter {m.perimeter_cm} cm.",
    ]

    if m.push_score is not None:
        summary_parts.append(f"PUSH score: {m.push_score}.")

    # Add trend analysis if previous measurements are available
    if body.previous_measurements:
        prev = body.previous_measurements
        trends: list[str] = []

        area_delta = _percent_change(prev.area_cm2, m.area_cm2)
        depth_delta = _percent_change(prev.max_depth_mm, m.max_depth_mm)
        volume_delta = _percent_change(prev.volume_cm3, m.volume_cm3)

        trends.append(
            f"area {'decreased' if area_delta < 0 else 'increased'} by "
            f"{abs(area_delta):.1f}% (from {prev.area_cm2:.2f} to {m.area_cm2:.2f} cm2)"
        )
        trends.append(
            f"depth {'decreased' if depth_delta < 0 else 'increased'} by "
            f"{abs(depth_delta):.1f}% (from {prev.max_depth_mm:.2f} to {m.max_depth_mm:.2f} mm)"
        )
        trends.append(
            f"volume {'decreased' if volume_delta < 0 else 'increased'} by "
            f"{abs(volume_delta):.1f}% (from {prev.volume_cm3:.2f} to {m.volume_cm3:.2f} cm3)"
        )

        overall = "improvement" if (area_delta < 0 and depth_delta < 0) else "change"
        summary_parts.append(
            f"Compared to previous assessment, {', '.join(trends[:-1])}, "
            f"and {trends[-1]}, indicating {overall}."
        )

    if body.clinical_notes:
        summary_parts.append(f"Clinical notes: {body.clinical_notes}.")

    return " ".join(summary_parts)


def _percent_change(old: float, new: float) -> float:
    """Return percentage change from old to new. Negative = decrease."""
    if old == 0:
        return 0.0
    return ((new - old) / old) * 100
