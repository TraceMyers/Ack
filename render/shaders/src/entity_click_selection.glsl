if (frame.running_entity_select && ivec2(gl_FragCoord.xy) == frame.entity_select_pixel) {
    uint64_t depth_and_id = (uint64_t(floatBitsToUint(gl_FragCoord.z)) << 32) | uint64_t(mesh_inst.entity_id);
    atomicMax(frame_rw.selected_entity_id, depth_and_id);
}
