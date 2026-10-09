MIN_DEPTH :: 0.0;
MAX_DEPTH :: 1.0;
VK_API_VERSION_1_3 :: #run VK_MAKE_VERSION(1, 3, 0);
TERM_RENDERER_VERSION :: #run VK_MAKE_VERSION(
    TeRM_Render_Version.MAJOR, TeRM_Render_Version.MINOR, 0
);
DEPTH_FORMAT :: VkFormat.D24_UNORM_S8_UINT;
INVALID_MEMORY_TYPE_INDEX : u32 : 0xffff_ffff;

Renderer :: struct {
    API :: "vulkan";
    API_VERSION :: VK_API_VERSION_1_3;

    // when multithreading with multiple renderers, this data should be copied.
    using shared_data: struct {
        // your application name
        application_name := "your graphics application";
        // your application version
        application_version := #run VK_MAKE_VERSION(0, 1, 0);

        // change this if you want
        engine_name := "Ack! renderer";
        engine_version := TERM_RENDERER_VERSION;

        msaa_samples := 1;

        delta_time: float32;
        unscaled_delta_time: float32;
        
        global_shader_time: float32;
        global_shader_delta_time: float32;

        window: Window_Type;

        clear_color: Color4f = COLOR4F_WHITE;

        vk_instance: VkInstance;
        surface: VkSurfaceKHR;
        physical: Physical_Device;
        logical: Logical_Device;
        swapchain: Swapchain;
        frames: []Graphics_Frame;

        view_mode: Renderer_View_Mode;

        transfer_command_pool: VkCommandPool;
        transfer_command_buffer: VkCommandBuffer;
        transfer_fence: VkFence;
        transfer_buffer_memory_barriers: Buffer_Memory_Barrier_Collection;

        graphics_queue: VkQueue; // per thread?
        transfer_queue: VkQueue; // per thread?

        descriptor_pool: VkDescriptorPool;

        imgui_context: ImGui.ImGuiContext;
        imgui_descriptor_pool: VkDescriptorPool;
        user_imgui_callback: ();

        rendered_frame_count: s32;

        // todo: putting a single view on an Image is proving probably not right?
        depth_buffer: *GPU_Image;
        depth_buffer_visualize_view: VkImageView;

        init_success: bool;

        camera_info: Camera_Info;
        camera_position: Vector3;
        camera_orientation: Quaternion;
        light_direction: Vector3 = {0,0,-1};

        max_texture_count: int;

        gpu_heap_pool: Pool(GPU_Heap);
        image_pool: Pool(GPU_Image);

        linear_allocators: [GPU_HEAP_TYPE_COUNT]GPU_Linear_Allocator;

        depth_sampler_descriptor_set_layout: VkDescriptorSetLayout;
        depth_sampler_pipeline_layout: VkPipelineLayout;
        depth_sampler_pipeline: VkPipeline;

        textures_descriptor_set_layout: VkDescriptorSetLayout;
        textures_descriptor_set: VkDescriptorSet;

        materials_storage_buffer_descriptor_set: VkDescriptorSet;
        materials_storage_buffer: GPU_Buffer;

        uniform_buffer_descriptor_set_layout: VkDescriptorSetLayout;
        storage_buffer_descriptor_set_layout: VkDescriptorSetLayout;

        billboard_vertex_buffer: GPU_Buffer;

        billboard_pipeline_layout: VkPipelineLayout;
        billboard_pipeline: VkPipeline;

        opaque_mesh_pipeline_layout: VkPipelineLayout;
        opaque_mesh_pipeline: VkPipeline;

        opaque_skinned_mesh_pipeline_layout: VkPipelineLayout;
        opaque_skinned_mesh_pipeline: VkPipeline;

        transparent_mesh_pipeline: VkPipeline;
        transparent_skinned_mesh_pipeline: VkPipeline;
        
        draw_in_front_opaque_line_pipeline: VkPipeline;
        opaque_line_pipeline: VkPipeline;

        draw_in_front_transparent_line_pipeline: VkPipeline;

        particle_draws: [..]Billboard_Instance;
        static_mesh_draws: [..]Static_Mesh_Draw;
        skinned_mesh_draws: [..]Skinned_Mesh_Draw;
        skinning_joints: [..]Matrix4;
        mesh_draw_specializations: [..]Mesh_Specialization_Params;

        in_front_line_draws: [..]Line_Draw;
        line_draws: [..]Line_Draw;
        transparent_in_front_line_draws: [..]Line_Draw;

        timed_in_front_line_draws: [..]Timed_Draw(Line_Draw);
        timed_line_draws: [..]Timed_Draw(Line_Draw);

        debug_switch: bool;

        prepared_opaque_static_mesh_draw_commands: [..]VkDrawIndexedIndirectCommand;
        prepared_opaque_skinned_mesh_draw_commands: [..]VkDrawIndexedIndirectCommand;
        prepared_in_front_line_draw_batches: [..]Line_Draw_Batch;
        prepared_line_draw_batches: [..]Line_Draw_Batch;
        prepared_transparent_in_front_line_draw_batches: [..]Line_Draw_Batch;

        last_mesh_draw_was_static: bool;
        in_the_middle_of_rendering: bool;
    };

    texture_references: []Texture_Ref;
    mesh_references: []Mesh_Ref;

    meshes: [..]Mesh;
    materials: Pool(Material);

    billboard_vertices := Static_Mesh_Vertex.[
        {position={-0.5, -0.5, 0}, uv_0={0, 0}},
        {position={ 0.5, -0.5, 0}, uv_0={1, 0}},
        {position={ 0.5,  0.5, 0}, uv_0={1, 1}},
        {position={-0.5, -0.5, 0}, uv_0={0, 0}},
        {position={ 0.5,  0.5, 0}, uv_0={1, 1}},
        {position={-0.5,  0.5, 0}, uv_0={0, 1}},
    ];

    sampler_table: Table(u32, VkSampler);
    shader_table: Table(string, VkShaderModule);
}

