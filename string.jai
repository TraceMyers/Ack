reset :: inline (s: *string) {
    if s.data != null {
        free(s.data);
        s.data = null;
    }
    s.count = 0;
}

as_array :: inline (str: string, $T: Type) -> []T {
    t_array: []T = ---;
    t_array.count = str.count / size_of(T);
    t_array.data = xx str.data;
    // requiring that the number of bytes is a multiple of the item size; no bytes left out
    engine_check(.LOW, t_array.count * size_of(T) == str.count); 
    return t_array;
}

to_string_safe :: inline (str: *u8, max_read_count: s64) -> string {
    for 0..max_read_count-1 {
        if str[it] == 0 {
            return string.{it, str};
        }
    }
    return string.{max_read_count, str};
}

as_string :: inline (array: []$T) -> string {
    return string.{array.count * size_of(T), xx array.data};
}

as_string :: inline (item: $T) -> string 
#modify {
    info := cast(*Type_Info)T;
    if info.type == .ARRAY {
        return false;
    }
    return true;
} {
    return string.{size_of(T), xx *item};
}

concatenate :: (strings: ..string) -> string {
    out_count := 0;
    for strings {
        out_count += it.count;
    }

    out_str := alloc_string(out_count);
    copy_loc := 0;
    for strings {
        memcpy(out_str.data + copy_loc, it.data, it.count);
        copy_loc += it.count;
    }
    engine_check(.LOW, copy_loc == out_str.count);

    return out_str;
}

reverse :: (str: string) {
    b: s64;
    half_count := str.count >> 1;
    while b <= half_count {
        e := str.count - 1 - b;
        str[b], str[e] = str[e], str[b];
        b += 1;
    }
}

is_alpha_upper :: inline (code_point: u32) -> bool {
    return code_point <= #char "Z" && code_point >= #char "A";
}

is_alpha_lower :: inline (code_point: u32) -> bool {
    return code_point <= #char "z" && code_point >= #char "a";
}

is_slash :: inline (code_point: u32) -> bool {
    return code_point == #char "/" || code_point == #char "\\";
}

to_lower_in_place :: inline (str: *string) {
    for *(str.*) {
        it.* = to_lower(it.*);
    }
}

view :: inline (str: string, begin: int, count: int) -> string {
    out := advance(str, begin);
    return {min(out.count, count), out.data};
}

to_lower :: inline (str: string) -> string {
    out_str := alloc_string(str.count);
    memcpy(out_str.data, str.data, str.count);
    to_lower_in_place(*out_str);
    return out_str;
}

to_upper_in_place :: inline (str: *string) {
    for *(str.*) {
        it.* = to_upper(it.*);
    }
}

to_upper :: inline (str: string) -> string {
    out_str := alloc_string(str.count);
    memcpy(out_str.data, str.data, str.count);
    to_upper_in_place(*out_str);
    return out_str;
}

hex_text_to_bytes :: (hex_text: string) -> string, bool {
    engine_check(.LOW, hex_text.count % 2 == 0);

    out_bytes := alloc_string(hex_text.count / 2);

    i := 0;
    high_nibble := true;

    for hex_text {
        digit: u8 = ---;
        if it >= #char "a" && it <= #char "z" {
            digit = it - #char "a" + 10;
        } else if it >= #char "A" && it <= #char "Z" {
            digit = it - #char "A" + 10;
        } else if digit >= #char "0" && digit <= #char "9" {
            digit = it - #char "0";
        } else {
            free(out_bytes.data);
            return {}, false;
        }

        one_if_doing_high_nibble := cast(int) (high_nibble != false);
        out_bytes[i] |= digit << (4 * one_if_doing_high_nibble);

        high_nibble = !high_nibble;
        i += one_if_doing_high_nibble;
    }

    return out_bytes, true;
}

// for expansion. process a string per line. usage = 'for :per_line your_string { .. }'
per_line :: (str: *string, body: Code, flags: For_Flags) #expand {
    // - getting a pointer to a local string instantiation doesn't do anything helpful.
    // you can modify the data and the count regardless
    // - going from last to first line might be useful to somebody, but I'm not sure it's
    // useful enough to implement here.
    #assert(flags == 0);

    line_count: s64;
    left, right: string;
    right = str.*;
    success: bool;
    end_loop: bool;

    while !end_loop {
        prev_right := right;
        success, left, right = split_from_left(right, #char "\n");

        line: string = ---;

        if success {
            if left.count > 0 && left[left.count-1] == #char "\r" {
                left.count -= 1;
            }
            line = left;
        } else {
            if prev_right.count > 0 {
                line = prev_right;
                end_loop = true;
            } else {
                break;
            }
        }

        `it := line;
        `it_index := line_count;
        line_count += 1;

        #insert body;
    }
}

