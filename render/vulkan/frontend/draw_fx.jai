// per-instance tweaks to how a mesh is shaded. mirrored by Draw_FX in
// shaders/src/header.glsl, which mesh_draw_fx.glsl applies.
Draw_FX :: struct {
    flags: Draw_FX_Flags;
    flash: FX_Flash;
    tint:  FX_Tint;
}

FX_Flash :: struct {
    rate: float = -1; // < 0: no flash. 0: constant brightening by value.
    value: float;
    begin_time: float;
}

FX_Tint :: struct {
    using color: Color3f = .{1, 1, 1};
}

// one flag per Draw_FX field, named the same, but in upper case. e.g. "flash" has flag "FLASH"
Draw_FX_Flags :: enum_flags u32 {
    #insert -> string {
        flags_builder: String_Builder;
        fx_type := cast(*Type_Info_Struct) type_info(Draw_FX);
        for member : fx_type.members {
            if member.name == "flags" {
                continue;
            }
            print(*flags_builder, "%;\n", to_upper(member.name));
        }
        return builder_to_string(*flags_builder);
    }
}

add_draw_fx :: (inst: *Mesh_Instance, draw_fx: $T) {
    meshes := *engine.renderer.meshes;
    if inst.draw_fx == -1 {
        inst.draw_fx = xx pool_borrow(*meshes.draw_fxs);
    }
    params := *meshes.draw_fxs[inst.draw_fx];

    #insert -> string {
        builder: String_Builder;
        fx_type := cast(*Type_Info_Struct) type_info(Draw_FX);
        for member : fx_type.members {
            if member.name == "flags" {
                continue;
            }
            if (cast(*Type) *member.type).* == T {
                print(*builder,            
                #string HERE
                    params.% = draw_fx;
                    params.flags |= .%;
                HERE,
                    member.name,
                    to_upper(member.name)
                );
                return builder_to_string(*builder);
            }
        }
        assert(false); // T not in Draw_FX
        return "";
    }
}

remove_draw_fx :: (inst: *Mesh_Instance, $T: Type) {
    if inst.draw_fx == -1 {
        return;
    }
    meshes := *engine.renderer.meshes;
    params := *meshes.draw_fxs[inst.draw_fx];

    #insert -> string {
        builder: String_Builder;
        fx_type := cast(*Type_Info_Struct) type_info(Draw_FX);
        for member : fx_type.members {
            if (cast(*Type) *member.type).* == T {
                print(*builder, "params.flags &= ~.%;", to_upper(member.name));
                return builder_to_string(*builder);
            }
        }
        assert(false); // T not in Draw_FX
        return "";
    }

    if params.flags == 0 {
        pool_return(*meshes.draw_fxs, inst.draw_fx);
        inst.draw_fx = -1;
    }
}

get_draw_fx :: inline (inst: *Mesh_Instance) -> *Draw_FX {
    if inst.draw_fx == -1 {
        return null;
    }
    return *engine.renderer.meshes.draw_fxs[inst.draw_fx];
}

