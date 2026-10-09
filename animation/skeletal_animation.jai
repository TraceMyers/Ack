// todo: frame rate from file. 
// todo: when/how is interpolate set in the exporter?
// todo: this export method is just flattening it rather than keyframing. super inefficient.
Skeletal_Animation :: struct {
    name:        string;
    timestamps:  []float32;
    // skeleton joint_count * timestamps.count
    transforms:  []Joint_Transform; 
    // if true, translation and scale = lerp, rotation = slerp; otherwise, teleport
    interpolate: bool;  
    speed: float; // todo: delete
}

Skeletal_Animation_Instance :: struct {
    animation: Gen_Ref;
    progress: float;
    speed := 1.0;
    weight := 1.0;
    root_joint: s16;
    prev: s16 = -1;
    next: s16 = -1;
}

Skeletal_Animation_Node :: struct {
    edges:               s16 = -1;
    animation_instances: s16 = -1;
    sync_instances := true;

    handle_blend: ([]*Skeletal_Animation_Instance);
}

Skeletal_Animation_Transition_Stage :: enum u8 {
    JUST_BEGAN;
    RUNNING;
    JUST_ENDED;
}

Skeletal_Animation_Edge_Side :: struct {
    next: s16 = -1;
    prev: s16 = -1;
    sync_nodes := true;
    transition_over_time := true;
    transition_duration := 0.1;

    should_begin_transition: () -> bool;
    handle_transition: (stage: Skeletal_Animation_Transition_Stage);
}

Skeletal_Animation_Edge :: struct {
    nodes: [2]s16 = .[-1, -1];
    sides: [2]Skeletal_Animation_Edge_Side;
}

Skeletal_Animation_Graph :: struct {
    nodes: [..]Skeletal_Animation_Node;
    edges: [..]Skeletal_Animation_Edge;
    animation_instances: [..]Skeletal_Animation_Instance;

    // something like this...
    pick_transition: ([]*Skeletal_Animation_Edge) -> *Skeletal_Animation_Edge;
    
}

Skeletal_Animation_Graph_Player :: struct {
    graph: Gen_Ref;
    entity_id: user_types.entity_id_type;

    cur_node: s16 = -1;
    cur_edge: s16 = -1;
    playing:  bool;

    transition_direction: enum u8 { FORWARD; BACKWARD; };
    transition_progress:  float;
};