Renderer_View_Mode :: enum u8 {
    LIT;
    DEPTH;
}

MAX_MATERIALS :: 1024;
MAX_STATIC_MESHES :: 128_000;
MAX_SKINNED_MESHES :: 64_000;
MAX_SKINNING_JOINTS :: MAX_SKINNED_MESHES * 8;
MAX_GPU_HEAPS :: 128;
MAX_UNIQUE_MESHES :: 1_000;

Line_Draw_Batch :: struct {
    buffer: GPU_Buffer;
    width: float32;
    count: s32;
}

GPU_Material :: struct {
    albedo_factor: Vector4;
    emissive_factor: Vector4;
    metallic_factor: float;
    roughness_factor: float;

    alpha_cutoff: float;

    albedo_uv: s32;
    metallic_uv: s32;
    roughness_uv: s32;
    normal_uv: s32;
    occlusion_uv: s32;
    emissive_uv: s32;

    albedo_tex: s32;
    normal_tex: s32;
    emissive_tex: s32;
    orm_tex: s32;
};

Mesh_Specialization_Flash :: struct {
    rate: float = -1;
    value: float;
    begin_time: float;
}

Mesh_Specialization_Tint :: struct {
    using color: Color3f = {1,1,1};
}

#insert #run generate_mesh_specialization_params(.[
    {"flash", Mesh_Specialization_Flash},
    {"tint",  Mesh_Specialization_Tint},
]);

Mesh_Specialization_Field_Create_Info :: struct {
    name: string;
    type: Type;
}

generate_mesh_specialization_params :: (fields: []Mesh_Specialization_Field_Create_Info) -> string {
    // flag count
    assert(fields.count <= 32);

    builder: String_Builder;

    print(*builder, "Mesh_Specialization_Params :: struct {\n");
    print(*builder, "\tflags: Mesh_Specialization_Flags;\n");
    for fields {
        print(*builder, "\t%: %;\n", it.name, it.type);
    }
    print(*builder, "}\n");

    print(*builder, "Mesh_Specialization_Flags :: enum_flags s32 {\n");
    for fields {
        print(*builder, "\t%;\n", to_upper(it.name));
    }
    print(*builder, "}\n");

    return builder_to_string(*builder);
}

