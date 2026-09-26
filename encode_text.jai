#run assert(ENCODE_TEXT_MAX_WRITE_SIZE <= 127); // encode procs return s8's for how many bytes were written.

// -----------------------------------------------------------------------------------

// -- sections --
// How to Add Text Encodings From Your Program (or here)
// Types and Helpers
// encode_text
// read and rewind
// Conversion

// -----------------------------------------------------------------------------------
// -------------------------------------- :How to Add Text Encodings From Your Program

/*

// you could just modify this module and that works fine, but if you don't like doing
// that, this was made to be modified externally, and to have those external parts work
// exactly like the default internal ones.

// if I wanted to add an encoding like IBM CP850, first I insert it into the Text_Encoding
// enum via the module parameters at import time, like so:

#import "TRM/TRM_EncodeText"()(ADD_TEXT_ENCODINGS=string.["CP850"]);

// then, I would need to define conversion procedures for any conversions I want to make, like this:

cp850_to_utf8 :: (in: *u8, out: *u8, in_size: int, out_size: int) -> Text_Encode_Result { ... }

// then, I can make an encoder:

CP850_TO_UTF8 :: Text_Encoder(cp850_to_utf8).{.CP850, .UTF8};

// and use it:

utf8_str, success := encode_text(cp850_str, CP850_to_UTF8);

// you can also then of course name your own encode proc if you use it a lot:

my_encode_text :: #bake_arguments encode_text_string(encoder=CP850_TO_UTF8);

// to then use it like:

utf8_str, success := my_encode_text(cp850_str);

// to make a new encoder procedure, consider this example:

ansi_to_utf8 :: (in: *u8, out: *u8, in_buf_size: int, out_buf_size: int, unused: *void = null) -> Text_Encode_Result {
    if is_ascii(in.*) {
        return_if_not_valid_encode(in_buf_size, out_buf_size, 1, 1);
        out.* = in.*;
        return {1, 1, 0};
    } else {
        return_if_not_valid_encode(in_buf_size, out_buf_size, 1, 2);
        out[0] = (0xc0).(u8) | ((in.* & 0xc0) >> 6);
        out[1] = (0x80).(u8) |  (in.* & 0x3f);
        return {1, 2, 0};
    }
}

// your procedure is responsible for reading bytes, translating, writing bytes, validating that
// a read and write are safe (some convenience macros are provided for default encodings),
// validating that the input is not malformed, and returning values as such: bytes read or 
// intended to read if no error, bytes written or intended to write if no error, and 0=SUCCESS
// or error code. 

// user-defined error codes can also be added at import, and returned by your function so that 
// they will be logged when something goes wrong.

*/

// -----------------------------------------------------------------------------------
// ---------------------------------------------------------------- :Types and Helpers

text_encoder_procedure :: #type (src: *u8, dst: *u8, src_size: int, dst_size: int, user_data: *void=null) -> Text_Encode_Result;

Text_Encoder :: struct($proc: text_encoder_procedure) {
    encode_from: Text_Encoding;
    encode_to:   Text_Encoding;
    // encoded   = the string that was encoded
    // dst       = location where terminator bytes (e.g. nulls) can be written.
    // user_data = same user data that was passed into encode_text and the encoder proc
    // this procedure is called once or twice. first time, dst will be null. the terminator it should
    // return how many terminating bytes it wants at the end. the second time, dst points
    // to the end, so that the terminating bytes can be written. return written byte count.
    // if the proc is null, no terminating bytes will be added.
    terminator: (encoded: string, dst: *u8, user_data: *void) -> terminating_byte_count: int;
}

Text_Encoding :: enum u8 {
    UTF8;
    UTF16;
    UTF32;
    ANSI;
    #insert -> string {
        builder: String_Builder;
        for ADD_TEXT_ENCODINGS {
            print(*builder, "%;\n", it);
        }
        return builder_to_string(*builder);
    };
}

