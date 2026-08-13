#!/bin/bash

args=()
for arg in "$@"; do
    [[ "$arg" == "-v" ]] || args+=("$arg")
done

exec "${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang" "${args[@]}"
