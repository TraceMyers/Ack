/*
todo: rewrite docs
*/

// global engine component handles
entity_handle: u32; 
physics_body_handle: u32;

// types

Component_Ref :: struct {
    type_handle: u32;
    id: Gen_ID;
}

Component_Instance :: struct {
    data: *void;
    ref: Component_Ref;
}

Component_Handling_Flags :: enum_flags {
    INITIALIZE_ON_ADD;
    DEINITIALIZE_ON_REMOVE;
    STABLE_ID;
    MAY_NOT_HAVE_OWNER;
}
DEFAULT_COMPONENT_HANDLING_FLAGS : Component_Handling_Flags : .INITIALIZE_ON_ADD | .DEINITIALIZE_ON_REMOVE;

Component_Storage_Index :: struct {
    chunk: s32;
    index: s32;
}

Component_Slot :: struct {
    component: *u8;
    owner_id: *Gen_ID;
    generation: *u32;
}

Component_Storage :: struct {
    type_name: string;
    tinfo: *Type_Info;

    chunks: [..]*u8;
    stable_tracking: Bit_Array;
    free_index: s32;
    type_size: u32;

    type_handle: u32;

    type_init: (*void);
    type_deinit: (*void);

    handling: Component_Handling_Flags;

    combinations: [..]Component_Combination_Handle;

    ITEMS_PER_CHUNK :: 64;
    COMPONENT_ALIGN :: 8;

    #assert(type_of(stable_tracking.slots[0]) == s64);
}

// interface

component_storage :: ($T: Type) -> *Component_Storage {
    return component_storage(type_info(T));
}

component_storage :: (info: *Type_Info) -> *Component_Storage {
    return *engine.components[table_find_pointer(*engine.type_to_component_handle, info).*];
}

component_handle_to_type :: (handle: u32) -> *Type_Info {
    return engine.components[handle].tinfo;
}

add_component_type :: ($T: Type, init_handling := DEFAULT_COMPONENT_HANDLING_FLAGS, override_init: (*void) = null, deinit: (*void) = null) -> u32 {
    handle_ptr, just_added := find_or_add(*engine.type_to_component_handle, type_info(T));

    if just_added {
        array_add(*engine.components, {});
        handle_ptr.* = xx (engine.components.count - 1);
        init(*engine.components[handle_ptr.*], T, init_handling, override_init, deinit);
    }

    return handle_ptr.*;
}

init_engine_default_entity_components :: () {
    null_handle := add_component_type(void);
    engine_check(null_handle == 0);

    entity_flags := DEFAULT_COMPONENT_HANDLING_FLAGS | .MAY_NOT_HAVE_OWNER | .STABLE_ID;
    entity_handle = add_component_type(Entity, init_handling=entity_flags);

    add_component_type(Transform);

    // stable ids so body indexes stored in the contact grid never move
    physics_body_handle = add_component_type(Physics_Body, init_handling = DEFAULT_COMPONENT_HANDLING_FLAGS | .STABLE_ID, deinit=xx deinit_physics_body);

    add_component_type(Static_Mesh_Instance);
    add_component_type(Skeletal_Mesh_Instance);
    add_component_type(Input);
    add_component_type(Camera);
}

init :: (using storage: *Component_Storage, $T: Type, component_handling: Component_Handling_Flags, override_init: (*void), deinit: (*void)) {
    #assert(align_of(T) <= Component_Storage.COMPONENT_ALIGN);

    type_name = sprint("%", T);
    tinfo = type_info(T);
    
    chunks.allocator = context.allocator;
    stable_tracking.allocator = context.allocator;

    handling = component_handling;

    type_size = size_of(T);
    type_handle = table_find_pointer(*engine.type_to_component_handle, type_info(T)).*;

    type_init = ifx override_init != null then override_init else get_virtual_meminit(T);
    type_deinit = deinit;
}

get_component :: inline (ref: Component_Ref, $T: Type) -> *T {
    return cast(*T) get_component_data(ref);
}

get_component :: inline (using storage: *Component_Storage, id: Gen_ID, $T: Type) -> *T {
    return cast(*T) get_component_data(storage, id);
}

get_component_data :: inline (ref: Component_Ref) -> *void {
    return get_component_data(*engine.components[ref.type_handle], ref.id);
}

