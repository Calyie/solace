cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME}
  "main.cc"
  "my_application.cc"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the application ID.
add_definitions(-DAPPLICATION_ID="${APPLICATION_ID}")

# AIR-3: the operating system's network block (net_block.h) in release builds only; debug and profile builds are reached
# by Flutter's tools through the Dart VM service on a loopback internet socket.
target_compile_definitions(${BINARY_NAME} PRIVATE "$<$<CONFIG:Release>:SOLACE_RELEASE_NET_BLOCK>")

# Solace Home (docs/HOME_SERVER.md): a build made with --dart-define=SOLACE_HOME=true, which Flutter writes base64-encoded
# into the generated config ("U09MQUNFX0hPTUU9dHJ1ZQ==" is "SOLACE_HOME=true"), lets TCP and UDP sockets through the
# network block (net_block.h SOLACE_HOME_NET) so the paired home server can be reached. Every other build keeps the
# block exactly as it was.
set(SOLACE_GENERATED_CONFIG "${CMAKE_CURRENT_SOURCE_DIR}/../flutter/ephemeral/generated_config.cmake")
if(EXISTS "${SOLACE_GENERATED_CONFIG}")
  file(STRINGS "${SOLACE_GENERATED_CONFIG}" SOLACE_DART_DEFINES REGEX "DART_DEFINES=")
  if(SOLACE_DART_DEFINES MATCHES "(DART_DEFINES=|,)U09MQUNFX0hPTUU9dHJ1ZQ==(,|\"|$)")
    target_compile_definitions(${BINARY_NAME} PRIVATE SOLACE_HOME_NET)
    message(STATUS "Solace Home build: the network block lets TCP and UDP sockets through")
  endif()
endif()

# Add dependency libraries. Add any application-specific dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK)

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")
