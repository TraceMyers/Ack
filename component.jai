// this is a relatively simple implementation of an "entity component system",
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
// the first pointer of the component's type on said entity struct is assumed to be the relevant component pointer, unless the pointer is explicitly provided.
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
//      // this only sets 'freak_cheek', since the component pointer search does not recurse into the base type
//      create_component(*entity_cheeks, es.id);
//
//      // if we want to initialize 'left_cheek' and 'right_cheek', we must pass pointers.
//      create_component(*entity_cheeks, es.id, *es.left_cheek);
//      create_component(*entity_cheeks, es.id, *es.right_cheek);
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

Component_Storage :: struct($component_type: Type, $components_per_chunk := 128) {
    using soa: SOA(struct{
        chunks: *component_type;
        ids:    *user_types.entity_id_type;
        infos:  *Component_Storage_Info;
    });
    allocator: Allocator;
    component_count: int;

    #run assert(is_power_of_two(components_per_chunk), "components_per_chunk % is not a power of two. it must be a power of two in order to guarantee fast indexing during get_component", components_per_chunk);
    CHUNK_INDEXING_SHIFT    :: #run shift_for_power_of_two_mul_or_div(components_per_chunk);
    COMPONENT_INDEXING_MASK :: #run (components_per_chunk - 1);
}

Component_Storage_Info :: struct {
    type_at_offset: enum u32 { POINTER; ARRAY; };
    byte_offset:    u32;
    array_index:    s32;
}

Component_Storage_Iteration :: struct($component_type: Type) {
    component: *component_type;
    entity_id: user_types.entity_id_type;
}

init :: (using storage: *Component_Storage, reserve_at_least := 0) {
    reset(storage);
    soa_set_allocator(*soa, context.allocator);
    allocator = context.allocator;
    reserve(storage, reserve_at_least);
}

reset :: (using storage: *Component_Storage) {
    engine_check(.LOW, chunk_allocations_same_sized(storage));

    if chunks.count > 0 {
        free_chunks(storage, 0, chunks.count-1);
        soa_reset(*soa);
    }
    
    allocator = {};
    component_count = 0;
}

reset_keeping_memory :: (using storage: *Component_Storage) {
    component_count = 0;
}

reserve :: (using storage: *Component_Storage, reserve_at_least := 0) {
    engine_check(.LOW, chunk_allocations_same_sized(storage));

    if reserve_at_least <= 0 {
        return;
    }

    // index to the last reserved component, getting its chunk index. +1 = number of chunks.
    reserve_chunk_count := get_component_indexer(storage, reserve_at_least-1).first + 1;
    chunk_count_before  := chunks.count;
    if chunk_count_before >= reserve_chunk_count {
        return;
    }

    soa_resize(*soa, reserve_chunk_count);
    alloc_chunks(storage, chunk_count_before, reserve_chunk_count-1);
}

shrink :: (using storage: *Component_Storage) {
    engine_check(.LOW, chunk_allocations_same_sized(storage));

    chunk_count, chunk_max := get_chunk_count_and_max(storage);

    if chunk_count < chunk_max {
        free_chunks(storage, chunk_count, chunk_max-1);
        soa_resize(*storage.soa, chunk_count);
    }
}

create_component :: (storage: *Component_Storage($component_type), id: user_types.entity_id_type, component: **component_type = null) -> *component_type {
    engine_check(.HIGH, chunk_allocations_same_sized(storage));

    entity := user_types.id_to_entity_proc(id);
    component_ptr, component_ptr_offset := get_component_pointer_and_offset(storage, entity, component);

    add_new_component(storage, component_ptr, id, entity, component_ptr_offset, -1);
    return component_ptr.*;
}

create_component_in_array :: (storage: *Component_Storage($component_type), id: user_types.entity_id_type, array: *[..]*component_type) -> *component_type {
    engine_check(.HIGH, chunk_allocations_same_sized(storage));

    entity        := user_types.id_to_entity_proc(id);
    component_ptr := array_add(array);
    array_offset  := cast(*u8) array - cast(*u8) entity;

    add_new_component(storage, component_ptr, id, entity, array_offset, array.count - 1);
    return component_ptr.*;
}