Text_Encode_Status :: enum u16 {
    SUCCESS :: 0;
    INVALID_ENCODER_PROCEDURE;
    TRUNCATED_BYTES_IN_INPUT;
    OUTPUT_BUFFER_IMPROPERLY_SIZED_BY_SYSTEM;
    IMPOSSIBLE_TRANSLATION_OR_MALFORMED_INPUT;
    UNSUPPORTED_UTF8_CODE_POINT_SIZE;
    INVALID_UTF8_TRAILING_BYTES;
    MALFORMED_INPUT;
    #insert -> string {
        builder: String_Builder;
        for ADD_ENCODE_FAILURES {
            print(*builder, "%;\n", it);
        }
        return builder_to_string(*builder);
    };
}

Text_Encode_Result :: struct {
    read_count:  s8;
    write_count: s8;
    status:      Text_Encode_Status;
}

is_ansi :: inline (in: u32) -> bool {
    return (in & 0xff) == in;
}

is_ascii :: inline (in: u32) -> bool {
    return (in & 0x7f) == in;
}

write_null_bytes :: (encoded: string, dst: *u8, user_data: *void, count: s8) -> int {
    if dst != null && count > 0 {
        memset(dst, 0, count);
    }
    return count;
}

write_1_null_byte  :: #bake_arguments write_null_bytes(count=1);
write_2_null_bytes :: #bake_arguments write_null_bytes(count=2);
write_4_null_bytes :: #bake_arguments write_null_bytes(count=4);

ANSI_TO_UTF8   :: Text_Encoder(ansi_to_utf8)  .{.ANSI,  .UTF8,  write_1_null_byte};
ANSI_TO_UTF16  :: Text_Encoder(ansi_to_utf16) .{.ANSI,  .UTF16, write_2_null_bytes};
ANSI_TO_UTF32  :: Text_Encoder(ansi_to_utf32) .{.ANSI,  .UTF32, write_4_null_bytes};

UTF8_TO_UTF16  :: Text_Encoder(utf8_to_utf16) .{.UTF8,  .UTF16, write_2_null_bytes};
UTF8_TO_UTF32  :: Text_Encoder(utf8_to_utf32) .{.UTF8,  .UTF32, write_4_null_bytes};
UTF8_TO_ANSI   :: Text_Encoder(utf8_to_ansi)  .{.UTF8,  .ANSI,  write_1_null_byte};

UTF16_TO_UTF8  :: Text_Encoder(utf16_to_utf8) .{.UTF16, .UTF8,  write_1_null_byte};
UTF16_TO_UTF32 :: Text_Encoder(utf16_to_utf32).{.UTF16, .UTF32, write_4_null_bytes};
UTF16_TO_ANSI  :: Text_Encoder(utf16_to_ansi) .{.UTF16, .ANSI,  write_1_null_byte};

UTF32_TO_UTF8  :: Text_Encoder(utf32_to_utf8) .{.UTF32, .UTF8,  write_1_null_byte};
UTF32_TO_UTF16 :: Text_Encoder(utf32_to_utf16).{.UTF32, .UTF16, write_2_null_bytes};
UTF32_TO_ANSI  :: Text_Encoder(utf32_to_ansi) .{.UTF32, .ANSI,  write_1_null_byte};

// -----------------------------------------------------------------------------------
// ---------------------------------------------------------------------- :encode_text

