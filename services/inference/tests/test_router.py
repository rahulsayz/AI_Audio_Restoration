"""
Unit tests for the intelligence router.
Checks feature-to-recipe mappings, step-wise thresholds, and cultural caps.
"""
import pytest
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
        click_rate_per_s=0.0,
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
        click_rate_per_s=0.0,
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
        click_rate_per_s=0.0,
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
        click_rate_per_s=0.0,
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
        click_rate_per_s=0.0,
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
        def __init__(self, snr: float | None, centroid: float | None, crest: float | None, click_rate: float | None = 0.0):
            self.snr_estimate_db = snr
            self.spectral_centroid_hz = centroid
            self.crest_factor = crest
            self.click_rate_per_s = click_rate

        def HasField(self, name: str) -> bool:  # noqa: N802
            if name == "snr_estimate_db":
                return self.snr_estimate_db is not None
            if name == "spectral_centroid_hz":
                return self.spectral_centroid_hz is not None
            if name == "click_rate_per_s":
                return self.click_rate_per_s is not None
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


def test_router_handles_various_click_rates() -> None:
    """
    Asserts that click rates trigger the declick stage with the correct strength values.
    """
    # 1. Severe clicks (> 10.0) -> strength 0.8
    features_severe = AudioFeatures(
        sample_rate=48000,
        channels=2,
        duration_s=30.0,
        snr_estimate_db=36.0,  # Clean SNR to bypass deep_filter_net
        click_rate_per_s=12.5,
    )
    recipe_severe = route_features(features_severe)
    assert len(recipe_severe.stages) == 1
    assert recipe_severe.stages[0].stage_name == "declick"
    assert recipe_severe.stages[0].strength == pytest.approx(0.8)
    assert recipe_severe.stages[0].params.params["threshold_multiplier"] == 5.0

    # 2. Medium clicks (5.0 <= rate <= 10.0) -> strength 0.5
    features_med = AudioFeatures(
        sample_rate=48000,
        channels=2,
        duration_s=30.0,
        snr_estimate_db=36.0,
        click_rate_per_s=7.5,
    )
    recipe_med = route_features(features_med)
    assert len(recipe_med.stages) == 1
    assert recipe_med.stages[0].stage_name == "declick"
    assert recipe_med.stages[0].strength == pytest.approx(0.5)

    # 3. Light clicks (1.0 <= rate < 5.0) -> strength 0.3
    features_light = AudioFeatures(
        sample_rate=48000,
        channels=2,
        duration_s=30.0,
        snr_estimate_db=36.0,
        click_rate_per_s=2.5,
    )
    recipe_light = route_features(features_light)
    assert len(recipe_light.stages) == 1
    assert recipe_light.stages[0].stage_name == "declick"
    assert recipe_light.stages[0].strength == pytest.approx(0.3)

    # 4. Extremely light clicks (0.0 < rate < 1.0) -> strength 0.1
    features_ex_light = AudioFeatures(
        sample_rate=48000,
        channels=2,
        duration_s=30.0,
        snr_estimate_db=36.0,
        click_rate_per_s=0.5,
    )
    recipe_ex_light = route_features(features_ex_light)
    assert len(recipe_ex_light.stages) == 1
    assert recipe_ex_light.stages[0].stage_name == "declick"
    assert recipe_ex_light.stages[0].strength == pytest.approx(0.1)

    # 5. Clean / Zero click rate -> bypass declick (returns passthrough because SNR is clean too)
    features_clean = AudioFeatures(
        sample_rate=48000,
        channels=2,
        duration_s=30.0,
        snr_estimate_db=36.0,
        click_rate_per_s=0.0,
    )
    recipe_clean = route_features(features_clean)
    assert len(recipe_clean.stages) == 1
    assert recipe_clean.stages[0].stage_name == "passthrough"


def test_router_declicks_by_default_if_click_rate_omitted() -> None:
    """
    Asserts that if click_rate_per_s is not provided/omitted from features,
    declick is included by default at strength 0.5.
    """
    features = AudioFeatures(
        sample_rate=48000,
        channels=2,
        duration_s=30.0,
        snr_estimate_db=36.0,  # Clean SNR to bypass deep_filter_net
        # click_rate_per_s is omitted
    )
    recipe = route_features(features)
    assert len(recipe.stages) == 1
    assert recipe.stages[0].stage_name == "declick"
    assert recipe.stages[0].strength == pytest.approx(0.5)


def test_router_dehum_triggered_on_50hz_hum() -> None:
    """
    Asserts that 50Hz hum triggers the dehum stage at strength 0.5.
    """
    features = AudioFeatures(
        sample_rate=48000,
        channels=2,
        duration_s=30.0,
        snr_estimate_db=36.0,
        click_rate_per_s=0.0,
        hum_50hz_present=True,
        hum_60hz_present=False,
    )
    recipe = route_features(features)
    assert len(recipe.stages) == 1
    assert recipe.stages[0].stage_name == "dehum"
    assert recipe.stages[0].strength == pytest.approx(0.5)


def test_router_dehum_triggered_on_60hz_hum() -> None:
    """
    Asserts that 60Hz hum triggers the dehum stage at strength 0.5.
    """
    features = AudioFeatures(
        sample_rate=48000,
        channels=2,
        duration_s=30.0,
        snr_estimate_db=36.0,
        click_rate_per_s=0.0,
        hum_50hz_present=False,
        hum_60hz_present=True,
    )
    recipe = route_features(features)
    assert len(recipe.stages) == 1
    assert recipe.stages[0].stage_name == "dehum"
    assert recipe.stages[0].strength == pytest.approx(0.5)


