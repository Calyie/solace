# Project-level configuration.
cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "solace")
# The unique GTK application identifier for this application. See:
# https://wiki.gnome.org/HowDoI/ChooseApplicationID
set(APPLICATION_ID "app.personal.solace")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(SET CMP0063 NEW)

# Load bundled libraries from the lib/ directory relative to the binary.
set(CMAKE_INSTALL_RPATH "$ORIGIN/lib")

# Root filesystem for cross-building.
if(FLUTTER_TARGET_PLATFORM_SYSROOT)
  set(CMAKE_SYSROOT ${FLUTTER_TARGET_PLATFORM_SYSROOT})
  set(CMAKE_FIND_ROOT_PATH ${CMAKE_SYSROOT})
  set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
  set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
  set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
  set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
endif()

# Define build configuration options.
if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE "Debug" CACHE
    STRING "Flutter build mode" FORCE)
  set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
    "Debug" "Profile" "Release")
endif()

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_14)
  # warnings stay errors, except a library marking a function deprecated (2026-11-14: Ubuntu's newer appindicator
  # headers deprecate app_indicator_new, which tray_manager 0.5.3 still calls)
  target_compile_options(${TARGET} PRIVATE -Wall -Werror -Wno-error=deprecated-declarations)
  target_compile_options(${TARGET} PRIVATE "$<$<NOT:$<CONFIG:Debug>>:-O3>")
  target_compile_definitions(${TARGET} PRIVATE "$<$<NOT:$<CONFIG:Debug>>:NDEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# System-level dependencies.
find_package(PkgConfig REQUIRED)
pkg_check_modules(GTK REQUIRED IMPORTED_TARGET gtk+-3.0)

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)

# Only the install-generated bundle's copy of the executable will launch
# correctly, since the resources must in the right relative locations. To avoid
# people trying to run the unbundled copy, put it in a subdirectory instead of
# the default top-level location.
set_target_properties(${BINARY_NAME}
  PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/intermediates_do_not_run"
)


# === ONNX Runtime for the safety classifier, checked before use (security review SUP-4, 2026-11-14) ===
# flutter_onnxruntime 1.9.0 (its linux/CMakeLists.txt) downloads Microsoft's prebuilt ONNX Runtime from GitHub with no
# checksum, and skips that download when the unpacked copy is already in its build folder. So the app puts a checked
# copy into that folder first, before the plugin is configured. A copy without our "checked" marker, or whose library no
# longer matches, is deleted and made again, so an unchecked copy is never compiled against or shipped.
# Since 2026-11-19 the source is Microsoft's own NuGet package Microsoft.ML.OnnxRuntime 1.28.0 (the version the iPhone
# and the Mac already ship), because the GitHub release archives this build used (1.28.3) are no longer published. The
# package is pinned by its SHA-256; on 2026-11-19 its SHA-512 matched the packageHash in NuGet's own catalog and it
# carried Microsoft Corporation's signature (docs/SECURITY.md section 6). Each library inside is pinned as well. A new
# version needs new hashes here, never just a new number, and ONNX Runtime 1.29 and later turn on telemetry to
# Microsoft by default (docs/security/sup3_proposal_2026-11-14.md, risk 5), so an upgrade past 1.28 also needs that off.
set(SOLACE_ORT_VERSION "1.28.0")
set(SOLACE_ORT_NUPKG_SHA256 "769d1d3ea8ab6cd69f737c9dd4d4462aa4ad0ccfa106eaf506efc40d7bead5db")
if(CMAKE_SYSTEM_PROCESSOR MATCHES "x86_64")
  set(SOLACE_ORT_ARCH "x64")
  set(SOLACE_ORT_RID "linux-x64")
  set(SOLACE_ORT_LIB_SHA256 "1461ef7cc3d9e49982591721683cc3e3a55580aeca9a5254e7aac47b75ee4bab")
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "aarch64")
  set(SOLACE_ORT_ARCH "aarch64")
  set(SOLACE_ORT_RID "linux-arm64")
  set(SOLACE_ORT_LIB_SHA256 "f1ec1a08eb99bd6e5401340f0a2b101381bf4694415480291dc13bcaa30f9ec7")
