// wasn't sure where else to put this. I think other things will eventually make their way here...

num64 :: union {
    _f64: float64;
    _f32: [2]float32 = ---;
    _u64: u64        = ---;
    _s64: s64        = ---;
    _u32: [2]u32     = ---;
    _s32: [2]s32     = ---;
    _u16: [4]u16     = ---;
    _s16: [4]s16     = ---;
    _u8:  [8]u8      = ---;
    _s8:  [8]s8      = ---;
    data: *void      = ---;
}

num32 :: union {
    _f32: float32;
    _u32: u32        = ---;
    _s32: s32        = ---;
    _u16: [2]u16     = ---;
    _s16: [2]s16     = ---;
    _u8:  [4]u8      = ---;
    _s8:  [4]s8      = ---;
}

num16 :: union {
    _u16: u16;
    _s16: s16        = ---;
    _u8:  [2]u8      = ---;
    _s8:  [2]s8      = ---;
}

num8 :: union {
    _u8: u8;
    _s8: s8          = ---;
}

// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.
