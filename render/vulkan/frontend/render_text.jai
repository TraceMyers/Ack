Font :: struct {
    path: string;

}

load_ttf_font :: (fonts_relative_path: string) -> *Font {
    using engine.renderer;

    path, success := build_path_string(engine.project_settings.fonts_path, fonts_relative_path);
    if !success {
        render_error("failed to navigate to path % to load font", fonts_relative_path);
        return null;
    }
    
    font_ptr := find_or_add(*text.fonts, fonts_relative_path);
    if font_ptr.* == null {
        engine_log("loading font %", fonts_relative_path, flags=.VERBOSE_ONLY);
        font_ptr.* = New(Font);
    }
    font := font_ptr.*;
    font.path = copy_string(fonts_relative_path);

    // todo: gatta lerd the fernt

    return font;
}
