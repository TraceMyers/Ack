// todo: errors for other systems
// todo: code for other systems
// todo: more system info

System_Information :: struct {
    cpu_frequency_per_second: s64;
}

// system_information: System_Information;

recommended_system_init :: () -> bool {
    #if OS == .WINDOWS {
        Win32.SetProcessDPIAware();

        sample_rdtscp_cycle_count();
        sample_cycle_count("seconds_since_init();", *seconds_since_init_cycle_count, SECONDS_SINCE_INIT_CYCLE_COUNT_DEFAULT);

        // query_system_information(*system_information);

        return true;
    } else {
        return false;
    }
}


query_system_information :: (info: *System_Information) {
//     if OS == .WINDOWS {
//         Win32.QueryPerformanceFrequency(*info.cpu_frequency_per_second);
//     }
}

is_window_open :: (window: Window_Type) -> bool {
    #if OS == .WINDOWS {
        return xx IsWindow(window);
    }
    return false;
}

is_window_minimized :: (window: Window_Type) -> bool {
    #if OS == .WINDOWS {
        return xx IsIconic(window);
    }
    return false;
}

make_window_take_focus :: (window: Window_Type) {
    if OS == .WINDOWS {
        SetForegroundWindow(window);
        Win32.SetCapture(window);
    }
}

get_mouse_cursor_position :: () -> x: s32, y: s32 {
    #if OS == .WINDOWS {
        pos: Win32.POINT;
        Win32.GetCursorPos(*pos);
        return pos.x, pos.y;
    }
    return 0,0;
}

set_mouse_cursor_position :: (x: s32, y: s32) {
    #if OS == .WINDOWS {
        SetCursorPos(x, y);
    }
}

set_mouse_cursor_visibility :: (window: Window_Type, visible: bool) {
    #if OS == .WINDOWS {
        if visible {
            ShowCursor(true);
        } else {
            // windows uses a voting system for ShowCursor that expects all applications to agree that the cursor
            // should be hidden or shown, which... I don't know maybe there's a way to make it work.
            // this stuffs the ballot box.
            safety_counter := 100;
            while ShowCursor(false) >= 0 && safety_counter > 0 { 
                safety_counter -= 1; 
            }
        }
    }
}

get_console_window :: () -> Window_Type {
    #if OS == .WINDOWS {
        return GetConsoleWindow();
    } else return null;
}

set_console_cursor_position :: (window: Window_Type, x: s16, y: s16) {
    if OS == .WINDOWS {
        SetConsoleCursorPosition(window, {x, y});
    }
}

clear_console :: () {
    if OS == .WINDOWS {
        print("\e[1;1H\e[2J");
    }
}

MIN_CPU_PAUSE_CYCLES : u64 : 320;

