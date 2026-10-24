Graphics_Pipeline :: enum {
    BILLBOARD;
    OPAQUE_STATIC_MESH;
    OPAQUE_SKELETAL_MESH;
    OPAQUE_LINE;
    TRANSPARENT_LINE;
    DEPTH_VISUALIZATION;
}

GRAPHICS_PIPELINE_COUNT :: #run enum_highest_value(Graphics_Pipeline) + 1;

// pushed to every pipeline. each field is a device address (see gpu_address). mirrored by the
// push_constant block in shaders/src/header.glsl.
Push_Constants :: struct {
    frame:     VkDeviceAddress; // *Frame_Data
    sections:  VkDeviceAddress; // *[]Draw_Section, indexed by gl_DrawID. changes per indirect draw.
    instances: VkDeviceAddress; // *[]Instance_Data, indexed by gl_InstanceIndex
    joints:    VkDeviceAddress; // *[]Matrix4
    materials: VkDeviceAddress; // *[]GPU_Material
    vertices:  VkDeviceAddress; // *[]Line_Vertex
}

#run assert(size_of(Push_Constants) <= 128, "vulkan only guarantees 128 bytes of push constants");

push_constants :: inline (cmd: VkCommandBuffer, constants: *Push_Constants) {
    using engine.renderer;
    vkCmdPushConstants(cmd, pipeline_layout, .ALL, 0, size_of(Push_Constants), constants);
}

create_pipelines :: () -> bool {
    using engine.renderer;
    auto_release_temp();

    push_range := VkPushConstantRange.{
        stageFlags = .ALL,
        offset     = 0,
        size       = size_of(Push_Constants)
    };
    layout_info := VkPipelineLayoutCreateInfo.{
        setLayoutCount         = 1,
        pSetLayouts            = *textures.layout,
        pushConstantRangeCount = 1,
        pPushConstantRanges    = *push_range
    };
    if !render_evaluate(vkCreatePipelineLayout(logical_device.obj, *layout_info, null, *pipeline_layout), "failed to create the pipeline layout") then return false;

    pipelines[Graphics_Pipeline.OPAQUE_STATIC_MESH]   = build_pipeline("static mesh",   "mesh_vert",         "mesh_frag");
    pipelines[Graphics_Pipeline.OPAQUE_SKELETAL_MESH] = build_pipeline("skeletal mesh", "skinned_mesh_vert", "mesh_frag");
    // lines blend so that colors with alpha < 255 are see-through
    pipelines[Graphics_Pipeline.OPAQUE_LINE]          = build_pipeline("line",          "line_vert",         "line_frag", .LINE_LIST, blend=true);

    for pipeline : Graphics_Pipeline.[.OPAQUE_STATIC_MESH, .OPAQUE_SKELETAL_MESH, .OPAQUE_LINE] {
        if pipelines[pipeline] == null return false;
    }
    return true;
}

#scope_file

