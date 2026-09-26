// -- sections --
// Misc Metaprogramming
// Enumarray

// -----------------------------------------------------------------------------------
// -------------------------------------------------------------- Misc Metaprogramming

code_string :: ($code: Code) -> string #expand {
    builder: String_Builder;
    assert(Program_Print.print_expression(*builder, compiler_get_nodes(code)));
    return builder_to_string(*builder);
}

align_of :: inline ($T: Type) -> int {
    return align_of(T.(*Type_Info));
}

align_of :: (info: *Type_Info, max_depth := 50, max_align := S64_MAX) -> int {
    engine_check(.HIGH, max_depth >= 1);

    if max_align <= 1 {
        return 1;
    }

    align := 1;

    Stack_Item :: struct {
        info: *Type_Info;
        member: s32;
    }

    type_stack: [..]Stack_Item;
    type_stack.allocator = temp;
    array_reserve(*type_stack, max_depth + 1);

    array_add(*type_stack, {info, 0});

    while type_stack.count > 0 {
        top   := *type_stack[type_stack.count-1];
        depth := type_stack.count; 

        if top.info.type == {
        case .INTEGER;      #through;
        case .FLOAT;        #through;
        case .POINTER;      #through;
        case .PROCEDURE;    #through;
        case .ENUM;         #through;
        case .BOOL;
            align = max(align, info.runtime_size);
        case .STRING;
            align = max(align, size_of(*u8));
        case .STRUCT;
            top_info_struct := cast(*Type_Info_Struct) top.info;
            if top.member < top_info_struct.members.count && depth + 1 <= max_depth {
                array_add(*type_stack, {top_info_struct.members[top.member].type, 0});
                top.member += 1;
                continue;
            }
        case .ARRAY;
            top_info_array := cast(*Type_Info_Array) top.info;
            if top_info_array.array_type == .FIXED {
                if top.member == 0 && depth + 1 <= max_depth {
                    array_add(*type_stack, {top_info_array.element_type, 0});
                    top.member += 1;
                    continue;
                }
            } else {
                align = max(align, size_of(*u8));
                align = max(align, size_of(int));
            }
        case;
        }

        // only use case I can think of is early-out at, say, 8 bytes. might be worth it.
        if align >= max_align {
            align = max_align;
            break;
        }

        type_stack.count -= 1;
    }

    return align;
}

get_struct_field :: (s: *$struct_type, $field_type: Type) -> *field_type {
    field_offset : int : #run -> int {
        tinfo := cast(*Type_Info) struct_type;
        engine_check(.HIGH, tinfo.type == .STRUCT);
        tinfo_struct := cast(*Type_Info_Struct) tinfo;

        for member : tinfo_struct.members {
            if ((*member.type).(*Type)).* == field_type {
                return member.offset_in_bytes;
            }
        }
        return -1;
    }

    #if field_offset == -1 {
        return null;
    } else {
        field_ptr := cast(*field_type) ((cast(*u8) s) + field_offset);
        return field_ptr;
    }
}

// because T2 == *T1 is valid syntax in only one situation I've seen.
type_2_is_pointer_to_type_1 :: (T1: Type, T2: Type) -> bool {
    tinfo_ptr := cast(*Type_Info_Pointer) T2;
    if tinfo_ptr.type != .POINTER then return false;
    return tinfo_ptr.pointer_to == cast(*Type_Info) T1;
}

Struct_Visit_Item :: struct {
    data: *u8;
    info: *Type_Info;
    member: *Type_Info_Struct_Member;
    iter_index: int;
    iter_index_matching_options: int;
}

Struct_Visit :: struct {
    using item: Struct_Visit_Item;
    parent_stack: []Struct_Visit_Item;
    path: *String_Stack;
}

Struct_Visitor_Command :: enum {
    CONTINUE;
    PUSH_MEMBER_OR_CONTINUE;
    POP_PARENT;
    EXIT;
}

Struct_Visitor :: #type (visit_data: *Struct_Visit, user_data: *void) -> command: Struct_Visitor_Command;

Struct_Visit_Options :: struct {
    visit_pointers      := true;
    visit_only_non_null_pointers := true;
    visit_procedures    := false;
    visit_constants     := false;
    visit_overlays      := false;
}

struct_visit :: (struct_data: *$T, user_data: *void, visitor: Struct_Visitor, options: Struct_Visit_Options = {}) {
    parent_stack: [..]Struct_Visit_Item;
    parent_stack.allocator = temp;
    array_reserve(*parent_stack, 16);

    cur_parent_tinfo := cast(*Type_Info_Struct) type_info(T);
    engine_check(.MEDIUM, cur_parent_tinfo.type == .STRUCT);
    array_add(*parent_stack, {xx struct_data, cur_parent_tinfo, null, 0, 0});
    
    struct_visit_impl(*parent_stack, user_data, visitor, options);
}

#scope_module

