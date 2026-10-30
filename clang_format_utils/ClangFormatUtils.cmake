if(CMAKE_VERSION VERSION_LESS 3.30)
    message(FATAL_ERROR "ClangFormatUtils requires CMake 3.30 or newer")
endif()
cmake_policy(SET CMP0163 NEW)

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

function(_clang_format_contains_generator_expression output value)
    string(FIND "${value}" "$<" position)
    if(position EQUAL -1)
        set(${output} FALSE PARENT_SCOPE)
    else()
        set(${output} TRUE PARENT_SCOPE)
    endif()
endfunction()

function(_clang_format_resolve_target_source output source_dir binary_dir source_file)
    _clang_format_contains_generator_expression(is_expression "${source_file}")
    if(is_expression OR IS_ABSOLUTE "${source_file}")
        set(${output} "${source_file}" PARENT_SCOPE)
        return()
    endif()

    set(source_path "${source_dir}/${source_file}")
    set(binary_path "${binary_dir}/${source_file}")

    # Query the binary path only when the source path does not exist: querying
    # a nonexistent binary path can affect CMake's later source resolution.
    if(NOT EXISTS "${source_path}")
        get_source_file_property(is_generated "${binary_path}" GENERATED)
        if(is_generated OR EXISTS "${binary_path}")
            set(source_path "${binary_path}")
        endif()
    endif()

    set(${output} "${source_path}" PARENT_SCOPE)
endfunction()

function(_clang_format_resolve_header output source_dir header_file)
    _clang_format_contains_generator_expression(is_expression "${header_file}")
    if(NOT is_expression AND NOT IS_ABSOLUTE "${header_file}")
        set(header_file "${source_dir}/${header_file}")
    endif()
    set(${output} "${header_file}" PARENT_SCOPE)
endfunction()

function(_clang_format_append_files output)
    set(files "${${output}}")
    foreach(file IN LISTS ARGN)
        _clang_format_contains_generator_expression(is_expression "${file}")
        if(NOT is_expression)
            get_source_file_property(is_generated "${file}" GENERATED)
            if(is_generated)
                continue()
            endif()
        endif()
        list(APPEND files "${file}")
    endforeach()
    set(${output} "${files}" PARENT_SCOPE)
endfunction()

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
    get_target_property(TARGET_BINARY_DIR ${_clang_format_TARGET} BINARY_DIR)
    get_target_property(HEADER_SETS ${_clang_format_TARGET} HEADER_SETS)
    get_target_property(INTERFACE_HEADER_SETS ${_clang_format_TARGET} INTERFACE_HEADER_SETS)

    set(RESOLVED_SOURCES "")
    foreach(source_file ${TARGET_SOURCES})
        if(source_file MATCHES "-NOTFOUND")
            continue()
        endif()
        _clang_format_resolve_target_source(source_path "${TARGET_SOURCES_DIR}" "${TARGET_BINARY_DIR}" "${source_file}")
        list(APPEND RESOLVED_SOURCES "${source_path}")
    endforeach()
    set(RESOLVED_HEADERS "")
    foreach(SET_NAME ${HEADER_SETS} ${INTERFACE_HEADER_SETS})
        if(SET_NAME MATCHES "-NOTFOUND")
            continue()
        endif()
        get_target_property(SET_FILES ${_clang_format_TARGET} HEADER_SET_${SET_NAME})
        if(SET_FILES)
            foreach(header_file IN LISTS SET_FILES)
                _clang_format_resolve_header(header_path "${TARGET_SOURCES_DIR}" "${header_file}")
                list(APPEND RESOLVED_HEADERS "${header_path}")
            endforeach()
        endif()
    endforeach()

    set(ALL_FILES "")
    _clang_format_append_files(ALL_FILES ${RESOLVED_SOURCES} ${RESOLVED_HEADERS})

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
            COMMENT "Running clang-format: ${clang_format_utility_target_name}"
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
