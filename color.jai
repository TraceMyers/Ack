using Default_Color_Palette :: struct {
    COLOR4F_WHITE         :: Color4f.{1,1,1,1};
    COLOR4F_BLACK         :: Color4f.{0,0,0,1};
    COLOR4F_RED           :: Color4f.{1,0,0,1};
    COLOR4F_GREEN         :: Color4f.{0,1,0,1};
    COLOR4F_BLUE          :: Color4f.{0,0,1,1};
    COLOR4F_YELLOW        :: Color4f.{1,1,0,1};
    COLOR4F_CYAN          :: Color4f.{0,1,1,1};
    COLOR4F_MAGENTA       :: Color4f.{1,0,1,1};
    COLOR4F_BRIGHT_PURPLE :: Color4f.{0.65, 0.1, 0.82, 1};
    COLOR4F_DARK_PURPLE   :: Color4f.{0.4, 0.02, 0.5, 1};
    COLOR4F_SKY_BLUE      :: #run to_color4f(0x87ceeb);
}

// generate 32 bit colors from float colors
#insert #run -> string {
    tinfo := cast(*Type_Info_Struct) type_info(Default_Color_Palette);
    builder: String_Builder;
    for member : tinfo.members {
        constant_value := cast(*Color4f) *tinfo.constant_storage[member.offset_into_constant_storage];
        _32bit_color_name := replace(member.name, "4F", "4B",, temp);
        r := alter_cast(constant_value.r, u8, true, true);
        g := alter_cast(constant_value.g, u8, true, true);
        b := alter_cast(constant_value.b, u8, true, true);
        a := alter_cast(constant_value.a, u8, true, true);
        print(*builder, "% :: Color4b.{%,%,%,%};\n", _32bit_color_name, r, g, b, a);
    }
    return builder_to_string(*builder);
};

GREY_FACTORS :: Color3f.{0.2126, 0.7152, 0.0722};

FLOAT_RGB_TYPES :: Type.[Color3f, Color4f];

HSY_Component :: enum {
    HUE; 
    SATURATION;
    LUMINANCE;
};

Color2f :: struct {
    r: float32;
    g: float32;

#overlay(r) vec2: Vector2 = ---;
#overlay(r) component: [2]float = ---;
#overlay(r) array: [2]float32 = ---;
}

Color3f :: struct {
    r: float32;
    g: float32;
    b: float32;

#overlay(r) rg: Color2f = ---;
#overlay(g) gb: Color2f = ---;
#overlay(r) using #as vector: Vector3 = ---;
#overlay(r) array: [3]float32 = ---;
}

Color4f :: struct {
    r: float32;
    g: float32;
    b: float32;
    a: float32 = 1.0;

#overlay(r) rgb: Color3f = ---;
#overlay(r) rg: Color2f = ---;
#overlay(g) gb: Color2f = ---;
#overlay(b) ba: Color2f = ---;
#overlay(r) using #as vector: Vector4 = ---;
#overlay(r) array: [4]float32 = ---;
}

Color4b :: struct {
    r: u8 #align 4; // should align to 4 bytes so this struct can be read as a u32;
    g: u8;
    b: u8;
    a: u8 = 255;

#overlay(r) bytes: [4]u8 = ---;
#overlay(r) _u32: u32 = ---;
}

Color_HSY :: struct {
    hue: float32;
    saturation := 1.0;
    // note that unlike lightness (midpoint=0.5), luminance's midpoint depends on the hue.
    luminance := 0.5;
    alpha := 1.0; // mirrors rgba's 'a', so that converting rgba -> hsy -> rgba isn't throwing away the alpha value
}

operator * :: inline (color: Color4f, scalar: float) -> Color4f #symmetric {
    debug__check_float_rgb(color4f);

    c := Color4f.{color.r * scalar, color.g * scalar, color.b * scalar, color.a};
    c.r = clamp(c.r, 0, 1);
    c.g = clamp(c.g, 0, 1);
    c.b = clamp(c.b, 0, 1);
    return c;
}

to_color4f :: inline (color3f: Color3f, alpha := 1.0) -> Color4f {
    debug__check_float_rgb(color3f);
    engine_check(.HIGH, is_norm_float(alpha));

    float_color: Color4f = ---;
    float_color.r = color3f.r;
    float_color.g = color3f.g;
    float_color.b = color3f.b;
    float_color.a = alpha;
    return float_color;
}

