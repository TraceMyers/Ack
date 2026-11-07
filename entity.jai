Entity_Ref :: #type,isa Component_Ref;

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

make_entity :: (owner: *Entity = null) -> *Entity {
    inst: Component_Instance;
    if owner == null {
        inst = add_component(Entity, {});
    } else {
        owner_ref := Entity_Ref.{entity_handle, owner.id};
        add_component(owner, Entity);
        inst = get_component_instance(owner, type_info(Entity));
    }
    e := cast(*Entity) inst.data;
    e.id = inst.ref.id;
    return e;
}

destroy_entity :: (e: *Entity, component_remove_depth := 0) {
    engine_check(component_remove_depth < MAX_RECURSION_DEPTH, "potential infinite recursion detected");

    // if this is is a top-level destroy_entity call (not being called in the middle 
    // of a chain of remove_component calls), and this entity is owned by another entity,
    // then reroute through remove_component(parent, self) so that the parent
    // can remove this entity from its table.
    if component_remove_depth == 0 {
        owner := get_owner(e);
        if owner != null {
            remove_component(owner, e, component_remove_depth + 1);
            return;
        }
    }

    for *e.components {
        remove_component(e, it, component_remove_depth + 1);
    }
    deinit(*e.components);

    inst := Component_Instance.{xx e, {entity_handle, e.id}};
    remove_component(*inst);
}

make_spatial_entity :: (owner: *Entity = null) -> *Entity {
    e := make_entity(owner);
    add_component(e, Transform);
    return e;
}

make_physical_entity :: (physics_template: string, owner: *Entity = null) -> *Entity {
    e := make_spatial_entity(owner);
    add_component(e, Physics_Body);
    init_physics_body(e, physics_template);
    return e;
}

make_physical_entity_with_input :: (physics_template: string, owner: *Entity = null) -> *Entity {
    e := make_physical_entity(owner);
    add_component(e, Input);
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

get_ref :: inline (e: *Entity) -> Entity_Ref {
    return {entity_handle, e.id};
}

null_entity_ref :: inline () -> Entity_Ref {
    return {entity_handle, {}};
}

is_null :: inline (id: Gen_ID) -> bool {
    return id == Gen_ID.{};
}

queue_destroy_entity :: (entity: *Entity) {
    if (entity.flags & .MARKED_FOR_DESTRUCTION) == 0 {
        array_add(*engine.entities_queued_for_destruction, entity.id);
        entity.flags |= .MARKED_FOR_DESTRUCTION;
    }
}

execute_destroy_entities :: () {
    for engine.entities_queued_for_destruction {
        e := get_entity(it);
        engine_check((e.flags & .MARKED_FOR_DESTRUCTION) != 0);
        destroy_entity(e);
    }
    array_reset_keeping_memory(*engine.entities_queued_for_destruction);
}