// todo: specialization params should be put into their own buffer
// and speicalized instances will have an index if they are specialised.

Mesh_Instance_Shader_Data :: struct {
    transform: Matrix4;
    layer: Draw_Layer;
    specialization: Mesh_Specialization_Params #align 4;
}

Skinned_Mesh_Instance_Shader_Data :: struct {
    transform: Matrix4;
    layer: Draw_Layer;
    joint_offset: s32;
    specialization: Mesh_Specialization_Params #align 4;
};

// this is on the per-draw level
Mesh_Section_Shader_Data :: struct {
    mesh_instance_offset: s32;
    mesh_instance_count:  s32;
    material: s32;
}

Draw_Layer :: enum u32 {
    GAME; // farthest layer. uses vast majority of z-space.
    LAYER_1; // closest of the near layers
    LAYER_2;
    LAYER_3;
    LAYER_4;
    LAYER_5; // farthest of the near layers
}

Static_Mesh_Draw :: struct {
    ref: Mesh_Ref;
    position: Vector3;
    orientation: Quaternion;
    scale: Vector3;
    layer: Draw_Layer;
    specialization : s32 = -1;
}

Timed_Draw :: struct($draw_type: Type) {
    draw: draw_type;
    time_remaining: float32;
}

Skinned_Mesh_Draw :: struct {
    using static_draw: Static_Mesh_Draw;

    using joint_data: union {
        // set when using the draw interface
        using _interface: struct {
            pose: *Skeletal_Pose;
        };
        // for internal use, points into the renderer's skinning joints array.
        using _internal: struct {
            joint_offset: s32;
        };
    }
}

get_animation_blends :: inline (draw: *Skinned_Mesh_Draw) -> []Skeletal_Animation_Blend {
    blends: []Skeletal_Animation_Blend = ---; 
    blends.data  = draw.blends.data;
    blends.count = draw.blend_count;
    return blends;
}

Line_Draw :: struct {
    a: Vector3;
    b: Vector3;
    color: Color4b;
    width: float;
}

Particle_Draw :: struct {
    position: Vector3;
    color: Color4b = #run to_color4b(COLOR4F_WHITE);
    scale: float = 1.0;
    texture_index: s16 = -1;
    layer: Draw_Layer;
}

Texture_Ref :: struct {
    path: string;
    using texture: Texture;
}


Render_Init_Options :: struct {
    populate_shader_data_in_working_directory := true;
    initialize_dev_gui := true;
    max_texture_count := 4096;
}

Queue_Family_Capability_Flags :: enum_flags {
    PRESENT;
    GRAPHICS;
    COMPUTE;
    TRANSFER;
}

Buffer_Memory_Barrier_Collection :: struct {
    barriers: [..]VkBufferMemoryBarrier;
    pipeline_stage_flags: VkPipelineStageFlags;
}

Queue_Family_Indices :: struct {
    present_index:  u32 = U32_MAX;
    graphics_index: u32 = U32_MAX;
    compute_index:  u32 = U32_MAX;
    transfer_index: u32 = U32_MAX;
    #overlay(present_index) array: [4]u32 = ---;
}

Physical_Device :: struct {
    obj: VkPhysicalDevice;
    type: VkPhysicalDeviceType;
    size: VkDeviceSize;
    queue_family_indices: Queue_Family_Indices;
    properties: Physical_Device_Properties;
}

Logical_Device :: struct {
    obj: VkDevice;
}

Physical_Device_Vendor :: enum u32 {
    UNKNOWN;
    NVIDIA;
    AMD;
    INTEL;
    ARM;
    QUALCOMM;
    IMGTEC;
}

Physical_Device_Driver_Version :: struct {
    major: s32      = -1;
    minor: s32      = -1;
    secondary: s32  = -1;
    tertiary: s32   = -1;
    #overlay(secondary) patch: s32 = ---;
    #overlay(major) array: [4]s32;
}

