#!/bin/zsh
cd "$(dirname "$0")/.."
if xcode-select -p 2>/dev/null | grep -q "Xcode.app"; then
  exec swift test "$@"
fi
CLT=/Library/Developer/CommandLineTools
exec swift test --build-system native \
  -Xswiftc -F -Xswiftc $CLT/Library/Developer/Frameworks \
  -Xswiftc -plugin-path -Xswiftc $CLT/usr/lib/swift/host/plugins/testing \
  -Xlinker -F -Xlinker $CLT/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker $CLT/Library/Developer/Frameworks "$@" 2>&1 | grep -v "ld: warning"
