// --- sections ---
// Types and Constants
// Init
// Convenience Procs
// Primitives
// Dynamic Arrays
// Arrays
// Strings
// Bytes
// Helpers
// Byte Reversing for Net Serialization
// Struct Serialization Versioning
// Internal Helpers

// -----------------------------------------------------------------------------------
// -------------------------------------------------------------- :Types and Constants

SERIALIZER_CHECKSUM_SIZE :: 32;
CHECKSUM_UINT32_COUNT :: SERIALIZER_CHECKSUM_SIZE / 4;
Serializer_Checksum_Type :: [CHECKSUM_UINT32_COUNT]u32;

Rw_Mode :: enum u8 {
    WRITE;
    READ;
}

Serializer :: struct($alloc_mode: Serializer_Alloc_Mode = .STATIC, $align_mode: Serializer_Align_Mode = .BYTE) {
    memory: string;
    allocator: Allocator; // only used if dynamic
    // used only when reading out arrays. if not set, will default to using the above allocator.
    read_array_allocator: Allocator; 
    head: s64;
    parameter_align : u8 = 1; // must be power of 2 if used
    rw_mode: Rw_Mode;
    pad_for_checksum := false;
    reverse_byte_order: bool;
}

Serializer_Alloc_Mode :: enum u8 {
    STATIC;
    DYNAMIC;
}

Serializer_Align_Mode :: enum u8 {
    BYTE;
    PRIMITIVE;
    PARAMETER;
}

// -----------------------------------------------------------------------------------
// ----------------------------------------------------------------------------- :Init

initialize :: (using buffer: *Serializer, init_rw_mode: Rw_Mode, static_memory := "", use_checksum := false, reverse_primitive_byte_order := false) {
    rw_mode = init_rw_mode;
    pad_for_checksum = use_checksum;
    reverse_byte_order = reverse_primitive_byte_order;
    if static_memory != "" {
        engine_check(alloc_mode == .STATIC);
        memory = static_memory;
    }
    reset_head_with_mode(buffer, init_rw_mode);
}

// call any time you want to reset the head and/or switch mode
reset_head_with_mode :: (using buffer: *Serializer, m: Rw_Mode) {
    rw_mode = m;
    if pad_for_checksum {
        head = SERIALIZER_CHECKSUM_SIZE;
    } else {
        head = 0;
    }
}

reset :: (using buffer: *Serializer, keep_allocation := true) {
    if !keep_allocation {
        // static memory belongs to the caller. only a dynamic serializer owns its memory.
        #if alloc_mode == .DYNAMIC {
            if memory.data != null then free(memory.data,, allocator);
        }
        memory = "";
    }
    reset_head_with_mode(buffer, rw_mode);
}

// -----------------------------------------------------------------------------------
// ---------------------------------------------------------------- :Convenience Procs

write               :: #bake_arguments serialize_primitive(mode=.WRITE);
read                :: #bake_arguments serialize_primitive(mode=.READ);
write_array         :: #bake_arguments serialize_array(mode=.WRITE);
read_array          :: #bake_arguments serialize_array(mode=.READ);
write_array_data    :: #bake_arguments serialize_array_data(mode=.WRITE);
read_array_data     :: #bake_arguments serialize_array_data(mode=.READ);
write_string        :: #bake_arguments serialize_string(mode=.WRITE);
read_string         :: #bake_arguments serialize_string(mode=.READ);
write_bytes         :: #bake_arguments serialize_bytes(mode=.WRITE);
read_bytes          :: #bake_arguments serialize_bytes(mode=.READ);

read_out :: inline (using buffer: *Serializer, $T: Type) -> T 
#modify {
    return is_serial_primitive(T);
} {
    item: T = ---;
    read(buffer, *item);
    return item;
}

// -----------------------------------------------------------------------------------
// ----------------------------------------------------------------------- :Primitives

serialize :: (using buffer: *Serializer, item: *$T) -> bool
#modify {
    return is_serial_primitive(T);
} {
    if rw_mode == .WRITE {
        return serialize_primitive(buffer, item, .WRITE);
    } else {
        return serialize_primitive(buffer, item, .READ);
    }
}

