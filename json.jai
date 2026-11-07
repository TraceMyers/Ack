// --- sections --- 
// interface procedures
// interface types
// errors
// parser types
// parse_json
// parse number
// parse string
// parse boolean or null
// parse collection
// on enter and exit
// misc

// if you use json_get to get to the value of a json element without checking the type,
// you may reasonably not want your program to crash if the json is syntactically correct,
// but the element has the wrong type. pointers to these error values are passed back in that case.
// these values are meant to be obviously wrong.
JSON_GET_ERROR_OBJECT : JSON_Object = {.[{JSON_GET_ERROR_STRING_ELEMENT, JSON_GET_ERROR_STRING_ELEMENT}]};
JSON_GET_ERROR_ARRAY  : JSON_Array  = {.[JSON_GET_ERROR_STRING_ELEMENT]};
JSON_GET_ERROR_STRING : string      : "Ack!/JSON ERROR: this string is invalid because you used json_get on an element that was not of the assumed type";
JSON_GET_ERROR_INT    : s64         = S64_MIN + 1;
JSON_GET_ERROR_FLOAT  : float64     = #run (cast(*float64) *NaN_INT).*; // NaN
JSON_GET_ERROR_NBOOL  : NBool       = .JSON_GET_ERROR;

JSON_GET_ERROR_STRING_ELEMENT :: JSON_Element.{type=.STRING, str=JSON_GET_ERROR_STRING};

// -----------------------------------------------------------------------------------
// ------------------------------------------------------------- :interface procedures

// alt name
load_json :: load_json_from_file;

// numbers_always_float : never parse to integer
// shrink_allocations   : if the allocations are taking up too much space, shrink
// json_is_minified     : you expect the json to be minified. allocation reservations are larger per file size if true.
load_json_from_file :: (file_path: string, numbers_always_float := false, shrink_allocations := true, json_is_minified := true, log_errors := false) -> JSON_Load_Result {
    on_enter_any_load_proc();

    file_data, success := read_entire_file(file_path, log_errors=log_errors,,temp);
    if !success then return {};

    load_json_from_string(file_data, numbers_always_float, shrink_allocations, json_is_minified, log_errors);
    return context.json_load_result;
}

// numbers_always_float : never parse to integer
// shrink_allocations   : if the allocations are taking up too much space, shrink
// json_is_minified     : you expect the json to be minified. allocation reservations are larger per file size if true.
load_json_from_string :: (text: string, numbers_always_float := false, shrink_allocations := true, json_is_minified := true, log_errors := false) -> JSON_Load_Result {
    on_enter_any_load_proc();
    on_enter_main_load_proc(log_errors);

    result := *context.json_load_result;
    result.file_size = xx text.count;
    result.allocator = context.allocator;
    parser := JSON_Parser.{text=text, always_float=numbers_always_float, user_expects_minified_json=json_is_minified};

    success := parse_json(*parser);
    on_exit_main_load_proc(*parser, success, shrink_allocations, log_errors);

    return context.json_load_result;
}

// this will return a valid file position until the next load, or until free. if the result
// is temp-stored, the relevant 'free' happens after the storage mark moves to before
// a point before this element's result was allocated, such as when temp storage is reset.
// if the allocation is definitely no longer valid (being able to assess validity isn't guaranteed),
// this procedure returns -1.
get_file_position :: (element: *JSON_Element) -> s32 {
    element_index := element - context.json_load_result.elements.data;
    if element_index >= 0 && element_index < context.json_load_result.elements.count {
        return context.json_load_result.file_positions[element_index];
    } else return -1;
}

// traverse the tree of elements from a loaded file. see for_each_json_element_proc definition for
// how to define your per-element callback. user_data can be anything, gets passed into your callback.
for_each_element :: (result: *JSON_Load_Result, proc: for_each_json_element_proc, user_data: *void = null) {
    // ----------------------------

    _push_collection :: (container: JSON_Element_Container) -> bool #expand {
        push_success := static_array_add(*`collection_stack, container, `collection_buffer.count);
        static_array_add(*`index_stack, 0, `index_buffer.count);
        if !push_success {
            return false;
        }
        return true;
    }

    _pop_collection :: () #expand {
        `collection_stack.count -= 1;
        `index_stack.count -= 1;
    }

    // ----------------------------

    if result.elements.count == 0 {
        engine_log("can't search a json result that doesn't have any elements");
        return;
    }

    if result.elements[0].type != .ARRAY && result.elements[0].type != .OBJECT {
        engine_log("can't search a json result that doesn't have a collection (array, object) at the top level");
        return;
    }

    collection_buffer: [512]JSON_Element_Container;
    collection_stack: []JSON_Element_Container;
    collection_stack.data = collection_buffer.data;

    index_buffer: [collection_buffer.count]int;
    index_stack: []int;
    index_stack.data = index_buffer.data;

    // push the top-level collection element
    static_array_add(*collection_stack, {null, *result.elements[0]}, collection_buffer.count);
    static_array_add(*index_stack, 0, index_buffer.count);

    while collection_stack.count > 0 {
        element_index := *index_stack[index_stack.count-1];
        collection := collection_stack[collection_stack.count-1].value;

        element_container: JSON_Element_Container = ---;
        parent_element_count: int;

        if collection.type == .ARRAY {
            if element_index.* >= collection.array.elements.count {
                _pop_collection();
                continue;
            } else {
                element_container.key = null;
                element_container.value = *collection.array.elements[element_index.*];
                parent_element_count = collection.array.elements.count;
            }
        } else { // OBJECT
            if element_index.* >= collection.object.elements.count {
                _pop_collection();
                continue;
            } else {
                kv_pair := *collection.object.elements[element_index.*];
                element_container.key   = *kv_pair.key;
                element_container.value = *kv_pair.value;
                parent_element_count = collection.object.elements.count;
            }
        }

        continue_searching, push_element_collection := proc(collection_stack, element_container, element_index.*, parent_element_count, user_data);

        if !continue_searching {
            break;
        }

        element_index.* += 1;

        if push_element_collection {
            if element_container.value.type == .ARRAY {
                if !_push_collection(element_container) {
                    // todo: error
                    break;
                }
            } else if element_container.value.type == .OBJECT {
                if !_push_collection(element_container) {
                    // todo: error
                    break;
                }
            }
        }
    }
}

// free the allocations of a result. unnecessary if the result was temp allocated. though,
// if it was temp, you probably want to reset your temp storage mark to before the load call.
free :: (using result: *JSON_Load_Result) {
    free(elements.data,,allocator);
    free(strings.data,,allocator);
    free(file_positions.data,,allocator);
    result.* = {};
}

// getter without no error logs
json_get_nl :: #bake_arguments json_get(log_errors=false);

