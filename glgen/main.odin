package main

import "core:fmt"
import "core:encoding/xml"
import "core:os"
import "core:io"
import "core:c"
import "core:strings"
import cfront "core:c/frontend"
import "core:time"

GL_Type :: struct {
    name: string,
    c_type: string,
    odin_type: string, // to be determined from c_type
}

GL_Enum_Type :: enum {
    Normal,
    Bitmask,
}

GL_Enum_Value :: struct {
    name: string,
    type: GL_Enum_Type,
    value: string,
    groups: []string, // OpenGL has enums that apply to multiple groups. We might want to handle that eventually
}

GL_Command_Param :: struct {
    name: string,
    type: string,
}

GL_Command :: struct {
    name: string,
    return_type: string,
    params: [dynamic]GL_Command_Param,    
}

GL_Def :: union {
    GL_Type,
    GL_Command,
    GL_Enum_Value,
}

State :: struct {
    gl_defs: map[string]GL_Def,
}



parse_gl_enums :: proc(state: ^State, doc: ^xml.Document, enums_elem: ^xml.Element) {
    enum_type: GL_Enum_Type = .Normal
    for attrib in enums_elem.attribs {
        if attrib.key == "type" {
            switch attrib.val {
            case "bitmask": enum_type = .Bitmask
            }
        }
    }
    // get all <enum> in <enums>
    for value in enums_elem.value {
        id := value.(xml.Element_ID)
        enum_elem := &doc.elements[id]
        enum_val: GL_Enum_Value
        defer state.gl_defs[enum_val.name] = enum_val
        enum_val.type = enum_type
        if enum_elem.ident == "enum" {
            for attrib in enum_elem.attribs {
                if attrib.key == "value" {
                    enum_val.value = attrib.val
                } else if attrib.key == "name" {
                    enum_val.name = attrib.val
                } else if attrib.key == "group" {
                    enum_val.groups = strings.split(attrib.val, ",")
                }
            }
        }
    } 
}

parse_gl_types :: proc(state: ^State, doc: ^xml.Document, types_elem: ^xml.Element) {
    using state
    for value in types_elem.value {
        type_elem_id := value.(xml.Element_ID)
        type_elem := doc.elements[type_elem_id]
        type: GL_Type
        found_name_attrib := false
        for attrib in type_elem.attribs {
            if attrib.key == "name" {
                found_name_attrib = true
                type.name = attrib.val
            }
        }

        concatenated_c_type: string
        for value, i in type_elem.value {
            switch val in value {
            case string:
                concatenated_c_type = strings.concatenate({concatenated_c_type, val})
                
            case xml.Element_ID:
                e := doc.elements[val]
                if e.ident == "name" {
                    type.name = e.value[0].(string)
                }
            }
        }

        type.c_type = concatenated_c_type
        // make sense of the c_type
        c_type, _ := strings.remove(type.c_type, "typedef", 1)
        c_type, _ = strings.remove(c_type, ";", 1) 
        c_type = strings.trim_space(c_type)
        is_simple_type := true
        is_nonsense_type := false
        is_function_type := false
        for char in c_type {
            if char == '#' {
                is_nonsense_type = true
                is_simple_type = false
                break
            } else if char == '(' || char == ')' {
                is_simple_type = false
                is_function_type = true
                break
            }
        }

        if is_simple_type {
            c_type, _ = strings.remove(c_type, "typedef", 1)
            c_type = strings.trim_prefix(c_type, "khronos_")
            c_type = strings.trim_suffix(c_type, "_t")
            switch c_type {
            case "unsigned int": type.odin_type = "u32"
            case "int": type.odin_type = "i32"
            case "short": type.odin_type = "i16"
            case "unsigned short": type.odin_type = "u16"
            case "unsigned char": type.odin_type = "u8"
            case "char": type.odin_type = "i8"
            case "void": type.odin_type = "void" // this should be invalid
            case "void*", "void *": type.odin_type = "rawptr"
            case "float": type.odin_type = "f32"
            case "double": type.odin_type = "f64"
            case "int8": type.odin_type = "i8"
            case "uint8": type.odin_type = "u8"
            case "int16": type.odin_type = "i16"
            case "uint16": type.odin_type = "u16"
            case "int32": type.odin_type = "i32"
            case "uint32": type.odin_type = "u32"
            case "int64": type.odin_type = "i64"
            case "uint64": type.odin_type = "u64"
            case "intptr": type.odin_type = "int"
            case "uintptr": type.odin_type = "uintptr"
            case "ssize": type.odin_type = "int" // is this correct?
            case:
                if strings.contains(c_type, "struct") {
                    type.odin_type = "rawptr"
                } else {
                    type.odin_type = c_type
                }
            }
        } else {
            // handle special cases to save sanity
            switch type.name {
            case "GLDEBUGPROC": type.odin_type = `#type proc "c" (source, type: GLEnum, id: GLuint, category: GLenum, severity: GLEnum, length: GLsizei, message: cstring, userParam: rawptr)`
            case "GLDEBUGPROCARB": type.odin_type = `#type proc "c" (source, type: GLEnum, id: GLuint, category: GLenum, severity: GLEnum, length: GLsizei, message: cstring, userParam: rawptr)`
            case "GLDEBUGPROCKHR": type.odin_type = `#type proc "c" (source, type: GLEnum, id: GLuint, category: GLenum, severity: GLEnum, length: GLsizei, message: cstring, userParam: rawptr)`
            case "GLDEBUGPROCAMD": type.odin_type = `#type proc "c" (id: GLuint, category: GLenum, severity: GLEnum, length: GLsizei, message: cstring, userParam: rawptr)`
            case "GLhandleARB": type.odin_type = `u32 when ODIN_OS != .darwin else rawptr`
            case "khrplatform": // this is nonsense
            case "GLVULKANPROCNV": type.odin_type = `nil`
            case: fmt.panicf("Unhandled special case %v\n", type.name)
            }
        }
        
        if type.name != "khrplatform" {
            gl_defs[type.name] = type
        }
        
        // note(dragos): we should assert that the type.name not_in gl_defs
    }
}

