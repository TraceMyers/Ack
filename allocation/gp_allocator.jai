// general purpose allocator
// release build, tight loops, tested ~50ns for small allocations and ~500ns for medium to large. 
// still probably needs work and likely has bugs. probably needs explicit debug support...

GP_Allocator :: struct {
    MIN_BIN_ITEM_SIZE :: 16;
    ITEMS_PER_LIST :: 128;
    INITIAL_LIST_COUNT_PER_BIN :: 50;
    using #as base: Allocator;
    bins: [8]GP_Bin;
    med_allocator: Super_Allocator(4096);
    lrg_allocator: Super_Allocator(131072);
    parent_allocator: Allocator;
}

GP_Bin :: struct {
    first_available : s32 = -1;
    lists: [..][]u8;
}

gp_allocator_proc :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, allocator: *void) -> *void {
    gp_allocator := allocator.(*GP_Allocator);
    if mode == {
    case .ALLOCATE;
        return gp_alloc(gp_allocator, size);
    case .RESIZE;
        new_allocation := gp_alloc(gp_allocator, size);
        if old_memory != null {
            memcpy(new_allocation, old_memory, min(size, old_size));
            gp_free(gp_allocator, xx old_memory);
        }
        return new_allocation;
    case .FREE;
        if old_memory != null {
            gp_free(gp_allocator, old_memory);
        }
    case .STARTUP;
    case .SHUTDOWN;
    case .THREAD_START;
    case .THREAD_STOP;
    case .CREATE_HEAP;
    case .DESTROY_HEAP;
    case .IS_THIS_YOURS;
    case .CAPS;
    }
    return null;
}

// last checked, defaults give ~70MB
initialize_gp_allocator :: (using allocator: *GP_Allocator, add_medium_chunk_lists := 4, add_large_chunk_lists := 1) {
    in_parent_allocator := context.allocator;
    allocator.* = .{parent_allocator=in_parent_allocator};
    base.data = allocator;
    base.proc = gp_allocator_proc;
    for *bin : bins {
        bin_index := it_index;
        for 1..INITIAL_LIST_COUNT_PER_BIN {
            gp_allocator_add_list(allocator, bin_index);
        }
    }
    initialize_super_allocator(allocator=*med_allocator, add_chunk_lists=add_medium_chunk_lists,, parent_allocator);
    initialize_super_allocator(allocator=*lrg_allocator, add_chunk_lists=add_large_chunk_lists,, parent_allocator);
}

gp_allocator_add_list :: (using allocator: *GP_Allocator, bin_index: s64) {
    engine_check(.LOW, bin_index >= 0 && bin_index < bins.count);
    item_size := MIN_BIN_ITEM_SIZE << bin_index;
    list_size := item_size * ITEMS_PER_LIST;
    bin := *bins[bin_index];
    list := array_add(*bin.lists);
    list.data = alloc(item_size * ITEMS_PER_LIST,,parent_allocator);
    list.count = item_size * ITEMS_PER_LIST;

    item_index_begin : s32 = xx ((bin.lists.count - 1) * ITEMS_PER_LIST);
    for < 0..ITEMS_PER_LIST-2 {
        item_slot : *s32 = xx (list.data + item_size * it);
        item_slot.* = item_index_begin + (it.(s32) + 1);
    }

    final_slot : *s32 = xx (list.data + item_size * (ITEMS_PER_LIST - 1));
    if bin.first_available == -1 {
        final_slot.* = -1;
    } else {
        final_slot.* = bin.first_available;        
    }
    bin.first_available = item_index_begin;
}

gp_alloc :: (using allocator: *GP_Allocator, alloc_size: s64) -> *void {
    size_with_header := alloc_size + ALLOCATION_HEADER_SPACE;
    
    if alloc_size <= 0 {
        return null;
    } else if size_with_header <= 2048 {
        // small allocations, fast track
        bin_index := max(bit_scan_reverse((size_with_header-1) >> 3) - 1, 0);
        bin := *bins[bin_index];
        if bin.first_available == -1 {
            gp_allocator_add_list(allocator, bin_index);
        }
        engine_check(.HIGH, bin.first_available != -1);
        item_size := MIN_BIN_ITEM_SIZE << bin_index;
        list_index := bin.first_available / ITEMS_PER_LIST;
        item_index := bin.first_available - list_index * ITEMS_PER_LIST;
        allocation := bin.lists[list_index].data + item_index * item_size;

        bin.first_available = allocation.(*s32).*;

        allocation.(*Allocation_Header).id = xx ((Allocator_Identifier.GP_ALLOCATOR_16.(s32) + bin_index) | ALLOCATOR_VALIDATION_PATTERN);
        allocation.(*Allocation_Header).gp.list = xx list_index;

        return allocation + ALLOCATION_HEADER_SPACE;
    } else if size_with_header < 131072 {
        // medium allocations ~(2-130KB)
        allocation := super_alloc(*med_allocator, alloc_size);
        header := (allocation.(*u8) - ALLOCATION_HEADER_SPACE).(*Allocation_Header);
        // overwrite the id so the allocator can be identified on free
        header.id = xx (Allocator_Identifier.GP_ALLOCATOR_SUPER_MED.(s32) | ALLOCATOR_VALIDATION_PATTERN);
        return allocation;
    } else {
        // large allocations (130KB+)
        allocation := super_alloc(*lrg_allocator, alloc_size);
        header := (allocation.(*u8) - ALLOCATION_HEADER_SPACE).(*Allocation_Header);
        // overwrite the id so the allocator can be identified on free
        header.id = xx (Allocator_Identifier.GP_ALLOCATOR_SUPER_LRG.(s32) | ALLOCATOR_VALIDATION_PATTERN);
        return allocation;
    }
}