get_component_data :: inline (using storage: *Component_Storage, id: Gen_ID) -> *void {
    if id.index < 0 return null;
    index := to_component_storage_index(id.index);
    if index.chunk >= chunks.count return null;
    if get_slot_generation(storage, index).* != id.generation {
        return null;
    }
    return get_slot_component_memory(storage, index);
}

component_field_name :: (type: Type) -> string {
    name := tprint("%", type);
    // polymorphic structs print their parameters, as in "Physics_Body_Base(properties_type=void)"
    paren := find_index_from_left(name, #char "(");
    if paren >= 0 name.count = paren;
    return to_lower_copy(name,, temp);
}

add_component :: ($T: Type, owner_ref: Entity_Ref) -> Component_Instance {
    handle := table_find_pointer(*engine.type_to_component_handle, type_info(T)).*;
    return add_component(handle, owner_ref);
}

add_component :: (handle: u32, owner_ref: Entity_Ref) -> Component_Instance {
    return add_component(*engine.components[handle], owner_ref);
}

add_component :: (using storage: *Component_Storage, owner_ref: Entity_Ref) -> Component_Instance {
    free_component_index := Component_Storage_Index.{xx chunks.count, 0};

    if (handling & .STABLE_ID) != 0 {
        for :only_cleared_bits stable_tracking {
            free_component_index = to_component_storage_index(it_index);
            break;
        }
    } else {
        free_component_index = to_component_storage_index(free_index);
        free_index += 1;
    }

    if free_component_index.chunk >= chunks.count {
        engine_check(free_component_index.chunk == chunks.count && free_component_index.index == 0);
        add_chunk(storage);
    }
    
    if (handling & .STABLE_ID) != 0 {
        i := free_component_index.chunk * ITEMS_PER_CHUNK + free_component_index.index;
        stable_tracking[i] = true;
    }

    slot := get_component_slot(storage, free_component_index);
    slot.owner_id.* = owner_ref.id;

    if combinations.count > 0 {
        owner := get_entity(owner_ref);

        if owner != null then for ci : combinations {
            combo := *engine.component_combinations[ci];
            has_all_types := true;

            for type : combo.types {
                if type == tinfo {
                    continue;
                }
                if get_component_instance(owner, type) == null {
                    has_all_types = false;
                    break;
                }
            }

            if has_all_types {
                array_add(*combo.entities_with_combination, owner_ref.id);
            }
        }
    }

    if (handling & .INITIALIZE_ON_ADD) != 0 {
        type_init(slot.component);
    }

    index := free_component_index.chunk * ITEMS_PER_CHUNK + free_component_index.index;
    return {slot.component, {type_handle, {xx index, slot.generation.*}}};
}

remove_component :: (inst: *Component_Instance, allow_shrink := true) {
    // ----------

    clear_slot :: (slot: Component_Slot, type_size: int) {
        memset(slot.component, 0, type_size);
        slot.owner_id.* = .{};
        slot.generation.* += 1;
    }

    // ----------

    using storage: *Component_Storage = *engine.components[inst.ref.type_handle];

    component_index := to_component_storage_index(inst.ref.id.index);
    slot := get_component_slot(storage, component_index);

    if (handling & .DEINITIALIZE_ON_REMOVE) != 0 && type_deinit != null {
        type_deinit(slot.component);
    }

    old_owner_id := slot.owner_id.*;

    if (handling & .STABLE_ID) != 0 {
        engine_check(stable_tracking[inst.ref.id.index]);
        stable_tracking[inst.ref.id.index] = false;
        clear_slot(slot, type_size);
    } else {
        engine_check(inst.ref.id.index < free_index);

        last_index := free_index - 1;
        last_component_index := to_component_storage_index(last_index);
        last_slot := get_component_slot(storage, last_component_index);

        if inst.ref.id.index != free_index - 1 {
            memcpy(slot.component, last_slot.component, type_size);
            slot.owner_id.* = last_slot.owner_id.*;
            slot.generation.* += 1;

            if slot.owner_id.index < 0 {
                engine_check((handling & .MAY_NOT_HAVE_OWNER) != 0);
            } else {
                swap_slot_owner := get_entity(slot.owner_id.*);
                swap_slot_inst  := table_find_pointer(*swap_slot_owner.components, tinfo);
                swap_slot_inst.data = slot.component;
                swap_slot_inst.ref.id = .{inst.ref.id.index, slot.generation.*};
            }
        }

        clear_slot(last_slot, type_size);
        free_index -= 1;
    }

    if combinations.count > 0 {
        owner := get_entity(old_owner_id);
        if owner != null then for ci : combinations {
            combo := *engine.component_combinations[ci];
            // Gen_ID has no operator ==, so array_unordered_remove_by_value can't be used
            for combo.entities_with_combination {
                if it.index == old_owner_id.index && it.generation == old_owner_id.generation {
                    remove it;
                    break;
                }
            }
        }
    }

    inst.* = {};
}

last_allocated_index :: (using storage: *Component_Storage) -> int {
    if (handling & .STABLE_ID) != 0 {
        for < :only_set_bits bit_value, bit_index : stable_tracking {
            return bit_index;
        }
    } else {
        return free_index - 1;
    }
    return -1;
}

// component tracking

to_component_storage_index :: (i: int) -> Component_Storage_Index {
    #assert(is_power_of_two(Component_Storage.ITEMS_PER_CHUNK));
    DIVIDE_SHIFT :: #run shift_for_power_of_two_mul_or_div(Component_Storage.ITEMS_PER_CHUNK);
    return .{xx (i >> DIVIDE_SHIFT), xx (i & (Component_Storage.ITEMS_PER_CHUNK - 1))};
}

get_component_slot :: inline (storage: *Component_Storage, index: Component_Storage_Index) -> Component_Slot {
    return {
        get_slot_component_memory(storage, index),
        get_slot_owner_id(storage, index),
        get_slot_generation(storage, index)
    };
}

get_slot_owner_id :: inline (storage: *Component_Storage, index: Component_Storage_Index) -> *Gen_ID {
    return *get_owner_id_list(storage, index.chunk)[index.index];
}

get_slot_generation :: inline (storage: *Component_Storage, index: Component_Storage_Index) -> *u32 {
    return *get_generation_list(storage, index.chunk)[index.index];
}

get_slot_component_memory :: inline (storage: *Component_Storage, index: Component_Storage_Index) -> *u8 {
    if index.chunk >= storage.chunks.count {
        return null;
    }
    return get_component_list_memory(storage, index.chunk) + cast(int) index.index * storage.type_size;
}

// lists

get_owner_id_list :: inline (using storage: *Component_Storage, chunk: int) -> []Gen_ID {
    array: []Gen_ID = ---;
    array.data = cast(*Gen_ID) chunks[chunk];
    array.count = ITEMS_PER_CHUNK;
    return array;
}

get_generation_list :: inline (using storage: *Component_Storage, chunk: int) -> []u32 {
    array: []u32 = ---;
    array.data = cast(*u32) (chunks[chunk] + generation_list_offset(storage));
    array.count = ITEMS_PER_CHUNK;
    return array;
}

get_component_list_memory :: inline (using storage: *Component_Storage, chunk: int) -> *u8 {
    return chunks[chunk] + component_list_offset(storage);
}

// offsets

generation_list_offset :: inline (using storage: *Component_Storage) -> int {
    return aligned_offset(0, size_of(Gen_ID), ITEMS_PER_CHUNK, size_of(u32));
}

component_pointer_list_offset :: (using storage: *Component_Storage) -> int {
    return aligned_offset(generation_list_offset(storage), size_of(u32), ITEMS_PER_CHUNK, size_of(*void));
}

component_list_offset :: inline (using storage: *Component_Storage, plus_list_size := false) -> int {
    offset := aligned_offset(generation_list_offset(storage), size_of(u32), ITEMS_PER_CHUNK, COMPONENT_ALIGN);
    if plus_list_size {
        offset = aligned_offset(offset, type_size, ITEMS_PER_CHUNK, COMPONENT_ALIGN);        
    }
    return offset;
}

#scope_file

add_chunk :: (using storage: *Component_Storage) {
    alloc_size := component_list_offset(storage, true);
    array_add(*chunks, alloc(alloc_size));

    if chunks.count > stable_tracking.slots.count {
        array_resize(*stable_tracking.slots, chunks.count,, stable_tracking.allocator);
    }
    stable_tracking.count = chunks.count * ITEMS_PER_CHUNK;

    memset(chunks[chunks.count-1], 0, alloc_size);
    owner_ids := get_owner_id_list(storage, chunks.count-1);
    for *id : owner_ids {
        id.* = .{};
    }
}

// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.