// convenience getter for dereferencing a json element to its inner value, while validating against the type enum
// e.g. for element : json_get(*element.object).elements { ... }
//                    ^ this makes sure element.type is .OBJECT and returns the pointer that was passed in
// incorrect_type_response is a comptime value
// if it's .RETURN_ERROR_VALUE (default), then you will get an error value back (see top of file)
// if it's .ASSERT, the program will crash if the type is wrong
// this was made this way with the understanding that some programs will be parsing json downloaded at
// runtime (like in web stuff) which shouldn't crash the program if it's not typed correctly, 
// and some programs will be parsing json that come from files that should always be correct, like config
// files or glTF or what have you. In that case, you may want to crash and correct the bad json.
json_get :: (val: $T, $incorrect_type_response := enum {RETURN_ERROR_VALUE; ASSERT;}.RETURN_ERROR_VALUE, log_errors := true) -> T {
    // this *might* be overkill, but it should never be wrong
    OFFSET_TO_FIELD :: #run -> int {
        element_type_info := cast(*Type_Info_Struct) JSON_Element;
        tag: JSON_Element_Type = .INTERNAL_UNINITIALIZED; 

        if T == {
        case *JSON_Object;
            tag = .OBJECT;
        case *JSON_Array;
            tag = .ARRAY;
        case *string;
            tag = .STRING;
        case *s64;
            tag = .INT;
        case *float64;
            tag = .FLOAT;
        case *NBool;
            tag = .NBOOL;
        }

        for element_type_info.tagged_union_bindings {
            if it.constant_value == xx tag {
                member_index  := it.member_index;
                member_info   := *element_type_info.members[member_index];
                return member_info.offset_in_bytes;
            }
        }

        assert(false, "json_get only takes pointers to JSON_Element fields, e.g. *JSON_Object, *string, *s64, ...");
        return 0;
    }

    OFFSET_TO_TYPE :: #run -> int {
        e: *JSON_Element;
        return xx *e.type;
    }

    // I recall reading that the value of a tagged union is not necessarily (or never is?) stored at the top. it's
    // probably a good idea to just do things this way forever, but especially now while the language is in flux.

    // subtract the offset to 'val' from the top of the union, then add back the offset to the type enum
    type_ptr := (cast(*u8) val) - OFFSET_TO_FIELD + OFFSET_TO_TYPE;
    // deref to get the type
    type := (cast(*JSON_Element_Type) type_ptr).*;
    
    return_val: T = val;

    #if T == {
    case *JSON_Object;
        #if incorrect_type_response == .RETURN_ERROR_VALUE {
            if type != .OBJECT {
                return_val = *JSON_GET_ERROR_OBJECT;
                if log_errors{
                    engine_error("json element is an %, but is being used as a %", type, T);
                }
            }
        } else {
            engine_check(type == .OBJECT, "json element is an %, but is being used as a %", type, T);
        }
    case *JSON_Array;
        #if incorrect_type_response == .RETURN_ERROR_VALUE {
            if type != .ARRAY {
                return_val = *JSON_GET_ERROR_ARRAY;
                if log_errors{
                    engine_error("json element is an %, but is being used as a %", type, T);
                }
            }
        } else {
            engine_check(type == .ARRAY, "json element is an %, but is being used as a %", type, T);
        }
    case *string;
        #if incorrect_type_response == .RETURN_ERROR_VALUE {
            if type != .STRING {
                return_val = *JSON_GET_ERROR_STRING;
                if log_errors{
                    engine_error("json element is an %, but is being used as a %", type, T);
                }
            }
        } else {
            engine_check(type == .STRING, "json element is a %, but is being used as a %", type, T);
        }
    case *s64;
        #if incorrect_type_response == .RETURN_ERROR_VALUE {
            if type != .INT {
                return_val = *JSON_GET_ERROR_INT;
                if log_errors{
                    engine_error("json element is an %, but is being used as a %", type, T);
                }
            }
        } else {
            engine_check(type == .INT, "json element is an %, but is being used as a %", type, T);
        }
    case *float64;
        #if incorrect_type_response == .RETURN_ERROR_VALUE {
            if type != .FLOAT {
                return_val = *JSON_GET_ERROR_FLOAT;
                if log_errors{
                    engine_error("json element is an %, but is being used as a %", type, T);
                }
            }
        } else {
            engine_check(type == .FLOAT, "json element is a %, but is being used as a %", type, T);
        }
    case *NBool;
        #if incorrect_type_response == .RETURN_ERROR_VALUE {
            if type != .NBOOL {
                return_val = *JSON_GET_ERROR_NBOOL;
                if log_errors{
                    engine_error("json element is an %, but is being used as a %", type, T);
                }
            }
        } else {
            engine_check(type == .NBOOL, "json element is a %, but is being used as a %", type, T);
        }
    }

    return return_val;
}

// -----------------------------------------------------------------------------------
// ------------------------------------------------------------------ :interface types

JSON_Element_Container :: struct {
    // if the value element is a member of an object, this will be readable
    key   : *JSON_Element; // null if no key
    value : *JSON_Element;
}

// the procedure type for use with for_each_element. you drive the search. 
// return values:
// bool 1 is whether to keep going at all. false = quit search.
// bool 2 is, if the current element is a container (object, array), whether to search into it.
for_each_json_element_proc :: #type (
    // the current stack of collections (arrays, objects) hierarchically containing each other
    // the parent of the current element is the last element in this list.
    parent_stack: []JSON_Element_Container, 
    // current element in the search
    element: JSON_Element_Container,
    // iterating over parent element, what is the index of this element?
    element_index: int,
    // number of elements owned by the parent (shallow ownership)
    parent_element_count: int,
    // data you pass in
    user_data: *void
) -> continue_searching: bool, search_element_if_it_is_a_container: bool;

JSON_Load_Result :: struct {
    // list of all elements in the tree. first element is file root element
    elements: []JSON_Element;
    // all of the strings in one buffer
    strings: []u8;
    // the file position of each element
    file_positions: []s32;
    // the size of the data that was read, whether a file or string was input. 
    file_size: s32;
    // number of strings in the strings array
    string_count: s32;
    // if there are any errors, they will be in this list. errors are not necessarily
    // fatal. if fatal, they will be marked. fatal errors mark an unsucessful load.
    // this array points into a buffer owned by the module, and it's valid until 
    // the next load or save.
    // errors and terminal errors do not mean that the nodes weren't at least partially parsed
    errors: []JSON_Error;
    // carry this around so freeing is easier
    allocator: Allocator;
    // for now, always utf8. may make this a parameter in the future.
    // string_encoding: Text_Encoding = .UTF8;
    // if any errors caused loading to exit early, this will be true. if so,
    // the final error in the list is guaranteed to be a fatal one, but not necessarily the
    // inciting error. if the error list is truncated, the fatal error replaced a non-fatal one. 
    any_fatal_errors: bool;
    // if adding more errors would have overflowed the internal buffer, this is set
    errors_truncated: bool;
}

JSON_Element_Type :: enum u8 {
    // default element type. used for debugging.
    INTERNAL_UNINITIALIZED :: 0;
    // an object or array that is being or has been expored as a parent.
    // post-processed into an object or array.
    INTERNAL_COLLECTION_BUILDER;
    // internals for nbool
    TRUE;
    FALSE;
    NULL;
    // types for you~
    OBJECT;
    ARRAY;
    STRING;
    INT;
    FLOAT;
    NBOOL;
}

// nullable bool
NBool :: enum s8 {
    JSON_GET_ERROR :: -128;
    NULL           :: -1;
    FALSE          ::  0;
    TRUE           ::  1;
}

JSON_Element :: union type: JSON_Element_Type {
    // internal fields. explained in enum.
    .INTERNAL_UNINITIALIZED      ,, _internal_null : void;
    .INTERNAL_COLLECTION_BUILDER ,, _internal_collection_builder : JSON_Collection_Builder;
    // fields for you~
    .OBJECT                   ,, object         : JSON_Object;
    .ARRAY                    ,, array          : JSON_Array;
    .STRING                   ,, str            : string;
    .INT                      ,, i64            : s64;            
    .FLOAT                    ,, f64            : float64;
    .NBOOL                    ,, nbool          : NBool;
}

JSON_Object :: struct {
    // an array the superimposes the KV_Pair type on top of JSON_Element. 
    // when adding elements from an object, into the elements array, 
    // the per-element layout looks like: [(key),(value),(key),(value), ..]
    // this array just puts a different view on it: [(key, value), (key, value), ..]
    elements : []JSON_KV_Pair;
}

JSON_Array :: struct {
    elements : []JSON_Element;
}

JSON_KV_Pair :: struct {
    key   : JSON_Element; // guaranteed to be a string
    value : JSON_Element;
}

JSON_Collection_Parse_State :: enum u8 {
    OBJECT_EXPECT_KEY_OR_END :: 1;
    OBJECT_EXPECT_KEY;
    OBJECT_EXPECT_COLON;
    OBJECT_EXPECT_VALUE;
    OBJECT_EXPECT_COMMA_OR_END;
    ARRAY_EXPECT_VALUE_OR_END;
    ARRAY_EXPECT_VALUE;
    ARRAY_EXPECT_COMMA_OR_END;
}

JSON_Collection_Builder :: struct {
    type: JSON_Element_Type;
    state: JSON_Collection_Parse_State;
    debug_filepos: u16;
    child_elements_offset  : s32;
    child_elements_count   : s32;
    child_elements_counter : s32;
    #overlay(child_elements_offset) string_begin_element: s32;
    #overlay(child_elements_count)  string_length: s32;
}

// -----------------------------------------------------------------------------------
// --------------------------------------------------------------------------- :errors

JSON_Error_Code :: enum u16 {
    FAILED_TO_LOAD_FILE;
    EXTRA_END_CURLY_BRACE;
    EXTRA_END_SQUARE_BRACE;
    COLLECTION_WITHOUT_END_DELIMITER;
    EXTRA_COLLECTION_END_DELIMITER;
    TRAILING_COMMA;
    UNEXPECTED_COLON;
    UNEXPECTED_END_OF_OBJECT;
    UNEXPECTED_END_OF_ARRAY;
    UNEXPECTED_BEGINNING_OF_OBJECT;
    INVALID_BYTE;
    OUT_OF_PLACE_PLUS_WHEN_PARSING_NUMBER;
    OUT_OF_PLACE_MINUS_WHEN_PARSING_NUMBER;
    OUT_OF_PLACE_DOT_WHEN_PARSING_NUMBER;
    OUT_OF_PLACE_E_WHEN_PARSING_NUMBER;
    EXTRA_DIGITS_IN_ZERO_WHEN_PARSING_NUMBER;
    IMPROPERLY_FORMED_NUMBER_VALUE;
    STRING_WITHOUT_END_QUOTE;
    FIRST_WORD_OF_UTF16_CODE_POINT_IS_HIGH_SURROGATE_BUT_FOUND_NO_LOW_SURROGATE;
    EXPECTED_VALUE_TRUE;
    EXPECTED_VALUE_FALSE;
    EXPECTED_VALUE_NULL;
    EXPECTED_COLON;
    EXPECTED_OBJECT_KEY;
    EXPECTED_COMMA_OR_END_OF_COLLECTION;
    UNEXPECTED_END_OF_INPUT;
    IMPROPERLY_FORMED_HEX;
    INVALID_ESCAPE_CODE_IN_STRING;
    DATA_AFTER_ROOT_VALUE;
    UNPAIRED_UTF16_LOW_SURROGATE;
    _INTERNAL_ERROR_MARKER_COUNT_DOES_NOT_MATCH_COLLECTION_COUNT;
    _INTERNAL_ERROR_BUILDER_STACK_DEPLETED;
    _INTERNAL_FAILED_TRANSLATING_UTF16_TO_UTF8;
    _INTERNAL_UNEXPECTED_UTF16_READ_BYTE_COUNT;
    _INTERNAL_ERROR_MARKER_TYPE_DOES_NOT_MATCH_COLLECTION_TYPE;
    _INTERNAL_ERROR_INVALID_COLLECTION_TYPE;
    _INTERNAL_ERROR_COLLECTION_MISSING_ELEMENTS;
    _INTERNAL_ERROR_OBJECT_HAS_ODD_NUMBER_OF_ELEMENTS;
}

