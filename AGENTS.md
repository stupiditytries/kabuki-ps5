# AGENTS.md

## Project

Kabuki is a C++20 PS5 homebrew control panel. Run the following commands from the repository root on Linux or WSL.

## Install build dependencies

On Debian 12, install the host tools and LLVM 16:

```bash
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
  build-essential binutils clang-16 lld-16 llvm-16 python3 curl unzip
```

The build requires the public [PS5 Payload SDK](https://github.com/ps5-payload-dev/sdk). Install the project's pinned and checksum-verified SDK v0.44 using its CI setup script, then point `PS5_PAYLOAD_SDK` to it:

```bash
bash tools/ci/setup-sdk.sh "$HOME/kabuki-sdk"
export PS5_PAYLOAD_SDK="$HOME/kabuki-sdk/ps5-payload-sdk"
python3 tools/fetch-deps.py
```

If the SDK is already installed, set `PS5_PAYLOAD_SDK` to its directory instead. Ensure `PATH` is exported and includes the host compiler and LLVM tools. The project's CI uses LLVM 18; LLVM 16 also works on Debian 12.

## Test and build

```bash
bash tests/run.sh
bash build.sh
```

The release payload is `build/kabuki-ps5.elf`. The build checks that it is under 2 MiB. To run the same test, build and packaging sequence as CI, use `bash tools/ci/build-release.sh`; its output is in `dist/`.

Use `bash build.sh --dev` only for development: it can replace a running Kabuki instance and is not intended for distribution. Host tests do not replace testing on a PS5.