serialize_primitive :: (using buffer: *Serializer, item: *$T, $mode: Rw_Mode) -> bool
#modify {
    return is_serial_primitive(T);
} {
    validate_read_write();
    if !align_head_up_for_type(buffer, T) {
        return false;
    }
    new_head := head + size_of(T);
    if !check_new_head(buffer, new_head) {
        return false;
    }
    
    #if mode == .WRITE {
        internal_write_primitive(buffer, item);
    } else {
        internal_read_primitive(buffer, item);
    }

    head = new_head;
    return true;
}

// -----------------------------------------------------------------------------------
// ------------------------------------------------------------------- :Dynamic Arrays

serialize :: (using buffer: *Serializer, array: *[..]$T) -> bool
#modify {
    return is_serial_primitive(T);
} {
    if rw_mode == .WRITE {
        return serialize_dynamic_array(buffer, array, .WRITE);
    } else {
        return serialize_dynamic_array(buffer, array, .READ);
    }
}

serialize :: (using buffer: *Serializer, array: *[..]$T, array_count: s64) -> bool
#modify {
    return is_serial_primitive(T);
} {
    if rw_mode == .WRITE {
        return serialize_dynamic_array_data(buffer, array, array_count, .WRITE);
    } else {
        return serialize_dynamic_array_data(buffer, array, array_count, .READ);
    }
}

serialize_dynamic_array :: (using buffer: *Serializer, array: *[..]$T, $mode: Rw_Mode) -> bool
#modify {
    return is_serial_primitive(T);
} {
    array_count: s64 = xx array.count;
    if !serialize_primitive(buffer, *array_count, mode) then return false;
    return serialize_dynamic_array_data(buffer, array, array_count, mode);
}

serialize_dynamic_array_data :: (using buffer: *Serializer, array: *[..]$T, array_count: s64, $mode: Rw_Mode) -> bool
#modify {
    return is_serial_primitive(T);
} {
    validate_read_write();

    if array_count == 0 {
        return true;
    }

    if !align_head_up_for_type(buffer, T) {
        return false;
    }

    array_size := size_of(T) * array_count;
    new_head := head + array_size;

    if !check_new_head(buffer, new_head) {
        return false;
    }

    #if mode == .WRITE {
        memcpy(memory.data + head, array.data, array_size);
    } else {
        if array.data == null {
            array_resize(array, array_count, false);
        } else if array.count < array_count {
            return false;
        }
        memcpy(array.data, memory.data + head, array_size);
    }

    head = new_head;
    return true;
}

// -----------------------------------------------------------------------------------
// --------------------------------------------------------------------------- :Arrays

serialize :: (using buffer: *Serializer, array: *[]$T) -> bool
#modify {
    return is_serial_primitive(T);
} {
    if rw_mode == .WRITE {
        return serialize_array(buffer, array, .WRITE);
    } else {
        return serialize_array(buffer, array, .READ);
    }
}

serialize :: (using buffer: *Serializer, array: *[]$T, array_count: s64) -> bool
#modify {
    return is_serial_primitive(T);
} {
    if rw_mode == .WRITE {
        return serialize_array_data(buffer, array, array_count, .WRITE);
    } else {
        return serialize_array_data(buffer, array, array_count, .READ);
    }
}

serialize_array :: (using buffer: *Serializer, array: *[]$T, $mode: Rw_Mode) -> bool
#modify {
    return is_serial_primitive(T);
} {
    array_count: s64 = xx array.count;
    if !serialize_primitive(buffer, *array_count, mode) then return false;
    return serialize_array_data(buffer, array, array_count, mode);
}

