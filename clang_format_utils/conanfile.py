from conan import ConanFile
from conan.tools.files import copy

class CMakeClangFormatUtils(ConanFile):
    name = "cmake_clang_format_utils"
    version = "1.0"
    package_type = "static-library"
    exports_sources = "*.cmake"

    def package(self):
        copy(self, "*.cmake", src=self.source_folder, dst=self.package_folder)

    def package_info(self):
        self.cpp_info.builddirs = ["."]