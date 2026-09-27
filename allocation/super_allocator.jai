// it's super.
// very good on its own in a user-defined range of allocation sizes, [n, 64*n], 
// n = min allocation size. can be used for larger ones, but just not as good. 
// i have used this for strings in a text editor, was great.
// more generally, works well as a building block allocator, as in GP_Allocator.

SUPER_ALLOCATOR_MIN_ALLOCATION_SIZE :: 16;

Allocation_Header :: struct {
    // this was moved to overlay with id_sentinel in order to shrink the header overall.
    // id: Allocator_Identifier;

    // when an allocation is valid, the upper 4 bits are stamped with a specific bit pattern.
    // this is intentionally placed at byte 0 of the struct because the lowest byte of data is the one most likely to change, and so (naively speaking) most likely to change when trashed. id trashed = probably crash rather than garbagify the allocator books.
    using specific: union {
        super: struct {
            id_sentinel:       u8;
            inner_chunk:       u8;
            inner_chunk_count: u16;
            outer_chunk:       u16;
            list:              s16;
        };
        gp: struct {
            unused: u32 = ---;
            list:   s32 = ---;
        };
    };
    #overlay(specific.super.id_sentinel) id: Allocator_Identifier;
    #overlay(specific.super.id_sentinel) bit_pattern: u8 = ---;
}

Super_Allocator :: struct ($MIN_ALLOCATION_SIZE := SUPER_ALLOCATOR_MIN_ALLOCATION_SIZE) {
    using #as super_base: Allocator;
    min_alloc_size := xx MIN_ALLOCATION_SIZE;
    parent_allocator: Allocator;
    chunk_lists: [..][]Super_Allocator_Outer_Chunk(MIN_ALLOCATION_SIZE);
    books: Super_Allocator_Books;
    books_allocated_size: s64;
    default_outer_chunk_count_per_list: s32 = 32;
    shrink_to_min_lists: s32 = 1;
    default_reserve_size: s32;
    old_list_count: s32;

    CHUNKS_PER_HEAP :: 64;
    CHUNK_SIZE :: size_of(Super_Allocator_Outer_Chunk(MIN_ALLOCATION_SIZE));
    #run assert(is_power_of_two(MIN_ALLOCATION_SIZE));
    #run assert(MIN_ALLOCATION_SIZE >= ALLOCATION_HEADER_SPACE, "min allocation size: %, allocation header size: %", MIN_ALLOCATION_SIZE, ALLOCATION_HEADER_SPACE);
}

Super_Allocator_Outer_Chunk :: struct ($MIN_ALLOCATION_SIZE: s64) {
    inner_chunks: [64][MIN_ALLOCATION_SIZE]u8;
}

Super_Allocator_Books :: struct {
    largest_gap_per_list: *u8;
    gap_list_of_lists: []*u8;
    flag_list_of_lists: []*u64;
}

super_allocator_proc ::(mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, allocator_data: *void) -> *void {
    MIN_SIZE :: 16;
    MAX_SIZE :: 131072;

    dummy_super_allocator := allocator_data.(*Super_Allocator);

    #insert -> string {
        builder: String_Builder;

        print(*builder, 
#string HERE
        if dummy_super_allocator.min_alloc_size == {
HERE
        );

        size := MIN_SIZE;
        while size <= MAX_SIZE {
            print(*builder,
#string HERE
        case %;   
            super_allocator := allocator_data.(*Super_Allocator(%));
            return super_allocator_proc_impl(mode, size, old_size, old_memory, super_allocator);
HERE,
                size, size
            );
            size <<= 1;
        }

        print(*builder,
#string HERE
        case;
            engine_check(.LOW, false, "invalid super allocator min alloc size: % (must be >= % and <= %)", dummy_super_allocator.min_alloc_size, MIN_SIZE, MAX_SIZE);
        }
HERE,
            size, MIN_SIZE, MAX_SIZE
        );
        return builder_to_string(*builder);
    };
    return null;
}