parse_gl_commands :: proc(state: ^State, doc: ^xml.Document, element: ^xml.Element) {
    for value in element.value {
        command_elem_id := value.(xml.Element_ID)
        command_elem := &doc.elements[command_elem_id]
        if command_elem.ident == "command" {
            command := parse_gl_command(state, doc, command_elem)
            state.gl_defs[command.name] = command
        }
    }
}

parse_gl_command :: proc(state: ^State, doc: ^xml.Document, element: ^xml.Element) -> (command: GL_Command) {
    for value in element.value {
        tag_id := value.(xml.Element_ID)
        tag := &doc.elements[tag_id]
        switch tag.ident {
        case "proto": 
            command.name, command.return_type = parse_gl_command_proto(state, doc, tag)        
        case "param":
            append(&command.params, parse_gl_command_param(state, doc, tag))
        }
    }
    return command
}

parse_gl_command_proto :: proc(state: ^State, doc: ^xml.Document, proto: ^xml.Element) -> (name, return_type: string) {
    concat_type: string
    for value, i in proto.value {
        switch v in value {
        case string:
            concat_type = strings.concatenate({concat_type, v, " "})
        case xml.Element_ID:
            elem := doc.elements[v]
            if elem.ident == "name" {
                name = elem.value[0].(string)
            } else if elem.ident == "ptype" {
                concat_type = strings.concatenate({concat_type, elem.value[0].(string)})
            }
        }
    }
    concat_type = strings.trim_space(concat_type)
    // This method of type parsing is quite empirical, it's not fully correct, but it seems to work with the current registry
    if concat_type != "void" {
        return_type = concat_type
        switch return_type {
        case "void*", "void *":
            return_type = "rawptr"
        case:
            is_const := false
            is_ptr := false
            is_string := false
            if strings.contains(concat_type, "*") {
                is_ptr = true
                concat_type, _ = strings.remove(concat_type, "*", 1)
            }
            if strings.contains(concat_type, "const") {
                is_const = true
                concat_type, _ = strings.remove(concat_type, "const", 1)
            }
            if is_ptr && is_const && concat_type == "GLubyte" {
                is_string = true
            }
            for attrib in proto.attribs {
                if attrib.key == "kind" && attrib.val == "String" {
                    is_string = true
                }
            }
            concat_type = strings.trim_space(concat_type)
            if is_string {
                return_type = "cstring"
            } else if is_ptr {
                return_type = strings.concatenate({"^", concat_type}) 
            }
        }
    }
    return name, return_type
}

