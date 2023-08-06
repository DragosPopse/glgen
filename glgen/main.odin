package main

import "core:fmt"
import "core:encoding/xml"
import "core:os"
import "core:io"
import "core:c"
import "core:strings"
import cfront "core:c/frontend"
import "core:time"



GL_Profile :: enum {
    Compatibility,
    Core,
}

GL_API :: enum {
    GL,
    GLES1,
    GLES2,
    GLX,
    WGL,
}

GL_API_strings := [GL_API]string{
    .GL = "gl",
    .GLES1 = "gles1",
    .GLES2 = "gles2",
    .GLX = "glx",
    .WGL = "wgl",
}

GL_Version :: struct {
    api: GL_API,
    profile: GL_Profile,
    major: int,
    minor: int,
    extensions: map[string]bool,
}



State :: struct {
    opts: Gen_Options,
    registry: GL_Registry,
}

// This should be called in the gen code
remove_gl_prefix :: proc(str: string) -> string {
    if strings.has_prefix(str, "GL_") {
        if str[3] >= '0' && str[3] <= '9' {
            // it starts with a number, so don't remove the underline
            return str[2:]
        }
        return str[3:]
    }
    if strings.has_prefix(str, "GL") || strings.has_prefix(str, "gl") {
        if str[2:] == "enum" do return "Enum"
        return str[2:]
    }
    return str
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
        value, name: string
        groups: []string
        // Mega-Note: It seems that GL_ACTIVE_PROGRAM_EXT has api="gles2", so maybe we can check for those for different APIs. Need to check in the commands code aswell
        // Note: The check is a workaround. See GL_ACTIVE_PROGRAM_EXT. Need a way to handle that speifically for that extension
        defer if definition_exists(&state.registry, name) {
            enum_val := get_registered_enum(&state.registry, name)
            enum_val.type = enum_type
            enum_val.value = value
            enum_val.groups = groups
        }
        if enum_elem.ident == "enum" {
            for attrib in enum_elem.attribs {
                if attrib.key == "value" {
                    value = attrib.val
                } else if attrib.key == "name" {
                    name = attrib.val
                } else if attrib.key == "group" {
                    groups = strings.split(attrib.val, ",")
                }
            }
        }
    } 
}