gp_free :: (using allocator: *GP_Allocator, addr: *u8) {
    header := (addr - ALLOCATION_HEADER_SPACE).(*Allocation_Header);
    // log("free header address: %", header.(u64));
    identifier := (header.bit_pattern & 0x0f).(Allocator_Identifier);
    if identifier >= .GP_ALLOCATOR_16 && identifier <= .GP_ALLOCATOR_2048 {
        engine_check(.HIGH, (header.bit_pattern & 0xf0) == ALLOCATOR_VALIDATION_PATTERN, "bad validation bits %", (header.bit_pattern & 0xf0));

        bin_index        := (identifier - .GP_ALLOCATOR_16).(s64);
        item_size        := MIN_BIN_ITEM_SIZE << bin_index;
        bin              := *bins[bin_index];
        list_index       := header.gp.list;
        list_data_begin  := bin.lists[list_index].data;
        list_data_end    := list_data_begin + item_size * ITEMS_PER_LIST;

        engine_check(.HIGH, header.(*u8) >= list_data_begin && header.(*u8) < list_data_end);

        item_index       := (header.(*u8) - list_data_begin) / item_size;
        block_index : s32 = xx (list_index * ITEMS_PER_LIST + item_index);

        // prefer allocating out lower-indexed blocks first
        if block_index < bin.first_available {
            header.(*s32).*     = bin.first_available;
            bin.first_available = block_index;
        } else {
            first_available_list  := bin.first_available / ITEMS_PER_LIST;
            first_available_index := bin.first_available % ITEMS_PER_LIST;
            next_available_block  := cast(*s32) (bin.lists[first_available_list].data + first_available_index * item_size);
            header.(*s32).*        = next_available_block.*;
            next_available_block.* = block_index;
        }
    } else if identifier == { 
    case .GP_ALLOCATOR_SUPER_MED;
        // this id was overwritten so it could be directed to the medium allocator. need to fix it so the super allocator can validate
        header.id = xx (Allocator_Identifier.SUPER_ALLOCATOR.(s32) | ALLOCATOR_VALIDATION_PATTERN);
        super_free(*med_allocator, addr);
    case .GP_ALLOCATOR_SUPER_LRG;
        // this id was overwritten so it could be directed to the large allocator. need to fix it so the super allocator can validate
        header.id = xx (Allocator_Identifier.SUPER_ALLOCATOR.(s32) | ALLOCATOR_VALIDATION_PATTERN);
        super_free(*lrg_allocator, addr);
    case;
        engine_check(.LOW, false, "invalid id for allocation %", identifier);
    }
}

snapshot :: (using allocator: *GP_Allocator, small_bin_index: int, allocate_with: *Allocator = null) -> []Allocator_Heap_Snapshot {
    use_allocator := ifx allocate_with == null then context.default_allocator else allocate_with.*;

    snapshots: []Allocator_Heap_Snapshot;

    bin := *bins[small_bin_index];
    unallocated_bin := bin.first_available;
    item_size := MIN_BIN_ITEM_SIZE << small_bin_index;

    array_resize(*snapshots, bin.lists.count,, use_allocator);
    for *snapshots {
        it.allocated_blocks.allocator = use_allocator;
        array_reserve(*it.allocated_blocks, ITEMS_PER_LIST / 16);
        list := *bins[small_bin_index].lists[it_index];
        it.begin_address = xx list.data;
        it.end_address   = xx (it.begin_address + list.count);
    }

    item_is_allocated := make_bit_array(bin.lists.count * ITEMS_PER_LIST,, temp); 
    set_all_bits(*item_is_allocated);

    while unallocated_bin != -1 {
        clear_bit(*item_is_allocated, unallocated_bin);
        list  := unallocated_bin / ITEMS_PER_LIST;
        index := unallocated_bin % ITEMS_PER_LIST;
        item_loc := bin.lists[list].data + (index * item_size);
        item_s32 := (cast(*s32) item_loc).*;
        unallocated_bin = item_s32;
    }

    add_blocks :: (snapshots: []Allocator_Heap_Snapshot, first: int, end: int, item_size: int) {
        begin_list  := first     / ITEMS_PER_LIST;
        begin_index := first     % ITEMS_PER_LIST;
        end_list    := (end - 1) / ITEMS_PER_LIST;
        end_index   := end       % ITEMS_PER_LIST;
        if end_index == 0 then end_index = ITEMS_PER_LIST;

        for list : begin_list..end_list {
            begin_i := 0;
            end_i   := ITEMS_PER_LIST;
            if list == begin_list {
                begin_i = begin_index;
            }
            if list == end_list {
                end_i = end_index;
            }
            array_add(*snapshots[list].allocated_blocks, .[cast(s32) (begin_i * item_size), cast(s32) (end_i * item_size)]);
        }
    }

    last_empty := -1;

    for :only_cleared_bits item_is_allocated {
        first         := last_empty + 1;
        end           := it_index;
        set_bit_count := end - first;
        if set_bit_count > 0 {
            add_blocks(snapshots, first, end, item_size);
        }
        last_empty = it_index;
    }

    if last_empty < item_is_allocated.count - 1 {
        add_blocks(snapshots, last_empty + 1, item_is_allocated.count, item_size);
    }

    return snapshots;
}

// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.
