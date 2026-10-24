Clock_Sync :: enum {
    NONE;
    AUTO;
    MANUAL;
}

Loop_Clock :: struct {
    frame: int;

    time: float64;
    delta_time: float32;
    unscaled_delta_time: float32;

    // multiplier applied to 'delta_time' every frame. does not effect 'time'.
    delta_time_scale: float64 = 1.0;
    
    sync: Clock_Sync = .AUTO;
    manual_sync_frame_time_ms: float64 = 1.0/60.0;

    auto_sync_data: struct {
        // configure
        // todo: target frame times based on monitor and also manually overridable
        target_frame_times := float.[1.0/30.0, 1.0/60.0, 1.0/120.0, 1.0/240.0];
        require_consecutive_seconds_hitting_frame_time := 5.0;
        spike_time_before_shifting_auto_frame_time_sync := 1.0;

        // internal tracking
        missed_target_frame_timestamps: [4]float64 = .[-100,-100,-100,-100];
        auto_frame_time_spike_timer: [4]float64;
        target_frame_time_index: int = 3;
    };
}

init_clock :: (clock: *Loop_Clock, auto_target_frame_times_override: []float64 =.[]) {
    clock.* = {};
    clock.time = seconds_since_init();
    clock.unscaled_delta_time = 1.0 / 60.0;
    clock.delta_time = xx (clock.unscaled_delta_time * clock.delta_time_scale);
}

update_clock :: (clock: *Loop_Clock) {
    new_time: float64;

    if clock.sync == {
    case .NONE;
        new_time = seconds_since_init();
    case .AUTO;
        new_time = auto_sync(clock);
    case .MANUAL;
        new_time = manual_sync(clock);
    }

    frame_time := new_time - clock.time;
    clock.unscaled_delta_time = xx clamp(frame_time, 1.0/10_000.0, 0.3);
    clock.delta_time = xx (clock.unscaled_delta_time * clock.delta_time_scale);
    clock.time = new_time;
    clock.frame += 1;
}

auto_sync :: (clock: *Loop_Clock) -> float64 {
    using clock.auto_sync_data;

    target_frame_time_ms := target_frame_times[target_frame_time_index] * 1000.0;
    new_time, wait_time_ms := wait(clock.time, target_frame_time_ms);
    begin_wait_time := new_time - wait_time_ms * (1.0 / 1000.0);

    // todo: this currently requires that the spike last > 1sec to shift down a gear. however, it should probably
    // do a simple analysis of the frequency and length of spikes and determine the sync frame time from that. 
    delta_time_before_wait := max(target_frame_time_ms - wait_time_ms, 0.0);
    for target_frame_times {
        if delta_time_before_wait + 0.00005 > target_frame_times[it_index] {
            auto_frame_time_spike_timer[it_index] += delta_time_before_wait;
            if auto_frame_time_spike_timer[it_index] > spike_time_before_shifting_auto_frame_time_sync {
                missed_target_frame_timestamps[it_index] = new_time;
            }
        } else {
            auto_frame_time_spike_timer[it_index] = 0;
        }
    }

    target_frame_time_index = 0;
    for < timestamp : missed_target_frame_timestamps {
        if new_time - timestamp > require_consecutive_seconds_hitting_frame_time {
            target_frame_time_index = it_index;
            break;
        }
    }

    return new_time;
}

manual_sync :: (clock: *Loop_Clock) -> new_time: float64 {
    new_time := wait(clock.time, clock.manual_sync_frame_time_ms * 1000.0);
    return new_time;
}

// highly accurate wait.
wait_until :: (time_seconds: float64) -> current_time_seconds: float64, wait_time_ms: float64 {
    current_time_seconds := seconds_since_init();
    current_time, wait_time_ms := wait((time_seconds - current_time_seconds) * 1000.0);
    return current_time, wait_time_ms;
}

// highly accurate wait.
wait :: (wait_ms: float64) -> current_time_seconds: float64, wait_time_ms: float64 {
    start_time := seconds_since_init();
    current_time, wait_time_ms := wait(start_time, wait_ms);
    return current_time, wait_time_ms;
}

