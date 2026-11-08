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

// loads most ttf and some otf font files. OpenType is a web of extensions to TrueType,
// so they overlap extensively.
// the whole-file checksum is not checked by default, because that would mean reordering and
// resumming every doubleword from head to tail in the file. every table already
// has its own checksum, and every procedure should already be checking the validity
// of memory ranges, so it is largely redundant. if the error you get back seems odd,
// try turning on run_whole_file_checksum, and that will probably tell you if the error
// is due to file corruption.
load_truetype_font_impl :: (font: *Font, fonts_relative_path: string, run_whole_file_checksum := false) -> bool {
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
    ttf_try(read(null, *s, .FIXED,  *sfnt_version)); 
    ttf_try(read(null, *s, .USHORT, *num_tables));
    ttf_try(read(null, *s, .USHORT, *search_range));
    ttf_try(read(null, *s, .USHORT, *entry_selector));
    ttf_try(read(null, *s, .USHORT, *range_shift));

    font_type: Font_Type = .NONE;
    if version.major == 1 && version.minor == 0 && version.patch == 0 {
        font_type = .TRUETYPE;
    } else {
        version_str := to_string(sfnt_version, 2,, temp);
        versino_str.count = 4;
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

    // currently only supporting TrueType, but planning to expand support, so
    // some code below this block may already be written in preparation for that.
    if font_type != .TRUETYPE {
        engine_error("unsupported truetype/opentype font type %", font_type);
        return false;
    }

    if run_whole_file_checksum {
        if font_type == .OPENTYPE_FONT_COLLECTION {
            engine_warning("run_whole_file_checksum was set to true, but font file % is a font collection, which does not make use of whole-file checksums. skipping whole-file checksum", fonts_relative_path);
        } else {
            whole_file_checksum := calculate_ttf_checksum(font_data);
            // every ttf/otf (that isn't a font collection) has a whole-file checksum
            // equalling this value due to a checksum adjustment value being written into
            // every file to make it true.
            if whole_file_checksum != 0xB1B0AFBA {
                engine_error("ttf file corruption detected via whole-file checksum. should have equalled 0xb1b0afba, but was %", whole_file_checksum);
                return false;
            }
        }
    }

    loading_font := Loading_Font.{font=font, type=font_type};

    // ttf format goes 1. file header, 2. table directory entries, 3. table data.
    // each directory entry corresponds to a table within the table data section.
    // my directory leaves a lot of optional tables out, because don't need
    // table directories are supposed to be in a certain order, probably for
    // legacy speed reasons, but they were put in a confusing order. I reordered
    // them so they are in the right processing order.
    loading_font.table_directory = Table_Directory_Entry.[
        // font header
        {tag="head", proc=read_ttf_table_head, required=true},
        // maximum profile
        {tag="maxp", proc=read_ttf_table_maxp, required=true},
        // horizontal header
        {tag="hhea", proc=read_ttf_table_hhea, required=true},
        // horizontal metrics
        {tag="hmtx", proc=read_ttf_table_hmtx, required=true},
        // character to glyph mapping
        {tag="loca", proc=read_ttf_table_loca, required=(font_type==.TRUETYPE)},
        // glyph data
        {tag="cmap", proc=read_ttf_table_cmap, required=true},
        // index to location
        {tag="glyf", proc=read_ttf_table_glyf, required=(font_type==.TRUETYPE)},
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
        ttf_try(read(null, *s, .TAG,   *tag));
        ttf_try(read(null, *s, .ULONG, *dummy_entry.checksum));
        ttf_try(read(null, *s, .ULONG, *dummy_entry.offset));
        ttf_try(read(null, *s, .ULONG, *dummy_entry.length));

        for *table : loading_font.table_directory {
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
                break;
            }
        }
    }

    // it would never make sense for it to be < 2, but putting this here
    // in case craziness happens above, the below code doesn't go into an infinite loop
    // ('for' doesn't check for max < min... at time of writing)
    engine_check(loading_font.table_directory.count >= 2);

    for ti1 : 0..loading_font.table_directory.count-2 {
        table := *loading_font.table_directory[ti1];
        for ti2 : ti1+1..loading_font.table_directory.count-1 {
            other_table := *loading_font.table_directory[ti2];
            if ranges_overlap(table.offset, table.offset + table.length, other_table.offset, other_table.offset + other_table.length) {
                engine_error("found tables with overlapping data ranges: % and %", table.*, other_table.*);
                return false;
            }
        }
    }

    init(*loading_font.code_point_to_glyph_index, 1024,, temp);
    defer deinit(*loading_font.code_point_to_glyph_index);

    for table, ti : loading_font.table_directory {
        if !table.exists_in_file {
            if table.required {
                engine_error("failed to find required table % in ttf font", table.tag);
                return false;
            }
            continue; 
        }

        table_data := array_view(as_array(font_data, u8), table.offset, table.length);

        checksum, success := calculate_ttf_checksum(table_data);

        if !success {
            return false;
        }

        if checksum != table.checksum && table.tag != "head" {
            engine_error("ttf file corruption in table %. in-file checkum %, calculated %", table.tag, table.checksum, checksum);
            return false;
        }

        if !table.proc(table_data, *loading_font) {
            engine_error("failed to load table % in ttf font", table.tag);
            return false;
        }
        
        if table.tag == "head" {
            // the header table's checksum is supposed to not include the 'checksum_adjustment' 
            // field, so that has to be treated specially.
            header_checksum := checksum - lf.header.checksum_adjustment;
            if header_checksum != table.checksum {
                engine_error("ttf file corruption in header table %. in-file checkum %, calculated %", table.tag, table.checksum, header_checksum);
                return false;
            }
        }
    }

    return true;
}