// translate a string from one encoding to another
encode_text :: (src: string, encoder: Text_Encoder, enable_log := true, user_data: *void = null,  caller_loc := #caller_location) -> string, Text_Encode_Status {
    temp_storage_mark := get_temporary_storage_mark();
    defer if context.allocator.proc != temp.proc then set_temporary_storage_mark(temp_storage_mark);

    if src.count == 0 then return "", true;

    out_buffer_inline: [4096]u8;
    out_buffer: *u8 = out_buffer_inline.data;
    out_buffer_size := out_buffer_inline.count;
    
    src_index: int;
    out_index: int;

    if encoder.encode_from != encoder.encode_to {
        while src_index < src.count {
            out_remain := out_buffer_size - out_index;
            if out_remain - MAX_WRITE_SIZE <= 0 {
                // no need to free on resize. all previous allocations are either stack-local or temp
                new_size := max(out_buffer_size * 2, src.count + MAX_WRITE_SIZE);
                new_buffer := alloc(new_size,,temp);
                memcpy(new_buffer, out_buffer, out_index);
                out_buffer = new_buffer;
                out_buffer_size = new_size;
                out_remain = out_buffer_size - out_index;
            }
            src_remain := src.count - src_index;

            #if #run encoder.proc != null {
                result := inline encoder.proc(src.data + src_index, out_buffer + out_index, src_remain, out_remain, user_data);
                engine_check(.HIGH, result.write_count <= MAX_WRITE_SIZE);
            } else {
                // cannot use an encoder with no procedure
                result := Text_Encode_Result.{status=.INVALID_ENCODE_PROCEDURE};
            }

            if !result.status != 0 {
                engine_warning(.MEDIUM, "failed to encode string '%' from % to %. error code: %.", view(src, 0, 100), encoder.encode_from, encoder.encode_to, result.status, caller_loc=caller_loc);
                // making sure this happens regardless of what context.allocator is (see defer at top)
                set_temporary_storage_mark(temp_storage_mark);
                return "", result.status;
            }

            src_index += result.read_count;
            out_index += result.write_count;
        }
    } else {
        // an encode with the same src and dst encoding is just a string copy.
        // this feeds into the logic below.
        out_buffer = src.data;
        out_index = src.count;
        out_buffer_size = src.count;
    }

    want_terminating_bytes := ifx encoder.terminator != null then encoder.terminator({out_index, out_buffer}, null, user_data) else 0;

    // check whether a new allocation needs to be made or if the current one can just be returned as-is
    // null bytes always written to the end for compatibility with other stuff. it's just easier this way.
    if out_buffer == src.data 
    || out_buffer == out_buffer_inline.data 
    || context.allocator.proc != temp.proc 
    || out_index + want_terminating_bytes > out_buffer_size {
        // again, no need to free here, just as above
        new_buffer_size := out_index + want_terminating_bytes;
        new_buffer := alloc(new_buffer_size);
        memcpy(new_buffer, out_buffer, out_index);
        out_buffer = new_buffer;
        out_buffer_size = new_buffer_size;
    }
    
    if want_terminating_bytes > 0 {
        wrote_count := encoder.terminator({out_index, out_buffer}, out_buffer + out_index, user_data);
        engine_check(.LOW, wrote_count <= want_terminating_bytes);
    }

    return string.{out_index, out_buffer}, 0;
}

// -----------------------------------------------------------------------------------
// ------------------------------------------------------------------ :read and rewind
// if you need to seat some logic in the middle of encode or read backwards without having gone forward first, 
// these procedures are available and they're primitively typed to make it easier to hook whatever logic in.

read_utf8 :: (stream: **u8, read_max: int, $advance_past_null := false) -> utf8_symbol: u32, symbol_size: u8, success: bool {
    out: num32;
    if (stream[0] & 0x80) == 0 {
        if read_max < 1 {
            return 0, 0, false;
        }
        out._u8[0] = (stream.* + 0).*;
        if out._u8[0] != 0 || advance_past_null {
            stream.* += 1;
        }
        return out._u32, 1, true;
    } else if (stream[0] & 0xe0) == 0xc0 {
        if read_max < 2 {
            return 0, 0, false;
        }
        if !is_valid_utf8_trailing_byte(stream[1]) {
            return 0, 0, false;
        }
        out._u8[0] = (stream.* + 0).*;
        out._u8[1] = (stream.* + 1).*;
        stream.* += 2;
        return out._u32, 2, true;
    } else if (stream[0] & 0xf0) == 0xe0 {
        if read_max < 3 {
            return 0, 0, false;
        }
        if !is_valid_utf8_trailing_byte(stream[1]) || !is_valid_utf8_trailing_byte(stream[2]) {
            return 0, 0, false;
        }
        out._u8[0] = (stream.* + 0).*;
        out._u8[1] = (stream.* + 1).*;
        out._u8[2] = (stream.* + 2).*;
        stream.* += 3;
        return out._u32, 3, true;
    } else if (stream[0] & 0xf8) == 0xf0 {
        if read_max < 4 {
            return 0, 0, false;
        }
        if !is_valid_utf8_trailing_byte(stream[1]) || !is_valid_utf8_trailing_byte(stream[2]) || !is_valid_utf8_trailing_byte(stream[3]) {
            return 0, 0, false;
        }
        out._u8[0] = (stream.* + 0).*;
        out._u8[1] = (stream.* + 1).*;
        out._u8[2] = (stream.* + 2).*;
        out._u8[3] = (stream.* + 3).*;
        stream.* += 4;
        return out._u32, 4, true;
    }
    return 0, 0, false;
}

