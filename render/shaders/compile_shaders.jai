#run {
    set_build_options_dc({do_output=false});
    process_command_line_arguments();

    Shader_File :: struct {
        input_path: string;
        output_path: string;
        stage: string;
    }

    Shader_Files :: struct {
        header: string;
        shaders: [..]Shader_File;
    }

    to_output_path :: (short_name: string) -> string {
        new_name := copy_string(short_name);
        for < *c : new_name {
            if c.* == #char "." {
                c.* = #char "_";
                break;
            }
        }
        return sprint("spirv/%.spv", new_name);
    }

    visitor :: (info: *File_Visit_Info, files: *Shader_Files) {
        if info.short_name == "header.glsl" {
            files.header = copy_string(info.full_name,, temp);
        } else {
            input_path := copy_string(info.full_name,, temp);
            output_path := to_output_path(info.short_name,, temp);

            if ends_with(info.short_name, "vert") {
                array_add(*files.shaders, {input_path, output_path, "vert"});
            } else if ends_with(info.short_name, "frag") {
                array_add(*files.shaders, {input_path, output_path, "frag"});
            } else if ends_with(info.short_name, "compute") {
                array_add(*files.shaders, {input_path, output_path, "compute"});
            }
        }
    }

    files: Shader_Files;

    visit_files("src", recursive=true, *files, visitor);

    compile_shader :: (header_text: string, shader: Shader_File) {
        auto_release_temp();
        do_log("shader compilation: % -> %", shader.input_path, shader.output_path);
        shader_text, read_success := read_entire_file(shader.input_path, true,, temp);
        if !read_success {
            do_log("failed reading input file. exiting.");
            exit(1);
        }

        // find paste directives written into the shader code.
        // they will be formatted like "## some_file_name", alone on a line.
        // this finds 'some_file_name.glsl' in the src folder and pastes the contents.
        shader_text_rebuilder: String_Builder;
        for :per_line shader_text {
            trimmed := trim(it);
            if begins_with(trimmed, "##") {
                found_space, left, right := split_from_left(trimmed, " ");
                filename := tprint("src/%.glsl", right);
                lines_to_paste, success := read_entire_file(filename,, temp);
                assert(success);
                print(*shader_text_rebuilder, "\n%\n", lines_to_paste);
            } else {
                print(*shader_text_rebuilder, tprint("%\n", it));
            }
        }

        shader_text = builder_to_string(*shader_text_rebuilder);

        combined_shader_text := tprint("%\n%", header_text, shader_text);
        write_success := write_entire_file("temp.glsl", combined_shader_text);
        if !write_success {
            do_log("failed writing temp file. exiting.");
            exit(1);
        }
        stage := tprint("-fshader-stage=%", shader.stage);
        result := run_command("glslc.exe", stage, "temp.glsl", "-o", shader.output_path);
        if result.exit_code != 0 {
            do_log("failed compilation. glslc exit code: %. exiting.", result.exit_code);
            exit(1);
        }
    }

    header_text, success := read_entire_file(files.header);
    if !success {
        do_log("failed loading header file %. exiting.", files.header);
        exit(1);
    }

    for shader : files.shaders {
        compile_shader(header_text, shader);
    }

    file_delete("temp.glsl");
}

process_command_line_arguments :: () {
    build_options := get_build_options();
    cl_args := build_options.compile_time_command_line;

    for arg : cl_args {
        if arg == "no-log" {
            should_do_log = false;
        }
    }
}

do_log :: (fmt: string, args: ..Any, caller_loc := #caller_location) #expand {
    if should_do_log {
        log(fmt, ..args, caller_loc);
    }
}

should_do_log := true;

#import "Basic";
#import "File_Utilities";
#import "String";
#import "Compiler";
#import "Process";
#import "File";

#import "TeRM/TeRM_String";

// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.
