// todo: optionals implanting bitfields? probably overdoing it.
// I don't use this a lot but it's good for optional parameters whose entire
// value range is valid, so you can't, say, make -1 represent 'invalid value'.

Optional :: struct($T: Type) {
    value: T;
    is_valid: bool;
}

opt_in :: (value: $T) -> Optional(T) {
    return Optional(T).{value, true};
}

opt_out :: ($T: Type) -> Optional(T) {
    return {};
}

// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.
