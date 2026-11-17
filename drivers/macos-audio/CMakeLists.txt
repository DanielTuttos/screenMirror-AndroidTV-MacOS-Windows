cmake_minimum_required(VERSION 3.12.0)

project(ScreenMirrorAudio CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# "-" = firma ad-hoc (suficiente para un driver local). Para distribuir, usar un Developer ID.
set(CODESIGN_ID "-" CACHE STRING "Codesign ID")

set(DRIVER_NAME "ScreenMirrorAudio")
set(DRIVER_VERSION "1.0.0")
set(DRIVER_COPYRIGHT "ScreenMirror")
set(DRIVER_IDENTIFIER "tv.screenmirror.audio")
set(DRIVER_UID "5C1F8A52-3E7B-4D19-9A64-0B8E2F7D3C41")
set(DRIVER_ENTRYPOINT "ScreenMirrorAudioEntryPoint")

# libASPL fijada por commit: el build es reproducible y no depende de «master».
include(ExternalProject)
ExternalProject_Add(libASPL_dependency
  GIT_REPOSITORY https://github.com/gavv/libASPL.git
  GIT_TAG 633e0f70203edd87d320fc5a3cae901e1363aac5
  BINARY_DIR ${CMAKE_CURRENT_BINARY_DIR}/libASPL-build
  INSTALL_DIR ${CMAKE_CURRENT_BINARY_DIR}/libASPL-prefix
  CMAKE_ARGS -DCMAKE_INSTALL_PREFIX=<INSTALL_DIR>
  LOG_DOWNLOAD YES
  LOG_CONFIGURE YES
  LOG_BUILD YES
  LOG_INSTALL YES
)

# MODULE = bundle Mach-O cargable (lo que espera coreaudiod), no una .dylib.
add_library(${DRIVER_NAME} MODULE "Driver.cpp")
add_dependencies(${DRIVER_NAME} libASPL_dependency)
target_include_directories(${DRIVER_NAME} PRIVATE ${CMAKE_CURRENT_BINARY_DIR}/libASPL-prefix/include)
target_link_libraries(${DRIVER_NAME} PRIVATE ${CMAKE_CURRENT_BINARY_DIR}/libASPL-prefix/lib/libASPL.a)

find_library(LIB_CoreFoundation CoreFoundation REQUIRED)
target_link_libraries(${DRIVER_NAME} PRIVATE ${LIB_CoreFoundation})

set_target_properties(${DRIVER_NAME} PROPERTIES
  OUTPUT_NAME "${DRIVER_NAME}"
  BUNDLE true
  BUNDLE_EXTENSION "driver"
  PREFIX ""
  SUFFIX ""
  MACOSX_BUNDLE ON
  MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/Info.plist.in"
  MACOSX_BUNDLE_BUNDLE_NAME "${DRIVER_NAME}"
  MACOSX_BUNDLE_BUNDLE_VERSION "${DRIVER_VERSION}"
  MACOSX_BUNDLE_COPYRIGHT "${DRIVER_COPYRIGHT}"
  MACOSX_BUNDLE_GUI_IDENTIFIER "${DRIVER_IDENTIFIER}"
  MACOSX_BUNDLE_SHORT_VERSION_STRING "${DRIVER_VERSION}"
)

add_custom_command(
  TARGET ${DRIVER_NAME}
  POST_BUILD
  COMMENT "Firmando ${DRIVER_NAME}.driver (${CODESIGN_ID})"
  VERBATIM
  COMMAND codesign --force -s "${CODESIGN_ID}" "${CMAKE_CURRENT_BINARY_DIR}/${DRIVER_NAME}.driver"
)
