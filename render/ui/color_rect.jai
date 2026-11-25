push_ui_rect :: (_anchor: Vector2, _pivot: Vector2, dims: Rect_Vector, offset: Vector2) -> Rect {
    using engine.renderer.ui.style;
    
    rect        := push_rect(_anchor, _pivot, dims, offset, rect_padding);
    lower_right := rect.upper_left + rect.dimensions;
    draw_quad_2d(rect.upper_left, lower_right, rect_color, rect_rounding);
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
