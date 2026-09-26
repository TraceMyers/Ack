pause_physics :: () {
    context.physical_world.step_state = .PAUSED;
}

unpause_physics :: () {
    context.physical_world.step_state = .RUN_PHYSICS;
}
