package main
import "core:strings"
import "core:fmt"
import "core:encoding/xml"

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

register_extension_enum :: proc(registry: ^GL_Registry, extension_name: string, def_name: string) {
    fmt.assertf(def_name not_in registry.all_defs, "%v enum is already registered", def_name)
    fmt.assertf(extension_name in registry.all_extensions, "%v feature does not exist", extension_name)
    extension := registry.all_extensions[extension_name]
    e := new(GL_Enum_Value)
    e.name = def_name
    registry.all_defs[def_name] = e
    append(&extension.enums, e)
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

register_extension_command :: proc(registry: ^GL_Registry, extension_name: string, def_name: string) {
    fmt.assertf(def_name not_in registry.all_defs, "%v command already exists", def_name)
    fmt.assertf(extension_name in registry.all_features, "%v feature doesn't exist", extension_name)
    extension := registry.all_extensions[extension_name]
    c := new(GL_Command)
    c.name = def_name
    registry.all_defs[def_name] = c
    append(&extension.commands, c)
}


// Note: The feature_name is not really needed here, it's dumb
// Note: we'll loop only through the features, since the extensions don't seem to have remove tags
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

register_features_and_extensions :: proc(doc: ^xml.Document, registry: ^GL_Registry, version: GL_Version) {
    //features_to_remove: [dynamic]string // We'll remove them at the end in case parsing doesn't happen in order
    
    versions_loop: for feat_elem in doc.elements do if feat_elem.ident == "feature" {
        api, name, number: string
        for attrib in feat_elem.attribs {
            switch attrib.key {
            case "api": api = attrib.val
            case "name": name = attrib.val
            case "number": number = attrib.val
            }
        }
        if api != GL_API_strings[version.api] do continue versions_loop
        major, minor := parse_gl_version(number)
        features_profile: Maybe(GL_Profile)
        if version.major < major do continue
        if version.minor < minor do continue
        register_feature(registry, name, major, minor)
        features_loop: for tag_id in feat_elem.value do if tag_id, is_tag := tag_id.(xml.Element_ID); is_tag {
            if require_tag := doc.elements[tag_id]; require_tag.ident == "require" {
                profile_str: string
                for attrib in require_tag.attribs do if attrib.key == "profile" {
                    profile_str = attrib.val
                }
                if profile_str == "compatibility" && version.profile == .Core {
                    continue features_loop
                }
                for tag_id in require_tag.value do if tag_id, is_tag := tag_id.(xml.Element_ID); is_tag {
                    feature_tag := doc.elements[tag_id]
                    if feature_tag.ident == "enum" || feature_tag.ident == "command" { // we ignore <type> since it's goofy anyway
                        for attrib in feature_tag.attribs do if attrib.key == "name" {
                            def_name := attrib.val
                            if !definition_exists(registry, def_name) {
                                if feature_tag.ident == "enum" {
                                    register_feature_enum(registry, name, def_name)
                                } else if feature_tag.ident == "command" {
                                    register_feature_command(registry, name, def_name)
                                }
                            }
                        }
                    }
                }
            } else if remove_tag := doc.elements[tag_id]; remove_tag.ident == "remove" {
                profile_str: string
                for attrib in remove_tag.attribs do if attrib.key == "profile" {
                    profile_str = attrib.val
                }
                if !(profile_str == "core" && version.profile == .Core || profile_str == "compatibility" && version.profile == .Compatibility) {
                    continue features_loop
                }
                for tag_id in remove_tag.value do if tag_id, is_tag := tag_id.(xml.Element_ID); is_tag {
                    feature_tag := doc.elements[tag_id]
                    if feature_tag.ident == "enum" || feature_tag.ident == "command" {
                        for attrib in feature_tag.attribs do if attrib.key == "name" {
                            def_name := attrib.val
                            if definition_exists(registry, def_name) {
                                if feature_tag.ident == "enum" {
                                    remove_enum(registry, name, def_name)
                                } else if feature_tag.ident == "command" {
                                    remove_command(registry, name, def_name)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    extensions_loop: for extension_element in doc.elements do if extension_element.ident == "extension" { 
        supported, name: string
        for attrib in extension_element.attribs {
            switch attrib.key {
            case "name": name = attrib.val
            case "supported": supported = attrib.val
            }
        }
        supported_apis := strings.split(supported, "|")
        found_gl := false
        for api in supported_apis {
            api := strings.trim_space(api)
            if api == "gl" {
                found_gl = true
                break
            }
        }
        if name not_in version.extensions do continue
        if !found_gl do continue extensions_loop
        register_extension(registry, name)
        requires_loop: for v in extension_element.value do if tag_id, is_tag := v.(xml.Element_ID); is_tag {
            require_tag := doc.elements[tag_id]
            if require_tag.ident != "require" do continue requires_loop
            for v in require_tag.value do if tag_id, is_tag := v.(xml.Element_ID); is_tag {
                tag := doc.elements[tag_id]
                require_name: string
                for attrib in tag.attribs {
                    if attrib.key == "name" do require_name = name
                }
                switch tag.ident {
                case "enum":
                    register_extension_enum(registry, name, require_name)
                case "command":
                    register_extension_command(registry, name, require_name)
                }
            }
        }
    }
}