// memory is split into pages of 64 chunks, and chunks into 64 slots. an allocation is a run of
// 1 to 64 slots inside a single chunk, so every search and update is a few ops on one u64.
// allocations bigger than 64 slots are passed straight through to the data allocator.
//
// all books live outside the managed memory, so the data allocator can be the gpu_allocator
// (pointers are then masked GPU_Allocations, which only ever get added to and compared).
//
// chains well: pages are 4096 * slot_size bytes, which is exactly the max in-grid allocation of an
// Allocator_64 with 64x the slot size. so 16 -> 1024 -> context.allocator is a decent gp allocator.
//
// can be scoped to a heap by starting it under push_allocator(heap). see make_heap.

ALLOCATOR_64_RUN_BUCKETS :: 7; // free runs of >= 1, 2, 4, 8, 16, 32, 64 slots

Allocator_64 :: struct {
    using #as base: Allocator;
    using body: Allocator_64_Body;
    pages:     Pool(Allocator_64_Page);
    // sorted by begin. used to find the page (or oversized allocation) an address belongs to.
    ranges:    [..]Allocator_64_Range;
    // bit p: page p has a chunk with a free run >= 1 << bucket
    page_fits: [ALLOCATOR_64_RUN_BUCKETS][..]u64;
    // root gpu allocator, if this memory lives on the gpu
    gpu:       *GPU_Allocator;
    gpu_min_align:    s64;
    slot_shift:       u8;
    empty_page_count: s32;
}

Allocator_64_Body :: struct {
    // power of two. max in-grid allocation is 64 * slot_size, page size is 4096 * slot_size.
    slot_size        := 16;
    // alignment requested for pages, and so the max alignment this allocator can satisfy.
    page_align       := 64;
    keep_empty_pages := 1;
    books_allocator: Allocator;
    data_allocator:  Allocator;
}

Allocator_64_Page :: struct {
    begin:  *u8; // may be a masked GPU_Allocation
    used:   [64]u64;
    starts: [64]u64; // bit set at the first slot of each allocation
    fits:   [ALLOCATOR_64_RUN_BUCKETS]u64; // bit c: chunk c has a free run >= 1 << bucket
    used_slot_count: s32;
}

Allocator_64_Range :: struct {
    begin: u64;
    end:   u64;
    // what the data allocator returned. differs from begin if it ignored the requested alignment.
    raw:   *void;
    // -1 = oversized, passed straight through to the data allocator
    page:  s32;
}

allocator_64_proc :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, allocator_data: *void) -> *void {
    allocator := cast(*Allocator_64) allocator_data;

    if #complete mode == {
    case .ALLOCATE;
        return allocator_64_allocate(allocator, size);
    case .RESIZE;
        return allocator_64_resize(allocator, size, old_size, old_memory);
    case .FREE;
        allocator_64_free(allocator, old_memory);
        return null;
    case .STARTUP;
        return allocator_64_startup(allocator);
    case .SHUTDOWN;
        allocator_64_shutdown(allocator);
        return null;
    case .THREAD_START; #through;
    case .THREAD_STOP;
        engine_check(false, "multithreaded access not supported");
        return null;
    case .CREATE_HEAP; #through;
    case .DESTROY_HEAP;
        engine_check(false, "creating and destoying heaps not supported");
        return null;
    case .IS_THIS_YOURS;
        if find_range(allocator, xx old_memory) >= 0 {
            return cast(*void) true;
        }
        return null;
    case .CAPS;
        return xx (Allocator_Caps.FREE | .ACTUALLY_RESIZE | .IS_THIS_YOURS);
    }
    return null;
}