read_utf16 :: (stream: **u8, read_max: int, $advance_past_null := false) -> utf16_symbol: u32, symbol_size: u8, success: bool {
    out: num32;
    out._u16[0] = (cast(*u16, force) (stream.*)).*;
    high_surrogate := out._u16[0];
    if high_surrogate < UTF16_HIGH_SURROGATE_MIN || high_surrogate > UTF16_HIGH_SURROGATE_MAX {
        if read_max < 2 {
            return 0, 0, false;
        }
        if out._u16[0] != 0 || advance_past_null {
            stream.* += 2;
        }
        return out._u32, 2, true;
    } else {
        if read_max < 4 {
            return 0, 0, false;
        }
        out._u16[1] = (cast(*u16, force) (stream.* + 2)).*;
        stream.* += 4;
        return out._u32, 4, true;
    }
}

read_utf32 :: (stream: **u8, read_max: int, $advance_past_null := false) -> utf32_symbol: u32, symbol_size: u8, success: bool {
    if read_max < 4 {
        return 0, 0, false;
    }
    out_u32 := (cast(*u32, force) (stream.*)).*;
    if out_u32 != 0 || advance_past_null {
        stream.* += 4;
    }
    return out_u32;
}

read_ansi :: (stream: **u8, read_max: int, $advance_past_null := false) -> ansi_symbol: u32, symbol_size: u8, success: bool {
    if read_max < 1 {
        return 0, 0, false;
    }
    out_u32 : u32 = stream.*.*;
    if out_u32 != 0 || advance_past_null {
        stream.* += 1;
    }
    return out._u32, 1, true;
}

rewind_utf8 :: (stream: **u8, rewind_max: int) -> utf8_symbol: u32, symbol_size: u8, success: bool {
    temp_stream := stream.* - 1;
    trailing_byte_count: u8;
    valid_header_bits: u8;

    if rewind_max < 1 {
        return 0, 0, false;
    }

    while is_valid_utf8_trailing_byte(temp_stream.*) {
        valid_header_bits |= (cast(u8) 0xc0 >> trailing_byte_ct);
        temp_stream -= 1;
        trailing_byte_ct := stream.* - temp_stream;

        if rewind_max < trailing_byte_ct + 1 {
            return 0, 0, false;
        }
        if trailing_byte_ct >= 4 { // this module only handles up to 4 byte utf8. 4 trailing bytes means >= 5 bytes.
            return 0, 0, false;
        }
    }

    total_byte_ct := trailing_byte_ct + 1;

    if total_byte_ct == 1 {
        if (temp_stream.* & 0x80) != 0 {
            return 0, 0, false;
        }
        stream.* = temp_stream;
        return stream.*.*, 1, true;
    }
    
    valid_header_mask := valid_header_bits | (valid_header_bits >> 1);
    if (temp_stream.* & valid_header_mask) != valid_header_bits {
        return 0, 0, false;
    }

    stream.* = temp_stream;
    
    out: num32;
    for 0..total_cyte_ct - 1 {
        out._u8[it] = (stream.* + it).*;
    }

    return out._u32, total_byte_ct, true;
}