JSON_Error_Flags :: enum_flags u16 {
    FATAL;
    INTERNAL_UNPROCESSED;
}

JSON_Error :: struct {
    code: JSON_Error_Code; 
    flags: JSON_Error_Flags;
    line: s32;
    column: s32;
    // converted to line,column on exit
    #overlay(line) _internal_file_position: s32 = ---;
}

#scope_module // -----------------------------------------------------------------------

add_load_error :: (code: JSON_Error_Code, file_position: s64, flags: JSON_Error_Flags = 0) {
    if flags & .FATAL {
        context.json_load_result.any_fatal_errors = true;
    }

    error := JSON_Error.{
        code=code, flags=flags|.INTERNAL_UNPROCESSED, _internal_file_position=xx file_position
    };

    if context.json_errors.count == context.json_error_buffer.count {
        if context.json_load_result.any_fatal_errors {
            // make sure at least the final fatal error is recorded, even if the errors are truncated.
            context.json_error_buffer[context.json_error_buffer.count-1] = error;
        }
        context.json_load_result.errors_truncated = true;
        return;
    }

    context.json_errors.count += 1;
    context.json_errors[context.json_errors.count-1] = error;
}

// -----------------------------------------------------------------------------------
// --------------------------------------------------------------------- :parser types

JSON_Parser :: struct {
    text: string;
    pos: s64;
    elements: [..]JSON_Element;
    strings: [..]u8;
    file_positions: [..]s32;
    builder_stack: [..]s32;
    building_collection: *JSON_Collection_Builder;

    user_expects_minified_json: bool;

    number_parser: JSON_Number_Parser;
    always_float: bool;

    string_parser: JSON_String_Parser;
    string_lookup_table: Table(string, s32);
}

Parse_Number_Stage :: enum {
    SIGN; 
    BASE_BEGIN;
    BASE_ZERO;
    BASE_NONZERO;
    FRACTION_DIGITS_BEGIN;
    FRACTION_DIGITS;
    EXPONENT_DIGITS_BEGIN;
    EXPONENT_DIGITS;
}

JSON_Number_Parser :: struct {
    sign           : s64 = 1;
    exponent_sign  : s64 = 1;
    // magnitude of the integer part. digits that would overflow s64 are dropped and counted.
    base           : s64;
    base_dropped_digits : s64;
    exponent       : s64;
    fraction: string;
    stage: Parse_Number_Stage;
}

JSON_String_Parser :: struct {
    // the text between the quotes
    input_string: string;
    // where input_string begins in the json text, for error positions
    text_offset: int;
    output_string_begin: int;
    // read position in input_string
    pos: int;
}

// -----------------------------------------------------------------------------------
// ----------------------------------------------------------------------- :parse_json

parse_json :: (parser: *JSON_Parser) -> bool {
    reserve_allocations(parser);

    while parser.pos < parser.text.count {
        byte := parser.text[parser.pos];
        
        if is_space(byte) {
            parser.pos += 1;
            continue;
        }

        // the root value is complete. only whitespace may follow it.
        if parser.builder_stack.count == 0 && parser.elements.count > 0 {
            code := ifx byte == #char "}" then JSON_Error_Code.EXTRA_END_CURLY_BRACE
                else ifx byte == #char "]" then JSON_Error_Code.EXTRA_END_SQUARE_BRACE
                else JSON_Error_Code.DATA_AFTER_ROOT_VALUE;
            add_load_error(code, parser.pos, .FATAL);
            return false;
        }

        if byte == {
        case #char "{";
            if !begin_parse_collection(parser, .OBJECT) {
                return false;
            }
        case #char "[";
            if !begin_parse_collection(parser, .ARRAY) {
                return false;
            }
        case #char "\"";
            if !parse_string(parser) {
                return false;
            }
        case #char "t";
            if !parse_boolean_or_null(parser, .TRUE) {
                return false;
            }
        case #char "f";
            if !parse_boolean_or_null(parser, .FALSE) {
                return false;
            }
        case #char "n";
            if !parse_boolean_or_null(parser, .NULL) {
                return false;
            }
        case #char ",";
            if parser.builder_stack.count == 0 {
                add_load_error(.TRAILING_COMMA, parser.pos, .FATAL);
                return false;
            } else if parser.building_collection.state == {
            case .OBJECT_EXPECT_COMMA_OR_END;
                parser.building_collection.state = .OBJECT_EXPECT_KEY;
            case .ARRAY_EXPECT_COMMA_OR_END;
                parser.building_collection.state = .ARRAY_EXPECT_VALUE;
            case;
                add_load_error(.TRAILING_COMMA, parser.pos, .FATAL);
                return false;
            }
            parser.pos += 1;
        case #char ":";
            if parser.builder_stack.count == 0 {
                add_load_error(.UNEXPECTED_COLON, parser.pos, .FATAL);
                return false;
            } else if parser.building_collection.state == {
            case .OBJECT_EXPECT_COLON;
                parser.building_collection.state = .OBJECT_EXPECT_VALUE;
            case;
                add_load_error(.UNEXPECTED_COLON, parser.pos, .FATAL);
                return false;
            }
            parser.pos += 1;
        case #char "}";
            if parser.builder_stack.count == 0 {
                add_load_error(.EXTRA_END_CURLY_BRACE, parser.pos, .FATAL);
                return false;
            } else if parser.building_collection.state == {
            case .OBJECT_EXPECT_KEY_OR_END;
                #through;
            case .OBJECT_EXPECT_COMMA_OR_END;
                if parser.building_collection.type != .OBJECT {
                    add_load_error(.UNEXPECTED_END_OF_OBJECT, parser.pos, .FATAL);
                    return false;
                }
                if !pop_collection(parser) {
                    return false;
                }
            case;
                add_load_error(.UNEXPECTED_END_OF_OBJECT, parser.pos, .FATAL);
                return false;
            }
            parser.pos += 1;
        case #char "]";
            if parser.builder_stack.count == 0 {
                add_load_error(.EXTRA_END_SQUARE_BRACE, parser.pos, .FATAL);
                return false;
            } else if parser.building_collection.state == {
            case .ARRAY_EXPECT_VALUE_OR_END;
                #through;
            case .ARRAY_EXPECT_COMMA_OR_END;
                if parser.building_collection.type != .ARRAY {
                    add_load_error(.UNEXPECTED_END_OF_ARRAY, parser.pos, .FATAL);
                    return false;
                }
                if !pop_collection(parser) {
                    return false;
                }
            case;
                add_load_error(.UNEXPECTED_END_OF_ARRAY, parser.pos, .FATAL);
                return false;
            }       
            parser.pos += 1;
        case;
            if is_digit(byte) || byte == "-" {
                if !parse_number(parser) {
                    return false;
                }
            } else {
                add_load_error(.INVALID_BYTE, parser.pos, .FATAL);
                return false;
            }
        }
    }

    return true;
}

reserve_allocations :: (using parser: *JSON_Parser) {
    // these reservation sizes were made from two samples: 
    // - the minified json of a binary gltf file 
    // - the spaced json of an example corporate data file
    elements_per_file_byte, string_bytes_per_file_byte, strings_per_file_byte: float;
    if parser.user_expects_minified_json {
        elements_per_file_byte     = 0.140707;
        string_bytes_per_file_byte = 0.295157;
        strings_per_file_byte      = 0.032068;
    } else {
        elements_per_file_byte     = 0.033319;
        string_bytes_per_file_byte = 0.082472;
        strings_per_file_byte      = 0.005769;
    }

    // overshoot to avoid reallocations
    OVERSHOOT_FACTOR :: 1.5;
    elements_est := parser.text.count * elements_per_file_byte     * OVERSHOOT_FACTOR;
    bytes_est    := parser.text.count * string_bytes_per_file_byte * OVERSHOOT_FACTOR;
    strings_est  := parser.text.count * strings_per_file_byte      * OVERSHOOT_FACTOR;

    elements_reserve_count     := max(32,  round(elements_est));
    string_bytes_reserve_count := max(96,  round(bytes_est));
    strings_reserve_count      := max(16,  round(strings_est));

    array_reserve(*elements,         elements_reserve_count);
    array_reserve(*file_positions,   elements_reserve_count); 
    array_reserve(*strings,          string_bytes_reserve_count);
    init(*string_lookup_table, strings_reserve_count,, temp);
}

