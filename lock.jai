ENABLE_RW_MUTEX_SPIN_TEST :: true;

// -----------------------------------------------------------------------------------

scope_lock :: (mutex: *$T) #expand #modify { return T != RW_Mutex; } {
    lock(mutex);
    `defer unlock(mutex);
}

// -----------------------------------------------------------------------------------

Spin_Mutex :: struct {
    state: bool;
}

lock :: inline (mutex: *Spin_Mutex) {
    try_count: u64;
    while true {
        // read() == should use fewer cycles on failure.
        if atomic_read(*mutex.state) == false && compare_and_swap(*mutex.state, false, true) {
            return;
        }
        pause_cycles := min(try_count * 32, 4096);
        cpu_pause(pause_cycles);
        try_count += 1;
    }
}

unlock :: inline (mutex: *Spin_Mutex) {
    atomic_write(mutex.state, false);
}


// -----------------------------------------------------------------------------------

Spin_Queue_Mutex :: struct {
    counter: u64;
    serving: u64;
}

lock :: inline (mutex: *Spin_Queue_Mutex) {
    try_count: u64;
    ticket := atomic_add(*mutex.counter, 1);
    while atomic_read(*mutex.serving) != ticket {
        pause_cycles := min(try_count * 32, 4096);
        cpu_pause(pause_cycles);
        try_count += 1;
    }
}

unlock :: inline (mutex: *Spin_Queue_Mutex) {
    atomic_add(*mutex.serving, 1);
}


// -----------------------------------------------------------------------------------

RW_Lock_Type :: enum u8 {
    READ;
    WRITE;
}

RW_Mutex :: struct {
    state: s64;
    wait_events: [..]Event_Handle;
    wait_events_mutex: Spin_Mutex;

    #if ENABLE_RW_MUTEX_SPIN_TEST {
        spin_failure_count: u64;
        contended_spin_acquisition_count: u64;
    }

    READ_KEY  : s64 : 1;
    WRITE_KEY : s64 : -48_000;
}

RW_Mutex_Acquired :: struct {
    unlock_key: s64;
}

init :: (mutex: *RW_Mutex) {
    mutex.wait_events.allocator = context.allocator;
}

lock :: inline (mutex: *RW_Mutex, $type := RW_Lock_Type.WRITE) -> RW_Mutex_Acquired {
    acquired: RW_Mutex_Acquired = ---;

    #if type == .READ {
        try_acquire_loop(mutex, RW_Mutex.READ_KEY,  state => state >= 0);
        acquired.key = -RW_Mutex.READ_KEY;
    } else {
        try_acquire_loop(mutex, RW_Mutex.WRITE_KEY, state => state == 0);
        acquired.key = -RW_Mutex.WRITE_KEY;
    }
    
    return acquired;
}

unlock :: inline (mutex: *RW_Mutex, acquired: RW_Mutex_Acquired) {
    atomic_add(*mutex.state, acquired.unlock_key);
    wake_front(mutex);
}

scope_lock :: (mutex: *RW_Mutex, $type := RW_Lock_Type.WRITE) #expand {
    acquired := lock(mutex, type);
    `defer unlock(mutex, acquired);
}

#scope_module

try_acquire_loop :: (mutex: *RW_Mutex, $key: s64, $lock_acquired: (s64) -> bool) {
    try_count: s64;
    wait_event: Thread_Wait_Event;

    while true {
        if inline lock_acquired(mutex.state) {
            pre_lock_value := atomic_add(*mutex.state, key);           
            if inline lock_acquired(pre_lock_value) {
                #if ENABLE_RW_MUTEX_SPIN_TEST {
                    if try_count > 0 {
                        atomic_add(*mutex.contended_spin_acquistion_count, 1);
                    }
                }
                if wait_event.handle != null {
                    move_front(mutex);
                }
                return;
            }
            atomic_add(*mutex.state, -key);
        }

        #if ENABLE_RW_MUTEX_SPIN_TEST {
            atomic_add(*mutex.spin_failure_count, 1);
        }

        try_count += 1;

        if try_count <= 8 {
            pause();
        } else if try_count <= 16 {
            pause_cycles := try_count * 256;
            cpu_pause(pause_cycles);
        } else if wait_event.handle == null {
            wait_event = add_wait_event(mutex);
        } else {
            // thread sleeps here
            wait_for_event(wait_event.handle);
            // and wakes up here
            // divide try_count by 2 so that it can go back into attempting lock acquisition before returning to waiting
            try_count >>= 1;
        }
    }
}

wake_front :: inline (mutex: *RW_Mutex, do_lock := true) {
    if do_lock then lock(*mutex.wait_events_mutex);
    if mutex.wait_events.count > 0 {
        signal_event(mutex.wait_events[0]);
    }
    if do_lock then unlock(*mutex.wait_events_mutex);
}

move_front :: (mutex: *RW_Mutex) {
    scope_lock(*mutex.wait_events_mutex);
    engine_check(.HIGH, mutex.wait_events.count > 0);
    front_event := mutex.wait_events[0];
    array_ordered_remove_by_index(*mutex.wait_events, 0);
    return_thread_wait_event(front_event);
    wake_front(mutex, false);
}

add_wait_event :: inline (mutex: *RW_Mutex) -> Thread_Wait_Event {
    scope_lock(*mutex.wait_events_mutex);
    event := borrow_thread_wait_event();
    array_add(*mutex.wait_events, event.handle);
    return event;
}

#scope_module

// -----------------------------------------------------------------------------------

init_thread_wait_events :: () {
    context.thread_wait_Events.items.allocator = context.allocator;
    context.thread_wait_Events.queue.allocator = context.allocator;
}

borrow_thread_wait_event :: () -> Thread_Wait_Event {
    using context.thread_wait_events;

    engine_check(.HIGH, items.count < U16_MAX);

    if queue.count == 0 {
        old_count := items.count;
        new_count := max(16, old_count * 2);
        array_resize(*items, new_count);
        array_reserve(*queue, new_count);
        for < old_count..new_count-1 {
            array_add(*queue, it);
        }
    }

    event  := Thread_Wake_Event.{pool_id=queue[queue.count-1]};
    queue.count -= 1;

    handle := *items[event.pool_id];

    if handle.* == null {
        handle.* = CreateEventA(null, Win32.BOOL.TRUE, Win32.BOOL.FALSE, tprint("thread wait event %", event.pool_id));
        engine_check(.HIGH, handle.* != null);
    }
    event.handle = handle.*;

    return event;
}

return_thread_wait_event :: (event: Thread_Wait_Event) {
    handle := context.thread_wait_events.items[event.pool_id];
    reset_event(event.handle);
    array_add(*context.thread_wait_events.queue, event.pool_id);
}

// -----------------------------------------------------------------------------------

#if OS == .WINDOWS {
    Event_Handle :: Win32.HANDLE;

    reset_event :: (handle: Event_Handle) {
        Win32.ResetEvent(handle);
    }

    signal_event :: (handle: Event_Handle) {
        Win32.SetEvent(handle);
    }

    wait_for_event :: (event: Event_Handle) {
        result := Win32.WaitForSingleObject(event, Win32.INFINITE);
        // ideally this would be a continuable break
        engine_check(.LOW, result == Win32.WAIT_OBJECT_0);
    }
}

Thread_Wait_Event :: struct {
    handle: Event_Handle;
    pool_id: s64;
}

Event_Pool :: struct {
    items: [..]Event_Handle;
    queue: [..]u16;
}