// depth tested, drawn into the render target. vertices are pulled in the vertex shader, so
// there's no vertex input state.
build_pipeline :: (name: string, vertex_shader: string, fragment_shader: string, topology := VkPrimitiveTopology.TRIANGLE_LIST, blend := false) -> VkPipeline {
    using engine.renderer;

    vert := create_shader_module(vertex_shader);
    frag := create_shader_module(fragment_shader);
    defer if vert != null then vkDestroyShaderModule(logical_device.obj, vert, null);
    defer if frag != null then vkDestroyShaderModule(logical_device.obj, frag, null);
    if vert == null || frag == null {
        return null;
    }

    stages := VkPipelineShaderStageCreateInfo.[
        .{stage = .VERTEX_BIT,   module = vert, pName = "main"},
        .{stage = .FRAGMENT_BIT, module = frag, pName = "main"},
    ];

    vertex_input   := VkPipelineVertexInputStateCreateInfo.{};
    input_assembly := VkPipelineInputAssemblyStateCreateInfo.{topology = topology};
    // viewport and scissor are dynamic, so only the counts matter here
    viewport := VkPipelineViewportStateCreateInfo.{viewportCount = 1, scissorCount = 1};
    rasterization := VkPipelineRasterizationStateCreateInfo.{
        polygonMode = .FILL,
        lineWidth   = 1.0,
        cullMode    = .NONE, // bad default. just for now
        frontFace   = .CLOCKWISE,
    };
    multisampling := VkPipelineMultisampleStateCreateInfo.{
        rasterizationSamples = ._1_BIT,
        minSampleShading     = 1.0,
    };
    depth_stencil := VkPipelineDepthStencilStateCreateInfo.{
        depthTestEnable  = VK_TRUE,
        depthWriteEnable = VK_TRUE,
        depthCompareOp   = .GREATER, // 1=near, 0=far
    };
    blend_attachment := VkPipelineColorBlendAttachmentState.{
        colorWriteMask      = .R_BIT | .G_BIT | .B_BIT | .A_BIT,
        blendEnable         = xx blend,
        srcColorBlendFactor = .SRC_ALPHA,
        dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA,
        colorBlendOp        = .ADD,
        srcAlphaBlendFactor = .ONE,
        dstAlphaBlendFactor = .ZERO,
        alphaBlendOp        = .ADD
    };
    color_blend := VkPipelineColorBlendStateCreateInfo.{
        attachmentCount = 1,
        pAttachments    = *blend_attachment
    };
    // line width is set per batch of lines. it's ignored for triangles.
    dynamic_states := VkDynamicState.[.VIEWPORT, .SCISSOR, .LINE_WIDTH];
    dynamic_state := VkPipelineDynamicStateCreateInfo.{
        dynamicStateCount = dynamic_states.count,
        pDynamicStates    = dynamic_states.data
    };

    color_format := RENDER_TARGET_FORMAT;
    depth_format := depth_buffer.format;
    rendering := VkPipelineRenderingCreateInfo.{
        colorAttachmentCount    = 1,
        pColorAttachmentFormats = *color_format,
        depthAttachmentFormat   = depth_format,
        stencilAttachmentFormat = depth_format
    };

    create_info := VkGraphicsPipelineCreateInfo.{
        pNext               = *rendering,
        stageCount          = stages.count,
        pStages             = stages.data,
        pVertexInputState   = *vertex_input,
        pInputAssemblyState = *input_assembly,
        pViewportState      = *viewport,
        pRasterizationState = *rasterization,
        pMultisampleState   = *multisampling,
        pDepthStencilState  = *depth_stencil,
        pColorBlendState    = *color_blend,
        pDynamicState       = *dynamic_state,
        layout              = pipeline_layout,
    };

    pipeline: VkPipeline;
    if !render_evaluate(vkCreateGraphicsPipelines(logical_device.obj, VK_NULL_HANDLE, 1, *create_info, null, *pipeline), "failed to create graphics pipeline \"%\"", name) {
        return null;
    }

    render_log("created graphics pipeline \"%\"", name, flags=.VERBOSE_ONLY);
    return pipeline;
}

// name is the compiled shader's name without extension, e.g. "mesh_vert"
create_shader_module :: (name: string) -> VkShaderModule {
    using engine.renderer;

    file_path := tprint("%/%/spirv/%.spv", engine.project_info.project_path, engine.project_info.shaders_path, name);
    spirv, success := read_entire_file(file_path, true,, temp);
    if !render_evaluate(success, "failed to load shader binary %. if it's an engine shader, set copy_shaders_from_engine and compile_shaders in the renderer creation settings.", file_path) then return null;

    create_info := VkShaderModuleCreateInfo.{
        codeSize = xx spirv.count,
        pCode    = xx spirv.data
    };

    module: VkShaderModule;
    if !render_evaluate(vkCreateShaderModule(logical_device.obj, *create_info, null, *module), "failed to create a shader module from %", file_path) then return null;
    return module;
}