else()
  message(FATAL_ERROR "No pinned ONNX Runtime for ${CMAKE_SYSTEM_PROCESSOR}")
endif()
# the plugin reads these two: the version it looks for, and never a system copy found by pkg-config or a search path
set(ONNXRUNTIME_VERSION "${SOLACE_ORT_VERSION}")
set(USE_SYSTEM_ONNXRUNTIME OFF CACHE BOOL "Use the checked ONNX Runtime download only" FORCE)
set(SOLACE_ORT_NAME "onnxruntime-linux-${SOLACE_ORT_ARCH}-${SOLACE_ORT_VERSION}")
set(SOLACE_ORT_PARENT "${CMAKE_BINARY_DIR}/plugins/flutter_onnxruntime/onnxruntime")
set(SOLACE_ORT_DIR "${SOLACE_ORT_PARENT}/${SOLACE_ORT_NAME}")
set(SOLACE_ORT_LIB "${SOLACE_ORT_DIR}/lib/libonnxruntime.so.${SOLACE_ORT_VERSION}")
set(SOLACE_ORT_MARK "${SOLACE_ORT_DIR}/.solace_checked_sha256")
set(SOLACE_ORT_OK FALSE)
if(EXISTS "${SOLACE_ORT_MARK}" AND EXISTS "${SOLACE_ORT_LIB}")
  file(READ "${SOLACE_ORT_MARK}" SOLACE_ORT_MARKED)
  file(SHA256 "${SOLACE_ORT_LIB}" SOLACE_ORT_HAVE)
  if(SOLACE_ORT_MARKED STREQUAL SOLACE_ORT_NUPKG_SHA256 AND SOLACE_ORT_HAVE STREQUAL SOLACE_ORT_LIB_SHA256)
    set(SOLACE_ORT_OK TRUE)
  endif()
