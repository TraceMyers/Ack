Ring_Buffer :: struct($T: Type) {
    items: []T;
    front: u32 = EMPTY;
    back:  u32;

    on_erasure: #type (erasing: *T, replacement: *T);

    EMPTY :: U32_MAX;
}

operator *[] :: inline (using buffer: *Ring_Buffer($T), index: int) -> *T {
    return buffer.items[index];
}

operator []= :: inline (using buffer: *Ring_Buffer($T), index: int, value: T) {
    buffer.items[index] = value;
}

make_ring_buffer :: inline ($T: Type, size: int) -> Ring_Buffer(T) {
    engine_check(.LOW, size >= 0);
    return ifx size == 0 then Ring_Buffer(T).{} else Ring_Buffer(T).{items=NewArray(size, T)};
}

push_front :: (using buffer: *Ring_Buffer($T), item: T) {
    engine_check(.MEDIUM, items.count > 0);
    push_impl(buffer, item, *front, *back, decrement_wrap);
}

push_back :: (using buffer: *Ring_Buffer($T), item: T) {
    engine_check(.MEDIUM, items.count > 0);
    push_impl(buffer, item, *back, *front, increment_wrap);
}

pop_front :: (using buffer: *Ring_Buffer($T)) -> T {
    engine_check(.MEDIUM, items.count > 0 && front != EMPTY);
    return pop_impl(buffer, *front, increment_wrap);
}

pop_back :: (using buffer: *Ring_Buffer($T)) -> T {
    engine_check(.MEDIUM, items.count > 0 && front != EMPTY);
    return pop_impl(buffer, *back, decrement_wrap);
}

count :: (using buffer: *Ring_Buffer) -> int {
    if front == EMPTY {
        return 0;
    } else if back >= front {
        return back - front + 1;
    } else {
        return (items.count - front) + (back + 1);
    }
}

make_array :: (using buffer: *Ring_Buffer($T)) -> []T {
    if front == EMPTY {
        return .[];
    }

    buf_i := front;
    out_array := NewArray(count(buffer), T);

    for 0..out_array.count-1 {
        out_array[it] = items[buf_i];
        buf_i = increment_wrap(buf_i, cast(u32) 0, cast(u32) (items.count-1));
    }

    return out_array;
}

#scope_module

// implements both push_front and push_back
push_impl :: (using buffer: *Ring_Buffer($T1), item: T1, pushing: *u32, other: *u32, $move_action: $T2) #expand {
    if front == EMPTY {
        front = 0;
        back  = 0;
    } else {
        if count(buffer) == items.count {
            if on_erasure != null {
                on_erasure(*items[other.*], *item);
            }
            other.* = move_action(other.*,  cast(u32) 0, cast(u32) (items.count-1));
        }
        pushing.* = move_action(pushing.*, cast(u32) 0, cast(u32) (items.count-1));
    }
    items[pushing.*] = item;
}

// implements both pop_front and pop_back
pop_impl :: (using buffer: *Ring_Buffer($T1), pushing: *u32, $move_action: $T2) -> T1 #expand {
    item := items[pushing.*];
    if front == back {
        front = EMPTY;
    } else {
        pushing.* = move_action(pushing.*, cast(u32) 0, cast(u32) (items.count-1));
    }
    return item;
}
