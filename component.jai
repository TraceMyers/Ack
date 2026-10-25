/*
todo: rewrite docs
*/

Component_Storage :: struct($component_type: Type, $in_components_per_chunk := 64) {
    using #as multi: Multi_Component_Storage(struct{components: component_type;}, components_per_chunk=in_components_per_chunk);
}

Multi_Component_Storage :: struct($component_collection: Type, $components_per_chunk := 64) {
    Chunk :: struct {
        using soa: Sized_SOA(component_collection, components_per_chunk);
        // using collection: component_collection;
        ids:   [components_per_chunk]user_types.entity_id_type;
        infos: [components_per_chunk]Component_Storage_Info;
    }

    chunks: [..]*Chunk;
    component_count: int;

    #run assert(is_power_of_two(components_per_chunk), "components_per_chunk % is not a power of two. it must be a power of two in order to guarantee fast indexing during get_component", components_per_chunk);
    CHUNK_INDEXING_SHIFT    :: #run shift_for_power_of_two_mul_or_div(components_per_chunk);
    COMPONENT_INDEXING_MASK :: #run (components_per_chunk - 1);
    
    first_component_name, first_component_type :: #run -> string, Type {
        collection_tinfo := cast(*Type_Info_Struct) type_info(component_collection);
        assert(collection_tinfo.type == .STRUCT);
        first_member := collection_tinfo.members[0];
        return first_member.name, (cast(*Type) *first_member.type).*;
    };

    // create component getters for storages that are housing multiple components.
    // you can use get_component (farther down) to get the first (or only component)
    #if #run (cast(*Type_Info_Struct) type_info(component_collection)).members.count > 1 {
        #insert -> string {
            builder: String_Builder;
            collection_tinfo := cast(*Type_Info_Struct) type_info(component_collection);
            for collection_tinfo.members {
                print(*builder,
        #string END
        get_%_component :: inline (storage: *Multi_Component_Storage, index: Index_2D) -> *% {
            return *storage.chunks[index.first].%[index.second];
        }
        END,
                    it.name, (cast(*Type) *it.type).*, it.name
                );

                print(*builder,
        #string END
        get_%_component :: inline (storage: *Multi_Component_Storage, i: int) -> *% {
            index := get_component_indexer(storage, i);
            return *storage.chunks[index.first].%[index.second];
        }
        END,
                    it.name, (cast(*Type) *it.type).*, it.name
                );
            }
            return builder_to_string(*builder);
        }
    }
}

Component_Storage_Info :: struct {
    type_at_offset: enum u32 { POINTER; ARRAY; };
    byte_offset:    u32;
    array_index:    s32;
}

Component_Storage_Iteration :: struct($component_type: Type) {
    component: *component_type;
    index: Index_2D;
    entity_id: user_types.entity_id_type;
}

init :: (using storage: *Multi_Component_Storage, reserve_at_least := 0) {
    reset(storage);
    reserve(storage, reserve_at_least);
}

reset :: (using storage: *Multi_Component_Storage) {
    if chunks.count > 0 {
        free_chunks(storage, 0, chunks.count-1);
        array_reset(*chunks);
    }
    chunks.allocator = {};
    component_count = 0;
}

reset_keeping_memory :: (using storage: *Multi_Component_Storage) {
    component_count = 0;
}

reserve :: (using storage: *Multi_Component_Storage, reserve_at_least := 0) {
    if reserve_at_least <= 0 {
        return;
    }

    // index to the last reserved component, getting its chunk index. +1 = number of chunks.
    reserve_chunk_count := get_component_indexer(storage, reserve_at_least-1).first + 1;
    chunk_count_before  := chunks.count;

    if chunk_count_before >= reserve_chunk_count {
        return;
    }

    array_resize(*chunks, reserve_chunk_count);
    alloc_chunks(storage, chunk_count_before, reserve_chunk_count-1);
}

shrink :: (using storage: *Multi_Component_Storage) {
    chunk_count, chunk_max := get_chunk_count_and_max(storage);

    if chunk_count < chunk_max {
        free_chunks(storage, chunk_count, chunk_max-1);
        array_resize(*chunks, chunk_count);
    }
}

