package main


Gen_Options :: struct {
    use_odin_types: bool, 
    // Note: GLhandleARB will still be needed as it's #ifdef'd 
    gen_debug_helpers: bool, // #config(GL_DEBUG, true) helpers
    gen_enum_types: bool, // Generate distinct types for enum groups
    version: GL_Version,
    remove_gl_prefix: bool,
}