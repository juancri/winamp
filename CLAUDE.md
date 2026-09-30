# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Source for the Winamp desktop client (Windows, C/C++, Win32 API). There is no cross-platform build: everything is Visual Studio 2019 / MSBuild. On a non-Windows machine you can read and edit code but cannot build or run it. There is no test suite for Winamp itself; the only `test` dirs belong to vendored third-party code and to SDK sample plugins (e.g. `Src/Plugins/SDK/dsp_test`).

## Build

The master solution is `winampAll_2019.sln` at the repo root (~190 projects). Build it from the root in a VS2019 Developer prompt:

```
msbuild winampAll_2019.sln /p:Configuration=Release /p:Platform=Win32   # or Debug, x64
```

To build a single project (a plugin, say), pass its `.vcxproj` directly, e.g. `msbuild Src\Plugins\Input\in_mp3\in_mp3.vcxproj /p:Configuration=Release /p:Platform=Win32`.

Wrapper scripts live in `Src/winampAll/`: `build_winampAll_2019.cmd` builds all four variants (x86/x64 × Debug/Release), `build_winamp_<arch>_<config>_2019.cmd` builds one, and `clean_winampAll_2019.cmd` cleans. They hardcode the VS2019 **Community** `vcvars` path and call `msbuild winampAll_2019.sln` relative to the current directory, so run them from the repo root.

Build output: each project builds into `<PlatformShortName>_<Configuration>\` next to its `.vcxproj`. A post-build `xcopy` then gathers binaries into `Build\Winamp_<arch>_<config>\` (plugins go in `Plugins\`), which gives you a runnable install tree.

Sources not in the open-source release: `Src/vlb` (Dolby VLB decoder; removed from the `.sln` and from `in_mp3`) and `Src/Plugins/DSP/sc_serv3` (so `dsp_sc` can't build). Qt and CEF aren't in the repo, so the Qt-based `Src/Components/wac_*` projects fail too.

### CI build (usable from Linux)

`.github/workflows/build-windows.yml` builds Release|Win32 on a GitHub Windows runner and uploads `Build/Winamp_x86_Release` (artifact `Winamp_x86_Release`) plus `msbuild*.log`; the run summary lists failing projects. It runs on pushes to `community` and `ci/**`, or `gh workflow run build-windows.yml`. Fetch it with `gh run download <id> -n Winamp_x86_Release` and run it under Wine (`WINEPREFIX=~/.wine-winamp wine winamp.exe`). The workflow encodes several non-obvious fixes, and each one is explained in a comment next to it: vcpkg is pinned and built with the v142 toolset through `.github/vcpkg-triplets/`, vcpkg is wired in with `ForceImport*CppTargets` instead of `integrate install`, the spdlog overlay is skipped, and it sets `CL=/DFMT_UNICODE#0`. `winampv6` lists ~100 plugins as solution dependencies (for build order only), so the workflow also builds `winampv6.vcxproj` on its own, and one broken plugin doesn't block `winamp.exe`.

### One-time dependency setup (Windows)

- `install-packages.cmd` (repo root) clones and bootstraps vcpkg into `.\vcpkg`, copies the patched port overlays from `vcpkg-ports/` into `vcpkg/ports/`, and installs the packages as `x86-windows-static-md` (plus `x86-windows-static` for some). To change a third-party library version, edit its port in `vcpkg-ports/` (versions are tracked in `vcpkg-ports/LibraryVersions.json`). `vcpkg_version_finder.py <pkg> [vcpkg_path]` helps look up port version history.
- Unpack vendored archives: `BuildTools/lib/unpack_intel_ipp_6.1.1.035.cmd` (exactly IPP 6.1.1.035 is required), `BuildTools/lib/unpack_microsoft_directx_sdk_2010.cmd`, `Src/winampAll/unpack_libvpx_v1.8.2_msvc16.cmd`, and `Src/winampAll/unpack_libmpg123.cmd`.
- OpenSSL 1.0.1u static libs come from `Src/winampAll/build_vs_2019_openssl_{x86,64}.cmd`, which need 7-Zip, NASM and Perl.
- The VS2019 ATL header needs a manual patch: in `atlmfc/include/atltransactionmanager.h` around line 427, change `::DeleteFile(` to `DeleteFile(`.
- Scripts expect 7-Zip Portable at `BuildTools\7-ZipPortable_22.01\`. External tools (7-Zip, Git, TortoiseSVN) are not bundled for licensing reasons.
- `install-packages.cmd` and `cef_x86.bat`/`automate-git.py` also reference Qt DLL archives (`Qt\`) and a CEF archive (`Src\external_dependencies\CEF.7z.*`) that are not in this repo.

## Architecture

**Core executable** — `Src/Winamp/` (project `winampv6.vcxproj`). It holds the player, main window, playlist, config, skin loading, COM/JS automation objects (`*COM.cpp`) and the plugin loader. This directory also defines the classic **plugin ABI** headers that every plugin includes:
- `IN2.H` (input/decoder, `In_Module`), `OUT.H` (output), `GEN.H` (general purpose), `DSP.H`, `VIS.H`
- `wa_ipc.h`: the IPC message API. Plugins talk to the host with `SendMessage(hwndParent, WM_WA_IPC, param, IPC_*)`.

**Plugins** — `Src/Plugins/<Type>/<prefix>_<name>/`, each one a DLL. The prefix gives the type and the exported entry point: `in_` (`winampGetInModule2`), `out_`, `gen_`, `dsp_`, `vis_`, `enc_` (encoders), `ml_` (Media Library sub-plugins, hosted by `gen_ml`), and `pmp_` (portable devices, hosted by `ml_pmp`). `Src/Plugins/SDK/` holds sample plugins.

**Wasabi service layer** — `Src/Wasabi/` (the `api/` interfaces plus the `bfc/` base classes) is the component/service framework that sits alongside the classic ABI. A plugin gets the service manager (`api_service*`) with `IPC_GET_API_SERVICE`, or through `In_Module::service` for input plugins. It then looks up services by GUID (`service_getServiceByGuid` → `waServiceFactory`). Many interfaces are declared as `api_*.h` headers, and plugins usually keep an `api__<plugin>.h` that defines the service pointers they use. `Src/Wasabi2/`, `Src/nu/` (shared utility code), `Src/nsutil`, `Src/nswasabi`, and `Src/replicant` are common support libraries. Plugin projects typically add `..\..\..\Wasabi` and `..\..\..\replicant` to their include paths.

**Top-level `Src/` libraries** — Most of the other directories under `Src/` are standalone codec, format, or service components (e.g. `aacdec`, `h264`, `nsmkv`, `nsv`, `png`, `jpeg`, `playlist`, `xspf`, `nde` = Nullsoft Database Engine used by the media library, `tagz` = title formatting, `ns-eel2` = expression evaluator used by AVS/MilkDrop). Many of them build as `.w5s`/`.wac` service components that register with the Wasabi service manager instead of being linked directly.

**Other trees**: `Src/installer/` (NSIS installer, lang packs, SDK packaging), `Src/resources/` (skins, media), `Src/external_dependencies/` (vendored third-party sources: cpr, giflib, libmp4v2, openmpt, IPP, DirectX SDK).