create_component :: (storage: *Multi_Component_Storage, id: user_types.entity_id_type, component_ptr: **storage.first_component_type) -> *storage.first_component_type {
    entity := user_types.id_to_entity_proc(id);
    component_ptr_offset := get_component_pointer_offset(storage, entity, component_ptr);

    add_new_component(storage, component_ptr, id, entity, component_ptr_offset, -1);
    return component_ptr.*;
}

create_component_in_array :: (storage: *Multi_Component_Storage, id: user_types.entity_id_type, array: *[..]*storage.first_component_type) -> *storage.first_component_type {
    entity        := user_types.id_to_entity_proc(id);
    component_ptr := array_add(array);
    array_offset  := cast(*u8) array - cast(*u8) entity;

    add_new_component(storage, component_ptr, id, entity, array_offset, array.count - 1);
    return component_ptr.*;
}

// before calling:
//
// entity_a          entity_b
//    |                 |
//    v                 v
// [  0  |  1  |  2  |  3  ]    <- array of components
// 
// after destroy_component called for the component owned by entity_a, component 3 is copied to 0:
// 
// entity_b
//    |
//    v
// [  0  |  1  |  2  ]
//
// replacement_entity_callback is provided in order to allow you to make corrections game-side to 
// data tracking the location of the component by pointer or index. for example, you may have copies 
// of the component pointer that need to be corrected. in the params of replacement_entity_callback,
// 'replacer' is entity_b, 'replacer_component' is the component entity_b now points to, 
// and 'new_index' is the 2d index of the component, represented in this example by the 1d index, 0.
destroy_component :: (storage: *Multi_Component_Storage, id: user_types.entity_id_type, component: **storage.first_component_type, auto_shrink := false, reset_array_on_entity_if_empty := true, replacement_entity_callback: (replacer: *Ack_Entity, replacer_component: *storage.first_component_type, new_index: Index_2D) = null) {
    removing_component := get_component_indexer(storage, component);
    engine_check(removing_component.first >= 0);

    entity       := user_types.id_to_entity_proc(id);
    stored_chunk := storage.chunks[removing_component.first];
    stored_id    := *stored_chunk.ids[removing_component.second];
    stored_info  := *stored_chunk.infos[removing_component.second];

    // make sure we're not removing a component out from under another entity
    engine_check(memcmp(stored_id, *id, size_of(user_types.entity_id_type)) == 0); 

    if stored_info.type_at_offset == .POINTER {
        component.* = null;        
    } else { // .ARRAY
        field_ptr       := ((cast(*u8) entity) + stored_info.byte_offset);
        e_arr_ptr       := cast(*[..]*storage.first_component_type) field_ptr;
        component_index := component - e_arr_ptr.data;

        engine_check(component_index == stored_info.array_index);

        if component_index < e_arr_ptr.count - 1 {
            swapping_with_component := *e_arr_ptr.*[e_arr_ptr.count-1];
            indexer := get_component_indexer(storage, swapping_with_component);
            swapping_with_component_info := *storage.chunks[indexer.first].infos[indexer.second];
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
        replacement_chunk     := storage.chunks[last_component.first];
        replacement_id        := *replacement_chunk.ids[last_component.second];
        replacement_info      := *replacement_chunk.infos[last_component.second];

        // swap back id and component meta info
        stored_id.*   = replacement_id.*;
        stored_info.* = replacement_info.*;

        // swap back component datas
        #insert -> string {
            builder: String_Builder;

            print(*builder, "primary_component := *stored_chunk.%[removing_component.second];\n", storage.first_component_name);

            collection_tinfo := cast(*Type_Info_Struct) type_info(storage.component_collection);
            for member : collection_tinfo.members {
                print(*builder, "stored_chunk.%[removing_component.second] = replacement_chunk.%[last_component.second];\n", member.name, member.name);
            }
            return builder_to_string(*builder);
        }

        // fix pointer for entity whose component was moved
        replacement_entity := user_types.id_to_entity_proc(stored_id.*);
        field_ptr          := ((cast(*u8) replacement_entity) + replacement_info.byte_offset);

        if stored_info.type_at_offset == .POINTER {
            e_cmp_ptr   := cast(**storage.first_component_type) field_ptr;
            e_cmp_ptr.*  = primary_component;
        } else { // .ARRAY
            e_arr_ptr   := cast(*[..]*storage.first_component_type) field_ptr;
            e_arr_ptr.*[stored_info.array_index] = primary_component;
        }

        if replacement_entity_callback != null {
            replacement_entity_callback(replacement_entity, primary_component, removing_component);
        }
    }

    storage.component_count -= 1;
    if auto_shrink then shrink(storage);
}

