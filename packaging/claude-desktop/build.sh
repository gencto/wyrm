#!/usr/bin/env bash
# Build the Claude Desktop extension (`.mcpb`) of wyrm-mcp for this machine (ADR 0041).
#
#   packaging/claude-desktop/build.sh              # this OS and CPU
#   packaging/claude-desktop/build.sh --universal  # macOS: one arm64 + x86_64 binary
#
# Output: dist/claude-desktop/wyrm-<version>-<platform>.mcpb. Open it with Claude Desktop
# (double-click, or Settings → Extensions → Install Extension…).
set -euo pipefail
cd "$(dirname "$0")/../.."

universal=0
[[ "${1:-}" == "--universal" ]] && universal=1

case "$(uname -s)" in
  Darwin) platform=darwin ;;
  MINGW* | MSYS* | CYGWIN* | Windows_NT) platform=win32 ;;
  Linux) platform=linux ;;
  *) echo "unknown OS $(uname -s)" >&2; exit 1 ;;
esac

# Only what the connector needs: stdio and the gateway client (no HTTP transport).
features=(--no-default-features --features gateway)

if [[ $universal == 1 ]]; then
  [[ $platform == darwin ]] || { echo "--universal is for macOS" >&2; exit 1; }
  for t in aarch64-apple-darwin x86_64-apple-darwin; do
    rustup target add "$t" >/dev/null
    cargo build --release -p wyrm-mcp "${features[@]}" --target "$t"
  done
  mkdir -p target/universal-apple-darwin/release
  bin=target/universal-apple-darwin/release/wyrm-mcp
  lipo -create -output "$bin" \
    target/aarch64-apple-darwin/release/wyrm-mcp \
    target/x86_64-apple-darwin/release/wyrm-mcp
else
  cargo build --release -p wyrm-mcp "${features[@]}"
  bin=target/release/wyrm-mcp
  [[ $platform == win32 ]] && bin=target/release/wyrm-mcp.exe
fi

"${PYTHON:-python3}" packaging/claude-desktop/pack.py --binary "$bin" --platform "$platform"
