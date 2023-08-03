package main

import "core:fmt"
import "core:encoding/xml"
import "core:os"
import "core:io"
import "core:c"
import "core:strings"
import cfront "core:c/frontend"

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



parse_enums_elem :: proc(state: ^State, doc: ^xml.Document, enums_elem: ^xml.Element) {
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
            }
            if char == '(' || char == ')' {
                is_simple_type = false
                is_function_type = true
                break
            }
        }

        if is_simple_type {
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
            case "intptr": type.odin_type = "intptr"
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
            case "GLVULKANPROCNV":
            case: fmt.panicf("Unhandled special case %v\n", type.name)
            }
        }
        
        if type.name != "khrplatform" {
            gl_defs[type.name] = type
        }
        
        // note(dragos): we should assert that the type.name not_in gl_defs
    }
}

main :: proc() {
    state: State
    gl_xml_file := "./OpenGL-Registry/xml/gl.xml"
    doc, err := xml.load_from_file(gl_xml_file, {flags =
		{.Ignore_Unsupported, .Decode_SGML_Entities}})
    for &element in doc.elements {
        switch element.ident {
        case "types": parse_gl_types(&state, doc, &element)
        case "enums": parse_enums_elem(&state, doc, &element)\
        }
    }

    fmt.printf("%#v\n", state.gl_defs)
}