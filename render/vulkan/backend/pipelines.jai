#scope_file

using engine.renderer;
using engine.renderer.backend;

#scope_module

Graphics_Pipeline :: enum {
    BILLBOARD;
    OPAQUE_STATIC_MESH;
    OPAQUE_SKELETAL_MESH;
    OPAQUE_LINE;
    TRANSPARENT_LINE;
    DEPTH_VISUALIZATION;
}

Graphics_Pipeline_Layout :: enum {
    BILLBOARD;
    OPAQUE_STATIC_MESH;
    OPAQUE_SKELETAL_MESH;
    DEPTH_VISUALIZATION;
}
