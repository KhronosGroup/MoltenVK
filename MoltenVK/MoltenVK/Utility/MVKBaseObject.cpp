/*
 * MVKBaseObject.cpp
 *
 * Copyright (c) 2014-2017 The Brenwill Workshop Ltd. (http://www.brenwill.com)
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 * 
 *     http://www.apache.org/licenses/LICENSE-2.0
 * 
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include "MVKBaseObject.h"
#include <stdlib.h>
#include <cxxabi.h>

using namespace std;


#pragma mark -
#pragma mark MVKBaseObject

string MVKBaseObject::className() {
    int status;
    char* demangled = abi::__cxa_demangle(typeid(*this).name(), 0, 0, &status);
    string clzName = demangled;
    free(demangled);
    return clzName;
}