// if the component ptr is in an array (added via create_component_in_array), it will
// be removed by swapping with the last component in the array.
destroy_component :: (storage: *Component_Storage($component_type), id: user_types.entity_id_type, component: **component_type, auto_shrink := false, reset_array_on_entity_if_empty := true) {
    engine_check(.HIGH, chunk_allocations_same_sized(storage));

    removing_component := get_component_indexer(storage, component);
    engine_check(.LOW, removing_component.first >= 0);

    entity       := user_types.id_to_entity_proc(id);

    stored_component := *storage.chunks[removing_component.first][removing_component.second];
    stored_id        := *storage.ids   [removing_component.first][removing_component.second];
    stored_info      := *storage.infos [removing_component.first][removing_component.second];

    // make sure we're not removing a component out from under another entity
    engine_check(.LOW, memcmp(stored_id, *id, size_of(user_types.entity_id_type)) == 0); 

    if stored_info.type_at_offset == .POINTER {
        component.* = null;        
    } else { // .ARRAY
        field_ptr       := ((cast(*u8) entity) + stored_info.byte_offset);
        e_arr_ptr       := cast(*[..]*component_type) field_ptr;
        component_index := component - e_arr_ptr.data;

        engine_check(.LOW, component_index == stored_info.array_index);

        if component_index < e_arr_ptr.count - 1 {
            swapping_with_component := *e_arr_ptr.*[e_arr_ptr.count-1];
            indexer := get_component_indexer(storage, swapping_with_component);
            swapping_with_component_info := *storage.infos[indexer.first][indexer.second];
            swapping_with_component_info.array_index = stored_info.array_index;
            component.* = swapping_with_component.*;
        }
        e_arr_ptr.count -= 1;

        if e_arr_ptr.count == 0 && reset_array_on_entity_if_empty {
            array_reset(e_arr_ptr);
        }
    }

    last_component := get_component_indexer(storage, storage.component_count);
    removing_last_component := removing_component == last_component;

    if !removing_last_component {
        replacement_component := *storage.chunks[last_component.first][last_component.second];
        replacement_id        := *storage.ids   [last_component.first][last_component.second];
        replacement_info      := *storage.infos [last_component.first][last_component.second];

        // swap back
        stored_component.* = replacement_component.*;
        stored_id.*        = replacement_id.*;
        stored_info.*      = replacement_info.*;

        // fix pointer for entity whose component was moved
        replacement_entity := user_types.id_to_entity_proc(stored_id.*);
        field_ptr          := ((cast(*u8) replacement_entity) + replacement_info.byte_offset);

        if stored_info.type_at_offset == .POINTER {
            e_cmp_ptr   := cast(**component_type) field_ptr;
            e_cmp_ptr.*  = stored_component;
        } else { // .ARRAY
            e_arr_ptr   := cast(*[..]*component_type) field_ptr;
            e_arr_ptr.*[stored_info.array_index] = stored_component;
        }
    }

    storage.component_count -= 1;
    if auto_shrink then shrink(storage);
}

for_expansion :: (storage: Component_Storage, body: Code, flags: For_Flags) #expand {
    iteration_type :: Component_Storage_Iteration(storage.component_type);

    if storage.component_count <= 0 {
        return;
    }
    
    end := get_component_indexer(*storage, storage.component_count - 1);
    last_chunk := end.first;

    for <=((flags & .REVERSE) != 0) c : 0..last_chunk {
        it_index_base := c * storage.components_per_chunk;

        chunk := *storage.chunks[c];
        ids   := *storage.ids[c];

        component_count := ifx c == last_chunk then end.second+1 else storage.components_per_chunk;

        for <=((flags & .REVERSE) != 0) cmp : 0..component_count-1 {
            `it_index  := it_index_base + cmp;
            `it        := iteration_type.{*chunk.*[cmp], ids.*[cmp]};

            #insert body;
        }
    }
}

get_component_indexer :: inline (storage: *Component_Storage, i: int) -> Index_2D {
    return {xx (i >> storage.CHUNK_INDEXING_SHIFT), xx (i & storage.COMPONENT_INDEXING_MASK)};
}

