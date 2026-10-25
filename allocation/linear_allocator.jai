// can be scoped to a heap by starting it under push_allocator(heap). see make_heap.
Linear_Allocator :: struct {
    using #as base: Allocator;
    using body: Linear_Allocator_Body;
    pages: [..]Linear_Allocator_Page;
    cur_page: int = -1;
}

Linear_Allocator_Page :: struct {
    bytes: []u8;
    // bytes allocated out of this heap.
    allocated: int;
}

Linear_Allocator_Body :: struct {
    default_page_size := 64 * 1024 * 1024;
    books_allocator: Allocator;
    data_allocator:  Allocator;
    data_allocator_align := 8;
}

linear_allocator_proc :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, allocator_data: *void) -> *void {
    allocator := cast(*Linear_Allocator) allocator_data;

    if #complete mode == {
    case .FREE;
        return null;
    case .RESIZE; 
        if size <= old_size {
            return old_memory;
        }
        // resize not supported for gpu allocations because that would require a copy
        // and I don't want to do that rn.
        engine_check(allocator.data_allocator.proc != gpu_allocator_proc); 
        allocation := linear_allocator_allocate(allocator, size);
        memcpy(allocation, old_memory, min(size, old_size));
        return allocation;
    case .ALLOCATE;
        return linear_allocator_allocate(allocator, size);
    case .STARTUP;
        return linear_allocator_startup(allocator);
    case .SHUTDOWN;
        linear_allocator_shutdown(allocator);
        return null;
    case .THREAD_START; 
        #through;
    case .THREAD_STOP;
        engine_check(false, "multithreaded access not supported");
        return null;
    case .CREATE_HEAP; 
        #through;
    case .DESTROY_HEAP;
        engine_check(false, "creating and destoying heaps not supported");
        return null;
    case .IS_THIS_YOURS;
        if allocator.cur_page >= 0 then for p : 0..allocator.cur_page {
            page := *allocator.pages[p];
            byte_diff := cast(*u8) old_memory - page.bytes.data;
            if byte_diff >= 0 && byte_diff < page.allocated {
                return cast(*void) true;
            }
        }
        return null;
    case .CAPS;
        return xx Allocator_Caps.IS_THIS_YOURS;
    }
}

linear_allocator_startup :: (using allocator: *Linear_Allocator) -> *void {
    engine_check(default_page_size > 0);
    engine_check(pages.count == 0);
    
    allocator.base = {proc=linear_allocator_proc, data=allocator};

    if data_allocator.proc == null {
        data_allocator = context.allocator;
    }
    if books_allocator.proc == null {
        books_allocator = context.allocator;
    }
    
    pages.allocator = books_allocator;
    return null;
}

linear_allocator_allocate :: (using allocator: *Linear_Allocator, size: s64) -> *void {
    engine_check(is_power_of_two(context.allocator_align), level=.HIGH);

    if data_allocator.proc == null {
        data_allocator = context.allocator;
    }

    if size == 0 {
        return null;
    }

    align := context.allocator_align;
    page  := get_current_page(allocator, size + xx align);

    begin_address: *void;
    remaining_bytes: int;
    aligned_size := size;

    if page != null {
        // for gpu allocations, the memory's purpose determines the minimum alignment,
        // making it the only situation where a lower-level allocator determines alignment
        // to a higher-level one.
        if data_allocator.proc == gpu_allocator_proc {
            align = max(get_heap(xx data_allocator.data, cast(*void) page.bytes.data).min_alignment, align);
        }

        begin_address, aligned_size = get_begin_address_and_aligned_size(page, size, align);
        remaining_bytes             = page.bytes.count - page.allocated;
    }
    
    if remaining_bytes < aligned_size {
        page                        = add_page(allocator, max(size + xx align, default_page_size));
        // if gpu allocation, after getting a new page, align param doesn't matter because
        // the 4 lower order bytes will always be 0.
        begin_address, aligned_size = get_begin_address_and_aligned_size(page, size, align);
    }

    page.allocated += xx aligned_size;
    return begin_address;
}

linear_allocator_reset_keeping_memory :: (allocator: *Linear_Allocator) {
    for *allocator.pages {
        it.allocated = 0;
    }
    allocator.cur_page = ifx allocator.pages.count > 0 then 0 else -1;
}

linear_allocator_reset :: (allocator: *Linear_Allocator) {
    save_body := allocator.body;
    linear_allocator_shutdown(allocator);
    allocator.body = save_body;
    linear_allocator_startup(allocator);
}

linear_allocator_shutdown :: (allocator: *Linear_Allocator) {
    for page : allocator.pages {
        array_free(page.bytes,, allocator.data_allocator);
    }
    array_reset(*allocator.pages);
    allocator.* = {};
}

#scope_file

get_current_page :: (allocator: *Linear_Allocator, alloc_size: int) -> *Linear_Allocator_Page {
    if allocator.pages.count == 0 {
        return null;
    }
    return *allocator.pages[allocator.cur_page];
}

add_page :: (allocator: *Linear_Allocator, size: int) -> *Linear_Allocator_Page {
    allocator.cur_page += 1;
    while allocator.cur_page < allocator.pages.count {
        page := *allocator.pages[allocator.cur_page];
        if enough_space(page, size) {
            return page;
        }
        allocator.cur_page += 1;
    }
    page := array_add(*allocator.pages);
    push_allocator(allocator.data_allocator.proc, allocator.data_allocator.data, allocator.data_allocator_align);
    page.bytes = make_static_array(u8, size, false);
    return page;
}

get_begin_address_and_aligned_size :: (page: *Linear_Allocator_Page, size: int, align: u32) -> address: *void, size: int {
    begin_address         := (cast(u64) page.bytes.data) + (cast(u64) page.allocated);
    aligned_begin_address : u64 = xx align_forward(xx begin_address, align);
    aligned_size          :int = xx ((aligned_begin_address - begin_address) + xx size);
    return cast(*void) aligned_begin_address, aligned_size;
}

// size already includes worst-case alignment padding
enough_space :: (page: *Linear_Allocator_Page, size: int) -> bool {
    return page.bytes.count - page.allocated >= size;
}

