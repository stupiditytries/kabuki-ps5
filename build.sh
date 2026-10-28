#!/usr/bin/env bash
# Builds build/kabuki-ps5.elf: the payload, with Kabuki's ShellUI worker embedded in it.
#
#   ./build.sh          a normal build
#   ./build.sh --dev    development only: the new build replaces a running one without a reboot
#                       (see docs/DEVELOPING.md); never hand a --dev build to anyone else
#
# Needs the PS5 Payload SDK (PS5_PAYLOAD_SDK, default /opt/ps5-payload-sdk) and the pinned
# dependencies (python3 tools/fetch-deps.py).
set -euo pipefail
repo=$(cd "$(dirname "$0")" && pwd)
if [[ -z ${PS5_PAYLOAD_SDK:-} && -f "$repo/.local/build-env.sh" ]]; then
    source "$repo/.local/build-env.sh"
fi
sdk=${PS5_PAYLOAD_SDK:-/opt/ps5-payload-sdk}
dev=0
for arg in "$@"; do
    case $arg in
        --dev) dev=1 ;;
        *) echo "Usage: build.sh [--dev]" >&2; exit 2 ;;
    esac
done
json="$repo/.deps/nlohmann/include"
if [[ ! -f $json/nlohmann/json.hpp ]]; then
    echo "Missing dependencies: run python3 tools/fetch-deps.py" >&2
    exit 1
fi
out="$repo/build/kabuki"
mkdir -p "$out"
common=(-Oz -ffunction-sections -fdata-sections -march=znver2 -fPIC -Wall -Wextra -ffile-prefix-map="$repo"=.
        -I"$repo/src/common" -I"$repo/src/loader"
        -DPROBE_INPUT -DPROBE_TOGGLE -DPROBE_NATIVE)

# The worker that runs inside ShellUI: PUI widgets, input, the interface.
"$sdk/bin/prospero-clang++" "${common[@]}" -Werror -std=c++20 \
    -I"$repo/src/shellui" -I"$repo/src/ui" \
    -shared -Wl,--gc-sections -Wl,-e,elf_main -Wl,-Bsymbolic -Wl,--hash-style=sysv -Wl,--eh-frame-hdr \
    -Wl,-T,"$repo/src/shellui/constructors.ld" \
    "$repo/src/shellui/worker.cpp" -lScePad -lmonosgen-2.0 -lkernel_sys -lSceLibcInternal -o "$out/worker.elf"

"$sdk/bin/prospero-strip" --strip-unneeded "$out/worker.elf"

# Embedded in the payload, with the loader's small method-lookup helper.
python3 "$repo/tools/embed.py" "$out/worker.elf" "$out/blob.c"
"$sdk/bin/prospero-clang" -c "$repo/src/loader/lookup-shim.S" -o "$out/lookup-shim.o"
objcopy -O binary -j .text "$out/lookup-shim.o" "$out/lookup-shim.bin"
python3 "$repo/tools/embed-shim.py" "$out/lookup-shim.bin" "$out/lookup-blob.c"
"$sdk/bin/prospero-clang" "${common[@]}" -Wno-sign-compare -c "$repo/src/loader/pt.c" -o "$out/pt.o"
"$sdk/bin/prospero-clang" "${common[@]}" -c "$repo/src/loader/stable_elfldr_bridge.c" -o "$out/elfldr.o"
"$sdk/bin/prospero-clang" "${common[@]}" -c "$out/blob.c" -o "$out/blob.o"
"$sdk/bin/prospero-clang" "${common[@]}" -c "$out/lookup-blob.c" -o "$out/lookup-blob.o"

# The payload itself (the daemon): loads the worker, reads the pad, links to providers.
daemon=("${common[@]}" "$out/lookup-blob.o" -DPROBE_CAPTURE -I"$repo/src/daemon" -I"$json")
if [[ $dev == 1 ]]; then
    build_id=$(sha256sum "$out/worker.elf" | cut -c1-16)
    daemon+=(-DPROBE_DEV_REPLACE "-DPROBE_BUILD_ID=0x${build_id}ULL")
    echo "Development build (replaces a running Kabuki), worker build id $build_id"
fi
"$sdk/bin/prospero-clang++" "${daemon[@]}" -Werror -std=c++20 "$repo/src/daemon/controller.cpp" \
    "$repo/src/loader/stable_shellui_injector.cpp" "$repo/src/loader/remote_call.cpp" \
    "$out/pt.o" "$out/elfldr.o" "$out/blob.o" -lSceSystemService -lkernel_sys -lSceLibcInternal \
    -Wl,--gc-sections -o "$repo/build/kabuki-ps5.elf"
"$sdk/bin/prospero-strip" --strip-unneeded "$repo/build/kabuki-ps5.elf"

# Payloads much over 2 MiB have failed to start on the console without any message.
size=$(stat -c %s "$repo/build/kabuki-ps5.elf")
if (( size > 2097152 )); then
    echo "build/kabuki-ps5.elf is $size bytes, over the 2 MiB payload limit" >&2
    exit 1
fi
sha256sum "$repo/build/kabuki-ps5.elf"
echo "size $size bytes"
