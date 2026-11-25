push_ui_rect :: (_anchor: Vector2, _pivot: Vector2, dims: Rect_Vector, offset: Vector2) -> Rect {
    using engine.renderer.ui;

    if dynamic_rect_stack.count > 0 {
        // array_add(*dynamic_rect_stack, {_anchor, _pivot, dims, offset, padding, true});
        // temp_stack := dynamic_rect_stack;
        // dynamic_rect_stack.count = 0;
        // push_composite_rect(..temp_stack);

        // for 

        // return top_rect();
    }

    rect        := push_rect(_anchor, _pivot, dims, offset, style.rect.padding);
    lower_right := rect.upper_left + rect.dimensions;
    draw_quad_2d(rect.upper_left, lower_right, style.rect.color, style.rect.rounding);
    return rect;
}

push_ui_rect :: inline (_anchor: Vector2, dims: Rect_Vector, offset: Vector2) -> Rect {
    return push_ui_rect(_anchor, _anchor, dims, offset);
}

push_ui_rect :: inline (_anchor: Vector2, dims: Vector2, offset: Vector2) -> Rect {
    return push_ui_rect(_anchor, _anchor, {dims, .PIXEL}, offset);
}

push_ui_rect :: inline (_anchor: Vector2, dims: Rect_Vector) -> Rect {
    return push_ui_rect(_anchor, _anchor, dims, Vector2.{});
}

push_ui_rect :: inline (_anchor: Vector2, dims: Vector2) -> Rect {
    return push_ui_rect(_anchor, _anchor, {dims, .PIXEL}, Vector2.{});
}

Dynamic_Rect_Args :: struct {
    _anchor:    Vector2;
    _pivot:     Vector2;
    offset:     Vector2;
    draw:       bool;
    draw_style: Rect_UI_Style;
}

push_dynamic_ui_rect :: (_anchor: Vector2, _pivot: Vector2, offset: Vector2, draw := true) {
    using engine.renderer.ui;
    array_add(*dymamic_rect_stack, {_anchor, _pivot, offset, draw, style.rect});
}

push_dynamic_ui_rect :: inline (_anchor: Vector2, offset := Vector2.{}, draw := true) {
    push_dynamic_ui_rect(_anchor, _anchor, offset, draw);
}