#scope_file

ttf_try :: #bake_arguments engine_run_or_return_failure(log_proc=null, flags=.VERBOSE_ONLY);

find_table :: (lf: *Loading_Font, tag: string) -> *Table_Directory_Entry {
    for *lf.table_directory {
        if it.tag == tag {
            return it;
        }
    }
    return null;
}

Loading_Font :: struct {
    using font: *Font;
    table_directory: []Table_Directory_Entry;
    type: Font_Type;
    header: Font_Header;
    profile: Font_Maximum_Profile;
    horizontal_header: Font_Horizontal_Header;
    horizontal_metrics: Font_Horizontal_Metrics;
    glyph_offsets: []u32;
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
    MAGIC_NUMBER: u32 : 0x5f0f3cf5;
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
    // grid scale (?) 16 to 16834
    units_per_em: u16; 
    // seconds since 1904-01-01 utc (macintoch epoch)
    created: s64;
    // seconds since 1904-01-01 utc (macintoch epoch)
    modified: s64;
    // 'global outline' bounding box (?)
    x_min: float32;
    y_min: float32;
    x_max: float32;
    y_max: float32;
    // legacy style flags
    mac_style: enum_flags u16 {
        BOLD;
        ITALIC;
    };
    smallest_readable_size_in_pixels: u16;
    // ignored, deprecated in 2009. newer fonts set this to 2.
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
    caret_offset: s16;
    reserved: [4]s16; 
    metric_data_format: s16;
    num_hmetrics: u16;
}

Font_Horizontal_Metrics :: struct {
    metrics: []Horizontal_Metric;
}

Horizontal_Metric :: struct {
    advance_width: float32;
    left_side_bearing: float32;
}

Glyph_Header :: struct {
    num_contours: s16;
    x_min: s16;
    y_min: s16;
    x_max: s16;
    y_max: s16;
}

Simple_Glyph :: struct {
    end_points_of_contours: []u16;
    instruction_length: u16;
    instructions: []u8;
}