// try to pause the cpu at least some number of tsc cycles while minimizing overshoot. if wait_cycles < min value, 
// just calls pause() once, because that resolution is too small for the procedure to handle. this was tuned for 
// an optimized build, so it may be less accurate in a debug build.
cpu_pause :: inline (wait_cycles: u64 = MIN_CPU_PAUSE_CYCLES-1) {
    if wait_cycles <= MIN_CPU_PAUSE_CYCLES-1 {
        pause();
        return;
    }

    core_ids:   [2]u32 = ---;
    timestamps: [2]u64 = ---;

    timestamps[0], core_ids[0] = rdtscp();
    
    // this was fun! (https://www.agner.org/optimize/instruction_tables.pdf)
    // ------------------------------------------------------------------------------------------
    // optimized disassembly of this procedure up to and including rdtscp()  |  intel coffee lake 
    // ------------------------------------------------------------------------------------------
    // > if wait_cycles <= MIN_CPU_PAUSE_CYCLES-1                            |                    | 
    // 1. cmp rdx, 0x18F                                                     | CMP   r,i  (1, 1/4)|
    // 2. jbe                                                                | JBE   m    (0,   2)|
    // > rdtscp high:, result, msr;                                          |                    |
    // 3. mov r9, rdx                                                        | MOV   r,r  (1, 1/4)|
    // 4. rdtscp                                                             | rest is sampled    |
    // 5. mov r10d, ecx       (<< store core_ids[0])      
    // > shl.q  high, 32;                                                     
    // 6. shl rdx, 0x20       (<< shift hi bits up)       
    // > or.q   result, high;                                                 
    // 7. or rax, rdx         (<< combine hi and lo)      
    // 8. mov r11, rax        (<< store cycles[0])        
    LEADING_INSTRUCTION_CYCLES : u64 : 2;

    // + 8 cycle penalty for a jbe branch miss. high end penalty = 16, halved to 8 for 50/50.
    // (https://www.agner.org/optimize/microarchitecture.pdf)
    AVERAGE_BRANCH_MISS_PENALTY : u64 : 8;
    LEADING_COST :: LEADING_INSTRUCTION_CYCLES + AVERAGE_BRANCH_MISS_PENALTY;

    // this proc, simplified:
    //      leading costs
    //      first rdtscp time point   <-- time point 0
    //      first rdtscp cost
    //      |
    //      0 or more iterations in-between
    //      |
    //      newest rdtscp time point   <-- time point 1
    //      newest rdtscp cost
    // if you subtract time point 0 from time point 1, the difference leaves out the leading costs and the 
    // latest rdtscp call cost, so those need to be added back transiently every iteration OR just subtracted 
    // once at the beginning. the cost of this line is not expliclity accounted for because it's in-between 
    // the oldest and newest timestamps, so that would be double-dipping.
    wait_cycles -= LEADING_COST + rdtscp_cycle_count;
    cycle_sum: u64;

    while cycle_sum < wait_cycles {
        remain          := max(wait_cycles - cycle_sum, 0);
        // >> 8 is divide by 256. 256 is a conservative upper bound for pause() cycle cost.
        pauses_per_loop := remain >> 8;

        if pauses_per_loop >= 4 {
            pause();
            pause();
            pause();
            pause();
        } else if pauses_per_loop >= 2 {
            pause();
            pause();
        } else {
            pause();
        }
        
        timestamps[1], core_ids[1] = rdtscp();

        // were the two time stamps recorded from the same core?
        if core_ids[0] == core_ids[1] {
            cycle_sum = timestamps[1] - timestamps[0];
        } else {
            // if the core running the procedure changes between timestamps, 
            // assume 160 * ppl cycles were consumed to avoid overshooting the target.
            // not adding rdtscp_cycle_count because it is added transiently per iteration,
            // so it already exists in the sum.
            cycle_sum    += 160 * pauses_per_loop;
            // reset the base so we can keep measuring.
            timestamps[0] = timestamps[1] - cycle_sum;
            core_ids[0]   = core_ids[1];
        }
    }
}

wait_until :: (time: float64) -> time_spent_ms: float64, end_time: float64 {
    start_time := seconds_since_init();
    time_spent_ms, end_time := wait(start_time, time - start_time);
    return time_spent_ms, end_time;
}

// progressive backoff starting with OS-level timer then cpu pauses. waits until at least 
// wait_ms time has passed, and tries to wait no longer.
// it's slightly awkward to pass in start_time, but it's the most reasonable way to
// use this for a frame sync (start_time = beginning of this frame). maybe I should 
// make an explicit frame_sync proc instead?
wait :: (start_time: float64, wait_ms: float64) -> time_spent_ms: float64, begin_wait_time: float64, end_wait_time: float64 {
    begin_wait_time := seconds_since_init();
    end_time        := begin_wait_time;

    if wait_ms <= 0 {
        return 0, begin_wait_time, end_time;
    }

    spent_ms: float64;

    roomy_wait_time_ms := wait_ms - 1.5;
    while spent_ms < roomy_wait_time_ms {
        _, end_time = wait_inaccurate(0.5);
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

    return spent_ms, begin_wait_time, end_time;
}

// used by wait(), but also good if you want something more accurate than sleep_milliseconds(1)
// and doesn't burn any cycles unnecessarily.
wait_inaccurate :: inline (wait_ms: float64) -> time_spent_ms: float64, end_time: float64 {
    #if OS == .WINDOWS {
        start_time := seconds_since_init();
        end_time   := start_time;

        if context.system_timer == null {
            security_params: SyncObjectSecurityParams = .TIMER_MODIFY_STATE | .SYNCHRONIZE;
            flags : s32 = CREATE_WAITABLE_TIMER_MANUAL_RESET | CREATE_WAITABLE_TIMER_HIGH_RESOLUTION;
            context.system_timer = CreateWaitableTimerExW(null, null, flags, xx security_params);
            engine_check(.LOW, context.system_timer != null);
        }

        spent_ms: float64;

        while spent_ms < wait_ms {
            MILLI_TO_100_NANO : s64 : 10_000;

            remaining_time_in_hundreds_of_ns: Win32.LARGE_INTEGER;
            remaining_time_in_hundreds_of_ns.QuadPart = max(cast(s64) (wait_ms - spent_ms) * MILLI_TO_100_NANO, 0);
            // negative time value indicates it's a duration, rather than a time point.
            remaining_time_in_hundreds_of_ns.QuadPart *= -1; 

            set_success := Win32.SetWaitableTimer(context.system_timer, *remaining_time_in_hundreds_of_ns, 0, null, null, Win32.BOOL.FALSE);
            engine_check(.LOW, set_success == .TRUE, "win32 SetWaitableTimer error: %", Win32.GetLastError());

            wait_success := Win32.WaitForSingleObject(context.system_timer, 20);
            engine_check(.LOW, wait_success == Win32.WAIT_OBJECT_0, "win32 WaitForSingleObject error: %", Win32.GetLastError());

            end_time = seconds_since_init();
            spent_ms = (end_time - start_time) * 1000.0;
        }

        return spent_ms, end_time;
    }
    // } else {
    //     sleep_milliseconds(max(cast(s32) wait_ms, 1));
    // }
}

