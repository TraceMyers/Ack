#scope_module

end_of_frame_sync :: () -> float64 {

    if !engine.settings.auto_sync_frame_time {
        return seconds_since_init();
    }

    _, begin_wait_time, new_time := wait(engine.clock.time, target_frame_times[target_frame_time_index] * 1000.0);

    // todo: this currently requires that the spike last > 1sec to shift down a gear. however, it should probably
    // do a simple analysis of the frequency and length of spikes and determine the sync frame time from that. 
    delta_time_before_wait := xx (begin_wait_time - engine.clock.time);
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

#scope_file

// todo: hz stepping based on monitor (refreshable)
// todo: make more configurable by user
// todo: manual set option
target_frame_times := float.[1.0/30.0, 1.0/60.0, 1.0/120.0, 1.0/240.0];
missed_target_frame_timestamps: [4]float64 = .[-100,-100,-100,-100];
auto_frame_time_spike_timer: [4]float64;
target_frame_time_index: int = 3;
require_consecutive_seconds_hitting_frame_time := 5.0;
spike_time_before_shifting_auto_frame_time_sync := 1.0;
