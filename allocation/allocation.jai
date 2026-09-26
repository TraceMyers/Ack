#load "bump_allocator.jai";
#load "gp_allocator.jai";
#load "no_allocator.jai";
#load "super_allocator.jai";

ALLOCATION_HEADER_SPACE :: #run ceil_to_power_of_two_multiple(size_of(Allocation_Header), 8);

Allocator_Heap_Snapshot :: struct {
    begin_address: s64;
    end_address:   s64;
    allocated_blocks: [..][2]s32;
}

scope_set_allocator :: (allocator: Allocator) #expand {
    original_allocator := context.allocator;
    context.allocator = allocator;
    `defer context.allocator = original_allocator;
}

ALLOCATOR_VALIDATION_PATTERN : u8 : 0x70;

Allocator_Identifier :: enum u8 {
    SUPER_ALLOCATOR :: 1;
    GP_ALLOCATOR_16;
    GP_ALLOCATOR_32;
    GP_ALLOCATOR_64;
    GP_ALLOCATOR_128;
    GP_ALLOCATOR_256;
    GP_ALLOCATOR_512;
    GP_ALLOCATOR_1024;
    GP_ALLOCATOR_2048;
    GP_ALLOCATOR_SUPER_MED;   
    GP_ALLOCATOR_SUPER_LRG;
}

// -----------------------------------------------------------------------------------
// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.
