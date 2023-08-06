package main
import "core:encoding/xml"
import "core:fmt"

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
}