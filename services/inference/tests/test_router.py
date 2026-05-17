"""
Unit tests for the intelligence router.
Checks feature-to-recipe mappings.
"""
from sangeet.v1.restoration_pb2 import AudioFeatures
from sangeet_inference.router import route_features

def test_router_returns_passthrough_recipe() -> None:
    """
    Asserts that route_features returns a RestorationRecipe containing exactly the passthrough stage.
    """
    features = AudioFeatures(
        sample_rate=48000,
        channels=2,
        duration_s=30.0,
        snr_estimate_db=45.0,
        hum_50hz_present=False,
        hum_60hz_present=False
    )
    
    recipe = route_features(features)
    
    # Recipe must contain exactly one stage
    assert len(recipe.stages) == 1
    
    stage_invocation = recipe.stages[0]
    assert stage_invocation.stage_name == "passthrough"
    assert stage_invocation.strength == 1.0
