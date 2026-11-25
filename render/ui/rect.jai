Rect_Anchor :: enum u8 {
    UPPER_LEFT;
    UPPER_RIGHT;
    LOWER_RIGHT;
    LOWER_LEFT;
    CENTER;
    TOP;
    RIGHT;
    LEFT;
    BOTTOM;
}

DEFAULT_RECT_ANCHORS :: Vector2.[
    {0.0, 0.0},
    {1.0, 0.0},
    {1.0, 1.0},
    {0.0, 1.0},
    {0.5, 0.5},
    {0.5, 0.0},
    {1.0, 0.5},
    {0.0, 0.5},
    {0.5, 1.0}
];

Rect :: struct {
    using upper_left: Vector2; 
    dimensions: Vector2;
    padding: [4]float;

    #overlay(padding[0])        padding_left:   float;
    #overlay(padding[1])        padding_top:    float;
    #overlay(padding[2])        padding_right:  float;
    #overlay(padding[3])        padding_bottom: float;
    #overlay(dimensions.x)      width: float;
    #overlay(dimensions.y)      height: float;
}

Composite_Rect_Args :: struct {
    _anchor:    Vector2;
    _pivot:     Vector2;
    dims:       Rect_Vector;
    offset:     Vector2;
    padding:    [4]float;
}

Rect_Vector :: struct {
    using vector: Vector2;
    type: enum { PIXEL; NORMAL; };
}

anchor :: inline (_anchor: Rect_Anchor) -> Vector2 {
    return DEFAULT_RECT_ANCHORS[_anchor];
}
pivot :: anchor;

pad :: (left := 0.0, top := 0.0, right := 0.0, bottom := 0.0) -> [4]float #expand {
    return .[left, top, right, bottom];
}

all_pad :: (value := 0.0) -> [4]float #expand {
    return .[value, value, value, value];
}

get_rect_high_water_mark :: () -> int {
    top_rect();
    return engine.renderer.ui.rect_stack.count - 1;
}

set_rect_high_water_mark :: (i: int) {
    engine_check(i >= 0 && i < engine.renderer.ui.rect_stack.count);
    engine.renderer.ui.rect_stack.count = i + 1;
}

