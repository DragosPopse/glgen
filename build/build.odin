package main

import "core:fmt"
import "../odin-build/build"
import "core:os"
import "core:strings"
import "core:path/filepath"
import "core:c/libc"

Conf_Type :: enum {
    Debug,
    Release,
}

Target :: struct {
    name: string,
    platform: build.Platform,
    conf: Conf_Type,
}
Project :: build.Project(Target)

CURRENT_PLATFORM :: build.Platform{ODIN_OS, ODIN_ARCH}


copy_dll :: proc(config: build.Config) -> int {
    out_dir := filepath.dir(config.out, context.temp_allocator)

    cmd := fmt.tprintf("xcopy /y /i \"%svendor\\sdl2\\SDL2.dll\" \"%s\\SDL2.dll\"", ODIN_ROOT, out_dir)
    return build.syscall(cmd, true)
}

copy_assets :: proc(config: build.Config) -> int {
    out_dir := filepath.dir(config.out, context.temp_allocator)
    src_dir := config.src
    //assets_dir := strings.concatenate({src_dir, "/assets"}, context.temp_allocator)
    assets_dir := "./assets"
    if os.exists(assets_dir) {
        when ODIN_OS == .Windows {
            cmd := fmt.tprintf("xcopy /y /i /s /e \".\\assets\" \"%s\\assets\"", out_dir)
        } else {
            cmd := fmt.tprintf("cp -a \"./assets\" \"%s/assets\"", out_dir)
        }
        
        return build.syscall(cmd, true)
    } else {
        fmt.printf("Couldn't find %s. Ignoring copying assets.\n", assets_dir)
    }

    return 0
}

add_targets :: proc(project: ^Project) {
    build.add_target(project, Target{"deb", CURRENT_PLATFORM, .Debug})
    build.add_target(project, Target{"rel", CURRENT_PLATFORM, .Release})
}


configure_target :: proc(project: Project, target: Target) -> (config: build.Config) {
    config = build.config_make()
 
    config.platform = target.platform
    config.collections["shared"] = strings.concatenate({ODIN_ROOT, "shared"})
    exe_ext := "out"

    switch target.conf {
        case .Debug: {
            config.flags += {.Debug}
            config.optimization = .Minimal
        }

        case .Release: {
            config.optimization = .Speed
            config.flags += {.Disable_Assert, .No_Bounds_Check}
        }
    }
        

   
    config.out = fmt.aprintf("out/%s/RevolverFox.%s", target.name, exe_ext)
    config.src = "./fox"
    config.name = target.name
    config.defines["GL_DEBUG"] = true

    return
}


main :: proc() {
    project: build.Project(Target)
    project.configure_target_proc = configure_target
    options := build.build_options_make_from_args(os.args[1:])
    add_targets(&project)
    build.build_project(project, options)
}