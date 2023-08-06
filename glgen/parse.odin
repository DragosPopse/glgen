package main
import "core:encoding/xml"
import "core:fmt"
import "core:strings"

parse_gl_version :: proc(v: string) -> (major, minor: int) {
    versions := strings.split(v, ".")
    major = int(versions[0][0] - '0')
    minor = int(versions[1][0] - '0')
    return major, minor
}