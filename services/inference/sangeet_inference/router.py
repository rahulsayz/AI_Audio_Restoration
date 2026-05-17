"""
Sangeet AI Intelligence Router.
Decides the sequence of restoration stages and strengths based on input features.
"""
from sangeet.v1.restoration_pb2 import (
    AudioFeatures,
    RestorationRecipe,
    StageInvocation,
    StageParams,
)


def route_features(features: AudioFeatures) -> RestorationRecipe:
    """
    Decides the correct pipeline stages and strengths based on cultural audio features.

    Args:
        features: AudioFeatures protobuf object.

    Returns:
        RestorationRecipe protobuf object specifying the ordered processing chain.
    """
    recipe = RestorationRecipe()

    # 1. Determine dehum strength based on hum detection
    dehum_strength = 0.0
    if features is not None:
        hum_50 = getattr(features, "hum_50hz_present", False)
        hum_60 = getattr(features, "hum_60hz_present", False)
        if hum_50 or hum_60:
            dehum_strength = 0.5
    else:
        dehum_strength = 0.5

    if dehum_strength > 0.0:
        dehum_params = StageParams()
        dehum_params.params["strength"] = dehum_strength

        dehum_invocation = StageInvocation(
            stage_name="dehum", strength=dehum_strength, params=dehum_params
        )
        recipe.stages.append(dehum_invocation)

    # 2. Determine deep_filter_net strength based on SNR estimate
    strength = 0.0
    if features is not None and features.HasField("snr_estimate_db"):
        snr = features.snr_estimate_db
        if snr < 15.0:
            strength = 0.7
        elif 15.0 <= snr < 25.0:
            strength = 0.5
        elif 25.0 <= snr < 35.0:
            strength = 0.3
        else:  # snr >= 35.0
            strength = 0.0

        # Apply is_classical heuristic to cap the strength at 0.5 for cultural fidelity.
        # Heuristic for V1: is_classical = (spectral_centroid_hz < 1500 AND crest_factor > 15 dB)
        is_classical = getattr(features, "is_classical", False)
        spectral_centroid = getattr(features, "spectral_centroid_hz", None)
        crest_factor = getattr(features, "crest_factor", None)

        if not is_classical and spectral_centroid is not None and crest_factor is not None:
            if spectral_centroid < 1500.0 and crest_factor > 15.0:
                is_classical = True

        if is_classical:
            # Cap strength at 0.5 for classical music to preserve subtle ornamentation/resonance
            strength = min(strength, 0.5)
    else:
        # Unknown/missing SNR -> strength 0.0 (skip)
        strength = 0.0

    if strength > 0.0:
        params = StageParams()
        params.params["strength"] = strength

        invocation = StageInvocation(
            stage_name="deep_filter_net", strength=strength, params=params
        )
        recipe.stages.append(invocation)

    # 3. Determine declick strength based on click_rate_per_s
    declick_strength = 0.0
    if features is not None and features.HasField("click_rate_per_s"):
        click_rate = features.click_rate_per_s
        if click_rate > 10.0:
            declick_strength = 0.8
        elif 5.0 <= click_rate <= 10.0:
            declick_strength = 0.5
        elif 1.0 <= click_rate < 5.0:
            declick_strength = 0.3
        elif 0.0 < click_rate < 1.0:
            declick_strength = 0.1
        else:  # click_rate == 0.0
            declick_strength = 0.0
    elif features is not None:
        # Default-on fallback if click_rate_per_s is not present / omitted
        declick_strength = 0.5
    else:
        declick_strength = 0.0

    if declick_strength > 0.0:
        declick_params = StageParams()
        declick_params.params["strength"] = declick_strength
        declick_params.params["threshold_multiplier"] = 5.0

        declick_invocation = StageInvocation(
            stage_name="declick", strength=declick_strength, params=declick_params
        )
        recipe.stages.append(declick_invocation)

    # 4. Determine bandwidth_extension strength based on hf_rolloff_hz
    # NOTE: In V1, we unconditionally disable bandwidth_extension (bwe_strength = 0.0).
    # This is a deliberate design decision to prevent the stage from running on clean
    # audio. The V1 feature 'hf_rolloff_hz' measures energy concentration rather than
    # the actual high-frequency bandwidth cutoff. Consequently, clean wideband audio
    # was incorrectly routed to bandwidth extension, destroying natural high-frequency
    # details and replacing them with synthetic harmonics.
    # We keep the logic intact but bypass it here, pending a research-grade bandwidth-cutoff
    # detector and an opt-in/opt-out user interface in Phase 2.
    bwe_strength = 0.0

    if bwe_strength > 0.0:
        bwe_params = StageParams()
        bwe_params.params["strength"] = bwe_strength
        bwe_params.params["cutoff_frequency_hz"] = features.hf_rolloff_hz

        bwe_invocation = StageInvocation(
            stage_name="bandwidth_extension", strength=bwe_strength, params=bwe_params
        )
        recipe.stages.append(bwe_invocation)

    # 5. Fallback to passthrough if no active stages are selected
    if len(recipe.stages) == 0:
        invocation = StageInvocation(
            stage_name="passthrough", strength=1.0, params=None
        )
        recipe.stages.append(invocation)

    return recipe
