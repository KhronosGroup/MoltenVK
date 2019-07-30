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

#ifndef SHELL_MVK_H
#define SHELL_MVK_H

#include <MoltenVK/mvk_vulkan.h>
#include "Shell.h"
#include <sys/time.h>

class PosixTimer {
public:
    double get();
    PosixTimer();

protected:
    uint64_t _tsBase;
    double _tsPeriod;
};

class ShellMVK : public Shell {
public:
    ShellMVK(Game &game);
    ~ShellMVK();

    void run(void* view);
    void update_and_draw();

    void run() { run(nullptr); };
    void quit() { }

protected:
    void* _caMetalLayer;
    PosixTimer _timer;
    double _current_time;
    double _profile_start_time;
    int _profile_present_count;

    PFN_vkGetInstanceProcAddr load_vk();
    bool can_present(VkPhysicalDevice phy, uint32_t queue_family);

    VkSurfaceKHR create_surface(VkInstance instance);
};

#endif // SHELL_MVK_H