// reducing code bloat by doing this part without generics
struct_visit_impl :: no_inline (parent_stack: *[..]Struct_Visit_Item, user_data: *void, visitor: Struct_Visitor, options: Struct_Visit_Options) {

    path: String_Stack;
    init(*path);
    defer free_stack(*path);

    while parent_stack.count > 0 {

        cur_parent := *parent_stack.*[parent_stack.count-1];
        cur_parent_info := cast(*Type_Info_Struct) cur_parent.info;
        command: Struct_Visitor_Command = .CONTINUE;

        while cur_parent.iter_index < cur_parent_info.members.count {
            defer cur_parent.iter_index += 1;
            member := *cur_parent_info.members[cur_parent.iter_index];

            if !options.visit_constants  && (member.flags & .CONSTANT) != 0 {
                continue;
            }
            if !options.visit_overlays   && (member.flags & .OVERLAY) != 0 {
                continue;
            }
            if !options.visit_procedures && member.type.type == .PROCEDURE {
                continue; 
            }

            use_info := member.type;
            member_data := cur_parent.data + member.offset_in_bytes;

            if use_info.type == .POINTER {
                if !options.visit_pointers {
                    continue;
                }
                use_info    = (cast(*Type_Info_Pointer) use_info).pointer_to;
                member_data = (cast(**u8) member_data).*;

                if options.visit_only_non_null_pointers && member_data == null {
                    continue;
                }
            }

            defer cur_parent.iter_index_matching_options += 1;

            {
                if path.sizes.count == 0 {
                    push(*path, member.name);
                } else {
                    push(*path, ".%", member.name);
                }
                defer pop(*path);

                visit_data := Struct_Visit.{
                    item = {xx member_data, use_info, member, 0, 0},
                    parent_stack = parent_stack.*,
                    path = *path
                };

                command = visitor(*visit_data, user_data);
            }

            if command == {
            case .PUSH_MEMBER_OR_CONTINUE;
                if use_info.type == .STRUCT && member_data != null {
                    array_add(parent_stack, {member_data, use_info, member, 0, 0});
                    push(*path, ".%", member.name);
                    break;
                }
            case .POP_PARENT;
                break;
            case .EXIT;
                return;
            }
        }

        if command == .POP_PARENT || cur_parent.iter_index == cur_parent_info.members.count {
            parent_stack.count -= 1;
            if path.sizes.count > 0 {
                pop(*path);
            } else {
                engine_check(.MEDIUM, parent_stack.count == 0);
            }
        }
    }
}

#scope_export

// -----------------------------------------------------------------------------------
// ------------------------------------------------------------------------- Enumarray

// for generating an enum and array parallel to each other. I really don't like maintaining order between the enum and the array.
//
// usage:
//
// Some_Struct :: struct { a: int; };
//
// EXAMPLE_CREATE_INFOS :: EnumArray_Create_Info.[
//      "ENUM_VALUE_1", .{
//          a=1
//      },
//      "ENUM_VALUE_2", .{
//          a=500
//      }
// ];
// 
// #insert #run generate_parallel_enum_and_array(..EXAMPLE_CREATE_INFOS, "Some_Enum", u8, "Some_Structs", Some_Struct, true);
//
// this will generate...
//
// Some_Enum :: { ENUM_VALUE_1; ENUM_VALUE_2; }  
// Some_Structs :: Some_Struct.[.{a=1}, .{a=500}];
// 

Enumarray_Create_Info :: struct {
    name: string;
    props: Code;
}

generate_parallel_enum_and_array :: ($create_infos: ..Enumarray_Create_Info, enum_name: string, $enum_backing_type: Type, array_name: string, $array_item_type: Type, array_is_constant: bool) -> string {
    return generate_parallel_enum_and_array(..create_infos, enum_name, enum_backing_type, array_name, #run tprint("%", array_item_type), array_is_constant);
}

generate_parallel_enum_and_array :: ($create_infos: ..Enumarray_Create_Info, enum_name: string, $enum_backing_type: Type, array_name: string, $array_item_type_name: string, array_is_constant: bool) -> string {
    builder: String_Builder;
    print_to_builder(*builder, "% :: enum % {\n", enum_name, enum_backing_type);
    for create_infos {
        print_to_builder(*builder, "\t%;\n", it.name);
    }
    print_to_builder(*builder, "}\n\n");

    assignment_operator := ifx array_is_constant then "::" else ":=";
    print_to_builder(*builder, "% % %.[\n", array_name, assignment_operator, array_item_type_name);

    for create_infos {
        code_str := code_string(it.props);
        for *c : code_str {
            if c.* == #char ";" {
                c.* = #char " ";
            }
            if c.* == #char "\n" {
                c.* = #char " ";
            }
        }
        if it_index == create_infos.count - 1 {
            print_to_builder(*builder, "\t%\n", code_str);
        } else {
            print_to_builder(*builder, "\t%,\n", code_str);
        }
    }
    print_to_builder(*builder, "];");
    
    out_str := builder_to_string(*builder);
    return out_str;
}

// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.