get_component_indexer :: inline (storage: *Component_Storage($component_type), component: **component_type) -> Index_2D {
    indexer := Index_2D.{-1, 0};

    for chunk_begin, chunk_index : storage.chunks {
        component_index_in_chunk := component.* - chunk_begin;
        indexer.second = xx component_index_in_chunk;
        if indexer.second >= 0 && indexer.second < storage.components_per_chunk {
            indexer.first = xx chunk_index;
            break;
        }
    }

    return indexer;
}

get_component :: inline (storage: *Component_Storage, i: int) -> *storage.component_type {
    engine_check(.LOW, i < storage.component_count);
    indexer := get_component_indexer(storage, i);
    return *storage.chunks[indexer.first][indexer.second];
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
        engine_check(.LOW, component_storage.chunks.allocated == 0 || component_storage.ids.allocated == 0 || component_storage.chunks.allocated != component_storage.ids.allocated, "entity component storage % uninitialized!", member.name);
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

get_component_pointer_and_offset :: (storage: *Component_Storage($component_type), entity: *$Entity_Type, component_ptr_override: **component_type) -> **component_type, int {
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

    engine_check(.HIGH, component_ptr_offset >= 0 && component_ptr_offset < size_of(type_of(entity.*)));
    return component_ptr, component_ptr_offset;
}

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

add_new_component :: (storage: *Component_Storage($component_type), component_ptr: **component_type, id: user_types.entity_id_type, entity: *$T, offset: int, array_index: int) {
    engine_check(.LOW, array_index <= #run get_max_value(type_of(Component_Storage_Info.array_index)));

    next_component_count := storage.component_count + 1;
    defer storage.component_count = next_component_count;

    need_chunk_count := (next_component_count >> storage.CHUNK_INDEXING_SHIFT) + 1;
    have_chunk_count := storage.chunks.count;

    if need_chunk_count > have_chunk_count {
        engine_check(.LOW, need_chunk_count == have_chunk_count + 1);
        soa_add(*storage.soa);
        new_chunk_index := have_chunk_count;
        alloc_chunks(storage, new_chunk_index, new_chunk_index);
    }

    indexer := get_component_indexer(storage, next_component_count-1);
    component_ptr.* = *storage.chunks[indexer.first][indexer.second];

    ini :: initializer_of(storage.component_type);

    #if ini {
        inline ini(*storage.chunks[indexer.first][indexer.second]);
    } else {
        memset(*storage.chunks[indexer.first][indexer.second], 0, size_of(storage.component_type));
    }
    storage.ids  [indexer.first][indexer.second] = id;
    storage.infos[indexer.first][indexer.second] = {ifx array_index == -1 then .POINTER else .ARRAY, xx offset, xx array_index};
}

chunk_allocations_same_sized :: (using storage: *Component_Storage) -> bool {
    return chunks.count == ids.count && chunks.count == infos.count;
}

alloc_chunks :: (using storage: *Component_Storage, first: int, last: int) {
    for chunk : first..last {
        engine_check(.LOW, chunks[chunk] == null && ids[chunk] == null && infos[chunk] == null);
        chunks[chunk] = alloc(size_of(component_type) * components_per_chunk,, allocator);
        ids[chunk]    = alloc(size_of(user_types.entity_id_type) * components_per_chunk,, allocator);
        infos[chunk]  = alloc(size_of(Component_Storage_Info) * components_per_chunk,, allocator);
    }
}

free_chunks :: (using storage: *Component_Storage, first: int, last: int) {
    for chunk : first..last {
        engine_check(.LOW, chunks[chunk] != null && ids[chunk] != null && infos[chunk] != null);
        free(chunks[chunk],, allocator);
        free(ids[chunk],,    allocator);
        free(infos[chunk],,  allocator);
    }
}

get_chunk_count_and_max :: inline (using storage: *Component_Storage) -> count: int, max: int {
    chunk_count_max := chunks.count;
    chunk_count := get_component_indexer(storage, component_count).first + 1;
    engine_check(.HIGH, chunk_count <= chunk_count_max);
    return chunk_count, chunk_count_max;
}

// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.
