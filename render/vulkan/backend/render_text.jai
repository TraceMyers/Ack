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

// loads most ttf and some otf font files.
load_truetype_font_impl :: (font: *Font, fonts_relative_path: string) -> bool {
    auto_release_temp();

    engine_log("loading font %", fonts_relative_path, flags=.VERBOSE_ONLY);

    path, success := build_path_string(engine.project_info.fonts_path, fonts_relative_path);
    if !success {
        render_error("failed to navigate to path %/% to load font", engine.project_info.fonts_path, fonts_relative_path);
        return false;
    }

    font_data:, success = read_entire_file(path,, temp);
    if !success {
        engine_error("failed to read file %", path);
        return false;
    }

    font.path = copy_string(fonts_relative_path);

    s: Serializer;
    initialize(*s, .READ, as_string(font_data), reverse_primitive_byte_order=true);

    // file header
    sfnt_version: Version;
    num_tables, search_range, entry_selector, range_shift: u16;
    ttf_try(read_ttf_number(null, *s, .FIXED,  *sfnt_version)); 
    ttf_try(read_ttf_number(null, *s, .USHORT, *num_tables));
    ttf_try(read_ttf_number(null, *s, .USHORT, *search_range));
    ttf_try(read_ttf_number(null, *s, .USHORT, *entry_selector));
    ttf_try(read_ttf_number(null, *s, .USHORT, *range_shift));

    font_type: Font_Type = .NONE;
    if version.major == 1 && version.minor == 0 && version.patch == 0 {
        font_type = .TRUETYPE;
    } else {
        version_str := to_string(sfnt_version, 2,, temp);
        if version_str == {
        case "OTTO";
            font_type = .OPENTYPE_CFF;
        case "ttcf";
            font_type = .OPENTYPE_FONT_COLLECTION;
        case "wOFF";
            font_type = .WOFF_1;
        case "wOF2";
            font_type = .WOFF_2;
        case "true"; 
            font_type = .APPLE_TRUE;
        case "typ1";
            font_type = .APPLE_TYP1;
        }
    }

    if font_type != .TRUETYPE {
        engine_error("unsupported truetype/opentype font type %", font_type);
        return false;
    }

    // ttf format goes 1. file header, 2. table directory entries, 3. table data.
    // each directory entry corresponds to a table within the table data section.
    // my directory leaves a lot of optional tables out, because don't need
    // table directories are supposed to be in a certain order, probably for
    // legacy speed reasons, but they were put in a confusing order. I reordered
    // them so they are in the right processing order.
    table_directory := Table_Directory_Entry.[
        // font header
        {tag="head", proc=read_ttf_table_head, required=true},
        // maximum profile
        {tag="maxp", proc=read_ttf_table_maxp, required=true},
        // horizontal header
        {tag="hhea", proc=read_ttf_table_hhea, required=true},
        // horizontal metrics
        {tag="hmtx", proc=read_ttf_table_hmtx, required=true},
        // character to glyph mapping
        {tag="cmap", proc=read_ttf_table_cmap, required=true},
        // index to location
        {tag="loca", proc=read_ttf_table_loca, required=true},
        // glyph data
        {tag="glyf", proc=read_ttf_table_glyf, required=true},
        // naming table
        {tag="name", proc=read_ttf_table_name, required=true},
        // OS/2 and Windows specific metrics
        {tag="OS/2", proc=read_ttf_table_OS_2, required=true},
        // PostScript information
        {tag="post", proc=read_ttf_table_post, required=true},
        // kerning
        {tag="kern", proc=read_ttf_table_kern, required=false},
        // also kerning?
        {tag="GPOS", proc=read_ttf_table_GPOS, required=false},
    ];

    tag: [4]u8;
    tag_str := as_string(tag);
    dummy_entry: Table_Directory_Entry;

    for 0..num_tables-1 {
        ttf_try(read_ttf_number(null, *s, .TAG,   *tag));
        ttf_try(read_ttf_number(null, *s, .ULONG, *dummy_entry.checksum));
        ttf_try(read_ttf_number(null, *s, .ULONG, *dummy_entry.offset));
        ttf_try(read_ttf_number(null, *s, .ULONG, *dummy_entry.length));

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

                table_data := array_view(as_array(font_data, u8), table.offset, table.length);
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
        
        table_data := array_view(as_array(font_data, u8), table.offset, table.length);
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
    version: Font_Type;
    header: Font_Header;
    profile: Font_Maximum_Profile;
    horizontal_header: Font_Horizontal_Header;
    horizontal_metrics: Font_Horizontal_Metrics;
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

Font_Type :: enum {
    NONE;
    TRUETYPE;
    OPENTYPE_CFF;
    OPENTYPE_FONT_COLLECTION;
    WOFF_1;
    WOFF_2;
    APPLE_TRUE;
    APPLE_TYP1;
}

Font_Number :: enum u8 {
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

Font_Header :: struct {
    table_version: Version;
    font_revision: Version;
    checksum_adjustment: u32;
    magic_number: u32;
    flags: enum_flags u16 {
        Y_ZERO_BASELINE;
        X_ZERO_SIDEBEARING;
        INSTRUCTIONS_MAY_DEPEND_ON_POINT_SIZE;
        FORCE_PPEM_TO_USE_INTEGER_SCALARS;
        INSTRUCTIONS_MAY_ALTER_ADVANCE_WIDTH;
    };
    units_per_em: u16; // 16 to 16834
    created: s64;
    modified: s64;
    x_min: float32;
    y_min: float32;
    x_max: float32;
    y_max: float32;
    mac_style: enum_flags u16 {
        BOLD;
        ITALIC;
    };
    smallest_readable_size_in_pixels: u16;
    font_direction_hint: enum s16 {
        FULLY_MIXED_DIRECTIONAL_GLYPHS  :: 0;
        STRONGLY_LEFT_TO_RIGHT          :: 1;
        LEFT_TO_RIGHT_WITH_NEUTRALS     :: 2;
        STRONGLY_RIGHT_TO_LEFT          :: -1;
        RIGHT_TO_LEFT_WITH_NEUTRALS     :: -2;
    };
    index_to_loc_format: enum s16 {
        SHORT;
        LONG;
    };
    glyph_data_format: s16;
}

Font_Maximum_Profile :: struct {
    table_version: Version;
    num_glyphs: u16;
    max_points: u16;
    max_contours: u16;
    max_composite_points: u16;
    max_composite_contours: u16;
    max_zones: u16;
    max_twilight_points: u16;
    max_storage: u16;
    max_function_defs: u16;
    max_instruction_defs: u16;
    max_stack_elements: u16;
    max_size_of_instructions: u16;
    max_component_elements: u16;
    max_component_depth: u16;
}

Font_Horizontal_Header :: struct {
    table_version: Version;
    ascender: float32;
    descender: float32;
    line_gap: float32;
    advance_width_max: float32;
    min_left_side_bearing: float32;
    min_right_side_bearing: float32;
    x_max_extent: float32;
    caret_slope_rise: s16;
    caret_slope_run: s16;
    reserved: [5]u16; 
    metric_data_format: s16;
    number_of_hmetrics: u16;
}

Font_Horizontal_Metrics :: struct {
    metrics: []Horizontal_Metric;
    left_side_bearing: []float32;
}

Horizontal_Metric :: struct {
    advance_width: float32;
    lsb: float32;
}

read_ttf_table_head :: (table_data: []u8, lf: *Loading_Font) -> bool {
    s: Serializer;
    initialize(*s, .READ, as_string(table_data), true);

    ttf_try(read(lf, *s, .FIXED,        *lf.header.table_version));
    ttf_try(read(lf, *s, .FIXED,        *lf.header.font_revision));
    ttf_try(read(lf, *s, .ULONG,        *lf.header.checksum_adjustment));
    ttf_try(read(lf, *s, .ULONG,        *lf.header.magic_number));
    ttf_try(read(lf, *s, .USHORT,       *lf.header.flags));
    ttf_try(read(lf, *s, .USHORT,       *lf.header.units_per_em));
    ttf_try(read(lf, *s, .LONGDATETIME, *lf.header.created));
    ttf_try(read(lf, *s, .LONGDATETIME, *lf.header.modified));
    ttf_try(read(lf, *s, .FWORD,        *lf.header.x_min));
    ttf_try(read(lf, *s, .FWORD,        *lf.header.y_min));
    ttf_try(read(lf, *s, .FWORD,        *lf.header.x_max));
    ttf_try(read(lf, *s, .FWORD,        *lf.header.y_max));
    ttf_try(read(lf, *s, .USHORT,       *lf.header.mac_style));
    ttf_try(read(lf, *s, .USHORT,       *lf.header.smallest_readable_size_in_pixels));
    ttf_try(read(lf, *s, .SHORT,        *lf.header.font_direction_hint));
    ttf_try(read(lf, *s, .SHORT,        *lf.header.index_to_loc_format));
    ttf_try(read(lf, *s, .SHORT,        *lf.header.glyph_data_format));

    ttf_try(lf.units_per_em >= 16 && lf.units_per_em <= 16384); // valid range
    ttf_try((lf.flags & 0xffe0) == 0); // required by spec

    return true;
}

read_ttf_table_maxp :: (table_data: []u8, lf: *Loading_Font) -> bool {
    s: Serializer;
    initialize(*s, .READ, as_string(table_data), true);

    ttf_try(read(lf, *s, .FIXED,  *lf.profile.table_version));
    ttf_try(read(lf, *s, .USHORT, *lf.profile.num_glyphs));
    ttf_try(read(lf, *s, .USHORT, *lf.profile.max_points));
    ttf_try(read(lf, *s, .USHORT, *lf.profile.max_contours));
    ttf_try(read(lf, *s, .USHORT, *lf.profile.max_composite_points));
    ttf_try(read(lf, *s, .USHORT, *lf.profile.max_composite_contours));
    ttf_try(read(lf, *s, .USHORT, *lf.profile.max_zones));
    ttf_try(read(lf, *s, .USHORT, *lf.profile.max_twilight_points));
    ttf_try(read(lf, *s, .USHORT, *lf.profile.max_storage));
    ttf_try(read(lf, *s, .USHORT, *lf.profile.max_function_defs));
    ttf_try(read(lf, *s, .USHORT, *lf.profile.max_instruction_defs));
    ttf_try(read(lf, *s, .USHORT, *lf.profile.max_stack_elements));
    ttf_try(read(lf, *s, .USHORT, *lf.profile.max_size_of_instructions));
    ttf_try(read(lf, *s, .USHORT, *lf.profile.max_component_elements));
    ttf_try(read(lf, *s, .USHORT, *lf.profile.max_component_depth));

    return true;
}

read_ttf_table_hhea :: (table_data: []u8, lf: *Loading_Font) -> bool {
    s: Serializer;
    initialize(*s, .READ, as_string(table_data), true);

    ttf_try(read(lf, *s, .FIXED,  *lf.horizontal_header.table_version));
    ttf_try(read(lf, *s, .FWORD,  *lf.horizontal_header.ascender));
    ttf_try(read(lf, *s, .FWORD,  *lf.horizontal_header.descender));
    ttf_try(read(lf, *s, .FWORD,  *lf.horizontal_header.line_gap));
    ttf_try(read(lf, *s, .UFWORD, *lf.horizontal_header.advance_width_max));
    ttf_try(read(lf, *s, .FWORD,  *lf.horizontal_header.min_left_side_bearing));
    ttf_try(read(lf, *s, .FWORD,  *lf.horizontal_header.min_right_side_bearing));
    ttf_try(read(lf, *s, .FWORD,  *lf.horizontal_header.x_max_extent));
    ttf_try(read(lf, *s, .SHORT,  *lf.horizontal_header.caret_slope_rise));
    ttf_try(read(lf, *s, .SHORT,  *lf.horizontal_header.caret_slope_run));
    ttf_try(read(*s,              *lf.horizontal_header.reserved));
    ttf_try(read(lf, *s, .SHORT,  *lf.horizontal_header.metric_data_format));
    ttf_try(read(lf, *s, .USHORT, *lf.horizontal_header.number_of_hmetrics));

    // out of date?
    for reserved_value : lf.horizontal_header.reserved {
        ttf_try(reserved_value == 0);
    }

    // required by spec
    ttf_try(lf.horizontal_header.number_of_hmetrics > 0);

    return true;
}

read_ttf_table_hmtx :: (table_data: []u8, lf: *Loading_Font) -> bool {
    s: Serializer;
    initialize(*s, .READ, as_string(table_data), true);

    lf.horizontal_metrics.metrics = make_static_array(Horizontal_Metric, lf.horizontal_header.number_of_hmetrics);
    for *metric : lf.horizontal_metrics.metrics {
        ttf_try(read(lf, *s, .UFWORD, *metric.advance_width));
        ttf_try(read(lf, *s, .FWORD,  *metric.lsb));
    }

    return true;
}

read_ttf_table_cmap :: (table_data: []u8, lf: *Loading_Font) -> bool {
    s: Serializer;
    initialize(*s, .READ, as_string(table_data), true);

    table_version_number, table_count: u16;

    ttf_try(read_ttf_number(lf, *s, .USHORT, *table_version_number));
    if table_version_number != 0 {
        engine_error("ttf parser does not support cmap table version number > 0. seeing version %", table_version_number, flags=.VERBOSE_ONLY);
        return false;
    }
    ttf_try(read_ttf_number(lf, *s, .USHORT, *table_count));

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

    for 0..table_count-1 {
        subtable: Subtable_Directory_Entry = ---;

        ttf_try(read_ttf_number(lf, *s, .USHORT, *subtable.platform_id));
        ttf_try(read_ttf_number(lf, *s, .USHORT, *subtable.platform_encoding_id));
        ttf_try(read_ttf_number(lf, *s, .ULONG,  *subtable.offset_to_subtable));
        subtable.expected_format = -1;

        // todo: check
        if subtable.platform_id == {
        case 0;
            if subtable.platform_encoding_id == {
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
            if subtable.platform_encoding_id == 0 {
                subtable.expected_format = 0; // or 6
                subtable.coverage = .MAC_ROMAN;
            }
        case 3;
            if subtable.platform_encoding_id == {
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
            return cast(int) a.coverage - cast(int) b.coverage; // lower enum values better
        } else return b.expected_format - a.expected_format; // 12 > 4 > 0
    });

    best_subtable := *unicode_subtables[0];

    ttf_try(best_subtale.offset_to_subtable < table_data.count);
    s.memory.data  = table_data.data + best_subtable.offset_to_subtable;
    s.memory.count = max(s.memory.count - best_subtable.offset_to_subtable, 0);
    s.head         = 0;

    format, length, version: u16 = ---;
    
    ttf_try(read_ttf_number(lf, *s, .USHORT, *format));
    ttf_try(read_ttf_number(lf, *s, .USHORT, *length));
    ttf_try(read_ttf_number(lf, *s, .USHORT, *version));

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
            table_set(*lf.code_point_to_glyph_index, cast(u32) it_index, it);
        }
    case 4;
        segment_count_x2, search_range, entry_selector, range_shift: u16 = ---;
        ttf_try(read_ttf_number(lf, *s, .USHORT, *segment_count_x2));
        ttf_try(read_ttf_number(lf, *s, .USHORT, *search_range));
        ttf_try(read_ttf_number(lf, *s, .USHORT, *entry_selector));
        ttf_try(read_ttf_number(lf, *s, .USHORT, *range_shift));
        
        segment_count := segment_count_x2 / 2;
        if segment_count == 0 {
            engine_error("invalid segment count 0 in cmap subtable format 4");
            return false;
        }

        end_codes := make_static_array(u16, segment_count,, temp);
        for 0..segment_count - 1 {
            ttf_try(read_ttf_number(lf, *s, .USHORT, *end_codes[it]));
        }

        reserved_padding: u16 = ---;
        ttf_try(read_ttf_number(lf, *s, .USHORT, *reserved_padding));

        if reserved_padding != 0 {
            engine_warning("padding in cmap subtable format 4 should be 0 but was %", reserved_padding);
        }

        start_codes := make_static_array(u16, segment_count,, temp);
        for 0..segment_count - 1 {
            ttf_try(read_ttf_number(lf, *s, .USHORT, *start_codes[it]));
        }

        id_deltas := make_static_array(u16, segment_count,, temp);
        for 0..segment_count - 1 {
            ttf_try(read_ttf_number(lf, *s, .USHORT, *id_deltas[it]));
        }

        id_offsets := make_static_array(u16, segment_count,, temp);
        for 0..segment_count - 1 {
            ttf_try(read_ttf_number(lf, *s, .USHORT, *id_offsets[it]));
        }

        remaining_size := s.memory.count - s.head;

        id_array := make_static_array(u16, remaining_size / 2,, temp);
        for 0..id_array.count - 1{
            ttf_try(read_ttf_number(lf, *s, .USHORT, *id_array[it]));
        }
        
        for segment : 0..segment_count-1 {
            start_code      := start_codes[segment];
            end_code        := end_codes[segment];
            id_delta        := id_deltas[segment];
            id_byte_offset  := id_offsets[segment];

            found_end: bool;
            if end_code == 0xffff {
                if start_code == 0xffff {
                    break;
                }
                end_code -= 1;
                found_end = true;
            } else ttf_try(segment < segment_count - 1);

            for code : start_code..end_code {
                glyph_id: u32;

                if id_byte_offset != 0 {
                    id_index_offset := cast(s64) (id_byte_offset / 2) - (segment_count - segment);
                    id_index := id_index_offset + (code - start_code);
                    ttf_try(id_index >= 0 && id_index < id_array.count);
                    glyph_id = cast(u32) id_array[id_index];
                    if glyph_id == 0 {
                        continue;
                    }
                    glyph_id = (glyph_id + id_delta) & 0xffff;
                } else {
                    glyph_id = (cast(u32) code + id_delta) & 0xffff;
                }

                table_set(*lf.code_point_to_glyph_index, cast(u32) code, glyph_id);
            }

            if found_end {
                break;
            }
        }
    case 6;
        engine_error("unicode subtable format % encountered. not supported yet.", format);
        return false;
    case 12;
        engine_error("unicode subtable format % encountered. not supported yet.", format);
        return false;
    case;
        engine_error("unicode subtable format % encountered. only 0, 4, 6, 12, 14 are supported.", format);
        return false;
    }
    
    return true;
}

read_ttf_table_glyf :: (table_data: []u8, lf: *Loading_Font) -> bool {
    return false;
}

read_ttf_table_loca :: (table_data: []u8, lf: *Loading_Font) -> bool {
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
            // and slightly bigger files. just tell people to pad with 0's or to not do it.
            byte := ifx i + it < table_data.count then table_data[i + it] else 0;
            word = (word << 8) | byte;
        }
        sum += word;
        i += 4;
    }
    return sum;
}

read_ttf_number :: (lf: *Loading_Font, s: *Serializer, $num_type: Font_Number, out: *$T) -> bool {
    success: bool;

    #if #complete num_type == {
    case .BYTE;
        #assert(T == u8);
        success = read(s, out);
    case .CHAR;
        #assert(T == s8);
        success = read(s, out);
    case .USHORT; 
        #assert(T == u16);
        success = read(s, out);
    case .OFFSET16;
        #assert(T == u16);
        success = read(s, out);
    case .SHORT;
        #assert(T == s16);
        success = read(s, out);
    case .ULONG;
        #assert(T == u32);
        success = read(s, out);
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
            bits := cast,no_check(u32) num;
            out.major = bits >> 16;
            out.minor = bits & 0xffff;
            out.patch = 0;
        }
    case .FUNIT;
        #assert(false);
    case .FWORD;
        #assert(T == float32);
        num: s16 = ---;
        success = read(s, *num);
        out.* = cast(float32) num / cast(float32) lf.header.units_per_em;
    case .UFWORD; // word, go gaters
        #assert(T == float32);
        num: u16 = ---;
        success = read(s, *num);
        out.* = cast(float32) num / cast(float32) lf.header.units_per_em;
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

