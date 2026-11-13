#load "component.jai";
#load "component_storage.jai";
#load "component_loops.jai";
#load "example.jai";

Entity_ID :: #type,isa Component_ID;

// entities are components. in other words, Component is the base object.
// entities are then defined as components that can own other components (including other entities).
Entity :: struct {
    using #as component_base: Scalable_Spatial_Component;
    flags: Entity_Flags;
    id: Entity_ID;
    component_allocations: [..]Component_Allocation;
}

Component_Allocation :: struct {
    id: Component_ID;
    offset_to_pointer: s32;
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

// all child transforms become relative after attachment. this rule determines
// how a transform field of a child is interpreted at time of attachment. 
Transform_Attach_Rule :: enum u8 {
    // the child transform field is recalculated so that it remains unchanged in world space
    CALCULATE_RELATIVE_FROM_WORLD;
    // the child transform field is interpreted as already being relative to the parent
    INTEPRET_CURRENT_AS_RELATIVE;
    // erase the child transform field (takes whatever the parent has.)
    USE_PARENT;
}

Transform_Attach_Ruleset :: struct {
    position_rule: Transform_Attach_Rule;
    orientation_rule: Transform_Attach_Rule;
    scale_rule: Transform_Attach_Rule;
}

make_entity :: inline ($E: Type) -> *E {
    return xx make_entity_get_instance(T).data;
}

make_entity_get_instance :: inline ($E: Type) -> Component_Instance {
    #assert(is_subclass_of(E, "Entity"));
    inst := add_component(E, {});
    e := cast(*Entity) inst.data;
    e.id = inst.id;
    return inst;
}

destroy_entity :: (entity: *Entity, depth := 0) {
    engine_check(depth < MAX_RECURSION_DEPTH, "potential infinite recursion detected");

    // if this is is a top-level destroy_entity call (not being called in the middle 
    // of a chain of remove_component calls), and this entity is owned by another entity,
    // then reroute through remove_component(parent, self) so that the parent
    // can remove this entity from its table.
    if component_remove_depth == 0 {
        parent := get_parent(entity);
        if parent != null {
            detach_component(parent, entity, false);
            return;
        }
    }

    for allocation : entity.component_allocations {
        component_ptr := (cast(**Component) (cast(*u8) entity + allocation.offset_to_pointer)).*;
        component_storage := *engine.components[allocation.id.type_handle];
        if component_storage.component_is_entity {
            destroy_entity(xx component_ptr, depth + 1);
        } else {
            remove_component({component_ptr, allocation.id});
        }
    }

    remove_component({entity, entity.id});
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
    e := make_physical_entity(physics_template, owner);
    add_component(e, Input);
    return e;
}

is_entity :: inline (id: Component_ID, $check_null := true) -> bool {
    #if check_null {
        if is_null(id) {
            return false;
        }
    }
    component_storage := *engine.components[id.type_handle];
    return component_storage.component_is_entity;
}

get_entity :: (id: Entity_ID) -> *Entity {
    if is_null(id) {
        return null;
    }
    engine_check(is_entity(id, false));
    return cast(*Entity) get_component_data(component_storage, id.index, id.generation);
}

get_entity :: (id: Entity_ID, $T: Type) -> *T {
    base_entity := get_entity(id);
    return cast_entity(base_entity, T);
}

cast_entity :: inline (entity: *Entity, $T: Type, $exact_match := false) -> *T {
    #assert(is_subclass_of(T, "Entity", false));
    return cast_component(entity, T, exact_match);
}

cast_entity_checked :: inline (entity: *Entity, $T: Type, $exact_match := false) -> *T {
    #assert(is_subclass_of(T, "Entity", false));
    return cast_component_checked(entity, T, exact_match);
}

null_entity_id :: inline () -> Entity_ID {
    return .{};
}

