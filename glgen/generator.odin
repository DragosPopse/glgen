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
    
    write_string(sb, "load_gl :: proc(set_proc_address: Set_Proc_Address) {\n")
    
    for feature in registry.features {
        fmt.sbprintf(sb, "    // %s\n", feature.name)
        for command in feature.commands {
            name := command.name
            if opts.remove_gl_prefix do name = remove_gl_prefix(name)
            fmt.sbprintf(sb, "    set_proc_address(impl_%s, \"%s\")\n", name, command.name)
        }
    }
    write_string(sb, "}\n\n")
}

generate_gl_def :: proc(state: ^State) -> (result: string) {
    using strings
    sb := strings.builder_make()
    write_string(&sb, "package gl\n")
    write_string(&sb, "import \"core:c\"\n")
    write_string(&sb, "import \"core:builtin\"\n")
    write_string(&sb, "\n")

    for d in state.registry.types {
        if strings.contains(d.name, "struct") || d.name == "GLvoid" || d.name == "void" do continue // Rework
        d := d^
        if state.opts.remove_gl_prefix do d.name = remove_gl_prefix(d.name)
        if definition_exists(&state.registry, d.odin_type) && state.opts.remove_gl_prefix do d.odin_type = remove_gl_prefix(d.odin_type)
        fmt.sbprintf(&sb, "%s :: %s\n", d.name, d.odin_type)
    }

    write_string(&sb, "\n")

    for f in state.registry.features {
        fmt.sbprintf(&sb, "// %s\n", f.name)
        for d in f.enums {
            if d.name == "" do continue // This shouldn't be here... but it seems something is wrong somewhere in parsing
            d := d^
            if state.opts.remove_gl_prefix do d.name = remove_gl_prefix(d.name)
            fmt.sbprintf(&sb, "%s :: %s\n", d.name, d.value)
        }
    }

    write_string(&sb, "\n")

    for f in state.registry.features {
        fmt.sbprintf(&sb, "// %s\n", f.name)
        for d in f.commands {
            d := d^
            if state.opts.remove_gl_prefix do d.name = remove_gl_prefix(d.name)
            fmt.sbprintf(&sb, "impl_%s: proc \"c\" (", d.name)
                for param, i in d.params {
                    param := param // this is not needed rn...
                    if state.opts.remove_gl_prefix do param.name = remove_gl_prefix(param.name)
                    fmt.sbprintf(&sb, "%s: %s", param.name, param.type)
                    if i < len(d.params) - 1 {
                        write_string(&sb, ", ")
                    }
                }
                write_string(&sb, ")")
                if d.return_type != "" {
                    fmt.sbprintf(&sb, " -> %s", d.return_type)
                }
                write_string(&sb, "\n")
        }
    }

    write_string(&sb, "\n\n")
    write_string(&sb, "// Wrappers\n")

    for f in state.registry.features do for d in f.commands {
        d := d^
        if state.opts.remove_gl_prefix do d.name = remove_gl_prefix(d.name)
        fmt.sbprintf(&sb, "%s :: proc \"c\" (", d.name)
        for param, i in d.params {
            param := param
            if state.opts.remove_gl_prefix do param.name = remove_gl_prefix(param.name)
            fmt.sbprintf(&sb, "%s: %s", param.name, param.type)
            if i < len(d.params) - 1 {
                write_string(&sb, ", ")
            }
        }
        write_string(&sb, ")")
        if d.return_type != "" {
            fmt.sbprintf(&sb, " -> %s", d.return_type)
        }
        fmt.sbprintf(&sb, " {{ ")
        if d.return_type != "" {
            fmt.sbprintf(&sb, "return impl_%s(", d.name)
        } else {
            fmt.sbprintf(&sb, "impl_%s(", d.name)
        }
        for param, i in d.params {
            fmt.sbprintf(&sb, "%s", param.name)
            if i < len(d.params) - 1 {
                write_string(&sb, ", ")
            }
        }
        write_string(&sb, ")")
        write_string(&sb, " }\n")
        
    }

    write_string(&sb, "\n\n")
    write_string(&sb, "Set_Proc_Address :: #type proc(p: rawptr, name: cstring)\n\n")
    
    write_string(&sb, "load_gl :: proc(set_proc_address: Set_Proc_Address) {\n")
    using state
    for feature in registry.features {
        fmt.sbprintf(&sb, "    // %s\n", feature.name)
        for command in feature.commands {
            name := command.name
            if opts.remove_gl_prefix do name = remove_gl_prefix(name)
            fmt.sbprintf(&sb, "    set_proc_address(impl_%s, \"%s\")\n", name, command.name)
        }
    }
    write_string(&sb, "}\n\n")

    return strings.to_string(sb)
}