endif()
if(NOT SOLACE_ORT_OK)
  file(REMOVE_RECURSE "${SOLACE_ORT_DIR}")
  file(MAKE_DIRECTORY "${SOLACE_ORT_PARENT}")
  set(SOLACE_ORT_PKG "${SOLACE_ORT_PARENT}/microsoft.ml.onnxruntime.${SOLACE_ORT_VERSION}.nupkg")
  set(SOLACE_ORT_UNZIP "${SOLACE_ORT_PARENT}/nupkg")
  file(DOWNLOAD
    "https://api.nuget.org/v3-flatcontainer/microsoft.ml.onnxruntime/${SOLACE_ORT_VERSION}/microsoft.ml.onnxruntime.${SOLACE_ORT_VERSION}.nupkg"
    "${SOLACE_ORT_PKG}" TLS_VERIFY ON EXPECTED_HASH SHA256=${SOLACE_ORT_NUPKG_SHA256} STATUS SOLACE_ORT_STATUS)
  list(GET SOLACE_ORT_STATUS 0 SOLACE_ORT_CODE)
  if(NOT SOLACE_ORT_CODE EQUAL 0)
    file(REMOVE "${SOLACE_ORT_PKG}")
    message(FATAL_ERROR "ONNX Runtime package download or check failed: ${SOLACE_ORT_STATUS}")
  endif()
  file(REMOVE_RECURSE "${SOLACE_ORT_UNZIP}")
  file(MAKE_DIRECTORY "${SOLACE_ORT_UNZIP}")
  execute_process(COMMAND ${CMAKE_COMMAND} -E tar xf "${SOLACE_ORT_PKG}"
                  WORKING_DIRECTORY "${SOLACE_ORT_UNZIP}" RESULT_VARIABLE SOLACE_ORT_UNTAR)
  file(REMOVE "${SOLACE_ORT_PKG}")
  set(SOLACE_ORT_FROM "${SOLACE_ORT_UNZIP}/runtimes/${SOLACE_ORT_RID}/native/libonnxruntime.so")
  if(NOT SOLACE_ORT_UNTAR EQUAL 0 OR NOT EXISTS "${SOLACE_ORT_FROM}")
    message(FATAL_ERROR "ONNX Runtime package did not unpack to ${SOLACE_ORT_FROM}")
  endif()
  file(SHA256 "${SOLACE_ORT_FROM}" SOLACE_ORT_HAVE)
  if(NOT SOLACE_ORT_HAVE STREQUAL SOLACE_ORT_LIB_SHA256)
    file(REMOVE_RECURSE "${SOLACE_ORT_UNZIP}")
    message(FATAL_ERROR "ONNX Runtime library has SHA-256 ${SOLACE_ORT_HAVE}, pinned ${SOLACE_ORT_LIB_SHA256}")
  endif()
  # the layout of Microsoft's Linux archive, which the plugin expects: include/, and lib/ with the library and its links
  file(MAKE_DIRECTORY "${SOLACE_ORT_DIR}/lib")
  file(COPY "${SOLACE_ORT_UNZIP}/build/native/include" DESTINATION "${SOLACE_ORT_DIR}")
  file(COPY_FILE "${SOLACE_ORT_FROM}" "${SOLACE_ORT_LIB}")
  file(CREATE_LINK "libonnxruntime.so.${SOLACE_ORT_VERSION}" "${SOLACE_ORT_DIR}/lib/libonnxruntime.so.1" SYMBOLIC)
  file(CREATE_LINK "libonnxruntime.so.1" "${SOLACE_ORT_DIR}/lib/libonnxruntime.so" SYMBOLIC)
  file(REMOVE_RECURSE "${SOLACE_ORT_UNZIP}")
  file(SHA256 "${SOLACE_ORT_LIB}" SOLACE_ORT_HAVE)
  if(NOT SOLACE_ORT_HAVE STREQUAL SOLACE_ORT_LIB_SHA256 OR NOT EXISTS "${SOLACE_ORT_DIR}/include/onnxruntime_cxx_api.h")
    file(REMOVE_RECURSE "${SOLACE_ORT_DIR}")
    message(FATAL_ERROR "The checked ONNX Runtime copy is incomplete")
  endif()
  file(WRITE "${SOLACE_ORT_MARK}" "${SOLACE_ORT_NUPKG_SHA256}")
endif()
message(STATUS "ONNX Runtime ${SOLACE_ORT_VERSION} checked: ${SOLACE_ORT_LIB}")

# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)

# The classifier plugin's library needs libonnxruntime.so.1 (the checked copy above) at run time, but its only search
# path was the runner's build folder, and the bundle carried just sherpa-onnx's libonnxruntime.so (another file, another
# name): found 2026-11-14, the app could not start on another machine. So the plugin also looks beside itself, and the
# checked library is installed there under the name it asks for (see the install rules below).
set_property(TARGET flutter_onnxruntime_plugin APPEND PROPERTY BUILD_RPATH "$ORIGIN")


# === Installation ===
# By default, "installing" just makes a relocatable bundle in the build
# directory.
set(BUILD_BUNDLE_DIR "${PROJECT_BINARY_DIR}/bundle")
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

# Start with a clean build bundle directory every time.
install(CODE "
  file(REMOVE_RECURSE \"${BUILD_BUNDLE_DIR}/\")
  " COMPONENT Runtime)

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}/lib")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

foreach(bundled_library ${PLUGIN_BUNDLED_LIBRARIES})
  install(FILES "${bundled_library}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endforeach(bundled_library)

# the checked ONNX Runtime for the classifier plugin, as a real file under its own name (its plugin's bundled entry is
# a symbolic link that sherpa-onnx's library of the same name replaces)
install(FILES "${SOLACE_ORT_LIB}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}" RENAME "libonnxruntime.so.1"
  COMPONENT Runtime)

# Copy the native assets provided by the build.dart from all packages.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/linux/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
   DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
   COMPONENT Runtime)

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
if(NOT CMAKE_BUILD_TYPE MATCHES "Debug")
  install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()