read_ttf_table_head :: (table_data: []u8, lf: *Loading_Font) -> bool {
    using lf.header;

    s: Serializer;
    initialize(*s, .READ, as_string(table_data), true);

    ttf_try(read(lf, *s, .FIXED,        *table_version));
    ttf_try(read(lf, *s, .FIXED,        *font_revision));
    ttf_try(read(lf, *s, .ULONG,        *checksum_adjustment));
    ttf_try(read(lf, *s, .ULONG,        *magic_number));
    ttf_try(read(lf, *s, .USHORT,       *flags));
    ttf_try(read(lf, *s, .USHORT,       *units_per_em));
    ttf_try(read(lf, *s, .LONGDATETIME, *created));
    ttf_try(read(lf, *s, .LONGDATETIME, *modified));
    ttf_try(read(lf, *s, .FWORD,        *x_min));
    ttf_try(read(lf, *s, .FWORD,        *y_min));
    ttf_try(read(lf, *s, .FWORD,        *x_max));
    ttf_try(read(lf, *s, .FWORD,        *y_max));
    ttf_try(read(lf, *s, .USHORT,       *mac_style));
    ttf_try(read(lf, *s, .USHORT,       *smallest_readable_size_in_pixels));
    ttf_try(read(lf, *s, .SHORT,        *font_direction_hint));
    ttf_try(read(lf, *s, .SHORT,        *index_to_loc_format));
    ttf_try(read(lf, *s, .SHORT,        *glyph_data_format));

    // valid range
    ttf_try(units_per_em >= 16 && units_per_em <= 16384); 
    // all unused flags must be 0
    ttf_try((flags & 0xffe0) == 0); 
    // all header tables have same magic number
    ttf_try(magic_number == MAGIC_NUMBER);
    // only two valid values for this field
    ttf_try(index_to_loc_format >= 0 && index_to_loc_format <= 1);
    // this field was deprecated and newer files set this to 2, means nothing.
    if font_direction_hint != .LEFT_TO_RIGHT_WITH_NEUTRALS {
        engine_warning("font has direction hint % in header. this field was deprecated in the opentype specification, so it will be ignored.", flags=.VERBOSE_ONLY);
    }

    return true;
}

read_ttf_table_maxp :: (table_data: []u8, lf: *Loading_Font) -> bool {
    using lf.profile;

    s: Serializer;
    initialize(*s, .READ, as_string(table_data), true);

    ttf_try(read(lf, *s, .FIXED,  *table_version));
    ttf_try(read(lf, *s, .USHORT, *num_glyphs));

    // must be at least one glyph, required by spec
    ttf_try(num_glyphs > 0);

    if lf.type == .TRUETYPE {
        ttf_try(table_version.major == 1 && table_version.minor == 0 && table_version.patch == 0);
    } else {
        if lf.type == .OPENTYPE_CFF {
            ttf_try(table_version.major == 0 && table_version.minor == 5 && table_version.patch == 0);
            // this type does not have the remainder of the maxp table
            // but the type is unsupported rn anyway
        }
        engine_error("unsupported font type %", lf.type);
    }

    ttf_try(read(lf, *s, .USHORT, *max_points));
    ttf_try(read(lf, *s, .USHORT, *max_contours));
    ttf_try(read(lf, *s, .USHORT, *max_composite_points));
    ttf_try(read(lf, *s, .USHORT, *max_composite_contours));
    ttf_try(read(lf, *s, .USHORT, *max_zones));
    ttf_try(read(lf, *s, .USHORT, *max_twilight_points));
    ttf_try(read(lf, *s, .USHORT, *max_storage));
    ttf_try(read(lf, *s, .USHORT, *max_function_defs));
    ttf_try(read(lf, *s, .USHORT, *max_instruction_defs));
    ttf_try(read(lf, *s, .USHORT, *max_stack_elements));
    ttf_try(read(lf, *s, .USHORT, *max_size_of_instructions));
    ttf_try(read(lf, *s, .USHORT, *max_component_elements));
    ttf_try(read(lf, *s, .USHORT, *max_component_depth));

    return true;
}

