#!/usr/bin/env bash
# Run inside an MSYS2 MinGW64 shell, from the repo root, AFTER `ninja -C builddir install`
# has installed Papers into dist/papers (see .github/workflows/windows-build.yml).
#
# This copies every MinGW DLL papers.exe actually needs, plus the shared data
# (icon theme, gdk-pixbuf loaders, compiled GSettings schemas) it looks for
# relative to its own install prefix, so the resulting dist/papers folder can
# be zipped up and run on a plain Windows 10 machine with nothing else installed.
set -euo pipefail

DIST="$(pwd)/dist/papers"
MINGW_ROOT="/mingw64"

if [ ! -f "$DIST/bin/papers.exe" ]; then
  echo "ERROR: $DIST/bin/papers.exe not found — did 'ninja install' run first?" >&2
  exit 1
fi

echo "==> Collecting DLL dependencies of papers.exe"

# Recursively walk `ldd` output, copying any DLL that lives under the MSYS2
# mingw64 tree (i.e. one we built against) and is not a base Windows system DLL.
declare -A seen
copy_deps() {
  local bin="$1"
  local dep path
  while IFS= read -r line; do
    dep="$(echo "$line" | awk '{print $1}')"
    path="$(echo "$line" | awk '{print $3}')"
    [ -z "$dep" ] && continue
    [ -n "${seen[$dep]:-}" ] && continue
    case "$path" in
      /c/Windows/*|/C/Windows/*|/mingw64/bin/msys-*) continue ;;
    esac
    case "$path" in
      "$MINGW_ROOT"/bin/*.dll)
        seen[$dep]=1
        cp -u "$path" "$DIST/bin/"
        copy_deps "$path"
        ;;
    esac
  done < <(ldd "$bin" 2>/dev/null || true)
}

copy_deps "$DIST/bin/papers.exe"
echo "==> Copied ${#seen[@]} dependency DLLs"

echo "==> Bundling gdk-pixbuf loaders (image format support)"
PIXBUF_VER_DIR="$(find "$MINGW_ROOT/lib/gdk-pixbuf-2.0" -maxdepth 1 -type d -name '2.*' | head -n1)"
if [ -n "$PIXBUF_VER_DIR" ]; then
  mkdir -p "$DIST/lib/gdk-pixbuf-2.0"
  cp -r "$PIXBUF_VER_DIR" "$DIST/lib/gdk-pixbuf-2.0/"
  DEST_VER_DIR="$DIST/lib/gdk-pixbuf-2.0/$(basename "$PIXBUF_VER_DIR")"
  for dll in "$DEST_VER_DIR"/loaders/*.dll; do
    copy_deps "$dll"
  done
  GDK_PIXBUF_MODULEDIR="$DEST_VER_DIR/loaders" gdk-pixbuf-query-loaders \
    > "$DEST_VER_DIR/loaders.cache"
fi

echo "==> Bundling icon theme (hicolor + Adwaita)"
mkdir -p "$DIST/share/icons"
for theme in hicolor Adwaita; do
  if [ -d "$MINGW_ROOT/share/icons/$theme" ]; then
    cp -r "$MINGW_ROOT/share/icons/$theme" "$DIST/share/icons/"
  fi
done

echo "==> Merging and recompiling GSettings schemas"
mkdir -p "$DIST/share/glib-2.0/schemas"
cp -n "$MINGW_ROOT"/share/glib-2.0/schemas/*.xml "$DIST/share/glib-2.0/schemas/" 2>/dev/null || true
glib-compile-schemas "$DIST/share/glib-2.0/schemas"

echo "==> Bundling gettext locale data (translated UI strings)"
if [ -d "$DIST/share/locale" ]; then
  : # already installed by ninja install
fi

echo "==> Writing portable launcher"
cat > "$DIST/../Papers.bat" <<'EOF'
@echo off
setlocal
set "PAPERS_ROOT=%~dp0papers"
set "PATH=%PAPERS_ROOT%\bin;%PATH%"
set "GSETTINGS_SCHEMA_DIR=%PAPERS_ROOT%\share\glib-2.0\schemas"
set "XDG_DATA_DIRS=%PAPERS_ROOT%\share"
start "" "%PAPERS_ROOT%\bin\papers.exe" %*
EOF

echo "==> Done. Portable app is in dist/papers (launch via dist/Papers.bat or dist/papers/bin/papers.exe)"
