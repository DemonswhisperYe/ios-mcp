#!/usr/bin/env bash
# Rebuild the server and Settings from this checkout, using unchanged v1.2.8 payloads.
set -euo pipefail
cd "$(dirname "$0")/.."

scheme=${1:?select rootful, rootless, or roothide}
base=62c4464f688c8f269419924b1a19c996de75f175
prefix=
case "$scheme" in
  rootful)  arch=arm;    digest=fa6bcf28f52f8648e2821ef07bb667f43be13a4c942dcb0995372cde90e1acab ;;
  rootless) arch=arm64;  digest=2b1321c8b2723ae2bf0bfa15425f800275651d34a67f6b4d4d25c2c670aae336; prefix=var/jb/ ;;
  roothide) arch=arm64e; digest=9cce934fe76ab421cb29f14c09be2b44251fda4cbc87c2e3559be9df8a580f33 ;;
  *) echo "Unknown package scheme: $scheme" >&2; exit 2 ;;
esac
# If an upstream binary or resource needs to change, use the project's full source build.
git diff --exit-code "$base" -- AppSync third_party 'mcp-*' control ios-mcp.plist prefs/entry LICENSE NOTICE THIRD_PARTY_NOTICES.md

work=$(mktemp -d "${RUNNER_TEMP:-/tmp}/ios-mcp-auth.XXXXXX")
input="com.witchan.ios-mcp_1.2.8_iphoneos-$arch.deb"
curl -fLsS --retry 3 "https://github.com/witchan/ios-mcp/releases/download/v1.2.8/$input" -o "$work/$input"
(cd "$work" && echo "$digest  $input" | shasum -a 256 -c -)
dpkg-deb -R "$work/$input" "$work/stage"

args=(FINALPACKAGE=1 DEBUG=0 STRIP=1 "THEOS_OBJ_DIR_NAME=obj/auth-$scheme")
if [[ $scheme != rootful ]]; then args+=("THEOS_PACKAGE_SCHEME=$scheme"); fi
gmake -j3 "${args[@]}" all
obj=".theos/obj/auth-$scheme"
lib="$work/stage/${prefix}Library"
cp "$obj/ios-mcp.dylib" "$lib/MobileSubstrate/DynamicLibraries/ios-mcp.dylib"
rsync -a "$obj/iosmcpprefs.bundle/" "$lib/PreferenceBundles/iosmcpprefs.bundle/"

version="1.2.8+auth.${GITHUB_RUN_NUMBER:-0}.${GITHUB_RUN_ATTEMPT:-1}"
control="$work/stage/DEBIAN/control"
sed "s/^Version: .*/Version: $version/" "$control" > "$work/control"
cp "$work/control" "$control"
mkdir -p packages
output="com.witchan.ios-mcp_${version}_iphoneos-$arch.deb"
COPYFILE_DISABLE=1 dpkg-deb --root-owner-group -Zxz --build "$work/stage" "packages/$output"
python3 tests/paddle_package_test.py --arch "$arch" --version "$version" --out "$work/audit.json"
(cd packages && shasum -a 256 "$output" > SHA256SUMS)
