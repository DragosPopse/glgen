package main

import "core:fmt"
import "core:encoding/xml"
import "core:os"
import "core:io"
import "core:c"
import "core:strings"

GL_Type :: enum {
    GLEnum,
    GLboolean,
    GLbitfield,
    GLbyte,
    GLubyte,
    GLshort,
    GLushort,
    GLint,
    GLuint,
    GLclampx,
    GLsizei,
    GLfloat,
    GLclampf,
    GLdouble,
    GLclampd,
    GLchar,
    GLcharARB,
    GLhalf,
    GLhalfARB,
    GLfixed,
    GLintptr,
    GLintptrARB,
    GLsizeiptr,
    GLsizeiptrARB,
    GLint64,
    GLint64EXT,
    GLuint64,
    GLuint64EXT,
    GLHalfNV,


    GLvdpauSurfaceNV, // = GLintptr
}

Odin_Type :: enum {
    cint,
    cuint,
    i8,
    u8,
    bool,
    i16,
    u16,
    i32,
    u32,
    i64,
    u64,
    f32,
    f64,
    intptr,
    uintptr,
}

GL_Enum_Type :: enum {
    Normal,
    Bitmask,
}

// Note(Dragos): seems like some enum values are part of multiple groups, so it might be needed to make the groups part of the Enum_Value insetad
GL_Enum_Group :: struct {
    type: GL_Enum_Type,
    name: string,
    values: [dynamic]GL_Enum_Value,
}

GL_Enum_Value :: struct {
    name: string,
    value: string,
    groups: []string, // OpenGL has enums that apply to multiple groups. We might want to handle that eventually
}

string_to_gl_type :: proc(str: string) -> GL_Type {
    switch str {
    case "GLEnum": return .GLEnum
    case "GLboolean": return .GLboolean
    case "GLbitfield": return .GLbitfield
    case "GLbyte": return .GLbyte
    case "GLubyte": return .GLubyte
    case "GLshort": return .GLshort
    case "GLushort": return .GLushort
    case "GLint": return .GLint
    case "GLuint": return .GLuint
    case "GLclampx": return .GLclampx
    case "GLsizei": return .GLsizei
    case "GLfloat": return .GLfloat
    case "GLclampf": return .GLclampf
    case "GLdouble": return .GLdouble
    case "GLclampd": return .GLclampd
    case "GLchar": return .GLchar
    case "GLcharARB": return .GLcharARB
    case "GLhalf": return .GLhalf
    case "GLhalfARB": return .GLhalfARB
    case "GLfixed": return .GLfixed
    case "GLintptr": return .GLintptr
    case "GLintptrARB": return .GLintptrARB
    case "GLsizeiptr": return .GLsizeiptr
    case "GLsizeiptrARB": return .GLsizeiptrARB
    case "GLint64": return .GLint64
    case "GLint64EXT": return .GLint64EXT
    case "GLuint64": return .GLuint64
    case "GLuint64EXT": return .GLuint64EXT
    case "GLHalfNV": return .GLHalfNV
    case "GLvdpauSurfaceNV": return .GLvdpauSurfaceNV
    }
    return nil
}

gl_type_to_odin_type :: proc(gl_type: GL_Type) -> Odin_Type {
    switch gl_type {
    case .GLEnum:           return .cuint
    case .GLboolean:        return .u8
    case .GLbitfield:       return .cuint
    case .GLbyte:           return .i8
    case .GLubyte:          return .u8
    case .GLshort:          return .i16
    case .GLushort:         return .u16
    case .GLint:            return .cint
    case .GLuint:           return .cuint
    case .GLclampx:         return .i32
    case .GLsizei:          return .cint
    case .GLfloat:          return .f32
    case .GLclampf:         return .f32
    case .GLdouble:         return .f64
    case .GLclampd:         return .f64
    case .GLchar:           return .i8
    case .GLcharARB:        return .i8
    case .GLhalf:           return .u16
    case .GLhalfARB:        return .u16
    case .GLfixed:          return .i32
    case .GLintptr, .GLvdpauSurfaceNV: return .intptr
    case .GLintptrARB:      return .intptr
    case .GLsizeiptr:       return .uintptr
    case .GLsizeiptrARB:    return .uintptr
    case .GLint64:          return .i64
    case .GLint64EXT:       return .i64
    case .GLuint64:         return .u64
    case .GLuint64EXT:      return .u64
    case .GLHalfNV:         return .u16
    }
    return nil
}

parse_enums_elem :: proc(doc: ^xml.Document, enums_elem: ^xml.Element) -> (group: GL_Enum_Group) {
    group.type = .Normal
    for attrib in enums_elem.attribs {
        if attrib.key == "group" {
            group.name = attrib.val
        } else if attrib.key == "type" {
            switch attrib.val {
            case "bitmask": group.type = .Bitmask
            }
        }
    }
    // get all <enum> in <enums>
    for id in enums_elem.children {
        enum_elem := &doc.elements[id]
        enum_val: GL_Enum_Value
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
            append(&group.values, enum_val)
        }
    } 
    return group
}

gl_enums: [dynamic]GL_Enum_Group

main :: proc() {
    gl_xml_file := "./OpenGL-Registry/xml/gl.xml"
    doc, err := xml.load_from_file(gl_xml_file)    
    /*
    types := &doc.elements[typelist]
    for t, i in types.children {
        child := doc.elements[t]
        if child.ident == "type" && i == 1 {
            fmt.printf("Type: %#v\n", child)
            name := doc.elements[child.children[0]]
            fmt.printf("Name: %#v\n", name)
        } 
    }
    */

    { // Get enums
        for &node in doc.elements {
            if node.ident == "enums" {
                result := parse_enums_elem(doc, &node)
                append(&gl_enums, result)
            }
        }
    }
    fmt.printf("%#v\n\n", len(gl_enums))
}