allocator_64_startup :: (using allocator: *Allocator_64) -> *void {
    engine_check(is_power_of_two(slot_size), "slot size % is not a power of two", slot_size);
    engine_check(is_power_of_two(page_align) && page_align <= slot_size * 4096, "bad page align %", page_align);
    engine_check(pool_is_empty(*pages) && ranges.count == 0);

    allocator.base = {proc=allocator_64_proc, data=allocator};

    if data_allocator.proc == null {
        data_allocator = context.allocator;
    }
    if books_allocator.proc == null {
        books_allocator = context.allocator;
    }

    slot_shift = xx (bit_scan_forward(slot_size) - 1);

    // for gpu memory, the heap determines a minimum alignment, so the root gpu allocator is needed
    // to look up heaps. it's found through any number of Allocator_64s.
    if data_allocator.proc == gpu_allocator_proc {
        gpu = xx data_allocator.data;
    } else if data_allocator.proc == allocator_64_proc {
        gpu = (cast(*Allocator_64) data_allocator.data).gpu;
    }

    pool_set_allocator(*pages, books_allocator);
    ranges.allocator = books_allocator;
    for *page_fits {
        it.allocator = books_allocator;
    }
    return null;
}

allocator_64_shutdown :: (using allocator: *Allocator_64) {
    for ranges {
        free(it.raw,, data_allocator);
    }
    array_reset(*ranges);
    for *page_fits {
        array_reset(it);
    }
    pool_reset(*pages);
    allocator.* = {};
}

allocator_64_allocate :: (using allocator: *Allocator_64, size: s64) -> *void {
    if size <= 0 {
        return null;
    }

    align := cast(s64) context.allocator_align;
    if gpu != null {
        if pool_is_empty(*pages) {
            add_page(allocator);
        }
        align = max(align, gpu_min_align);
    }
    engine_check(is_power_of_two(align) && align <= page_align, "alignment % unsupported (page align is %)", align, page_align);

    slot_count := (size + slot_size - 1) >> slot_shift;
    if slot_count > 64 {
        begin, raw := data_alloc(allocator, size, align);
        add_range(allocator, .{begin=xx begin, end=xx (begin + size), raw=raw, page=-1});
        return begin;
    }

    // alignment beyond the slot size means only some slots are legal starts. alignment beyond
    // the chunk size means only some chunks are.
    stride_log2 := bit_scan_reverse(max(align >> slot_shift, 1)) - 1;
    slot_starts  := LEGAL_STARTS[min(stride_log2, 6)];
    chunk_starts := LEGAL_STARTS[max(stride_log2 - 6, 0)];

    // ceil(log2(slot_count)). every chunk in this bucket has a big enough run.
    bucket := bit_scan_reverse(slot_count - 1);
    memory := allocate_in_bucket(allocator, bucket, slot_count, slot_starts, chunk_starts);
    // the bucket below may have runs that fit too, if slot_count isn't a power of two
    if memory == null && bucket > 0 && !is_power_of_two(slot_count) {
        memory = allocate_in_bucket(allocator, bucket - 1, slot_count, slot_starts, chunk_starts);
    }
    if memory == null {
        // a fresh page is aligned to page_align, so slot 0 is always a legal start
        memory = take(allocator, add_page(allocator), 0, 0, slot_count);
    }
    return memory;
}

allocator_64_free :: (using allocator: *Allocator_64, memory: *void) {
    if memory == null {
        return;
    }

    range_index := find_range(allocator, xx memory);
    engine_check(range_index >= 0, "% wasn't allocated by this allocator", memory);
    range := ranges[range_index];

    if range.page < 0 {
        array_ordered_remove_by_index(*ranges, range_index);
        free(range.raw,, data_allocator);
        return;
    }

    page := *pages.items[range.page];
    chunk, slot := get_chunk_and_slot(allocator, page, memory);
    slot_count := run_length(page, chunk, slot);

    page.used[chunk]   &= ~(run_mask(slot_count) << cast(u64) slot);
    page.starts[chunk] &= ~((cast(u64) 1) << cast(u64) slot);
    page.used_slot_count -= xx slot_count;
    update_fits(allocator, range.page, chunk);

    if page.used_slot_count == 0 {
        if empty_page_count >= keep_empty_pages {
            release_page(allocator, range.page);
        } else {
            empty_page_count += 1;
        }
    }
}

