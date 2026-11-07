// components don't all have to subclass this,
// but it allows for owner lookup via get_owner()
Component_Base :: struct {
    owner: Gen_ID;
}

// the only entity type. to subclass the entity, add components to its table at runtime
// and create different component combinations. it's a grab bag.
Entity :: struct {
    using #as base: Component_Base;
    id: Gen_ID;
    flags: Entity_Flags;
    components: Table(*Type_Info, Component_Instance);
}

// Entity takes Transform like it takes any other component - through its table.
// non-Entity types can store a Transform as a member (like Camera does, and it must be 'using').
// if you do that, get_transform, get_position, get_orientation, and get_scale can all be used to
// get the respective transform property of that component, multiplied down the owner hierarchy
// e.g. entity -> entity -> entity -> mesh component.
Transform :: struct {
    position: Vector3;
    orientation: Quaternion;
    scale := Vector3.{1,1,1};
}

Transform_No_Scale :: struct {
    position: Vector3;
    orientation: Quaternion;
}

Input :: struct {
    using #as base: Component_Base;
    move: Vector2;
    received_move_input_last_physics_step: bool;
    last_nonzero_move_input: Vector2;

    look: Vector2i;
    look_smoothed: Vector2;
}

Camera :: struct {
    using #as base: Component_Base;
    using tform: Transform_No_Scale;
    using info: Camera_Info;

    translation_speed := 1.0;
    rotation_speed := 2.5;
    look_up_degree_limit := 85.0;

    free_fly_toggle: bool;
}

// field names are the lowercased type name. note that jai prints an alias as the type it aliases,
// so e.g. Physics_Body (:: Physics_Body_Base(void)) becomes 'physics_body_base' and
// Static_Mesh_Instance (:: Mesh_Instance) becomes 'mesh_instance'.
Component_Collection :: struct($types: []Type) {
    #insert -> string {
        builder: String_Builder;
        for type : types {
            print(*builder, "%: *#run types[%];\n", component_field_name(type), it_index);
        }
        return builder_to_string(*builder);
    }
}

// get one component of type T on entity or null
get_component :: (entity: *Entity, $T: Type) -> *T {
    inst := table_find_pointer(*entity.components, type_info(T));
    return ifx inst == null then cast(*T) null else cast(*T) inst.data;
}

// get a custom struct instance with pointers to whatever set of components you want 
// from the entity. e.g. collect_components(e, Transform, Input) returns a struct
// with anonymous type { transform: *Transform; input: *Input; }.
collect_components :: (entity: *Entity, $types: ..Type) -> Component_Collection(types) {
    collection: Component_Collection(types) = ---;
    #insert -> string {
        builder: String_Builder;
        for type : types {
            print(*builder, "collection.% = get_component(entity, #run types[%]);\n", component_field_name(type), it_index);
        }
        return builder_to_string(*builder);
    }
    return collection;
}

get_or_add_component :: (entity: *Entity, $T: Type) -> *T {
    inst, just_added := find_or_add(*entity.components, type_info(T));
    if just_added {
        inst.* = add_component(T, {entity_handle, entity.id});
    }
    return cast(*T) inst.data;
}

add_component :: (entity: *Entity, $T: Type) -> *T {
    inst, just_added := find_or_add(*entity.components, type_info(T));
    engine_check(just_added);
    inst.* = add_component(T, {entity_handle, entity.id});
    return cast(*T) inst.data;
}

remove_component :: (entity: *Entity, $T: Type, component_remove_depth := 0) {
    inst := get_component_instance(entity, type_info(T));
    remove_component(entity, inst, component_remove_depth);
}

remove_component :: (entity: *Entity, info: *Type_Info, component_remove_depth := 0) {
    inst := get_component_instance(entity, info);
    remove_component(entity, inst, component_remove_depth);
}

remove_component :: (entity: *Entity, component: *$T, component_remove_depth := 0) {
    inst := get_component_instance(entity, type_info(T));
    engine_check(inst.data == component);
    remove_component(entity, inst, component_remove_depth);
}