is_null :: inline (id: Entity_ID) -> bool {
    return id.index < 0;
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

// allocate and track component of type C on entity of type E. the component field on E
// must be *C, and ptr_on_entity is a pointer to that pointer field.
// My_Entity :: struct { using #as base: Entity; stuff: *Stuff; }
// e := make_entity(My_Entity);
// add_component(e, *e.stuff);
// can be used to make a new entity, since entities are components.
add_component :: (entity: *$E/Entity, ptr_on_entity: **$C/Component) {
    COMPONENT_IS_ENTITY :: #run is_subclass_of(C, "Entity");
    inst := ifx COMPONENT_IS_ENTITY then make_entity_get_inst(C) else add_component(C, {});
    attach_component(entity, ptr_on_entity, inst.id);
}

// deallocate and untrack component of type C on entity of type E. symmetric bookend
// to add_component. automatically called during destroy entity for each
// still-allocated component.
remove_component :: (entity: *$E/Entity, ptr_on_entity: **$C/Component) {
    COMPONENT_IS_ENTITY :: #run is_subclass_of(C, "Entity");

    component := ptr_on_entity.*;
    if COMPONENT_IS_ENTITY {
        destroy_entity(xx component);
    } else {
        component_id := detach_component(e, ptr_on_entity, false);
        remove_component({ptr_on_entity.*, component_id});
    }
}

// pass ownership of a component from one entity to another.
transfer_component :: (entity_a: *$E1/Entity, ptr_on_entity_a: **$C/Component, entity_b: *$E2/Entity, ptr_on_entity_b: **C) {
    component_id := detach_component(entity_a, ptr_on_entity_a);
    attach_component(entity_b, ptr_on_entity_b, component_id);
}

// attach a component to a new parent. (component must be allocated + have no parent)
// 'rules' determines how the component's transform is interpreted during attachment.
// after attachment, all component transforms are relative to their parent's.
attach_component :: (entity: *$E/Entity, ptr_on_entity: **$C/Component, component_id: Component_ID, rules := Transform_Attach_Ruleset.{}) {
    engine_check(ptr_on_entity.* == null);

    component := get_component(component_id, C);
    engine_check(component != null);
    engine_check(get_parent(component) == null);

    ptr_offset := get_component_pointer_offset_validated(entity, pointer_on_entity);
    ptr_on_entity.* = component;
    component.parent = entity.id;

    array_add(*entity.component_allocations, {component_id, xx ptr_offset});

    IS_SPATIAL :: #run (is_subclass_of(C, "Spatial_Component");
    IS_SCALABLE_SPATIAL :: #run (is_subclass_of(C, "Scalable_Spatial_Component");

    #if #run IS_SPATIAL || IS_SCALABLE_SPATIAL {
        parent_transform: Transform;
        if rules.position_rule == .CALCULATE_RELATIVE_FROM_WORLD || rules.orientation_rule == .CALCULATE_RELATIVE_FROM_WORLD || rules.scale_rule == .CALCULATE_RELATIVE_FROM_WORLD {
            get_transform(get_parent(component), *parent_transform);
        }

        if rules.position_rule == {
        case .CALCULATE_RELATIVE_FROM_WORLD;
            // get the current world offset and un-rotate it, so that it will rotate back into
            // this world position when the parent orientation is applied.
            world_offset := component.transform.position - parent_transform.position;
            inverse_parent_rotation := conjugate(parent_transform.orientation);
            component.transform.position = rotate(world_offset, inverse_parent_rotation);
        case .USE_PARENT;
            component.transform.position = {};
        }

        if rules.orientation_rule == {
        case .CALCULATE_RELATIVE_FROM_WORLD;
            component.transform.orientation = rotation_from_a_to_b(parent_transform.orientation, component.transform.orientation);
        case .USE_PARENT;
            component.transform.orientation = {};
        }

        #if IS_SCALABLE_SPATIAL {
            if rules.scale_rule == {
            case .CALCULATE_RELATIVE_FROM_WORLD;
                component.transform.scale /= parent_transform.scale;
            case .USE_PARENT;
                component.transform.scale = {};
            }
        }
    }
}

// detach a component from its parent. (component must be allocated + have parent)
// transform_relative_to_world puts the component's transform back into world space.
detach_component :: (entity: *$E/Entity, ptr_on_entity: **$C/Component, transform_relative_to_world := true) -> Component_ID {
    engine_check(ptr_on_entity.* != null);
    ptr_offset := get_component_pointer_offset_validated(entity, pointer_on_entity);

    component := ptr_on_entity.*;
    engine_check(component.parent == entity.id);

    if transform_relative_to_world {
        IS_SPATIAL :: #run (is_subclass_of(C, "Spatial_Component");
        IS_SCALABLE_SPATIAL :: #run (is_subclass_of(C, "Scalable_Spatial_Component");

        #if IS_SPATIAL {
            world_transform: Transform_No_Scale;
            get_transform_no_scale(component, *world_transform);
            component.transform = world_transform;
        } else #if IS_SCALABLE_SPATIAL {
            world_transform: Transform;
            get_transform(component, *world_transform);
            component.transform = world_transform;
        }
    }

    found_allocation: bool;
    component_id: Component_ID;
    for entity.component_allocations {
        if it.offset_to_pointer == ptr_offset {
            component_id = it.id;
            found_allocation = true;
            remove it;
            break;
        }
    }
    engine_check(found_allocation);
    engine_check(engine.components[component_id.type_handle].tinfo == type_info(C)]);

    ptr_on_entity.* = null;
    component.parent = {};

    return component_id;
}