super_allocator_proc_impl :: inline (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, super_allocator: *Super_Allocator) -> *void {
    if mode == {
    case .ALLOCATE;
        return super_alloc(super_allocator, size);
    case .RESIZE;
        if old_memory != null {
            super_free(super_allocator, old_memory);
        }
        return super_alloc(super_allocator, size);
    case .FREE;
        if old_memory != null {
            super_free(super_allocator, old_memory);
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

initialize_super_allocator :: (using allocator: *Super_Allocator, in_default_chunk_list_size := 0, add_chunk_lists := 1) {
    in_parent_allocator := context.allocator;
    engine_check(.LOW, chunk_lists.count == 0 && chunk_lists.data == null);

    allocator.* = .{};
    allocator.super_base.data = allocator;
    allocator.super_base.proc = super_allocator_proc;
    parent_allocator = in_parent_allocator;

    if in_default_chunk_list_size > 0 {
        default_reserve_size = xx in_default_chunk_list_size;
    } else {
        default_reserve_size = xx (CHUNK_SIZE * 8);
    }

    if add_chunk_lists > 0 {
        for 0..add_chunk_lists - 1 {
            add_chunk_list(allocator, default_reserve_size, true,,parent_allocator);
        }
    }
}

shutdown_super_allocator :: (using allocator: *Super_Allocator) {
    for list : *chunk_lists {
        array_reset(list);
    }
    array_reset(*chunk_lists);
    free(books.largest_gap_per_list);
    allocator.* = .{};
}

add_chunk_list :: (using allocator: *Super_Allocator, min_bytes: s64, remake_books := true) {
    chunk_list := array_add(*chunk_lists);
    alloc_chunk_count := max(div_ceil(min_bytes, CHUNK_SIZE), 2);

    // Super_Allocation_Header requirements
    engine_check(.LOW, chunk_lists.count <= S16_MAX);
    engine_check(.LOW, alloc_chunk_count <= U16_MAX);

    if alloc_chunk_count < 8 && !did_small_chunk_count_warning {
        log("[Super_Allocator::add_chunk_list()] min bytes % leads to only % chunks being allocated per super allocator heap. the number of chunks per heap should probably be somewhere between 8 and 128", min_bytes, alloc_chunk_count);
        did_small_chunk_count_warning = true;
    }

    chunk_list.* = make_static_array(Super_Allocator_Outer_Chunk(allocator.MIN_ALLOCATION_SIZE), alloc_chunk_count);

    // removing this option because currently grow_allocator_books assumes only one list is
    // added at a time. so, if you don't grow the books after this list was added, 
    // it will cause problems.
    // if remake_books {
        grow_super_allocator_books(allocator,,parent_allocator);
    // }
}

basic_validity_check :: inline (using header: Allocation_Header) -> bool {
    return super.list >= 0 && (bit_pattern & 0xf0) == ALLOCATOR_VALIDATION_PATTERN;
}

super_alloc :: (using allocator: *Super_Allocator, size: s64) -> *void {
    allocation_size_with_header := size + ALLOCATION_HEADER_SPACE;
    ptr := try_super_alloc(allocator, allocation_size_with_header);
    // didn't find existing space, need to grow
    if ptr == null {
        add_chunk_list(allocator, max(allocation_size_with_header, default_reserve_size),, parent_allocator);
        ptr = try_super_alloc(allocator, allocation_size_with_header);
        engine_check(.LOW, ptr != null);
    }
    return ptr.(*u8) + ALLOCATION_HEADER_SPACE;
}

super_free :: (using allocator: *Super_Allocator, ptr: *void) {
    byte_ptr := ptr.(*u8);
    header := (byte_ptr - ALLOCATION_HEADER_SPACE).(*Allocation_Header);
    engine_check(.HIGH, basic_validity_check(header.*));

    list := header.super.list;
    outer_chunk := header.super.outer_chunk;
    inner_chunk := header.super.inner_chunk;
    inner_chunk_count := header.super.inner_chunk_count;

    if inner_chunk_count > 64 {
        outer_chunk_count := div_ceil(inner_chunk_count, 64);
        engine_check(.HIGH, outer_chunk_count <= U16_MAX);
        li := *chunk_lists[list];
        start_index := outer_chunk;
        end_index := start_index + outer_chunk_count - 1;
        engine_check(.HIGH, end_index < li.count);
        for i : start_index..end_index-1 {
            flag_set := *books.flag_list_of_lists[list][i];
            engine_check(.HIGH, (flag_set.* & U64_MAX) == U64_MAX);
            flag_set.* = 0;
            gap := *books.gap_list_of_lists[list][i];
            gap.* = 64;
            inner_chunk_count -= 64;
        }
        outer_chunk = end_index;
        inner_chunk = 0;
    }

    mask: u64 = ---;
    if inner_chunk_count == 64 {
        mask = U64_MAX;
    } else {
        mask = (((1).(u64) << (inner_chunk_count)) - 1) << (inner_chunk);
    }

    flag_set := *books.flag_list_of_lists[list][outer_chunk];
    engine_check(.HIGH, flag_set.* & mask == mask, "\nflag set: \n%, \nmask: \n%", FormatInt.{value=flag_set.*, base=2, minimum_digits=64}, FormatInt.{value=mask, base=2, minimum_digits=64});
    flag_set.* &= ~mask;

    gap := *books.gap_list_of_lists[list][outer_chunk];
    gap.* = xx largest_gap_in_bit_sequence_lsb(flag_set.*);

    largest_gap := *books.largest_gap_per_list[list];
    if inner_chunk_count > 64 {
        largest_gap.* = 64;
    } else if gap.* > largest_gap.* {
        max_gap: u8;
        for chunk : 0..chunk_lists[list].count-1 {
            gap = *books.gap_list_of_lists[list][outer_chunk];
            max_gap = max(max_gap, gap.*);
            if max_gap == CHUNKS_PER_HEAP then break;
        }
        largest_gap.* = max_gap;
    }

    header.* = .{};
}

try_super_alloc :: (using allocator: *Super_Allocator, size: s64) -> *void {
    header: *Allocation_Header;
    alloc_inner_chunk_count := div_ceil(size, allocator.MIN_ALLOCATION_SIZE);
    if alloc_inner_chunk_count > 64 {
        header = try_super_alloc_large(allocator, alloc_inner_chunk_count);
    } else {
        header = try_super_alloc_small(allocator, alloc_inner_chunk_count);
    }
    if header != null {
        // (these two fields are unioned)
        header.id = .SUPER_ALLOCATOR;
        header.bit_pattern |= ALLOCATOR_VALIDATION_PATTERN;
    }
    return header;
}

try_super_alloc_small :: (using allocator: *Super_Allocator, alloc_inner_chunk_count: s64) -> *Allocation_Header {
    alloc_mask: u64 = ---;
    if alloc_inner_chunk_count == 64 {
        alloc_mask = U64_MAX;
    } else {
        alloc_mask = ((1).(u64) << alloc_inner_chunk_count) - (1).(u64);
    }

    out_header: *Allocation_Header;
    allocated_gap_is_max := false;

    if chunk_lists.count > 0 then for list : 0..chunk_lists.count-1 {
        largest_gap := *books.largest_gap_per_list[list];
        if largest_gap.* >= alloc_inner_chunk_count {
            max_gap: u8;
            for chunk : 0..chunk_lists[list].count-1 {
                gap := *books.gap_list_of_lists[list][chunk];
                // only need to go in here if we haven't found the allocation that must be in this list yet...
                if out_header == null && gap.* >= alloc_inner_chunk_count {
                    allocated_gap_is_max = gap.* == largest_gap.*;
                    flag_set := *books.flag_list_of_lists[list][chunk];
                    alloc_index := find_index_of_missing_bit_sequence_lsb(flag_set.*, alloc_mask, alloc_inner_chunk_count);
                    flag_set.* |= alloc_mask << alloc_index;
                    gap.* = xx largest_gap_in_bit_sequence_lsb(flag_set.*);
                    out_header = (*chunk_lists[list][chunk].inner_chunks[alloc_index]).(*Allocation_Header);
                    out_header.super.list = xx list;
                    out_header.super.outer_chunk = xx chunk;
                    out_header.super.inner_chunk = xx alloc_index;
                    out_header.super.inner_chunk_count = xx alloc_inner_chunk_count;
                    if !allocated_gap_is_max {
                        max_gap = largest_gap.*;
                        break;
                    }
                }
                // ...otherwise, if we have found it, we're just doing bookkeeping
                max_gap = max(max_gap, gap.*);
                if max_gap == CHUNKS_PER_HEAP {
                    break;
                }
            }
            engine_check(.HIGH, out_header != null);
            largest_gap.* = max_gap;
            break;
        }
    }

    return out_header;
}

try_super_alloc_large :: (using allocator: *Super_Allocator, alloc_inner_chunk_count: s64) -> *Allocation_Header {
    engine_check(.LOW, alloc_inner_chunk_count > 64);
    alloc_outer_chunk_count := div_ceil(alloc_inner_chunk_count, 64);
    engine_check(.LOW, alloc_outer_chunk_count <= U16_MAX);

    out_header: *Allocation_Header;

    if chunk_lists.count > 0 then for list_index : 0..chunk_lists.count-1 {
        largest_gap := books.largest_gap_per_list[list_index];
        if largest_gap < 64 {
            continue;
        }
        chunk_index := 0;
        consecutive_free_outer_chunk_ct := 0;
        list := *chunk_lists[list_index];
        while chunk_index + alloc_outer_chunk_count <= list.count {
            gap := books.gap_list_of_lists[list_index][chunk_index];
            if gap == 64 {
                consecutive_free_outer_chunk_ct += 1;
                if consecutive_free_outer_chunk_ct == alloc_outer_chunk_count {
                    first_chunk_index := chunk_index - (alloc_outer_chunk_count-1);
                    last_chunk_index := first_chunk_index + (alloc_outer_chunk_count-1);
                    remain_inner_chunks := alloc_inner_chunk_count;
                    for c : first_chunk_index..last_chunk_index {
                        if remain_inner_chunks >= 64 {
                            books.gap_list_of_lists[list_index][c] = 0;
                            books.flag_list_of_lists[list_index][c] = U64_MAX;
                        } else {
                            books.gap_list_of_lists[list_index][c] = xx (64 - remain_inner_chunks);
                            books.flag_list_of_lists[list_index][c] = ((1).(u64) << remain_inner_chunks) - 1;
                        }
                        remain_inner_chunks -= 64;
                    }
                    out_header = (*list.*[first_chunk_index].inner_chunks[0]).(*Allocation_Header);
                    out_header.super.list = xx list_index;
                    out_header.super.outer_chunk = xx first_chunk_index;
                    out_header.super.inner_chunk = 0;
                    out_header.super.inner_chunk_count = xx alloc_inner_chunk_count;
                    break;
                }
            } else {
                consecutive_free_outer_chunk_ct = 0;
            }
            chunk_index += 1;
        }
        if out_header != null then break;
    }

    return out_header;
}

// todo: this function assumes ONE new list is being appended to the allocator data
// if I want this to be able to grow once after multiple lists are added (which would be 
// preferable for init), then this needs to be edited / rewritten.
grow_super_allocator_books :: (using allocator: *Super_Allocator) {
    // ---

    // for debuggging with memory view, set bytes to something nonzero and repeating
    write_debug_bytes_for_memory_view :: (bytes: *u8, byte_count: s64) {
        memset(bytes, 0xaf, byte_count);
    }

    // ---

    auto_release_temp();
    engine_check(.LOW, chunk_lists.count > 0);

    reader: []u8;
    reader.data = books.largest_gap_per_list;
    reader.count = books_allocated_size;
    reader_head: s64 = 0;

    writer := make_dynamic_array(u8, max(reader.count * 2, 2048),,temp);
    writer_head: s64 = 0;

    // write_debug_bytes_for_memory_view(writer.data, writer.allocated);

    do_copy := old_list_count > 0;
    if do_copy {
        engine_check(.LOW, books.largest_gap_per_list != null);
    }

    // ----- gap super list -----

    if do_copy {
        // copy the old super list
        write_and_read_bytes(*writer, reader, *writer_head, *reader_head, old_list_count);
    }

    // add a new final entry indicating 64 inner chunks is the largest available allocation in the new list
    free_count : u8 = 64;
    write_bytes(*writer, *writer_head, *free_count, 1);

    // ----- gap array datas -----

    gap_array_datas_offset := writer_head;
    if do_copy {
        // copy over each array of gaps
        for 0..chunk_lists.count-2 {
            write_and_read_bytes(*writer, reader, *writer_head, *reader_head, chunk_lists[it].count);
        }
    }
    // create new array of gaps
    final_list := *chunk_lists[chunk_lists.count-1];
    for 0..final_list.count-1 {
        write_bytes(*writer, *writer_head, *free_count, 1);
    }
    
    // all reads and writes going forward are 8-byte aligned, this only needs to be done once.
    serial_align_head_up(*reader_head, 8, reader.count);
    serial_writer_resize_if_needed(*writer, writer_head+8);
    serial_align_head_up(*writer_head, 8, writer.count);

    // ----- flag array datas -----

    flag_array_datas_offset := writer_head;
    if do_copy {
        // copy over each array of flags
        for 0..chunk_lists.count-2 {
            write_and_read_bytes(*writer, reader, *writer_head, *reader_head, xx (chunk_lists[it].count * 8), 8);
        }
    }
    // create new array of flags
    zero_u64 : u64 = 0;
    for 0..final_list.count-1 {
        write_bytes(*writer, *writer_head, xx *zero_u64, 8, 8);
    }

    // ----- gap array pointers -----

    pointers_to_gap_arrays_offset := writer_head;
    running_gap_array_offset : u64 = xx gap_array_datas_offset;
    if do_copy {
        // write offsets to gap array datas. will add base address later
        for 0..chunk_lists.count-2 {
            write_bytes(*writer, *writer_head, xx *running_gap_array_offset, 8, 8);
            running_gap_array_offset += xx chunk_lists[it].count;
        }
    }
    // create new offset/pointer to gap array datas
    write_bytes(*writer, *writer_head, xx *running_gap_array_offset, 8, 8);

    // ----- flag array pointers -----

    pointers_to_flag_arrays_offset := writer_head;
    running_flag_array_offset : u64 = xx flag_array_datas_offset;
    if do_copy {
        // write offsets to flag array datas. will add base address later
        for 0..chunk_lists.count-2 {
            write_bytes(*writer, *writer_head, xx *running_flag_array_offset, 8, 8);
            running_flag_array_offset += xx (chunk_lists[it].count * 8);
        }
    }
    // create new offset/pointer to flag array datas
    write_bytes(*writer, *writer_head, xx *running_flag_array_offset, 8, 8);

    old_allocation: *u8 = books.largest_gap_per_list;
    new_books_data_allocation: *u8;
    new_books_data_size: s64;

    if writer_head > books_allocated_size {
        new_books_data_size = ceil_to_power_of_two_multiple(max(writer_head, 1024), 2);
        new_books_data_allocation = make_static_array(u8, new_books_data_size,, parent_allocator).data;
        if old_allocation != null {
            free(old_allocation,,parent_allocator);
        }
    } else {
        new_books_data_size = books_allocated_size;
        new_books_data_allocation = old_allocation;
    }

    memset(new_books_data_allocation, 0, new_books_data_size);
    memcpy(new_books_data_allocation, writer.data, writer_head);

    // tell the books struct where its data is
    books.largest_gap_per_list = new_books_data_allocation;
    books.gap_list_of_lists.data = xx (new_books_data_allocation + pointers_to_gap_arrays_offset);
    books.gap_list_of_lists.count = chunk_lists.count;
    books.flag_list_of_lists.data = xx (new_books_data_allocation + pointers_to_flag_arrays_offset);
    books.flag_list_of_lists.count = chunk_lists.count;

    // previously, because we didn't know what the address of the allocation would be, when we created arrays of pointers,
    // we had to store offsets rather than actual addresses. now that we know the allocation address, we can add that
    // so the pointer points to the right place.
    for 0..chunk_lists.count-1 {
        gap_array_offset_from_allocation_head := books.gap_list_of_lists[it].(u64);
        books.gap_list_of_lists[it] = (new_books_data_allocation + gap_array_offset_from_allocation_head).(*u8);
        flag_array_offset_from_allocation_head := books.flag_list_of_lists[it].(u64);
        books.flag_list_of_lists[it] = (new_books_data_allocation.(u64) + flag_array_offset_from_allocation_head).(*u64);
    }

    books_allocated_size = new_books_data_size;
    old_list_count = xx chunk_lists.count;
}

repr :: (using allocator: *Super_Allocator) -> string {
    builder: String_Builder;
    builder.allocator = temp;
    for list : 0..chunk_lists.count-1 {
        print_to_builder(*builder, "list %:\n", FormatInt.{value=list, minimum_digits=2});
        for chunk : 0..chunk_lists[list].count-1 {
            print_to_builder(*builder, "\tchunk %: [%|%]\n", 
                FormatInt.{value=chunk, minimum_digits=3}, 
                FormatInt.{value=books.gap_list_of_lists[list][chunk], minimum_digits=2},
                FormatInt.{value=books.flag_list_of_lists[list][chunk], base=2, minimum_digits=64},
            );
        }
    }
    return builder_to_string(*builder);
}

// asking for an explicit allocator here rather than expecting .. ,, allocator) syntax
// because it's very important to not use the allocator that's being snapshotted.
// the fact that it's an explicit parameter means the body of this proc can
// know if an allocator was passed. works even if the super allocator is composed into
// another allocator.
snapshot :: (using allocator: *Super_Allocator, allocate_with: *Allocator = null) -> []Allocator_Heap_Snapshot {

    snapshots: [..]Allocator_Heap_Snapshot;
    if allocate_with == null {
        snapshots.allocator = context.default_allocator;
    } else {
        snapshots.allocator = allocate_with.*;
    }
    array_resize(*snapshots, chunk_lists.count);

    for *snapshots {
        it.allocated_blocks.allocator = snapshots.allocator;
    }

    add_chunk :: (begin: s32, end: s32) #expand {
        offset_begin := cast(s32) (`chunk_begin + begin * MIN_ALLOCATION_SIZE);
        offset_end   := cast(s32) (offset_begin + end * MIN_ALLOCATION_SIZE);
        array_add(*`snapshot.allocated_blocks, .[offset_begin, offset_end]);
    }

    if chunk_lists.count > 0 then for list : 0..chunk_lists.count-1 {
        snapshot := *snapshots[list];
        array_reserve(*snapshot.allocated_blocks, chunk_lists[list].count * 16);

        snapshot.begin_address = xx chunk_lists[list].data;
        snapshot.end_address   = snapshot.begin_address + chunk_lists[list].count * CHUNK_SIZE;

        for chunk : 0..chunk_lists[list].count-1 {
            allocated_block_flags := (cast(*s64) *books.flag_list_of_lists[list][chunk]).*;
            chunk_begin := chunk * CHUNK_SIZE;
            block_begin : s32 = -1;

            if allocated_block_flags == 0xffff_ffff_ffff_ffff {
                add_chunk(0, 64);
            } else if allocated_block_flags != 0 {
                // gap_size := books.gap_list_of_lists[list][chunk];
                // assert(gap_size != 0, "flags: 0x%, gap size: %", FormatInt.{value=allocated_block_flags, base=16, minimum_digits=16}, gap_size);
                // largest_gap := books.largest_gap_per_list[list];
                // assert(largest_gap != 0, "flags: 0x%, largest gap: %", FormatInt.{value=allocated_block_flags, base=16, minimum_digits=16}, largest_gap);

                for 0..63 {
                    if (allocated_block_flags & (1 << it)) != 0 {
                        if block_begin == -1 {
                            block_begin  = xx it;
                        }
                    } else {
                        if block_begin != -1 {
                            add_chunk(block_begin, xx it);
                            block_begin = -1;
                        }
                    }
                }
                
                if block_begin != -1 {
                    add_chunk(block_begin, 64);
                }
            }
        }
    }

    return snapshots;
}

// 0: one byte gap per chunk list
// 1: array of gap bytes per chunk list, laid out one after another
// 2: align to 8 bytes
// 3: array of flag u64s per chunk list, laid out one after another
// 4. one slice per chunk list, each pointing into [1]
// 5. one slice per chunk list, each pointing into [3]

// books "array data offset" offsets to [4]

/*
Super_Allocator {
    books pointers:

    ----------- largest_gap_array_ptr    
    |     ----- lists_of_gaps_array_ptr 
    |     |     flag_set_array_ptr ---------------------------------------
    |     |                                                               |
    |     ------------------------------------------                      |
    v                                              V                      v
    [gaps data | lists_of_gaps data | flags data | [lists_of_gaps_ptrs] | [flags_ptrs]
                  ^    ^   ^   ^                    |  |   |   |           |   |  |  |
                  |    |   |   |--------------------   |   |   |           (point into the flags data. omitted arrows because diagram would get confusing)
                  |    |   |---------------------------|   |   |
                  |    |------------------------------------   |
                  |--------------------------------------------|

*/

#scope_module

// tiny dual-head serializer implementation for Super_Allocator stuff
// -----------------------------------------------------------------------------------

write_bytes :: (record: *[..]u8, record_head: *s64, bytes: *u8, byte_count: s64, align : s8 = 1) {
    if byte_count == 0 {
        return;
    }

    serial_align_head_up(record_head, align, record.count);
    new_head := record_head.* + byte_count;

    serial_writer_resize_if_needed(record, new_head);
    memcpy(record.data + record_head.*, bytes, byte_count);   

    record_head.* = new_head;
}

write_and_read_bytes :: (writer: *[..]u8, reader: []u8, writer_head: *s64, reader_head: *s64, byte_count: s64, align : s8 = 1) {
    if byte_count == 0 {
        return;
    }

    serial_align_head_up(reader_head, align, writer.count);
    serial_align_head_up(writer_head, align, reader.count);
    new_reader_head := reader_head.* + byte_count;
    new_writer_head := writer_head.* + byte_count;

    serial_writer_resize_if_needed(writer, new_writer_head);
    engine_check(.LOW, reader_head.* <= reader.count);
    memcpy(writer.data + writer_head.*, reader.data + reader_head.*, byte_count);

    reader_head.* = new_reader_head;
    writer_head.* = new_writer_head;
}

serial_writer_resize_if_needed :: (record: *[..]u8, new_head: s64) {
    if new_head >= record.count {
        array_resize(record, new_head, false);
    }
}

serial_advance_head :: inline (record_head: *s64, by_count: s64, memory_size: s64) {
    new_head := record_head.* + by_count;
    engine_check(.LOW, by_count > 0);
    engine_check(.LOW, record_head.* >= 0 && record_head.* <= memory_size);
    engine_check(.LOW, new_head <= memory_size);
    record_head.* = new_head;
}

serial_align_head_up :: (record_head: *s64, align: s8, memory_size: s64) {
    new_head := ceil_to_power_of_two_multiple(record_head.*, align);
    diff := new_head - record_head.*;
    if diff > 0 {
        serial_advance_head(record_head, diff, memory_size);
    } else engine_check(.LOW, diff == 0);
}

did_small_chunk_count_warning := false;
