#load "rect.jai";
#load "color_rect.jai";

UI_Style :: struct {
    rect_color: Color4f;
    rect_rounding: float;
    rect_padding: [4]float;
}

UI_Style_Memory :: struct {
    offset: u16;
    size:   u16;
    bytes:  [16]u8;
}

// style memories type-strip and just store plain bytes when style vars are pushed.
// this checks to make sure that style memories are always large enough to contain
// a style push.
#run {
    for member : (cast(*Type_Info_Struct) type_info(UI_Style)).members {
        assert(member.type.runtime_size <= UI_Style_Memory.bytes.count);
    }
}

UI :: struct {
    rect_stack: [..]Rect;
    resize_rect_stack: [..]Push_Rect_Args;
    style: UI_Style;
    style_memories: [..]UI_Style_Memory;
}

push_ui_style :: ($name: string, value: $T) {
    using engine.renderer.ui;

    offset, size :: #run -> u16, u16 {
        for member : (cast(*Type_Info_Struct) type_info(UI_Style)).members {
            if member.name == name {
                assert(member.type == type_info(T), "value type % doesn't match expected type % for var named %", T, (cast(*Type) *member.type).*, member.name);
                return xx member.offset_in_bytes, xx member.type.runtime_size;
            }
        }
        assert(false, "failed to find field %: % in UI_Style", name, T);
        return 0, 0;
    };

    memory := array_add(*style_memories);
    memory.offset = offset;
    memory.size   = size;
    memcpy(memory.bytes.data, (cast(*u8) *style) + offset, size);
    memcpy((cast(*u8) *style) + offset, cast(*u8) *value, size);
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
    resize_rect_stack.count = 0;
    // i think it's ok to have a style memory stack with stuff in it at the top of the frame,
    // but maybe just check it's not leaking with a basic sanity check
    engine_check(style_memories.count < 3_000);
}
