if (mesh_inst.specialization.flags != 0) {
    int has_flag = mesh_inst.specialization.flags & 0x1;
    if (has_flag != 0) {
        if (mesh_inst.specialization.flash_rate > 0) {
            float flash_value = (sin((frame.time - mesh_inst.specialization.flash_begin_time) * mesh_inst.specialization.flash_rate * 2) + 1) * 0.5 * mesh_inst.specialization.flash_value;
            add_color.rgb = vec3(flash_value, flash_value, flash_value);
        } else if (mesh_inst.specialization.flash_rate == 0) {
            float flash_value = mesh_inst.specialization.flash_value;
            add_color.rgb = vec3(flash_value, flash_value, flash_value);
        }
    }
    tint.rgb = mesh_inst.specialization.tint;
}
