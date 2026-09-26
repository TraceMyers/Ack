
calculate_friction_coefficient_for_constant_speed :: inline (acceleration: float) -> coef: float {
    return acceleration / context.physical_world.gravity;
}
