#!/bin/zsh
set -e
cd "$(dirname "$0")/.."
VERSION="${1:?usage: scripts/release.sh <version>}"
VERSION="$VERSION" BUILD="${BUILD:-1}" scripts/build-app.sh
rm -f build/Sofia.zip build/Sofia.zip.sha256
ditto -c -k --norsrc --noextattr --keepParent build/Sofia.app build/Sofia.zip
(cd build && shasum -a 256 Sofia.zip > Sofia.zip.sha256)
echo "build/Sofia.zip and build/Sofia.zip.sha256 ready for release v$VERSION"
cat build/Sofia.zip.sha256