destroy_component_array :: (storage: *Multi_Component_Storage, id: user_types.entity_id_type, component_array: [..]storage.first_component_type, auto_shrink := false, reset_array_on_entity_if_empty := true, replacement_entity_callback: (replacer: *Ack_Entity, replacer_component: *storage.first_component_type, new_index: Index_2D) = null) {
    for < *storage {
        destroy_component(storage, id, it, auto_shrink, reset_array_on_entity_if_empty, replacement_entity_callback);
    }
}

for_expansion :: (storage: Multi_Component_Storage, body: Code, flags: For_Flags) #expand {
    if storage.component_count <= 0 {
        return;
    }
    
    end := get_component_indexer(*storage, storage.component_count - 1);
    last_chunk := end.first;

    for <=((flags & .REVERSE) != 0) c : 0..last_chunk {
        it_index_base := c * storage.components_per_chunk;

        chunk := storage.chunks[c];
        component_count := ifx c == last_chunk then end.second+1 else storage.components_per_chunk;

        for <=((flags & .REVERSE) != 0) cmp : 0..component_count-1 {
            `it_index := it_index_base + cmp;
            #insert #run tprint("`it := Component_Storage_Iteration(storage.first_component_type).{*chunk.%[cmp], {xx c, xx cmp}, chunk.ids[cmp]};\n", storage.first_component_name);

            #insert body;
        }
    }
}

get_component_indexer :: inline (storage: *Multi_Component_Storage, i: int) -> Index_2D {
    return index_1d_to_2d_pow2_width(i, storage.components_per_chunk);
}

// slow. only used during destroy
get_component_indexer :: inline (storage: *Multi_Component_Storage, component: **storage.first_component_type) -> Index_2D {
    indexer := Index_2D.{-1, 0};

    for chunk, chunk_index : storage.chunks {
        #insert #run tprint("component_index_in_chunk := component.* - chunk.%.data;\n", storage.first_component_name);
        if component_index_in_chunk >= 0 && component_index_in_chunk < storage.components_per_chunk {
            indexer.first  = xx chunk_index;
            indexer.second = xx component_index_in_chunk;
            break;
        }
    }

    return indexer;
}

get_component :: inline (storage: *Multi_Component_Storage, i: int) -> *storage.first_component_type {
    index := get_component_indexer(storage, i);
    return get_component(storage, index);
}

get_component :: inline (storage: *Multi_Component_Storage, index: Index_2D) -> *storage.first_component_type {
    #insert #run tprint("return *storage.chunks[index.first].%[index.second];\n", storage.first_component_name);
}

get_entity_id ::  inline (storage: *Multi_Component_Storage, i: int) -> user_types.entity_id_type {
    index := get_component_indexer(storage, i);
    return storage.chunks[index.first].ids[index.second];
}

get_entity_id ::  inline (storage: *Multi_Component_Storage, index: Index_2D) -> user_types.entity_id_type {
    return storage.chunks[index.first].ids[index.second];
}