Graphics_API_Version :: struct {
    major: u32;
    minor: u32;
    patch: u32;
}

DEFAULT_BUFFER_HEAP_SIZE : int :  16 * 1024 * 1024;
DEFAULT_IMAGE_HEAP_SIZE  : int : 128 * 1024 * 1024;
VERTEX_BUFFER_SIZE       : int :  96 * 1024 * 1024;
INDEX_BUFFER_SIZE        : int :  32 * 1024 * 1024;

GPU_Heap_Type :: enum u8 {
    DEVICE_LOCAL_BUFFER;
    HOST_VISIBLE_BUFFER;
    VERTEX_BUFFER;
    SKINNED_VERTEX_BUFFER;
    INDEX_BUFFER; // if this isn't the last buffer type, update is_buffer_type
    DEVICE_LOCAL_IMAGE; // if this isn't the first image type, update is_buffer_type
    HOST_VISIBLE_IMAGE;
}

GPU_HEAP_TYPE_COUNT :: #run enum_highest_value(GPU_Heap_Type) + 1;

is_buffer_type :: (heap_type: GPU_Heap_Type) -> bool {
    return heap_type <= .INDEX_BUFFER;
}

is_image_type :: (heap_type: GPU_Heap_Type) -> bool {
    return !is_buffer_type(heap_type);
}

is_host_visible_type :: (heap_type: GPU_Heap_Type) -> bool {
    if heap_type == {
    case .HOST_VISIBLE_BUFFER;
        return true;
    case .HOST_VISIBLE_IMAGE;
        return true;
    }
    return false;
}

is_device_local_type :: (heap_type: GPU_Heap_Type) -> bool {
    return !is_host_visible_type(heap_type);
}

GPU_Heap :: struct {
    memory: VkDeviceMemory;
    size: int;

    type: GPU_Heap_Type;
    allocator: GPU_Allocator;

    // these fields are only valid if this is a heap for allocating buffers
    buffer: VkBuffer; 
    buffer_usage: VkBufferUsageFlags;
    buffer_min_alignment: u32;

    is_valid: bool;
}

GPU_Allocator :: enum u8 {
    LINEAR_ALLOCATOR;
}

GPU_Allocation :: struct {
    source_heap: s16 = -1;
    allocator_heap_index: s16;
    source_heap_offset: s32;
    size: u32;
}

GPU_Image :: struct {
    using #as allocation: GPU_Allocation;
    obj:                  VkImage;   
    view:                 VkImageView;
    extent:               VkExtent3D;
    format:               VkFormat;
    usage:                VkImageUsageFlags;
    mip_count:            u8;
    layer_count:          u8;
    pool_index:           s16;
}

GPU_Buffer :: struct {
    using #as allocation: GPU_Allocation;
    usage_flags: VkBufferUsageFlags;
}

Physical_Device_Properties :: struct {
    api_version: u32;
    driver_version: u32;
    vendor_id: u32;
    device_id: u32;
    device_type: VkPhysicalDeviceType;
    device_name: string;
    device_name_buffer: [256]u8;
    texel_buffer_alignment: VkDeviceSize;
    uniform_buffer_alignment: VkDeviceSize;
    storage_buffer_alignment: VkDeviceSize;
    device_local_buffer_memory_index: u32;
    host_visible_buffer_memory_index: u32;
    device_local_image_memory_index: u32;
    host_visible_image_memory_index: u32;
    image_alignment: VkDeviceSize;
}

Swapchain_Support_Info :: struct {
    capabilities: VkSurfaceCapabilitiesKHR;
    formats: []VkSurfaceFormatKHR;
    present_modes: []VkPresentModeKHR;
}

Swapchain :: struct {
    obj: VkSwapchainKHR;
    extent: VkExtent2D;
    format: VkSurfaceFormatKHR;
    present_mode: VkPresentModeKHR;
    // the underlying image datas. not explicitly created by the vulkan api user, so not destroyed by vulkan api user.
    images: []VkImage;
    // the interface for an image. how to access it. texture and possibly a render target. in this case, definitely a render target.
    image_views: []VkImageView;
}

