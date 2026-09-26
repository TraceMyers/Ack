// this is close to the simplest thing you can reasonably call an "entity component system",
// or at least the "component system" part. store all components of a type in a single
// storage struct, then associate an entity ID with its component, which allows for automatic tight
// packing of components + management of the component pointers on the entities when
// component data moves around.
//
// when importing the engine, you need to pass one type and two procedures. (replace 'your' entries with your stuff)
//
// #import "Ack!"(
//     user_types = struct {
//         entity_id_type      :: Your_Entity_ID;       // your entity id data type
//         entity_to_id_proc   :: your_entity_to_id;    // your procedure, type: (*entity) -> entity id
//         id_to_entity_proc   :: your_id_to_entity;    // your procedure, type: (entity id) -> *entity
//     }
// );
//
// 'entity' in this case just means a struct that has a pointer to an instance of the relevant component type. 
// the first pointer of the component's type on said entity struct is assumed to be the relevant component pointer.
//
// e.g. 
// {
//      entity_cheeks: Component_Storage(Entity_Cheek);
//
//      Entity :: struct {
//          id: u64;
//          left_cheek:  *Entity_Cheek; <----------- only the first pointer will be valid
//          right_cheek: *Entity_Cheek;              after the first create_component() call
//      }                                              |
//                                                     |
//      e := Entity.{id=1};                            |
//                                                     |
//      create_component(*entity_cheeks, e.id); o------+
//      create_component(*entity_cheeks, e.id, *e.right_cheek); <-- turning the other cheek
//
//      Entity_Subtype :: struct {
//          using base: Entity;
//          freak_cheek: *Entity_Cheek;
//      }
//      
//      es := Entity_Subtype.{id=2};
//      
//      // same as above, this only sets 'left_cheek' on the base type.
//      create_component(*entity_cheeks, es.id);
//
//      // if we want to initialize 'freak_cheek', we must pass a pointer to it.
//      create_component(*entity_cheeks, es.id, *es.freak_cheek);
// }
//
// the consistency and simplicity of this approach makes it easier to manage than other implementations I have tried.
//
// the intended way to use this module:
//  
// Entity_Components :: struct {
//      hair_components: Component_Storage(Hair);
//      personality_components: Component_Storage(Personality);
// }
//
// World :: struct {
// ...
//      using entity_components: Entity_Components;
// ...
// }
//
// spawn_entity :: () -> *Entity {
// ...
//      create_component(*world.hair_components, new_entity.id);
//      create_component(*world.personality_components, new_entity.id);
// ...
// }
//
// style_entity_hairs :: () {
// ...
//      for world.hair_components {
//          entity := your_id_to_entity(it.entity_id); // get associated entity if you need to
//          style_hair(it.component);
//      }
// ...
// }
// 
// destroy_entity :: (entity: *Entity) {
// ...
//      destroy_component(*world.hair_components, entity.id);
//      destroy_component(*world.personality_components, entity.id);
// ...
// }

Component_Storage_Info :: struct {
    type_at_offset: enum u32 { POINTER; ARRAY; };
    byte_offset:    u32;
    array_index:    s32;
}

// todo: allocations should be in chunks. 
// fixes pointer correction cost issue and reallocation cost issue.
Component_Storage :: struct ($component_type: Type) {
    components: [..]component_type;
    ids:        [..]user_types.entity_id_type;
    infos:      [..]Component_Storage_Info;
}

Component_Storage_Iteration :: struct($component_type: Type) {
    component: *component_type;
    entity_id: user_types.entity_id_type;
}

for_expansion :: (storage: Component_Storage, body: Code, flags: For_Flags) #expand {
    iteration_type :: Component_Storage_Iteration(storage.component_type);
    
    for <=((flags & .REVERSE) != 0) i : 0..storage.components.count-1 {
        `it_index  := i;
        `it        := iteration_type.{*storage.components[i], storage.ids[i]};

        #insert body;
    }
}

init :: (storage: *Component_Storage, size: int) {
    array_reserve(*storage.components, size);
    array_reserve(*storage.ids,        size);
    array_reserve(*storage.infos,      size);
}

create_component :: (storage: *Component_Storage($component_type), id: user_types.entity_id_type, component: **component_type = null) -> *component_type, reallocated: bool {
    engine_check(.MEDIUM, storage.components.count == storage.ids.count && storage.components.count == storage.infos.count);

    entity := user_types.id_to_entity_proc(id);
    component_ptr, component_ptr_offset := get_component_pointer_and_offset(storage, entity, component);

    return component_ptr.*, add_new_component(storage, component_ptr, id, entity, component_ptr_offset, -1);
}

