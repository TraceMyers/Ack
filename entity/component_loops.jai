// looping over all components of a type is the intended fast iteration path.
// you're looping over an array in-order, which cpu's are purpose-built for.
//
// how to use (given you have some types that are already components, like Transform):
// 
// for component_loop(Transform) {
//      it.position.x += 1;
//      entity := get_entity(it.entity_id);
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
//
// if you want component variants, where you iterate over multiple components at once,
// (most well known variant-style ECS is Unreal's MASS) you can have similar perf at 
// greater convenience + less internal complexity by just doing this:
//
// - define an entity type that has components A, B and C
// - iterate over the entity type, then get A, B and C in the loop...
//
// for component_loop(My_Entity_Variant) {
//      entity := it.data;
//      a := get_component(entity, A);
//      b := get_component(entity, B);
//      c := get_component(entity, C);
//      ...
// }
//
// this makes the most sense if entity itself has data relevant to the loop. 
// otherwise, you'd just iterate over component A and save yourself the cost
// of getting the entity.
//
// to force variant-style cache coherence across components, you can make
// all entities of this variant, and allocate their components, all at once. 
// or, make that entity's components particular only to that entity type. maybe overkill, 
// but worth trying if you're looking for a perf boost on a large entity count of some variant.

Component_Storage_Loop :: struct($T: Type, $using_data: bool) {
    storage: *Component_Storage;
}

Component_Storage_Iteration :: struct($T: Type, $using_data: bool) {
    entity_id: CID;
    #if using_data && type_info(T).type == .STRUCT {
        using data: *T;
    } else {
        data: *T;
    }
}

// if 'using_data' is true, then the per-iteration component pointer 'data' will be declared
// with 'using', meaning that instead of typing it.data.bar += 1 you can just type it.bar += 1.
component_loop :: inline ($T: Type, $using_data := true) -> Component_Storage_Loop(T, using_data) {
    return .{component_storage(T)};
}

component_loop :: inline (info: *Type_Info) -> Component_Storage_Loop(void, false) {
    return .{component_storage(info)};
}

for_expansion :: (loop: $L/Component_Storage_Loop, body: Code, flags: For_Flags) #expand {
    storage := loop.storage;
    using storage;

    using_stable_ids := (handling & .STABLE_ID) != 0;
    last_index := last_allocated_index(storage);

    if last_index >= 0 {
        last_component_index := to_component_storage_index(last_index);

        for chunk : 0..last_component_index.chunk {
            component_mem_list := get_component_list_memory(storage, chunk);
            owner_id_list := get_owner_id_list(storage, chunk);

            last_item_index := ifx chunk == last_component_index.chunk then last_component_index.index else ITEMS_PER_CHUNK - 1;

            for item : 0..last_item_index {
                slot_index := chunk * ITEMS_PER_CHUNK + item;
                if using_stable_ids && !stable_tracking[slot_index] {
                    continue;
                }

                component := component_mem_list + cast(int) type_size * item;

                `it := Component_Storage_Iteration(L.T, L.using_data).{owner_id_list[item], xx component};
                `it_index := slot_index;

                // when the user uses the 'break' keyword, it breaks outside of both loops
                #insert (break = break chunk) body;
            }
        }
    }
}
