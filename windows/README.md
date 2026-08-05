# Papers on Windows — porting notes

This folder plus `.github/workflows/windows-build.yml` add a Windows build to
upstream Papers, which has never been built for Windows before. Summary of
what changed and why:

## What was changed in the source

- **`shell/src/meson.build`** — the step that copies the built Rust binary
  into place assumed a bare filename `papers`. Cargo's `windows-gnu` target
  produces `papers.exe`, so this was patched to append `.exe` on Windows
  (`host_machine.system() == 'windows'`). Without this the build silently
  failed to produce a usable binary on Windows.

No other source changes were required — the C/Rust code itself doesn't use
D-Bus, desktop portals, `fork()`/`dlopen()`, or other Linux-only APIs. It's
built on GLib, which is genuinely cross-platform.

## What was disabled for the Windows build (via Meson options)

| Option | Why |
|---|---|
| `nautilus=false` | GNOME Files extension — Linux file manager only |
| `thumbnailer=false` | Uses the freedesktop.org thumbnailer spec — not applicable on Windows |
| `keyring=disabled` | Password storage uses `oo7`, which talks to the Linux/D-Bus Secret Service. Disabling this just means Papers asks for a PDF password each time instead of remembering it — everything else is unaffected |
| `introspection=disabled` | GObject-Introspection cross-toolchain isn't needed to run the app, only to script it from other languages |
| `sysprof=disabled` | Linux profiling integration |
| `gtk_unix_print=disabled` | Linux/CUPS print backend — GTK uses its native Win32 print backend automatically instead |
| `documentation=false`, `user_doc=false`, `tests=false`, `file_tests=false` | Build-time only, not needed to produce the app |

PDF (poppler), comics (libarchive), TIFF, and DjVu support are left on their
default settings and will build if the corresponding MSYS2 package is
installed (see the workflow). Spell-check is left on `auto` too; if
`libspelling` isn't packaged for MinGW64 it will just be silently skipped —
check the Meson summary in the build log to see what actually got enabled.

## How the portable folder is built (`windows/package.sh`)

Papers links dynamically against MSYS2's shared MinGW64 runtime — it isn't
a standalone binary by default. `package.sh` runs after `ninja install` and:

1. Walks `ldd` recursively to copy every non-system DLL `papers.exe` needs.
2. Copies the gdk-pixbuf image-loader DLLs and regenerates their cache file.
3. Copies the hicolor/Adwaita icon themes.
4. Merges in GTK's own base GSettings schemas and recompiles
   `gschemas.compiled`.
5. Writes `Papers.bat`, a tiny launcher that points `GSETTINGS_SCHEMA_DIR`
   and `XDG_DATA_DIRS` at the bundled folder before starting `papers.exe`.
   GLib/GTK on Windows are usually able to find their own resources relative
   to the `.exe` automatically, so `papers\bin\papers.exe` may well run fine
   on its own — but use `Papers.bat` if icons, image thumbnails, or app
   settings don't behave.

## Running the build

1. Push this repo to GitHub.
2. Go to the **Actions** tab → **Windows build** → **Run workflow**.
3. When it finishes, download the `Papers-Windows` artifact from the run
   page — it's a zip containing `Papers.bat` and the `papers\` folder.
4. Unzip anywhere on a Windows 10 machine and run `Papers.bat` (or
   `papers\bin\papers.exe`).

## This is a first pass, not a guarantee

Nobody has built this specific app for Windows before, so treat the first
CI run as a debugging pass, not a finished product. If a step fails, the
Actions log will name the missing package or the exact compile error —
paste that back and it can be fixed directly. Two things worth checking on
the first successful run in particular:

- Whether PDF/comics/TIFF support actually got enabled (check the Meson
  "Configuration summary" printed near the top of the build log).
- Whether the app looks right without `Papers.bat` (i.e. whether GTK's
  built-in Windows path relocation is enough on its own).
