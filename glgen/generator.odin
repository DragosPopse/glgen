package main
import "core:strings"
import "core:fmt"
import "core:encoding/xml"

generate :: proc(sb: ^strings.Builder, registry: ^GL_Registry, opts: Gen_Options) {
    using strings
    write_string(sb, "package gl\n")
    write_string(sb, "import \"core:c\"\n")
    write_string(sb, "import \"core:builtin\"\n")
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

    for f in registry.features do for d in f.commands {
        d := d^
        if opts.remove_gl_prefix do d.name = remove_gl_prefix(d.name)
        fmt.sbprintf(sb, "%s :: proc \"c\" (", d.name)
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
