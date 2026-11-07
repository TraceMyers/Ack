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
            bit : u64 = cast,no_check(u64) (1 << limit);
        } else {
            bit : u64 = xx 1;
        }

        for i: 0..limit {
            #if set_or_cleared == .SET {
                found_set_or_cleared_bit := ((cast,no_check(u64) slot) & bit) != 0;
            } else { // CLEARED
                found_set_or_cleared_bit := ((cast,no_check(u64) slot) & bit) == 0;
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

containers_test :: () -> bool {
    // --- bit array iteration, across slot boundaries and in reverse
    {
        bits: Bit_Array;
        init_bit_array(*bits, 130);
        defer deinit(*bits);
        SET :: int.[0, 62, 64, 129];
        for SET set_bit(*bits, it);

        found: [..]int;
        found.allocator = temp;
        for :only_set_bits bits array_add(*found, it_index);
        test_condition(arrays_equal(found, SET));

        found.count = 0;
        for < :only_set_bits bits array_add(*found, it_index);
        test_condition(arrays_equal(found, int.[129, 64, 62, 0]));

        cleared_count := 0;
        first_cleared, last_cleared := -1, -1;
        for :only_cleared_bits bits {
            if first_cleared < 0 then first_cleared = it_index;
            last_cleared = it_index;
            cleared_count += 1;
        }
        test_condition(cleared_count == 130 - SET.count && first_cleared == 1 && last_cleared == 128);

        found.count = 0;
        for < :only_cleared_bits bits array_add(*found, it_index);
        test_condition(found.count == 130 - SET.count && found[0] == 128 && found[found.count-1] == 1);
    }

    // --- pool
    {
        Item :: struct {
            a: s32 = -1;
            b := 1.0;
        }
        init_item   :: (item: *Item) { item.a = 100; }
        deinit_item :: (item: *Item) { item.b = 0; }
        compare     :: (item: *Item, a: s32) -> bool { return item.a == a; }

        p: Pool(Item);
        defer pool_reset(*p);

        i0 := pool_borrow(*p, init_item);
        i1 := pool_borrow(*p, init_item);
        i2 := pool_borrow(*p, init_item);
        test_condition(i0 == 0 && i1 == 1 && i2 == 2 && p.top == 2);
        test_condition(pool_get(*p, i1).a == 100);

        pool_return(*p, i1, deinit_item);
        test_condition(!is_pool_item_in_use(*p, i1) && p.top == 2);
        // returned items are reinitialized
        test_condition(p.items[i1].a == -1 && p.items[i1].b == 1.0);

        // the lowest free slot is reused
        test_condition(pool_borrow(*p, init_item) == i1);
        test_condition(pool_get_index(*p, pool_get(*p, i2)) == i2);

        pool_get(*p, i2).a = 77;
        test_condition(pool_find(*p, cast(s32) 77, compare) == i2);
        test_condition(pool_find(*p, cast(s32) 12345, compare) == -1);

        // iteration only visits items in use
        pool_return(*p, i0);
        visited := 0;
        index_sum := 0;
        for p {
            visited += 1;
            index_sum += it_index;
        }
        test_condition(visited == 2 && index_sum == i1 + i2);

        // returning the top item moves top down to the next item in use
        pool_return(*p, i2);
        test_condition(p.top == i1);
        pool_return(*p, i1);
        test_condition(p.top == -1 && pool_is_empty(*p));

        // stress: borrow a bunch, return them in a scrambled order
        indices: [100]s64;
        for *indices it.* = pool_borrow(*p, init_item);
        for 0..indices.count-1 {
            swap_index := (it * 37 + 11) % indices.count;
            indices[it], indices[swap_index] = indices[swap_index], indices[it];
        }
        for indices pool_return(*p, it, deinit_item);
        test_condition(p.top == -1 && p.items.count == 0);
        found_any := false;
        for :only_set_bits p.in_use found_any = true;
        test_condition(!found_any);

        // shrinking stops at shrink_to_min
        p.shrink_to_min = 12;
        for *indices it.* = pool_borrow(*p);
        for < indices pool_return(*p, it);
        test_condition(p.top == -1 && p.items.count >= 12);
    }
    {
        // a locked pool doesn't grow
        q: Pool(int);
        pool_init(*q, 4, lock_allocation=true, do_track_generation=true);
        for 0..3 test_condition(pool_borrow(*q) == it);
        test_condition(pool_borrow(*q) == -1);

        // generations change when a slot is reused
        generation := pool_get_item_generation(*q, 2);
        pool_return(*q, 2);
        test_condition(pool_borrow(*q) == 2);
        test_condition(pool_get_item_generation(*q, 2) != generation);

        pool_set_allocator(*q, context.allocator);
        pool_reset(*q);
        array_reset(*q.generations);
    }

    // --- ring buffer
    {
        rb := make_ring_buffer(int, 4);
        defer array_free(rb.items);
        test_condition(count(*rb) == 0);
        test_condition(make_array(*rb).count == 0);

        for 1..3 push_back(*rb, it);
        push_front(*rb, 0);
        test_condition(count(*rb) == 4);
        {
            items := make_array(*rb);
            defer array_free(items);
            test_condition(arrays_equal(items, int.[0, 1, 2, 3]));
        }

        // pushing onto a full buffer overwrites the other end
        push_back(*rb, 4);
        test_condition(count(*rb) == 4);
        push_front(*rb, -1);
        {
            items := make_array(*rb);
            defer array_free(items);
            test_condition(arrays_equal(items, int.[-1, 1, 2, 3]));
        }

        test_condition(pop_front(*rb) == -1);
        test_condition(pop_back(*rb) == 3);
        test_condition(count(*rb) == 2);
        test_condition(pop_back(*rb) == 2);
        test_condition(pop_front(*rb) == 1);
        test_condition(count(*rb) == 0);

        // usable again after emptying, and wraps around the end of the storage
        for 10..15 push_back(*rb, it);
        {
            items := make_array(*rb);
            defer array_free(items);
            test_condition(arrays_equal(items, int.[12, 13, 14, 15]));
        }
    }

    return true;
}

// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.
