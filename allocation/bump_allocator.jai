// bump/arena, no auto resize

BUMP_ALLOCATOR_DEFAULT_HEAP_SIZE : s32 : 16 * 1024 * 1024; // 16MB

Bump_Allocator :: struct {
    using #as base: Allocator;
    parent_allocator: Allocator;
    heap: Bump_Allocator_Heap;
}

Bump_Allocator_Heap :: struct {
    bytes: []u8;
    end: s32;
}

bump_allocator_initialize :: (using bump: *Bump_Allocator, in_heap_size := BUMP_ALLOCATOR_DEFAULT_HEAP_SIZE) {
    parent_allocator = context.allocator;
    engine_check(.LOW, in_heap_size > 0);
    in_heap_size = ceil_to_power_of_two_multiple(in_heap_size, 8);
    proc = bump_allocator_proc;
    data = bump;
    heap = .{};
    heap.bytes = make_static_array(u8, in_heap_size);
}

bump_allocator_proc :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, allocator_data: *void) -> *void {
    if mode == {
    case .ALLOCATE;
        return bump_allocator_allocate(xx allocator_data, size);
    case .RESIZE;
        return bump_allocator_resize(xx allocator_data, size, old_size, old_memory);
    case .FREE;
        // could be useful for debug
    case .CREATE_HEAP;
        // bump_allocator_initialize(xx allocator_data);
    case .DESTROY_HEAP;
        bump_allocator_reset(xx allocator_data, false);
    }
    return null;
}

bump_allocator_allocate :: (using bump: *Bump_Allocator, size: s64) -> *void {
    new_size := heap.end + size;
    engine_check(.LOW, new_size <= heap.bytes.count);
    data_out := *heap.bytes[heap.end];
    memset(data_out, 0, size);
    // align everything to 8 because it's easy and works fine I think
    heap.end += xx size;
    heap.end = ceil_to_power_of_two_multiple(heap.end, 8);

    return data_out;
}

bump_allocator_resize :: (using bump: *Bump_Allocator, size: s64, old_size: s64, old_memory: *void) -> *void {
    if size <= old_size {
        return old_memory;
    }
    new_memory := bump_allocator_allocate(bump, size);
    memcpy(new_memory, old_memory, old_size);
    return new_memory;
}

bump_allocator_reset :: (using bump: *Bump_Allocator, keep_memory := true) {
    if keep_memory {
        heap.end = 0;
    } else {
        if heap.bytes.count > 0 {
            free(heap.bytes.data,,parent_allocator);
        }
        bump.* = .{};
    }
}

auto_reset_to_high_water_mark :: (using bump: *Bump_Allocator) #expand {
    _mark := heap.end;
    `defer reset_to_high_water_mark(bump, _mark);
}

get_high_water_mark :: (using bump: *Bump_Allocator) -> s32 {
    return heap.end;
}

reset_to_high_water_mark :: (using bump: *Bump_Allocator, mark: s32) {
    engine_check(.LOW, heap.bytes.count >= mark);
    heap.end = mark;
}

scope_mark_and_recede_allocations :: (using bump: *Bump_Allocator) #expand {
    mark := get_high_water_mark(bump);
    `defer reset_to_high_water_mark(bump, mark);
}

snapshot :: (using allocator: *Bump_Allocator, allocate_with: *Allocator = null) -> []Allocator_Heap_Snapshot {

    use_allocator := ifx allocate_with == null then context.default_allocator else allocate_with.*;

    snapshots: []Allocator_Heap_Snapshot;
    snapshots.data = alloc(size_of(Allocator_Heap_Snapshot),, use_allocator);
    snapshots.count = 1;

    snapshot := *snapshots[0];
    snapshot.* = {};
    snapshot.allocated_blocks.allocator = use_allocator;

    if heap.end > 0 {
        snapshot.begin_address = xx heap.bytes.data;    
        snapshot.end_address = snapshot.begin_address + heap.bytes.count;
        array_add(*snapshot.allocated_blocks, .[0, xx heap.end]);
    }

    return snapshots;
}

snapshot :: (using pool: *Flat_Pool, allocate_with: *Allocator = null) -> []Allocator_Heap_Snapshot {

    use_allocator := ifx allocate_with == null then context.default_allocator else allocate_with.*;

    snapshots: []Allocator_Heap_Snapshot;
    snapshots.data = alloc(size_of(Allocator_Heap_Snapshot),, use_allocator);
    snapshots.count = 1;

    snapshot := *snapshots[0];
    snapshot.* = {};
    snapshot.allocated_blocks.allocator = use_allocator;

    // note that allocator snapshots don't care about what parts of the pool
    // aren't committed.
    allocated_size := cast(s64) current_point - cast(s64) memory_base;
    if allocated_size > 0 {
        snapshot.begin_address = xx memory_base;    
        snapshot.end_address   = xx address_limit;
        array_add(*snapshot.allocated_blocks, .[0, xx allocated_size]);
    }

    return snapshots;
}