serialize_array_data :: (using buffer: *Serializer, array: *[]$T, array_count: s64, $mode: Rw_Mode) -> bool
#modify {
    return is_serial_primitive(T);
} {
    validate_read_write();

    if array_count == 0 {
        return true;
    }

    if !align_head_up_for_type(buffer, T) {
        return false;
    }

    array_size := size_of(T) * array_count;
    new_head := head + array_size;

    if !check_new_head(buffer, new_head) {
        return false;
    }

    #if mode == .WRITE {
        memcpy(memory.data + head, array.data, array_size);
    } else {
        if array.data == null {
            use_allocator := ifx read_array_allocator.proc != null then read_array_allocator else allocator;
            array.data = xx alloc(size_of(T) * array_count,, use_allocator);
            array.count = array_count;
        }
        if array.count < array_count {
            return false;
        }
        memcpy(array.data, memory.data + head, array_size);
    }

    head = new_head;
    return true;
}

// -----------------------------------------------------------------------------------
// -------------------------------------------------------------------------- :Strings

serialize :: (using buffer: *Serializer, str: *string) -> bool {
    if rw_mode == .WRITE {
        return serialize_string(buffer, str, .WRITE);
    } else {
        return serialize_string(buffer, str, .READ);
    }
}

serialize_string :: (using buffer: *Serializer, str: *string, $mode: Rw_Mode) -> bool {
    engine_check(rw_mode == mode);
    array: []u8;
    #if mode == .WRITE {
        array.data = str.data;
        array.count = str.count;
        return serialize_array(buffer, *array, .WRITE);
    } else {
        success := serialize_array(buffer, *array, .READ);
        if success {
            str.data = array.data;
            str.count = array.count;
        }
        return success;
    }
}

// -----------------------------------------------------------------------------------
// ---------------------------------------------------------------------------- :Bytes

serialize :: (using buffer: *Serializer, data: *u8, count: s64) -> bool {
    if rw_mode == .WRITE {
        return serialize_bytes(buffer, data, xx count, .WRITE);
    } else {
        return serialize_bytes(buffer, data, xx count, .READ);
    }
}

serialize_bytes :: inline (using buffer: *Serializer, data: *u8, count: s64, $mode: Rw_Mode) -> bool {
    array: []u8 = ---;
    array.count = xx count;
    array.data = data;
    return serialize_array_data(buffer, *array, count, mode);
}

// -----------------------------------------------------------------------------------
// -------------------------------------------------------------------------- :Helpers

// warning: this can't reverse bytes, if that function is needed
write_entire_file :: (name: string, buffer: *Serializer) -> bool {
    str := string.{buffer.head, buffer.memory.data};
    return write_entire_file(name, str);
}

view_bytes_before_head :: (using buffer: *Serializer) -> string {
    return string.{head, memory.data};
}

validate_checksum :: no_inline (using buffer: *Serializer) -> bool {
    engine_check(pad_for_checksum);
    engine_check(memory.count > SERIALIZER_CHECKSUM_SIZE);
    calculated: [CHECKSUM_UINT32_COUNT]u32;
    calculate_checksum(buffer, calculated.data);
    have : *[CHECKSUM_UINT32_COUNT]u32 = xx memory.data;
    for 0..CHECKSUM_UINT32_COUNT-1 {
        if have.*[it] != calculated[it] then return false;
    }
    return true;
}

imprint_checksum :: (using buffer: *Serializer) {
    engine_check(pad_for_checksum);
    engine_check(memory.count > SERIALIZER_CHECKSUM_SIZE);
    calculate_checksum(buffer, xx memory.data);
}

calculate_checksum :: (using buffer: *Serializer, out: *u32) {

    // --- 

    calc_checksum_impl :: (bufstr: string, out: *u32) {
        str := md5(bufstr);
        array: []u32;
        array.data = xx str.data;
        array.count = str.count / 4;
        engine_check(array.count == CHECKSUM_UINT32_COUNT);
        memcpy(out, array.data, size_of(u32) * CHECKSUM_UINT32_COUNT);
    }

    // --- 

    engine_check(pad_for_checksum);
    engine_check(memory.count > SERIALIZER_CHECKSUM_SIZE);
    engine_check(head >= SERIALIZER_CHECKSUM_SIZE);
    bufstr := string.{memory.count - SERIALIZER_CHECKSUM_SIZE, memory.data + SERIALIZER_CHECKSUM_SIZE};

    auto_release_temp();
    calc_checksum_impl(bufstr, out,,temp);
}