allocator_64_resize :: (using allocator: *Allocator_64, size: s64, old_size: s64, old_memory: *void) -> *void {
    if old_memory == null {
        return allocator_64_allocate(allocator, size);
    }
    if size <= 0 {
        allocator_64_free(allocator, old_memory);
        return null;
    }

    range_index := find_range(allocator, xx old_memory);
    engine_check(range_index >= 0, "% wasn't allocated by this allocator", old_memory);
    range := ranges[range_index];
    new_slot_count := (size + slot_size - 1) >> slot_shift;

    // try in place. shrinking always works, growing works if the slots after the run are free.
    if range.page >= 0 && new_slot_count <= 64 {
        page := *pages.items[range.page];
        chunk, slot    := get_chunk_and_slot(allocator, page, old_memory);
        old_slot_count := run_length(page, chunk, slot);
        diff_mask      := (run_mask(new_slot_count) ^ run_mask(old_slot_count)) << cast(u64) slot;

        if new_slot_count <= old_slot_count {
            page.used[chunk] &= ~diff_mask;
            page.used_slot_count -= xx (old_slot_count - new_slot_count);
            update_fits(allocator, range.page, chunk);
            return old_memory;
        } else if slot + new_slot_count <= 64 && (page.used[chunk] & diff_mask) == 0 {
            page.used[chunk] |= diff_mask;
            page.used_slot_count += xx (new_slot_count - old_slot_count);
            update_fits(allocator, range.page, chunk);
            return old_memory;
        }
    }

    engine_check(gpu == null, "can't move gpu memory on resize");
    new_memory := allocator_64_allocate(allocator, size);
    memcpy(new_memory, old_memory, min(size, old_size));
    allocator_64_free(allocator, old_memory);
    return new_memory;
}

snapshot :: (using allocator: *Allocator_64, allocate_with: *Allocator = null) -> []Allocator_Heap_Snapshot {
    use_allocator := ifx allocate_with == null then context.default_allocator else allocate_with.*;

    snapshots: [..]Allocator_Heap_Snapshot;
    snapshots.allocator = use_allocator;

    for range : ranges {
        snapshot := array_add(*snapshots);
        snapshot.* = .{begin_address=xx range.begin, end_address=xx range.end};
        snapshot.allocated_blocks.allocator = use_allocator;

        if range.page < 0 {
            array_add(*snapshot.allocated_blocks, .[0, xx (range.end - range.begin)]);
            continue;
        }

        page := *pages.items[range.page];
        for chunk : 0..63 {
            starts := page.starts[chunk];
            while starts != 0 {
                slot := bit_scan_forward(starts) - 1;
                starts &= starts - 1;
                block_begin := (chunk * 64 + slot) << slot_shift;
                block_end   := block_begin + (run_length(page, chunk, slot) << slot_shift);
                array_add(*snapshot.allocated_blocks, .[xx block_begin, xx block_end]);
            }
        }
    }

    return snapshots;
}

#scope_file

// legal start bits for a run, indexed by log2 of the stride between legal starts
LEGAL_STARTS :: u64.[
    0xffff_ffff_ffff_ffff,
    0x5555_5555_5555_5555,
    0x1111_1111_1111_1111,
    0x0101_0101_0101_0101,
    0x0001_0001_0001_0001,
    0x0000_0001_0000_0001,
    0x0000_0000_0000_0001,
];

allocate_in_bucket :: (using allocator: *Allocator_64, bucket: s64, slot_count: s64, slot_starts: u64, chunk_starts: u64) -> *void {
    for word, word_index : page_fits[bucket] {
        candidate_pages := word;
        while candidate_pages != 0 {
            page_index := word_index * 64 + bit_scan_forward(candidate_pages) - 1;
            candidate_pages &= candidate_pages - 1;

            page := *pages.items[page_index];
            candidate_chunks := page.fits[bucket] & chunk_starts;
            while candidate_chunks != 0 {
                chunk := bit_scan_forward(candidate_chunks) - 1;
                candidate_chunks &= candidate_chunks - 1;

                slot := find_run(page.used[chunk], slot_count, slot_starts);
                if slot >= 0 {
                    return take(allocator, page_index, chunk, slot, slot_count);
                }
            }
        }
    }
    return null;
}