// pass a pointer to an instance of a struct that has component storage members
// and validate that those storages are initialized. useful if you put all of
// your component storages on one struct - makes it a runtime error to add a new component
// storage without initializing it. *particularly* useful if you preallocate
// your components without intending to ever reallocate, making initialization mandatory.
debug__validate_component_storages_initialized :: (entity_components: *$T) {
    components_info := cast(*Type_Info_Struct) type_info(T);
    engine_check(components_info.type == .STRUCT);
    for member : components_info.members {
        if !is_subclass_of(member.type, "Multi_Component_Storage") {
            continue;
        }
        // all component storage types specializations have their members at the same offsets.
        // so, (void) just means the specialization doesn't matter.
        component_storage := cast(*Component_Storage(void)) (cast(*u8) entity_components + member.offset_in_bytes);
        engine_check(component_storage.chunks.allocated != 0, "entity component storage % uninitialized!", member.name);
    }
}

debug__validate_component_pointers :: (storage: *Multi_Component_Storage, component_ptr_offset_override: int = -1) {
    component_type             :: #run type_of(storage.*).first_component_type;
    first_component_ptr_offset :: #run get_first_component_pointer_offset(component_type);
    component_ptr_offset := ifx component_ptr_offset_override == -1 then first_component_ptr_offset else component_ptr_offset_override;

     for id : storage.ids {
        e := user_types.id_to_entity_proc(id);
        e_cmp_ptr  := cast(**type_of(storage.*).first_component_type) ((cast(*u8) e) + component_ptr_offset);
        #insert #run tprint("engine_check(e_cmp_ptr.* == *storage.%[it_index]);\n", storage.first_component_name);
    }
}

#scope_file

get_component_pointer_offset :: inline (storage: *Multi_Component_Storage, entity: *$Entity_Type, in_component_ptr: **storage.first_component_type) -> int {
    return cast(*u8) in_component_ptr - cast(*u8) entity;
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
    return -1;
}

add_new_component :: (storage: *Multi_Component_Storage, component_ptr: **storage.first_component_type, id: user_types.entity_id_type, entity: *$T, offset: int, array_index: int) {
    engine_check(array_index <= #run get_max_value(type_of(Component_Storage_Info.array_index)));

    next_component_count := storage.component_count + 1;
    defer storage.component_count = next_component_count;

    need_chunk_count := (next_component_count >> storage.CHUNK_INDEXING_SHIFT) + 1;
    have_chunk_count := storage.chunks.count;

    if need_chunk_count > have_chunk_count {
        engine_check(need_chunk_count == have_chunk_count + 1);
        array_add(*storage.chunks);
        new_chunk_index := have_chunk_count;
        alloc_chunks(storage, new_chunk_index, new_chunk_index);
    }

    indexer := get_component_indexer(storage, next_component_count-1);
    chunk := storage.chunks[indexer.first];

    chunk.ids[indexer.second] = id;
    chunk.infos[indexer.second] = {ifx array_index == -1 then .POINTER else .ARRAY, xx offset, xx array_index};

    #insert -> string {
        builder: String_Builder;

        print(*builder, "component_ptr.* = *chunk.%[indexer.second];\n", storage.first_component_name);

        collection_tinfo := cast(*Type_Info_Struct) type_info(storage.component_collection);
        for member : collection_tinfo.members {
            print(*builder, "meminit(*chunk.%[indexer.second]);\n", member.name);
        }
        return builder_to_string(*builder);
    }
}

chunk_allocations_same_sized :: (using storage: *Multi_Component_Storage) -> bool {
    return chunks.count == ids.count && chunks.count == infos.count;
}

alloc_chunks :: (using storage: *Multi_Component_Storage, first: int, last: int) {
    for c : first..last {
        engine_check(storage.chunks[c] == null);
        chunks[c] = alloc(size_of(storage.Chunk),, storage.chunks.allocator);
        memset(storage.chunks[c], 0, size_of(storage.Chunk));
    }
}

free_chunks :: (using storage: *Multi_Component_Storage, first: int, last: int) {
    for c : first..last {
        engine_check(chunks[c] != null);
        free(chunks[c],, chunks.allocator);
    }
}

get_chunk_count_and_max :: inline (using storage: *Multi_Component_Storage) -> count: int, max: int {
    chunk_count_max := chunks.count;
    chunk_count := get_component_indexer(storage, component_count).first + 1;
    engine_check(chunk_count <= chunk_count_max, level=.HIGH);
    return chunk_count, chunk_count_max;
}

// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.
