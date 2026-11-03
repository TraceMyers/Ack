/*
todo: rewrite docs
*/

entity_handle: u32;

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
    STABLE_ID;
    MAY_NOT_HAVE_OWNER;
}
DEFAULT_COMPONENT_HANDLING_FLAGS : Component_Handling_Flags : .INITIALIZE_ON_ADD;

Component_Storage_Index :: struct {
    chunk: s32;
    index: s32;
}

Component_Slot :: struct {
    component: *u8;
    owner_id: *Gen_Ref;
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
    handling: Component_Handling_Flags;

    ITEMS_PER_CHUNK :: 64;
    COMPONENT_ALIGN :: 8;

    #assert(type_of(stable_tracking.slots[0]) == s64);
}

// interface

component_handle_to_type :: (handle: u32) -> *Type_Info {
    return engine.components[handle].tinfo;
}

add_component_type :: ($T: Type, run_init := true, init_handling := DEFAULT_COMPONENT_HANDLING_FLAGS) -> u32 {
    handle_ptr, just_added := find_or_add(*engine.type_to_component_handle, type_info(T));

    if just_added {
        array_add(*engine.components, {});
        handle_ptr.* = xx (engine.components.count - 1);

        if run_init {
            init(*engine.components[handle_ptr.*], T, init_handling);
        }
    }

    return handle_ptr.*;
}

init_engine_default_entity_components :: () {
    add_component_type(void);

    engine_check(null_handle == 0);

    entity_handle = add_component_type(Entity, init_handling = DEFAULT_COMPONENT_HANDLING_FLAGS | .MAY_NOT_HAVE_OWNER);
    add_component_type(Transform);
}

init :: (using storage: *Component_Storage, $T: Type, component_handling := DEFAULT_COMPONENT_HANDLING_FLAGS) {
    type_name = sprint("%", T);
    tinfo = type_info(T);
    
    chunks.allocator = context.allocator;
    stable_tracking.allocator = context.allocator;

    handling = component_handling;

    type_size = size_of(T);
    type_init = get_virtual_meminit(T);
    type_handle = engine.type_to_component_handle[type_info(T)];
}

get_component :: inline (ref: Component_Ref, $T: Type) -> *T {
    return cast(*T) get_component_data(ref);
}

get_component :: inline (using storage: *Component_Storage, id: Gen_ID, $T: Type) -> *T {
    return cast(*T) get_component_data(storage, id);
}

get_component_data :: inline (ref: Component_Ref) -> *void {
    return get_component_data(*engine.components[ref.handle], ref.id);
}

get_component_data :: inline (using storage: *Component_Storage, id: Gen_ID) -> *void {
    index := to_component_storage_index(id.index);
    if get_slot_generation(storage, index).* != id.generation {
        return null;
    }
    return get_slot_component_memory(storage, index);
}

add_component :: ($T: Type, owner_ref: Entity_Ref) -> Component_Instance {
    handle := engine.type_to_component_handle[type_info(T)];
    return add_component(handle, owner_ref);
}

add_component :: (handle: u32, owner_ref: Entity_Ref) -> Component_Instance {
    return add_component(*engine.components[handle], owner_ref);
}

add_component :: (using storage: *Component_Storage, owner_ref: Entity_Ref) -> Component_Instance {
    free_component_index := Component_Index.{chunks.count, 0};

    if (handling & .STABLE_ID) != 0 {
        for :only_set stable_tracking {
            free_component_index = to_component_index(it_index);
            break;
        }
    } else {
        free_component_index = to_component_index(free_index);
        free_index += 1;
    }

    if free_component_index.chunk >= chunks.count {
        engine_check(free_component_index.chunk == chunks.count && free_component_index.index == 0);
        add_chunk(storage);
    }
    
    if (handling & .STABLE_ID) != 0 {
        i := free_component_index.chunk * ITEMS_PER_CHUNK + free_component_index.value;
        stable_tracking[i] = true;
    }

    slot := get_component_slot(free_component_index);
    slot.owner_id.* = owner_ref.id;

    if (handling & .INITIALIZE_ON_ADD) != 0 {
        type_inits[it](slot.component);
    }

    index := free_component_index.chunk * ITEMS_PER_CHUNK + free_component_index.index;
    return {slot.component, {type_handle, {xx index, slot.generation.*}}};
}

