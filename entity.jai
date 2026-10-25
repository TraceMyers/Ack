Ack_Entity :: struct {
    position:    Vector3;
    orientation: Quaternion;
    scale      := Vector3.{1,1,1};
}

is_null_entity_id :: inline (id: user_types.entity_id_type) -> bool {
    return user_types.entity_id_to_u64(id) == user_types.null_entity_id;
}

NULL_ENTITY_ID :: #run user_types.u64_to_entity_id(user_types.null_entity_id);

// the user_types interface doesn't check signatures
#assert type_of(user_types.entity_id_to_u64) == #type (user_types.entity_id_type) -> u64;
#assert type_of(user_types.u64_to_entity_id) == #type (u64) -> user_types.entity_id_type;