to_color4f :: inline (color3f: Color3f, alpha : u8 = 255) -> Color4f {
    debug__check_float_rgb(color3f);
    engine_check(.HIGH, is_norm_float(alpha));

    float_color: Color4f = ---;
    float_color.r = color3f.r;
    float_color.g = color3f.g;
    float_color.b = color3f.b;
    float_color.a = alter_cast(alpha, float, true);
    return float_color;
}

to_color4b :: inline (color4f: Color4f) -> Color4b {
    debug__check_float_rgb(color4f);

    byte_color: Color4b = ---;
    byte_color.r = alter_cast(color4f.r, u8, true);
    byte_color.b = alter_cast(color4f.b, u8, true);
    byte_color.g = alter_cast(color4f.g, u8, true);
    byte_color.a = alter_cast(color4f.a, u8, true);
    return byte_color;
}

to_color4f :: inline (color4b: Color4b) -> Color4f {
    float_color: Color4f = ---;
    float_color.r = alter_cast(color4b.r, float, true);
    float_color.g = alter_cast(color4b.g, float, true);
    float_color.b = alter_cast(color4b.b, float, true);
    float_color.a = alter_cast(color4b.a, float, true);
    return float_color;
}

to_color4b :: inline (hex_color_code: u32) -> Color4b {
    byte_color: Color4b = ---;
    byte_color.r = ((hex_color_code & 0xff0000) >> 16).(u8);
    byte_color.g = ((hex_color_code & 0x00ff00) >>  8).(u8);
    byte_color.b = ((hex_color_code & 0x0000ff) >>  0).(u8);
    byte_color.a = 255;
    return byte_color;
}

to_color4f :: inline (hex_color_code: u32) -> Color4f {
    color_4b := to_color4b(hex_color_code);
    return to_color4f(color_4b);
}

lerp :: inline (begin: Color4f, end: Color4f, t: float) -> Color4f {
    return {
        r = begin.r + (end.r - begin.r) * t,
        g = begin.g + (end.g - begin.g) * t,
        b = begin.b + (end.b - begin.b) * t,
        a = begin.a + (end.a - begin.a) * t,
    };
}

lerp_to_grey :: inline (color: $T/FLOAT_RGB_TYPES, grey_value: float, alpha: float) -> T {
    debug__check_float_rgb(color);
    engine_check(.HIGH, is_norm_float(grey_value));
    engine_check(.HIGH, is_norm_float(alpha));

    out_color := T.{
        r = lerp(color.r, grey_value, alpha),
        g = lerp(color.g, grey_value, alpha),
        b = lerp(color.b, grey_value, alpha)
    };
    #if T == Color4f then out_color.a = color.a;
    return out_color;
}

get_grey_value :: inline (color: $T/FLOAT_RGB_TYPES) -> float32 {
    debug__check_float_rgb(color);

    return GREY_FACTORS.r * color.r + GREY_FACTORS.g * color.g + GREY_FACTORS.b * color.b;
}

to_grey :: inline (color: $T/FLOAT_RGB_TYPES) -> T {
    debug__check_float_rgb(color);

    grey := get_grey_value(color);
    out_color := T.{r=grey, g=grey, b=grey};
    #if T == Color4f then out_color.a = color.a;
    return out_color;
}

lighten :: inline (color: $T/FLOAT_RGB_TYPES, alpha: float32) -> T {
    debug__check_float_rgb(color);
    engine_check(.HIGH, is_norm_float(alpha));

    return lerp_to_grey(color, 1, alpha);
}

darken :: inline (color: $T/FLOAT_RGB_TYPES, alpha: float32) -> T {
    debug__check_float_rgb(color);
    engine_check(.HIGH, is_norm_float(alpha));

    return lerp_to_grey(color, 0, alpha);
}

// HSY also doubles as HSL with these helper procedures

// 0.5 -> middle luminance of the hue
set_lightness :: (hsy: *Color_HSY, lightness := 0.5) {
    debug__check_hsy(hsy.*);
    engine_check(.HIGH, is_norm_float(lightness));

    mid_grey := get_grey_value(hue_to_rgb(hsy.hue));
    if lightness >= 0.5 {
        hsy.luminance = respace(lightness, {0.5, 1}, {mid_grey, 1});
    } else {
        hsy.luminance = respace(lightness, {0, 0.5}, {0, mid_grey});
    }
}