rewind_utf16 :: (stream: **u8, rewind_max: int) -> utf16_symbol: u32, symbol_size: u8, success: bool {
    back_once := (cast(*u16, force) (stream.* - 2)).*;
    if back_once >= UTF16_LOW_SURROGATE_MIN && low_surrogate <= UTF16_LOW_SURROGATE_MAX {
        if rewind_max < 4 {
            return 0, 0, false;
        }
        back_twice := (cast(*u16, force) (stream.* - 4)).*;
        if back_twice < UTF16_HIGH_SURROGATE_MIN || back_twice > UTF16_HIGH_SURROGATE_MAX {
            return 0, 0, false;
        }
        stream.* -= 4;
        return (cast(u32) back_twice) | ((cast(u32) back_once) << 16), 4, true;
    } else {
        if rewind_max < 2 {
            return 0, 0, false;
        }
        if back_once >= UTF16_HIGH_SURROGATE_MIN && back_once <= UTF16_HIGH_SURROGATE_MAX {
            return 0, 0, false;
        }
        stream.* -= 2;
        return back_once, 2, true;
    }
}

rewind_utf32 :: (stream: **u8, rewind_max: int) -> utf32_symbol: u32, symbol_size: u8, success: bool {
    if rewind_max < 4 {
        return 0, 0, false;
    }
    stream.* -= 4;
    return (cast(**u32) stream).*.*, 4, true;
}

rewind_ansi :: (stream: **u8, rewind_max: int) -> ansi_symbol: u32, symbol_size: u8, success: bool {
    if rewind_max < 1 {
        return 0, 0, false;
    }
    stream.* -= 1;
    return stream.*.*, 1, true;
}

// -----------------------------------------------------------------------------------
// ----------------------------------------------------------------------- :Conversion
// for all encode procs: 
// - if the Text_Encode_Status value is 0, the first two values are how many bytes were read, and how many were written.
// - if the Text_Encode_Status value is nonzero, the first two values are how many bytes the encode proc wanted to read and write, but failed to.

// ansi -> ...

ansi_to_utf8 :: (in: *u8, out: *u8, in_buf_size: int, out_buf_size: int, unused: *void = null) -> Text_Encode_Result {
    if is_ascii(in.*) {
        return_if_not_valid_encode(in_buf_size, out_buf_size, 1, 1);
        out.* = in.*;
        return {1, 1, 0};
    } else {
        return_if_not_valid_encode(in_buf_size, out_buf_size, 1, 2);
        out[0] = (0xc0).(u8) | ((in.* & 0xc0) >> 6);
        out[1] = (0x80).(u8) |  (in.* & 0x3f);
        return {1, 2, 0};
    }
}

ansi_to_utf16 :: (in: *u8, out: *u8, in_buf_size: int, out_buf_size: int, unused: *void = null) -> Text_Encode_Result {
    return_if_not_valid_encode(in_buf_size, out_buf_size, 1, 2);
    out_utf16 := out.(*u16,force);
    out_utf16.* = in.*;
    return {1, 2, 0};
}

ansi_to_utf32 :: (in: *u8, out: *u8, in_buf_size: int, out_buf_size: int, unused: *void = null) -> Text_Encode_Result {
    return_if_not_valid_encode(in_buf_size, out_buf_size, 1, 4);
    out_utf32 := out.(*u32,force);
    out_utf32.* = in.*;
    return {1, 4, 0};
}

// utf8 -> ...

