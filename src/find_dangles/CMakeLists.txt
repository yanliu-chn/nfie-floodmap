cmake_minimum_required(VERSION 2.8)
project(find_dangles CXX)

if (CMAKE_VERSION VERSION_LESS "3.1")
    if (CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
      set (CMAKE_CXX_FLAGS "-std=c++0x ${CMAKE_CXX_FLAGS}")
    endif ()
else ()
    set (CMAKE_CXX_STANDARD 11)
endif ()

# GDAL is required
find_package(GDAL REQUIRED)
include_directories(${GDAL_INCLUDE_DIR})

add_executable (find_dangles src/find_dangles.cpp)

target_link_libraries(find_dangles ${GDAL_LIBRARY})

install(TARGETS find_dangles DESTINATION bin)

