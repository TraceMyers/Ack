Render_Text :: struct {
    fonts: Table(string, *Font);
}

init_render_text :: () -> bool {
    engine_log("copying fonts from engine", flags=.VERBOSE_ONLY);

    fonts_path := engine.project_info.fonts_path;
    if !file_exists(fonts_path) {
        engine_error("unable to find fonts path %", engine.project_info.fonts_path);
    }

    if copy_engine_files_to_project {
        report_copy_error :: (error_fmt: string, args: ..Any) #expand {
            engine_error("failed to copy fonts from the engine to the project: %", tprint(error_fmt, ..args));
            `return false;
        }

        src_path, src_success := build_path_string(ack_engine_path(), "additional_materials/fonts");
        if !src_success {
            report_copy_error("unable to find engine source path additional_materials/fonts");
            return false;
        }

        engine_log("copy source = %, dest = %", src_path, fonts_path, flags=.VERY_VERBOSE_ONLY);
        
        copy_success := copy_directory(src_path, fonts_path,, temp);
        if !copy_success {
            report_copy_error("failed to copy fonts from % to %", src_path, fonts_path);
            return false;
        }

        engine_log("success copying fonts from engine", flags=.VERBOSE_ONLY);
    }

    return true;
}

