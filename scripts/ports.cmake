cmake_minimum_required(VERSION 3.5)

macro(debug_message)
    if(DEFINED PORT_DEBUG AND PORT_DEBUG)
        message(STATUS "[DEBUG] ${ARGN}")
    endif()
endmacro()

#Detect .vcpkg-root to figure VCPKG_ROOT_DIR, starting from triplet folder.
set(VCPKG_ROOT_DIR_CANDIDATE ${CMAKE_CURRENT_LIST_DIR})

if(DEFINED VCPKG_ROOT_PATH)
    set(VCPKG_ROOT_DIR_CANDIDATE ${VCPKG_ROOT_PATH})
else()
    message(FATAL_ERROR [[
        Your vcpkg executable is outdated and is not compatible with the current CMake scripts.
        Please re-build vcpkg by running bootstrap-vcpkg.
    ]])
endif()

# fixup Windows drive letter to uppercase.
get_filename_component(VCPKG_ROOT_DIR_CANDIDATE ${VCPKG_ROOT_DIR_CANDIDATE} ABSOLUTE)

# Validate VCPKG_ROOT_DIR_CANDIDATE
if (NOT EXISTS "${VCPKG_ROOT_DIR_CANDIDATE}/.vcpkg-root")
    message(FATAL_ERROR "Could not find .vcpkg-root")
endif()

set(VCPKG_ROOT_DIR ${VCPKG_ROOT_DIR_CANDIDATE})

list(APPEND CMAKE_MODULE_PATH ${CMAKE_CURRENT_LIST_DIR}/cmake)
set(DOWNLOADS ${VCPKG_ROOT_DIR}/downloads CACHE PATH "Location to download sources and tools")
set(SCRIPTS ${CMAKE_CURRENT_LIST_DIR} CACHE PATH "Location to stored scripts")
set(PACKAGES_DIR ${VCPKG_ROOT_DIR}/packages CACHE PATH "Location to store package images")
set(BUILDTREES_DIR ${VCPKG_ROOT_DIR}/buildtrees CACHE PATH "Location to perform actual extract+config+build")

if(PORT)
    set(CURRENT_BUILDTREES_DIR ${BUILDTREES_DIR}/${PORT})
    set(CURRENT_PACKAGES_DIR ${PACKAGES_DIR}/${PORT}_${TARGET_TRIPLET})
endif()


