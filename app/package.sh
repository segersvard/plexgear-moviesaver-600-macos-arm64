#!/bin/bash
# Paketerar redan byggda ARM64-filer och motsvarande källkod; returnerar fel vid ogiltig signatur.
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
package_stage="$(mktemp -d "${TMPDIR:-/tmp}/moviesaver-package.XXXXXX")"
package_root="$package_stage/Moviesaver-Inspelning-v0.1.0"
app_bundle="$package_root/Moviesaver Inspelning.app"
mkdir -p "$app_bundle/Contents/MacOS" "$package_root/Kallkod"
cp -X app/Info.plist "$app_bundle/Contents/Info.plist"
cp -X build/recorder build/Moviesaver "$app_bundle/Contents/MacOS/"
codesign --force --sign - "$app_bundle/Contents/MacOS/recorder"
codesign --force --sign - "$app_bundle"
codesign --verify --deep --strict "$app_bundle"
cp -X app/LAS-MIG.txt "$package_root/LAS-MIG.txt"
# En explicit lista håller privata inspelningar, registerloggar och byggen utanför leveransen.
for source_item in app src tests tools docs .github .gitignore Makefile README.md NOTICE LICENSE LICENSE-MIT CONTRIBUTING.md; do
 ditto --norsrc --noextattr "$source_item" "$package_root/Kallkod/$source_item"
done
find "$package_root/Kallkod" -type d -name __pycache__ -prune -exec rm -rf {} +
archive_path="$project_dir/build/Moviesaver-Inspelning-v0.1.0.zip"
ditto --norsrc --noextattr -c -k --keepParent "$package_root" "$archive_path"
printf 'Apppaket: %s\nSignerad app för lokalt prov: %s\n' "$archive_path" "$app_bundle"