parse_gl_types :: proc(state: ^State, doc: ^xml.Document, types_elem: ^xml.Element) {
    using state
    main_loop: for value in types_elem.value {
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
            case "unsigned int": type.odin_type = "builtin.u32"
            case "int": type.odin_type = "builtin.i32"
            case "short": type.odin_type = "builtin.i16"
            case "unsigned short": type.odin_type = "builtin.u16"
            case "unsigned char": type.odin_type = "builtin.u8"
            case "char": type.odin_type = "builtin.i8"
            case "void": type.odin_type = "void" // this should be invalid
            case "void*", "void *": type.odin_type = "rawptr"
            case "float": type.odin_type = "builtin.f32"
            case "double": type.odin_type = "builtin.f64"
            case "int8": type.odin_type = "builtin.i8"
            case "uint8": type.odin_type = "builtin.u8"
            case "int16": type.odin_type = "builtin.i16"
            case "uint16": type.odin_type = "builtin.u16"
            case "int32": type.odin_type = "builtin.i32"
            case "uint32": type.odin_type = "builtin.u32"
            case "int64": type.odin_type = "builtin.i64"
            case "uint64": type.odin_type = "builtin.u64"
            case "intptr": type.odin_type = "builtin.int"
            case "uintptr": type.odin_type = "builtin.uintptr"
            case "ssize": type.odin_type = "builtin.int" // is this correct?
            case:
                if strings.contains(c_type, "struct") {
                    type.odin_type = "rawptr"
                } else {
                    type.odin_type = c_type
                }
            }
            if type.name == "GLboolean" do type.odin_type = "bool"
        } else {
            // handle special cases to save sanity
            switch type.name {
            case "GLDEBUGPROC": type.odin_type = `#type proc "c" (source, type: Enum, id: uint, category: Enum, severity: Enum, length: sizei, message: cstring, userParam: rawptr)`
            case "GLDEBUGPROCARB": type.odin_type = `#type proc "c" (source, type: Enum, id: uint, category: Enum, severity: Enum, length: sizei, message: cstring, userParam: rawptr)`
            case "GLDEBUGPROCKHR": type.odin_type = `#type proc "c" (source, type: Enum, id: uint, category: Enum, severity: Enum, length: sizei, message: cstring, userParam: rawptr)`
            case "GLDEBUGPROCAMD": type.odin_type = `#type proc "c" (id: uint, category: Enum, severity: Enum, length: sizei, message: cstring, userParam: rawptr)`
            case "GLhandleARB": type.odin_type = `builtin.u32 when ODIN_OS != .Darwin else rawptr`
            case "khrplatform": // this is nonsense
            case "GLVULKANPROCNV": type.odin_type = `#type proc() // undefined`
            case: fmt.panicf("Unhandled special case %v\n", type.name)
            }
        }
        
        if type.name != "khrplatform" && type.c_type != "void" {
            //type.name = remove_gl_prefix(type.name)
            //if type.name == "enum" do type.name = "Enum" 
            //gl_type := registry_new_def(&state.registry, type.name, GL_Type)
            //gl_type^ = type
            gl_type := new(GL_Type)
            gl_type^ = type
            registry.all_defs[gl_type.name] = gl_type
            append(&registry.types, gl_type)
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
            if definition_exists(&state.registry, command.name) {
                gl_command := get_registered_command(&state.registry, command.name)
                gl_command^ = command
            }
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
                name = (elem.value[0].(string))
            } else if elem.ident == "ptype" {
                concat_type = strings.concatenate({concat_type, elem.value[0].(string)})
            }
        }
    }
    concat_type = strings.trim_space(concat_type)
    // This method of type parsing is quite empirical, it's not fully correct, but it seems to work with the current registry
    if concat_type != "void" {
        //return_type = concat_type
        switch concat_type {
        case "void*", "void *", "GLvoid*", "GLvoid *":
            return_type = "rawptr"
        case:
            is_const := false
            is_ptr := false
            is_string := false // we still got issues with strings
            if strings.contains(concat_type, "*") {
                is_ptr = true
                concat_type, _ = strings.remove(concat_type, "*", 1)
            }
            if strings.contains(concat_type, "const") {
                is_const = true
                concat_type, _ = strings.remove_all(concat_type, "const")
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
            
            if state.opts.remove_gl_prefix { // this mf shouldn't be here
                concat_type = remove_gl_prefix(concat_type)
                if concat_type == "enum" do concat_type = "Enum"
            }
            
            if is_string {
                return_type = "cstring"
            } else if is_ptr {
                return_type = strings.concatenate({"^", concat_type}) 
            } else {
                return_type = concat_type
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
            // Scuffed way to handle some keywords
            if param.name == "map" do param.name = "_map" // slight workaround
            else if param.name == "in" do param.name = "_in"
            else if param.name == "matrix" do param.name = "_matrix"
            else if param.name == "context" do param.name = "_context"
        }
    }

    concat_type = strings.trim_space(concat_type)
    if concat_type != "void" {
        switch param.type {
        //case "void*", "void *":
            //param.type = "rawptr"
        case:
            is_const := false
            ptr_count := 0
            is_string := false
            if ptr_count = strings.count(concat_type, "*"); ptr_count > 0 {
                concat_type, _ = strings.remove(concat_type, "*", ptr_count)
            }
            if strings.contains(concat_type, "const") {
                is_const = true
                concat_type, _ = strings.remove_all(concat_type, "const")
            }
            if ptr_count > 0 && is_const && (concat_type == "GLubyte" || concat_type == "GLchar") { // TODO handle [^]cstring
                is_string = true
            }
            for attrib in param_elem.attribs {
                if attrib.key == "kind" && attrib.val == "String" {
                    is_string = true
                }
            }
            
            concat_type = strings.trim_space(concat_type)
            if state.opts.remove_gl_prefix { // This shouldn't be here, but it's easier
                concat_type = remove_gl_prefix(concat_type)
                if concat_type == "enum" do concat_type = "Enum"
            }
            if strings.contains(concat_type, "struct") { // Todo: Make a special type for these
                param.type = "rawptr"
            } else if is_string {
                param.type = ""
                ptr_count -= 1
                for in 0..<ptr_count {
                    param.type = strings.concatenate({param.type, "[^]"})
                }
                param.type = strings.concatenate({param.type, "cstring"})
            } else if ptr_count > 0 {
                param.type = ""
                if strings.contains(concat_type, "void") {
                    ptr_count -= 1
                    concat_type = "rawptr"
                }
                for in 0..<ptr_count {
                    param.type = strings.concatenate({param.type, "[^]"})
                }
                param.type = strings.concatenate({param.type, concat_type}) 
            } else {
                param.type = concat_type
            }
        }
    }
    return param
}








main :: proc() {
    context.allocator = context.temp_allocator
    state: State
    {
        using state
        opts.use_odin_types = true
        opts.version.major = 4
        opts.version.minor = 6
        opts.version.profile = .Core
        opts.remove_gl_prefix = true
    }
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
    register_features_and_extensions(doc, &state.registry, state.opts.version)
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
    
    
    time.stopwatch_reset(&clock)
    time.stopwatch_start(&clock)
    file, ok := os.open("gl.odin", os.O_CREATE | os.O_TRUNC | os.O_WRONLY)
    sb := strings.builder_make()
    generate(&sb, &state.registry, state.opts)
    os.write_string(file, strings.to_string(sb))
    time.stopwatch_stop(&clock)
    def_gen_duration := time.stopwatch_duration(clock)
    fmt.printf("gl.odin Generation: %v ms\n", time.duration_milliseconds(def_gen_duration))
}