/*

// process of building pipelines:

build_info: Graphics_Pipeline_Build_Info;
build_info.pipeline_layout = my_pipeline_layout;
make_default_..._pipeline_build_info(*build_info, ...);
// set non-default fields in the build info
my_pipeline = build_pipeline(*build_info);

*/

Graphics_Pipeline_Build_Info :: struct {
    // filled out before passing in
    name := "a graphics pipeline"; // for logging
    color_attachment_format: VkFormat = .R8G8B8A8_UNORM; // VkFormat.R16G16B16A16_SFLOAT;
    pipeline_layout: VkPipelineLayout;

    // filled in per-type
    type: Build_Info_Type;

    shader_stages: []VkPipelineShaderStageCreateInfo;
    input_assembly: struct {
        create: VkPipelineInputAssemblyStateCreateInfo;
    };

    using type_data: union {
        vertex_fragment: struct {
            create: VkPipelineVertexInputStateCreateInfo;
            vertex_bindings: VkVertexInputBindingDescription;
            vertex_attributes: []VkVertexInputAttributeDescription;
        };
    };

    // filled in by default
    using common_data: struct {
        viewport: struct {
            create: VkPipelineViewportStateCreateInfo;
            viewport: VkViewport;
            scissor: VkRect2D;
        };
        rasterization: struct {
            create := VkPipelineRasterizationStateCreateInfo.{
                depthClampEnable = VK_FALSE,
                rasterizerDiscardEnable = VK_FALSE,
                polygonMode = .FILL,
                lineWidth = 1.0,
                cullMode = .NONE, // bad default. just for now
                frontFace = .CLOCKWISE,
                depthBiasEnable = VK_FALSE,
                depthBiasConstantFactor = 0.0,
                depthBiasClamp = 0.0,
                depthBiasSlopeFactor = 0.0
            };
        };
        multisampling: struct {
            create := VkPipelineMultisampleStateCreateInfo.{
                sampleShadingEnable = VK_FALSE,
                rasterizationSamples = ._1_BIT,
                minSampleShading = 1.0,
                pSampleMask = null,
                alphaToCoverageEnable = VK_FALSE,
                alphaToOneEnable = VK_FALSE
            };
        };
        color_blend: struct {
            create: VkPipelineColorBlendStateCreateInfo;
            attachment := VkPipelineColorBlendAttachmentState.{
                colorWriteMask = .R_BIT | .G_BIT | .B_BIT | .A_BIT,
                blendEnable = VK_FALSE,
                srcColorBlendFactor = .SRC_ALPHA,
                dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA,
                colorBlendOp = .ADD,
                srcAlphaBlendFactor = .ONE,
                dstAlphaBlendFactor = .ZERO,
                alphaBlendOp = .ADD
            };
        };
        dynamic_state: struct {
            create := VkPipelineDynamicStateCreateInfo.{
                dynamicStateCount = xx DEFAULT_DYNAMIC_STATES.count,
                pDynamicStates    = DEFAULT_DYNAMIC_STATES.data
            };
        }
        depth_stencil: struct {
            create := VkPipelineDepthStencilStateCreateInfo.{
                depthTestEnable = VK_TRUE,
                depthWriteEnable = VK_TRUE,
                depthCompareOp = .GREATER, // 1=near, 0=far
                depthBoundsTestEnable = VK_FALSE,
                stencilTestEnable = VK_FALSE,
            };
        }
        render: struct {
            create: VkPipelineRenderingCreateInfo;
        }
    };
}


make_default_vertex_fragment_pipeline_build_info :: (build_info: *Graphics_Pipeline_Build_Info, vertex_shader_filename: string = "", fragment_shader_filename: string = "", $Vertex_Type: Type) -> bool {
    build_info.type = .VERTEX_FRAGMENT;

    vert := get_shader(vertex_shader_filename);
    if !render_evaluate(.LOW, vert != null, "failed to get vert shader %", vertex_shader_filename) then return false;

    frag := get_shader(fragment_shader_filename);
    if !render_evaluate(.LOW, frag != null, "failed to get frag shader %", fragment_shader_filename) then return false;

    build_info.shader_stages = make_static_array(VkPipelineShaderStageCreateInfo, 2,, temp);
    build_info.shader_stages[0] = {
        stage = .VERTEX_BIT,
        module = vert,
        pName = "main"
    };
    build_info.shader_stages[1] = {
        stage = .FRAGMENT_BIT,
        module = frag,
        pName = "main"
    };

    {
        using build_info.vertex_fragment;

        vertex_bindings, vertex_attributes = make_vertex_descriptors(Vertex_Type,, temp);

        create = VkPipelineVertexInputStateCreateInfo.{
            vertexBindingDescriptionCount = 1,
            pVertexBindingDescriptions = *vertex_bindings,
            vertexAttributeDescriptionCount = xx vertex_attributes.count,
            pVertexAttributeDescriptions = vertex_attributes.data
        };
    }

    build_info.input_assembly.create = VkPipelineInputAssemblyStateCreateInfo.{
        topology = .TRIANGLE_LIST,
    };

    fill_default(build_info);
    return true;
}