// highly accurate wait.
// best choice for frame sync, because it doesn't call seconds_since_init an extra time
// like the wrapper implementations do. (the extra call bakes in a frame rate dependent
// overhead that decreases accuracy.)
// progressive backoff starting with OS-level timer then cpu pauses. waits until at least 
// wait_ms time has passed since start_time_seconds.
wait :: (start_time_seconds: float64, wait_ms: float64) -> current_time_seconds: float64, wait_time_ms: float64 {
    if wait_ms <= 0 {
        return start_time_seconds, 0;
    }

    start_time := start_time_seconds;
    end_time := start_time;
    spent_ms: float64;

    MEASURED_MINIMUM_INACCURATE_WAIT_TIME_MS :: 0.5;

    INACCURATE_WAIT_BUFFER_TIME :: MEASURED_MINIMUM_INACCURATE_WAIT_TIME_MS * 2.5;
    roomy_wait_time_ms := wait_ms - INACCURATE_WAIT_BUFFER_TIME;

    while spent_ms < roomy_wait_time_ms {
        _, end_time = wait_inaccurate(MEASURED_MINIMUM_INACCURATE_WAIT_TIME_MS);
        spent_ms = (end_time - start_time) * 1000.0;
    }

    time_remain_ms := wait_ms - spent_ms;
    while time_remain_ms > 0.005 {
        cpu_pause(2048);
        end_time = seconds_since_init();
        spent_ms = (end_time - start_time) * 1000.0;
        time_remain_ms = wait_ms - spent_ms;
    }

    while spent_ms < wait_ms {
        pause();
        end_time = seconds_since_init();
        spent_ms = (end_time - start_time) * 1000.0;
    }

    return end_time, spent_ms;
}

// used by wait(). also good if you want something more accurate than sleep_milliseconds(1)
// and doesn't burn any cycles unnecessarily. on a few systems I've owned (on windows), minimum
// wait time is ~0.5 ms, and it always oversleeps a little.
wait_inaccurate :: inline (wait_ms: float64) -> time_spent_ms: float64, end_time: float64 {
    #if OS == .WINDOWS {
        start_time := seconds_since_init();
        end_time   := start_time;

        if context.system_timer == null {
            security_params: SyncObjectSecurityParams = .TIMER_MODIFY_STATE | .SYNCHRONIZE;
            flags : s32 = CREATE_WAITABLE_TIMER_MANUAL_RESET | CREATE_WAITABLE_TIMER_HIGH_RESOLUTION;
            context.system_timer = CreateWaitableTimerExW(null, null, flags, xx security_params);
            engine_check(context.system_timer != null);
        }

        spent_ms: float64;

        while spent_ms < wait_ms {
            MILLI_TO_100_NANO : s64 : 10_000;

            remaining_time_in_hundreds_of_ns: Win32.LARGE_INTEGER;
            remaining_time_in_hundreds_of_ns.QuadPart = max(cast(s64) (wait_ms - spent_ms) * MILLI_TO_100_NANO, 0);
            // negative time value indicates it's a duration, rather than a time point.
            remaining_time_in_hundreds_of_ns.QuadPart *= -1; 

            set_success := Win32.SetWaitableTimer(context.system_timer, *remaining_time_in_hundreds_of_ns, 0, null, null, Win32.BOOL.FALSE);
            engine_check(set_success == .TRUE, "win32 SetWaitableTimer error: %", Win32.GetLastError());

            wait_success := Win32.WaitForSingleObject(context.system_timer, 20);
            engine_check(wait_success == Win32.WAIT_OBJECT_0, "win32 WaitForSingleObject error: %", Win32.GetLastError());

            end_time = seconds_since_init();
            spent_ms = (end_time - start_time) * 1000.0;
        }

        return spent_ms, end_time;
    }
    // } else {
    //     sleep_milliseconds(max(cast(s32) wait_ms, 1));
    // }
}
