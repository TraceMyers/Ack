pause_physics :: () {
    engine.physical_world.step_state = .PAUSED;
}

unpause_physics :: () {
    engine.physical_world.step_state = .RUN_PHYSICS;
}
