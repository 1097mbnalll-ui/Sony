# Tarjuman core: chiaki-ng lib (LAN Remote Play) + C bridge for Swift.
# Builds static libraries for iOS (arm64) or, for testing, the host system.
cmake_minimum_required(VERSION 3.20)
project(tarjuman_core C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
option(TRJM_BUILD_TESTS "Build host smoke tests" OFF)

set(CHIAKI_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/chiaki-ng")
set(CHIAKI_LIB "${CHIAKI_DIR}/lib")
set(CHIAKI_TP "${CHIAKI_DIR}/third-party")

include(FetchContent)
set(FETCHCONTENT_QUIET ON)

# ---- mbedtls (crypto backend; easier to cross-compile than OpenSSL) ----
set(ENABLE_TESTING OFF CACHE BOOL "" FORCE)
set(ENABLE_PROGRAMS OFF CACHE BOOL "" FORCE)
set(USE_SHARED_MBEDTLS_LIBRARY OFF CACHE BOOL "" FORCE)
set(USE_STATIC_MBEDTLS_LIBRARY ON CACHE BOOL "" FORCE)
set(MBEDTLS_FATAL_WARNINGS OFF CACHE BOOL "" FORCE)
FetchContent_Declare(mbedtls
	GIT_REPOSITORY https://github.com/Mbed-TLS/mbedtls.git
	GIT_TAG v2.28.8
	GIT_SHALLOW TRUE)

# ---- opus (audio) ----
set(OPUS_BUILD_SHARED_LIBRARY OFF CACHE BOOL "" FORCE)
set(OPUS_BUILD_TESTING OFF CACHE BOOL "" FORCE)
set(OPUS_BUILD_PROGRAMS OFF CACHE BOOL "" FORCE)
set(OPUS_INSTALL_PKG_CONFIG_MODULE OFF CACHE BOOL "" FORCE)
set(OPUS_INSTALL_CMAKE_CONFIG_MODULE OFF CACHE BOOL "" FORCE)
FetchContent_Declare(opus
	GIT_REPOSITORY https://github.com/xiph/opus.git
	GIT_TAG v1.5.2
	GIT_SHALLOW TRUE)

FetchContent_MakeAvailable(mbedtls opus)

# ---- protobuf (nanopb) ----
find_package(Python3 REQUIRED COMPONENTS Interpreter)
set(PB_OUT "${CMAKE_CURRENT_BINARY_DIR}/pb")
file(MAKE_DIRECTORY "${PB_OUT}")
add_custom_command(
	OUTPUT "${PB_OUT}/takion.pb.c" "${PB_OUT}/takion.pb.h"
	COMMAND "${Python3_EXECUTABLE}" "${CHIAKI_TP}/nanopb/generator/nanopb_generator.py"
		-I "${CHIAKI_LIB}/protobuf" -D "${PB_OUT}" "${CHIAKI_LIB}/protobuf/takion.proto"
	DEPENDS "${CHIAKI_LIB}/protobuf/takion.proto"
	COMMENT "Generating takion protobuf (nanopb)")

add_library(trjm_nanopb STATIC
	"${CHIAKI_TP}/nanopb/pb_common.c"
	"${CHIAKI_TP}/nanopb/pb_decode.c"
	"${CHIAKI_TP}/nanopb/pb_encode.c")
target_include_directories(trjm_nanopb PUBLIC "${CHIAKI_TP}/nanopb")
target_compile_definitions(trjm_nanopb PUBLIC PB_C99_STATIC_ASSERT)

# ---- jerasure / gf-complete (FEC) ----
file(GLOB GF_SRC "${CHIAKI_TP}/gf-complete/src/gf*.c")
list(FILTER GF_SRC EXCLUDE REGEX "neon")
add_library(trjm_jerasure STATIC ${GF_SRC}
	"${CHIAKI_TP}/jerasure/src/galois.c"
	"${CHIAKI_TP}/jerasure/src/jerasure.c"
	"${CHIAKI_TP}/jerasure/src/reed_sol.c"
	"${CHIAKI_TP}/jerasure/src/cauchy.c"
	"${CHIAKI_TP}/jerasure/src/liberation.c")
target_include_directories(trjm_jerasure PUBLIC
	"${CHIAKI_TP}/gf-complete/include" "${CHIAKI_TP}/jerasure/include")
target_compile_options(trjm_jerasure PRIVATE -w)

# ---- chiaki lib (LAN only) ----
file(GLOB CHIAKI_SRC "${CHIAKI_LIB}/src/*.c")
list(FILTER CHIAKI_SRC EXCLUDE REGEX "/(aia|aia_openssl|ffmpegdecoder|pidecoder)\\.c$")
list(APPEND CHIAKI_SRC
	"${CHIAKI_LIB}/src/remote/rudp.c"
	"${CHIAKI_LIB}/src/remote/rudpsendbuffer.c"
	"${CMAKE_CURRENT_SOURCE_DIR}/stubs/remote_stubs.c"
	"${PB_OUT}/takion.pb.c")

set(CHIAKI_LIB_ENABLE_OPUS 1)
set(CHIAKI_LIB_ENABLE_PI_DECODER 0)
set(CHIAKI_LIB_ENABLE_FFMPEG_DECODER 0)
configure_file("${CHIAKI_LIB}/config.h.in" "${CMAKE_CURRENT_BINARY_DIR}/include/chiaki/config.h")

add_library(trjm_chiaki STATIC ${CHIAKI_SRC})
target_include_directories(trjm_chiaki
	PUBLIC "${CHIAKI_LIB}/include" "${CMAKE_CURRENT_BINARY_DIR}/include"
	PRIVATE "${PB_OUT}" "${CMAKE_CURRENT_SOURCE_DIR}/stubs/include")
target_include_directories(trjm_chiaki PRIVATE "${CMAKE_CURRENT_BINARY_DIR}/opus_inc")
target_compile_definitions(trjm_chiaki PUBLIC CHIAKI_LIB_ENABLE_MBEDTLS)
target_compile_options(trjm_chiaki PRIVATE -Wno-unused-function -Wno-deprecated-declarations)
target_link_libraries(trjm_chiaki PUBLIC trjm_nanopb trjm_jerasure mbedcrypto opus)
if(NOT APPLE)
	find_package(Threads REQUIRED)
	target_link_libraries(trjm_chiaki PUBLIC Threads::Threads m)
endif()

# chiaki includes <opus/opus.h>; expose opus headers under an "opus/" prefix.
file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/opus_inc/opus")
foreach(h opus.h opus_defines.h opus_types.h opus_multistream.h opus_projection.h)
	configure_file("${opus_SOURCE_DIR}/include/${h}" "${CMAKE_CURRENT_BINARY_DIR}/opus_inc/opus/${h}" COPYONLY)
endforeach()

# ---- Tarjuman bridge (simple C API consumed from Swift) ----
add_library(trjm_bridge STATIC bridge/trjm.c)
target_include_directories(trjm_bridge PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/bridge"
	PRIVATE "${CMAKE_CURRENT_BINARY_DIR}/opus_inc")
target_link_libraries(trjm_bridge PUBLIC trjm_chiaki)

if(TRJM_BUILD_TESTS)
	add_executable(trjm_smoke tests/smoke.c)
	target_link_libraries(trjm_smoke trjm_bridge)
endif()