read_ttf_table_hhea :: (table_data: []u8, lf: *Loading_Font) -> bool {
    using lf.horizontal_header;

    s: Serializer;
    initialize(*s, .READ, as_string(table_data), true);

    ttf_try(read(lf, *s, .FIXED,  *table_version));
    ttf_try(read(lf, *s, .FWORD,  *ascender));
    ttf_try(read(lf, *s, .FWORD,  *descender));
    ttf_try(read(lf, *s, .FWORD,  *line_gap));
    ttf_try(read(lf, *s, .UFWORD, *advance_width_max));
    ttf_try(read(lf, *s, .FWORD,  *min_left_side_bearing));
    ttf_try(read(lf, *s, .FWORD,  *min_right_side_bearing));
    ttf_try(read(lf, *s, .FWORD,  *x_max_extent));
    ttf_try(read(lf, *s, .SHORT,  *caret_slope_rise));
    ttf_try(read(lf, *s, .SHORT,  *caret_slope_run));
    ttf_try(read(lf, *s, .SHORT,  *caret_offset));
    ttf_try(read(*s,              *reserved));
    ttf_try(read(lf, *s, .SHORT,  *metric_data_format));
    ttf_try(read(lf, *s, .USHORT, *num_hmetrics));

    for reserved_value : reserved {
        ttf_try(reserved_value == 0);
    }

    // at most one horizontal metric per glyph, at least one for all. 
    ttf_try(num_hmetrics > 0 && num_hmetrics <= lf.header.num_glyphs);
    // only valid version as far as I'm aware
    ttf_try(table_version.major == 1 && table_version.minor == 0 && table_version.patch == 0);

    return true;
}

read_ttf_table_hmtx :: (table_data: []u8, lf: *Loading_Font) -> bool {
    using lf.horizontal_metrics;

    s: Serializer;
    initialize(*s, .READ, as_string(table_data), true);

    // at most one horizontal meteric per glyph.
    // if num_hmetrics < num_glyphs, the final hmetric repeats for all remaining glyphs.
    // there is always exactly one left side bearing per glyph.
    metrics = make_static_array(Horizontal_Metric, lf.header.num_glyphs);
    for *metric : metrics {
        if it_index < lf.horizontal_header.num_hmetrics {
            ttf_try(read(lf, *s, .UFWORD, *metric.advance_width));
        } else {
            metric.advance_width = metrics[lf.horizontal_header.num_hmetrics-1].advance_width;
        }
        ttf_try(read(lf, *s, .FWORD,  *metric.left_side_bearing));
    }

    return true;
}

read_ttf_table_loca :: (table_data: []u8, lf: *Loading_Font) -> bool {
    s: Serializer;
    initialize(*s, .READ, as_string(table_data), true);
    
    // inclusive range on purpose. last loca value is the end of the last glyph

    lf.glyph_offsets = make_static_array(u32, lf.header.num_glyphs+1);

    glyf_table := find_table(lf, "glyf");
    ttf_try(glyf_table != null);

    prev_value: u32;
    for 0..lf.header.num_glyphs {
        offset := *lf.glyph_offsets[it];
        if lf.header.index_to_loc_format == .SHORT {
            ttf_try(read(lf, *s, .USHORT, offset));
            lf.glyph_offsets[it] *= 2;
        } else { // .LONG
            ttf_try(read(lf, *s, .ULONG, offset));
        }
        if it > 0 {
            ttf_try(offset.* >= lf.glyph_offsets[it-1]);
        }
        ttf_try(offset.* <= glyf_table.length);
    }

    return true;
}

