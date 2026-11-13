/*
todo: rewrite docs
*/

// global engine component handles
physics_body_handle: u16;

// types

Component_ID :: struct {
    type_handle: u16;
    generation: u16;
    index: s32 = -1;
}

operator == :: (a: Component_ID, b: Component_ID) -> bool {
    if a.index < 0 && b.index < 0 return true;
    return a.type_handle == b.type_handle && a.index == b.index && a.generation == b.generation;
}

Component_Instance :: struct {
    data: *void;
    id: Component_ID;
}

Component_Handling_Flags :: enum_flags {
    INITIALIZE_ON_ADD;
    DEINITIALIZE_ON_REMOVE;
    STABLE_ID;
}

DEFAULT_COMPONENT_HANDLING_FLAGS : Component_Handling_Flags : .INITIALIZE_ON_ADD | .DEINITIALIZE_ON_REMOVE;

Component_Storage_Index :: struct {
    chunk: s32;
    index: s32;
}

Component_Slot :: struct {
    component: *u8;
    owner_id: *Entity_ID;
    generation: *u16;
}

Component_Storage :: struct {
    type_name: string;
    tinfo: *Type_Info;

    chunks: [..]*u8;
    stable_tracking: Bit_Array;
    free_index: s32;
    type_size: u32;

    type_handle: u16;

    type_init: (*void);
    type_deinit: (*void);

    handling: Component_Handling_Flags;
    component_is_entity: bool;

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

add_entity_type :: ($T: Type) -> handle: u16 {
    #assert(is_subclass_of(T, "Entity"));
    entity_flags := DEFAULT_COMPONENT_HANDLING_FLAGS | .STABLE_ID;
    return add_component_type(T, init_handling=entity_flags);
}

add_component_type :: ($T: Type, init_handling := DEFAULT_COMPONENT_HANDLING_FLAGS, override_init: (*void) = null, deinit: (*void) = null) -> u16 {
    handle_ptr, just_added := find_or_add(*engine.type_to_component_handle, type_info(T));

    if just_added {
        engine_check(engine.components.count <= 0xFFFF, "too many component types for a u16 handle");
        array_add(*engine.components, {});
        handle_ptr.* = xx (engine.components.count - 1);
        init(*engine.components[handle_ptr.*], T, init_handling, override_init, deinit);
    }

    return handle_ptr.*;
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

    component_is_entity = T == Entity || is_subclass_of(T, "Entity");
}

get_component :: inline (id: Component_ID, $T: Type) -> *T {
    return cast(*T) get_component_data(id);
}

get_component_data :: inline (id: Component_ID) -> *void {
    return get_component_data(*engine.components[id.type_handle], id.index, id.generation);
}

get_component_data :: inline (using storage: *Component_Storage, slot_index: int, generation: u16) -> *void {
    if slot_index < 0 return null;
    index := to_component_storage_index(slot_index);
    if index.chunk >= chunks.count return null;
    if get_slot_generation(storage, index).* != generation {
        return null;
    }
    return get_slot_component_memory(storage, index);
}

add_component :: ($T: Type, owner_id: Entity_ID) -> Component_Instance {
    handle := table_find_pointer(*engine.type_to_component_handle, type_info(T)).*;
    return add_component(handle, owner_id);
}

add_component :: (handle: u16, owner_id: Entity_ID) -> Component_Instance {
    return add_component(*engine.components[handle], owner_id);
}

add_component :: (using storage: *Component_Storage, owner_id: Entity_ID) -> Component_Instance {
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
    slot.owner_id.* = owner_id;

    if (handling & .INITIALIZE_ON_ADD) != 0 {
        type_init(slot.component);
    }

    index := free_component_index.chunk * ITEMS_PER_CHUNK + free_component_index.index;
    return {slot.component, {type_handle, slot.generation.*, xx index}};
}

remove_component :: (id: Component_ID, allow_shrink := true) {
    inst := Component_Instance.{get_component_data(id), id};
    remove_component(inst, allow_shrink);
}

remove_component :: (inst: Component_Instance, allow_shrink := true) {
    // ----------

    clear_slot :: (slot: Component_Slot, type_size: int) {
        memset(slot.component, 0, type_size);
        slot.owner_id.* = .{};
        slot.generation.* += 1;
    }

    // ----------

    using storage: *Component_Storage = *engine.components[inst.id.type_handle];

    component_index := to_component_storage_index(inst.id.index);
    slot := get_component_slot(storage, component_index);

    if (handling & .DEINITIALIZE_ON_REMOVE) != 0 && type_deinit != null {
        type_deinit(slot.component);
    }

    old_owner_id := slot.owner_id.*;

    if (handling & .STABLE_ID) != 0 {
        engine_check(stable_tracking[inst.id.index]);
        stable_tracking[inst.id.index] = false;
        clear_slot(slot, type_size);
    } else {
        // swap-back of last component into the removed component's slot
        engine_check(inst.id.index < free_index);

        last_index := free_index - 1;
        last_component_index := to_component_storage_index(last_index);
        last_slot := get_component_slot(storage, last_component_index);

        if inst.id.index != free_index - 1 {
            memcpy(slot.component, last_slot.component, type_size);
            slot.owner_id.* = last_slot.owner_id.*;
            slot.generation.* += 1;

            // the last slot's owner needs their component pointer & tracking data updated
            if !is_null(slot.owner_id) {
                swap_slot_owner := get_entity(slot.owner_id.*);

                looking_for_id := Component_ID.{type_handle, last_slot.generation.*, last_index};
                fixed_component_data_on_entity: bool;

                for allocation : swap_slot_owner.component_allocations {
                    if allocation.id == looking_for_id {
                        pointer_to_component_field := (cast(*u8) entity) + allocation.offset_to_pointer;
                        component_ptr := cast(**void) pointer_to_component_field;
                        engine_check(component_ptr.* == last_slot.component);

                        component_ptr.* = slot.component;
                        allocation.id = {type_handle, slot.generation.*, inst.id.index};

                        fixed_component_data_on_entity = true;
                        break;
                    }
                }
                engine_check(fixed_component_data_on_entity);
            }
        }

        clear_slot(last_slot, type_size);
        free_index -= 1;
    }

    // todo: shrink
}

last_allocated_index :: (using storage: *Component_Storage) -> int {
    if (handling & .STABLE_ID) != 0 {
        for < :only_set_bits bit_value, bit_index : stable_tracking {
            return bit_index;
        }
        return -1;
    } else {
        return free_index - 1;
    }
}

init_engine_default_entity_components :: () {
    null_handle := add_component_type(void);
    engine_check(null_handle == 0);

    // stable ids so body indexes stored in the contact grid never move
    physics_body_handle = add_component_type(Physics_Body, init_handling = DEFAULT_COMPONENT_HANDLING_FLAGS | .STABLE_ID, deinit=xx deinit_physics_body);

    add_component_type(Static_Mesh_Instance);
    add_component_type(Skeletal_Mesh_Instance);
    add_component_type(Input);
    add_component_type(Camera);
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

// offsets

generation_list_offset :: inline (using storage: *Component_Storage) -> int {
    return aligned_offset(0, size_of(Entity_ID), ITEMS_PER_CHUNK, size_of(u16));
}

component_pointer_list_offset :: (using storage: *Component_Storage) -> int {
    return aligned_offset(generation_list_offset(storage), size_of(u16), ITEMS_PER_CHUNK, size_of(*void));
}

component_list_offset :: inline (using storage: *Component_Storage, plus_list_size := false) -> int {
    offset := aligned_offset(generation_list_offset(storage), size_of(u16), ITEMS_PER_CHUNK, COMPONENT_ALIGN);
    if plus_list_size {
        offset = aligned_offset(offset, type_size, ITEMS_PER_CHUNK, COMPONENT_ALIGN);        
    }
    return offset;
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

get_slot_owner_id :: inline (storage: *Component_Storage, index: Component_Storage_Index) -> *Entity_ID {
    return *get_owner_id_list(storage, index.chunk)[index.index];
}

get_slot_generation :: inline (storage: *Component_Storage, index: Component_Storage_Index) -> *u16 {
    return *get_generation_list(storage, index.chunk)[index.index];
}

get_slot_component_memory :: inline (storage: *Component_Storage, index: Component_Storage_Index) -> *u8 {
    if index.chunk >= storage.chunks.count {
        return null;
    }
    return get_component_list_memory(storage, index.chunk) + cast(int) index.index * storage.type_size;
}

// lists

get_owner_id_list :: inline (using storage: *Component_Storage, chunk: int) -> []Entity_ID {
    array: []Entity_ID = ---;
    array.data = cast(*Entity_ID) chunks[chunk];
    array.count = ITEMS_PER_CHUNK;
    return array;
}

get_generation_list :: inline (using storage: *Component_Storage, chunk: int) -> []u16 {
    array: []u16 = ---;
    array.data = cast(*u16) (chunks[chunk] + generation_list_offset(storage));
    array.count = ITEMS_PER_CHUNK;
    return array;
}

get_component_list_memory :: inline (using storage: *Component_Storage, chunk: int) -> *u8 {
    return chunks[chunk] + component_list_offset(storage);
}

// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.