remove_component :: (entity: *Entity, inst: *Component_Instance, component_remove_depth := 0) {
    engine_check(component_remove_depth < MAX_RECURSION_DEPTH, "potential infinite recursion detected");
    if inst.ref.type_handle == entity_handle {
        destroy_entity(xx inst.data, component_remove_depth + 1);
    }
    remove_component(inst);
    table_remove(*entity.components, engine.components[inst.ref.type_handle].tinfo);
}

// get a component type-stripped. you can store *Type_Infos at runtime
// and get the component without knowing the type at compile time.
get_component_data :: inline (e: *Entity, info: *Type_Info) -> *void {
    inst := table_find_pointer(*e.components, info);
    return ifx inst == null then null else inst.data;
}

// get a pointer to the wrapper struct around each component
get_component_instance :: (entity: *Entity, info: *Type_Info) -> *Component_Instance {
    return table_find_pointer(*entity.components, info);
}

// if your component type has a 'using #as yadda: Component_Base;' field, 
// you can lookup the owner from the component. important if the
// component has a transform and you want to get the component's transform.
get_owner :: inline (component: *$T) -> *Entity {
    #if #run is_subclass_of(type_info(T), "Component_Base") {
        return get_entity(component.owner);
    } else return null;
}

get_transform :: (component: *$T, tform: *Transform) {
    owner := get_owner(component);

    if owner != null {
        get_transform(owner, tform);

        #if T == Entity {
            self_tform := get_component(component, Transform);
            tform.position    += rotate(self_tform.position, owner_tform.orientation);
            tform.orientation *= self_tform.orientation;
            tform.scale       *= self_tform.scale;
        } else {
            #if #exists(T.position) {
                tform.position += rotate(component.position, tform.orientation);
            }
            #if #exists(T.orientation) {
                tform.orientation *= component.orientation;
            }
            #if #exists(T.scale) {
                tform.scale *= component.scale;
            }
        }
    } else {
        #if T == Entity {
            self_tform := get_component(component, Transform);
            tform.* = self_tform.*;
        } else {
            tform.* = {};
        }
    }
}

get_transform_no_scale :: (component: *$T, tform: *Transform_No_Scale) {
    owner := get_owner(component);

    if owner != null {
        get_transform_no_scale(owner, tform);

        #if T == Entity {
            self_tform := get_component(component, Transform);
            tform.position    += rotate(self_tform.position, tform.orientation);
            tform.orientation *= self_tform.orientation;
        } else {
            #if #exists(T.position) {
                tform.position += rotate(component.position, tform.orientation);
            }
            #if #exists(T.orientation) {
                tform.orientation *= component.orientation;
            }
        }
    } else {
        #if T == Entity {
            self_tform := get_component(component, Transform);
            tform.position = self_tform.position;
            tform.orientation = self_tform.orientation;
        } else {
            tform.* = {};
        }
    }
}

get_position :: (component: *$T) -> Vector3 
#modify { 
    return T != Physics_Body;
} {
    tform: Transform_No_Scale = ---;
    get_transform_no_scale(component, *tform);
    return tform.position;
}

get_orientation :: (component: *$T) -> Quaternion {
    owner := get_owner(component);
    orientation: Quaternion = ---;

    if owner != null {
        orientation = get_orientation(owner);

        #if T == Entity {
            self_tform := get_component(component, Transform);
            orientation *= self_tform.orientation;
        } else #if #exists(T.orientation) {
            orientation *= component.orientation;
        }
    } else {
        #if T == Entity {
            self_tform := get_component(component, Transform);
            orientation = self_tform.orientation;
        } else {
            orientation = {};
        }
    }

    return orientation;
}

get_scale :: (component: *$T) -> Vector3 {
    owner := get_owner(component);
    scale: Vector3 = ---;

    if owner != null {
        scale = get_scale(owner);

        #if T == Entity {
            self_tform := get_component(component, Transform);
            scale *= self_tform.scale;
        } else #if #exists(T.scale) {
            scale *= component.scale;
        }
    } else {
        #if T == Entity {
            self_tform := get_component(component, Transform);
            scale = self_tform.scale;
        } else {
            scale = {1,1,1};
        }
    }

    return scale;
}

get_axes :: inline (component: *$T) -> x: Vector3, y: Vector3, z: Vector3 {
    x, y, z: Vector3 = ---;
    calculate_axes(get_orientation(component), *x, *y, *z);
    return x, y, z;
}