create_component_in_array :: (storage: *Component_Storage($component_type), id: user_types.entity_id_type, array: *[..]*component_type) -> *component_type, reallocated: bool {
    engine_check(.MEDIUM, storage.components.count == storage.ids.count && storage.components.count == storage.infos.count);

    entity        := user_types.id_to_entity_proc(id);
    component_ptr := array_add(array);
    array_offset  := cast(*u8) array - cast(*u8) entity;

    return component_ptr.*, add_new_component(storage, component_ptr, id, entity, array_offset, array.count - 1);
}

// if the component ptr is in an array (added via create_component_in_array), it will
// be removed by swapping with the last component in the array.
destroy_component :: (storage: *Component_Storage($component_type), id: user_types.entity_id_type, component: **component_type, auto_shrink := false, reset_array_on_entity_if_empty := true) {
    engine_check(.MEDIUM, storage.components.count == storage.ids.count && storage.components.count == storage.infos.count);

    index  := component.* - storage.components.data;
    entity := user_types.id_to_entity_proc(id);
    info   := *storage.infos[index];

    engine_check(.LOW, memcmp(*storage.ids[index], *id, size_of(user_types.entity_id_type)) == 0); // make sure we're not removing a component out from under another entity

    if info.type_at_offset == .POINTER {
        component.* = null;        
    } else { // .ARRAY
        field_ptr       := ((cast(*u8) entity) + info.byte_offset);
        e_arr_ptr       := cast(*[..]*component_type) field_ptr;
        component_index := component - e_arr_ptr.data;

        engine_check(.LOW, component_index == info.array_index);

        if component_index < e_arr_ptr.count - 1 {
            swapping_with_component := *e_arr_ptr.*[e_arr_ptr.count-1];
            swapping_with_component_storage_index := swapping_with_component.* - storage.components.data;
            swapping_with_component_info := *storage.infos[swapping_with_component_storage_index];
            swapping_with_component_info.array_index = info.array_index;
            component.* = swapping_with_component.*;
        }
        e_arr_ptr.count -= 1;

        if e_arr_ptr.count == 0 && reset_array_on_entity_if_empty {
            array_reset(e_arr_ptr);
        }
    }

    if index < storage.components.count - 1 {
        // swap back
        storage.components[index] = storage.components[storage.components.count-1];
        storage.ids[index]        = storage.ids[storage.components.count-1];
        storage.infos[index]      = storage.infos[storage.components.count-1];

        // fix pointer for entity whose component was moved
        entity_at_end := user_types.id_to_entity_proc(storage.ids[index]);
        info_at_end   := *storage.infos[index];
        field_ptr     := ((cast(*u8) entity_at_end) + info_at_end.byte_offset);

        if info_at_end.type_at_offset == .POINTER {
            e_cmp_ptr   := cast(**component_type) field_ptr;
            e_cmp_ptr.*  = *storage.components[index];
        } else { // .ARRAY
            e_arr_ptr   := cast(*[..]*component_type) field_ptr;
            e_arr_ptr.*[info_at_end.array_index] = *storage.components[index];
        }
    } 

    storage.components.count -= 1;
    storage.ids.count        -= 1;

    if auto_shrink && shrink_if_small_enough(storage) {
        // potential hotspot here. for very large component storages, try setting auto_shrink to false
        fix_component_pointers(storage);
    }
}

shrink_if_small_enough :: (storage: *Component_Storage, realloc_if_using_leq_proportion := 0.35, remove_free_proportion := 0.75, minimum_allocated := 8) -> bool {
    if array_shrink_if_small_enough(*storage.components, realloc_if_using_leq_proportion, remove_free_proportion, minimum_allocated) {
        storage.ids.count = storage.components.count;
        array_shrink(*storage.ids, remove_free_proportion);
        array_shrink(*storage.infos, remove_free_proportion);
        return true;
    } else return false;
}

// iterate over all entities owning this component and fix the component pointers so they're 
// pointing into the component storages. this should not need to be called outside this module, but 
// it's potentially useful for debugging.
fix_component_pointers :: inline (storage: *Component_Storage) {
    for 0..storage.ids.count-1 { 
        entity     := user_types.id_to_entity_proc(storage.ids[it]);
        info       := *storage.infos[it];

        field_ptr := ((cast(*u8) entity) + info.byte_offset);

        if info.type_at_offset == .POINTER {
            e_cmp_ptr  := cast(**storage.component_type) field_ptr;
            e_cmp_ptr.* = *storage.components[it];
        } else { // ARRAY
            e_arr_ptr  := cast(*[..]*storage.component_type) field_ptr;
            e_arr_ptr.*[info.array_index] = *storage.components[it];
        }
    }
}