remove_component :: (using storage: *Component_Storage, inst: *Component_Instance, allow_shrink := true) {
    // ----------

    clear_slot :: (component_index: Component_Index, slot: *Component_Slot) #expand {
        memset(slot.component, 0, type_size);
        slot.owner_id.* = {};
        slot.generation.* += 1;
    }

    // ----------


    component_index := to_component_storage_index(inst.id.index);
    slot := get_component_slot(component_index);

    if (handling & .STABLE_ID) != 0 {
        engine_check(stable_tracking[component_index]);
        stable_tracking[component_index] = false;
        clear_slot(component_index, slot);
    } else {
        engine_check(inst.id.index < free_index);

        last_index := free_index - 1;
        last_component_index := to_component_storage_index(last_index);
        last_slot := get_component_slot(last_component_slot);

        if inst.id.index != free_index - 1 {
            memcpy(slot.component, last_slot.component, type_size);
            slot.owner_id.* = last_slot.owner_id.*;
            slot.generation.* += 1;

            swap_slot_owner := get_entity({entity_handle, slot.owner_id});
            if swap_slot_owner {
                swap_slot_inst  := swap_slot_owner.components[tinfo];
                swap_slot_inst.data = slot.component;
                swap_slot_inst.ref.id = {inst.id.index, slot.generation.*};
            } else {
                engine_check((handling & .MAY_NOT_HAVE_OWNER) != 0);
            }
        }

        clear_slot(last_component_index, last_slot);
        free_index -= 1;
    }

    inst.* = {};
}

Component_Storage_Iteration :: struct {
    data: *void;
    owner_id: Gen_ID;
}

for_expansion :: (using storage: *Component_Storage, body: Code, flags: For_Flags) #expand {
    last_index := -1;

    using_stable_ids := (handling & .STABLE_IDS) != 0;

    if using_stable_ids {
        for :only_set_bits bit_value, bit_index : stable_tracking {
            last_index = bit_index;
            break;
        }
    } else {
        last_index = free_index - 1;
    }

    if last_index >= 0 {
        last_component_index := to_component_storage_index(last_index);

        for chunk : 0..last_component_index.chunk {
            component_mem_list := get_component_list_memory(storage, chunk);
            owner_id_list := get_owner_id_list(storage, chunk);

            last_item_index := ifx chunk == last_component_index.chunk then last_component_index.index else ITEMS_PER_CHUNK - 1;

            `it_index := chunk * ITEMS_PER_CHUNK;
            
            for item : 0..last_item_index {
                if using_stable_ids && !stable_tracking[`it_index] {
                    continue;
                }

                component := component_mem_list + type_size * item;

                `it := Component_Storage_Iteration.{component, owner_id_list[item]};
                `it_index += 1;

                #insert body;
            }
        }
    }
}

// component tracking

to_component_storage_index :: (i: int) -> Component_Storage_Index {
    #assert(is_power_of_two(Component_Storage.ITEMS_PER_CHUNK));
    DIVIDE_SHIFT :: #run shift_for_power_of_two_mul_or_div(Component_Storage.ITEMS_PER_CHUNK);
    return {i >> DIVIDE_SHIFT, i & (Component_Storage.ITEMS_PER_CHUNK - 1)};
}

get_component_slot :: inline (storage: *Component_Storage, index: Component_Storage_index) -> Component_Slot {
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
    return *get_slot_generation_list(storage, index.chunk)[index.index];
}

get_slot_component_memory :: inline (storage: *Component_Storage, index: Component_Storage_index) -> *u8 {
    if index.chunk >= storage.chunks.count {
        return null;
    }
    return *get_component_list_memory(storage, index.chunk)[index.index];
}

// lists

get_owner_id_list :: inline (using storage: *Component_Storage, chunk: int) -> []Gen_ID {
    array: []Gen_ID = ---;
    array.data = xx chunks[chunk].data;
    array.count = ITEMS_PER_CHUNK;
    return array;
}

get_generation_list :: inline (using storage: *Component_Storage, chunk: int) -> []u32 {
    array: []u32 = ---;
    array.data = xx chunks[chunk].data + generation_list_offset(storage);
    array.count = ITEMS_PER_CHUNK;
    return array;
}

get_component_list_memory :: inline (using storage: *Component_Storage, chunk: int) -> *u8 {
    return chunks[chunk].data + component_list_offset(storage);
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

    memset(chunks[chunks.count-1], 0, alloc_size);
    owner_ids := get_owner_id_list(chunks.count-1);
    for *id : owner_ids {
        id.* = {};
    }
}

// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.
