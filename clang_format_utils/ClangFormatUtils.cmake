find_package(ClangFormat QUIET)

if(NOT CLANG_FORMAT_FOUND)
    find_program(CLANG_FORMAT_EXECUTABLE NAMES clang-format)
    if(CLANG_FORMAT_EXECUTABLE)
        set(CLANG_FORMAT_FOUND TRUE)
    endif()
endif()

if(CLANG_FORMAT_FOUND)
    execute_process(COMMAND "${CLANG_FORMAT_EXECUTABLE}" --version 
        OUTPUT_VARIABLE CLANG_FORMAT_VERSION)
    string(REGEX MATCH "[^\n]*version[^\n]*" CLANG_FORMAT_VERSION "${CLANG_FORMAT_VERSION}")
    string(STRIP "${CLANG_FORMAT_VERSION}" CLANG_FORMAT_VERSION)
    message(STATUS "Clang-format: ${CLANG_FORMAT_VERSION}")
endif()

function(add_clang_format_target clang_format_utility_target_name)
    if(NOT CLANG_FORMAT_FOUND)
        message(WARNING "clang-format not found, skipping format target creation for ${clang_format_utility_target_name}")
        return()
    endif()

    set(options "")
    set(oneValueArgs TARGET)
    set(multiValueArgs ARGS)
    cmake_parse_arguments(_clang_format "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    if(NOT _clang_format_TARGET)
        message(FATAL_ERROR "TARGET argument is required for add_clang_format_target")
    endif()

    # Get all sources and headers from the target
    get_target_property(TARGET_SOURCES ${_clang_format_TARGET} SOURCES)
    get_target_property(TARGET_SOURCES_DIR ${_clang_format_TARGET} SOURCE_DIR)
    get_target_property(HEADER_SETS ${_clang_format_TARGET} HEADER_SETS)
    get_target_property(INTERFACE_HEADER_SETS ${_clang_format_TARGET} INTERFACE_HEADER_SETS)

    set(ALL_FILES "")
    foreach(source_file ${TARGET_SOURCES})
        if(source_file MATCHES "-NOTFOUND")
            continue()
        endif()
        if(NOT IS_ABSOLUTE "${source_file}")
            string(PREPEND source_file "${TARGET_SOURCES_DIR}/")
        endif()
        list(APPEND ALL_FILES "${source_file}")
    endforeach()

    foreach(SET_NAME ${HEADER_SETS} ${INTERFACE_HEADER_SETS})
        if(SET_NAME MATCHES "-NOTFOUND")
            continue()
        endif()
        get_target_property(SET_FILES ${_clang_format_TARGET} HEADER_SET_${SET_NAME})
        if(SET_FILES)
            list(APPEND ALL_FILES ${SET_FILES})
        endif()
    endforeach()

    if(NOT ALL_FILES)
        message(WARNING "No sources or header sets found for target ${_clang_format_TARGET}")
        return()
    endif()

    list(REMOVE_DUPLICATES ALL_FILES)

    set(FORMAT_COMMAND "${CLANG_FORMAT_EXECUTABLE}" ${_clang_format_ARGS})

    if(NOT TARGET ${clang_format_utility_target_name})
        set(FORMAT_FILES "${CMAKE_CURRENT_BINARY_DIR}/${clang_format_utility_target_name}.files")
        file(GENERATE OUTPUT "${FORMAT_FILES}"
            CONTENT "$<JOIN:$<FILTER:$<TARGET_PROPERTY:${clang_format_utility_target_name},SOURCES>,EXCLUDE,CMakeFiles/>,\n>\n")

        add_custom_target(${clang_format_utility_target_name}
            COMMAND ${FORMAT_COMMAND} "--files=${FORMAT_FILES}"
            COMMENT "Formatting ${clang_format_utility_target_name} with clang-format"
            WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
            VERBATIM
        )
    endif()

    if(ALL_FILES)
        target_sources(${clang_format_utility_target_name} PRIVATE ${ALL_FILES})
    endif()
    
endfunction()

function(clang_format_targets_collection_begin)
    set_property(GLOBAL PROPERTY CMAKE_CLANG_FORMAT_TARGETS_LIST)
endfunction()

function(clang_format_targets_collection_append)
    set_property(GLOBAL APPEND PROPERTY CMAKE_CLANG_FORMAT_TARGETS_LIST ${ARGN})
endfunction()

function(clang_format_targets_collection_process clang_format_utility_target_name)
	get_property(format_targets GLOBAL PROPERTY CMAKE_CLANG_FORMAT_TARGETS_LIST)
	
	foreach(target ${format_targets})
        add_clang_format_target(${clang_format_utility_target_name} TARGET ${target} ARGS ${ARGN})
    endforeach()
endfunction()