build_pipeline :: (using build_info: *Graphics_Pipeline_Build_Info) -> VkPipeline {
    using context.renderer;

    // todo: this can be adapted to do non vert-frag
    pipeline_create := VkGraphicsPipelineCreateInfo.{
        pNext               = *render,
        stageCount          = xx shader_stages.count,
        pStages             = shader_stages.data,
        pVertexInputState   = *vertex_fragment.create,
        pInputAssemblyState = *input_assembly.create,
        pViewportState      = *viewport.create,
        pRasterizationState = *rasterization.create,
        pMultisampleState   = *multisampling.create,
        pDepthStencilState  = *depth_stencil.create,
        pColorBlendState    = *color_blend.create,
        pDynamicState       = *dynamic_state.create,
        layout              = pipeline_layout,
    };

    pipeline: VkPipeline;
    if !render_evaluate(.LOW, vkCreateGraphicsPipelines(logical.obj, VK_NULL_HANDLE, 1, *pipeline_create, null, *pipeline), "failed to create graphics pipeline \"%\"", build_info.name) {
        return null;
    }

    render_log(.MEDIUM, "created graphics pipeline \"%\"", build_info.name);
    return pipeline;
}

    // sType:              VkStructureType = .COMPUTE_PIPELINE_CREATE_INFO;
    // pNext:              *void;
    // flags:              VkPipelineCreateFlags;
    // stage:              VkPipelineShaderStageCreateInfo;
    // layout:             VkPipelineLayout;

    // basePipelineHandle: VkPipeline;
    // basePipelineIndex:  s32;
    // pipeline: VkPipeline;

    // VkPipelineShaderStageCreateInfo :: struct {
    //     sType:               VkStructureType = .PIPELINE_SHADER_STAGE_CREATE_INFO;
    //     pNext:               *void;
    //     flags:               VkPipelineShaderStageCreateFlags;
    //     stage:               VkShaderStageFlagBits;
    //     module:              VkShaderModule;
    //     pName:               *u8;
    //     pSpecializationInfo: *VkSpecializationInfo;
    // }

build_pipeline :: (compute_shader_filename: string, pipeline_name: string, layout: VkPipelineLayout, flags: VkPipelineCreateFlags = 0) -> VkPipeline {
    using context.renderer;

    shader := get_shader(compute_shader_filename);
    if !render_evaluate(.LOW, shader != null, "failed to get compute shader %", compute_shader_filename) then return null;

    create_info := VkComputePipelineCreateInfo.{
        flags = flags,
        stage = {
            stage  = .COMPUTE_BIT,
            module = shader,
            pName  = "main"
        },
        layout = layout
    };

    pipeline: VkPipeline;
    if !render_evaluate(.LOW, vkCreateComputePipelines(logical.obj, VK_NULL_HANDLE, 1, *create_info, null, *pipeline), "failed to create compute pipeline \"%\"", pipeline_name) {
        return null;
    }

    render_log(.MEDIUM, "created compute pipeline \"%\"", pipeline_name);
    return pipeline;
}

#scope_file

fill_default :: (using build_info: *Graphics_Pipeline_Build_Info) {
    using context.renderer;

    viewport = {
        create = {
            viewportCount = 1,
            pViewports = *viewport.viewport,
            scissorCount = 1,
            pScissors = *viewport.scissor
        },
        viewport = {
            width = xx swapchain.extent.width,
            height = xx swapchain.extent.height,
            minDepth = MIN_DEPTH,
            maxDepth = MAX_DEPTH
        },
        scissor = {
            extent = swapchain.extent
        }
    };

    color_blend.create = {
        logicOpEnable = VK_FALSE,
        logicOp = .COPY,
        attachmentCount = 1,
        pAttachments = *color_blend.attachment
    };

    render.create = {
        colorAttachmentCount=1,
        pColorAttachmentFormats = *color_attachment_format,
        depthAttachmentFormat = DEPTH_FORMAT,
        stencilAttachmentFormat = DEPTH_FORMAT
    };
}

DEFAULT_DYNAMIC_STATES :: VkDynamicState.[.VIEWPORT, .SCISSOR];

Build_Info_Type :: enum {
    VERTEX_FRAGMENT;
}
