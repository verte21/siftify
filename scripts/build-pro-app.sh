#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="SiftifyPro"
APP_BUNDLE="$REPO_ROOT/build/${APP_NAME}.app"
RES_DIR="$APP_BUNDLE/Contents/Resources"
ENGINE_DIR="$RES_DIR/engine"

SDK_PATH=""
if [[ -d "/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk" ]]; then
  SDK_PATH="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
else
  SDK_PATH="$(xcrun --show-sdk-path)"
fi

echo "==> Building standalone native macOS SwiftUI app ($APP_NAME) with $(basename "$SDK_PATH")..."

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$RES_DIR" "$ENGINE_DIR"

swiftc -O \
  -parse-as-library \
  -sdk "$SDK_PATH" \
  -target arm64-apple-macosx14.0 \
  "$REPO_ROOT"/macos/Sources/SiftifyCore/*.swift \
  "$REPO_ROOT"/macos/Sources/SiftifyPro/*.swift \
  -o "$APP_BUNDLE/Contents/MacOS/${APP_NAME}"

chmod +x "$APP_BUNDLE/Contents/MacOS/${APP_NAME}"

# Bundle default config & llama.cpp calibration inside Contents/Resources
cp "$REPO_ROOT/siftify.config.json" "$RES_DIR/siftify.config.json"
cp "$REPO_ROOT/macos/Resources/CALIBRATION.llamacpp.json" "$RES_DIR/CALIBRATION.llamacpp.json"

# Generate AppIcon.icns
ICONSET_TMP="$(mktemp -d)/AppIcon.iconset"
swift -sdk "$SDK_PATH" -target arm64-apple-macosx14.0 "$REPO_ROOT/swift/MakeProAppIcon.swift" "$ICONSET_TMP"
iconutil -c icns "$ICONSET_TMP" -o "$RES_DIR/AppIcon.icns"
rm -rf "$(dirname "$ICONSET_TMP")"

echo "==> Bundling & relocating standalone Apple Silicon Metal engine (llama-server + ggml)..."

python3 - "$ENGINE_DIR" <<'PY'
import glob
import os
import re
import shutil
import subprocess
import sys

engine_dir = sys.argv[1]

llama_srv = shutil.which("llama-server") or "/opt/homebrew/bin/llama-server"
llama_srv = os.path.realpath(llama_srv)
if not os.path.exists(llama_srv):
    raise SystemExit("ERROR: llama-server not found to bundle")

shutil.copy2(llama_srv, os.path.join(engine_dir, "llama-server"))

# Copy ggml dynamic backend plugins (.so)
ggml_opt = "/opt/homebrew/opt/ggml/libexec"
for so_path in sorted(glob.glob(os.path.join(ggml_opt, "libggml-*.so"))):
    shutil.copy2(os.path.realpath(so_path), os.path.join(engine_dir, os.path.basename(so_path)))

# Discover all non-system dylibs transitively from llama-server + plugins
queue = [os.path.join(engine_dir, f) for f in os.listdir(engine_dir)]
copied_sonames = {}  # canonical_name -> local_path

def otool_deps(path):
    out = subprocess.check_output(["otool", "-L", path], text=True)
    lines = [ln.strip().split(" (")[0] for ln in out.splitlines()[1:]]
    return [d for d in lines if d]

def resolve_homebrew_dep(dep, parent_real_dir):
    if dep.startswith("/"):
        return dep if os.path.exists(dep) else None
    if dep.startswith("@rpath/"):
        name = dep[len("@rpath/"):]
        candidates = [
            os.path.join(parent_real_dir, name),
            os.path.join(os.path.dirname(parent_real_dir), "lib", name),
            os.path.join("/opt/homebrew/opt/llama.cpp/lib", name),
            os.path.join("/opt/homebrew/opt/ggml/lib", name),
            os.path.join("/opt/homebrew/opt/openssl@4/lib", name),
            os.path.join("/opt/homebrew/opt/libomp/lib", name),
        ]
        for c in candidates:
            if os.path.exists(c):
                return c
    return None

origin_dirs = {os.path.join(engine_dir, "llama-server"): os.path.dirname(llama_srv)}
for f in os.listdir(engine_dir):
    if f.endswith(".so"):
        origin_dirs[os.path.join(engine_dir, f)] = os.path.realpath(ggml_opt)

while queue:
    cur = queue.pop(0)
    cur_base = os.path.basename(cur)
    parent_dir = origin_dirs.get(cur, "/opt/homebrew/lib")
    for dep in otool_deps(cur):
        if dep.startswith(("/usr/lib/", "/System/Library/")):
            continue
        dep_name = os.path.basename(dep)
        if dep_name == cur_base:
            continue
        if dep_name not in copied_sonames:
            src = resolve_homebrew_dep(dep, parent_dir)
            if not src:
                raise SystemExit(f"ERROR: Could not resolve dependency {dep} of {cur_base}")
            real_src = os.path.realpath(src)
            dst = os.path.join(engine_dir, dep_name)
            shutil.copy2(real_src, dst)
            copied_sonames[dep_name] = dst
            origin_dirs[dst] = os.path.dirname(real_src)
            queue.append(dst)

# Make writable and relocate all install names + rpaths
all_bins = [os.path.join(engine_dir, f) for f in sorted(os.listdir(engine_dir))]
for b in all_bins:
    os.chmod(b, 0o755)
    base = os.path.basename(b)
    if base.endswith(".dylib"):
        subprocess.check_call(["install_name_tool", "-id", f"@rpath/{base}", b], stderr=subprocess.DEVNULL)

    for dep in otool_deps(b):
        if dep.startswith(("/usr/lib/", "/System/Library/")):
            continue
        dep_name = os.path.basename(dep)
        if dep_name == base and base.endswith(".dylib"):
            continue
        target = f"@rpath/{dep_name}"
        if dep != target:
            subprocess.check_call(["install_name_tool", "-change", dep, target, b], stderr=subprocess.DEVNULL)

    # Strip any absolute /opt/homebrew LC_RPATH entries and ensure @executable_path + @loader_path exist
    load_cmds = subprocess.check_output(["otool", "-l", b], text=True)
    rpaths = re.findall(r"cmd LC_RPATH\n\s*cmdsize \d+\n\s*path ([^\n]+) \(offset", load_cmds)
    for rp in rpaths:
        if rp.startswith("/opt/homebrew") or rp.startswith("/Users/"):
            subprocess.check_call(["install_name_tool", "-delete_rpath", rp, b], stderr=subprocess.DEVNULL)
    remaining = set(re.findall(r"cmd LC_RPATH\n\s*cmdsize \d+\n\s*path ([^\n]+) \(offset",
                               subprocess.check_output(["otool", "-l", b], text=True)))
    for wanted in ("@executable_path", "@loader_path"):
        if wanted not in remaining:
            subprocess.check_call(["install_name_tool", "-add_rpath", wanted, b], stderr=subprocess.DEVNULL)

# Ad-hoc sign each dylib/so/executable after install_name_tool modification
for b in all_bins:
    if b != os.path.join(engine_dir, "llama-server"):
        subprocess.check_call(["codesign", "--force", "--sign", "-", b],
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
subprocess.check_call(["codesign", "--force", "--sign", "-", os.path.join(engine_dir, "llama-server")],
                      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

# Verify zero /opt/homebrew references remain
for b in all_bins:
    out = subprocess.check_output(["otool", "-L", b], text=True)
    for ln in out.splitlines()[1:]:
        dep = ln.strip().split(" (")[0]
        if "/opt/homebrew" in dep or "/Users/" in dep:
            raise SystemExit(f"ERROR: Non-relocated path {dep} remains in {os.path.basename(b)}")

print(f"Relocated and verified {len(all_bins)} standalone engine binaries/libraries.")
PY

cat > "$APP_BUNDLE/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>Siftify Pro</string>
  <key>CFBundleDisplayName</key>
  <string>Siftify Pro</string>
  <key>CFBundleIdentifier</key>
  <string>dev.siftify.pro</string>
  <key>CFBundleVersion</key>
  <string>0.4.0</string>
  <key>CFBundleShortVersionString</key>
  <string>0.4.0</string>
  <key>CFBundleExecutable</key>
  <string>${APP_NAME}</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSDesktopFolderUsageDescription</key>
  <string>Siftify Pro inspects files locally on your Mac to preview and organize folders.</string>
  <key>NSDownloadsFolderUsageDescription</key>
  <string>Siftify Pro inspects your Downloads locally on your Mac to preview and organize folders.</string>
  <key>NSDocumentsFolderUsageDescription</key>
  <string>Siftify Pro inspects documents locally on your Mac to preview and organize folders.</string>
</dict>
</plist>
EOF

codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null 2>&1
echo "==> Built standalone $APP_BUNDLE"
