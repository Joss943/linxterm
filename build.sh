#!/bin/bash
# LinXterm build script (Free Pascal)
set -e
cd "$(dirname "$(readlink -f "$0")")"
FPCDIR="${FPCDIR:-$HOME/.local/opt/fpc/usr/lib64/fpc/3.2.3}"
PPC="$FPCDIR/ppcx64"
if [ ! -x "$PPC" ]; then PPC="$(command -v ppcx64 || command -v fpc)"; fi
mkdir -p build/units build/libs bin
# linker symlinks to the runtime libraries (no -devel packages needed)
for l in gtk-3 gdk-3 vte-2.91 glib-2.0 gobject-2.0 gio-2.0 pango-1.0 cairo gdk_pixbuf-2.0 pangocairo-1.0; do
  f=$(ls /usr/lib64/lib$l.so.* 2>/dev/null | sort | head -1)
  [ -n "$f" ] && ln -sf "$f" "build/libs/lib$l.so"
done
cat > build/fpc.cfg <<CFG
-Fu$FPCDIR/units/x86_64-linux/*
-Fu$FPCDIR/units/x86_64-linux/rtl
-Fl/usr/lib/gcc/x86_64-redhat-linux/$(ls /usr/lib/gcc/x86_64-redhat-linux/ | sort -V | tail -1)
-Fl$PWD/build/libs
-Fl/usr/lib64
-Fusrc
-FUbuild/units
-FEbin
-O2
-Xs
-veiwn
CFG
for prog in linxterm lxaskpass lxtelnet lxserial lxrelay; do
  if [ -f "src/$prog.lpr" ]; then
    echo "== building $prog"
    rm -f "bin/$prog"
    "$PPC" -n @build/fpc.cfg "src/$prog.lpr" 2>&1 | grep -vE '^(Free Pascal|Copyright|Target OS|Compiling |Linking |Assembling|[0-9]+ lines compiled)' | grep -vE 'Note: (Call to subroutine|Local variable|Private type|Parameter)|Hint: ' || true
    test -x "bin/$prog" || { echo "BUILD FAILED: $prog"; exit 1; }
  fi
done
echo "Build OK"
