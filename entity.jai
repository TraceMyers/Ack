Entity :: struct {
    id: Gen_ID;
    flags: Entity_Flags;
    components: Table(*Type_Info, Component_Instance);
}

Entity_Ref :: #type,isa Component_Ref;

Transform :: struct {
    position: Vector3;
    orientation: Quaternion;
    scale := Vector3.{1,1,1};
}

Entity_Flags :: enum_flags {
    MARKED_FOR_DESTRUCTION;

    #insert -> string {
        builder: String_Builder;    
        for flag : ENTITY_FLAGS {
            print(*builder, "%;\n", flag);
        }
        return builder_to_string(*builder);
    }
}

make_entity :: () -> *Entity {
    inst := add_component(Entity, null_entity_ref());
    e := cast(*Entity) inst.data;
    e.id = inst.ref.id;
    return e;
}

destroy_entity :: (e: *Entity) {
    for * e.components {
        remove_component(it);
    }
    deinit(*e.components);

    inst: Component_Instance;
    inst.data = e;
    inst.ref = {entity_handle, e.id};
    remove_component(*inst);
}

make_spatial_entity :: () -> *Entity {
    e := make_entity();
    get_or_add_component(e, Transform);
    return e;
}

get_entity :: (id: Gen_ID) -> *Entity {
    return get_component({entity_handle, id}, Entity);
}

// returns null for a null ref (id.index < 0), including a default-initialized one
get_entity :: (ref: Entity_Ref) -> *Entity {
    engine_check(ref.type_handle == entity_handle || ref.id.index < 0);
    return get_component(ref, Entity);
}

get_ref :: (e: *Entity) -> Entity_Ref {
    return {entity_handle, e.id};
}

null_entity_ref :: inline () -> Entity_Ref {
    return {entity_handle, {}};
}

get_component_data :: inline (e: *Entity, info: *Type_Info) -> *void {
    inst := table_find_pointer(*e.components, info);
    return ifx inst == null then null else inst.data;
}

get_component_instance :: (entity: *Entity, info: *Type_Info) -> *Component_Instance {
    return table_find_pointer(*entity.components, info);
}

get_component :: (entity: *Entity, $T: Type) -> *T {
    inst := table_find_pointer(*entity.components, type_info(T));
    return ifx inst == null then cast(*T) null else cast(*T) inst.data;
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

remove_component :: (entity: *Entity, $T: Type) {
    remove_component(entity, type_info(T));
}

remove_component :: (entity: *Entity, info: *Type_Info) {
    inst := get_component_instance(entity, info);
    remove_component(inst);
    table_remove(*entity.components, info);
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

queue_destroy_entity :: (entity: *Entity) {
    if (entity.flags & .MARKED_FOR_DESTRUCTION) == 0 {
        array_add(*engine.entities_queued_for_destruction, entity.id);
        entity.flags |= .MARKED_FOR_DESTRUCTION;
    }
}

execute_destroy_entities :: () {
    for engine.entities_queued_for_destruction {
        // get the entity type enum and specialize destroy_entity for the given type.
        destroy_entity(get_entity(it));
    }
    array_reset_keeping_memory(*engine.entities_queued_for_destruction);
}