if(CMD MATCHES "^BUILD$")
    set(CMAKE_TRIPLET_FILE ${TARGET_TRIPLET_FILE})
    if(NOT EXISTS ${CMAKE_TRIPLET_FILE})
        message(FATAL_ERROR "Unsupported target triplet. Triplet file does not exist: ${CMAKE_TRIPLET_FILE}")
    endif()

    if(NOT DEFINED CURRENT_PORT_DIR)
        message(FATAL_ERROR "CURRENT_PORT_DIR was not defined")
    endif()
    set(TO_CMAKE_PATH "${CURRENT_PORT_DIR}" CURRENT_PORT_DIR)
    if(NOT EXISTS ${CURRENT_PORT_DIR})
        message(FATAL_ERROR "Cannot find port: ${PORT}\n  Directory does not exist: ${CURRENT_PORT_DIR}")
    endif()
    if(NOT EXISTS ${CURRENT_PORT_DIR}/portfile.cmake)
        message(FATAL_ERROR "Port is missing portfile: ${CURRENT_PORT_DIR}/portfile.cmake")
    endif()
    if(NOT EXISTS ${CURRENT_PORT_DIR}/CONTROL AND NOT EXISTS ${CURRENT_PORT_DIR}/vcpkg.json)
        message(FATAL_ERROR "Port is missing control or manifest file: ${CURRENT_PORT_DIR}/{CONTROL,vcpkg.json}")
    endif()

    unset(PACKAGES_DIR)
    unset(BUILDTREES_DIR)

    if(EXISTS ${CURRENT_PACKAGES_DIR})
        file(GLOB FILES_IN_CURRENT_PACKAGES_DIR "${CURRENT_PACKAGES_DIR}/*")
        if(FILES_IN_CURRENT_PACKAGES_DIR)
            file(REMOVE_RECURSE ${FILES_IN_CURRENT_PACKAGES_DIR})
            file(GLOB FILES_IN_CURRENT_PACKAGES_DIR "${CURRENT_PACKAGES_DIR}/*")
            if(FILES_IN_CURRENT_PACKAGES_DIR)
                message(FATAL_ERROR "Unable to empty directory: ${CURRENT_PACKAGES_DIR}\n  Files are likely in use.")
            endif()
        endif()
    endif()
    file(MAKE_DIRECTORY ${CURRENT_BUILDTREES_DIR} ${CURRENT_PACKAGES_DIR})

    include(${CMAKE_TRIPLET_FILE})

    if (DEFINED VCPKG_PORT_CONFIGS)
        foreach(VCPKG_PORT_CONFIG ${VCPKG_PORT_CONFIGS})
            include(${VCPKG_PORT_CONFIG})
        endforeach()
    endif()

    set(TRIPLET_SYSTEM_ARCH ${VCPKG_TARGET_ARCHITECTURE})
    include(${SCRIPTS}/cmake/vcpkg_common_definitions.cmake)
    include(${SCRIPTS}/cmake/vcpkg_common_functions.cmake)
    include(${CURRENT_PORT_DIR}/portfile.cmake)
    include(${SCRIPTS}/build_info.cmake)
elseif(CMD MATCHES "^CREATE$")
    file(TO_NATIVE_PATH ${VCPKG_ROOT_DIR} NATIVE_VCPKG_ROOT_DIR)
    file(TO_NATIVE_PATH ${DOWNLOADS} NATIVE_DOWNLOADS)
    if(EXISTS ports/${PORT}/portfile.cmake)
        message(FATAL_ERROR "Portfile already exists: '${NATIVE_VCPKG_ROOT_DIR}\\ports\\${PORT}\\portfile.cmake'")
    endif()
    if(NOT FILENAME)
        get_filename_component(FILENAME "${URL}" NAME)
    endif()
    string(REGEX REPLACE "(\\.(zip|gz|tar|tgz|bz2))+\$" "" ROOT_NAME ${FILENAME})
    if(EXISTS ${DOWNLOADS}/${FILENAME})
        message(STATUS "Using pre-downloaded: ${NATIVE_DOWNLOADS}\\${FILENAME}")
        message(STATUS "If this is not desired, delete the file and ${NATIVE_VCPKG_ROOT_DIR}\\ports\\${PORT}")
    else()
        include(vcpkg_download_distfile)
        set(_VCPKG_INTERNAL_NO_HASH_CHECK "TRUE")
        vcpkg_download_distfile(ARCHIVE
            URLS ${URL}
            FILENAME ${FILENAME}
        )
        set(_VCPKG_INTERNAL_NO_HASH_CHECK "FALSE")
    endif()
    file(SHA512 ${DOWNLOADS}/${FILENAME} SHA512)

    file(MAKE_DIRECTORY ports/${PORT})
    configure_file(${SCRIPTS}/templates/portfile.in.cmake ports/${PORT}/portfile.cmake @ONLY)
    configure_file(${SCRIPTS}/templates/CONTROL.in ports/${PORT}/CONTROL @ONLY)

    message(STATUS "Generated portfile: ${NATIVE_VCPKG_ROOT_DIR}\\ports\\${PORT}\\portfile.cmake")
    message(STATUS "Generated CONTROL: ${NATIVE_VCPKG_ROOT_DIR}\\ports\\${PORT}\\CONTROL")
    message(STATUS "To launch an editor for these new files, run")
    message(STATUS "    .\\vcpkg edit ${PORT}")
endif()