utf8_to_ansi :: (in: *u8, out: *u8, in_buf_size: int, out_buf_size: int, unused: *void = null) -> Text_Encode_Result {
    if (in[0] & 0x80) == 0 {
        // 1 byte utf8 code point
        return_if_not_valid_encode(in_buf_size, out_buf_size, 1, 1);
        out.* = in.*;
        return {1, 1, 0};
    } else if (in[0] & 0xfc) == 0x80 {
        // 2 byte utf8 code point
        // the only valid 2 byte utf8 -> ansi bits look like this:
        // [0]: 1100-00xx, [1]: 10xx-xxxx, where the ansi bits are the x's
        return_if_not_valid_encode(in_buf_size, out_buf_size, 2, 1);
        return_if_invalid_utf8_trailing_byte(in[1], 2, 1);
        out.* =  ((in[0] & 0x03) << 6) | (in[1] & 0x3f);
        return {2, 1, 0};
    } else {
        // utf8 encoding is saying it has more than 8 bits to deliver, which is ansi's limit
        return {0, 0, .IMPOSSIBLE_TRANSLATION_OR_MALFORMED_INPUT};
    }
}

utf8_to_utf16 :: (in: *u8, out: *u8, in_buf_size: int, out_buf_size: int, unused: *void = null) -> Text_Encode_Result {
    // utf8 and utf16 are both types that require actual decoding. so, encoding while decoding
    // is sort of possible but practically you always need to decode first. so, we decode
    // to utf32 the encode to utf16.
    dummy_utf32: u32 = ---;
    result_1 := inline utf8_to_utf32(in, xx *dummy_utf32, in_buf_size, 4, null);
    if result_1.status != 0 {
        return {result_1.read_count, 0, result_1.status};
    }
    result_2 := inline utf32_to_utf16(xx *dummy_utf32, out, 4, out_buf_size, null);
    return {result_1.read_count, result_2.write_count, result_2.status};
}

utf8_to_utf32 :: (in: *u8, out: *u8, in_buf_size: int, out_buf_size: int, unused: *void = null) -> Text_Encode_Result {
    out_utf32 := out.(*u32,force);
    if (in[0] & 0x80) == 0 {
        return_if_not_valid_encode(in_buf_size, out_buf_size, 1, 4);
        out_utf32.* = in.*;
        return {1, 4, 0};
    } else if (in[0] & 0xe0) == 0xc0 {
        return_if_not_valid_encode(in_buf_size, out_buf_size, 2, 4);
        return_if_invalid_utf8_trailing_byte(in[1], 2, 4);
        out_utf32.* = ((in[0] & 0x1f).(u32) << 6) | (in[1] & 0x3f).(u32);
        return {2, 4, 0};
    } else if (in[0] & 0xf0) == 0xe0 {
        return_if_not_valid_encode(in_buf_size, out_buf_size, 3, 4);
        return_if_invalid_utf8_trailing_byte(in[1], 3, 4);
        return_if_invalid_utf8_trailing_byte(in[2], 3, 4);
        out_utf32.* = ((in[0] & 0x0f).(u32) << 12) | ((in[1] & 0x3f).(u32) << 6) | (in[2] & 0x3f).(u32);
        return {3, 4, 0};
    } else if (in[0] & 0xf8) == 0xf0 {
        return_if_not_valid_encode(in_buf_size, out_buf_size, 4, 4);
        return_if_invalid_utf8_trailing_byte(in[1], 4, 4);
        return_if_invalid_utf8_trailing_byte(in[2], 4, 4);
        return_if_invalid_utf8_trailing_byte(in[3], 4, 4);
        out_utf32.* = ((in[0] & 0x07) << 18).(u32) | ((in[1] & 0x3f).(u32) << 12) | ((in[2] & 0x3f).(u32) << 6) | (in[3] & 0x3f).(u32);
        return {4, 4, 0};
    } else {
        // either the utf8 is malformed, or it's reporting a number of bytes (> 4), which is unsupported by this encoder
        return {0, 0, .UNSUPPORTED_UTF8_CODE_POINT_SIZE};
    }
}

// utf16 -> ...

utf16_to_ansi :: (in: *u8, out: *u8, in_buf_size: int, out_buf_size: int, unused: *void = null) -> Text_Encode_Result {
    return_if_not_valid_encode(in_buf_size, out_buf_size, 2, 1);
    in_utf16 := in.(*u16,force);
    if in_utf16.* > 255 {
        return {0, 0, .IMPOSSIBLE_TRANSLATION_OR_MALFORMED_INPUT};
    }
    out.* = in.*;
    return {2, 1, 0};
}