// lowest legal start of a run of slot_count free bits, or -1.
// after the loop, bit i is set only if bits i..i+slot_count-1 are all free. bits shifted in
// from the top are 0, so a run can't extend past the chunk.
find_run :: inline (used: u64, slot_count: s64, legal_starts: u64) -> s64 {
    free_bits := ~used;
    covered := 1;
    while covered < slot_count {
        shift := min(covered, slot_count - covered);
        free_bits &= free_bits >> cast(u64) shift;
        covered += shift;
    }
    free_bits &= legal_starts;
    if free_bits == 0 {
        return -1;
    }
    return bit_scan_forward(free_bits) - 1;
}

// length of the allocation starting at slot: used bits up to the next free bit or the next start
run_length :: inline (page: *Allocator_64_Page, chunk: s64, slot: s64) -> s64 {
    later_starts := (page.starts[chunk] >> cast(u64) slot) & ~(cast(u64) 1);
    run_bits     := (page.used[chunk] >> cast(u64) slot) & ~later_starts;
    if run_bits == U64_MAX {
        return 64;
    }
    return bit_scan_forward(~run_bits) - 1;
}

run_mask :: inline (slot_count: s64) -> u64 {
    if slot_count == 64 {
        return U64_MAX;
    }
    return ((cast(u64) 1) << cast(u64) slot_count) - 1;
}

get_chunk_and_slot :: inline (using allocator: *Allocator_64, page: *Allocator_64_Page, memory: *void) -> chunk: s64, slot: s64 {
    offset := (cast(*u8) memory) - page.begin;
    engine_check((offset & (slot_size - 1)) == 0, "% isn't the start of an allocation", memory, level=.HIGH);
    slot_index := offset >> slot_shift;
    chunk := slot_index >> 6;
    slot  := slot_index & 63;
    engine_check((page.starts[chunk] & ((cast(u64) 1) << cast(u64) slot)) != 0, "% isn't the start of an allocation", memory, level=.HIGH);
    return chunk, slot;
}

take :: (using allocator: *Allocator_64, page_index: s64, chunk: s64, slot: s64, slot_count: s64) -> *void {
    page := *pages.items[page_index];
    if page.used_slot_count == 0 {
        empty_page_count -= 1;
    }
    page.used[chunk]   |= run_mask(slot_count) << cast(u64) slot;
    page.starts[chunk] |= (cast(u64) 1) << cast(u64) slot;
    page.used_slot_count += xx slot_count;
    update_fits(allocator, page_index, chunk);
    return page.begin + ((chunk * 64 + slot) << slot_shift);
}

// recompute which buckets chunk is in, then whether the page is in each bucket.
// each step halves the runs that survive: after step b, set bits begin runs >= 1 << (b + 1).
update_fits :: (using allocator: *Allocator_64, page_index: s64, chunk: s64) {
    page      := *pages.items[page_index];
    chunk_bit := (cast(u64) 1) << cast(u64) chunk;
    page_word := page_index >> 6;
    page_bit  := (cast(u64) 1) << cast(u64) (page_index & 63);

    free_bits := ~page.used[chunk];
    for b : 0..ALLOCATOR_64_RUN_BUCKETS-1 {
        if free_bits != 0 {
            page.fits[b] |= chunk_bit;
        } else {
            page.fits[b] &= ~chunk_bit;
        }
        if page.fits[b] != 0 {
            page_fits[b][page_word] |= page_bit;
        } else {
            page_fits[b][page_word] &= ~page_bit;
        }
        if b < ALLOCATOR_64_RUN_BUCKETS-1 {
            free_bits &= free_bits >> cast(u64) (1 << b);
        }
    }
}