read_ttf_table_cmap :: (table_data: []u8, lf: *Loading_Font) -> bool {
    s: Serializer;
    initialize(*s, .READ, as_string(table_data), true);

    table_version_number, table_count: u16;

    ttf_try(read(lf, *s, .USHORT, *table_version_number));
    if table_version_number != 0 {
        engine_error("ttf parser does not support cmap table version number > 0. seeing version %", table_version_number, flags=.VERBOSE_ONLY);
        return false;
    }
    ttf_try(read(lf, *s, .USHORT, *table_count));

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

        ttf_try(read(lf, *s, .USHORT, *subtable.platform_id));
        ttf_try(read(lf, *s, .USHORT, *subtable.platform_encoding_id));
        ttf_try(read(lf, *s, .ULONG,  *subtable.offset_to_subtable));
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

    ttf_try(best_subtable.offset_to_subtable < table_data.count);
    s.memory.data  = table_data.data + best_subtable.offset_to_subtable;
    s.memory.count = max(s.memory.count - best_subtable.offset_to_subtable, 0);
    s.head         = 0;

    format, length, version: u16 = ---;
    
    ttf_try(read(lf, *s, .USHORT, *format));

    if format != best_subtable.expected_format {
        engine_warning("format in subtable doesn't match expected format in cmap subtable header % but maybe it's because I'm a dingus.", format, fmt_verbose(best_subtable.*));
    }

    try_set_subtable_length :: (s: *Serializer, length: u32) #expand {
        if length > s.memory.count {
            engine_error("cmap subtable length % greater than remaining byte count %", length, s.memory.count);
            `return false;
        }
        s.memory.count = length;
    }

    if format == {
    case 0;
        ttf_try(read(lf, *s, .USHORT, *length));
        try_set_subtable_length(*s, length);
        ttf_try(read(lf, *s, .USHORT, *version));

        glyph_id_array: [256]u8 = ---;
        ttf_try(read_bytes(*s, glyph_id_array.data, 256));
        for glyph_id : glyph_id_array {
            ttf_try(glyph_id < lf.header.num_glyphs);
            table_set(*lf.code_point_to_glyph_index, cast(u32) it_index, glyph_id);
        }
    case 4;
        ttf_try(read(lf, *s, .USHORT, *length));
        try_set_subtable_length(*s, length);
        ttf_try(read(lf, *s, .USHORT, *version));

        segment_count_x2, search_range, entry_selector, range_shift: u16 = ---;
        ttf_try(read(lf, *s, .USHORT, *segment_count_x2));
        ttf_try(read(lf, *s, .USHORT, *search_range));
        ttf_try(read(lf, *s, .USHORT, *entry_selector));
        ttf_try(read(lf, *s, .USHORT, *range_shift));
        
        segment_count := segment_count_x2 / 2;
        if segment_count == 0 {
            engine_error("invalid segment count 0 in cmap subtable format 4");
            return false;
        }

        end_codes := make_static_array(u16, segment_count,, temp);
        for 0..segment_count - 1 {
            ttf_try(read(lf, *s, .USHORT, *end_codes[it]));
        }
        ttf_try(end_codes[end_codes.count-1] == 0xffff);

        reserved_padding: u16 = ---;
        ttf_try(read(lf, *s, .USHORT, *reserved_padding));

        if reserved_padding != 0 {
            engine_warning("padding in cmap subtable format 4 should be 0 but was %", reserved_padding);
        }

        start_codes := make_static_array(u16, segment_count,, temp);
        for 0..segment_count - 1 {
            ttf_try(read(lf, *s, .USHORT, *start_codes[it]));
        }
        ttf_try(start_codes[start_codes.count-1] == 0xffff);

        id_deltas := make_static_array(u16, segment_count,, temp);
        for 0..segment_count - 1 {
            ttf_try(read(lf, *s, .USHORT, *id_deltas[it]));
        }

        id_offsets := make_static_array(u16, segment_count,, temp);
        for 0..segment_count - 1 {
            ttf_try(read(lf, *s, .USHORT, *id_offsets[it]));
        }

        remaining_size := s.memory.count - s.head;

        id_array := make_static_array(u16, remaining_size / 2,, temp);
        for 0..id_array.count - 1{
            ttf_try(read(lf, *s, .USHORT, *id_array[it]));
        }
        
        for segment : 0..segment_count-2 {
            start_code      := start_codes[segment];
            end_code        := end_codes[segment];
            id_delta        := id_deltas[segment];
            id_byte_offset  := id_offsets[segment];

            ttf_try(start_code < end_code);
            ttf_try(end_code < 0xffff);

            for code_point : start_code..end_code {
                glyph_id: u32;

                if id_byte_offset != 0 {
                    id_index_offset := cast(s64) (id_byte_offset / 2) - (segment_count - segment);
                    id_index := id_index_offset + (code_point - start_code);
                    ttf_try(id_index >= 0 && id_index < id_array.count);
                    glyph_id = cast(u32) id_array[id_index];
                    if glyph_id == 0 {
                        continue;
                    }
                    glyph_id = (glyph_id + id_delta) & 0xffff;
                } else {
                    glyph_id = (cast(u32) code_point + id_delta) & 0xffff;
                }

                ttf_try(glyph_id < lf.header.num_glyphs);
                table_set(*lf.code_point_to_glyph_index, cast(u32) code_point, glyph_id);
            }
        }
    case 12;
        reserved: u16 = ---;
        length, language, num_groups: u32 = ---;
        ttf_try(read(lf, *s, .USHORT, *reserved));
        ttf_try(reserved == 0);
        ttf_try(read(lf, *s, .ULONG,  *length);
        try_set_subtable_length(*s, length);
        ttf_try(read(lf, *s, .ULONG,  *language);
        ttf_try(read(lf, *s, .ULONG,  *num_groups);
        ttf_try(num_groups > 0);
        
        prev_start_code, prev_end_code: u32 = ---;
        for 0..num_groups-1 {
            start_code, end_code, start_glyph_id: u32 = ---;
            ttf_try(read(lf, *s, .ULONG, *start_code));
            ttf_try(read(lf, *s, .ULONG, *end_code));
            ttf_try(read(lf, *s, .ULONG, *start_glyph_id));

            ttf_try(start_code <= end_code);
            if it > 0 {
                ttf_try(start_code > prev_end_code);
            }

            for code_point : start_code..end_code {
                glyph_id := cast(s64) start_glyph_id + (cast(s64) code_point - start_code);
                ttf_try(glyph_id >= 0 && glyph_id < lf.header.num_glyphs);
                table_set(*lf.code_point_to_glyph_index, code_point, glyph_id);
            }

            prev_start_code, prev_end_code = start_code, end_code;
        }
    case;
        engine_error("unicode subtable format % encountered. only 0, 4, 6, 12, 14 are supported.", format);
        return false;
    }
    
    return true;
}

read_ttf_table_glyf :: (table_data: []u8, lf: *Loading_Font) -> bool {
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

calculate_ttf_checksum :: (file_data: []u8) -> u32, bool {
    i: int;
    sum: u32;
    while i < file_data.count {
        byte1, byte2, byte3, byte4: u32 = ---;
        // big-endian to little-endian, accounting for padding at the end of the data
        remaining_count := file_data.count - i;
        if remaining_count >= 4 {
            byte4 = file_data[i+0];
            byte3 = file_data[i+1];
            byte2 = file_data[i+2];
            byte1 = file_data[i+3];
        } else if remaining_count == 3 {
            byte4 = 0;
            byte3 = file_data[i+0];
            byte2 = file_data[i+1];
            byte1 = file_data[i+2];
        } else if remaining_count == 2 {
            byte4 = 0;
            byte3 = 0;
            byte2 = file_data[i+0];
            byte1 = file_data[i+1];
        } else {
            byte4 = 0;
            byte3 = 0;
            byte2 = 0;
            byte1 = file_data[i+0];
        }
        sum += (byte4 << 24) | (byte3 << 16) | (byte2 << 8) | byte1;
        i += 4;
    }
    return sum;
}

read :: (lf: *Loading_Font, s: *Serializer, $num_type: Font_Number, out: *$T) -> bool {
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

// converts major,minor,patch little-endian u32's into a lowest-order-byte-first 
// string. optional number of bytes per field (e.g. 2 bytes per field gets the 2
// lowest order bytes of each field and returns a string of length 6).
// this was made generally but I'm only using it for this file so I just moved it here.
// it can be moved out if it ends up being generally useful.
// example usage
// v: Version = {1, 2, 0}; -> 00000001, 00000002, a9876543
// s := to_string(v, 2);   -> "\x01\x00\x02\x00\x43\x65"
to_string :: (version: Version, $bytes_per_field := 4) -> string {
    #assert(bytes_per_field >= 1 && bytes_per_field <= 4);
    bytes: [bytes_per_field * 3]u8;
    for field : 0..2 {
        for b : 0..bytes_per_field-1 {
            bytes[field*bytes_per_field+b] = version.bytes[field*4+bytes_per_field-(b+1)];
        }
    }
    str := as_string(bytes);
    return copy_string(str);
}

