Render_Text :: struct {
    fonts: Table(string, *Font);
    allocator: Allocator;
}

init_render_text :: () -> bool {
    engine_log("copying fonts from engine", flags=.VERBOSE_ONLY);

    if engine.renderer.text.allocator.proc == null {
        engine.renderer.text.allocator = context.allocator;
    }

    irt_try :: #bake_arguments engine_run_or_return_failure(flags=.VERBOSE_ONLY);

    irt_try(file_exists(engine.project_info.fonts_path));
    irt_try(maybe_copy_files_to_project(engine.project_info.fonts_path, "additional_materials/fonts", "copying fonts into project"));

    return true;
}

// great primary sournce for the ttf file format (old, not including otf):
// http://hackipedia.org/browse.cgi/File%20formats/TrueType%20font%20format/TrueType%201%2e0%20Font%20Files%20Technical%20Specification%20v1%2e66%20%281995%2d08%29/Chapter%202%20%2d%20The%20TrueType%20Font%20File%2epdf
load_ttf_font_impl :: (font: *Font, fonts_relative_path: string) -> bool {
    auto_release_temp();

    engine_log("loading font %", fonts_relative_path, flags=.VERBOSE_ONLY);

    path, success := build_path_string(engine.project_settings.fonts_path, fonts_relative_path);
    if !success {
        render_error("failed to navigate to path %/% to load font", engine.project_settings.fonts_path, fonts_relative_path);
        return false;
    }

    font_data, success := read_entire_file(path,, temp);
    if !success {
        engine_error("failed to read file %", path);
        return false;
    }

    font.path = copy_string(fonts_relative_path);

    s: Serializer;
    initialize(*s, .READ, as_string(font_data), true);

    // file header
    sfnt_version: Version;
    num_tables, search_range, entry_selector: u16;
    ttf_try(read_ttf_number(*s, .FIXED,  *sfnt_version)); // todo: how does this change things?
    ttf_try(read_ttf_number(*s, .USHORT, *num_tables));
    ttf_try(read_ttf_number(*s, .USHORT, *search_range));
    ttf_try(read_ttf_number(*s, .USHORT, *entry_selector));

    // ttf format goes 1. file header, 2. table directory entries, 3. table data.
    // each directory entry corresponds to a table within the table data section.
    // my directory leaves a lot of optional tables out. not using them, kay?
    table_directory := Table_Directory_Entry.[
        // character to glyph mapping
        {tag="cmap", proc=read_ttf_table_cmap, required=true},
        // glyph data
        {tag="glyf", proc=read_ttf_table_glyf, required=true},
        // font header
        {tag="head", proc=read_ttf_table_head, required=true},
        // horizontal header
        {tag="hhea", proc=read_ttf_table_hhea, required=true},
        // horizontal metrics
        {tag="hmtx", proc=read_ttf_table_hmtx, required=true},
        // index to location
        {tag="loca", proc=read_ttf_table_loca, required=true},
        // maximum profile
        {tag="maxp", proc=read_ttf_table_maxp, required=true},
        // naming table
        {tag="name", proc=read_ttf_table_name, required=true},
        // PostScript information
        {tag="post", proc=read_ttf_table_post, required=true},
        // OS/2 and Windows specific metrics
        {tag="OS/2", proc=read_ttf_table_OS_2, required=true},
        // kerning
        {tag="kern", proc=read_ttf_table_kern, required=false},
        // also kerning?
        {tag="GPOS", proc=read_ttf_table_GPOS, required=false},
    ];

    tag: [4]u8;
    tag_str := as_string(tag);
    dummy_entry: Table_Directory_Entry;

    for 0..num_tables-1 {
        entry := *table_directory[it];

        ttf_try(read_ttf_number(*s, .TAG,   *tag));
        ttf_try(read_ttf_number(*s, .ULONG, *dummy_entry.checksum));
        ttf_try(read_ttf_number(*s, .ULONG, *dummy_entry.offset));
        ttf_try(read_ttf_number(*s, .ULONG, *dummy_entry.length));

        for *table : table_directory {
            if table.tag == tag_str {
                if table.exists_in_file {
                    engine_warning("found multiple tables with the same tag, which is considered invalid in a ttf file. to be permissive in the hopes that it's a minor error, the duplicate table is being skipped.", flags=.VERY_VERBOSE_ONLY);
                    break;
                }

                table.checksum       = dummy_entry.checksum;
                table.offset         = dummy_entry.offset;
                table.length         = dummy_entry.length;
                table.exists_in_file = true;

                table_end := table.offset + table.length;
                if table_end > font_data.count {
                    engine_error("ttf table % is supposed to begin at % and end at %, but the file only has % bytes.", table.tag, table.offset, table_end, font_data.count);
                    return false;
                }

                table_data := array_view(font_data, table.offset, table.length);
                calculated_checksum := calculate_ttf_table_checksum(table_data);
                if calculated_checksum != table.checksum {
                    engine_error("ttf file corruption in table %. in-file checkum %, calculated %", table.tag, table.checksum, calculated_checksum);
                    return false;
                }

                break;
            }
        }
    }

    loading_font := Loading_Font.{font=font};

    init(*loading_font.code_point_to_glyph_index, 1024,, temp);
    defer deinit(*loading_font.code_point_to_glyph_index);

    for table : table_directory {
        if !table.exists_in_file {
            if table.required {
                engine_error("failed to find required table % in ttf font", table.tag);
                return false;
            }
            continue; 
        }
        
        table_data := array_view(font_data, table.offset, table.length);
        if !table.proc(table_data, *loading_font) {
            engine_error("failed to load table % in ttf font", table.tag);
            return false;
        }
    }

    return true;
}

