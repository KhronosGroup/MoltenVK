/*
 * Samples.h
 *
 * Copyright (c) 2014-2018 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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


/** 
 * Loads the appropriate sample code, as indicated by the appropriate compiler build setting below.
 *
 * To select a sample to run, define one (and only one) of the macros below, either by adding
 * a #define XXX statement at the top of this file, or more flexibily, by adding the macro value
 * to the Preprocessor Macros (aka GCC_PREPROCESSOR_DEFINITIONS) compiler setting.
 *
 * To add a compiler setting, select the project in the Xcode Project Navigator panel, 
 * select the Build Settings panel, and add the value to the Preprocessor Macros 
 * (aka GCC_PREPROCESSOR_DEFINITIONS) entry.
 *
 * If you choose to add a #define statement to this file, be sure to clear the existing macro
 * from the Preprocessor Macros (aka GCC_PREPROCESSOR_DEFINITIONS) compiler setting in Xcode.
 */

#include <MoltenVK/mvk_vulkan.h>

// Rename main() in sample file so it won't conflict with the application main()
#define main(argc, argv)		sample_main(argc, argv)


#ifdef MVK_SAMP_15_draw_cube
#	include "../VulkanSamples/API-Samples/15-draw_cube/15-draw_cube.cpp"
#endif

#ifdef MVK_SAMP_copy_blit_image
#	include "../VulkanSamples/API-Samples/copy_blit_image/copy_blit_image.cpp"
#endif

#ifdef MVK_SAMP_draw_subpasses
#	include "../VulkanSamples/API-Samples/draw_subpasses/draw_subpasses.cpp"
#endif

#ifdef MVK_SAMP_draw_textured_cube
#	include "../VulkanSamples/API-Samples/draw_textured_cube/draw_textured_cube.cpp"
#endif

#ifdef MVK_SAMP_dynamic_uniform
#	include "../VulkanSamples/API-Samples/dynamic_uniform/dynamic_uniform.cpp"
#endif

#ifdef MVK_SAMP_immutable_sampler
#	include "../VulkanSamples/API-Samples/immutable_sampler/immutable_sampler.cpp"
#endif

#ifdef MVK_SAMP_memory_barriers
#	include "../VulkanSamples/API-Samples/memory_barriers/memory_barriers.cpp"
#endif

#ifdef MVK_SAMP_multiple_sets
#	include "../VulkanSamples/API-Samples/multiple_sets/multiple_sets.cpp"
#endif

#ifdef MVK_SAMP_multithreaded_command_buffers
#	include "../VulkanSamples/API-Samples/multithreaded_command_buffers/multithreaded_command_buffers.cpp"
#endif

#ifdef MVK_SAMP_occlusion_query         
#	include "../VulkanSamples/API-Samples/occlusion_query/occlusion_query.cpp"
#endif

#ifdef MVK_SAMP_pipeline_cache
#	include "../VulkanSamples/API-Samples/pipeline_cache/pipeline_cache.cpp"
#endif

#ifdef MVK_SAMP_push_constants
#	include "../VulkanSamples/API-Samples/push_constants/push_constants.cpp"
#endif

#ifdef MVK_SAMP_secondary_command_buffer
#	include "../VulkanSamples/API-Samples/secondary_command_buffer/secondary_command_buffer.cpp"
#endif

#ifdef MVK_SAMP_separate_image_sampler
#	include "../VulkanSamples/API-Samples/separate_image_sampler/separate_image_sampler.cpp"
#endif

#ifdef MVK_SAMP_template
#	include "../VulkanSamples/API-Samples/template/template.cpp"
#endif

#ifdef MVK_SAMP_texel_buffer
#	include "../VulkanSamples/API-Samples/texel_buffer/texel_buffer.cpp"
#endif