// -----------------------------------------------------------------------------------
// --------------------------------------------------------------------- :parse number

parse_number :: (parser: *JSON_Parser) -> bool {
    using parser.number_parser;
    parser.number_parser = {};

    advance_collection_state_for_value_or_return_if_invalid(parser);

    number_begin_pos := parser.pos;

    success := parse_number_components(parser);
    if !success then return false;

    represent_with_integer:, success = should_represent_number_with_integer(parser);
    if !success then return false;

    // overrides decision rather than skipping it, because important valdiation happens in the 
    // decision proc
    if parser.always_float {
        represent_with_integer = false;
    }

    if represent_with_integer {
        element := push_collection_child(parser, number_begin_pos);
        element.type = .INT;
        element.i64 = base * sign;
    } else {
        element := push_collection_child(parser, number_begin_pos);
        element.type = .FLOAT;
        // the sign is applied after, so that it isn't lost when base is 0 (e.g. -0.5)
        if base_dropped_digits > 0 {
            // the integer part overflowed. the fraction is far below float64 precision at this size.
            element.f64 = compose_float(base, "", exponent * exponent_sign + base_dropped_digits);
        } else {
            element.f64 = compose_float(base, fraction, exponent * exponent_sign);
        }
        if sign < 0 then element.f64 = -element.f64;
        // this can be used for a debug comparison
        // for *number_string {
        //     if it.* == #char "E" then it.* = #char "e"; // string_to_float64 doesn't like 'E'
        // }
        // baseline := string_to_float64(number_string);
    }

    return true;
}

parse_number_components :: (parser: *JSON_Parser) -> success: bool {
    using parser.number_parser;

    while parser.pos < parser.text.count {
        byte := parser.text[parser.pos];

        if byte == {
        case #char "+";
            // a sign is only valid right after the 'e'. the stage stays put so at least one digit is required.
            if stage == .EXPONENT_DIGITS_BEGIN && is_exponent_marker(parser.text[parser.pos-1]) {
                // exponent_sign is already 1
            } else {
                add_load_error(.OUT_OF_PLACE_PLUS_WHEN_PARSING_NUMBER, parser.pos, .FATAL);
                return false;
            }
        case #char "-";
            if stage == {
            case .SIGN;
                sign = -1;
                stage = .BASE_BEGIN;
            case .EXPONENT_DIGITS_BEGIN;
                if !is_exponent_marker(parser.text[parser.pos-1]) {
                    add_load_error(.OUT_OF_PLACE_MINUS_WHEN_PARSING_NUMBER, parser.pos, .FATAL);
                    return false;
                }
                exponent_sign = -1;
            case;
                add_load_error(.OUT_OF_PLACE_MINUS_WHEN_PARSING_NUMBER, parser.pos, .FATAL);
                return false;
            }
        case #char ".";
            if stage == .BASE_ZERO || stage == .BASE_NONZERO {
                stage = .FRACTION_DIGITS_BEGIN;
            } else {
                add_load_error(.OUT_OF_PLACE_DOT_WHEN_PARSING_NUMBER, parser.pos, .FATAL);
                return false;
            }
        case #char "E";
            #through;
        case #char "e";
            if stage == .BASE_ZERO || stage == .BASE_NONZERO || stage == .FRACTION_DIGITS {
                stage = .EXPONENT_DIGITS_BEGIN;
            } else {
                add_load_error(.OUT_OF_PLACE_E_WHEN_PARSING_NUMBER, parser.pos, .FATAL);
                return false;
            }
        case;
            digit := to_digit(byte); // returns 0xff if not digit
            if digit <= 9 {
                if stage == {
                case .SIGN;
                    #through;
                case .BASE_BEGIN;
                    if digit == 0 {
                        stage = .BASE_ZERO;
                    } else {
                        stage = .BASE_NONZERO;
                    }
                    base = digit;
                case .BASE_ZERO;
                    add_load_error(.EXTRA_DIGITS_IN_ZERO_WHEN_PARSING_NUMBER, parser.pos, .FATAL);
                    return false;
                case .BASE_NONZERO;
                    // the limits are folded at compile time, so this is one compare per digit
                    MAX_BEFORE_MUL :: S64_MAX / 10;
                    MAX_LAST_DIGIT :: S64_MAX % 10;
                    if base_dropped_digits > 0 || base > MAX_BEFORE_MUL || (base == MAX_BEFORE_MUL && digit > MAX_LAST_DIGIT) {
                        base_dropped_digits += 1;
                    } else {
                        base = base * 10 + digit;
                    }
                case .FRACTION_DIGITS_BEGIN;
                    fraction.data = parser.text.data + parser.pos;
                    fraction.count = 1;
                    stage = .FRACTION_DIGITS;
                case .FRACTION_DIGITS;
                    fraction.count += 1;
                case .EXPONENT_DIGITS_BEGIN;
                    stage = .EXPONENT_DIGITS;
                    #through;
                case .EXPONENT_DIGITS;
                    // anything this large is already infinity or zero. capping keeps compose_float's
                    // per-exponent loop short and the exponent from overflowing.
                    MAX_EXPONENT :: 100_000;
                    exponent = min(exponent * 10 + digit, MAX_EXPONENT);
                }
            } else {
                break;
            }
        }
        
        parser.pos += 1;
    }

    // trim trailing zeroes from the fraction
    while fraction.count > 0 && fraction[fraction.count-1] == "0" {
        fraction.count -= 1;
    }

    return true;
}

should_represent_number_with_integer :: (parser: *JSON_Parser) -> should_use_int: bool, success: bool {
    using parser.number_parser;

    if #complete stage == {
    case .SIGN;                  #through;
    case .BASE_BEGIN;            #through;
    case .FRACTION_DIGITS_BEGIN; #through;
    case .EXPONENT_DIGITS_BEGIN;
        add_load_error(.IMPROPERLY_FORMED_NUMBER_VALUE, parser.pos, .FATAL);
        return false, false;
    case .BASE_ZERO; #through;
    case .BASE_NONZERO;
        // an integer too big for s64 becomes a float instead of wrapping
        return base_dropped_digits == 0, true;
    case .FRACTION_DIGITS; #through;
    case .EXPONENT_DIGITS;
        return false, true;
    }
    return false, false;
}

// -----------------------------------------------------------------------------------
// --------------------------------------------------------------------- :parse string

