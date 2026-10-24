// json
// errors are cleared and added per-load and per-save, for each thread. 
// if the number of errors maxes out, errors are no longer stored unless a fatal error happens,
// then that ovewrites the last error.
// adding these to the context so they can be thread-local, allowing for multithreaded processing
#add_context json_error_buffer:       [32]JSON_Error;
#add_context json_errors:             []JSON_Error;
#add_context json_load_result:        JSON_Load_Result;

// mesh
#add_context ack_mesh_self_allocation: [..]u8;
#add_context ack_mesh_buffer_table: [..]Buffer_Table_Item;
#add_context ack_mesh_texture_buffer_table: [..]Texture_Buffer_Table_Item;

// lock
#add_context thread_wait_events: Event_Pool;

#if OS == .WINDOWS {
    // system
    #add_context system_timer: Win32.HANDLE;
}

#add_context allocator_align: u32 = 8;
#add_context gpu_alloc_info: GPU_Alloc_Info;