align_head_up :: (using buffer: *Serializer, align: u8) -> bool {
    if align == 1 then return true;
    new_head := ceil_to_power_of_two_multiple(head, align);
    if new_head == head then return true;
    // goes through check_new_head so that padding can grow a dynamic buffer
    if !check_new_head(buffer, new_head) then return false;
    head = new_head;
    return true;
}

check_new_head :: (using buffer: *Serializer, new_head: s64) -> bool {
    // ---

    realloc_mem :: (desired_capacity: s64, memory: *string) {
        new_memory := alloc_string(desired_capacity);
        memcpy(new_memory.data, memory.data, memory.count);
        free(memory.data);
        memory.* = new_memory;
    }

    // ---

    engine_check(new_head >= 0);
    #if alloc_mode == .STATIC {
        return new_head <= memory.count;
    } else { // DYNAMIC
        // only writes grow the buffer. reads are bounds checked like a static buffer.
        if rw_mode == .READ {
            return new_head <= memory.count;
        }
        if new_head > memory.count {
            if allocator.proc == null {
                allocator = context.default_allocator;
            }
            realloc_mem(max(max(memory.count * 2, new_head + 1024), 8192), *memory,, allocator);
        }
        return true;
    }
}

align_head_up_for_type :: inline (using buffer: *Serializer, $T: Type) -> bool {
    return align_head_up(buffer, serial_primitive_alignment(buffer, T));
}

// -----------------------------------------------------------------------------------
// --------------------------------------------- :Byte Reversing for Net Serialization

// iterate over struct members and reverse bytes of each member. NOT recursive. todo: maybe should be recursive
reverse_bytes :: (in: *$T) 
#modify {
    tinfo := T.(*Type_Info);
    return tinfo.type == .STRUCT;
} {
    byte_buffer: [size_of(T)]u8 = ---;
    memcpy(byte_buffer.data, in, size_of(T));

    for info : T.(*Type_Info_Struct).members {
        in\_field_ptr := byte_buffer.data + info.offset_in_bytes;
        out_field_ptr := in.(*u8) + info.offset_in_bytes;
        for 0..info.type.runtime_size-1 {
            out_field_ptr[it] = in_field_ptr[(info.type.runtime_size-1) - it];
        }
    }
}

reverse_bytes :: inline (in: $T) -> T
#modify {
    tinfo := T.(*Type_Info);
    if tinfo.type == {
    case .INTEGER; 
        #through;
    case .FLOAT; 
        #through;
    case .BOOL; 
        #through;
    case .ENUM;
        return true;
    }
    return false;
} {
    out: T = ---;
    TYPE_SIZE :: #run T.(*Type_Info).runtime_size;
    #if TYPE_SIZE == {
    case 1;
        return in;
    case;
        reverse_bytes((*out).(*u8), (*in).(*u8), TYPE_SIZE);
    }
    return out;
}

reverse_bytes :: (bytes_out: *u8, bytes_in: *u8, size: s64) {
    engine_check(size > 0);
    if size == {
    case 1;
        bytes_out.* = bytes_in.*;
    case 2;
        bytes_out[0], 
        bytes_out[1]  = 
                        bytes_in[1], 
                        bytes_in[0];
    case 4;
        bytes_out[0],
        bytes_out[1],
        bytes_out[2],
        bytes_out[3]  =
                        bytes_in[3],
                        bytes_in[2],
                        bytes_in[1],
                        bytes_in[0];
    case 8;
        bytes_out[0],
        bytes_out[1],
        bytes_out[2],
        bytes_out[3],
        bytes_out[4],
        bytes_out[5],
        bytes_out[6],
        bytes_out[7]  =
                        bytes_in[7],
                        bytes_in[6],
                        bytes_in[5],
                        bytes_in[4],
                        bytes_in[3],
                        bytes_in[2],
                        bytes_in[1],
                        bytes_in[0];
    case;
        engine_check(bytes_out != bytes_in, "can't do byte swaps in a for loop (not sure why), so pointers should not alias");
        for 0..size-1 {
            bytes_out[it] = bytes_in[(size-1)-it];
        }
    }
}