get_component_pointer_and_offset :: inline (storage: *Component_Storage($component_type), entity: *$Entity_Type, component_ptr_override: **component_type) -> **component_type, int {
    first_component_ptr_offset :: #run get_first_component_pointer_offset(component_type);

    component_ptr_offset: int = -1;
    component_ptr: **component_type;

    if component_ptr_override {
        component_ptr_offset = cast(*u8) component_ptr_override - cast(*u8) entity;
        component_ptr        = component_ptr_override;
    } else {
        component_ptr_offset = first_component_ptr_offset;
        component_ptr = cast(**component_type) ((cast(*u8) entity) + component_ptr_offset);
    }

    engine_check(.MEDIUM, component_ptr_offset >= 0 && component_ptr_offset < size_of(type_of(entity.*)));
    return component_ptr, component_ptr_offset;
}

// pass a pointer to an instance of a struct that has component storage members
// and validate that those storages are initialized. useful if you put all of
// your component storages on one struct - makes it a runtime error to add a new component
// storage without initializing it. *particularly* useful if you preallocate
// your components without intending to ever reallocate, making initialization mandatory.
debug__validate_component_storages_initialized :: (entity_components: *$T) {
    components_info := cast(*Type_Info_Struct) type_info(T);
    engine_check(.LOW, components_info.type == .STRUCT);
    for member : components_info.members {
        if !is_subclass_of(member.type, "Component_Storage") {
            continue;
        }
        // all component storage types specializations have their members at the same offsets.
        // so, (void) just means the specialization doesn't matter.
        component_storage := cast(*Component_Storage(void)) (cast(*u8) entity_components + member.offset_in_bytes);
        engine_check(.LOW, component_storage.components.allocated == 0 || component_storage.ids.allocated == 0 || component_storage.components.allocated != component_storage.ids.allocated, "entity component storage % uninitialized!", member.name);
    }
}

debug__validate_component_pointers :: (storage: *Component_Storage, component_ptr_offset_override: int = -1) {
    component_type             :: #run type_of(storage.*).component_type;
    first_component_ptr_offset :: #run get_first_component_pointer_offset(component_type);
    component_ptr_offset := ifx component_ptr_offset_override == -1 then first_component_ptr_offset else component_ptr_offset_override;

     for id : storage.ids {
        e := user_types.id_to_entity_proc(id);
        e_cmp_ptr  := cast(**type_of(storage.*).component_type) ((cast(*u8) e) + component_ptr_offset);
        engine_check(.LOW, e_cmp_ptr.* == *storage.components[it_index]);
    }
}

#scope_module

entity_type :: #run -> Type {
    proc_tinfo := type_info(type_of(user_types.entity_to_id_proc));
    assert(proc_tinfo.argument_types[0].type == .POINTER);
    arg_pointer_tinfo := cast(*Type_Info_Pointer) proc_tinfo.argument_types[0];
    return (cast(*Type) *(arg_pointer_tinfo.pointer_to)).*;
}

get_first_component_pointer_offset :: (component_type: Type) -> int {
    entity_tinfo := cast(*Type_Info_Struct) type_info(entity_type);
    for member : entity_tinfo.members {
        if member.type.type == .POINTER {
            pointer_tinfo := cast(*Type_Info_Pointer) member.type;
            field_type := (cast(*Type) *(pointer_tinfo.pointer_to)).*;
            if field_type == component_type {
                return member.offset_in_bytes;
            }
        }
    }
    engine_check(.LOW, false, "failed to find field of type *% on %", component_type, entity_type);
    return 0;
}

add_new_component :: (storage: *Component_Storage($component_type), component_ptr: **component_type, id: user_types.entity_id_type, entity: *$T, offset: int, array_index: int) -> need_fix_pointers: bool {

    data_before := storage.components.data;
    component_ptr.* = array_add(*storage.components); // data initialized in array_add call
    data_after  := storage.components.data;
    array_add(*storage.ids, id);
    
    engine_check(.LOW, array_index <= #run get_max_value(type_of(Component_Storage_Info.array_index)));
    array_add(*storage.infos, {ifx array_index == -1 then .POINTER else .ARRAY, xx offset, xx array_index});
    
    if data_after != data_before {
        // potential hotspot here. for very large component storages, try preallocating more than you need.
        fix_component_pointers(storage);
        return true;
    } else return false;
}

// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.