get_lightness :: (hsy: Color_HSY) -> float32 {
    debug__check_hsy(hsy);
    
    mid_grey := get_grey_value(hue_to_rgb(hsy.hue));
    if hsy.luminance > mid_grey {
        return respace(hsy.luminance, {mid_grey, 1}, {0.5, 1});
    } else {
        return respace(hsy.luminance, {0, mid_grey}, {0, 0.5});
    }
}

scale_saturation :: inline (color: $T/FLOAT_RGB_TYPES, scale: float32, try_preserve_aspect := HSY_Component.HUE) -> T {
    debug__check_float_rgb(color);
    engine_check(.HIGH, scale >= 0);
    engine_check(.LOW, try_preserve_aspect != .SATURATION);

    min_saturation := to_min_saturation(color);

    if scale <= 1 {
        grey_value := min_saturation.r;
        return lerp_to_grey(color, grey_value, 1-scale);
    }

    max_saturation, max_saturation_scale := to_max_saturation(color, try_preserve_aspect);

    if scale >= max_saturation_scale {
        return max_saturation;
    } else {
        norm_saturation_alpha := (scale - 1) / (max_saturation_scale - 1);
        out_color := T.{
            r = lerp(color.r, max_saturation.r, norm_saturation_alpha),
            g = lerp(color.g, max_saturation.g, norm_saturation_alpha),
            b = lerp(color.b, max_saturation.b, norm_saturation_alpha),
        };
        #if T == Color4f then out_color.a = color.a;
        return out_color;
    }
}

// the 'saturation_scale' out value would be 0, if it returned one, because saturation
// is being scaled to 0.
to_min_saturation :: to_grey;

// 'saturation_scale' is the distance from the current color to max saturation, relative
// to the distance from the min saturation to the color. e.g. if the color is equidistant
// between min and max saturation, saturation_scale would be 1.
to_max_saturation :: (color: $T/FLOAT_RGB_TYPES, try_preserve_aspect := HSY_Component.HUE) -> max_saturation: T, saturation_scale: float32 {
    debug__check_float_rgb(color);

    engine_check(.LOW, try_preserve_aspect != .SATURATION);

    min_saturation := to_min_saturation(color);
    grey_value := min_saturation.r;

    max_saturation := color;

    Color_Channel :: struct {
        input: float;
        max_saturation: *float;
        min_saturation: *float;
        grey_factor: float;
    }

    min_channel: Color_Channel;
    mid_channel: Color_Channel;
    max_channel: Color_Channel;

    r_channel := Color_Channel.{color.r, *max_saturation.r, *min_saturation.r, GREY_FACTORS.r};
    g_channel := Color_Channel.{color.g, *max_saturation.g, *min_saturation.g, GREY_FACTORS.g};
    b_channel := Color_Channel.{color.b, *max_saturation.b, *min_saturation.b, GREY_FACTORS.b};

    if color.r < color.g {
        if color.r < color.b && color.g < color.b {
            max_channel = b_channel;
            mid_channel = g_channel;
            min_channel = r_channel;
        } else {
            max_channel = g_channel;
            mid_channel = r_channel;
            min_channel = b_channel;
        }
    } else if color.g < color.b {
        if color.r > color.b {
            max_channel = r_channel;
            mid_channel = b_channel;
        } else {
            max_channel = b_channel;
            mid_channel = r_channel;
        }
        min_channel = g_channel;
    } else {
        max_channel = r_channel;
        mid_channel = g_channel;
        min_channel = b_channel;
    }

    max_channel.max_saturation.* -= min_channel.max_saturation.*;
    mid_channel.max_saturation.* -= min_channel.max_saturation.*;
    // in order for a color to hit max saturation, the lowest valued channel must be muted
    // to 0, because adding value in the third channel moves toward white, which moves
    // away from full saturation. 
    min_channel.max_saturation.* = 0;

    if max_channel.max_saturation.* <= 0 {
        return {r=1}, 1;
    }

    if try_preserve_aspect == .HUE {
        // there is always at least one channel with value 1. two channels have value 1 if the hue is
        // 50% the distance between two channels. here, we scale the max channel to 1 and mid channel to
        // a value in [0, 1]
        scale_factor := 1 / max_channel.max_saturation.*;
        mid_channel.max_saturation.* = clamp(mid_channel.max_saturation.* * scale_factor, 0, 1);
        max_channel.max_saturation.* = 1;
    } else { // .LUMINANCE
        // in attempting to preserve luminance, we are trying to keep the grey value the same.
        // doing so means maxing out the max channel and giving the remaining grey to the mid channel.
        // this only works if sufficient value exists in the channels. for dark colors, this
        // will just return only the channel with the strongest signal e.g. {r=0.2, g=0.1, b=0.05} -> {r=1}
        max_channel.max_saturation.* = 1;
        mid_channel.max_saturation.* = max((grey_value - max_channel.grey_factor) / mid_channel.grey_factor, 0);
    }

    // this procedure returns how much the channels can be scaled up until one of the 
    // channels hits its maximum, and a scale of 1 is represented by the current distance
    // from the grey value. so, 2x saturation scale would be 2x the current distance
    // from grey. 
    max_min_dist := max_channel.input - max_channel.min_saturation.*;
    mid_min_dist := mid_channel.input - mid_channel.min_saturation.*;

    max_max_dist := max_channel.max_saturation.* - max_channel.input;
    mid_max_dist := mid_channel.max_saturation.* - mid_channel.input;

    max_max_scale := abs(max_max_dist / max_min_dist);
    mid_max_scale := abs(mid_max_dist / mid_min_dist);

    max_saturation_scale := min(max_max_scale, mid_max_scale);

    #if T == Color4f then max_saturation.a = color.a;
    return max_saturation, max_saturation_scale;
}

