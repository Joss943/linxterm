#!/bin/bash
# LinXterm build script (Free Pascal)
set -e
cd "$(dirname "$(readlink -f "$0")")"
# Free Pascal: $FPCDIR, else ~/.local/opt/fpc, else the compiler of the distribution
if [ -z "$FPCDIR" ]; then
  for d in "$HOME"/.local/opt/fpc/usr/lib64/fpc/* /usr/lib64/fpc/* /usr/lib/x86_64-linux-gnu/fpc/* /usr/lib/fpc/* /usr/local/lib/fpc/*; do
    if [ -f "$d/units/x86_64-linux/rtl/system.ppu" ]; then FPCDIR="$d"; break; fi
  done
fi
[ -n "$FPCDIR" ] || { echo "Free Pascal not found: install the fpc package (or set FPCDIR)"; exit 1; }
PPC="$FPCDIR/ppcx64"
if [ ! -x "$PPC" ]; then PPC="$(command -v ppcx64 || command -v fpc)"; fi
mkdir -p build/units build/libs bin
# library folders: Fedora / openSUSE (lib64), Debian / Ubuntu (multiarch), Arch (lib)
LIBDIRS=""
for d in /usr/lib64 /usr/lib/x86_64-linux-gnu /lib/x86_64-linux-gnu /usr/lib; do
  [ -d "$d" ] && LIBDIRS="$LIBDIRS $d"
done
# linker symlinks to the runtime libraries (no -devel packages needed)
for l in gtk-3 gdk-3 vte-2.91 glib-2.0 gobject-2.0 gio-2.0 pango-1.0 cairo gdk_pixbuf-2.0 pangocairo-1.0; do
  f=""
  for d in $LIBDIRS; do
    f=$(ls "$d"/lib$l.so.* 2>/dev/null | sort | head -1)
    [ -n "$f" ] && break
  done
  [ -n "$f" ] || { echo "lib$l not found: install GTK 3 and VTE (vte-2.91)"; exit 1; }
  ln -sf "$f" "build/libs/lib$l.so"
done
# crtbegin.o and libgcc of the C compiler
GCCDIR=""
if command -v gcc >/dev/null; then GCCDIR=$(dirname "$(gcc -print-libgcc-file-name)"); fi
[ -d "$GCCDIR" ] || GCCDIR=$(ls -d /usr/lib/gcc/x86_64-*/* /usr/lib64/gcc/x86_64-*/* 2>/dev/null | sort -V | tail -1)
cat > build/fpc.cfg <<CFG
-Fu$FPCDIR/units/x86_64-linux/*
-Fu$FPCDIR/units/x86_64-linux/rtl
-Fl$GCCDIR
-Fl$PWD/build/libs
$(for d in $LIBDIRS; do echo "-Fl$d"; done)
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