utf16_to_utf8 :: (in: *u8, out: *u8, in_buf_size: int, out_buf_size: int, unused: *void = null) -> Text_Encode_Result {
    // utf8 and utf16 are both types that require actual decoding. so, encoding while decoding
    // is sort of possible but practically you always need to decode first. so, we decode
    // to utf32 the encode to utf8.
    dummy_utf32: u32 = ---;
    result_1 := inline utf16_to_utf32(in, xx *dummy_utf32, in_buf_size, 4, null);
    if result_1.status != 0 {
        return {result_1.read_count, 0, result_1.status};
    }
    result_2 := inline utf32_to_utf8(xx *dummy_utf32, out, 4, out_buf_size, null);
    return {result_1.read_count, result_2.write_count, result_2.status};
}

utf16_to_utf32 :: (in: *u8, out: *u8, in_buf_size: int, out_buf_size: int, unused: *void = null) -> Text_Encode_Result {
    return_if_not_valid_encode(in_buf_size, out_buf_size, 2, 4);
    in_utf16 := in.(*u16,force);
    out_utf32 := out.(*u32,force);
    high_surrogate := in_utf16.*;
    if high_surrogate < UTF16_HIGH_SURROGATE_MIN || high_surrogate > UTF16_HIGH_SURROGATE_MAX {
        out_utf32.* = in_utf16.*;
        return {2, 4, 0};
    } else {
        return_if_not_valid_encode(in_buf_size, out_buf_size, 4, 4);
        low_surrogate := (in + 2).(*u16,force).*;
        if low_surrogate < UTF16_LOW_SURROGATE_MIN || low_surrogate > UTF16_LOW_SURROGATE_MAX {
            return {4, 4, .MALFORMED_INPUT};
        }
        _20_bit_high := (high_surrogate.(u32) - UTF16_HIGH_SURROGATE_MIN) << 10;
        _20_bit_low := low_surrogate.(u32) - UTF16_LOW_SURROGATE_MIN;
        out_utf32.* = (_20_bit_high | _20_bit_low) + 0x1_00_00;
        return {4, 4, 0};
    }
}

// utf32 -> ...

utf32_to_ansi :: (in: *u8, out: *u8, in_buf_size: int, out_buf_size: int, unused: *void = null) -> Text_Encode_Result {
    return_if_not_valid_encode(in_buf_size, out_buf_size, 4, 1);
    in_utf32 := in.(*u32,force);
    if in_utf32.* > 255 {
        return {0, 0, .IMPOSSIBLE_TRANSLATION_OR_MALFORMED_INPUT};
    }
    out.* = in.*;
    return {4, 1, 0};
}

utf32_to_utf8 :: (in: *u8, out: *u8, in_buf_size: int, out_buf_size: int, unused: *void = null) -> Text_Encode_Result {
    return_if_not_valid_encode(in_buf_size, out_buf_size, 4, 1);
    c := in.(*u32,force).*;
    if (c & 0x7f) == c {
        out.* = in.*;
        return {4, 1, 0};
    } else if (c & 0x07_ff) == c {
        return_if_not_valid_encode(in_buf_size, out_buf_size, 4, 2);
        out[0] = (0xc0).(u8) | ((c & 0x07_c0) >> 6 ).(u8);
        out[1] = (0x80).(u8) | ( c & 0x00_3f       ).(u8);
        return {4, 2, 0};
    } else if (c & 0xff_ff) == c {
        return_if_not_valid_encode(in_buf_size, out_buf_size, 4, 3);
        out[0] = (0xe0).(u8) | ((c & 0xf0_00) >> 12).(u8);
        out[1] = (0x80).(u8) | ((c & 0x0f_c0) >>  6).(u8);
        out[2] = (0x80).(u8) | ( c & 0x00_3f       ).(u8);
        return {4, 3, 0};
    } else {
        if (c & 0xff_e0_00_00) != 0 {
            // only support code points representable with 4 bytes in utf8
            return {0, 0, .UNSUPPORTED_UTF8_CODE_POINT_SIZE};
        }
        return_if_not_valid_encode(in_buf_size, out_buf_size, 4, 4);
        out[0] = (0xf0).(u8) | ((c & 0x1c_00_00) >> 18).(u8);
        out[1] = (0x80).(u8) | ((c & 0x03_f0_00) >> 12).(u8);
        out[2] = (0x80).(u8) | ((c & 0x00_0f_c0) >>  6).(u8);
        out[3] = (0x80).(u8) | ( c & 0x00_00_3f       ).(u8);
        return {4, 4, 0};
    }
}

