render_check :: inline (result: VkResult, fmt := "", args: ..Any, $level := Ack_Validation_Level.NORMAL, caller_loc := #caller_location) #no_debug #expand {
    render_check(result == .SUCCESS, fmt, ..args, level=level, caller_loc=caller_loc);
}

render_evaluate :: inline (result: VkResult, fmt := "", args: ..Any, level := Ack_Validation_Level.NORMAL, caller_loc := #caller_location) -> bool #expand #no_debug {
    return render_evaluate(result == .SUCCESS, fmt, ..args, level=level, caller_loc=caller_loc);
}

#load "backend/backend.jai";

#import "Ack!/render/vulkan-jai";
