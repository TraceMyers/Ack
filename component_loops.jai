// SINGLE COMPONENT LOOPS
//
// looping over all components of one type is typically the fastest approach, because
// you're looping over an array in-order, which cpu's are purpose-built for.
//
// how to use (given you have some types that are already components, like Transform):
// 
// for component_loop(Transform) {
//      it.position.x += 1;
//      some_other_component := get_component(it.entity, Some_Other_Component);
//      ...
// }
//
// or you can get the component opaquely (*void) and do stuff with it despite not knowing the type
// at compile time.
//
// some_type_info: *Type_Info = foo();
// for component_loop(some_type_info) {
//     memset(it.data, 0, some_type_info.runtime_size); 
//     ...
// }

Component_Storage_Loop :: struct($T: Type, $using_data: bool) {
    storage: *Component_Storage;
}

Component_Storage_Iteration :: struct($T: Type, $using_data: bool) {
    entity: *Entity;
    #if using_data && type_info(T).type == .STRUCT {
        using data: *T;
    } else {
        data: *T;
    }
}

// if 'using_data' is true, then the per-iteration component pointer 'data' will be declared
// with 'using', meaning that instead of typing it.data.bar += 1 you can just type it.bar += 1.
component_loop :: ($T: Type, $using_data := true) -> *Component_Storage_Loop(T, using_data) {
    return {*engine.components[engine.type_to_component_handle[info]]};
}

component_loop :: (info: *Type_Info) -> Component_Storage_Loop(void, false) {
    return {*engine.components[engine.type_to_component_handle[info]]};
}

for_expansion :: (loop: *Component_Storage_Loop, body: Code, flags: For_Flags) #expand {
    using loop.storage;

    last_index := -1;

    using_stable_ids := (handling & .STABLE_IDS) != 0;
    last_index := last_allocated_index(storage);

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

                `it := Component_Storage_Iteration(loop.T, loop.using_data).{get_entity(owner_id_list[item]), xx component};
                `it_index += 1;

                #insert body;
            }
        }
    }
}

// MULTI COMPONENT LOOPS
//
// iterate over all rows of 'entity, component a, component b, ...'
// for all entities that have the entire list 'component a, component b, ...'
// 
// less efficient than single component loops in a handful of ways:
// 1. creation overhead after many components already exist is nonzero. (so it's probably better
// to create these loops on startup.)
// 2. cache coherence is okay-to-meh, because access is pretty random. depends on how coherent
// the arrays themselves are with each other.
// 3. each component-get is a hash table lookup, and each iteration uses a different table.
// 4. every combination you make adds some overhead to removing and adding a component within
// that combination.
//
// BUT, it's convenient. so, here's how to use:
//
// during startup...
// important_loop := make_component_combination_loop({"hair", Hair}, {"butt", Butt}, {"hairy_butt", "Hairy_Butt"});
//
// later..
// for important_loop {
//      measure(it.hair);
//      weigh(it.butt);
//      observe(it.entity, it.hairy_butt);
// }

Component_Combination_Handle :: u16;

Component_Combination :: struct {
    handle: Component_Combination_Handle;
    types: []*Type_Info;
    entities_with_combination: [..]Gen_ID;
}

Component_Combination_Loop_Item :: struct {
    name: string;
    type: Type;
}

Component_Combination_Loop :: struct (items: ..Component_Combination_Loop_Item) {
    handle: u16;
}

// the 'it' of a for_expansion when looping over a Component_Combination_Loop.
// expands the fields of the loop to a pointer per component + the entity, for example:
// Component_Combination_Loop({"transform", Transform}, {"move", Movement})
// gives 'it.entity', 'it.transform' and 'it.move' pointers.
Component_Combination_Iteration :: struct(items: ..Component_Combination_Loop_Item) {
    entity: *Entity;

    #insert -> string {
        builder: String_Builder;
        for items {
            print(*builder, "%: *%;\n", it.name, it.type);
        }
        return builder_to_string(*builder);
    }
}

make_component_combination_loop :: (items: ..Component_Combination_Loop_Item) -> Component_Combination_Loop(..items) {
    engine_check(Ts.count > 1);

    new_combo := array_add(*engine.component_combinations);
    new_combo.handle = engine.component_combinations.count - 1;
    new_combo.types = make_static_array(*Type_Info, items.count);

    entities := *engine.components[entity_handle];

    entity_has_component: [2]Bit_Array;
    entity_max := last_allocated_index(entities);

    init_bit_array(*entity_has_component[0], entity_max + 1,, temp);
    init_bit_array(*entity_has_component[1], entity_max + 1,, temp);
    slot_count := entity_has_components[0].slots.count;

    for item, i : items {
        component_handle := engine.type_to_component_handle[type_info(item.type)].*;
        storage := *engine.components[component_handle];
        array_add(*storage.combinations, xx new_combo.handle);

        new_combo.types[i] = type_info(T);

        if i == 0 then for storage {
            entity_has_component[0][it.owner_id.index] = true;
        } else {
            for storage {
                entity_has_component[1][it.owner_id.index] = true;
            }
            for 0..slot_count-1 {
                entity_has_component[0].slots[it] &= entity_has_component[1].slots[it];
            }
            clear_all_bits(*entity_has_component[1];
        }
    }

    for :only_set entity_has_component[0] {
        component_index := to_component_storage_index(it_index);
        entity_id := {xx it_index, get_slot_generation(entities, component_index).*};
        array_add(*new_combo.entities_with_combination, entity_id);
    }

    return { new_combo.handle };
}

for_expansion :: (loop: Component_Combination_Loop, body: Code, flags: For_Flags) #expand {
    #assert((flags & .POINTER) == 0);

    combo := *engine.component_combinations[loop.handle];
    engine_check(combo.types.count == loop.items.count);

    entities := *engine.components[entity_handle];

    for <=((flags & .REVERSE) != 0) id, i : combo.entities_with_combination {
        `it_index := i;

        `it: Component_Combination_Iteration(..loop.items);
        `it.entity = get_component(entities, id, Entity);

        #insert -> string {
            builder: String_Builder;
            for item : loop.items {
                print(*builder, "`it.% = get_component(`it.entity, %);\n", item.name, item.type);
            }
            return builder_to_string(*builder);
        };

        #insert body;
    }
}