// -----------------------------------------------------------------------------------
// ----------------------------------------------------------------- :Internal Helpers

#scope_module 

internal_write_primitive :: inline (using buffer: *Serializer, primitive: *$T) {
    if reverse_byte_order {
        #if #run T.(*Type_Info).type == .STRUCT {
            copy := primitive.*;
            reverse_bytes(*copy);
            memcpy(memory.data + head, *copy, size_of(T));
        } else {
            reverse_bytes(memory.data + head, primitive.(*u8), size_of(T));
        }
    } else {
        #if #complete align_mode == {
        case .PRIMITIVE;
            (memory.data + head).(*T).* = primitive.*;
        case .PARAMETER; 
            memcpy(memory.data + head, primitive, size_of(T));
        case .BYTE;
            memcpy(memory.data + head, primitive, size_of(T));
        }
    }
}

internal_read_primitive :: inline (using buffer: *Serializer, primitive: *$T) {
    if reverse_byte_order {
        #if #run T.(*Type_Info).type == .STRUCT {
            memcpy(primitive, memory.data + head, size_of(T));
            reverse_bytes(primitive); 
        } else {
            reverse_bytes(primitive.(*u8), memory.data + head, size_of(T));
        }
    } else {
        #if #complete align_mode == {
        case .PRIMITIVE;
             primitive.* = (memory.data + head).(*T).*;
        case .PARAMETER;
            memcpy(primitive, memory.data + head, size_of(T));
        case .BYTE;
            memcpy(primitive, memory.data + head, size_of(T));
        }
    }
}

serial_primitive_alignment :: inline (using buffer: *Serializer, $T: Type) -> u8 {
    T_ALIGNMENT : u8 : #run align_of(T);
    #if #complete align_mode == {
    case .PRIMITIVE;
        return T_ALIGNMENT;
    case .PARAMETER;
        return parameter_align;
    case .BYTE;
        return 1;
    }
    return 1;
}

is_serial_primitive :: (T: Type) -> bool {
    info := cast(*Type_Info)T;
    if info.type == .INTEGER return true;
    if info.type == .FLOAT   return true;
    if info.type == .BOOL    return true;
    if info.type == .ENUM    return true;
    if info.type == .STRUCT  return true;
    return false;
}

validate_read_write :: () #expand {
    engine_check(`rw_mode == `mode, "expected mode %, have mode %", `mode, `rw_mode);
    if `pad_for_checksum {
        engine_check(`head >= SERIALIZER_CHECKSUM_SIZE);
    }
}

#scope_export