c_strings_equal :: (a: *u8, b: *u8, max_read_count: s64) -> bool {
    if max_read_count <= 0 {
        return false;
    }
    for i : 0..max_read_count-1 {
        if a[i] != b[i] {
            return false;
        }
        if a[i] == 0 {
            return true;
        }
    }
    return true;
}

// String_Exchange + for_expansion = progressive string consumption with arbitrary break condition
// usage example:
//
// my_string := "hello/there..friend";
// my_exchange := String_Exchange.{src=my_string}; // can also have src be a pointer
// while my_exchange.src.count > 0 {
//     for my_exchange { 
//          if it == #char "/"
//              // trims the end '/' from dst
//              my_exchange.trim_bytes = 1;
//              break;
//          } else if it == #char "." {
//              if it_index < src.count - 1 && src[it_index+1] == #char "." {
//                  // trims the end '..' from dst
//                  my_exchange.trim_bytes = 2;
//                  break;
//              } else {
//                  check(false, "improperly formatted blah blah");
//              }
//          }
//     }
//     <- here, do something with my_exchange.dst (1."hello", 2."there", 3."friend")
// }
String_Exchange :: struct($type := enum { NORMAL; PTR; }.NORMAL) {
    source_type :: #insert #run tprint("%string;", ifx type == .NORMAL then "" else "*");
    src: source_type;
    dst: string;
    trim_bytes: s32;
    reset_trim_bytes := true;
    broke_out_of_loop: bool;
}

for_expansion :: (exchange: *String_Exchange, body: Code, flags: For_Flags) #expand {
    #assert(flags == 0);

    // letting the user know a break happened, so they can differentiate between
    // their own inserted break statement and just reaching the end of the source string
    do_break :: () #expand {
        exchange.broke_out_of_loop = true;
        break;
    }

    i := 0;
    if exchange.reset_trim_bytes {
        exchange.trim_bytes = 0;
    }
    exchange.broke_out_of_loop = false;

    while i < exchange.src.count {
        `it := exchange.src.data[i];
        `it_index := i;
        i += 1;

        #insert (break=do_break()) body;
    }

    exchange.dst = {max(i - exchange.trim_bytes, 0), exchange.src.data};
    exchange.src.data  += i;
    exchange.src.count -= i;
    if exchange.src.count <= 0 {
        exchange.src.data = null;
        exchange.src.count = 0;
    }
}


String_Stack :: struct {
    bytes: [..]u8;
    sizes: [..]s32;
    initialized: bool;
}

init :: inline (stack: *String_Stack) {
    if !stack.initialized {
        engine_check(.LOW, context.allocator.proc != temp.proc, "string stack allocator can't be the temporary allocator as that would risk memory corruption");
        array_reserve(*stack.bytes, 4096);
        array_reserve(*stack.sizes, 128);
        stack.initialized = true;
    }
}

free_stack :: (stack: *String_Stack) {
    array_reset(*stack.bytes);
    array_reset(*stack.sizes);
}

push :: (stack: *String_Stack, fmt: string, args: ..Any) -> string {
    init(stack);

    auto_release_temp();

    builder: String_Builder;
    builder.allocator = temp;
    print(*builder, "%", as_string(stack.bytes));
    print(*builder, fmt, ..args);
    new_bytes := builder_to_string(*builder,, temp);

    added_bytes := new_bytes.count - stack.bytes.count;
    array_add(*stack.sizes, xx added_bytes);

    if new_bytes.count > stack.bytes.count {
        array_resize(*stack.bytes, new_bytes.count);
    }

    if new_bytes.count > 0 {
        memcpy(stack.bytes.data, new_bytes.data, new_bytes.count);
    }
    return view_string(stack);
}

pop :: (stack: *String_Stack) {
    engine_check(.LOW, stack.sizes.count > 0);
    
    remove_count := stack.sizes[stack.sizes.count-1];
    stack.sizes.count -= 1;
    stack.bytes.count -= remove_count;
}

view_string :: (stack: *String_Stack) -> string {
    return string.{stack.bytes.count, stack.bytes.data};
}

// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.
