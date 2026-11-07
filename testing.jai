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
    for 0..ENGINE_TESTS.count-1 {
        array_insert_at(*p.tests, ENGINE_TESTS[it].name, 0);
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
                if note.text == "build_test" {
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
                        array_add(test_logs, copy_string(message));
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

            print(*builder, "print(\"\\nSUCCESS count: \%/\%\\n\\n\", success_count, total_count); }");

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

// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.
