Font :: struct {
    path: string;
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

