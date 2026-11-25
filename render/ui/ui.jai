#load "rect.jai";
#load "color_rect.jai";

Rect_UI_Style :: struct {
    color: Color4f;
    rounding: float;
    padding: [4]float;
}

UI_Style :: struct {
    rect: Rect_UI_Style;
}

UI_Style_Memory :: struct {
    offset: u16;
    size:   u16;
    bytes:  [16]u8;
}

UI :: struct {
    rect_stack: [..]Rect;
    dynamic_rect_stack: [..]Dynamic_Rect_Args;
    style: UI_Style;
    style_memories: [..]UI_Style_Memory;
}

scope_push_ui_style :: ($path: string, value: $T) #expand {
    push_ui_style(path, value);
    `defer pop_ui_style();
}

push_ui_style :: ($path: string, value: $T) {
    #assert(size_of(T) <= UI_Style_Memory.bytes.count);

    using engine.renderer.ui;

    // note the intentional limitation to keep UI_Style from becoming deep:
    // paths to fields can be no deeper than two steps beyond ui.style, e.g. ui.style.rect.color;
    offset :: #run find_field_offset(type_info(UI_Style), path, type_info(T), 2);
    #assert(offset >= 0);

    memory := array_add(*style_memories);
    memory.offset = offset;
    memory.size   = size_of(T);
    memcpy(memory.bytes.data, (cast(*u8) *style) + offset, size_of(T));
    memcpy((cast(*u8) *style) + offset, cast(*u8) *value, size_of(T));
}

pop_ui_style :: (pop_count := 1) {
    using engine.renderer.ui;

    if pop_count <= 0 {
        engine_warning("pop count % probably not intentional", pop_count, flags=.VERBOSE_ONLY);
        return;
    }

    for 0..pop_count-1 {
        memory := style_memories[style_memories.count-1];
        style_memories.count -= 1;
        memcpy((cast(*u8) *style) + memory.offset, memory.bytes.data, memory.size);
    }
}

flip_ui :: () {
    using engine.renderer.ui;
    rect_stack.count = 0;
    dynamic_rect_stack.count = 0;
    // i think it's ok to have a style memory stack with stuff in it at the top of the frame,
    // but maybe just check it's not leaking with a basic sanity check
    engine_check(style_memories.count < 3_000);
}