#scope_file

ttf_try :: #bake_arguments engine_run_or_return_failure(log_proc=null, flags=.VERBOSE_ONLY);

Loading_Font :: struct {
    using font: *Font;
    code_point_to_glyph_index: Table(u32, u32);
}

Table_Directory_Entry :: struct {
    tag:      string;
    checksum: u32;
    offset:   u32;
    length:   u32;

    proc: ([]u8, *Loading_Font) -> bool;

    required: bool;
    exists_in_file: bool;
}

TTF_Number :: enum u8 {
    BYTE;
    CHAR;
    USHORT;
    SHORT;
    ULONG;
    LONG;
    FIXED;
    FUNIT;
    FWORD;
    UFWORD;
    F2DOT14;
    LONGDATETIME;
    TAG;
    OFFSET16;
    OFFSET32;
    UINT24;
}

read_ttf_table_cmap :: (table_data: []u8, lf: *Loading_Font) -> bool {
    s: Serializer;
    initialize(*s, .READ, as_string(table_data), true);

    table_version_number, table_count: u16;

    ttf_try(read_ttf_number(*s, .USHORT, *table_version_number));
    if table_version_number != 0 {
        engine_error("ttf parser does not support cmap table version number > 0. seeing version %", table_version_number, flags=.VERBOSE_ONLY);
        return false;
    }
    ttf_try(read_ttf_number(*s, .USHORT, *table_count);

    if table_count == 0 {
        engine_error("cmap table count = 0. no mappings.", flags=.VERBOSE_ONLY);
        return false;
    }

    CMAP_Coverage :: enum u32 {
        FULL_UNICODE;
        BMP_ONLY;
        BMP;
        SYMBOL_FONT;
        MAC_ROMAN;
    }

    Subtable_Directory_Entry :: struct {
        platform_id:          u16;
        platform_encoding_id: u16;
        offset_to_subtable:   u32;
        expected_format:      s32;
        coverage:             CMAP_Coverage;
    }

    unicode_subtables := make_dynamic_array(Subtable_Directory_Entry, table_count,, temp);
    unicode_subtable_index := -1;

    for 0..table_count-1 {
        subtable: Subtable_Directory_Entry = ---;

        ttf_try(read_ttf_number(*s, .USHORT, *subtable.platform_id);
        ttf_try(read_ttf_number(*s, .USHORT, *subtable.platform_encoding_id);
        ttf_try(read_ttf_number(*s, .ULONG,  *subtable.offset_to_subtable);
        subtable.expected_format = -1;

        // todo: check
        if subtable.platform_id == {
        case 0;
            if subtable.encoding_id == {
            case 0; #through;
            case 1; #through;
            case 2;
                subtable.expected_format = 4;
                subtable.coverage = .BMP;
            case 3;
                subtable.expected_format = 4;
                subtable.coverage = .BMP_ONLY;
            case 4;
                subtable.expected_format = 12;
                subtable.coverage = .FULL_UNICODE;
            }
        case 1;
            if subtable.encoding_id == 0 {
                subtable.expected_format = 0; // or 6
                subtable.coverage = .MAC_ROMAN;
            }
        case 3;
            if subtable.encoding_id == {
            case 0;
                subtable.expected_format = 4;
                subtable.coverage = .SYMBOL_FONT;
            case 1;
                subtable.expected_format = 4;
                subtable.coverage = .BMP_ONLY;
            case 10;
                subtable.expected_format = 12;
                subtable.coverage = .FULL_UNICODE;
            }
        }

        if subtable.expected_format != -1 {
            array_add(*unicode_subtables, subtable);
        }
    }

    // todo: support more? ever necessary?
    if unicode_subtables.count == 0 {
        engine_error("did not find a unicode subtable within cmap. only unicode supported.");
        return false;
    }

    quick_sort(unicode_subtables, (a: Subtable_Directory_Entry, b: Subtable_Directory_Entry) -> int {
        if a.expected_format == b.expected_format {
            return a.coverage - b.coverage; // lower enum values better
        } else return b.expected_format - a.expected_format; // 12 > 4 > 0
    });

    best_subtable := *subtables[0];

    s.memory.data  = table_data.data + best_subtable.offset_to_subtable;
    s.memory.count = max(s.memory.count - best_subtable.offset_to_subtable, 0);
    s.head         = 0;

    format, length, version: u16 = ---;
    
    ttf_try(read_ttf_number(*s, .USHORT, *format));
    ttf_try(read_ttf_number(*s, .USHORT, *length));
    ttf_try(read_ttf_number(*s, .USHORT, *version));

    if length > s.memory.count {
        engine_error("cmap subtable length % greater than remaining byte count %", length, s.memory.count);
        return false;
    }

    if format != best_subtable.expected_format {
        engine_warning("format in subtable doesn't match expected format in cmap subtable header % but maybe it's because I'm a dingus.", format, fmt_verbose(best_subtable.*));
    }

    s.memory.count = length;

    if format == {
    case 0;
        glyph_id_array: [256]u8 = ---;
        ttf_try(read_bytes(*s, glyph_id_array.data, 256));
        for glyph_id_array {
            loading_font.code_point_to_glyph_index[cast(u32) it_index] = it;
        }
    case 4;
        segment_count_x2, search_range, entry_selector, range_shift: u16 = ---;
        ttf_try(read_ttf_number(*s, .USHORT, *segment_count_x2));
        ttf_try(read_ttf_number(*s, .USHORT, *search_range));
        ttf_try(read_ttf_number(*s, .USHORT, *entry_selector));
        ttf_try(read_ttf_number(*s, .USHORT, *range_shift));
        
        segment_count := segment_count_x2 / 2;
        if segment_count == 0 {
            engine_error("invalid segment count 0 in cmap subtable format 4");
            return false;
        }

        end_codes := make_static_array(u16, segment_count,, temp);
        for 0..segment_count - 1 {
            ttf_try(read_ttf_number(*s, .USHORT, *end_codes[it]);
        }

        if end_codes[end_codes.count-1] != 0xffff {
            engine_warning("final end code in cmap subtable format 4 should be 0xffff but was %", end_codes[end_codes.count-1]);
        }

        reserved_padding: u16 = ---;
        ttf_try(read_ttf_number(*s, .USHORT, *reserved_padding));

        if reserved_padding != 0 {
            engine_warning("padding in cmap subtable format 4 should be 0 but was %", reserved_padding);
        }

        start_codes := make_static_array(u16, segment_count,, temp);
        for 0..segment_count - 1 {
            ttf_try(read_ttf_number(*s, .USHORT, *start_codes[it]));
        }

        code_deltas := make_static_array(u16, segment_count,, temp);
        for 0..segment_count - 1 {
            ttf_try(read_ttf_number(*s, .USHORT, *code_deltas[it]));
        }

        glyph_offsets := make_static_array(u16, segment_count,, temp);
        for 0..segment_count - 1 {
            ttf_try(read_ttf_number(*s, .USHORT, *glyph_offsets[it]));
        }



    case 6;

    case 12;

    case;
        engine_error("unicode subtable format % encountered. only 0, 4, 6, 12, 14 are supported.", format);
        return false;
    }
    
    return false;
}

read_ttf_table_glyf :: (table_data: []u8, lf: *Loading_Font) -> bool {
    return false;
}

read_ttf_table_head :: (table_data: []u8, lf: *Loading_Font) -> bool {
    return false;
}

read_ttf_table_hhea :: (table_data: []u8, lf: *Loading_Font) -> bool {
    return false;
}

read_ttf_table_hmtx :: (table_data: []u8, lf: *Loading_Font) -> bool {
    return false;
}

read_ttf_table_loca :: (table_data: []u8, lf: *Loading_Font) -> bool {
    return false;
}

read_ttf_table_maxp :: (table_data: []u8, lf: *Loading_Font) -> bool {
    return false;
}

read_ttf_table_name :: (table_data: []u8, lf: *Loading_Font) -> bool {
    return false;
}

read_ttf_table_post :: (table_data: []u8, lf: *Loading_Font) -> bool {
    return false;
}

read_ttf_table_OS_2 :: (table_data: []u8, lf: *Loading_Font) -> bool {
    return false;
}

read_ttf_table_kern :: (table_data: []u8, lf: *Loading_Font) -> bool {
    return false;
}

read_ttf_table_GPOS :: (table_data: []u8, lf: *Loading_Font) -> bool {
    return false;
}

calculate_ttf_table_checksum :: (table_data: []u8) -> u32 {
    sum: u32;
    i: int;
    while i < table_data.count {
        word: u32;
        for 0..3 {
            // reverse byte order with 0 padding if the table isn't padded in-file.
            // padding is encouraged but not required, which is annoying because 
            // 1. you might as well not say anything, since a good parser will pad while reading 
            // anyway and 2. probably everybody pads in-file, so you get slower parsers
            // and slightly bigger files. just tell people to pad with 0's or it's incorrect.
            byte := ifx i + it < table_data.count then table_data[i + it] else 0;
            word = (word << 8) | byte;
        }
        sum += word;
        i += 4;
    }
    return sum;
}

read_ttf_number :: (s: *Serializer, $num_type: TTF_Number, out: *$T, inv_units_per_elem: *float32 = null) -> bool {
    success: bool;

    #if #complete num_type == {
    case .BYTE;
        #assert(T == u8);
        success = read(s, out);
    case .CHAR;
        #assert(T == s8);
        success = read(s, out);
    case .USHORT; 
        #through;
    case .OFFSET16;
        #assert(T == u16);
        success = read(s, out);
    case .SHORT;
        #assert(T == s16);
        success = read(s, out);
    case .ULONG;
        #through;
    case .OFFSET32;
        #assert(T == u32);
        success = read(s, out);
    case .LONG;
        #assert(T == s32);
        success = read(s, out);
    case .FIXED;
        #assert(T == float32 || T == Version);
        num: s32 = ---;
        success = read(s, *num);
        #if T == float32 {
            out.* = xx (cast(float64) num / 65536.0);
        } else {
            out.major = (num & 0xffff0000) >> 16;
            out.minor = (num & 0x0000ffff);
            out.patch = 0;
        }
    case .FUNIT;
        #assert(false);
    case .FWORD;
        #assert(T == float32);
        engine_check(units_per_elem != null);
        num: s16 = ---;
        success = read(s, *num);
        out.* = cast(float32) num * inv_units_per_elem;
    case .UFWORD; // word, go gaters
        #assert(T == float32);
        engine_check(units_per_elem != null);
        num: u16 = ---;
        success = read(s, *num);
        out.* = cast(float32) num * inv_units_per_elem;
    case .F2DOT14;
        #assert(T == float32);
        num: s16 = ---;
        success = read(s, *num);
        out.* = cast(float32) num / 16384.0;
    case .LONGDATETIME;
        #assert(T == s64);
        success = read(s, out);
    case .TAG;
        #assert(T == [4]u8);
        success = read_bytes(s, out.data, 4);
    case .UINT24;
        #assert(T == u32);
        out.* = 0;
        out_bytes := cast,force(*u8) out;
        success = read_bytes(s, out_bytes, 3);
        // byte swap for little endian. 
        // can't read a u24 with reverse byte order because it's not a primitive type.
        out_bytes[0], out_bytes[2] = out_bytes[2], out_bytes[0];
    }

    return success;
}
