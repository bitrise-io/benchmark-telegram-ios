#!/usr/bin/env bash
# Not timed. Same as the Bitrise Telegram "Prepare dependencies" step.
# Checking out TG_COMMIT removes .github/ from the work tree; the workflow runs these scripts from $RUNNER_TEMP.
set -eo pipefail
cd "$GITHUB_WORKSPACE"
git fetch --depth=1 origin "$TG_COMMIT"
git checkout --force "$TG_COMMIT"
# .gitmodules uses relative URLs (../tgcalls.git) that only resolve under TelegramMessenger
perl -pi -e 's#url\s*=\s*\.\./#url = https://github.com/TelegramMessenger/#' .gitmodules
git submodule sync --recursive
git submodule update --init --recursive --depth=1 || git submodule update --init --recursive

# Simulator builds don't need signing; the repo's fake-codesigning profile expired 2026-10-30.
python3 - <<'PY'
p = 'build-system/Make/Make.py'
s = open(p).read()
anchor = '    bazel_command_line.set_configuration(arguments.configuration)\n'
assert s.count(anchor) == 1, 'Make.py patch anchor not found'
s = s.replace(anchor, anchor + "    if arguments.configuration.endswith('_sim_arm64'):\n        bazel_command_line.set_disable_provisioning_profiles()\n")
open(p, 'w').write(s)
print('Patched Make.py: simulator builds pass --//Telegram:disableProvisioningProfiles')
PY

xcodebuild -downloadComponent MetalToolchain || true
printf 'kernel void k() {}\n' > "$RUNNER_TEMP/tg-check.metal"
xcrun metal -c "$RUNNER_TEMP/tg-check.metal" -o "$RUNNER_TEMP/tg-check.air"

BAZEL_VER=$(python3 -c 'import json;print(json.load(open("versions.json"))["bazel"].split(":")[0])')
BAZEL_SHA=$(python3 -c 'import json;v=json.load(open("versions.json"))["bazel"].split(":");print(v[1] if len(v)>1 else "")')
mkdir -p "$RUNNER_TEMP/tg-bazel"; BAZEL="$RUNNER_TEMP/tg-bazel/bazel-$BAZEL_VER"
curl -fsSL -o "$BAZEL" "https://github.com/bazelbuild/bazel/releases/download/${BAZEL_VER}/bazel-${BAZEL_VER}-darwin-arm64"
chmod +x "$BAZEL"
GOT=$(shasum -a 256 "$BAZEL" | awk '{print $1}')
[ "$GOT" = "$BAZEL_SHA" ] || echo "⚠️ bazel sha256 $GOT differs from versions.json ($BAZEL_SHA)"
echo "TG_BAZEL=$BAZEL" >> "$GITHUB_ENV"
echo "Xcode required by versions.json: $(python3 -c 'import json;print(json.load(open("versions.json"))["xcode"])')"
xcodebuild -version
