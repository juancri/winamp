set(VCPKG_TARGET_ARCHITECTURE x86)
set(VCPKG_CRT_LINKAGE static)
set(VCPKG_LIBRARY_LINKAGE static)
# Winamp's projects link with the v141/v142 toolsets; libraries built by v143 pull in CRT helpers
# (__ultof3, __dtoul3_legacy, ...) that the older runtime doesn't have.
set(VCPKG_PLATFORM_TOOLSET v142)
