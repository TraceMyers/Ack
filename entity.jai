
Entity_Ref :: #type,isa Component_Ref;

Entity_Flags :: enum u64 {

}

Entity :: struct {
    id: Gen_ID;
    entity_flags: Entity_Flags;
    components: Table(*Type_Info, Component_Instance);
}

Transform :: struct {
    position: Vector3;
    orientation: Quaternion;
    scale := Vector3.{1,1,1};
}

make_entity :: () -> *Entity {
    return add_component(Entity, null_entity_ref());
}

make_spatial_entity :: () -> *Entity {
    e := make_entity();
    get_or_add_component(e, Transform);
    return e;
}

get_entity :: (id: Gen_ID) -> *Entity {
    return get_component({entity_handle, id}, Entity);
}

get_entity :: (ref: Entity_Ref) -> *Entity {
    engine_check(ref.handle == entity_handle);
    return get_component(ref, Entity);
}

get_ref :: (e: *Entity) -> Entity_Ref {
    return {entity_handle, e.id};
}

null_entity_ref :: inline () -> Entity_Ref {
    return {entity_handle, {}};
}

get_component_data :: inline (e: *Entity, info: *Type_Info) -> *void {
    return cast(*T) e.components[info].data;
}

get_component :: inline (e: *Entity, $T: Type) -> *T {
    return cast(*T) get_component(e, type_info(T));
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
    return (T*) inst.data;
}

add_component :: (entity: *Entity, $T: Type) -> *T {
    inst, just_added := find_or_add(*entity.components, type_info(T));
    engine_check(just_added);
    inst.* = add_component(T, {entity_handle, entity.id});
    return (T*) inst.data;
}

remove_component :: (entity: *Entity, $T: Type) {
    remove_component(entity, type_info(T));
}

remove_component :: (entity: *Entity, info: *Type_Info) {
    inst := get_component_instance(entity, info);
    remove_component(inst);
    table_remove(*entity.components, info);
}