def test_router_dehum_triggered_by_default_when_features_none() -> None:
    """
    Asserts that if features is None, dehum is triggered by default at strength 0.5.
    """
    recipe = route_features(None)  # type: ignore[arg-type]
    # If features is None, deep_filter_net and declick are skipped,
    # but dehum is added by default at strength 0.5 (default-on fallback).
    assert len(recipe.stages) == 1
    assert recipe.stages[0].stage_name == "dehum"
    assert recipe.stages[0].strength == pytest.approx(0.5)


def test_router_signal_chain_ordering() -> None:
    """
    Asserts that the active signal chain stages are ordered correctly:
    Stage 3 (dehum) -> Stage 4 (deep_filter_net) -> Stage 5 (declick).
    BWE is unconditionally disabled in V1, so it must not be present in the active stages list.
    """
    features = AudioFeatures(
        sample_rate=48000,
        channels=2,
        duration_s=30.0,
        snr_estimate_db=10.0,  # Triggers deep_filter_net
        click_rate_per_s=8.0,  # Triggers declick
        hum_50hz_present=True,  # Triggers dehum
        hf_rolloff_hz=3500.0,  # BWE input but bypassed in V1
    )
    recipe = route_features(features)
    assert len(recipe.stages) == 3
    assert recipe.stages[0].stage_name == "dehum"
    assert recipe.stages[1].stage_name == "deep_filter_net"
    assert recipe.stages[2].stage_name == "declick"
    # Explicitly check BWE is not present
    for stage in recipe.stages:
        assert stage.stage_name != "bandwidth_extension"


def test_router_triggers_bwe_on_severe_rolloff() -> None:
    """
    Asserts that severe high-frequency rolloff (< 4000 Hz) does NOT trigger BWE in V1.
    """
    features = AudioFeatures(
        sample_rate=48000,
        channels=2,
        duration_s=30.0,
        snr_estimate_db=36.0,  # Clean to bypass denoiser
        click_rate_per_s=0.0,  # Bypass declick
        hf_rolloff_hz=3500.0,
    )
    recipe = route_features(features)
    # BWE is disabled, so we fallback to passthrough since no other stages are active
    assert len(recipe.stages) == 1
    assert recipe.stages[0].stage_name == "passthrough"


def test_router_triggers_bwe_on_medium_rolloff() -> None:
    """
    Asserts that medium high-frequency rolloff (4000 to 6000 Hz) does NOT trigger BWE in V1.
    """
    features = AudioFeatures(
        sample_rate=48000,
        channels=2,
        duration_s=30.0,
        snr_estimate_db=36.0,
        click_rate_per_s=0.0,
        hf_rolloff_hz=5000.0,
    )
    recipe = route_features(features)
    assert len(recipe.stages) == 1
    assert recipe.stages[0].stage_name == "passthrough"


def test_router_triggers_bwe_on_light_rolloff() -> None:
    """
    Asserts that light high-frequency rolloff (6000 to 8000 Hz) does NOT trigger BWE in V1.
    """
    features = AudioFeatures(
        sample_rate=48000,
        channels=2,
        duration_s=30.0,
        snr_estimate_db=36.0,
        click_rate_per_s=0.0,
        hf_rolloff_hz=7000.0,
    )
    recipe = route_features(features)
    assert len(recipe.stages) == 1
    assert recipe.stages[0].stage_name == "passthrough"


def test_router_bwe_bypassed_for_wideband() -> None:
    """
    Asserts that high-frequency rolloff >= 8000 Hz does not trigger BWE in V1.
    """
    features = AudioFeatures(
        sample_rate=48000,
        channels=2,
        duration_s=30.0,
        snr_estimate_db=36.0,
        click_rate_per_s=0.0,
        hf_rolloff_hz=9000.0,
    )
    recipe = route_features(features)
    assert len(recipe.stages) == 1
    assert recipe.stages[0].stage_name == "passthrough"


def test_router_bwe_capped_for_classical() -> None:
    """
    Asserts that BWE is disabled in V1 even on classical recordings with severe rolloff.
    """
    class MockAudioFeatures:
        def __init__(self, snr: float, centroid: float, crest: float, click_rate: float, rolloff: float):
            self.snr_estimate_db = snr
            self.spectral_centroid_hz = centroid
            self.crest_factor = crest
            self.click_rate_per_s = click_rate
            self.hf_rolloff_hz = rolloff

        def HasField(self, name: str) -> bool:  # noqa: N802
            if name == "snr_estimate_db":
                return self.snr_estimate_db is not None
            if name == "spectral_centroid_hz":
                return self.spectral_centroid_hz is not None
            if name == "click_rate_per_s":
                return self.click_rate_per_s is not None
            if name == "hf_rolloff_hz":
                return self.hf_rolloff_hz is not None
            return False

    classical_features = MockAudioFeatures(
        snr=36.0,
        centroid=1200.0,
        crest=18.0,
        click_rate=0.0,
        rolloff=3500.0,
    )
    recipe = route_features(classical_features)  # type: ignore[arg-type]

    assert len(recipe.stages) == 1
    assert recipe.stages[0].stage_name == "passthrough"


def test_router_bwe_unconditionally_disabled_in_v1() -> None:
    """
    CRITICAL V1 ROUTER TEST.
    Asserts that regardless of the hf_rolloff_hz value, bandwidth_extension
    is never added to the recipe in V1.
    """
    for rolloff in [1000.0, 3000.0, 5000.0, 7000.0]:
        features = AudioFeatures(
            sample_rate=48000,
            channels=2,
            duration_s=30.0,
            snr_estimate_db=36.0,
            click_rate_per_s=0.0,
            hf_rolloff_hz=rolloff,
        )
        recipe = route_features(features)
        assert len(recipe.stages) == 1
        assert recipe.stages[0].stage_name == "passthrough"


