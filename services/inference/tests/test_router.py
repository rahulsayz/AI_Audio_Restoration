"""
Unit tests for the intelligence router.
Checks feature-to-recipe mappings, step-wise thresholds, and cultural caps.
"""
from sangeet.v1.restoration_pb2 import AudioFeatures

from sangeet_inference.router import route_features


def test_router_returns_passthrough_recipe_for_clean_audio() -> None:
    """
    Asserts that route_features returns a RestorationRecipe containing exactly
    the passthrough stage for clean audio (SNR >= 35 dB).
    """
    features = AudioFeatures(
        sample_rate=48000,
        channels=2,
        duration_s=30.0,
        snr_estimate_db=36.0,
        hum_50hz_present=False,
        hum_60hz_present=False,
    )

    recipe = route_features(features)

    assert len(recipe.stages) == 1
    stage_invocation = recipe.stages[0]
    assert stage_invocation.stage_name == "passthrough"
    assert stage_invocation.strength == 1.0


def test_router_returns_passthrough_recipe_for_unknown_snr() -> None:
    """
    Asserts that when SNR estimate is missing/unknown, deep_filter_net is skipped,
    returning a passthrough recipe.
    """
    features = AudioFeatures(
        sample_rate=48000,
        channels=2,
        duration_s=30.0,
        # snr_estimate_db is omitted / None
        hum_50hz_present=False,
        hum_60hz_present=False,
    )

    recipe = route_features(features)

    assert len(recipe.stages) == 1
    stage_invocation = recipe.stages[0]
    assert stage_invocation.stage_name == "passthrough"
    assert stage_invocation.strength == 1.0


def test_router_handles_low_snr_threshold() -> None:
    """
    Asserts that low SNR (< 15 dB) triggers deep_filter_net at strength 0.7.
    """
    features = AudioFeatures(
        sample_rate=48000,
        channels=2,
        duration_s=30.0,
        snr_estimate_db=12.0,
        hum_50hz_present=False,
        hum_60hz_present=False,
    )

    recipe = route_features(features)

    assert len(recipe.stages) == 1
    stage_invocation = recipe.stages[0]
    assert stage_invocation.stage_name == "deep_filter_net"
    assert stage_invocation.strength == 0.7
    assert stage_invocation.params.params["strength"] == 0.7


def test_router_handles_medium_snr_15_to_25() -> None:
    """
    Asserts that SNR between 15-25 dB triggers deep_filter_net at strength 0.5.
    """
    features = AudioFeatures(
        sample_rate=48000,
        channels=2,
        duration_s=30.0,
        snr_estimate_db=20.0,
        hum_50hz_present=False,
        hum_60hz_present=False,
    )

    recipe = route_features(features)

    assert len(recipe.stages) == 1
    stage_invocation = recipe.stages[0]
    assert stage_invocation.stage_name == "deep_filter_net"
    assert stage_invocation.strength == 0.5
    assert stage_invocation.params.params["strength"] == 0.5


def test_router_handles_medium_high_snr_25_to_35() -> None:
    """
    Asserts that SNR between 25-35 dB triggers deep_filter_net at strength 0.3.
    """
    features = AudioFeatures(
        sample_rate=48000,
        channels=2,
        duration_s=30.0,
        snr_estimate_db=30.0,
        hum_50hz_present=False,
        hum_60hz_present=False,
    )

    recipe = route_features(features)

    assert len(recipe.stages) == 1
    stage_invocation = recipe.stages[0]
    assert stage_invocation.stage_name == "deep_filter_net"
    assert stage_invocation.strength == 0.3
    assert stage_invocation.params.params["strength"] == 0.3


def test_router_classical_music_capping_heuristic() -> None:
    """
    Asserts that low-SNR classical music has its deep_filter_net strength capped at 0.5.
    Verifies using a synthetic mock feature containing spectral_centroid_hz and crest_factor.
    """

    class MockAudioFeatures:
        def __init__(self, snr: float | None, centroid: float | None, crest: float | None):
            self.snr_estimate_db = snr
            self.spectral_centroid_hz = centroid
            self.crest_factor = crest

        def HasField(self, name: str) -> bool:  # noqa: N802
            if name == "snr_estimate_db":
                return self.snr_estimate_db is not None
            if name == "spectral_centroid_hz":
                return self.spectral_centroid_hz is not None
            return False

    # Classical music heuristic: spectral_centroid_hz < 1500 AND crest_factor > 15 dB
    # Normally SNR 10.0 dB triggers 0.7 strength, but must be capped at 0.5
    classical_features = MockAudioFeatures(snr=10.0, centroid=1200.0, crest=18.0)
    recipe = route_features(classical_features)  # type: ignore[arg-type]

    assert len(recipe.stages) == 1
    stage_invocation = recipe.stages[0]
    assert stage_invocation.stage_name == "deep_filter_net"
    assert stage_invocation.strength == 0.5
    assert stage_invocation.params.params["strength"] == 0.5

    # Non-classical music (high centroid, low crest factor) should NOT be capped
    non_classical_features = MockAudioFeatures(snr=10.0, centroid=2000.0, crest=8.0)
    recipe_non = route_features(non_classical_features)  # type: ignore[arg-type]

    assert len(recipe_non.stages) == 1
    assert recipe_non.stages[0].strength == 0.7
