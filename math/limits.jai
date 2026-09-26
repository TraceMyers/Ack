get_min_value :: ($Number_Type: Type) -> Number_Type
#modify {
    tinfo := Number_Type.(*Type_Info);
    return tinfo.type == .INTEGER || tinfo.type == .FLOAT;
} {
    #if Number_Type == {
    case u8;
        return 0;
    case u16; 
        return 0;
    case u32; 
        return 0;
    case u64;
        return 0;
    case s8;
        return S8_MIN;
    case s16;
        return S16_MIN;
    case s32;
        return S32_MIN;
    case s64;
        return S64_MIN;
    case float32;
        return FLOAT32_MIN;
    case float64;
        return FLOAT64_MIN;
    case;
        #run assert(false);
    }
}

get_max_value :: ($Number_Type: Type) -> Number_Type
#modify {
    tinfo := Number_Type.(*Type_Info);
    return tinfo.type == .INTEGER || tinfo.type == .FLOAT;
} {
    #if Number_Type == {
    case u8;
        return U8_MAX;
    case u16;
        return U16_MAX;
    case u32;
        return U32_MAX;
    case u64;
        return U64_MAX;
    case s8;
        return S8_MAX;
    case s16;
        return S16_MAX;
    case s32;
        return S32_MAX;
    case s64;
        return S64_MAX;
    case float32;
        return FLOAT32_MAX;
    case float64;
        return FLOAT64_MAX;
    case;
        #run assert(false);
    }
}

// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.