// sets default luminance to the mid grey for the hue
hue_to_hsy :: inline (hue: float32, saturation := 1.0, alpha := 1.0) -> Color_HSY {
    hsy := Color_HSY.{
        hue         = hue,
        saturation  = saturation,
        luminance   = get_grey_value(hue_to_rgb(hue)),
        alpha       = alpha
    };
    debug__check_hsy(hsy);
    return hsy;
}

hue_to_rgb :: (hue: float32, alpha := 1.0, $T := Color4f) -> T #modify { return T == Color3f || T == Color4f; } {
    engine_check(.HIGH, is_norm_float(hue));
    engine_check(.HIGH, is_norm_float(alpha));

    color := T.{
        r = respace(abs(0.5 - hue),           {ONE_SIXTH, ONE_THIRD}, {0, 1}),
        g = respace(abs(ONE_THIRD - hue),     {ONE_SIXTH, ONE_THIRD}, {1, 0}),
        b = respace(abs(ONE_THIRD * 2 - hue), {ONE_SIXTH, ONE_THIRD}, {1, 0})
    };
    #if T == Color4f then color.a = alpha;
    return color;
}

hsy_to_rgb :: (hsy: Color_HSY, $T := Color4f) -> T #modify { return T == Color3f || T == Color4f; } {
    debug__check_hsy(hsy);

    rgb := hue_to_rgb(hsy.hue, T=T);

    max_saturated_luminance := get_grey_value(hue_to_rgb(hsy.hue));

    grey_alpha := clamp(1 - hsy.saturation, 0.0, 1.0);
    rgb = lerp_to_grey(rgb, max_saturated_luminance, grey_alpha);
    
    if max_saturated_luminance <= hsy.luminance {
        luma_alpha := respace(hsy.luminance, {max_saturated_luminance, 1}, {0, 1});
        rgb = lighten(rgb, luma_alpha);
    } else {
        luma_alpha := respace(hsy.luminance, {0, max_saturated_luminance}, {1, 0});
        rgb = darken(rgb, luma_alpha);
    }

    #if T == Color4f then rgb.a = hsy.alpha;
    return rgb;
}