parse_string :: (parser: *JSON_Parser) -> bool {
    using parser.string_parser;
    parser.string_parser = {};

    advance_collection_state_for_string_or_return_if_invalid(parser);

    // get past opening quote
    string_begin_pos := parser.pos;
    parser.pos += 1;

    remaining_bytes := parser.text.count - parser.pos;
    remaining_text  := string.{remaining_bytes, parser.text.data + parser.pos};
    // collect the text between the quotes
    input_string=, _, found_end_quote := consume_until_non_escaped_quote(remaining_text);
    text_offset = parser.pos;
    parser.pos += input_string.count + 1;

    output_string_begin = parser.strings.count;

    if !found_end_quote {
        parser.pos -= 1;
        add_load_error(.STRING_WITHOUT_END_QUOTE, parser.pos, .FATAL);
        return false;
    }

    // jai compiler doesn't recognize \b and \f
    BACKSPACE : u8 : 0x8;
    FORM_FEED : u8 : 0xc;

    // unescaped bytes are copied over in runs. each escape ends the current run.
    run_begin := 0;
    while pos < input_string.count {
        if input_string[pos] != #char "\\" {
            pos += 1;
            continue;
        }

        if pos > run_begin {
            push_bytes(parser, .{pos - run_begin, input_string.data + run_begin});
        }

        escape_pos := pos;
        pos += 1; // past the backslash
        if pos >= input_string.count {
            // consume_until_non_escaped_quote never ends a string on an unpaired backslash
            add_load_error(.INVALID_ESCAPE_CODE_IN_STRING, text_offset + escape_pos, .FATAL);
            return false;
        }

        escape_code := input_string[pos];
        pos += 1; // past the escape code

        if escape_code == {
        case #char "\"";
            push_byte(parser, #char "\"");
        case #char "\\";
            push_byte(parser, #char "\\");
        case #char "/";
            push_byte(parser, #char "/");
        case #char "b";
            push_byte(parser, BACKSPACE);
        case #char "f";
            push_byte(parser, FORM_FEED);
        case #char "n";
            push_byte(parser, #char "\n");
        case #char "r";
            push_byte(parser, #char "\r");
        case #char "t";
            push_byte(parser, #char "\t");
        case #char "u";
            if !parse_unicode_escape(parser, text_offset + escape_pos) {
                return false;
            }
        case;
            add_load_error(.INVALID_ESCAPE_CODE_IN_STRING, text_offset + escape_pos, .FATAL);
            return false;
        }

        run_begin = pos;
    }

    if pos > run_begin {
        push_bytes(parser, .{pos - run_begin, input_string.data + run_begin});
    }

    new_string_length := parser.strings.count - output_string_begin;
    if new_string_length > 0 {
        // see if the string is cached
        str := string.{new_string_length, parser.strings.data + output_string_begin};
        existing_str_index_ptr := table_find_pointer(*parser.string_lookup_table, str);
        if existing_str_index_ptr != null {
            parser.strings.count = output_string_begin;
            output_string_begin = xx existing_str_index_ptr.*;
        } else {
            // null terminator, so that the strings array can be iterated over, and so the strings
            // can be passed to c libs without reallocation.
            push_byte(parser, 0);
            // cache the string
            table_set(*parser.string_lookup_table, str, xx output_string_begin);
        }
    }

    // a string, for now, uses a collection builder (like an object or array) until post-processing,
    // because the strings array will resize and pointers will become invalid.
    element := push_collection_child(parser, string_begin_pos);
    element.type = .INTERNAL_COLLECTION_BUILDER;
    element._internal_collection_builder = {};

    {
        using element._internal_collection_builder;
        type                    = .STRING;
        debug_filepos           = cast,trunc(u16) parser.pos;
        // informing the post-processing stage where the string begins and ends
        string_begin_element    = xx output_string_begin;
        string_length           = xx new_string_length;
        // for validation during post-processing
        child_elements_counter  = xx new_string_length;
    }

    return true;
}

// splits text at the first quote that isn't escaped. left excludes the quote, right begins after it.
consume_until_non_escaped_quote :: inline (text: string) -> left: string, right: string, found_quote: bool {
    i := 0;
    while i < text.count {
        if text[i] == #char "\\" {
            // skip the escaped byte, so that "\\" followed by a quote ends the string
            i += 2;
        } else if text[i] == #char "\"" {
            return .{i, text.data}, .{text.count - i - 1, text.data + i + 1}, true;
        } else {
            i += 1;
        }
    }
    return text, .{}, false;
}

push_byte :: inline (parser: *JSON_Parser, byte: u8) {
    array_add(*parser.strings, byte);
}

push_bytes :: inline (parser: *JSON_Parser, bytes: string) {
    old_count := parser.strings.count;
    array_resize(*parser.strings, old_count + bytes.count);
    memcpy(parser.strings.data + old_count, bytes.data, bytes.count);
}

// reads the hex digits after a "\u", plus a second "\uXXXX" for a surrogate pair, and pushes the code point as utf8.
// string_parser.pos starts just past the 'u'.
parse_unicode_escape :: (parser: *JSON_Parser, error_pos: int) -> bool {
    using parser.string_parser;

    first, success := parse_utf16_word_from_hex_text(parser);
    if !success {
        return false;
    }

    code_point := cast(u32) first;
    if code_point >= UTF16_HIGH_SURROGATE_MIN && code_point <= UTF16_HIGH_SURROGATE_MAX {
        if pos + 1 >= input_string.count || input_string[pos] != #char "\\" || input_string[pos+1] != #char "u" {
            add_load_error(.FIRST_WORD_OF_UTF16_CODE_POINT_IS_HIGH_SURROGATE_BUT_FOUND_NO_LOW_SURROGATE, error_pos, .FATAL);
            return false;
        }
        pos += 2;

        second:, success = parse_utf16_word_from_hex_text(parser);
        if !success {
            return false;
        }
        low := cast(u32) second;
        if low < UTF16_LOW_SURROGATE_MIN || low > UTF16_LOW_SURROGATE_MAX {
            add_load_error(.FIRST_WORD_OF_UTF16_CODE_POINT_IS_HIGH_SURROGATE_BUT_FOUND_NO_LOW_SURROGATE, error_pos, .FATAL);
            return false;
        }
        code_point = 0x1_0000 + ((code_point - UTF16_HIGH_SURROGATE_MIN) << 10) + (low - UTF16_LOW_SURROGATE_MIN);
    } else if code_point >= UTF16_LOW_SURROGATE_MIN && code_point <= UTF16_LOW_SURROGATE_MAX {
        add_load_error(.UNPAIRED_UTF16_LOW_SURROGATE, error_pos, .FATAL);
        return false;
    }

    utf8: [4]u8;
    result := utf32_to_utf8(xx *code_point, utf8.data, size_of(u32), utf8.count);
    if result.status != .SUCCESS {
        add_load_error(._INTERNAL_FAILED_TRANSLATING_UTF16_TO_UTF8, error_pos, .FATAL);
        return false;
    }

    push_bytes(parser, .{result.write_count, utf8.data});
    return true;
}

// -----------------------------------------------------------------------------------
// ------------------------------------------------------------ :parse boolean or null

parse_boolean_or_null :: (parser: *JSON_Parser, $type: JSON_Element_Type) -> bool {
    advance_collection_state_for_value_or_return_if_invalid(parser);

    // it's a car with a spoiler.
    //               _____________
    type_string ::  //////////////\
             #ifx type == .TRUE  then "true" 
        else #ifx type == .FALSE then "false"
        else                          "null";

    primitive_begin_pos := parser.pos;
    remaining_bytes := parser.text.count - parser.pos;
    str_in_text := string.{min(type_string.count, remaining_bytes), parser.text.data + parser.pos};
    parser.pos += str_in_text.count;

    if str_in_text != type_string {
        error_code : JSON_Error_Code :
            #ifx type == .TRUE  then JSON_Error_Code.EXPECTED_VALUE_TRUE
            else #ifx type == .FALSE then JSON_Error_Code.EXPECTED_VALUE_FALSE
            else JSON_Error_Code.EXPECTED_VALUE_NULL;
        add_load_error(error_code, parser.pos, .FATAL);
        return false;
    }

    element := push_collection_child(parser, primitive_begin_pos);
    element.type = .NBOOL;

    #if type == {
    case .TRUE;
        element.nbool = .TRUE;
    case .FALSE;
        element.nbool = .FALSE;
    case .NULL;
        element.nbool = .NULL;
    }

    return true;
}

// -----------------------------------------------------------------------------------
// ----------------------------------------------------------------- :parse collection

begin_parse_collection :: (parser: *JSON_Parser, $type: JSON_Element_Type) -> bool {
    if parser.builder_stack.count != 0 {
        // advance the state machine determining what symbols are valid to encounter next
        if parser.building_collection.state == {
        case .OBJECT_EXPECT_VALUE;
            parser.building_collection.state = .OBJECT_EXPECT_COMMA_OR_END;
        case .ARRAY_EXPECT_VALUE_OR_END; 
            #through;
        case .ARRAY_EXPECT_VALUE;
            parser.building_collection.state = .ARRAY_EXPECT_COMMA_OR_END;
        case;
            add_load_error(.UNEXPECTED_BEGINNING_OF_OBJECT, parser.pos, .FATAL);
            return false;
        }
    }

    parser.pos += 1;

    END_DELIMITER :: #ifx type == .OBJECT then #char "}" else #char "]";
    OTHER_COLLECTION_END_DELIMITER :: #ifx type == .OBJECT then #char "]" else #char "}";
    
    text_remainder := string.{parser.text.count - parser.pos, parser.text.data + parser.pos};
    any_non_space_text_between_delimiters: bool;
    found_end_delimiter: bool;
    collection_size: int;
    delimiter_stack: int = 1;

    while text_remainder.count > 0 {
        byte := text_remainder[0];
        text_remainder.data  += 1;
        text_remainder.count -= 1;

        if is_space(byte) {
            continue;
        }

        // this delimiter stacking isn't keeping track of whether the delimiters are being
        // supplied in the correct order (eg not checking for {[{]}}, 
        // but I'm not trying to perfectly validate here. that happens in the main loop.
        if byte == END_DELIMITER {
            delimiter_stack -= 1;
            if delimiter_stack <= 0 {
                if delimiter_stack < 0 {
                    add_load_error(.EXTRA_COLLECTION_END_DELIMITER, parser.pos, .FATAL);
                    return false;
                }
                found_end_delimiter = true;
                break;
            }
        } else {
            any_non_space_text_between_delimiters = true;
            if byte == OTHER_COLLECTION_END_DELIMITER {
                delimiter_stack -= 1;
            } else if byte == #char "{" || byte == #char "[" {
                delimiter_stack += 1;
            } else {
                if byte == {
                case #char "\"";
                    found_quote: bool = ---;
                    _, text_remainder, found_quote = consume_until_non_escaped_quote(text_remainder);
                    if !found_quote {
                        add_load_error(.STRING_WITHOUT_END_QUOTE, parser.pos, .FATAL);
                        return false;
                    } 
                    continue;
                case #char ",";
                    collection_size += cast(int) (delimiter_stack == 1);
                }
            }
        }
    }

    if !found_end_delimiter {
        add_load_error(.COLLECTION_WITHOUT_END_DELIMITER, parser.pos, .FATAL);
        return false;
    }

    collection_size += cast(int) any_non_space_text_between_delimiters;
    #if type == .OBJECT then collection_size *= 2;
    return push_collection(parser, type, collection_size);
}