// find first allocated component (not necessarily first pointer on entity) of type *C.
// returns null if none exist.
get_entity_component :: inline (entity: *Entity, $C/Component: Type) -> *C {
    return xx get_entity_component(entity, type_info(C));
}

// find first allocated component (not necessarily first pointer on entity) of type *C,
// given tinfo is the type info of component type C. returns null if none exist.
get_entity_component :: (entity: *Entity, tinfo: *Type_Info) -> *void {
    for allocation : entity.component_allocations {
        component_storage := *engine.components[allocation.id.type_handle];
        if component_storage.tinfo == tinfo {
            pointer_to_component_field := (cast(*u8) entity) + allocation.offset_to_pointer;
            voidptr := (cast(**void) pointer_to_component_field).*;
            return voidptr;
        }
    }
    return null;
}

// returns temp-allocated array of all all allocated components of type *C.
// unallocated components are not included.
get_entity_components :: inline (entity: *Entity, $C/Component: Type) -> []*C {
    return cast,force([]*C) get_entity_components(entity, type_info(C));
}

// returns temp-allocated array of all all allocated components of type *C, given tinfo is
// the type info of component type C. unallocated components are not included.
get_entity_components :: (entity: *Entity, tinfo: *Type_Info) -> []*void {
    components := make_dynamic_array(*void, min(entity.component_allocations.count, 16),, temp);
    for allocation : entity.component_allocations {
        component_storage := *engine.components[allocation.id.type_handle];
        if component_storage.tinfo == tinfo {
            pointer_to_component_field := (cast(*u8) entity) + allocation.offset_to_pointer;
            voidptr := (cast(**void) pointer_to_component_field).*;
            // if the component is allocated, a null pointer means a gnome stole your data.
            // this codebase does not abide gnomish mischief.
            engine_check(voidptr != null);
            array_add(*components, voidptr);
        }
    }
    return components;
}

// get the first pointer on the specific entity type E to component type C.
// note that this may give a different result than get_entity_component.
// returns the pointer regardless of allocatedness/validity. so, a null pointer
// can either mean that the first pointer of type *C on 'entity' is null, or
// it can mean that no *C exists on type E.
get_component :: (entity: *$E/Entity, $C/Component: Type) -> *C {
    OFFSETS :: #run collect_offsets(type_info(E), type_info(*C));
    #if OFFSETS.count > 0 {
        return (cast(**C) (cast(*u8) entity + OFFSETS[0])).*;
    } else {
        return null;
    }
}

// get a temp-allocated array of all non-null pointers to components of type C
// on entity of type E.
get_components :: (entity: *$E/Entity, $C/Component: Type) ->[]*C {
    OFFSETS :: #run collect_offsets(type_info(E), type_info(*C));
    components: []*C = ---;
    #if OFFSETS.count > 0 {
        components = make_static_array(*C, OFFSETS.count,, temp);
        non_null_count: int;
        for OFFSETS {
            ptr := (cast(**C) (cast(*u8) entity + OFFSETS[it])).*;
            if ptr != null {
                components[it] = ptr;
                non_null_count += 1;
            }
        }
        components.count = non_null_count;
    } else {
        components.data = null;
        components.count = 0;
    }
    return components;
}

#scope_file

get_component_pointer_offset_validated :: (entity: *$E/Entity, ptr_on_entity: **$T) -> int {
    #insert -> string {
        offsets := collect_offsets(type_info(E), type_info(*T));
        builder: String_Builder;
        print(*builder, "VALID_OFFSETS :: int.[");
        for offset : offsets {
            print(*builder, "%, ", offset);
        }
        print(*builder, "];\n");
        return builder_to_string(*builder);
    }

    offset := cast(*u8) ptr_on_entity - cast(*u8) entity;
    engine_check(array_find(VALID_OFFSETS, offset));
    return offset;
}
