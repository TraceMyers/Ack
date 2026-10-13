
calculate_friction_coefficient_for_constant_speed :: inline (acceleration: float) -> coef: float {
    return acceleration / engine.physical_world.gravity;
}