rgb_to_hsy :: (rgb: $T/FLOAT_RGB_TYPES) -> Color_HSY {
    debug__check_float_rgb(rgb);

    hsy: Color_HSY = ---;
    
    // the reference color (pure hue) has saturation=1
    max_saturated := to_max_saturation(rgb);

    hsy.luminance = get_grey_value(rgb);

    // this represents 0.5 lightness, because the most saturated version of a color is halfway between black and white.
    max_saturated_luminance := get_grey_value(max_saturated);

    derive_saturation :: (hsy: *Color_HSY, channel: float, max_saturated_luminance: float) {
        alpha: float = ---;
        target_value: float = ---;

        if max_saturated_luminance <= hsy.luminance {
            alpha = respace(hsy.luminance, {max_saturated_luminance, 1}, {0, 1});
            target_value = 1;
        } else {
            alpha = respace(hsy.luminance, {0, max_saturated_luminance}, {1, 0});
            target_value = 0;
        }

        MAX_SATURATED_CHANNEL_VALUE :: 1.0;
        luma_shifted_channel := lerp(MAX_SATURATED_CHANNEL_VALUE, target_value, alpha);

        numerator   := channel - hsy.luminance;
        denominator := luma_shifted_channel - hsy.luminance;

        if denominator == 0 {
            // 1 if numerator is nonzero because the quotient approaches
            // infinity as denom goes to zero, but 1 is max value for saturation.
            hsy.saturation = ifx numerator == 0 then 0.0 else 1.0;
        } else {
            hsy.saturation = numerator / denominator;
        }
    }

    // use channel that the hue is closest to as the pivot and lerp along the edge of the circle toward the other nonzero channel.
    if max_saturated.r == 1 {
        if max_saturated.g > 0 { // rg
            hsy.hue = 0 + max_saturated.g * ONE_SIXTH;
        } else { // rb
            hsy.hue = 1 - max_saturated.b * ONE_SIXTH;
        }
        derive_saturation(*hsy, rgb.r, max_saturated_luminance);
    } else if max_saturated.g == 1 {
        if max_saturated.r > 0 { // rg
            hsy.hue = ONE_THIRD - max_saturated.r * ONE_SIXTH;
        } else { // gb
            hsy.hue = ONE_THIRD + max_saturated.b * ONE_SIXTH;
        }
        derive_saturation(*hsy, rgb.g, max_saturated_luminance);
    } else {
        engine_check(.LOW, max_saturated.b == 1, "if b != 1, a mistake was made within this procedure");
        if max_saturated.r > 0 { // rb
            hsy.hue = 2 * ONE_THIRD + max_saturated.r * ONE_SIXTH;
        } else { // bgss
            hsy.hue = 2 * ONE_THIRD - max_saturated.g * ONE_SIXTH;
        }
        derive_saturation(*hsy, rgb.b, max_saturated_luminance);
    }

    #if T == Color4f then hsy.alpha = rgb.a; else hsy.alpha = 1;
    return hsy;
}

// linear = walk hue linearly from red to green to blue to red (or starting at whatever hue)
// star   = imagine a color wheel, move in a star pattern, generating a set of alternatingly
// opposite-ish hues.
// todo: the star algorithm is essentially n steps with 2 stages of alternation. stages of alternation could also be parameterized
sample_linear_color_space :: (steps: int, initial_hue := 0.0, saturation := 1.0, lightness := 0.5, alpha := 1.0, move_pattern := enum { LINEAR; STAR; }.LINEAR) -> []Color4f {
    engine_check(.HIGH, is_norm_float(initial_hue));
    engine_check(.HIGH, is_norm_float(saturation));
    engine_check(.HIGH, is_norm_float(lightness));
    engine_check(.HIGH, is_norm_float(alpha));

    if steps == 0 {
        return .[];
    }

    initial_hue = clamp(initial_hue, 0, 1);
    colors := make_static_array(Color4f, steps);

    hsy := Color_HSY.{saturation=saturation, alpha=alpha};
    opposite_begin := div_ceil(steps, 2);

    for 0..steps-1 {
        color_it: int;

        if move_pattern == .STAR {
            even_index := it & 0x1 == 0;
            half_index := it / 2;
            if even_index {
                color_it = half_index;
            } else {
                color_it = opposite_begin + half_index;
            }
        } else {
            color_it = it;
        }

        hsy.hue = initial_hue + cast(float) color_it / steps;
        if hsy.hue >= 1 {
            hsy.hue -= 1;
        }
        set_lightness(*hsy, lightness);

        colors[it] = hsy_to_rgb(hsy);
    }
    
    return colors;
}

debug__check_float_rgb :: inline (rgb: $T/FLOAT_RGB_TYPES) {
    engine_check(.HIGH, is_norm_float(rgb.r));
    engine_check(.HIGH, is_norm_float(rgb.g));
    engine_check(.HIGH, is_norm_float(rgb.g));
    #if T == Color4f {
        engine_check(.HIGH, is_norm_float(rgb.a));
    }
}

debug__check_hsy :: inline (hsy: Color_HSY) {
    engine_check(.HIGH, is_norm_float(hsy.hue));
    engine_check(.HIGH, is_norm_float(hsy.saturation));
    engine_check(.HIGH, is_norm_float(hsy.luminance));
    engine_check(.HIGH, is_norm_float(hsy.alpha));
}

#scope_module

ONE_THIRD :: 1.0 / 3.0;
ONE_SIXTH :: 1.0 / 6.0;

// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.
