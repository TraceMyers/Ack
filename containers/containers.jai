// for a given bit collection (u64), send a mask that represents a specific 
// sequence of bits, and search for a sequence where no mask 1's match any of the collection 1's.
// for example, pretending a collection is 8 bits:
// sequence/mask: 111
//              111     < matched below to 000
// collection: 10001001
//  bit index: 76543210
//                ^
// sequence can be found here, at lsb index 4
// index = 0 if the pattern exists when it begins at the least significant bit
find_index_of_missing_bit_sequence_lsb :: inline (bits: $T, sequence: u64, sequence_bit_count: s64) -> s8 {
    TYPE_BIT_COUNT :: (size_of(T) * 8);
    engine_check(.MEDIUM, sequence_bit_count > 0 && sequence_bit_count <= TYPE_BIT_COUNT);
    shift_range := TYPE_BIT_COUNT - sequence_bit_count;
    for 0..shift_range {
        mask := sequence << it;
        if (bits & mask) == 0 {
            return xx it;
        }
    }
    return -1;
}

largest_gap_in_bit_sequence_lsb :: inline (bits: $T) -> size: s8 {
    TYPE_BIT_COUNT :: (size_of(T) * 8);
    gap_size: s8;
    largest_gap_size: s8;
    for 0..TYPE_BIT_COUNT-1 {
        if (bits & xx ((1).(u64) << it)) == 0 {
            gap_size += 1;
            largest_gap_size = max(gap_size, largest_gap_size);
        } else {
            gap_size = 0;
        }
    }
    return largest_gap_size;
}

// -----------------------------------------------------------------------------------
// ---------------------------------------------------------------- :Bit_Array Helpers
// just a couple of for expansions for iterating over only cleared or only set bits. reverse
// iteration was also added, where the base for expansion did not implement that.
//
// this is particularly useful for allocation algorithms that want to find the front or back bit
// that is set or cleared, since they will exit the loop on the front valid slot.
//
// in other words...
//
// for bit arrays that looks something like this (imagining slots are 8 bits instead of 64)
// 
// [ 1 1 1 1 1 1 1 1 ] [ 1 1 1 1 1 1 1 1 ] [ 1 1 0 1 1 0 1 0 ]
//
// and given you want to find the front cleared bit, you clearly don't need to search
// into the front two slots. only when you reach slot 3 should you search the bits to find a 0.
//
// when the bit array becomes hundreds or thousands of slots long, this two stage search
// save a lot of time.

// for expansion for iterating over only '1' bits in a bit array. 
// usage looks like...
// for :only_set_bits your_bit_array { ... }
only_set_bits     :: #bake_arguments only_set_or_only_cleared_bits(set_or_cleared=.SET);
// for expansion for iterating over only '0' bits in a bit array. 
// usage looks like...
// for :only_cleared_bits your_bit_array { ... }
only_cleared_bits :: #bake_arguments only_set_or_only_cleared_bits(set_or_cleared=.CLEARED);

// definition for the above for expansions
only_set_or_only_cleared_bits :: (array: *Bit_Array, body: Code, flags: For_Flags, $set_or_cleared: enum {SET; CLEARED;}) #expand {
    #assert((flags & .POINTER) == 0);

    // you already know whether it's set or cleared, so this is sort of performative,
    // but I figured it makes sense to keep it this way for consistency with
    // the base for expansion def
    `it := #ifx set_or_cleared == .SET then 1 else 0;

    // the other reason this exists is to add reverse iteration, which the pool uses.
    for <=((flags & .REVERSE) != 0) slot, slot_index: array.slots {

        // one reason this expansion exists. skip over slots that have no candidate bits.
        #if set_or_cleared == .SET {
            if slot == 0 then continue;
        } else {
            if slot == BIT_ARRAY_SLOT_MAX_VALUE then continue;
        }
        
        base_index := slot_index * BIT_ARRAY_SLOT_BIT_COUNT;
        limit      := min(array.count - base_index - 1, BIT_ARRAY_SLOT_BIT_COUNT - 1);  // Don't go past the number of bits that are actually stored.

        #if (flags & .REVERSE) != 0 {
            bit := 1 << limit;
        } else {
            bit := 1;
        }

        for i: 0..limit {
            #if set_or_cleared == .SET {
                found_set_or_cleared_bit := (slot & bit) != 0;
            } else { // CLEARED
                found_set_or_cleared_bit := (slot & bit) == 0;
            }

            #if (flags & .REVERSE) != 0 {
                bit >>= 1;
            } else {
                bit <<= 1;
            }

            if found_set_or_cleared_bit {
                #if (flags & .REVERSE) != 0 {
                    `it_index := base_index + (limit - i);
                } else {
                    `it_index := base_index + i;
                }

                #insert (remove=#assert(false), break=break slot) body;
            }
        }            
    }
}

BIT_ARRAY_SLOT_SIZE :: size_of(s64);
BIT_ARRAY_SLOT_MAX_VALUE : s64 : 0xffff_ffff_ffff_ffff;
BIT_ARRAY_SLOT_BIT_COUNT :: BIT_ARRAY_SLOT_SIZE * 8;

#import "Bit_Array";

#load "hybrid_storage_array.jai";
#load "pool.jai";
#load "ring_buffer.jai";
#load "struct_of_arrays.jai";

// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.
