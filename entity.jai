
Entity_Ref :: #type,isa Component_Ref;

Entity_Flags :: enum u64 {

}

Entity :: struct {
    id: Gen_ID;
    entity_flags: Entity_Flags;
    components: Table(*Type_Info, Component_Instance);
}

Transform :: struct {
    position:    Vector3;
    orientation: Quaternion;
    scale := Vector3.{1,1,1};
}

make_entity :: () -> *Entity {
    return add_component(Entity, null_entity_ref());
}

make_spatial_entity :: () -> *Entity {
    e := make_entity();
    find_or_add_component(e, Transform);
    return e;
}

get_entity :: (ref: Entity_Ref) -> *Entity {
    engine_check(ref.handle == entity_handle);
    return get_component(ref, Entity);
}

get_entity_ref :: (e: *Entity) -> Entity_Ref {
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

find_component :: (entity: *Entity, $T: Type) -> *T {
    inst := table_find(*entity.components, type_info(T));
    return ifx inst == null then cast(*T) null else cast(*T) inst.data;
}

find_or_add_component :: (entity: *Entity, $T: Type) -> *T {
    inst, just_added := find_or_add(*entity.components, type_info(T));
    if just_added {
        inst.* = add_component(T, {entity_handle, entity.id});
    }
    return (T*) inst.data;
}