serialize_test :: () -> bool {
    Test_Struct :: struct {
        a: s32;
        b: u8;
        c: float64;
        d: u16;
    }

    same :: (x: Test_Struct, y: Test_Struct) -> bool {
        return x.a == y.a && x.b == y.b && x.c == y.c && x.d == y.d;
    }

    // writes one of everything, reads it back, and checks values and that every read lands on the same head as its write
    round_trip :: (s: *$S, use_checksum := false) -> bool {
        initialize(s, .WRITE, use_checksum=use_checksum);

        t := Test_Struct.{a=-100, b=255, c=0.1, d=0xbeef};
        str := "whatever";
        array := u16.[1, 2, 3, 4, 5, 6, 7];
        array_view: []u16 = array;
        dynamic: [..]s32;
        dynamic.allocator = temp;
        for s32.[10, -20, 30] array_add(*dynamic, it);

        heads: [9]s64;
        test_condition(serialize(s, *t.a));        heads[0] = s.head;
        test_condition(serialize(s, *t.b));        heads[1] = s.head;
        test_condition(serialize(s, *t.c));        heads[2] = s.head;
        test_condition(serialize(s, *t));          heads[3] = s.head;
        test_condition(serialize(s, *str));        heads[4] = s.head;
        test_condition(serialize(s, *array_view)); heads[5] = s.head;
        test_condition(serialize(s, *dynamic));    heads[6] = s.head;
        test_condition(serialize(s, *t.b));        heads[7] = s.head;
        test_condition(serialize(s, *t.d));        heads[8] = s.head;

        if use_checksum {
            imprint_checksum(s);
            test_condition(validate_checksum(s));
            s.memory[SERIALIZER_CHECKSUM_SIZE + 3] ^= 0xff;
            test_condition(!validate_checksum(s));
            s.memory[SERIALIZER_CHECKSUM_SIZE + 3] ^= 0xff;
            test_condition(validate_checksum(s));
        }

        reset_head_with_mode(s, .READ);

        r1, r2: Test_Struct;
        r_str: string;
        r_array: []u16;
        r_dynamic: [..]s32;
        r_dynamic.allocator = temp;
        r_b: u8;
        r_d: u16;

        test_condition(serialize(s, *r1.a));      test_condition(s.head == heads[0]);
        test_condition(serialize(s, *r1.b));      test_condition(s.head == heads[1]);
        test_condition(serialize(s, *r1.c));      test_condition(s.head == heads[2]);
        test_condition(serialize(s, *r2));        test_condition(s.head == heads[3]);
        test_condition(serialize(s, *r_str));     test_condition(s.head == heads[4]);
        test_condition(serialize(s, *r_array));   test_condition(s.head == heads[5]);
        test_condition(serialize(s, *r_dynamic)); test_condition(s.head == heads[6]);
        test_condition(serialize(s, *r_b));       test_condition(s.head == heads[7]);
        test_condition(serialize(s, *r_d));       test_condition(s.head == heads[8]);

        r1.d = t.d;
        test_condition(same(r1, t) && same(r2, t));
        test_condition(r_str == str);
        test_condition(arrays_equal(r_array, array));
        test_condition(arrays_equal(r_dynamic, dynamic));
        test_condition(r_b == t.b && r_d == t.d);
        return true;
    }

    // --- every alloc and align mode round-trips, with and without a checksum
    {
        s: Serializer(.STATIC, .BYTE);
        s.read_array_allocator = temp;
        s.memory = talloc_string(1024);
        test_condition(round_trip(*s));
        test_condition(round_trip(*s, use_checksum=true));
    }
    {
        s: Serializer(.STATIC, .PRIMITIVE);
        s.read_array_allocator = temp;
        s.memory = talloc_string(1024);
        test_condition(round_trip(*s));
        test_condition(round_trip(*s, use_checksum=true));
    }
    for align : u8.[1, 2, 4, 8] {
        s: Serializer(.STATIC, .PARAMETER);
        s.read_array_allocator = temp;
        s.memory = talloc_string(1024);
        s.parameter_align = align;
        test_condition(round_trip(*s));
    }
    {
        s: Serializer(.DYNAMIC, .BYTE);
        s.allocator = context.allocator;
        s.read_array_allocator = temp;
        defer free(s.memory.data,, s.allocator);
        test_condition(round_trip(*s));
        test_condition(round_trip(*s, use_checksum=true));
    }

    // --- alignment padding
    {
        s: Serializer(.STATIC, .PRIMITIVE);
        initialize(*s, .WRITE, static_memory=talloc_string(64));
        b: u8 = 1;
        q: u64 = 2;
        serialize(*s, *b);
        serialize(*s, *q);
        test_condition(s.head == 16);
    }
    {
        s: Serializer(.STATIC, .PARAMETER);
        s.parameter_align = 4;
        initialize(*s, .WRITE, static_memory=talloc_string(64));
        b: u8 = 1;
        serialize(*s, *b);
        serialize(*s, *b);
        test_condition(s.head == 5);
    }

    // --- a static buffer refuses writes and reads past its end, and doesn't move the head
    {
        s: Serializer(.STATIC, .BYTE);
        initialize(*s, .WRITE, static_memory=talloc_string(6));
        x: u32 = 7;
        test_condition(serialize(*s, *x));
        test_condition(!serialize(*s, *x));
        test_condition(s.head == 4);

        reset_head_with_mode(*s, .READ);
        test_condition(serialize(*s, *x));
        test_condition(!serialize(*s, *x));
        test_condition(s.head == 4);
    }

    // --- a dynamic buffer keeps its contents while it grows
    {
        s: Serializer(.DYNAMIC, .PRIMITIVE);
        s.allocator = context.allocator;
        defer free(s.memory.data,, s.allocator);
        initialize(*s, .WRITE);
        for i : 0..999 {
            v := (i * 7919).(u32);
            test_condition(serialize(*s, *v));
        }
        test_condition(s.head == 4000);
        reset_head_with_mode(*s, .READ);
        for i : 0..999 {
            v: u32;
            test_condition(serialize(*s, *v));
            test_condition(v == (i * 7919).(u32));
        }
    }

    // --- reversed byte order is big endian on the wire and transparent to the caller
    {
        Wire :: struct {
            a: u16;
            b: u32;
        }
        s: Serializer(.STATIC, .BYTE);
        initialize(*s, .WRITE, static_memory=talloc_string(32), reverse_primitive_byte_order=true);
        v: u32 = 0x11223344;
        w := Wire.{0x0102, 0x0a0b0c0d};
        f: float64 = -1234.5;
        serialize(*s, *v);
        serialize(*s, *w);
        serialize(*s, *f);
        test_condition(s.memory[0] == 0x11 && s.memory[1] == 0x22 && s.memory[2] == 0x33 && s.memory[3] == 0x44);

        reset_head_with_mode(*s, .READ);
        rv: u32;
        rw: Wire;
        rf: float64;
        serialize(*s, *rv);
        serialize(*s, *rw);
        serialize(*s, *rf);
        test_condition(rv == v && rw.a == w.a && rw.b == w.b && rf == f);

        reset_head_with_mode(*s, .READ);
        test_condition(read_out(*s, u32) == v);
    }

    test_condition(reverse_bytes(cast(u32) 0x11223344) == 0x44332211);
    test_condition(reverse_bytes(cast(s16) 0x0102) == 0x0201);

    // --- reading past the end of a dynamic buffer fails instead of growing it
    {
        s: Serializer(.DYNAMIC, .BYTE);
        s.allocator = context.allocator;
        defer free(s.memory.data,, s.allocator);
        initialize(*s, .WRITE);
        v: u32 = 7;
        serialize(*s, *v);
        capacity := s.memory.count;
        reset_head_with_mode(*s, .READ);
        big: [16384]u8;
        test_condition(!serialize(*s, big.data, big.count));
        test_condition(s.memory.count == capacity);
    }

    // --- alignment padding can grow a dynamic buffer
    {
        s: Serializer(.DYNAMIC, .PRIMITIVE);
        s.allocator = context.allocator;
        defer free(s.memory.data,, s.allocator);
        initialize(*s, .WRITE);
        bytes: [9217]u8;
        serialize(*s, bytes.data, bytes.count);   // capacity becomes 9217 + 1024, not a multiple of 8
        filler: [1024]u8;
        serialize(*s, filler.data, filler.count); // head lands exactly on the capacity
        test_condition(s.head == s.memory.count && s.head % 8 != 0);
        q: u64 = 2;
        test_condition(serialize(*s, *q));        // needs padding past the capacity
    }

    // --- reset keeps or releases memory without asserting
    {
        s: Serializer(.DYNAMIC, .BYTE);
        s.allocator = context.allocator;
        initialize(*s, .WRITE);
        v: u32 = 7;
        serialize(*s, *v);
        reset(*s);
        test_condition(s.head == 0 && s.memory.count > 0);
        reset(*s, keep_allocation=false);
        test_condition(s.memory.count == 0 && s.memory.data == null);
    }

    return true;
}

// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.
