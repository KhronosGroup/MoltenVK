#include <MoltenVK/mvk_vulkan.h>
#include <stdbool.h>
#ifndef TRUE
#define TRUE true
#endif
#ifndef FALSE
#define FALSE false
#endif
#include "cube.c"

static struct demo g_demo;

void cube_runner_start(void* caMetalLayer) {
    memset(&g_demo, 0, sizeof(g_demo));

#if TARGET_OS_SIMULATOR
    // Avoid linear host-coherent texture loading on simulator
    const char* argv[] = { "cube", "--use_staging" };
    demo_main(&g_demo, caMetalLayer, 2, argv);
#else
    const char* argv[] = { "cube" };
    demo_main(&g_demo, caMetalLayer, 1, argv);
#endif
}

void cube_runner_draw(void)   { demo_draw(&g_demo); }
void cube_runner_resize(void) { demo_resize(&g_demo); }
void cube_runner_stop(void)   { demo_cleanup(&g_demo); }
