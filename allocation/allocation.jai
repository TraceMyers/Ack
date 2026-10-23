#load "allocator_64.jai";
#load "linear_allocator.jai";
#load "general_purpose_allocator.jai";
#load "heap_allocator.jai";
#load "gpu_allocator.jai";
#load "no_allocator.jai";

push_allocator :: (allocator: Allocator, align: int) #expand #no_debug {
    old_allocator     := context.allocator;
    old_align         := context.allocator_align;

    context.allocator       = allocator;
    context.allocator_align = xx align;

    `defer {
        context.allocator       = old_allocator;
        context.allocator_align = old_align;
    }
}

push_allocator :: (proc: Allocator_Proc, data: *void, align: int) #expand #no_debug {
    old_allocator     := context.allocator;
    old_align         := context.allocator_align;

    context.allocator.proc  = proc;
    context.allocator.data  = data;
    context.allocator_align = xx align;

    `defer {
        context.allocator       = old_allocator;
        context.allocator_align = old_align;
    }
}

push_allocator :: (allocator: Allocator, align: int, gpu_alloc_info: GPU_Alloc_Info) #expand #no_debug {
    old_allocator      := context.allocator;
    old_align          := context.allocator_align;
    old_gpu_alloc_info := context.gpu_alloc_info;

    context.allocator       = allocator;
    context.allocator_align = xx align;
    context.gpu_alloc_info  = gpu_alloc_info;

    `defer {
        context.allocator       = old_allocator;
        context.allocator_align = old_align;
        context.gpu_alloc_info  = old_gpu_alloc_info;
    }
}

Allocator_Heap_Snapshot :: struct {
    begin_address: s64;
    end_address:   s64;
    allocated_blocks: [..][2]s32;
}

// -----------------------------------------------------------------------------------
// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.