get_current_frame :: () -> *Graphics_Frame {
    using context.renderer;
    return *frames[rendered_frame_count % frames.count];
}

Graphics_Frame :: struct {
    command_pool: VkCommandPool;
    command_buffer: VkCommandBuffer;
    image_available_semaphore: VkSemaphore;
    image_rendered_semaphore: VkSemaphore;
    render_fence: VkFence;
    present_fence: VkFence;

    per_frame_uniform_descriptor_set: VkDescriptorSet;
    per_frame_uniform_buffer: GPU_Buffer;

    billboard_instance_buffer_descriptor_set: VkDescriptorSet;
    billboard_instance_buffer: GPU_Buffer;

    mesh_instances_shader_data_descriptor_set: VkDescriptorSet;
    mesh_instances_shader_data: GPU_Buffer;

    mesh_sections_shader_data_descriptor_set: VkDescriptorSet;
    mesh_sections_shader_data: GPU_Buffer;

    skinned_mesh_instances_shader_data_descriptor_set: VkDescriptorSet;
    skinned_mesh_instances_shader_data: GPU_Buffer;

    skinned_mesh_sections_shader_data_descriptor_set: VkDescriptorSet;
    skinned_mesh_sections_shader_data: GPU_Buffer;

    skinning_joints_buffer_descriptor_set: VkDescriptorSet;
    skinning_joints_buffer: GPU_Buffer;

    opaque_mesh_draw_commands_descriptor_set: VkDescriptorSet;
    opaque_mesh_draw_commands: GPU_Buffer;

    opaque_skinned_mesh_draw_commands_descriptor_set: VkDescriptorSet;
    opaque_skinned_mesh_draw_commands: GPU_Buffer;

    depth_sampler_descriptor_set: VkDescriptorSet;

    temp_allocators: [GPU_HEAP_TYPE_COUNT]GPU_Linear_Allocator;
}

Descriptor_Pool_Ratio :: struct {
    type: VkDescriptorType;
    ratio: float32;
}

Billboard_Instance :: struct {
    position:      Vector3; _pad0: float32;
    tint:          Color4f;
    scale:         Vector2; 
    uv_offset:     Vector2;
    uv_scale:      Vector2; 
    texture_index: u32;
    layer: Draw_Layer;
}

Per_Frame_Uniform_Buffer :: struct {
    view:                    Matrix4;
    view_projection_game:    Matrix4;
    view_projection_layer_1: Matrix4;
    view_projection_layer_2: Matrix4;
    view_projection_layer_3: Matrix4;
    view_projection_layer_4: Matrix4;
    view_projection_layer_5: Matrix4;
    camera_position:         Vector3; _pad0: float32;
    camera_forward:          Vector3; _pad1: float32;
    camera_up:               Vector3; _pad2: float32;
    camera_right:            Vector3; _pad3: float32;
    light_direction:         Vector3; _pad4: float32;
    time:                    float32;
    delta_time:              float32;
    camera_near:             float32;
    camera_far:              float32;
}

Sprite_Rect :: struct {
    offset: Vector2;
    scale: Vector2;
}

#load "vulkan_renderer_initialization.jai";
#load "vulkan_system_information.jai";
#load "vulkan_renderer_update.jai";
#load "vulkan_draw_interface.jai";
#load "vulkan_dev_gui.jai";
#load "vulkan_mesh.jai";

#scope_module

#load "../vulkan_backend/vulkan_getters.jai";
#load "../vulkan_backend/vulkan_startup.jai";
#load "../vulkan_backend/vulkan_swapchain_and_attachments.jai";
#load "../vulkan_backend/vulkan_create_data.jai";
#load "../vulkan_backend/vulkan_pipelines.jai";
#load "../vulkan_backend/vulkan_shaders.jai";
#load "../vulkan_backend/vulkan_linear_allocator.jai";
#load "../vulkan_backend/vulkan_draw.jai";


// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.