add_page :: (using allocator: *Allocator_64) -> s64 {
    page_size  := slot_size * 4096;
    begin, raw := data_alloc(allocator, page_size, page_align);

    page_index := pool_borrow(*pages);
    page := *pages.items[page_index];
    page.begin = begin;

    page_word := page_index >> 6;
    page_bit  := (cast(u64) 1) << cast(u64) (page_index & 63);
    for b : 0..ALLOCATOR_64_RUN_BUCKETS-1 {
        page.fits[b] = U64_MAX;
        if page_fits[b].count <= page_word {
            array_resize(*page_fits[b], page_word + 1);
        }
        page_fits[b][page_word] |= page_bit;
    }

    if gpu != null {
        gpu_min_align = get_heap(gpu, begin).min_alignment;
    }

    empty_page_count += 1;
    add_range(allocator, .{begin=xx begin, end=xx (begin + page_size), raw=raw, page=xx page_index});
    return page_index;
}

release_page :: (using allocator: *Allocator_64, page_index: s64) {
    range_index := find_range(allocator, xx pages.items[page_index].begin);
    raw := ranges[range_index].raw;
    array_ordered_remove_by_index(*ranges, range_index);
    free(raw,, data_allocator);

    page_word := page_index >> 6;
    page_bit  := (cast(u64) 1) << cast(u64) (page_index & 63);
    for b : 0..ALLOCATOR_64_RUN_BUCKETS-1 {
        page_fits[b][page_word] &= ~page_bit;
    }
    pool_return(*pages, page_index);
}

// on the gpu, heaps start at offset 0, so the fallback for ignored alignment never happens there.
data_alloc :: (using allocator: *Allocator_64, size: s64, align: s64) -> begin: *u8, raw: *void {
    push_allocator(data_allocator, align);
    raw := alloc(size);
    if ((cast(u64) raw) & cast(u64) (align - 1)) == 0 {
        return raw, raw;
    }
    free(raw);
    raw = alloc(size + align - 1);
    return cast(*u8) ceil_to_power_of_two_multiple(cast(u64) raw, cast(u64) align), raw;
}

// index of the range containing address, or -1
find_range :: (using allocator: *Allocator_64, address: u64) -> s64 {
    index := upper_bound(allocator, address) - 1;
    if index < 0 || address >= ranges[index].end {
        return -1;
    }
    return index;
}

add_range :: (using allocator: *Allocator_64, range: Allocator_64_Range) {
    array_insert_at(*ranges, range, upper_bound(allocator, range.begin));
}

// index of the first range that begins after address
upper_bound :: (using allocator: *Allocator_64, address: u64) -> s64 {
    low  := 0;
    high := ranges.count;
    while low < high {
        mid := (low + high) / 2;
        if ranges[mid].begin <= address {
            low = mid + 1;
        } else {
            high = mid;
        }
    }
    return low;
}

#scope_export

allocator_64_test :: () -> bool {
    a: Allocator_64;
    a.data_allocator = context.default_allocator;
    allocator_64_startup(*a);
    defer allocator_64_shutdown(*a);

    Live :: struct {
        memory: *u8;
        size:   s64;
        stamp:  u8;
    }
    live: [..]Live;
    live.allocator = temp;

    stamp_is_intact :: (l: Live) -> bool {
        for 0..l.size-1 {
            if l.memory[it] != l.stamp then return false;
        }
        return true;
    }

    // in-grid, oversized, and over-aligned allocations, with random frees mixed in
    for 0..9_999 {
        size  := random_get_within_range(1, 64 * 16 * 2).(s64);
        align := 8 << (it % 4);
        context.allocator_align = xx align;
        memory := alloc(size,,a).(*u8);
        test_condition((memory.(u64) & (align - 1).(u64)) == 0);

        l := Live.{memory, size, xx (it % 255 + 1)};
        memset(l.memory, l.stamp, l.size);
        array_add(*live, l);

        if it & 1 {
            index := random_get_within_range(0, (live.count-1).(float)).(s64);
            test_condition(stamp_is_intact(live[index]));
            free(live[index].memory,,a);
            array_unordered_remove_by_index(*live, index);
        }
    }
    context.allocator_align = 8;

    for live {
        test_condition(stamp_is_intact(it));
        free(it.memory,,a);
    }

    // everything freed: only the kept empty pages are left
    test_condition(a.ranges.count <= a.keep_empty_pages);

    return true;
} @engine_test

// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.