sample_cycle_count :: ($code: string, cycle_count: *u64, default_value_if_failure: u64) -> bool {
    ITER_COUNT :: 60;
    cycles: [ITER_COUNT]u64;
    collected: int;

    for 0..ITER_COUNT-1 {
        cycles_1, core_id_1 := rdtscp();
        #insert code;
        cycles_2, core_id_2 := rdtscp();
        if core_id_1 == core_id_2 {
            cycles[collected] = xx max(cast(s64) cycles_2 - cast(s64) cycles_1 - cast(s64) rdtscp_cycle_count, 1);
            collected += 1;
        }
    }

    cycle_count_est, success := estimate_cycle_count(array_view(cycles, 0, collected));
    if success {
        cycle_count.* = round(cycle_count_est, u64);
        return true;
    } else {
        cycle_count.* = default_value_if_failure;
        return false;
    }
}

// call this for a more accurate cpu_pause
sample_rdtscp_cycle_count :: () -> bool {
    ITER_COUNT :: 60;
    cycles: [ITER_COUNT]u64;
    collected: int;

    for 0..ITER_COUNT-1 {
        cycles_1, core_id_1 := rdtscp();
        cycles_2, core_id_2 := rdtscp();
        if core_id_1 == core_id_2 {
            cycles[collected] = xx max(cast(s64) cycles_2 - cast(s64) cycles_1, 1);
            collected += 1;
        }
    }

    cycle_count_est, success := estimate_cycle_count(array_view(cycles, 0, collected));
    if success {
        rdtscp_cycle_count = round(cycle_count_est, u64);
        return true;
    } else {
        log("% failed to collect any rdtscp cycle count samples. setting to default %", #procedure_name(), RDTSCP_CYCLE_COUNT_DEFAULT);
        rdtscp_cycle_count = RDTSCP_CYCLE_COUNT_DEFAULT;
        return false;
    }
}

RDTSCP_CYCLE_COUNT_DEFAULT : u64 : 40;
rdtscp_cycle_count: u64 = RDTSCP_CYCLE_COUNT_DEFAULT;

SECONDS_SINCE_INIT_CYCLE_COUNT_DEFAULT : u64 : 3600;
seconds_since_init_cycle_count: u64 = SECONDS_SINCE_INIT_CYCLE_COUNT_DEFAULT;

#scope_module

estimate_cycle_count :: (samples: []u64) -> float64, bool {
    if samples.count >= 1 {
        // assuming normal distribution
        mean, sd := calculate_mean_and_standard_deviation(samples);
        critical_value_95p := 1.96;
        // max value in 95% confidence interval
        cycle_count_est := mean + critical_value_95p * (sd / sqrt(cast(float) samples.count));
        return cycle_count_est, true;
    } else {
        return 0, false;
    }
}
