// example SOA declaration
// Physics_Body_SOA :: SOA(struct{
//     flags:              Physics_Body_Flags;
//     collision_channels: Collision_Channel;
//     entity_id:          user_types.entity_id_type;
//     axes:               [3]u64;
//     using body:         Physics_Body_Internal;
// });
// the anonymous struct's type can be accessed via Physics_Body_SOA.item_type

soa_member_type :: ($item_type: Type, member_index: s64) -> Type {
    tinfo := cast(*Type_Info_Struct) type_info(item_type);
    member := tinfo.members[member_index];
    return (cast(*Type) *member.type).*;
}

// wrapping each member type of the SOA so that the types don't need to be known to this file,
// I believe because it keeps the type generic until the SOA specialization is instantiated.
SOA_Member_Type :: struct(item_type: Type, member_index: s64) {
    T :: #run soa_member_type(item_type, member_index);
}

SOA :: struct($item_type: Type) {
    #insert -> string {
        tinfo := cast(*Type_Info_Struct) type_info(item_type);
        assert(tinfo.type == .STRUCT);

        builder: String_Builder;

        INVALID_MEMBER : Type_Info_Struct_Member.Flags = .CONSTANT | .OVERLAY;

        for member, member_index : tinfo.members {
            if member.flags & INVALID_MEMBER {
                continue;
            }
            if member.type.runtime_size == 0 {
                continue;
            }
            print(*builder, "\t%: [..]SOA_Member_Type(item_type, %).T;\n", member.name, member_index);
        }

        return builder_to_string(*builder);
    }
}

soa_for_each_array :: (soa: *SOA, operation: string, $declare_item_field_var := false, only_front_array := false) #expand {
    #insert -> string {
        builder: String_Builder;

        tinfo := type_info(soa.item_type);
        assert(tinfo.type == .STRUCT);
        tinfo_struct := cast(*Type_Info_Struct) tinfo;

        INVALID_MEMBER : Type_Info_Struct_Member.Flags = .CONSTANT | .OVERLAY;

        i := 0;
        for member : tinfo_struct.members {
            if member.flags & INVALID_MEMBER {
                continue;
            }
            if member.type.runtime_size == 0 {
                continue;
            }
            defer i += 1;
            print(*builder, "\t{\n");
            print(*builder, "\t\tarray := *soa.%;\n", member.name);
            #if declare_item_field_var {
                print(*builder, "\t\tfield := *`item.%;\n", member.name);
            }
            print(*builder, "#insert operation;");
            print(*builder, "\t}\n");
            if only_front_array {
                break;
            }
        }

        return builder_to_string(*builder);
    }
}

soa_set_allocator :: (soa: *SOA, allocator: Allocator) {
    soa_for_each_array(soa, "array.allocator = `allocator;");
}

soa_add :: (soa: *SOA) {
    soa_for_each_array(soa, "array_add(array);");
}

soa_add :: (soa: *SOA, item: soa.item_type) {
    soa_for_each_array(soa, "array_add(array, field.*);", true);
}

soa_set :: (soa: *SOA, i: s64, item: soa.item_type) {
    soa_for_each_array(soa, "array.*[`i] = field.*;", true);
}

soa_get :: (soa: *SOA, i: s64) -> soa.item_type {
    item: soa.item_type = ---;
    soa_for_each_array(soa, "field.* = array.*[`i];", true);
    return item;
}

soa_unordered_remove_by_index :: (soa: *SOA, i: s64) {
    soa_for_each_array(soa, "array_unordered_remove_by_index(array, `i);");
}

soa_ordered_remove_by_index :: (soa: *SOA, i: s64) {
    soa_for_each_array(soa, "array_ordered_remove_by_index(array, `i);");
}

soa_resize :: (soa: *SOA, count: s64) {
    soa_for_each_array(soa, "array_resize(array, `count);");
}

soa_reserve :: (soa: *SOA, count: s64) {
    soa_for_each_array(soa, "array_reserve(array, `count);");
}

soa_reset :: (soa: *SOA) {
    soa_for_each_array(soa, "array_reset(array);");
}

soa_reset_keeping_memory :: (soa: *SOA) {
    soa_for_each_array(soa, "array_reset_keeping_memory(array);");
}

soa_count :: (soa: *SOA) -> int {
    count: int = ---;
    soa_for_each_array(soa, "`count = array.count;", false, true);
    return count;
}
