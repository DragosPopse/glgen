package main
import "core:strings"
import "core:fmt"
import "core:encoding/xml"

generate :: proc(sb: ^strings.Builder, registry: ^GL_Registry, opts: Gen_Options) {
    using strings
    write_string(sb, "package gl\n")
    write_string(sb, "import \"core:c\"\n")
    write_string(sb, "import \"core:builtin\"\n")
    write_string(sb, "import \"core:fmt\"\n")
    write_string(sb, "import \"core:runtime\"\n")
    write_string(sb, "\n")
    write_string(sb, "GL_DEBUG :: #config(GL_DEBUG, ODIN_DEBUG)\n")
    write_string(sb, "\n")
    for d in registry.types {
        if strings.contains(d.name, "struct") || d.name == "GLvoid" || d.name == "void" do continue // Rework
        d := d^
        if opts.remove_gl_prefix do d.name = remove_gl_prefix(d.name)
        if definition_exists(registry, d.odin_type) && opts.remove_gl_prefix do d.odin_type = remove_gl_prefix(d.odin_type)
        fmt.sbprintf(sb, "%s :: %s\n", d.name, d.odin_type)
    }

    write_string(sb, "\n")

    for f in registry.features {
        fmt.sbprintf(sb, "// %s\n", f.name)
        for d in f.enums {
            if d.name == "" do continue // This shouldn't be here... but it seems something is wrong somewhere in parsing
            d := d^
            if opts.remove_gl_prefix do d.name = remove_gl_prefix(d.name)
            fmt.sbprintf(sb, "%s :: %s\n", d.name, d.value)
        }
    }

    write_string(sb, "\n")

    for f in registry.features {
        fmt.sbprintf(sb, "// %s\n", f.name)
        for d in f.commands {
            d := d^
            if opts.remove_gl_prefix do d.name = remove_gl_prefix(d.name)
            fmt.sbprintf(sb, "impl_%s: proc \"c\" (", d.name)
                for param, i in d.params {
                    param := param // this is not needed rn... it's even wrong
                    if opts.remove_gl_prefix do param.name = remove_gl_prefix(param.name)
                    fmt.sbprintf(sb, "%s: %s", param.name, param.type)
                    if i < len(d.params) - 1 {
                        write_string(sb, ", ")
                    }
                }
                write_string(sb, ")")
                if d.return_type != "" {
                    fmt.sbprintf(sb, " -> %s", d.return_type)
                }
                write_string(sb, "\n")
        }
    }

    write_string(sb, "\n")

    for ext in registry.extensions {
        fmt.sbprintf(sb, "// %s\n", ext.name)
        for d in ext.enums {
            if d.name == "" do continue // This shouldn't be here... but it seems something is wrong somewhere in parsing
            d := d^
            if opts.remove_gl_prefix do d.name = remove_gl_prefix(d.name)
            fmt.sbprintf(sb, "%s :: %s\n", d.name, d.value)
        }
    }

    write_string(sb, "\n")

    for ext in registry.extensions {
        fmt.sbprintf(sb, "// %s\n", ext.name)
        for d in ext.commands {
            d := d^
            if opts.remove_gl_prefix do d.name = remove_gl_prefix(d.name)
            fmt.sbprintf(sb, "impl_%s: proc \"c\" (", d.name)
                for param, i in d.params {
                    param := param // this is not needed rn... it's even wrong
                    if opts.remove_gl_prefix do param.name = remove_gl_prefix(param.name)
                    fmt.sbprintf(sb, "%s: %s", param.name, param.type)
                    if i < len(d.params) - 1 {
                        write_string(sb, ", ")
                    }
                }
                write_string(sb, ")")
                if d.return_type != "" {
                    fmt.sbprintf(sb, " -> %s", d.return_type)
                }
                write_string(sb, "\n")
        }
    }

    write_string(sb, "\n")

    for ext in registry.extensions {
        name := ext.name
        if opts.remove_gl_prefix do name = remove_gl_prefix(name)
        fmt.sbprintf(sb, "%s := false\n", name)
    }


    write_string(sb, "\n\n")
    write_string(sb, "// Wrappers\n")

    write_string(sb, "when GL_DEBUG {\n")
    {
        write_string(sb, `
    debug_helper :: proc"c"(from_loc: runtime.Source_Code_Location, num_ret: int, args: ..any, loc := #caller_location) {
        context = runtime.default_context()

        Error_Enum :: enum {
            NO_ERROR = NO_ERROR,
            INVALID_VALUE = INVALID_VALUE,
            INVALID_ENUM = INVALID_ENUM,
            INVALID_OPERATION = INVALID_OPERATION,
            INVALID_FRAMEBUFFER_OPERATION = INVALID_FRAMEBUFFER_OPERATION,
            OUT_OF_MEMORY = OUT_OF_MEMORY,
            STACK_UNDERFLOW = STACK_UNDERFLOW,
            STACK_OVERFLOW = STACK_OVERFLOW,
            // TODO: What if the return enum is invalid?
        }

        // There can be multiple errors, so we're required to continuously call glGetError until there are no more errors
        for i := 0; /**/; i += 1 {
            err := cast(Error_Enum)impl_GetError()
            if err == .NO_ERROR { break }

            fmt.printf("%d: glGetError() returned GL_%v\n", i, err)

            // add function call
            fmt.printf("   call: gl%s(", loc.procedure)
            {
                // add input arguments
                for arg, i in args[num_ret:] {
                if i > 0 { fmt.printf(", ") }

                if v, ok := arg.(u32); ok { // TODO: Assumes all u32 are GLenum (they're not, GLbitfield and GLuint are also mapped to u32), fix later by better typing
                    if err == .INVALID_ENUM {
                        fmt.printf("INVALID_ENUM=%d", v)
                    } else {
                        fmt.printf("GL_%v=%d", GL_Enum(v), v)
                    }
                } else {
                    fmt.printf("%v", arg)
                }
                }

                // add return arguments
                if num_ret == 1 {
                    fmt.printf(") -> %v \n", args[0])
                } else if num_ret > 1 {
                    fmt.printf(") -> (")
                    for arg, i in args[1:num_ret] {
                        if i > 0 { fmt.printf(", ") }
                        fmt.printf("%v", arg)
                    }
                    fmt.printf(")\n")
                } else {
                    fmt.printf(")\n")
                }
            }

            // add location
            fmt.printf("   in:   %s(%d:%d)\n", from_loc.file_path, from_loc.line, from_loc.column)
        }
    }
`)
        for f in registry.features do for d in f.commands {
            d := d^
            if opts.remove_gl_prefix do d.name = remove_gl_prefix(d.name)
            fmt.sbprintf(sb, "    %s :: proc \"c\" (", d.name)
            for param, i in d.params {
                param := param
                if opts.remove_gl_prefix do param.name = remove_gl_prefix(param.name)
                fmt.sbprintf(sb, "%s: %s", param.name, param.type)
                if i < len(d.params) - 1 {
                    write_string(sb, ", ")
                }
            }
            if len(d.params) > 0 {
                write_string(sb, ", loc := #caller_location)")
            } else {
                write_string(sb, "loc := #caller_location)")
            }
            if d.return_type != "" {
                fmt.sbprintf(sb, " -> %s", d.return_type)
            }
            fmt.sbprintf(sb, " {{ ")
            if d.return_type != "" {
                fmt.sbprintf(sb, "ret := impl_%s(", d.name)
            } else {
                fmt.sbprintf(sb, "impl_%s(", d.name)
            }
            for param, i in d.params {
                fmt.sbprintf(sb, "%s", param.name)
                if i < len(d.params) - 1 {
                    write_string(sb, ", ")
                }
            }
            write_string(sb, "); ")
            num_ret := 0 if d.return_type == "" else 1
            fmt.sbprintf(sb, "debug_helper(loc, %d", num_ret)
            if num_ret > 0 {
                write_string(sb, ", ret")
            }
            if len(d.params) == 0 {
                write_string(sb, "); ")
            } else {
                write_string(sb, ", ")
                for param, i in d.params {
                    fmt.sbprintf(sb, "%s", param.name)
                    if i < len(d.params) - 1 {
                        write_string(sb, ", ")
                    }
                }
                write_string(sb, "); ")
            }
            if num_ret > 0 {
                write_string(sb, "return ret")
            }
            write_string(sb, " }\n")
        }
    }
    write_string(sb, "} else {\n")
    {
        for f in registry.features do for d in f.commands {
            d := d^
            if opts.remove_gl_prefix do d.name = remove_gl_prefix(d.name)
            fmt.sbprintf(sb, "    %s :: proc \"c\" (", d.name)
            for param, i in d.params {
                param := param
                if opts.remove_gl_prefix do param.name = remove_gl_prefix(param.name)
                fmt.sbprintf(sb, "%s: %s", param.name, param.type)
                if i < len(d.params) - 1 {
                    write_string(sb, ", ")
                }
            }
            write_string(sb, ")")
            if d.return_type != "" {
                fmt.sbprintf(sb, " -> %s", d.return_type)
            }
            fmt.sbprintf(sb, " {{ ")
            if d.return_type != "" {
                fmt.sbprintf(sb, "return impl_%s(", d.name)
            } else {
                fmt.sbprintf(sb, "impl_%s(", d.name)
            }
            for param, i in d.params {
                fmt.sbprintf(sb, "%s", param.name)
                if i < len(d.params) - 1 {
                    write_string(sb, ", ")
                }
            }
            write_string(sb, ")")
            write_string(sb, " }\n")
        }
    }
    write_string(sb, "}\n")

    write_string(sb, "\n\n")
    write_string(sb, "Set_Proc_Address :: #type proc(p: rawptr, name: cstring)\n\n")

    for ext in registry.extensions {
        name := ext.name
        if opts.remove_gl_prefix do name = remove_gl_prefix(name)
        fmt.sbprintf(sb, "load_%s :: proc(set_proc_address: Set_Proc_Address) {{\n", name)
        for command in ext.commands {
            name := command.name
            if opts.remove_gl_prefix do name = remove_gl_prefix(name)
            fmt.sbprintf(sb, "    set_proc_address(&impl_%s, \"%s\")\n", name, command.name)
        }
        write_string(sb, "}\n\n")
    }
    
    write_string(sb, "load_gl :: proc(set_proc_address: Set_Proc_Address) {\n")

    
    for feature in registry.features {
        fmt.sbprintf(sb, "    // %s\n", feature.name)
        for command in feature.commands {
            name := command.name
            if opts.remove_gl_prefix do name = remove_gl_prefix(name)
            fmt.sbprintf(sb, "    set_proc_address(&impl_%s, \"%s\")\n", name, command.name)
        }
    }

    extensions_enum, num_extensions_enum: string
    glGetStringi_str, glGetIntegerv_str: string
    if opts.remove_gl_prefix {
        extensions_enum = "EXTENSIONS"
        num_extensions_enum = "NUM_EXTENSIONS"
        glGetStringi_str = "impl_GetStringi"
        glGetIntegerv_str = "impl_GetIntegerv"
    } else {
        extensions_enum = "GL_EXTENSIONS"
        num_extensions_enum = "GL_NUM_EXTENSIONS"
        glGetStringi_str = "impl_glGetStringi"
        glGetIntegerv_str = "impl_glGetIntegerv"
    }
    write_string(sb, "\n")
    
    fmt.sbprintf(sb, "    ext_count: i32; %s(%s, &ext_count) // Todo: error handling \n", glGetIntegerv_str, num_extensions_enum)
    
    if len(registry.all_extensions) > 0 {
        fmt.sbprintf(sb, "    Extension_Load_Helper :: struct {{ name: cstring, loaded_ptr: ^bool, load_proc: proc(set_proc_address: Set_Proc_Address)}}\n")
        fmt.sbprintf(sb, "    extensions_wanted := [?]Extension_Load_Helper {{\n")
        for extension in registry.extensions {
            name := extension.name
            if opts.remove_gl_prefix do name = remove_gl_prefix(name)
            fmt.sbprintf(sb, "        {{\"%s\", &%s, load_%s}},\n", extension.name, name, name)
        }
        fmt.sbprintf(sb, "    }\n")
        write_string(sb, "    for i in 0..<ext_count {\n")
        fmt.sbprintf(sb, "        name := %s(%s, cast(u32)i)\n", glGetStringi_str, extensions_enum)
        write_string(sb, "        for &e in extensions_wanted {\n")
        write_string(sb, "            if e.name == name {\n")
        write_string(sb, "                e.loaded_ptr^ = true\n")
        write_string(sb, "                e.load_proc(set_proc_address)\n")
        write_string(sb, "            }\n")
        write_string(sb, "        }\n")
        write_string(sb, "    }\n")
    }

    write_string(sb, "}\n\n")
}