// This code is duplicated from parse_gl_command_proto. Refactor later.
parse_gl_command_param :: proc(state: ^State, doc: ^xml.Document, param_elem: ^xml.Element) -> (param: GL_Command_Param) {
    concat_type: string
    for value, i in param_elem.value {
        switch v in value {
        case string:
            concat_type = strings.concatenate({concat_type, v, " "})
        case xml.Element_ID:
            elem := doc.elements[v]
            if elem.ident == "name" {
                param.name = elem.value[0].(string)
            } else if elem.ident == "ptype" {
                concat_type = strings.concatenate({concat_type, elem.value[0].(string)})
            }
            if param.name == "map" do param.name = "_map" // slight workaround
        }
    }

    concat_type = strings.trim_space(concat_type)
    if concat_type != "void" {
        param.type = concat_type
        switch param.type {
        case "void*", "void *":
            param.type = "rawptr"
        case:
            is_const := false
            ptr_count := 0
            is_string := false
            if ptr_count = strings.count(concat_type, "*"); ptr_count > 0 {
                concat_type, _ = strings.remove(concat_type, "*", ptr_count)
            }
            if strings.contains(concat_type, "const") {
                is_const = true
                concat_type, _ = strings.remove(concat_type, "const", 1)
            }
            if ptr_count == 1 && is_const && concat_type == "GLubyte" { // TODO handle [^]cstring
                is_string = true
            }
            for attrib in param_elem.attribs {
                if attrib.key == "kind" && attrib.val == "String" {
                    is_string = true
                }
            }
            concat_type = strings.trim_space(concat_type)
            if is_string {
                param.type = "cstring"
            } else if ptr_count > 0 {
                for in 0..<ptr_count {
                    param.type = strings.concatenate({param.type, "^"})
                }
                param.type = strings.concatenate({param.type, concat_type}) 
            }
        }
    }
    return param
}

generate_gl_def :: proc(state: ^State) -> (result: string) {
    using strings
    sb := strings.builder_make()
    write_string(&sb, "package gl\n")
    write_string(&sb, "import \"core:c\"\n")
    write_string(&sb, "\n")

    for name, def in state.gl_defs do if d, ok := def.(GL_Type); ok {
        if strings.contains(name, "struct") do continue // Rework
        fmt.sbprintf(&sb, "%s :: %s\n", d.name, d.odin_type)
    }

    write_string(&sb, "\n")

    for name, def in state.gl_defs do if d, ok := def.(GL_Enum_Value); ok {
        if name == "" do continue // This shouldn't be here... but it seems something is wrong somewhere in parsing
        fmt.sbprintf(&sb, "%s :: %s\n", d.name, d.value)
    }

    write_string(&sb, "\n")

    for name, def in state.gl_defs do if d, ok := def.(GL_Command); ok {
        fmt.sbprintf(&sb, "impl_%s: proc \"c\"(", d.name)
            for param, i in d.params {
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

    return strings.to_string(sb)
}

main :: proc() {
    context.allocator = context.temp_allocator
    state: State
    gl_xml_file := "./OpenGL-Registry/xml/gl.xml"
    clock: time.Stopwatch
    time.stopwatch_start(&clock)
    doc, err := xml.load_from_file(gl_xml_file, {flags =
		{.Ignore_Unsupported, .Decode_SGML_Entities}})
    time.stopwatch_stop(&clock)
    xml_load_duration := time.stopwatch_duration(clock)
    fmt.printf("XML Parse: %v ms\n", time.duration_milliseconds(xml_load_duration))
    
    time.stopwatch_reset(&clock)
    time.stopwatch_start(&clock)
    for &element in doc.elements {
        switch element.ident {
        case "types": parse_gl_types(&state, doc, &element)
        case "enums": parse_gl_enums(&state, doc, &element)
        case "commands": parse_gl_commands(&state, doc, &element)
        }
    }
    time.stopwatch_stop(&clock)
    def_parse_duration := time.stopwatch_duration(clock)
    fmt.printf("GL Definition Parse: %v ms\n", time.duration_milliseconds(def_parse_duration))
    
    file, ok := os.open("gl.odin", os.O_CREATE | os.O_TRUNC | os.O_WRONLY)
    
    gen := generate_gl_def(&state)
    os.write_string(file, gen)
}