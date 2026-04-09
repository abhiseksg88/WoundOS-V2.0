"""Pydantic models matching the iOS ServerResponse contract exactly."""

from pydantic import BaseModel


class WoundMeasurement(BaseModel):
    areaCm2: float
    maxDepthMm: float
    avgDepthMm: float
    volumeMl: float
    lengthMm: float
    widthMm: float
    perimeterMm: float
    underminingMm: float | None = None
    tunnelingMm: float | None = None


class PUSHScore(BaseModel):
    areaScore: int  # 0-10
    exudateScore: int  # 0-3
    surfaceTypeScore: int  # 0-4


class ServerResponse(BaseModel):
    measurements: WoundMeasurement
    annotatedImageBase64: str
    depthHeatmapBase64: str
    woundMaskBase64: str
    meshOBJData: str | None = None
    splatURL: str | None = None
    clinicalSummary: str
    pushScore: PUSHScore | None = None
    processingTimeMs: int


class MeasurementDelta(BaseModel):
    areaDiffPercent: float
    depthDiffPercent: float
    note: str


class CameraIntrinsics(BaseModel):
    fx: float
    fy: float
    cx: float
    cy: float
    width: int
    height: int


class CameraPose(BaseModel):
    timestamp: float
    transform: list[list[float]]  # 4x4 matrix
    trackingState: str = "normal"


class TissueComposition(BaseModel):
    granulation_pct: float = 0.0
    slough_pct: float = 0.0
    necrotic_pct: float = 0.0
    epithelial_pct: float = 0.0