auto_reset_rect_hwm :: () #expand {
    hwm := get_rect_high_water_mark();
    defer `set_rect_high_water_mark(hwm);
}

push_rect :: (_anchor: Vector2, _pivot: Vector2, dims: Rect_Vector, offset := Vector2.{}, padding := float.[0,0,0,0]) -> Rect {
    using engine.renderer.ui;

    parent := top_rect();
    anchored_position, parent_padded_ul, parent_padded_dims := apply_anchor(parent, _anchor);
    parent_padded_lr := parent_padded_ul + parent_padded_dims;

    anchored_position += offset;

    // determine how much space there is to expand in each dimension depending in the
    // pivot & anchor (e.g. pivot & anchor in center => expand equally in all directions)
    max_dims := Vector2.{
        // min of space right, space left = maximum width
        min(safe_div(parent_padded_lr.x  - anchored_position.x, 1 - _pivot.x, true), // space right
            safe_div(anchored_position.x - parent_padded_ul.x,  _pivot.x,     true)), // space left
        // min of space top, space bot = maximum height
        min(safe_div(parent_padded_lr.y  - anchored_position.y, 1 - _pivot.y, true), // space below
            safe_div(anchored_position.y - parent_padded_ul.y,  _pivot.y,     true)) // space above
    };

    denorm_dims: Vector2 = ---;
    if #complete dims.type == {
    case .PIXEL;
        denorm_dims = dims.vector;
    case .NORMAL;
        denorm_dims = dims.vector * parent_padded_dims;
    }

    denorm_dims = min(denorm_dims, max_dims);
    upper_left := anchored_position - _pivot * denorm_dims;

    new_rect := Rect.{upper_left, denorm_dims, padding};
    array_add(*rect_stack, new_rect);

    return new_rect;
}

// push a stack of rects at once, the final rect's dimensions being passed separately
// each former rect will resize to fit its child. in other words, the final
// rect has a fixed size and the rest are dynamically sized.
push_composite_rect :: (last_rect_dimensions: Vector2, arg_stack: ..Dynamic_Rect_Args) -> Rect {
    engine_check(arg_stack.count > 0);
    engine_check(arg_stack[arg_stack.count-1].dims.type == .PIXEL);

    if arg_stack.count == 1 {
        using arg_stack[0];
        return push_rect(_anchor, _pivot, dims, offset, padding);     
    }

    auto_release_temp();
    push_stack := array_copy(arg_stack,, temp);

    for < 0..arg_stack.count-2 {
        child  := push_stack[it+1];
        parent := *push_stack[it];

        parent_inner_x := max(
            safe_div((1-child._pivot.x) * child.dims.x + child.offset.x, 1-child._anchor.x, false),
            safe_div(   child._pivot.x  * child.dims.x - child.offset.x, child._anchor.x,   false)
        );
        parent_inner_y := max(
            safe_div((1-child._pivot.y) * child.dims.y + child.offset.y, 1-child._anchor.y, false),
            safe_div(   child._pivot.y  * child.dims.y - child.offset.y, child._anchor.y,   false)
        );

        parent.dims    = {{parent_inner_x, parent_inner_y}, .PIXEL};
        parent.dims.x += parent.padding[0] + parent.padding[2];
        parent.dims.y += parent.padding[1] + parent.padding[3];
    }

    for push_stack {
        push_rect(it._anchor, it._pivot, it.dims, it.offset, it.padding);
    }

    return top_rect();
}

// pops the top rect and returns the new top rect
// viewport rect if 'empty'
pop_rect :: (pop_count := 1) -> Rect {
    for 0..pop_count-1 {
        if engine.renderer.ui.rect_stack.count > 1 {
            engine.renderer.ui.rect_stack.count -= 1;
        }
    }
    return top_rect();
}

// relative_position_from_top is the positional difference from the top one.
// so, -1 is 1 back from the top, -2 is 2 back, and so on. any positive value is illegal.
// using negative numbers for readability.
top_rect :: (relative_position_from_top := 0) -> Rect {
    using engine.renderer.ui;

    if rect_stack.count == 0 {
        viewport := get_window_viewport();
        array_add(*rect_stack, {dimensions=viewport});
    }
    // bounds check happens during indexing, which is why no engine_check is necessary
    return rect_stack[rect_stack.count - 1 + relative_position_from_top];
}

bottom_rect :: (relative_position_from_bottom := 0) -> Rect {
    using engine.renderer.ui;

    if rect_stack.count == 0 {
        viewport := get_window_viewport();
        array_add(*rect_stack, {dimensions=viewport});
    }
    // bounds check happens during indexing, which is why no engine_check is necessary
    return rect_stack[relative_position_from_bottom];
}

apply_anchor :: (rect: Rect, _anchor: Vector2) -> anchored_upper_left: Vector2, rect_padded_ul: Vector2, rect_padded_dims: Vector2 {
    padded_ul, padded_dims := apply_padding(rect);
    padded_lr              := padded_ul + padded_dims;
    anchored_position      := padded_ul + _anchor * padded_dims;
    return anchored_position, padded_ul, padded_dims;
}

apply_padding :: (rect: Rect) -> upper_left: Vector2, dimensions: Vector2 {
    padded_ul    := rect.upper_left + Vector2.{rect.padding_left, rect.padding_top};
    padded_dims  := rect.dimensions;
    padded_dims.x = max(padded_dims.x - (rect.padding_left + rect.padding_right),  0.0);
    padded_dims.y = max(padded_dims.y - (rect.padding_top  + rect.padding_bottom), 0.0);
    return padded_ul, padded_dims;
}

#scope_file

safe_div :: (dividend: float, divisor: float, $prefer_infinity: bool) -> float {
    #if !prefer_infinity {
        if dividend <= 0 then return 0;
    }
    if divisor  <= 0 then return FLOAT32_INFINITY;
    return max(dividend, 0) / divisor;
}

#assert(enum_highest_value(Rect_Anchor) + 1 == DEFAULT_RECT_ANCHORS.count);
