/*
 * Copyright (C) 2016 The Brenwill Workshop Ltd.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included
 * in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL
 * THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 */

#include "ShellMVK.h"
#include <mach/mach_time.h>
#include <cassert>
#include <sstream>
#include <dlfcn.h>
#include "Helpers.h"
#include "Game.h"

PosixTimer::PosixTimer()
{
    _tsBase = mach_absolute_time();
    mach_timebase_info_data_t timebase;
    mach_timebase_info(&timebase);
    _tsPeriod = (double)timebase.numer / (double)timebase.denom;
}

double PosixTimer::get()
{
    return (double)(mach_absolute_time() - _tsBase) * _tsPeriod / 1e9;
}

ShellMVK::ShellMVK(Game& game) : Shell(game)
{
    _timer = PosixTimer();
    _current_time = _timer.get();
    _profile_start_time = _current_time;
    _profile_present_count = 0;

    instance_extensions_.push_back(VK_EXT_METAL_SURFACE_EXTENSION_NAME);

    init_vk();
}

ShellMVK::~ShellMVK()
{
    destroy_context();
    cleanup_vk();
}

PFN_vkGetInstanceProcAddr ShellMVK::load_vk()
{
    return vkGetInstanceProcAddr;
}

bool ShellMVK::can_present(VkPhysicalDevice phy, uint32_t queue_family)
{
    return true;
}

VkSurfaceKHR ShellMVK::create_surface(VkInstance instance) {
    VkSurfaceKHR surface;

    VkResult err;
    VkMetalSurfaceCreateInfoEXT surface_info;
    surface_info.sType = VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT;
    surface_info.pNext = NULL;
    surface_info.flags = 0;
    surface_info.pLayer = _caMetalLayer;
    err = vkCreateMetalSurfaceEXT(instance, &surface_info, NULL, &surface);
    assert(!err);

    return surface;
}

void ShellMVK::update_and_draw() {

    acquire_back_buffer();

    double t = _timer.get();
    add_game_time(static_cast<float>(t - _current_time));

    present_back_buffer();

    _current_time = t;

    _profile_present_count++;
    if (_current_time - _profile_start_time >= 5.0) {
        const double fps = _profile_present_count / (_current_time - _profile_start_time);
        std::stringstream ss;
        ss << _profile_present_count << " presents in " <<
        _current_time - _profile_start_time << " seconds " <<
        "(FPS: " << fps << ")";
        log(LOG_INFO, ss.str().c_str());

        _profile_start_time = _current_time;
        _profile_present_count = 0;
    }
}

void ShellMVK::run(void* caMetalLayer) {
    _caMetalLayer = caMetalLayer;       // not retained
    create_context();
    resize_swapchain(settings_.initial_width, settings_.initial_height);
}
