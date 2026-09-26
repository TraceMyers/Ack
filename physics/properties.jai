Physics_Properties :: struct {
    mass:              float = 1.0;
    pointing_friction: float = 0.5;
    slide_friction:    float = 0.5;
    move_input_acceleration: float;

    // auto-set
    inv_mass:          float = 1.0;

    call_per_step: (*Physics_Body);
}

set_property :: (in_body: *Physics_Body_Base, $property_name: string, new_value: $T) 
#modify {
    // intercept ints and change them to floats so you can pass values like '1' for 
    // float properties rather than '1.0'. minor convenience.
    if (cast(*Type_Info) T).type == .INTEGER {
        T = float;
    }
    return true;
} {
    #assert(property_name != "inv_mass");
    body := cast(*Physics_Body_Internal) in_body;

    PROPERTY_OFFSET :: #run -> int {
        props_tinfo := type_info(Physics_Properties);
        for member : props_tinfo.members {
            if member.name == property_name {
                member_type := (cast(*Type) *member.type).*;
                assert(member_type == T, "in Physics_Properties, % has type %, but a value of type % was passed to set_property", property_name, member_type, T);
                return member.offset_in_bytes;
            }
        }
        assert(false, "found no physics property with the name %", property_name);
        return 0;
    }

    make_properties_unique(body);
    property_ptr := cast(*T) ((cast(*u8) body.properties) + PROPERTY_OFFSET);
    property_ptr.* = new_value;

    #if property_name == "mass" {
        physics_check(.HIGH, body.mass > 0);
        body.inv_mass = 1.0 / body.mass;
    }
}

get_property :: inline (in_body: *Physics_Body_Base, $property_name: string) -> float {
    body := cast(*Physics_Body_Internal) in_body;
    return #insert #run tprint("body.properties.%;", property_name);
}

// if PHYSICS_VALIDATION_LEVEL > 0 (module param) is true, this can be called
// any time by the user to make a point in time they know the template properties
// to be valid.
debug__mark_template_properties_valid :: () {
    #if PHYSICS_VALIDATION_LEVEL > 0 {
        using context.physical_world;
        physics_check(.LOW, body_templates.values.count == debug_template_properties.count);
        for 0..body_templates.values.count-1 {
            debug_template_properties[it] = body_templates.values[it].properties;
        }
    }
}

// if PHYSICS_VALIDATION_LEVEL > 0 (module param) is true, this can be called
// any time by the user to make sure they aren't invalidating their own templates. it
// will also be called automatically during the physics update.
debug__validate_template_properties :: () {
    #if PHYSICS_VALIDATION_LEVEL > 0 {
        using context.physical_world;
        physics_check(.LOW, body_templates.values.count == debug_template_properties.count);
        for 0..body_templates.values.count-1 {
            physics_check(.LOW, body_templates.values[it].properties == debug_template_properties[it]);
        }
    }
}

is_unique :: inline (properties: *Physics_Properties) -> unique: bool, unique_index: s32 {
    using context.physical_world;
    unique_index := properties - unique_properties.items.data;
    if unique_index >= 0 && unique_index < unique_properties.items.count {
        physics_check(.MEDIUM, is_pool_item_in_use(*unique_properties, unique_index));
        return true, xx unique_index;
    }
    physics_check(.MEDIUM, is_data_from_template(xx properties));
    return false, -1;
}

make_properties_unique :: inline (in_body: *Physics_Body_Base) {
    body := cast(*Physics_Body_Internal) in_body;
    if !is_unique(body.properties) {
        new_properties_index := pool_borrow(*context.physical_world.unique_properties);
        new_properties := *context.physical_world.unique_properties[new_properties_index];
        new_properties.* = body.properties.*;
        body.properties = new_properties;
    }
}

// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.
