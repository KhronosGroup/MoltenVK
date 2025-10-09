#
# Copyright 2021 Adobe. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.
#
function(MoltenVK_Filter_Flags flags)
  include(CheckCXXCompilerFlag)
  include(CheckOBJCXXCompilerFlag)
  set(output_flags)
  foreach(FLAG IN ITEMS ${${flags}})
    string(REPLACE "=" "-" FLAG_VAR "${FLAG}")

    # Check if the flag is supported by the C++ compiler
    if(NOT DEFINED IS_SUPPORTED_${FLAG_VAR}_CXX)
      check_cxx_compiler_flag("${FLAG}" IS_SUPPORTED_${FLAG_VAR}_CXX)
    endif()
    if(IS_SUPPORTED_${FLAG_VAR}_CXX)
      list(APPEND output_flags $<$<COMPILE_LANGUAGE:CXX>:${FLAG}>)
    endif()

    # Check if the flag is supported by the Objective-C++ compiler
    if(NOT DEFINED IS_SUPPORTED_${FLAG_VAR}_OBJCXX)
      check_objcxx_compiler_flag("${FLAG}" IS_SUPPORTED_${FLAG_VAR}_OBJCXX)
    endif()
    if(IS_SUPPORTED_${FLAG_VAR}_OBJCXX)
      list(APPEND output_flags $<$<COMPILE_LANGUAGE:OBJCXX>:${FLAG}>)
    endif()
  endforeach()
  set(${flags} ${output_flags} PARENT_SCOPE)
endfunction()