// get the in-place location of the new element within the parent collection's list,
// the parent collection's list is allocated when the collection is pushed.
push_collection_child :: inline (parser: *JSON_Parser, file_pos: int) -> *JSON_Element {
    if parser.elements.count == 0 {
        // there is only one top-level element...
        array_add(*parser.file_positions, xx file_pos);
        return array_add(*parser.elements);
    } else {
        // ... the rest of the elements allocate in-place within a collection.
        // only the root is added outside a collection. parse_json rejects anything after the root.
        engine_check(parser.builder_stack.count > 0);
        using parser.building_collection;
        // child_elements_count was pre-counted. if 'counter' goes over 'count', then either the pre-count was wrong,
        // or we're adding more children than exist.
        engine_check(child_elements_counter < child_elements_count);
        element_index := child_elements_offset + child_elements_counter;
        new_element := *parser.elements[element_index];
        parser.file_positions[element_index] = xx file_pos;
        child_elements_counter += 1;
        return new_element;
    }
}

push_collection :: (using parser: *JSON_Parser, collection_type: JSON_Element_Type, collection_count: int) -> success: bool {
    // all elements (except for the root collection) are children of a parent collection. 
    // this new collection is also a child. as it happens below, when a collection is 
    // pushed, that collection's element list is reserved at the end of the elements array 
    //                               -----------------
    //                              |                 |
    //                              |                 v
    // elements array = ... [ parent collection ] ... [ elem 0 ] [ elem 1] ...
    //                                                           ^
    //                                                           |
    // if the parent object's list already has 1 previously instantiated element,
    // we are getting this element back from this proc call. the element itself will 
    // become a parent object with its own list at the end of the array.
    new_collection := push_collection_child(parser, parser.pos-1);
    // fix: doing this before the resize below
    new_collection_index : s32 = xx (new_collection - elements.data);
    new_collection.type = .INTERNAL_COLLECTION_BUILDER;
    new_collection._internal_collection_builder = {};
    {
        using new_collection._internal_collection_builder;
        type = collection_type;

        if type == .OBJECT {
            state = .OBJECT_EXPECT_KEY_OR_END;
        } else {
            state = .ARRAY_EXPECT_VALUE_OR_END;
        }

        child_elements_count = xx collection_count;

        // put this collection at the top of the stack, even if empty
        array_add(*builder_stack, new_collection_index);
        child_elements_counter = 0;

        debug_filepos = cast,trunc(u16) parser.pos;

        if child_elements_count > 0 {
            child_elements_offset = xx elements.count;
            // push all of this collection's elements into the element array right now 
            // so they're contiguously allocated. elements will have type UNINITIALIZED
            // so they can be checked later to make sure they were set correctly after this step
            array_resize(*elements, elements.count + collection_count);
            array_resize(*file_positions, elements.count);
        } else {
            child_elements_offset = -1;
        }
        // NOTE: DON'T DO ANYTHING WITH THE COLLECTION POINTER HERE,
        // IT IS POTENTIALLY INVALID MEMORY DUE TO THE ARRAY RESIZE
    }
    building_collection = *elements[new_collection_index]._internal_collection_builder;

    return true;
}

pop_collection :: (using parser: *JSON_Parser) -> success: bool {
    if builder_stack.count == 0 {
        add_load_error(._INTERNAL_ERROR_BUILDER_STACK_DEPLETED, parser.pos, .FATAL);
        return false;
    }
    if building_collection.child_elements_counter != building_collection.child_elements_count {
        add_load_error(._INTERNAL_ERROR_COLLECTION_MISSING_ELEMENTS, parser.pos, .FATAL);
        return false;
    }
    builder_stack.count -= 1;
    if builder_stack.count == 0 {
        building_collection = null;
    } else {
        building_collection = *elements[builder_stack[builder_stack.count-1]]._internal_collection_builder;
    }
    return true;
}

post_process_collections :: (elements: *[]JSON_Element, strings: []u8) -> bool {
    for *element : elements.* {
        if element.type != .INTERNAL_COLLECTION_BUILDER {
            continue;
        }

        builder := *element._internal_collection_builder;

        if builder.child_elements_counter != builder.child_elements_count {
            add_load_error(._INTERNAL_ERROR_COLLECTION_MISSING_ELEMENTS, builder.debug_filepos, .FATAL);
            return false;
        }
        if builder.type == .OBJECT {
            // must be even number of elements, so they can be key-value pairs
            if (builder.child_elements_count & 0x1) != 0 { 
                add_load_error(._INTERNAL_ERROR_OBJECT_HAS_ODD_NUMBER_OF_ELEMENTS, builder.debug_filepos, .FATAL);
                return false;
            }
            collection_elements: []JSON_KV_Pair;
            if builder.child_elements_count != 0 {
                collection_elements.data = xx *(elements.*)[builder.child_elements_offset];
                collection_elements.count = (builder.child_elements_count / 2);
            }
            element.type = .OBJECT;
            element.object.elements = collection_elements;
        } else if builder.type == .ARRAY {
            collection_elements: []JSON_Element;
            if builder.child_elements_count != 0 {
                collection_elements.data = *(elements.*)[builder.child_elements_offset];
                collection_elements.count = builder.child_elements_count;
            }
            element.type = .ARRAY;
            element.array.elements = collection_elements;
        } else if builder.type == .STRING {
            str: string;
            if builder.string_length != 0 {
                str.data = *strings[builder.string_begin_element];
                str.count = builder.string_length;
            }
            element.type = .STRING;
            element.str = str;
        } else {
            add_load_error(._INTERNAL_ERROR_INVALID_COLLECTION_TYPE, builder.debug_filepos, .FATAL);
            return false;
        }
    }
    return true;
}
// -----------------------------------------------------------------------------------
// ---------------------------------------------------------------- :on enter and exit

