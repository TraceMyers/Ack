scope_set_working_directory :: (dir: string) #expand {
    cwd := get_working_directory();
    set_working_directory(dir);
    `defer set_working_directory(cwd);   
}

convert_to_forward_slashes :: (path: string) {
    for *c : path {
        if c.* == #char "\\" {
            c.* = #char "/";
        }
    }
}

// 1. converts to forward slashes because parse_path doesn't recognize backslashes -.-
// 2. always temp
parse_path_ext :: (in_path: string, reduce := true) -> Path {
    path := copy_string(in_path,, temp);
    convert_to_forward_slashes(path);
    return parse_path(path, reduce,, temp);
}

// 1. subtract words instead of using sum
// 2. always temp
path_to_string_ext :: (path: *Path, subtract_count := 0) -> string {
    return path_to_string(path.*, path.words.count - subtract_count,, temp);
}

move_down_directory :: (path: *Path, directory: string) {
    array_add(*path.words, directory);
}

move_up_directory :: (path: *Path) {
    engine_check(.LOW, path.words.count > 0);
    path.words.count -= 1;
}

// resolve '..' and symlinks 
get_final_path :: (path: string) -> string {
    #if OS == .WINDOWS {
        using Win32;
        handle := CreateFileA(temp_c_string(path), 0, Win32.FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, null, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, null);
        path_buffer: [4096]u8;
        out_path_len := GetFinalPathNameByHandleA(handle, path_buffer.data, xx path_buffer.count);
        if out_path_len == 0 {
            log("get_path_after_resolving_symlinks win32 error: %", GetLastError());
            return {};
        }

        out_path: string;
        path_as_given := string.{out_path_len, path_buffer.data};
        index_of_drive_colon := find_index_from_left(path_as_given, #char ":");
        engine_check(.LOW, index_of_drive_colon > 0);

        // windows adds \\?\ before the drive letter sometimes/all the time (?) to indicate
        // that the path is final. I'm deleting it because it's a potentially unfamiliar
        // syntax whatever code is making use of the path.
        index_of_drive_letter := index_of_drive_colon - 1;
        out_path = alloc_string(out_path_len - index_of_drive_letter);
        memcpy(out_path.data, path_buffer.data + index_of_drive_letter, out_path_len - index_of_drive_letter);

        return out_path;
    } else {
        return path;
    }
}

// extension filter for if it's a directory. e.g. string.["jai", "c", "txt"] to count
// lines in files of those extension
count_lines :: (file_or_directory_path: string, extension_filter: []string = .[]) -> total: int, non_blank: int {
    auto_release_temp();

    path, filename, ext := path_decomp(file_or_directory_path);
    count := File_Lines_Count.{ext_filter=extension_filter}; 

    if ext.count > 0 {
        // file
        count_file_lines(file_or_directory_path, *count);
    } else {
        // directory
        visit_files(file_or_directory_path, recursive=true, *count, count_file_lines_visitor,, temp);
    }

    return count.total, count.non_blank;
}

#scope_file

File_Lines_Count :: struct {
    total:     int;
    non_blank: int;
    ext_filter: []string;
}

count_file_lines_visitor :: (info: *File_Visit_Info, count: *File_Lines_Count) {
    file_ext := path_extension(info.full_name);
    if count.ext_filter.count == 0 {
        count_file_lines(info.full_name, count);
    } else for ext : count.ext_filter {
        if ext == file_ext {
            count_file_lines(info.full_name, count);
            return;
        }
    }
}

count_file_lines :: (file_path: string, count: *File_Lines_Count) {
    auto_release_temp();

    text, read_success := read_entire_file(file_path, true,, temp);

    if read_success {
        for :per_line line : text {
            non_blank: bool;
            for c : line {
                if !is_space(c) {
                    non_blank = true;
                    break;
                }
            }

            count.total += 1;
            if non_blank {
                count.non_blank += 1;
            }
        }
    }
}

#if OS == .WINDOWS {
    GetFinalPathNameByHandleA :: (handle: Win32.HANDLE, out_path_buffer: *u8, out_path_buffer_size_including_null: s32, flags: s32 = 0) -> out_path_length: s32 #foreign kernel32;
}
