Font :: struct {
    path: string;
    code_point_to_glyph: Table(u32, Glyph);
}


Glyph :: struct {

}

load_ttf_font :: (fonts_relative_path: string) -> *Font {
    using engine.renderer;

    scope_set_allocator(text.allocator);

    font_ptr := find_or_add(*text.fonts, fonts_relative_path);

    if font_ptr.* == null 
        font_ptr.* = New(Font);
        if !load_ttf_font_impl(font_ptr.*, fonts_relative_path) {
            free(font_ptr.*);
            table_remove(*text.fonts, fonts_relative_path);
            engine_error("failed to load font %" fonts_relative_path);
            return null;
        }
    }

    return font_ptr.*;
}

get_glyph :: (font: *Font, code_point: u32) -> Glyph {
    glyph := table_find(*font.code_point_to_glyph, code_point);
    if glyph == null {
        // code point 0 maps to the special glyph representing a missing character.
        glyph = table_find(*font.code_point_to_glyph, 0);
    }
    return glyph.*;
}