on_enter_any_load_proc :: () #expand {
    `_mark := get_temporary_storage_mark();
    `defer if context.allocator.proc != temp.proc then set_temporary_storage_mark(`_mark);
}

on_enter_main_load_proc :: (log_errors: bool) { 
    context.json_load_result = {};
    context.json_errors.data = context.json_error_buffer.data;
    context.json_errors.count = 0;
}

on_exit_main_load_proc :: (parser: *JSON_Parser, parse_success: bool, shrink_allocations: bool, log_errors: bool) {
    // -----------------------------------------------------

    _increment_wrap :: inline (x: $T, min: T, max: T) -> T {
        if x >= max {
            return min;
        } else return x + 1;
    }

    // -----------------------------------------------------

    if parse_success && shrink_allocations && context.json_load_result.allocator.proc != temp.proc {
        array_shrink_if_small_enough(*parser.elements, 0.9);
        array_shrink_if_small_enough(*parser.strings, 0.9);
        array_shrink_if_small_enough(*parser.file_positions, 0.9);
    }

    post_process_success := post_process_collections(*parser.elements, parser.strings);

    if parse_success && post_process_success {
        context.json_load_result.elements = parser.elements;
        context.json_load_result.strings = parser.strings;
        context.json_load_result.file_positions = parser.file_positions;
    } else {
        array_reset(*parser.elements);
        array_reset(*parser.strings);
        array_reset(*parser.file_positions);
    }

    context.json_load_result.errors = context.json_errors;

    file_context_lines: [8]string;
    fcl_indices: [file_context_lines.count]int;
    fcl_i := 0;

    if parser.text.count > 0 && context.json_errors.count > 0 {
        next_text_covered_size := 0;

        // each error originally is only recorded at a file position
        // convert that to line, column
        for :per_line line, line_index : parser.text {
            text_covered_size := next_text_covered_size;
            next_text_covered_size += line.count;

            line_file_position_begin := line.data - parser.text.data;
            line_file_position_end   := line_file_position_begin + line.count;

            processed_error_count := 0;

            file_context_lines[fcl_i] = line;
            defer fcl_i = _increment_wrap(fcl_i, 0, file_context_lines.count-1);

            for *err : context.json_errors {
                if (err.flags & .INTERNAL_UNPROCESSED) == 0 {
                    processed_error_count += 1;
                    continue;
                }

                if err._internal_file_position >= line_file_position_begin 
                && err._internal_file_position <= line_file_position_end {
                    err.column = xx (err._internal_file_position - line_file_position_begin);
                    err.line = xx line_index;
                    err.flags &= ~.INTERNAL_UNPROCESSED;

                    space_buffer: [128]u8 = ---;
                    space_count := min(space_buffer.count, err.column);
                    memset(space_buffer.data, " ", space_count);
                    spaces := string.{space_count, space_buffer.data};

                    // getting cached line indices, oldest to newest
                    fcl_indices[0] = _increment_wrap(fcl_i, 0, file_context_lines.count-1);
                    if fcl_indices.count > 1 then for 1..fcl_indices.count-1 {
                        fcl_indices[it] = _increment_wrap(fcl_indices[it-1], 0, file_context_lines.count-1);
                    }

                    if log_errors {
                        error_string_builder: String_Builder;
                        print(*error_string_builder,
#string HERE


    error code : %
    flags      : %
    line #     : %
    column #   : %
HERE,
                            err.code, 
                            err.flags, 
                            err.line, 
                            err.column
                        );

                        // print the file lines so the user can see the error location in the text
                        for fcl_indices {
                            if it_index == 0 {
                                print(*error_string_builder, "    text       : %\n", file_context_lines[it]);
                            } else {
                                print(*error_string_builder, "                 %\n", file_context_lines[it]);
                            }
                        }
                        // caret points at the problem location
                        print(*error_string_builder,         "                 %^\n", spaces);

                        engine_log(builder_to_string(*error_string_builder));
                    }

                    processed_error_count += 1;
                }
            }

            if processed_error_count == context.json_errors.count {
                break;
            }
        }
    }
}

// -----------------------------------------------------------------------------------
// ----------------------------------------------------------------------------- :misc

is_exponent_marker :: inline (byte: u8) -> bool {
    return byte == #char "e" || byte == #char "E";
}

to_digit :: inline (byte: u8) -> u8 {
    if byte >= #char "0" && byte <= #char "9" {
        return byte - #char "0";
    }
    return 0xff;
}

// reads 4 hex digits as a utf16 word. the text is big endian: "00e9" -> 0x00e9.
parse_utf16_word_from_hex_text :: (parser: *JSON_Parser) -> u16, bool {
    using parser.string_parser;
    if input_string.count - pos < 4 {
        add_load_error(.UNEXPECTED_END_OF_INPUT, text_offset + pos, .FATAL);
        return 0, false;
    }
    word: u16;
    for 0..3 {
        c := input_string[pos + it];
        nibble: u16 = ---;
        if c >= #char "0" && c <= #char "9" {
            nibble = c - #char "0";
        } else if c >= #char "a" && c <= #char "f" {
            nibble = c - #char "a" + 10;
        } else if c >= #char "A" && c <= #char "F" {
            nibble = c - #char "A" + 10;
        } else {
            add_load_error(.IMPROPERLY_FORMED_HEX, text_offset + pos + it, .FATAL);
            return 0, false;
        }
        word = (word << 4) | nibble;
    }
    pos += 4;
    return word, true;
}

advance_collection_state_for_string_or_return_if_invalid :: (using parser: *JSON_Parser) #expand {
    if builder_stack.count != 0 {
        if building_collection.state == {
        case .OBJECT_EXPECT_KEY_OR_END;
            #through;
        case .OBJECT_EXPECT_KEY;
            building_collection.state = .OBJECT_EXPECT_COLON;
        case .OBJECT_EXPECT_COLON;
            add_load_error(.EXPECTED_COLON, pos, .FATAL);
            `return false;
        case .OBJECT_EXPECT_VALUE;
            building_collection.state = .OBJECT_EXPECT_COMMA_OR_END;
        case .OBJECT_EXPECT_COMMA_OR_END;
            add_load_error(.EXPECTED_COMMA_OR_END_OF_COLLECTION, pos, .FATAL);
            `return false;
        case .ARRAY_EXPECT_VALUE_OR_END;
            #through;
        case .ARRAY_EXPECT_VALUE;
            building_collection.state = .ARRAY_EXPECT_COMMA_OR_END;
        case .ARRAY_EXPECT_COMMA_OR_END;
            add_load_error(.EXPECTED_COMMA_OR_END_OF_COLLECTION, pos, .FATAL);
            `return false;
        }
    }
}

advance_collection_state_for_value_or_return_if_invalid :: (using parser: *JSON_Parser) #expand {
    if builder_stack.count != 0 {
        if building_collection.state == {
        case .OBJECT_EXPECT_KEY_OR_END;
            #through;
        case .OBJECT_EXPECT_KEY;
            add_load_error(.EXPECTED_OBJECT_KEY, pos, .FATAL);
            `return false;
        case .OBJECT_EXPECT_COLON;
            add_load_error(.EXPECTED_COLON, pos, .FATAL);
            `return false;
        case .OBJECT_EXPECT_VALUE;
            building_collection.state = .OBJECT_EXPECT_COMMA_OR_END;
        case .OBJECT_EXPECT_COMMA_OR_END;
            add_load_error(.EXPECTED_COMMA_OR_END_OF_COLLECTION, pos, .FATAL);
            `return false;
        case .ARRAY_EXPECT_VALUE_OR_END;
            #through;
        case .ARRAY_EXPECT_VALUE;
            building_collection.state = .ARRAY_EXPECT_COMMA_OR_END;
        case .ARRAY_EXPECT_COMMA_OR_END;
            add_load_error(.EXPECTED_COMMA_OR_END_OF_COLLECTION, pos, .FATAL);
            `return false;
        }
    }
}

// -----------------------------------------------------------------------------------

NaN_INT : s64 = 0x7fff_ffff_ffff_ffff;

#scope_export