utf32_to_utf16 :: (in: *u8, out: *u8, in_buf_size: int, out_buf_size: int, unused: *void = null) -> Text_Encode_Result {
    in_utf32 := in.(*u32,force);
    out_utf16 := out.(*u16,force);
    return_if_not_valid_encode(in_buf_size, out_buf_size, 4, 2);
    if in_utf32.* > U16_MAX {
        if in_utf32.* > 0x10ffff {
            return {4, 4, .IMPOSSIBLE_TRANSLATION_OR_MALFORMED_INPUT};
        }
        return_if_not_valid_encode(in_buf_size, out_buf_size, 4, 4);
        utf32_20_bit := in_utf32.* - 0x1_00_00;
        out_utf16[0] = (((utf32_20_bit & UTF16_HIGH_MASK) >> 10) + UTF16_HIGH_SURROGATE_MIN).(u16); // high surrogate
        out_utf16[1] = ((utf32_20_bit & UTF16_LOW_MASK) + UTF16_LOW_SURROGATE_MIN).(u16); // low surrogate
        return {4, 4, 0};
    } else {
        // this range is reserved for utf16 encoding. invalid range for a code point.
        if in_utf32.* >= UTF16_HIGH_SURROGATE_MIN && in_utf32.* <= UTF16_LOW_SURROGATE_MAX {
            return {4, 2, .MALFORMED_INPUT};
        }
        out_utf16.* = xx in_utf32.*;
        return {4, 2, 0};
    }
}

// -----------------------------------------------------------------------------------

return_if_not_valid_encode :: (in_buf_size: int, out_buf_size: int, read_size: int, write_size: int) #expand {
    if in_buf_size < read_size {
        `return {read_size, write_size, Text_Encode_Status.TRUNCATED_BYTES_IN_INPUT};
    }
    if out_buf_size < write_size {
        `return {read_size, write_size, Text_Encode_Status.OUTPUT_BUFFER_IMPROPERLY_SIZED_BY_SYSTEM};
    }
}

return_if_invalid_utf8_trailing_byte :: (b: u8, read_size: int, write_size: int) #expand {
    if !is_valid_utf8_trailing_byte(b) {
        `return {read_size, write_size, Text_Encode_Status.INVALID_UTF8_TRAILING_BYTES};
    }
}

is_valid_utf8_trailing_byte :: inline (b: u8) -> bool {
    return (b & 0xc0) == 0x80;
}

UTF16_HIGH_SURROGATE_MIN : u32 : 0xd800;
UTF16_HIGH_SURROGATE_MAX : u32 : 0xdbff;
UTF16_LOW_SURROGATE_MIN  : u32 : 0xdc00;
UTF16_LOW_SURROGATE_MAX  : u32 : 0xdfff;
UTF16_HIGH_MASK          : u32 : #run (0x3ff << 10).(u32);
UTF16_LOW_MASK           : u32 : #run (0x3ff).(u32);

// -----------------------------------------------------------------------------------

#scope_module


U16_MAX : u16 : 0xffff;

Utf16_Word :: enum u8 {
    BASIC_MULTILINGUAL_PLANE;
    HIGH_SURROGATE;
    LOW_SURROGATE;
}

// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.
