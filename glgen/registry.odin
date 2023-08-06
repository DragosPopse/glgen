package main
import "core:strings"
import "core:fmt"

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
    ^GL_Type,
    ^GL_Command,
    ^GL_Enum_Value,
}

GL_Feature :: struct {
    major, minor: int,
    major_minor: int, // major * 10 + minor
    name: string,
    enums: [dynamic]^GL_Enum_Value,
    commands: [dynamic]^GL_Command,
}

GL_Extension :: struct {
    name: string,
    enums: [dynamic]^GL_Enum_Value,
    commands: [dynamic]^GL_Command,
}

// The definitions are added only by name first, then def types are resolved later
// GL_Type is not part of the feature set (for now at least), since they are already quite goofy
GL_Registry :: struct {
    all_defs: map[string]GL_Def,
    all_features: map[string]^GL_Feature,
    all_extensions: map[string]^GL_Extension,
    types: [dynamic]^GL_Type,
    features: [dynamic]^GL_Feature,
    extensions: [dynamic]^GL_Extension,
}

definition_exists :: proc(registry: ^GL_Registry, name: string) -> bool {
    return name in registry.all_defs
}

register_feature :: proc(registry: ^GL_Registry, feature_name: string, major, minor: int) {
    fmt.assertf(feature_name not_in registry.all_features, "%v feature is already registered", feature_name)
    feature := new(GL_Feature)
    feature.name = feature_name
    feature.major = major
    feature.minor = minor
    feature.major_minor = major * 10 + minor
    registry.all_features[feature_name] = feature
    append(&registry.features, feature)
}

register_extension :: proc(registry: ^GL_Registry, extension_name: string) {
    assert(extension_name not_in registry.all_extensions)
    extension := new(GL_Extension)
    extension.name = extension_name
    registry.all_extensions[extension_name] = extension
    append(&registry.extensions, extension)
}

register_feature_enum :: proc(registry: ^GL_Registry, feature_name: string, def_name: string) {
    fmt.assertf(def_name not_in registry.all_defs, "%v enum is already registered", def_name)
    fmt.assertf(feature_name in registry.all_features, "%v feature does not exist", feature_name)
    feature := registry.all_features[feature_name]
    e := new(GL_Enum_Value)
    e.name = def_name
    registry.all_defs[def_name] = e
    append(&feature.enums, e)
}

register_feature_command :: proc(registry: ^GL_Registry, feature_name: string, def_name: string) {
    fmt.assertf(def_name not_in registry.all_defs, "%v command already exists", def_name)
    fmt.assertf(feature_name in registry.all_features, "%v feature doesn't exist", feature_name)
    feature := registry.all_features[feature_name]
    c := new(GL_Command)
    c.name = def_name
    registry.all_defs[def_name] = c
    append(&feature.commands, c)
}

remove_enum :: proc(registry: ^GL_Registry, feature_name: string, def_name: string) {
    fmt.assertf(def_name in registry.all_defs, "%v enum does not exist for removal", def_name)
    fmt.assertf(feature_name in registry.all_features, "%v feature does not exist", feature_name)
    //feature := registry.all_features[feature_name]
    index := -1
    f_index := -1
    for feature, j in registry.features {
        for e, i in feature.enums {
            if e.name == def_name {
                index = i
                f_index = j
                break
            }
        }
    }
    fmt.assertf(index >= 0 && f_index >= 0, "%v enum was not found for removal", def_name)
    feature := registry.features[f_index]
    ordered_remove(&feature.enums, index)
    delete_key(&registry.all_defs, def_name)
}

remove_command :: proc(registry: ^GL_Registry, feature_name: string, def_name: string) {
    fmt.assertf(def_name in registry.all_defs, "%v command does not exist for removal", def_name)
    fmt.assertf(feature_name in registry.all_features, "%v feature does not exist", feature_name)
    index := -1
    f_index := -1
    for feature, j in registry.features {
        for e, i in feature.commands {
            if e.name == def_name {
                index = i
                f_index = j
                break
            }
        }
    }
    fmt.assertf(index >= 0 && f_index >= 0, "%v command was not found for removal", def_name)
    feature := registry.features[f_index]
    ordered_remove(&feature.commands, index)
    delete_key(&registry.all_defs, def_name)
}

get_registered_enum :: proc(registry: ^GL_Registry, name: string) -> ^GL_Enum_Value {
    if name not_in registry.all_defs do return nil
    return registry.all_defs[name].(^GL_Enum_Value) or_else nil
}

get_registered_command :: proc(registry: ^GL_Registry, name: string) -> ^GL_Command {
    if name not_in registry.all_defs do return nil
    return registry.all_defs[name].(^GL_Command) or_else nil
}