json_test :: () -> bool {
    find :: (obj: *JSON_Element, key: string) -> *JSON_Element {
        if obj.type != .OBJECT then return null;
        for *obj.object.elements {
            if it.key.str == key then return *it.value;
        }
        return null;
    }

    Tree_Stats :: struct {
        values: int;
        keys: int;
        max_depth: int;
    }

    gather_stats :: (parent_stack: []JSON_Element_Container, element: JSON_Element_Container, element_index: int, parent_element_count: int, user_data: *void) -> bool, bool {
        stats := cast(*Tree_Stats) user_data;
        stats.values += 1;
        if element.key != null then stats.keys += 1;
        stats.max_depth = max(stats.max_depth, parent_stack.count);
        return true, true;
    }

    // --- a document with every element type
    text := #string END
{
    "name": "ack",
    "count": 3,
    "neg": -12,
    "pi": 3.25,
    "large_int": 9007199254740993,
    "flags": [true, false, null],
    "nested": {"empty_obj": {}, "empty_arr": [], "list": [1, [2, [3]]]},
    "name_again": "ack"
}
END;

    result := load_json_from_string(text);
    defer free(*result);

    if result.errors.count > 0 || result.elements.count == 0 {
        for result.errors log("  json error % at line %, column %", it.code, it.line, it.column);
        return false;
    }
    root := *result.elements[0];
    test_condition(root.type == .OBJECT && root.object.elements.count == 8);

    name := find(root, "name");
    test_condition(name != null && name.type == .STRING && name.str == "ack");
    // strings are null terminated and deduplicated
    test_condition(name.str.data[name.str.count] == 0);
    name_again := find(root, "name_again");
    test_condition(name_again != null && name_again.str.data == name.str.data);

    count := find(root, "count");
    test_condition(count != null && count.type == .INT && count.i64 == 3);
    test_condition(text[get_file_position(count)] == #char "3");
    neg := find(root, "neg");
    test_condition(neg != null && neg.type == .INT && neg.i64 == -12);
    pi := find(root, "pi");
    test_condition(pi != null && pi.type == .FLOAT && pi.f64 == 3.25);
    large_int := find(root, "large_int");
    test_condition(large_int != null && large_int.type == .INT && large_int.i64 == 9007199254740993);

    flags := find(root, "flags");
    test_condition(flags != null && flags.type == .ARRAY && flags.array.elements.count == 3);
    test_condition(flags.array.elements[0].nbool == .TRUE);
    test_condition(flags.array.elements[1].nbool == .FALSE);
    test_condition(flags.array.elements[2].nbool == .NULL);

    nested := find(root, "nested");
    empty_obj := find(nested, "empty_obj");
    test_condition(empty_obj != null && empty_obj.type == .OBJECT && empty_obj.object.elements.count == 0);
    empty_arr := find(nested, "empty_arr");
    test_condition(empty_arr != null && empty_arr.type == .ARRAY && empty_arr.array.elements.count == 0);
    list := find(nested, "list");
    test_condition(list != null && list.type == .ARRAY && list.array.elements.count == 2);
    test_condition(list.array.elements[0].i64 == 1);
    inner := *list.array.elements[1];
    test_condition(inner.type == .ARRAY && inner.array.elements[0].i64 == 2);
    test_condition(inner.array.elements[1].array.elements[0].i64 == 3);

    // json_get hands back the error value instead of reinterpreting the union
    test_condition(json_get_nl(*count.i64).* == 3);
    test_condition(json_get_nl(*count.str).* == JSON_GET_ERROR_STRING);
    test_condition(json_get_nl(*name.object) == *JSON_GET_ERROR_OBJECT);

    // every element but the root is visited once, as a value or a key
    {
        stats: Tree_Stats;
        for_each_element(*result, gather_stats, *stats);
        test_condition(stats.values == 19 && stats.keys == 11);
        test_condition(1 + stats.values + stats.keys == result.elements.count);
        test_condition(stats.max_depth == 5);
    }

    // --- numbers. ones written without a fraction or exponent must come back as ints.
    Number :: struct {
        text: string;
        value: float64;
        must_be_int: bool;
    }
    numbers :: Number.[
        {"0", 0, true},
        {"-12", -12, true},
        {"3.25", 3.25, false},
        {"-0.5", -0.5, false},
        {"2.5e3", 2500, false},
        {"1e2", 100, false},
        {"1E+2", 100, false},
        {"1e-2", 0.01, false},
        {"125e-2", 1.25, false},
        {"6.02214076e23", 6.02214076e23, false},
        {"9223372036854775807", 9223372036854775807.0, true},
        {"-9223372036854775807", -9223372036854775807.0, true},
        // too big for s64: becomes a float instead of wrapping
        {"99999999999999999999", 1.0e20, false},
        {"12345678901234567890123.5", 1.2345678901234567890123e22, false},
        // more fraction digits than a u64 can hold
        {"0.12345678901234567890123", 0.12345678901234567890123, false},
    ];
    all_numbers_ok := true;
    for number : numbers {
        r := load_json_from_string(tprint("[%]", number.text));
        defer free(*r);
        ok := r.errors.count == 0 && r.elements.count == 2;
        value: float64;
        if ok {
            e := r.elements[1];
            if e.type == .INT {
                value = xx e.i64;
            } else if e.type == .FLOAT {
                value = e.f64;
            } else {
                ok = false;
            }
            if number.must_be_int && e.type != .INT then ok = false;
        }
        if !ok || abs(value - number.value) > abs(number.value) * 1.0e-15 {
            log("  json number % parsed as % (errors: %)", number.text, value, r.errors.count);
            all_numbers_ok = false;
        }
    }
    test_condition(all_numbers_ok);

    // --- string escapes, anywhere in the string
    Escaped :: struct {
        json: string;
        expected: string;
    }
    escaped_strings :: Escaped.[
        .{"\"plain\"",                 "plain"},
        .{"\"\\\"at start\"",          "\"at start"},
        .{"\"a\\\"b\"",                "a\"b"},
        .{"\"a\\\\b\\/c\"",            "a\\b/c"},
        .{"\"tab\\there\\nnew\\r\"",   "tab\there\nnew\r"},
        .{"\"\\u00e9\"",               "\xc3\xa9"},
        .{"\"x\\u20ACy\"",             "x\xe2\x82\xacy"},
        .{"\"\\ud83d\\ude00\"",        "\xf0\x9f\x98\x80"},
        .{"\"ends in \\\\\"",          "ends in \\"},
        .{"\"\\\\\\\"\"",              "\\\""},
        .{"\"mixed \\u00E9\\t\\u20ac!\"", "mixed \xc3\xa9\t\xe2\x82\xac!"},
    ];
    all_strings_ok := true;
    for escaped : escaped_strings {
        r := load_json_from_string(tprint("[%]", escaped.json));
        defer free(*r);
        ok := r.errors.count == 0 && r.elements.count == 2 && r.elements[1].type == .STRING;
        if !ok || r.elements[1].str != escaped.expected {
            log("  json string % parsed as '%' (errors: %)", escaped.json, ifx ok then r.elements[1].str else "", r.errors.count);
            all_strings_ok = false;
        }
    }
    test_condition(all_strings_ok);

    // --- options
    {
        floats := load_json_from_string("[1, -2, 3]", numbers_always_float=true);
        defer free(*floats);
        test_condition(floats.errors.count == 0);
        for floats.elements[0].array.elements {
            test_condition(it.type == .FLOAT);
        }
        test_condition(floats.elements[0].array.elements[1].f64 == -2.0);
    }
    {
        temp_result := load_json_from_string("{\"a\": [1, 2, {\"b\": \"c\"}]}",, temp);
        test_condition(temp_result.errors.count == 0 && temp_result.elements.count == 8);
    }

    // --- malformed input fails, the first error is the inciting one, and no elements are handed back
    Bad :: struct {
        text: string;
        code: JSON_Error_Code;
    }
    bad_inputs :: Bad.[
        .{"[1, 2",          .COLLECTION_WITHOUT_END_DELIMITER},
        .{"{\"a\" 1}",      .EXPECTED_COLON},
        .{"[1 2]",          .EXPECTED_COMMA_OR_END_OF_COLLECTION},
        .{"[\"a\" \"b\"]",  .EXPECTED_COMMA_OR_END_OF_COLLECTION},
        .{"{1: 2}",         .EXPECTED_OBJECT_KEY},
        .{"[01]",           .EXTRA_DIGITS_IN_ZERO_WHEN_PARSING_NUMBER},
        .{"[1.]",           .IMPROPERLY_FORMED_NUMBER_VALUE},
        .{"[1e]",           .IMPROPERLY_FORMED_NUMBER_VALUE},
        .{"[--1]",          .OUT_OF_PLACE_MINUS_WHEN_PARSING_NUMBER},
        .{"[tru]",          .EXPECTED_VALUE_TRUE},
        .{"[nul]",          .EXPECTED_VALUE_NULL},
        .{"[\"abc]",        .STRING_WITHOUT_END_QUOTE},
        .{"[\"\\q\"]",      .INVALID_ESCAPE_CODE_IN_STRING},
        .{"[\"\\u12\"]",    .UNEXPECTED_END_OF_INPUT},
        .{"[\"\\u12g4\"]",  .IMPROPERLY_FORMED_HEX},
        .{"[\"\\ud83dx\"]", .FIRST_WORD_OF_UTF16_CODE_POINT_IS_HIGH_SURROGATE_BUT_FOUND_NO_LOW_SURROGATE},
        .{"[\"\\ud83d\\u0041\"]", .FIRST_WORD_OF_UTF16_CODE_POINT_IS_HIGH_SURROGATE_BUT_FOUND_NO_LOW_SURROGATE},
        .{"[\"\\udc00\"]",  .UNPAIRED_UTF16_LOW_SURROGATE},
        .{"[1e+]",          .IMPROPERLY_FORMED_NUMBER_VALUE},
        .{"[1e+-2]",        .OUT_OF_PLACE_MINUS_WHEN_PARSING_NUMBER},
        .{"[1e2+]",         .OUT_OF_PLACE_PLUS_WHEN_PARSING_NUMBER},
        .{"[-]",            .IMPROPERLY_FORMED_NUMBER_VALUE},
        .{"[1, ?]",         .INVALID_BYTE},
        .{"{\"a\": 1]",     .COLLECTION_WITHOUT_END_DELIMITER},
        .{"{\"a\": 1}}",    .EXTRA_END_CURLY_BRACE},
        .{"[1]]",           .EXTRA_END_SQUARE_BRACE},
        .{"}",              .EXTRA_END_CURLY_BRACE},
        .{",",              .TRAILING_COMMA},
        .{"[1] [2]",        .DATA_AFTER_ROOT_VALUE},
        .{"1 2",            .DATA_AFTER_ROOT_VALUE},
        .{"\"a\" \"b\"",    .DATA_AFTER_ROOT_VALUE},
        .{"{} x",           .DATA_AFTER_ROOT_VALUE},
    ];
    all_bad_inputs_rejected := true;
    for bad : bad_inputs {
        r := load_json_from_string(bad.text);
        defer free(*r);
        first_code := ifx r.errors.count > 0 then r.errors[0].code else .FAILED_TO_LOAD_FILE;
        if !r.any_fatal_errors || r.errors.count == 0 || first_code != bad.code || r.elements.count != 0 {
            log("  json '%' gave % errors (first: %), expected %", bad.text, r.errors.count, first_code, bad.code);
            all_bad_inputs_rejected = false;
        }
    }
    test_condition(all_bad_inputs_rejected);

    // whitespace after the root is fine
    {
        r := load_json_from_string("  [1, 2]  \n\t ");
        defer free(*r);
        test_condition(r.errors.count == 0 && r.elements.count == 3);
    }

    // errors report 0-based line and column
    {
        r := load_json_from_string("[\n  1,\n  x\n]");
        defer free(*r);
        test_condition(r.errors.count > 0 && r.errors[0].code == .INVALID_BYTE);
        test_condition(r.errors[0].line == 2 && r.errors[0].column == 2);
        test_condition((r.errors[0].flags & .FATAL) != 0);
    }

    // --- a real file
    {
        path := tprint("%/additional_materials/test_supplemental/100 KB 10 Level Formatted.json", #filepath);
        file_result := load_json_from_file(path, json_is_minified=false, log_errors=true);
        defer free(*file_result);
        test_condition(file_result.errors.count == 0 && file_result.elements.count > 1000);
        stats: Tree_Stats;
        for_each_element(*file_result, gather_stats, *stats);
        test_condition(1 + stats.values + stats.keys == file_result.elements.count);
        test_condition(stats.max_depth >= 10);
    }

    return true;
}

// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.
