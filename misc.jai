Index_2D :: struct {
    first:  s32;
    second: s32;
}

index_2d_to_1d :: inline (index: Index_2D, width: int) -> int {
    return index.first * width + index.second;
}

index_1d_to_2d :: inline (index: int, width: int) -> Index_2D {
    return {xx (index / width), xx (index % width)};
}

index_1d_to_2d_pow2_width :: inline (index: int, $width: int) -> Index_2D {
    shift :: #run shift_for_power_of_two_mul_or_div(width);
    return {xx (index >> shift), xx (index & (width-1))};
}

Gen_Ref :: struct {
    index: s32;
    generation: u32;
}

operator == :: (a: Gen_Ref, b: Gen_Ref) -> bool {
    return a.index == b.index && a.generation == b.generation;
}

operator == :: (a: Index_2D, b: Index_2D) -> bool {
    return a.first == b.first && a.second == b.second;
}

