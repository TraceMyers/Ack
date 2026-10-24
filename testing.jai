test_condition :: ($condition: Code, loc := #caller_location) #expand {
    if !(#insert condition) {
        log("  [test_condition] % @ %", #run code_string(condition), loc);

        `return false;
    }
}

get_testing_plugin :: () -> *Metaprogram_Plugin {
    p := New(Testing_Plugin);

    p.init = xx testing_plugin_init;
    p.message = xx testing_plugin_message;

    return p;
}

#scope_module

Testing_Plugin :: struct {
    using #as base: Metaprogram_Plugin;

    include_tests: [..]string;
    exclude_tests: [..]string;
    run_all_tests: bool;

    tests: [..]string;
    ran_tests: bool;
}

testing_plugin_init :: (p: *Testing_Plugin, options: []string) -> bool {
    array_reserve(*p.tests, 256);

    // parse options
    next_option_is_inclusive: bool;
    next_option_is_exclusive: bool;
    p.run_all_tests = true;
    
    for option : options {
        if next_option_is_inclusive {
            assert(could_be_procedure_name(option), "invalid procedure name %", option);
            array_add_if_unique(*p.include_tests, option);
            next_option_is_inclusive = false;
            p.run_all_tests = false;
        } else if next_option_is_exclusive {
            assert(could_be_procedure_name(option), "invalid procecure name %", option);
            array_add_if_unique(*p.exclude_tests, option);
            next_option_is_exclusive = false;
            p.run_all_tests = false;
        } else {
            if option == "--all" || option == "-a" {
                p.run_all_tests = true;
            } else if option == "--exclude" || option == "-e" {
                next_option_is_exclusive = true;
            } else if option == "--include" || option == "-i" {
                next_option_is_inclusive = true;
            }
        }
    }
    
    assert(!next_option_is_inclusive && !next_option_is_exclusive, "provided a dangling -i or -e argument");

    if p.run_all_tests {
        p.include_tests.count = 0;
    }

    return true;
}

testing_plugin_message :: (p: *Testing_Plugin, message: *Message) {
    if p.ran_tests {
        return;
    }

    if message.kind == .TYPECHECKED {
        m_typechecked := cast(*Message_Typechecked) message;
        for b : m_typechecked.procedure_bodies {
            body := b.expression;
            for note : body.header.notes {
                if note.text == "test" || note.text == "engine_test" {
                    if !is_runnable_test(body.header) {
                        continue;
                    }
                    array_add_if_unique(*p.tests, body.header.name);
                }
            }
        }
    } else if message.kind == .PHASE {
        m_phase := cast(*Message_Phase) message;
        if m_phase.phase == .TYPECHECKED_ALL_WE_CAN && p.tests.count > 0 {
            // if p.include_tests.count > 0 {
            //     for p.include_tests
            // }
            // todo: include/exclude
            // todo: test runner process so build process is insulated from crashes
            builder: String_Builder;
            print(*builder, 
            #string END
                #run {
                    print("running tests...\n\n");
                    success_count: int;
                    total_count: int;

                    test_logs: [..]string;
                    defer_log :: (message: string, data: *void, in_info: Log_Info) {
                        test_logs := cast(*[..]string) data;
                        array_add(test_logs, message);
                    }

            END);
    
            for test : p.tests {
                print(*builder, 
                #string END
                    {
                        print("%: ");
                        total_count += 1;

                        context.logger = defer_log;
                        context.logger_data = *test_logs;

                        if %() {
                            print("SUCCESS\n");
                            success_count += 1;
                        } else {
                            print("FAILURE\n");
                        }

                        context.logger = runtime_support_default_logger;

                        if test_logs.count > 0 {
                            for test_log : test_logs {
                                log(test_log);
                            }
                            array_reset(*test_logs);
                        }
                    }
                END,
                    test, test
                );
            }

            print(*builder, "print(\"\\nSUCCESS count: \%/\%\\n\", success_count, total_count); }");

            add_build_string(builder_to_string(*builder), message.workspace);

            p.ran_tests = true;
        }
    }
}

// with dead code elimination off, tests noted in other modules (e.g. String) get typechecked too.
// only run tests from the main program and from this engine, and only ones shaped () -> bool.
is_runnable_test :: (header: *Code_Procedure_Header) -> bool {
    load := header.location.enclosing_load;
    module_name := "";
    if load && load.enclosing_import {
        module_name = load.enclosing_import.module_name;
    }
    is_main_program := load && load.enclosing_import && load.enclosing_import.module_type == .MAIN_PROGRAM;
    if !is_main_program && module_name != "Ack!" {
        return false;
    }

    if header.arguments.count != 0 || header.returns.count != 1 || header.returns[0].type.type != .BOOL {
        log("[testing] skipping % (%): tests must be shaped () -> bool", header.name, get_filename(header));
        return false;
    }
    return true;
}

should_run_tests :: (p: *Testing_Plugin) -> bool {
    return p.run_all_tests || p.include_tests.count > 0;
}

could_be_procedure_name :: (str: string) -> bool {
    if str.count == 0 {
        return false;
    }
    if !is_alpha(str[0]) && str[0] != #char "_" {
        return false;
    }
    if str.count > 1 then for 0..str.count-1 {
        if !is_alnum(str[it]) && str[it] != #char "_" {
            return false;
        }
    }
    return true;
}

// Metaprogram_Plugin :: struct {
//     // 'workspace' is set by the metaprogram that creates the plugin.
//     // It tells you which workspace we are operating on, where
//     // all the messages are coming from, etc. If you add source,
//     // it would be to this workspace.
//     workspace: Workspace;

//     init:              (p: *Metaprogram_Plugin, options: [] string) -> bool;

//     before_intercept:  (p: *Metaprogram_Plugin, flags: *Intercept_Flags);
//     add_source:        (p: *Metaprogram_Plugin);
//     message:           (p: *Metaprogram_Plugin, message: *Message);  // We don't pass the Workspace, because it's on Message.
//     finish:            (p: *Metaprogram_Plugin);
//     shutdown:          (p: *Metaprogram_Plugin);

//     log_help:          (p: *Metaprogram_Plugin);

//     // As a temporary way for compile-time code to execute plugins, we have added
//     // communication_proc(). It kind of sucks because it only takes strings, but the presumption
//     // is you didn't know what to import to get any actual types defined by this module.
//     // It's an open problem to establish a general mechanism that does this better...
//     // maybe you just #dynamic_specialize to get the module then #insert some #code
//     // or something.

//     communication_proc: (p: *Metaprogram_Plugin, key: string, value: string) -> bool;  // May be null!
// }

// text_encoding_test :: () -> bool, string {
//     utf8_real_world_file := tprint("%/test_supplemental/utf8_in.txt", #filepath);
//     utf8_real_world, read_utf8_real_world_success := read_entire_file(utf8_real_world_file);
//     test_condition(read_utf8_real_world_success);
//     encode_success: bool;

//     // starting with real world utf8 and moving it through all of the translation paths
//     {
//         to_utf32:, encode_success = encode_text(utf8_real_world, UTF8_TO_UTF32,, temp);
//         test_condition(encode_success);
//         back_to_utf8:, encode_success = encode_text(to_utf32, UTF32_TO_UTF8,, temp);
//         test_condition(encode_success);
//         test_condition(utf8_real_world == back_to_utf8);
//     }
//     {
//         // this uses utf16 <-> utf32 as a transition state for each code point, so that is also tested somewhat
//         to_utf16:, encode_success = encode_text(utf8_real_world, UTF8_TO_UTF16,, temp);
//         test_condition(encode_success);
//         back_to_utf8:, encode_success = encode_text(to_utf16, UTF16_TO_UTF8,, temp);
//         test_condition(encode_success);
//         test_condition(utf8_real_world == back_to_utf8);
//     }

//     {
//         to_ansi:, encode_success = encode_text(utf8_real_world, UTF8_TO_ANSI);
//         test_condition(!encode_success);
//     }

//     ansi_val := "\xff";
//     ansi_to_utf8:, encode_success = encode_text(ansi_val, ANSI_TO_UTF8);
//     test_condition(encode_success);
//     test_condition(ansi_to_utf8.count == 2);

//     bad_utf8_1 := "\xf0\x02";
//     bad_utf8_to_utf32_1:, encode_success = encode_text(bad_utf8_1, UTF8_TO_UTF32);
//     test_condition(!encode_success);

//     bad_utf8_2 := "\xe1\x81";
//     bad_utf8_to_utf32_2:, encode_success = encode_text(bad_utf8_2, UTF8_TO_UTF32);
//     test_condition(!encode_success);

//     bad_utf32 := "\x01\x02\x03";
//     bad_utf32_to_utf16:, encode_success = encode_text(bad_utf32, UTF32_TO_UTF16);
//     test_condition(!encode_success);

//     unaligned_utf16 := copy_string("\x00\x01\x02");
//     addr_is_even := (unaligned_utf16.data.(u64) & 1) == 0;
//     if addr_is_even {
//         unaligned_utf16.data += 1;
//     }
//     else {
//         unaligned_utf16[0] = unaligned_utf16[1];
//         unaligned_utf16[1] = unaligned_utf16[2];
//     }
//     unaligned_utf16.count -= 1;
//     unaligned_utf16_to_utf32:, encode_success = encode_text(unaligned_utf16, UTF16_TO_UTF32);
//     test_condition(encode_success);
//     test_condition(unaligned_utf16_to_utf32.count == 4);
//     test_condition(unaligned_utf16_to_utf32 == "\x01\x02\x00\x00");

//     return_test_success();
// }

// math_test :: () -> bool, string {
//     // seems silly to test this but it's free so whatever
//     test_condition(!is_power_of_two(65));
//     test_condition(!is_power_of_two(-1));
//     for i : 0..63 {
//         pow2 : u64 = (1).(u64) << i.(u64);
//         test_condition(is_power_of_two(pow2));
//         if i > 1 {
//             test_condition(!is_power_of_two(pow2-1));
//         }
//     }

//     {
//         val := 5;
//         min := 2;
//         max := 8;
//         add_to_val := 20;
//         result := add_wrap(val, add_to_val, min, max);
//         test_condition(result == 4);
//     }
//     {
//         val := 11;
//         min := 2;
//         max := 12;

//         add_to_val := 2;
//         result := add_wrap(val, add_to_val, min, max);
//         test_condition(result == min);

//         add_to_val = 2 + (max - min);
//         result = add_wrap(val, add_to_val, min, max);
//         test_condition(result == max);

//         val = 3;
//         add_to_val = max - val;
//         result = add_wrap(val, add_to_val, min, max);
//         test_condition(result == max);

//         add_to_val = -1;
//         result = add_wrap(val, add_to_val, min, max);
//         test_condition(result == min);

//         add_to_val = -2;
//         result = add_wrap(val, add_to_val, min, max);
//         test_condition(result == max);

//         add_to_val = -2 - (max-min);
//         result = add_wrap(val, add_to_val, min, max);
//         test_condition(result == min);

//         add_to_val -= 1;
//         result = add_wrap(val, add_to_val, min, max);
//         test_condition(result == max);

//         val = 2;
//         min = 2;
//         max = 2;
//         add_to_val = 20;
//         result = add_wrap(val, add_to_val, min, max);
//         test_condition(result == 2);

//         add_to_val = -20;
//         result = add_wrap(val, add_to_val, min, max);
//         test_condition(result == 2);
//     }
//     {
//         int_val : u8 = 127;
//         norm_val := alter_cast(int_val, float, true);
//         test_condition(abs(norm_val-0.5) <= 0.005);

//         int_val = 0;
//         norm_val = alter_cast(int_val, float, true);
//         test_condition(norm_val == 0.0);

//         int_val = 255;
//         norm_val = alter_cast(int_val, float, true);
//         test_condition(norm_val == 1.0);

//         float_val := 0.0;
//         out_int := alter_cast(float_val, s8, false, false);
//         test_condition(out_int == 0);

//         float_val = 1.0;
//         out_int = alter_cast(float_val, s8, true, false);
//         test_condition(out_int == 127);

//         float_val = 1.0;
//         out_int = alter_cast(float_val, s8, true, true);
//         test_condition(out_int == 127);

//         float_val = xx S32_MAX;
//         out_int2 := alter_cast(float_val, s32, false, false);
//         // overflow on cast back to int
//         test_condition(out_int2 == S32_MIN);

//         out_int2 = alter_cast(float_val, s32, false, true);
//         // round() clamps to stop the overflow
//         test_condition(out_int2 == S32_MAX);

//         have_to_assign_to_var_or_cast_doesnt_work_right : s32 = S32_MIN;
//         float_val = have_to_assign_to_var_or_cast_doesnt_work_right.(float) - 128.0;
//         out_int2 = alter_cast(float_val, s32, false, true);
//         // round() clamps to stop the underflow
//         test_condition(out_int2 == S32_MIN);
//     }
//     {
//         a: s32 = 8;
//         b := ceil_to_multiple(a, 8);
//         c := floor_to_multiple(a, 8);
//         test_condition(b == 8);
//         test_condition(c == 8);

//         a = 9;
//         b = ceil_to_multiple(a, 8);
//         c = floor_to_multiple(a, 8);
//         test_condition(b == 16);
//         test_condition(c == 8);

//         a = 7;
//         b = ceil_to_multiple(a, 8);
//         c = floor_to_multiple(a, 8);
//         test_condition(b == 8);
//         test_condition(c == 0);
//     }

//     return_test_success();
// }

// array_utils_test :: () -> bool, string {
//     {
//         arr := string.["hello", "yes", "fishy joe"];
//         pointer_based_index := array_element_index(arr, *arr[1]);
//         success, found_index := array_find(arr, "yes");
//         test_condition(pointer_based_index == found_index);
//     }
//     {
//         arr1 := s32.[1, 2, 3];
//         arr2 := s32.[1, 2, 3, 4];
//         test_condition(!arrays_equal(arr1, arr2));
//         arr3 : []s32 = arr2;
//         arr3.count -= 1;
//         test_condition(arrays_equal(arr1, arr3));
//     }
//     {
//         arr1 := make_dynamic_array(s32, 2,,temp);
//         arr2 := s32.[1, 2, 3, 4];
//         array_append(*arr1, arr2);
//         test_condition(arrays_equal(arr1, arr2));

//         arr3 := array_concatenate(arr1, arr2);
//         arr_compare := s32.[1,2,3,4,1,2,3,4];
//         test_condition(arrays_equal(arr3, arr_compare));

//         arr4 := array_duplicate(arr3);
//         test_condition(arrays_equal(arr3, arr4));
//     }

//     return_test_success();
// }

// pool_test :: () -> bool, string {
//     SomeStruct :: struct {
//         a : s32 = -1;
//         b := 1.0;
//         c := "a string!";
//     }

//     init_item_proc :: (s: *SomeStruct) {
//         assert(s.a == -1 && s.b == 1.0 && s.c == "a string!");
//         s.a = 100;
//         s.b = 100.0;
//         s.c = "neh";
//     }

//     deinit_item_proc :: (s: *SomeStruct) {
//         assert(s.a == 100 && s.b == 100.0 && s.c == "neh");
//         s.* = .{};
//     }

//     p: Pool(SomeStruct);
//     p.shrink_to_min = 0;
//     pool_set_capacity(*p, 32);

//     i1 := pool_acquire(*p, init_item_proc);
//     s1 := *p[i1];
//     test_condition(s1 == *p[0]);

//     i2 := pool_acquire(*p, init_item_proc);
//     s2 := *p[i2];
//     test_condition(s2 == *p[1]);

//     i3 := pool_acquire(*p, init_item_proc);
//     s3 := *p[i3];
//     test_condition(s3 == *p[2]);

//     pool_release(*p, i2, deinit_item_proc);
//     test_condition(p.top == 2);
//     test_condition(!is_pool_item_in_use(*p, 1));

//     i3b := pool_get_index(*p, s3);
//     test_condition(i3b == i3);

//     i2 = pool_acquire(*p, init_item_proc);
//     s2 = *p[i2];
//     test_condition(s2 == *p[1]);
//     test_condition(is_pool_item_in_use(*p, 1));

//     compare_proc :: (a: *SomeStruct, b: *SomeStruct) -> bool {
//         return a == b;
//     }

//     i3c := pool_find(*p, s3, compare_proc);
//     test_condition(i3c == i3);

//     // --
//     pool_reset(*p, deinit_item_proc);
//     // --

//     i1 = pool_acquire(*p, init_item_proc);
//     s1 = *p[i1];
//     test_condition(s1 == *p[0]);

//     i2 = pool_acquire(*p, init_item_proc);
//     s2 = *p[i2];
//     test_condition(s2 == *p[1]);

//     i3 = pool_acquire(*p, init_item_proc);
//     s3 = *p[i3];
//     test_condition(s3 == *p[2]);

//     pool_release(*p, i2, deinit_item_proc);
//     test_condition(p.top == 2);
//     test_condition(!is_pool_item_in_use(*p, 1));

//     i3b = pool_get_index(*p, s3);
//     test_condition(i3b == i3);

//     i2 = pool_acquire(*p, init_item_proc);
//     s2 = *p[i2];
//     test_condition(s2 == *p[1]);
//     test_condition(is_pool_item_in_use(*p, 1));

//     i3c = pool_find(*p, s3, compare_proc);
//     test_condition(i3c == i3);
    
//     // --
//     pool_reset(*p, deinit_item_proc);
//     // --
    
//     indices := make_dynamic_array(s64, 100,, temp);
//     for 0..99 {
//         pool_acquire(*p, init_item_proc);
//         array_add(*indices, it);
//     }

//     shuffle_array :: (arr: []$T) {
//         if arr.count == 0 then return;
//         for i: 0..arr.count-1 {
//             rand_val := random_get_zero_to_one_new();
//             swap_index := round(respace(xx rand_val, Vector2.{0.0, 1.0}, Vector2.{0.0, xx (arr.count-1)}));
//             arr[i], arr[swap_index] = arr[swap_index], arr[i];
//         }
//     }

//     shuffle_array(indices);

//     for indices {
//         pool_release(*p, it, deinit_item_proc);
//     }

//     test_condition(p.top == -1);
//     test_condition(p.items.count == 0);
//     first_set_bit: s64 = -1;
//     for :only_set_bits p.in_use {
//         first_set_bit = it_index;
//         break;
//     }
//     test_condition(first_set_bit == -1);

//     p.shrink_to_min = 12;
//     for 0..99 {
//         pool_acquire(*p, init_item_proc);
//     }
//     for indices {
//         pool_release(*p, it, deinit_item_proc);
//     }

//     test_condition(p.top == -1);
//     test_condition(p.items.count >= 12);

//     return_test_success();
// }

// bump_allocator_test :: no_inline () -> bool, string {
//     // b: Bump_Allocator;
//     // bump_allocator_initialize(*b);
//     // defer bump_allocator_reset(*b);

//     // test_condition(b.heaps.count == 1 || b.heaps[1].bytes.count == 0);
//     // test_condition(b.heaps[0].bytes.count == BUMP_ALLOCATOR_DEFAULT_HEAP_SIZE);
//     // test_condition(b.heaps[0].end == 0);
//     // {
//     //     scope_mark_and_recede_allocations(*b);
//     //     alloc1 := bump_allocator_allocate(*b, 1024);     
//     //     test_condition(b.heaps[0].end == 1024);
//     //     alloc2 := bump_allocator_allocate(*b, 1025);
//     //     test_condition(b.heaps[0].end == 1024 + 1025 + 7);
//     //     alloc3 := bump_allocator_allocate(*b, 1023);
//     //     test_condition(b.heaps[0].end == 1024 + 1025 + 7 + 1023 + 1);
//     //     {
//     //         scope_mark_and_recede_allocations(*b);
//     //         data_prev: *u8 = null;
//     //         prev_alloc_size: s32 = -1;
//     //         for 0..100 {
//     //             data: *u8 = bump_allocator_allocate(*b, it);
//     //             if prev_alloc_size >= 1 {
//     //                 diff := data.(u64) - data_prev.(u64);
//     //                 should_be_diff := ceil_to_multiple(prev_alloc_size, 8);
//     //                 test_condition(diff == xx should_be_diff);
//     //             } else if prev_alloc_size == 0 {
//     //                 // alloc(0) == no diff;
//     //                 diff := data.(u64) - data_prev.(u64);
//     //                 test_condition(diff == 0);
//     //             }
//     //             prev_alloc_size = xx it;
//     //             data_prev = data;
//     //         }
//     //     }
//     //     test_condition(b.heaps[0].end == 1024 + 1025 + 7 + 1023 + 1);
//     // }
//     // test_condition(b.heaps[0].end == 0);

//     // {
//     //     scope_set_allocator(b);
//     //     {
//     //         scope_mark_and_recede_allocations(*b);
//     //         alloc1 := alloc(1024);     
//     //         test_condition(b.heaps[0].end == 1024);
//     //         alloc2 := alloc(1025);
//     //         test_condition(b.heaps[0].end == 1024 + 1025 + 7);
//     //         alloc3 := alloc(1023);
//     //         test_condition(b.heaps[0].end == 1024 + 1025 + 7 + 1023 + 1);
//     //         {
//     //             scope_mark_and_recede_allocations(*b);
//     //             for 0..100 {
//     //                 alloc(it);
//     //             }
//     //         }
//     //         test_condition(b.heaps[0].end == 1024 + 1025 + 7 + 1023 + 1);
//     //     }
//     // }
//     // test_condition(b.heaps[0].end == 0);

//     // {
//     //     scope_set_allocator(b);
//     //     scope_mark_and_recede_allocations(*b);
//     //     alloc_sz := BUMP_ALLOCATOR_DEFAULT_HEAP_SIZE / 3 - 8;
//     //     for 0..5 {
//     //         data: *u8 = alloc(alloc_sz);
//     //         if it <= 2 {
//     //             test_condition(b.heaps[1].bytes.count == 0);
//     //             test_condition(b.heaps[1].end == 0);
//     //         } else if it <= 5 {
//     //             test_condition(b.heaps[0].end < BUMP_ALLOCATOR_DEFAULT_HEAP_SIZE);
//     //             test_condition(b.heaps[1].bytes.count == BUMP_ALLOCATOR_DEFAULT_HEAP_SIZE);
//     //             test_condition(b.heaps[2].bytes.count == 0);
//     //             test_condition(b.heaps[2].end == 0);
//     //         }
//     //     }
//     // }
//     // test_condition(b.heaps[0].end == 0);


//     return_test_success();
// }

// Test_Struct :: struct {
//     a: s32;
//     b: u8;
//     c: float64;
//     d: string;
// }

// operator == :: (t1: Test_Struct, t2: Test_Struct) -> bool {
//     return t1.a == t2.a && t1.b == t2.b && t1.c == t2.c && t1.d == t2.d;
// }

// serializer_test :: () -> bool, string {
//     checksum: Serializer_Checksum_Type;
//     {
//         ser: Serializer(.STATIC, .BYTE);
//         ser.memory = alloc_string(1024);
//         ser.read_array_allocator = context.allocator;
//         serializer_test_body(*checksum, true);
//     }
//     {
//         ser: Serializer(.STATIC, .PRIMITIVE);
//         ser.memory = alloc_string(1024);
//         ser.read_array_allocator = context.allocator;
//         serializer_test_body();
//     }
//     {
//         ser: Serializer(.STATIC, .PARAMETER);
//         ser.memory = alloc_string(1024);
//         ser.read_array_allocator = context.allocator;
//         ser.parameter_align = 1;
//         serializer_test_body();
//         ser.parameter_align = 2;
//         serializer_test_body();
//         ser.parameter_align = 4;
//         serializer_test_body();
//         ser.parameter_align = 8;
//         serializer_test_body();
//     }
//     {
//         ser: Serializer(.DYNAMIC, .BYTE);
//         ser.allocator = context.allocator;
//         ser.read_array_allocator = context.allocator;
//         serializer_test_body(*checksum);
//     }
//     return_test_success();
// }

// string_test :: () -> bool, string {
//     lines := string.[
//         "",
//         "hey there",
//         "",
//         "this is a line",
//         "and this is another line"
//     ];

//     builder: String_Builder;
//     for lines {
//         print(*builder, "%\n", it);
//     }
//     test_str := builder_to_string(*builder);
    
//     for :per_line line : test_str {
//         assert(line == lines[it_index]);
//     }

//     return_test_success();
// }

// json_test :: () -> bool, string {
//     scope_set_working_directory(#filepath);

//     jason := load_json_from_file("test_supplemental/100 KB 10 Level Formatted.json", log_errors=true);
//     defer free(*jason);

//     // todo: invalid json test suite

//     // log("string byte count: %", jason.strings.count);
//     // strings := string.{jason.strings.count, jason.strings.data};
//     // for strings {
//     //     if it == 0 {
//     //         print("|");
//     //     } else {
//     //         print("%", string.{1, *it});
//     //     }
//     // }

//     test_condition(jason.errors.count == 0);

//     // for_each_proc :: (stack: []*JSON_Element, parent: *JSON_Element, object_key: string, value: *JSON_Element, user_data: *void) -> bool {
//     //     if value.type == .STRING {
//     //         log("count: %, value: %", value.bytes.count, value.bytes);
//     //     }
//     //     return true;
//     // }
//     // for_each_element(*jason, for_each_proc);

//     return_test_success();
// }

// gltf_test :: () -> bool, string {
//     scope_set_working_directory(#filepath);

//     asset: Asset_3D;
//     gltf := load_gltf_from_file("test_supplemental/gltf_sample_models/avocado/glTF-Binary/Avocado.glb", *asset, log_errors=true);

//     return_test_success();
// }

// locks_test :: () -> bool, string {

//     return_test_success();
// }

// // ---------------------------------------------------------------------------------------------------------------------
// #scope_file // ---------------------------------------------------------------------------------------------- SCOPE_FILE
// // ---------------------------------------------------------------------------------------------------------------------

// serializer_test_body :: (checksum: *Serializer_Checksum_Type = null, load_checksum := false) #expand {
//     s := `ser;
//     initialize(*s, .WRITE, use_checksum=checksum != null);

//     t: Test_Struct;
//     memset(*t, 0, size_of(Test_Struct));
//     t = Test_Struct.{
//         a = 100,
//         b = 255,
//         c = 0.1,
//         d = "hello"
//     };
//     str := "whatever";
//     array := u16.[1, 2, 3, 4, 5, 6, 7];
//     array_for_copy : []u16 = array;

//     serialize(*s, *t.a);
//     head_1 := s.head;
//     serialize(*s, *t.b);
//     head_2 := s.head;
//     serialize(*s, *t.c);
//     head_3 := s.head;
//     serialize(*s, *t.d);
//     head_4 := s.head;
//     serialize(*s, *t);
//     head_5 := s.head;
//     serialize(*s, *str);
//     head_6 := s.head;
//     serialize(*s, *array_for_copy);
//     head_7 := s.head;
//     serialize(*s, *t);
//     head_8 := s.head;
//     serialize(*s, *t.a);
//     head_9 := s.head;
//     serialize(*s, *t.b);
//     head_10 := s.head;
//     serialize(*s, *t.c);
//     head_11 := s.head;
//     serialize(*s, *t.d);
//     head_12 := s.head;

//     if checksum {
//         // if load_checksum {
//         //     memcpy(checksum.data, s.memory.data, SERIALIZER_CHECKSUM_SIZE);
//         // } else {
//         //     memcpy(s.memory.data, checksum.data, SERIALIZER_CHECKSUM_SIZE);
//             imprint_checksum(*s);
//             test_condition(validate_checksum(*s));
//         // }
//     }

//     rt1, rt2, rt3, rt4: Test_Struct;
//     memset(*rt1, 0, size_of(Test_Struct));
//     rstr: string;
//     rarray: []u16;

//     reset_head_with_mode(*s, .READ);

//     serialize(*s, *rt1.a);
//     test_condition(head_1 == s.head);
//     serialize(*s, *rt1.b);
//     test_condition(head_2 == s.head);
//     serialize(*s, *rt1.c);
//     test_condition(head_3 == s.head);
//     serialize(*s, *rt1.d);
//     test_condition(head_4 == s.head);
//     serialize(*s, *rt2);
//     test_condition(head_5 == s.head);
//     serialize(*s, *rstr);
//     test_condition(head_6 == s.head);
//     serialize(*s, *rarray);
//     test_condition(head_7 == s.head);
//     serialize(*s, *rt3);
//     test_condition(head_8 == s.head);
//     serialize(*s, *rt4.a);
//     test_condition(head_9 == s.head);
//     serialize(*s, *rt4.b);
//     test_condition(head_10 == s.head);
//     serialize(*s, *rt4.c);
//     test_condition(head_11 == s.head);
//     serialize(*s, *rt4.d);
//     test_condition(head_12 == s.head);

//     test_condition(rt1 == t);
//     test_condition(rt2 == t);
//     test_condition(rt3 == t);
//     test_condition(rt4 == t);
//     test_condition(rstr == str);
//     test_condition(arrays_equal(rarray, array));
// }

// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.
