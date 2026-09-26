
dev_gui_process_input_event :: (event: Event) {
    using io := GetIO();

    mouse_button: s32 = -1;
    if event.key_code == {
    case .MOUSE_BUTTON_LEFT;
        mouse_button = 0;
    case .MOUSE_BUTTON_RIGHT;
        mouse_button = 1;
    case .MOUSE_BUTTON_MIDDLE;
        mouse_button = 2;
    }
    if mouse_button != -1 {
        AddMouseButtonEvent(io, mouse_button, event.key_pressed != 0);
        return;
    }

    if event.type == {
    case .KEYBOARD;
        imgui_update_key_modifiers(io, *event);
        imgui_key := input_key_to_imgui_key(io, event.key_code);
        AddKeyEvent(io, imgui_key, event.key_pressed != 0);
    case .TEXT_INPUT;
        AddInputCharacter(io, event.utf32);
    case .MOUSE_WHEEL;
        wheel_val := event.wheel_delta.(float) / event.typical_wheel_delta.(float);
        AddMouseWheelEvent(io, 0, wheel_val);
    }
}

dev_gui_rgba :: (r: u8, g: u8, b: u8, a : u8 = 255) -> ImGui.ImColor {
    return .{r.(float) / 255.0, g.(float) / 255.0, b.(float) / 255.0, a.(float) / 255.0};
}

dev_gui_init_fonts :: () {
    scope_set_working_directory(ack_renderer_path());

    font_config: ImGui.ImFontConfig;
    font_config.OversampleH = 3;
    font_config.OversampleV = 3;
    font_config.PixelSnapH = false;

    io := ImGui.GetIO();
    io.Fonts.AddFontFromFileTTF(io.Fonts, "fonts/RobotoMono-SemiBold.ttf", 24.0, null, io.Fonts.GetGlyphRangesDefault(io.Fonts));

    io.Fonts.Build(io.Fonts);
}

dev_gui_set_theme_paper_and_ink :: () {
    s := ImGui.GetStyle();

    ROUNDING :: 4.0;
    s.WindowRounding    = ROUNDING;
    s.ChildRounding     = ROUNDING;
    s.PopupRounding     = ROUNDING;
    s.FrameRounding     = ROUNDING;
    s.ScrollbarRounding = ROUNDING;
    s.GrabRounding      = ROUNDING;
    s.TabRounding       = ROUNDING;
    s.TreeLinesRounding = ROUNDING;

    main_bg_color       := dev_gui_rgba(243,237,226);
    main_bg_color.xyz *= 0.85;
    secondary_bg_color  := dev_gui_rgba(239,232,219);
    secondary_bg_color.xyz *= 0.85;

    s.Colors[ImGui.Col.Text]                  = dev_gui_rgba(43,43,43);
    s.Colors[ImGui.Col.TextDisabled]          = dev_gui_rgba(111,106,96);
    s.Colors[ImGui.Col.WindowBg]              = main_bg_color;
    s.Colors[ImGui.Col.ChildBg]               = secondary_bg_color;
    s.Colors[ImGui.Col.PopupBg]               = secondary_bg_color;
    s.Colors[ImGui.Col.Border]                = dev_gui_rgba(0,0,0,35);
    s.Colors[ImGui.Col.FrameBg]               = dev_gui_rgba(255,255,255,180);
    s.Colors[ImGui.Col.FrameBgHovered]        = dev_gui_rgba(42,127,98,60);
    s.Colors[ImGui.Col.FrameBgActive]         = dev_gui_rgba(178,76,99,70);
    s.Colors[ImGui.Col.TitleBg]               = dev_gui_rgba(243,237,226);
    s.Colors[ImGui.Col.TitleBgActive]         = dev_gui_rgba(243,237,226);
    s.Colors[ImGui.Col.MenuBarBg]             = dev_gui_rgba(239,232,219);
    s.Colors[ImGui.Col.ScrollbarBg]           = dev_gui_rgba(239,232,219);
    s.Colors[ImGui.Col.ScrollbarGrab]         = dev_gui_rgba(42,127,98,120);
    s.Colors[ImGui.Col.ScrollbarGrabHovered]  = dev_gui_rgba(42,127,98,180);
    s.Colors[ImGui.Col.ScrollbarGrabActive]   = dev_gui_rgba(178,76,99,200);
    s.Colors[ImGui.Col.CheckMark]             = dev_gui_rgba(42,127,98);
    s.Colors[ImGui.Col.SliderGrab]            = dev_gui_rgba(42,127,98,220);
    s.Colors[ImGui.Col.SliderGrabActive]      = dev_gui_rgba(178,76,99,230);
    s.Colors[ImGui.Col.Button]                = dev_gui_rgba(42,127,98,230);
    s.Colors[ImGui.Col.ButtonHovered]         = dev_gui_rgba(42,127,98,255);
    s.Colors[ImGui.Col.ButtonActive]          = dev_gui_rgba(178,76,99,240);
    s.Colors[ImGui.Col.Header]                = dev_gui_rgba(42,127,98,80);
    s.Colors[ImGui.Col.HeaderHovered]         = dev_gui_rgba(178,76,99,120);
    s.Colors[ImGui.Col.HeaderActive]          = dev_gui_rgba(42,127,98,160);
    s.Colors[ImGui.Col.Separator]             = dev_gui_rgba(0,0,0,50);
    s.Colors[ImGui.Col.ResizeGrip]            = dev_gui_rgba(0,0,0,40);
    s.Colors[ImGui.Col.ResizeGripHovered]     = dev_gui_rgba(0,0,0,80);
    s.Colors[ImGui.Col.ResizeGripActive]      = dev_gui_rgba(0,0,0,120);
    s.Colors[ImGui.Col.Tab]                   = dev_gui_rgba(255,255,255,200);
    s.Colors[ImGui.Col.TabHovered]            = dev_gui_rgba(178,76,99,160);
    s.Colors[ImGui.Col.TabActive]             = dev_gui_rgba(42,127,98,160);
    s.Colors[ImGui.Col.TableHeaderBg]         = dev_gui_rgba(255,255,255,180);
    s.Colors[ImGui.Col.TableBorderStrong]     = dev_gui_rgba(0,0,0,40);
    s.Colors[ImGui.Col.TableBorderLight]      = dev_gui_rgba(0,0,0,20);
}

// Black-box CRT terminal. Sharp 90-degree corners, hard 1px borders, monospace
// vibes. The whole UI reads like a dumb terminal with a phosphor afterglow,
// not a floating panel.
dev_gui_set_theme_crt_phosphor :: () {
    s := ImGui.GetStyle();

    s.WindowRounding    = 0.0;
    s.ChildRounding     = 0.0;
    s.PopupRounding     = 0.0;
    s.FrameRounding     = 0.0;
    s.ScrollbarRounding = 0.0;
    s.GrabRounding      = 0.0;
    s.TabRounding       = 0.0;
    s.TreeLinesRounding = 0.0;

    s.WindowBorderSize  = 1.0;
    s.ChildBorderSize   = 1.0;
    s.PopupBorderSize   = 1.0;
    s.FrameBorderSize   = 1.0;
    s.TabBorderSize     = 1.0;
    s.SeparatorTextBorderSize = 2.0;

    s.WindowPadding     = .{14, 12};
    s.FramePadding      = .{10, 6};
    s.ItemSpacing       = .{10, 8};
    s.ItemInnerSpacing  = .{8, 6};
    s.IndentSpacing     = 18.0;
    s.ScrollbarSize     = 14.0;
    s.GrabMinSize       = 14.0;

    s.WindowTitleAlign  = .{0.5, 0.5};
    s.ButtonTextAlign   = .{0.5, 0.5};
    s.SeparatorTextAlign = .{0.0, 0.5};
    s.SeparatorTextPadding = .{20, 4};

    bg            := dev_gui_rgba(2, 6, 4);
    bg_alt        := dev_gui_rgba(0, 0, 0);
    phosphor      := dev_gui_rgba(120, 255, 160) * 0.92;
    phosphor_dim  := dev_gui_rgba(70, 200, 110) * 0.92;
    phosphor_glow := dev_gui_rgba(180, 255, 200) * 0.92;
    // phosphor      := dev_gui_rgba(230, 230, 250);
    // phosphor_dim  := dev_gui_rgba(200, 200, 250);
    // phosphor_glow := dev_gui_rgba(250, 250, 250);
    amber         := dev_gui_rgba(255, 190, 80);

    s.Colors[ImGui.Col.Text]                  = phosphor;
    s.Colors[ImGui.Col.TextDisabled]          = dev_gui_rgba(50, 110, 70);
    s.Colors[ImGui.Col.WindowBg]              = bg;
    s.Colors[ImGui.Col.ChildBg]               = bg_alt;
    s.Colors[ImGui.Col.PopupBg]               = bg;
    s.Colors[ImGui.Col.Border]                = phosphor_dim;
    s.Colors[ImGui.Col.BorderShadow]          = dev_gui_rgba(0, 0, 0, 0);
    s.Colors[ImGui.Col.FrameBg]               = dev_gui_rgba(10, 28, 18);
    s.Colors[ImGui.Col.FrameBgHovered]        = dev_gui_rgba(30, 70, 45);
    s.Colors[ImGui.Col.FrameBgActive]         = dev_gui_rgba(50, 110, 75);
    s.Colors[ImGui.Col.TitleBg]               = dev_gui_rgba(8, 22, 14);
    s.Colors[ImGui.Col.TitleBgActive]         = dev_gui_rgba(20, 60, 35);
    s.Colors[ImGui.Col.TitleBgCollapsed]      = bg;
    s.Colors[ImGui.Col.MenuBarBg]             = dev_gui_rgba(8, 22, 14);
    s.Colors[ImGui.Col.ScrollbarBg]           = bg_alt;
    s.Colors[ImGui.Col.ScrollbarGrab]         = phosphor_dim;
    s.Colors[ImGui.Col.ScrollbarGrabHovered]  = phosphor;
    s.Colors[ImGui.Col.ScrollbarGrabActive]   = phosphor_glow;
    s.Colors[ImGui.Col.CheckMark]             = amber;
    s.Colors[ImGui.Col.SliderGrab]            = phosphor;
    s.Colors[ImGui.Col.SliderGrabActive]      = amber;
    s.Colors[ImGui.Col.Button]                = dev_gui_rgba(0, 0, 0);
    s.Colors[ImGui.Col.ButtonHovered]         = dev_gui_rgba(30, 80, 50);
    s.Colors[ImGui.Col.ButtonActive]          = dev_gui_rgba(60, 140, 90);
    s.Colors[ImGui.Col.Header]                = dev_gui_rgba(20, 60, 35);
    s.Colors[ImGui.Col.HeaderHovered]         = dev_gui_rgba(40, 100, 60);
    s.Colors[ImGui.Col.HeaderActive]          = dev_gui_rgba(70, 160, 100);
    s.Colors[ImGui.Col.Separator]             = phosphor_dim;
    s.Colors[ImGui.Col.SeparatorHovered]      = phosphor;
    s.Colors[ImGui.Col.SeparatorActive]       = phosphor_glow;
    s.Colors[ImGui.Col.ResizeGrip]            = phosphor_dim;
    s.Colors[ImGui.Col.ResizeGripHovered]     = phosphor;
    s.Colors[ImGui.Col.ResizeGripActive]      = phosphor_glow;
    s.Colors[ImGui.Col.Tab]                   = dev_gui_rgba(0, 0, 0);
    s.Colors[ImGui.Col.TabHovered]            = dev_gui_rgba(40, 100, 60);
    s.Colors[ImGui.Col.TabSelected]           = dev_gui_rgba(20, 60, 35);
    s.Colors[ImGui.Col.TabSelectedOverline]   = amber;
    s.Colors[ImGui.Col.TabDimmed]             = dev_gui_rgba(0, 0, 0);
    s.Colors[ImGui.Col.TabDimmedSelected]     = dev_gui_rgba(10, 30, 18);
    s.Colors[ImGui.Col.PlotLines]             = phosphor;
    s.Colors[ImGui.Col.PlotLinesHovered]      = amber;
    s.Colors[ImGui.Col.PlotHistogram]         = phosphor_dim;
    s.Colors[ImGui.Col.PlotHistogramHovered]  = amber;
    s.Colors[ImGui.Col.TableHeaderBg]         = dev_gui_rgba(10, 30, 18);
    s.Colors[ImGui.Col.TableBorderStrong]     = phosphor_dim;
    s.Colors[ImGui.Col.TableBorderLight]      = dev_gui_rgba(30, 70, 45);
    s.Colors[ImGui.Col.TableRowBg]            = dev_gui_rgba(0, 0, 0, 0);
    s.Colors[ImGui.Col.TableRowBgAlt]         = dev_gui_rgba(20, 60, 35, 60);
    s.Colors[ImGui.Col.TextLink]              = amber;
    s.Colors[ImGui.Col.TextSelectedBg]        = dev_gui_rgba(60, 140, 90, 140);
    s.Colors[ImGui.Col.DragDropTarget]        = amber;
    s.Colors[ImGui.Col.NavCursor]             = amber;
    s.Colors[ImGui.Col.ModalWindowDimBg]      = dev_gui_rgba(0, 0, 0, 200);
    s.Colors[ImGui.Col.InputTextCursor]       = phosphor_glow;
}

// Warm dark "lounge" mode. Espresso background, oat-cream text, with sage
// and dried-apricot accents splitting the interaction work. Soft rounding
// and no borders so it reads as a cozy room, not a control panel.
dev_gui_set_theme_mocha_lounge :: () {
    s := ImGui.GetStyle();

    ROUNDING :: 6.0;
    s.WindowRounding    = ROUNDING;
    s.ChildRounding     = ROUNDING;
    s.PopupRounding     = ROUNDING;
    s.FrameRounding     = ROUNDING;
    s.ScrollbarRounding = ROUNDING;
    s.GrabRounding      = ROUNDING;
    s.TabRounding       = ROUNDING;
    s.TreeLinesRounding = 4.0;

    s.WindowBorderSize  = 0.0;
    s.FrameBorderSize   = 0.0;
    s.PopupBorderSize   = 0.0;
    s.TabBorderSize     = 0.0;

    s.WindowPadding     = .{14, 12};
    s.FramePadding      = .{10, 6};
    s.ItemSpacing       = .{10, 6};
    s.ItemInnerSpacing  = .{8, 4};
    s.IndentSpacing     = 20.0;
    s.GrabMinSize       = 14.0;

    bg_main      := dev_gui_rgba(38, 28, 22);   // espresso
    bg_secondary := dev_gui_rgba(50, 38, 30);   // cocoa
    bg_frame     := dev_gui_rgba(62, 48, 38);   // raised cocoa
    text         := dev_gui_rgba(234, 220, 198);
    text_dim     := dev_gui_rgba(160, 145, 125);
    sage         := dev_gui_rgba(160, 180, 140);
    apricot      := dev_gui_rgba(220, 160, 110);

    s.Colors[ImGui.Col.Text]                  = text;
    s.Colors[ImGui.Col.TextDisabled]          = text_dim;
    s.Colors[ImGui.Col.WindowBg]              = bg_main;
    s.Colors[ImGui.Col.ChildBg]               = bg_secondary;
    s.Colors[ImGui.Col.PopupBg]               = bg_secondary;
    s.Colors[ImGui.Col.Border]                = dev_gui_rgba(234, 220, 198, 30);
    s.Colors[ImGui.Col.BorderShadow]          = dev_gui_rgba(0, 0, 0, 0);
    s.Colors[ImGui.Col.FrameBg]               = bg_frame;
    s.Colors[ImGui.Col.FrameBgHovered]        = dev_gui_rgba(160, 180, 140, 60);
    s.Colors[ImGui.Col.FrameBgActive]         = dev_gui_rgba(220, 160, 110, 80);
    s.Colors[ImGui.Col.TitleBg]               = bg_secondary;
    s.Colors[ImGui.Col.TitleBgActive]         = bg_frame;
    s.Colors[ImGui.Col.TitleBgCollapsed]      = bg_main;
    s.Colors[ImGui.Col.MenuBarBg]             = bg_secondary;
    s.Colors[ImGui.Col.ScrollbarBg]           = bg_main;
    s.Colors[ImGui.Col.ScrollbarGrab]         = dev_gui_rgba(160, 180, 140, 120);
    s.Colors[ImGui.Col.ScrollbarGrabHovered]  = sage;
    s.Colors[ImGui.Col.ScrollbarGrabActive]   = apricot;
    s.Colors[ImGui.Col.CheckMark]             = sage;
    s.Colors[ImGui.Col.SliderGrab]            = dev_gui_rgba(160, 180, 140, 220);
    s.Colors[ImGui.Col.SliderGrabActive]      = apricot;
    s.Colors[ImGui.Col.Button]                = bg_frame;
    s.Colors[ImGui.Col.ButtonHovered]         = dev_gui_rgba(160, 180, 140, 90);
    s.Colors[ImGui.Col.ButtonActive]          = dev_gui_rgba(220, 160, 110, 200);
    s.Colors[ImGui.Col.Header]                = dev_gui_rgba(160, 180, 140, 60);
    s.Colors[ImGui.Col.HeaderHovered]         = dev_gui_rgba(160, 180, 140, 110);
    s.Colors[ImGui.Col.HeaderActive]          = dev_gui_rgba(220, 160, 110, 160);
    s.Colors[ImGui.Col.Separator]             = dev_gui_rgba(234, 220, 198, 30);
    s.Colors[ImGui.Col.SeparatorHovered]      = dev_gui_rgba(160, 180, 140, 140);
    s.Colors[ImGui.Col.SeparatorActive]       = dev_gui_rgba(220, 160, 110, 200);
    s.Colors[ImGui.Col.ResizeGrip]            = dev_gui_rgba(234, 220, 198, 25);
    s.Colors[ImGui.Col.ResizeGripHovered]     = dev_gui_rgba(160, 180, 140, 110);
    s.Colors[ImGui.Col.ResizeGripActive]      = dev_gui_rgba(220, 160, 110, 180);
    s.Colors[ImGui.Col.Tab]                   = bg_secondary;
    s.Colors[ImGui.Col.TabHovered]            = dev_gui_rgba(160, 180, 140, 80);
    s.Colors[ImGui.Col.TabSelected]           = bg_frame;
    s.Colors[ImGui.Col.TabSelectedOverline]   = apricot;
    s.Colors[ImGui.Col.TabDimmed]             = bg_secondary;
    s.Colors[ImGui.Col.TabDimmedSelected]     = bg_frame;
    s.Colors[ImGui.Col.PlotLines]             = sage;
    s.Colors[ImGui.Col.PlotLinesHovered]      = apricot;
    s.Colors[ImGui.Col.PlotHistogram]         = sage;
    s.Colors[ImGui.Col.PlotHistogramHovered]  = apricot;
    s.Colors[ImGui.Col.TableHeaderBg]         = bg_frame;
    s.Colors[ImGui.Col.TableBorderStrong]     = dev_gui_rgba(234, 220, 198, 50);
    s.Colors[ImGui.Col.TableBorderLight]      = dev_gui_rgba(234, 220, 198, 22);
    s.Colors[ImGui.Col.TableRowBg]            = dev_gui_rgba(0, 0, 0, 0);
    s.Colors[ImGui.Col.TableRowBgAlt]         = dev_gui_rgba(234, 220, 198, 12);
    s.Colors[ImGui.Col.TextLink]              = apricot;
    s.Colors[ImGui.Col.TextSelectedBg]        = dev_gui_rgba(160, 180, 140, 110);
    s.Colors[ImGui.Col.DragDropTarget]        = apricot;
    s.Colors[ImGui.Col.NavCursor]             = apricot;
    s.Colors[ImGui.Col.ModalWindowDimBg]      = dev_gui_rgba(16, 10, 6, 180);
    s.Colors[ImGui.Col.InputTextCursor]       = text;
}

// Botanical light theme. Pale eucalyptus paper, deep forest ink, terracotta
// and warm-gold accents. Tighter rounding and a thin border give it a
// drafted-on-good-paper feel rather than a screen-glow feel.
dev_gui_set_theme_sage_and_clay :: () {
    s := ImGui.GetStyle();

    ROUNDING :: 3.0;
    s.WindowRounding    = ROUNDING;
    s.ChildRounding     = ROUNDING;
    s.PopupRounding     = ROUNDING;
    s.FrameRounding     = ROUNDING;
    s.ScrollbarRounding = ROUNDING;
    s.GrabRounding      = ROUNDING;
    s.TabRounding       = ROUNDING;
    s.TreeLinesRounding = ROUNDING;

    s.WindowBorderSize  = 1.0;
    s.FrameBorderSize   = 0.0;
    s.PopupBorderSize   = 1.0;
    s.TabBorderSize     = 0.0;

    s.WindowPadding     = .{12, 10};
    s.FramePadding      = .{8, 5};
    s.ItemSpacing       = .{8, 6};
    s.ItemInnerSpacing  = .{6, 4};
    s.IndentSpacing     = 18.0;
    s.GrabMinSize       = 12.0;

    bg_main      := dev_gui_rgba(225, 230, 213); // pale eucalyptus
    bg_secondary := dev_gui_rgba(212, 220, 198); // sage
    bg_frame     := dev_gui_rgba(238, 240, 224); // cream-paper
    text         := dev_gui_rgba(56, 70, 50);    // forest
    text_dim     := dev_gui_rgba(118, 132, 108);
    clay         := dev_gui_rgba(178, 100, 70);
    gold         := dev_gui_rgba(195, 150, 80);

    s.Colors[ImGui.Col.Text]                  = text;
    s.Colors[ImGui.Col.TextDisabled]          = text_dim;
    s.Colors[ImGui.Col.WindowBg]              = bg_main;
    s.Colors[ImGui.Col.ChildBg]               = bg_secondary;
    s.Colors[ImGui.Col.PopupBg]               = bg_secondary;
    s.Colors[ImGui.Col.Border]                = dev_gui_rgba(56, 70, 50, 60);
    s.Colors[ImGui.Col.BorderShadow]          = dev_gui_rgba(0, 0, 0, 0);
    s.Colors[ImGui.Col.FrameBg]               = bg_frame;
    s.Colors[ImGui.Col.FrameBgHovered]        = dev_gui_rgba(178, 100, 70, 50);
    s.Colors[ImGui.Col.FrameBgActive]         = dev_gui_rgba(178, 100, 70, 90);
    s.Colors[ImGui.Col.TitleBg]               = bg_secondary;
    s.Colors[ImGui.Col.TitleBgActive]         = bg_main;
    s.Colors[ImGui.Col.TitleBgCollapsed]      = bg_secondary;
    s.Colors[ImGui.Col.MenuBarBg]             = bg_secondary;
    s.Colors[ImGui.Col.ScrollbarBg]           = bg_secondary;
    s.Colors[ImGui.Col.ScrollbarGrab]         = dev_gui_rgba(56, 70, 50, 100);
    s.Colors[ImGui.Col.ScrollbarGrabHovered]  = dev_gui_rgba(178, 100, 70, 180);
    s.Colors[ImGui.Col.ScrollbarGrabActive]   = dev_gui_rgba(195, 150, 80, 220);
    s.Colors[ImGui.Col.CheckMark]             = clay;
    s.Colors[ImGui.Col.SliderGrab]            = dev_gui_rgba(56, 70, 50, 200);
    s.Colors[ImGui.Col.SliderGrabActive]      = clay;
    s.Colors[ImGui.Col.Button]                = bg_frame;
    s.Colors[ImGui.Col.ButtonHovered]         = dev_gui_rgba(178, 100, 70, 90);
    s.Colors[ImGui.Col.ButtonActive]          = dev_gui_rgba(178, 100, 70, 200);
    s.Colors[ImGui.Col.Header]                = dev_gui_rgba(178, 100, 70, 50);
    s.Colors[ImGui.Col.HeaderHovered]         = dev_gui_rgba(178, 100, 70, 100);
    s.Colors[ImGui.Col.HeaderActive]          = dev_gui_rgba(178, 100, 70, 160);
    s.Colors[ImGui.Col.Separator]             = dev_gui_rgba(56, 70, 50, 60);
    s.Colors[ImGui.Col.SeparatorHovered]      = clay;
    s.Colors[ImGui.Col.SeparatorActive]       = gold;
    s.Colors[ImGui.Col.ResizeGrip]            = dev_gui_rgba(56, 70, 50, 50);
    s.Colors[ImGui.Col.ResizeGripHovered]     = dev_gui_rgba(178, 100, 70, 130);
    s.Colors[ImGui.Col.ResizeGripActive]      = dev_gui_rgba(195, 150, 80, 200);
    s.Colors[ImGui.Col.Tab]                   = bg_secondary;
    s.Colors[ImGui.Col.TabHovered]            = dev_gui_rgba(178, 100, 70, 80);
    s.Colors[ImGui.Col.TabSelected]           = bg_main;
    s.Colors[ImGui.Col.TabSelectedOverline]   = clay;
    s.Colors[ImGui.Col.TabDimmed]             = bg_secondary;
    s.Colors[ImGui.Col.TabDimmedSelected]     = bg_main;
    s.Colors[ImGui.Col.PlotLines]             = clay;
    s.Colors[ImGui.Col.PlotLinesHovered]      = gold;
    s.Colors[ImGui.Col.PlotHistogram]         = clay;
    s.Colors[ImGui.Col.PlotHistogramHovered]  = gold;
    s.Colors[ImGui.Col.TableHeaderBg]         = bg_secondary;
    s.Colors[ImGui.Col.TableBorderStrong]     = dev_gui_rgba(56, 70, 50, 60);
    s.Colors[ImGui.Col.TableBorderLight]      = dev_gui_rgba(56, 70, 50, 28);
    s.Colors[ImGui.Col.TableRowBg]            = dev_gui_rgba(0, 0, 0, 0);
    s.Colors[ImGui.Col.TableRowBgAlt]         = dev_gui_rgba(56, 70, 50, 16);
    s.Colors[ImGui.Col.TextLink]              = clay;
    s.Colors[ImGui.Col.TextSelectedBg]        = dev_gui_rgba(195, 150, 80, 130);
    s.Colors[ImGui.Col.DragDropTarget]        = clay;
    s.Colors[ImGui.Col.NavCursor]             = clay;
    s.Colors[ImGui.Col.ModalWindowDimBg]      = dev_gui_rgba(56, 70, 50, 130);
    s.Colors[ImGui.Col.InputTextCursor]       = clay;
}

// Cinematic dusk: deep aubergine ground, peach-cream text, antique gold
// and soft mauve as accents. Bigger rounding, fat padding, no borders -
// reads as a moody after-hours panel rather than a tool window.
dev_gui_set_theme_twilight_plum :: () {
    // original mauve-purple input field
    twilight_plum_apply(dev_gui_rgba(70, 52, 84));
}

// darker frame — input fields recede more, higher contrast against text
dev_gui_set_theme_twilight_plum_deep :: () {
    twilight_plum_apply(dev_gui_rgba(34, 24, 42));
}

// lighter frame — input fields feel raised off the panel
dev_gui_set_theme_twilight_plum_lifted :: () {
    twilight_plum_apply(dev_gui_rgba(86, 64, 102));
}

// more chromatic mauve — pushes the purple harder
dev_gui_set_theme_twilight_plum_saturated :: () {
    twilight_plum_apply(dev_gui_rgba(82, 56, 96));
}

// cooler, blue-leaning indigo frame
dev_gui_set_theme_twilight_plum_cool :: () {
    twilight_plum_apply(dev_gui_rgba(54, 46, 84));
}

// warmer, rose-tinted frame
dev_gui_set_theme_twilight_plum_warm :: () {
    twilight_plum_apply(dev_gui_rgba(82, 58, 80));
}

dev_gui_set_theme_twilight_plum_neutral :: () {
    twilight_plum_apply(dev_gui_rgba(28, 28, 28));
}

twilight_plum_apply :: (bg_frame: ImGui.ImColor) {
    s := ImGui.GetStyle();

    s.WindowRounding    = 0.0;
    s.ChildRounding     = 0.0;
    s.PopupRounding     = 0.0;
    s.FrameRounding     = 0.0;
    s.ScrollbarRounding = 0.0;
    s.GrabRounding      = 0.0;
    s.TabRounding       = 0.0;
    s.TreeLinesRounding = 0.0;

    s.WindowBorderSize  = 0.0;
    s.FrameBorderSize   = 0.0;
    s.PopupBorderSize   = 0.0;
    s.TabBorderSize     = 0.0;

    s.WindowPadding     = .{16, 14};
    s.FramePadding      = .{12, 7};
    s.ItemSpacing       = .{10, 8};
    s.ItemInnerSpacing  = .{8, 6};
    s.IndentSpacing     = 22.0;
    s.GrabMinSize       = 16.0;

    // bg_main      := dev_gui_rgba(42, 30, 52);   // aubergine
    bg_main      := dev_gui_rgba(42, 42, 42);   // aubergine
    bg_secondary := dev_gui_rgba(54, 40, 66);
    text         := dev_gui_rgba(248, 228, 205); // peach cream
    text_dim     := dev_gui_rgba(170, 150, 138);
    gold         := dev_gui_rgba(220, 175, 90);
    mauve        := dev_gui_rgba(195, 130, 165);

    s.Colors[ImGui.Col.Text]                  = text;
    s.Colors[ImGui.Col.TextDisabled]          = text_dim;
    s.Colors[ImGui.Col.WindowBg]              = bg_main;
    s.Colors[ImGui.Col.ChildBg]               = bg_secondary;
    s.Colors[ImGui.Col.PopupBg]               = bg_secondary;
    s.Colors[ImGui.Col.Border]                = dev_gui_rgba(248, 228, 205, 28);
    s.Colors[ImGui.Col.BorderShadow]          = dev_gui_rgba(0, 0, 0, 0);
    s.Colors[ImGui.Col.FrameBg]               = bg_frame;
    s.Colors[ImGui.Col.FrameBgHovered]        = dev_gui_rgba(195, 130, 165, 70);
    s.Colors[ImGui.Col.FrameBgActive]         = dev_gui_rgba(220, 175, 90, 90);
    s.Colors[ImGui.Col.TitleBg]               = bg_secondary;
    s.Colors[ImGui.Col.TitleBgActive]         = bg_frame;
    s.Colors[ImGui.Col.TitleBgCollapsed]      = bg_main;
    s.Colors[ImGui.Col.MenuBarBg]             = bg_secondary;
    s.Colors[ImGui.Col.ScrollbarBg]           = bg_main;
    s.Colors[ImGui.Col.ScrollbarGrab]         = dev_gui_rgba(248, 228, 205, 80);
    s.Colors[ImGui.Col.ScrollbarGrabHovered]  = dev_gui_rgba(195, 130, 165, 200);
    s.Colors[ImGui.Col.ScrollbarGrabActive]   = dev_gui_rgba(220, 175, 90, 220);
    s.Colors[ImGui.Col.CheckMark]             = gold;
    s.Colors[ImGui.Col.SliderGrab]            = dev_gui_rgba(195, 130, 165, 220);
    s.Colors[ImGui.Col.SliderGrabActive]      = gold;
    s.Colors[ImGui.Col.Button]                = bg_frame;
    s.Colors[ImGui.Col.ButtonHovered]         = dev_gui_rgba(195, 130, 165, 130);
    s.Colors[ImGui.Col.ButtonActive]          = dev_gui_rgba(220, 175, 90, 220);
    s.Colors[ImGui.Col.Header]                = dev_gui_rgba(195, 130, 165, 70);
    s.Colors[ImGui.Col.HeaderHovered]         = dev_gui_rgba(195, 130, 165, 130);
    s.Colors[ImGui.Col.HeaderActive]          = dev_gui_rgba(220, 175, 90, 180);
    s.Colors[ImGui.Col.Separator]             = dev_gui_rgba(248, 228, 205, 28);
    s.Colors[ImGui.Col.SeparatorHovered]      = mauve;
    s.Colors[ImGui.Col.SeparatorActive]       = gold;
    s.Colors[ImGui.Col.ResizeGrip]            = dev_gui_rgba(248, 228, 205, 30);
    s.Colors[ImGui.Col.ResizeGripHovered]     = dev_gui_rgba(195, 130, 165, 140);
    s.Colors[ImGui.Col.ResizeGripActive]      = dev_gui_rgba(220, 175, 90, 200);
    s.Colors[ImGui.Col.Tab]                   = bg_secondary;
    s.Colors[ImGui.Col.TabHovered]            = dev_gui_rgba(195, 130, 165, 110);
    s.Colors[ImGui.Col.TabSelected]           = bg_frame;
    s.Colors[ImGui.Col.TabSelectedOverline]   = gold;
    s.Colors[ImGui.Col.TabDimmed]             = bg_secondary;
    s.Colors[ImGui.Col.TabDimmedSelected]     = bg_frame;
    s.Colors[ImGui.Col.PlotLines]             = mauve;
    s.Colors[ImGui.Col.PlotLinesHovered]      = gold;
    s.Colors[ImGui.Col.PlotHistogram]         = mauve;
    s.Colors[ImGui.Col.PlotHistogramHovered]  = gold;
    s.Colors[ImGui.Col.TableHeaderBg]         = bg_frame;
    s.Colors[ImGui.Col.TableBorderStrong]     = dev_gui_rgba(248, 228, 205, 50);
    s.Colors[ImGui.Col.TableBorderLight]      = dev_gui_rgba(248, 228, 205, 22);
    s.Colors[ImGui.Col.TableRowBg]            = dev_gui_rgba(0, 0, 0, 0);
    s.Colors[ImGui.Col.TableRowBgAlt]         = dev_gui_rgba(248, 228, 205, 12);
    s.Colors[ImGui.Col.TextLink]              = gold;
    s.Colors[ImGui.Col.TextSelectedBg]        = dev_gui_rgba(195, 130, 165, 130);
    s.Colors[ImGui.Col.DragDropTarget]        = gold;
    s.Colors[ImGui.Col.NavCursor]             = gold;
    s.Colors[ImGui.Col.ModalWindowDimBg]      = dev_gui_rgba(20, 12, 28, 200);
    s.Colors[ImGui.Col.InputTextCursor]       = gold;
}

dev_gui_set_theme_crt_amber_and_ice :: () {
    s := ImGui.GetStyle();

    s.WindowRounding    = 0.0;
    s.ChildRounding     = 0.0;
    s.PopupRounding     = 0.0;
    s.FrameRounding     = 0.0;
    s.ScrollbarRounding = 0.0;
    s.GrabRounding      = 0.0;
    s.TabRounding       = 0.0;
    s.TreeLinesRounding = 0.0;

    s.WindowBorderSize  = 1.0;
    s.ChildBorderSize   = 1.0;
    s.PopupBorderSize   = 1.0;
    s.FrameBorderSize   = 1.0;
    s.TabBorderSize     = 1.0;
    s.SeparatorTextBorderSize = 2.0;

    s.WindowPadding     = .{14, 12};
    s.FramePadding      = .{10, 6};
    s.ItemSpacing       = .{10, 8};
    s.ItemInnerSpacing  = .{8, 6};
    s.IndentSpacing     = 18.0;
    s.ScrollbarSize     = 14.0;
    s.GrabMinSize       = 14.0;

    s.WindowTitleAlign     = .{0.5, 0.5};
    s.ButtonTextAlign      = .{0.5, 0.5};
    s.SeparatorTextAlign   = .{0.0, 0.5};
    s.SeparatorTextPadding = .{20, 4};

    bg            := dev_gui_rgba(8, 5, 2);
    bg_alt        := dev_gui_rgba(0, 0, 0);
    p             := dev_gui_rgba(255, 176, 50)  * 0.92; // amber
    p_dim         := dev_gui_rgba(180, 120, 30)  * 0.92;
    p_tint_dark   := dev_gui_rgba(35, 22, 6);
    p_tint_mid    := dev_gui_rgba(70, 45, 12);
    s2            := dev_gui_rgba(120, 220, 255);          // ice
    s2_glow       := dev_gui_rgba(180, 240, 255);
    s2_tint_dark  := dev_gui_rgba(8, 22, 32);
    s2_tint_mid   := dev_gui_rgba(20, 50, 75);

    s.Colors[ImGui.Col.Text]                  = p;
    s.Colors[ImGui.Col.TextDisabled]          = dev_gui_rgba(110, 75, 25);
    s.Colors[ImGui.Col.WindowBg]              = bg;
    s.Colors[ImGui.Col.ChildBg]               = bg_alt;
    s.Colors[ImGui.Col.PopupBg]               = bg;
    s.Colors[ImGui.Col.Border]                = p_dim;
    s.Colors[ImGui.Col.BorderShadow]          = dev_gui_rgba(0, 0, 0, 0);
    s.Colors[ImGui.Col.FrameBg]               = p_tint_dark;
    s.Colors[ImGui.Col.FrameBgHovered]        = s2_tint_dark;
    s.Colors[ImGui.Col.FrameBgActive]         = s2_tint_mid;
    s.Colors[ImGui.Col.TitleBg]               = p_tint_dark;
    s.Colors[ImGui.Col.TitleBgActive]         = p_tint_mid;
    s.Colors[ImGui.Col.TitleBgCollapsed]      = bg;
    s.Colors[ImGui.Col.MenuBarBg]             = p_tint_dark;
    s.Colors[ImGui.Col.ScrollbarBg]           = bg_alt;
    s.Colors[ImGui.Col.ScrollbarGrab]         = p_dim;
    s.Colors[ImGui.Col.ScrollbarGrabHovered]  = s2;
    s.Colors[ImGui.Col.ScrollbarGrabActive]   = s2_glow;
    s.Colors[ImGui.Col.CheckMark]             = s2;
    s.Colors[ImGui.Col.SliderGrab]            = p;
    s.Colors[ImGui.Col.SliderGrabActive]      = s2;
    s.Colors[ImGui.Col.Button]                = bg_alt;
    s.Colors[ImGui.Col.ButtonHovered]         = s2_tint_dark;
    s.Colors[ImGui.Col.ButtonActive]          = s2;
    s.Colors[ImGui.Col.Header]                = p_tint_mid;
    s.Colors[ImGui.Col.HeaderHovered]         = s2_tint_dark;
    s.Colors[ImGui.Col.HeaderActive]          = s2;
    s.Colors[ImGui.Col.Separator]             = p_dim;
    s.Colors[ImGui.Col.SeparatorHovered]      = s2;
    s.Colors[ImGui.Col.SeparatorActive]       = s2_glow;
    s.Colors[ImGui.Col.ResizeGrip]            = p_dim;
    s.Colors[ImGui.Col.ResizeGripHovered]     = s2;
    s.Colors[ImGui.Col.ResizeGripActive]      = s2_glow;
    s.Colors[ImGui.Col.Tab]                   = bg_alt;
    s.Colors[ImGui.Col.TabHovered]            = s2_tint_dark;
    s.Colors[ImGui.Col.TabSelected]           = p_tint_mid;
    s.Colors[ImGui.Col.TabSelectedOverline]   = s2;
    s.Colors[ImGui.Col.TabDimmed]             = bg_alt;
    s.Colors[ImGui.Col.TabDimmedSelected]     = p_tint_dark;
    s.Colors[ImGui.Col.PlotLines]             = p;
    s.Colors[ImGui.Col.PlotLinesHovered]      = s2;
    s.Colors[ImGui.Col.PlotHistogram]         = p_dim;
    s.Colors[ImGui.Col.PlotHistogramHovered]  = s2;
    s.Colors[ImGui.Col.TableHeaderBg]         = p_tint_dark;
    s.Colors[ImGui.Col.TableBorderStrong]     = p_dim;
    s.Colors[ImGui.Col.TableBorderLight]      = p_tint_mid;
    s.Colors[ImGui.Col.TableRowBg]            = dev_gui_rgba(0, 0, 0, 0);
    s.Colors[ImGui.Col.TableRowBgAlt]         = dev_gui_rgba(35, 22, 6, 80);
    s.Colors[ImGui.Col.TextLink]              = s2;
    s.Colors[ImGui.Col.TextSelectedBg]        = dev_gui_rgba(120, 220, 255, 110);
    s.Colors[ImGui.Col.DragDropTarget]        = s2_glow;
    s.Colors[ImGui.Col.NavCursor]             = s2;
    s.Colors[ImGui.Col.ModalWindowDimBg]      = dev_gui_rgba(0, 0, 0, 200);
    s.Colors[ImGui.Col.InputTextCursor]       = s2_glow;
}

// CGA-flashback: hot magenta phosphor against cyan interaction signal. Both
// hues are saturated and high-energy, so the screen reads less like a
// terminal and more like a stylized arcade attract mode.
dev_gui_set_theme_crt_pink_and_cyan :: () {
    s := ImGui.GetStyle();

    s.WindowRounding    = 0.0;
    s.ChildRounding     = 0.0;
    s.PopupRounding     = 0.0;
    s.FrameRounding     = 0.0;
    s.ScrollbarRounding = 0.0;
    s.GrabRounding      = 0.0;
    s.TabRounding       = 0.0;
    s.TreeLinesRounding = 0.0;

    s.WindowBorderSize  = 1.0;
    s.ChildBorderSize   = 1.0;
    s.PopupBorderSize   = 1.0;
    s.FrameBorderSize   = 1.0;
    s.TabBorderSize     = 1.0;
    s.SeparatorTextBorderSize = 2.0;

    s.WindowPadding     = .{14, 12};
    s.FramePadding      = .{10, 6};
    s.ItemSpacing       = .{10, 8};
    s.ItemInnerSpacing  = .{8, 6};
    s.IndentSpacing     = 18.0;
    s.ScrollbarSize     = 14.0;
    s.GrabMinSize       = 14.0;

    s.WindowTitleAlign     = .{0.5, 0.5};
    s.ButtonTextAlign      = .{0.5, 0.5};
    s.SeparatorTextAlign   = .{0.0, 0.5};
    s.SeparatorTextPadding = .{20, 4};

    bg            := dev_gui_rgba(4, 2, 6);
    bg_alt        := dev_gui_rgba(0, 0, 0);
    p             := dev_gui_rgba(255, 90, 180)  * 0.92; // magenta
    p_dim         := dev_gui_rgba(180, 60, 130)  * 0.92;
    p_tint_dark   := dev_gui_rgba(38, 12, 26);
    p_tint_mid    := dev_gui_rgba(70, 22, 50);
    s2            := dev_gui_rgba(80, 230, 240);           // cyan
    s2_glow       := dev_gui_rgba(160, 250, 255);
    s2_tint_dark  := dev_gui_rgba(4, 26, 30);
    s2_tint_mid   := dev_gui_rgba(8, 55, 60);

    s.Colors[ImGui.Col.Text]                  = p;
    s.Colors[ImGui.Col.TextDisabled]          = dev_gui_rgba(110, 50, 80);
    s.Colors[ImGui.Col.WindowBg]              = bg;
    s.Colors[ImGui.Col.ChildBg]               = bg_alt;
    s.Colors[ImGui.Col.PopupBg]               = bg;
    s.Colors[ImGui.Col.Border]                = p_dim;
    s.Colors[ImGui.Col.BorderShadow]          = dev_gui_rgba(0, 0, 0, 0);
    s.Colors[ImGui.Col.FrameBg]               = p_tint_dark;
    s.Colors[ImGui.Col.FrameBgHovered]        = s2_tint_dark;
    s.Colors[ImGui.Col.FrameBgActive]         = s2_tint_mid;
    s.Colors[ImGui.Col.TitleBg]               = p_tint_dark;
    s.Colors[ImGui.Col.TitleBgActive]         = p_tint_mid;
    s.Colors[ImGui.Col.TitleBgCollapsed]      = bg;
    s.Colors[ImGui.Col.MenuBarBg]             = p_tint_dark;
    s.Colors[ImGui.Col.ScrollbarBg]           = bg_alt;
    s.Colors[ImGui.Col.ScrollbarGrab]         = p_dim;
    s.Colors[ImGui.Col.ScrollbarGrabHovered]  = s2;
    s.Colors[ImGui.Col.ScrollbarGrabActive]   = s2_glow;
    s.Colors[ImGui.Col.CheckMark]             = s2;
    s.Colors[ImGui.Col.SliderGrab]            = p;
    s.Colors[ImGui.Col.SliderGrabActive]      = s2;
    s.Colors[ImGui.Col.Button]                = bg_alt;
    s.Colors[ImGui.Col.ButtonHovered]         = s2_tint_dark;
    s.Colors[ImGui.Col.ButtonActive]          = s2;
    s.Colors[ImGui.Col.Header]                = p_tint_mid;
    s.Colors[ImGui.Col.HeaderHovered]         = s2_tint_dark;
    s.Colors[ImGui.Col.HeaderActive]          = s2;
    s.Colors[ImGui.Col.Separator]             = p_dim;
    s.Colors[ImGui.Col.SeparatorHovered]      = s2;
    s.Colors[ImGui.Col.SeparatorActive]       = s2_glow;
    s.Colors[ImGui.Col.ResizeGrip]            = p_dim;
    s.Colors[ImGui.Col.ResizeGripHovered]     = s2;
    s.Colors[ImGui.Col.ResizeGripActive]      = s2_glow;
    s.Colors[ImGui.Col.Tab]                   = bg_alt;
    s.Colors[ImGui.Col.TabHovered]            = s2_tint_dark;
    s.Colors[ImGui.Col.TabSelected]           = p_tint_mid;
    s.Colors[ImGui.Col.TabSelectedOverline]   = s2;
    s.Colors[ImGui.Col.TabDimmed]             = bg_alt;
    s.Colors[ImGui.Col.TabDimmedSelected]     = p_tint_dark;
    s.Colors[ImGui.Col.PlotLines]             = p;
    s.Colors[ImGui.Col.PlotLinesHovered]      = s2;
    s.Colors[ImGui.Col.PlotHistogram]         = p_dim;
    s.Colors[ImGui.Col.PlotHistogramHovered]  = s2;
    s.Colors[ImGui.Col.TableHeaderBg]         = p_tint_dark;
    s.Colors[ImGui.Col.TableBorderStrong]     = p_dim;
    s.Colors[ImGui.Col.TableBorderLight]      = p_tint_mid;
    s.Colors[ImGui.Col.TableRowBg]            = dev_gui_rgba(0, 0, 0, 0);
    s.Colors[ImGui.Col.TableRowBgAlt]         = dev_gui_rgba(38, 12, 26, 80);
    s.Colors[ImGui.Col.TextLink]              = s2;
    s.Colors[ImGui.Col.TextSelectedBg]        = dev_gui_rgba(80, 230, 240, 110);
    s.Colors[ImGui.Col.DragDropTarget]        = s2_glow;
    s.Colors[ImGui.Col.NavCursor]             = s2;
    s.Colors[ImGui.Col.ModalWindowDimBg]      = dev_gui_rgba(0, 0, 0, 200);
    s.Colors[ImGui.Col.InputTextCursor]       = s2_glow;
}

// Cold-war alarm console: deep red phosphor as the resting layer with
// cobalt-blue interaction signal. Reads like a SAGE/early radar console
// where the red channel is "what's there" and the blue is "what you did."
dev_gui_set_theme_crt_red_and_cobalt :: () {
    s := ImGui.GetStyle();

    s.WindowRounding    = 0.0;
    s.ChildRounding     = 0.0;
    s.PopupRounding     = 0.0;
    s.FrameRounding     = 0.0;
    s.ScrollbarRounding = 0.0;
    s.GrabRounding      = 0.0;
    s.TabRounding       = 0.0;
    s.TreeLinesRounding = 0.0;

    s.WindowBorderSize  = 1.0;
    s.ChildBorderSize   = 1.0;
    s.PopupBorderSize   = 1.0;
    s.FrameBorderSize   = 1.0;
    s.TabBorderSize     = 1.0;
    s.SeparatorTextBorderSize = 2.0;

    s.WindowPadding     = .{14, 12};
    s.FramePadding      = .{10, 6};
    s.ItemSpacing       = .{10, 8};
    s.ItemInnerSpacing  = .{8, 6};
    s.IndentSpacing     = 18.0;
    s.ScrollbarSize     = 14.0;
    s.GrabMinSize       = 14.0;

    s.WindowTitleAlign     = .{0.5, 0.5};
    s.ButtonTextAlign      = .{0.5, 0.5};
    s.SeparatorTextAlign   = .{0.0, 0.5};
    s.SeparatorTextPadding = .{20, 4};

    bg            := dev_gui_rgba(6, 2, 2);
    bg_alt        := dev_gui_rgba(0, 0, 0);
    p             := dev_gui_rgba(255, 70, 60)   * 0.92; // red
    p_dim         := dev_gui_rgba(170, 45, 40)   * 0.92;
    p_tint_dark   := dev_gui_rgba(38, 8, 8);
    p_tint_mid    := dev_gui_rgba(70, 18, 18);
    s2            := dev_gui_rgba(110, 160, 255);          // cobalt
    s2_glow       := dev_gui_rgba(170, 200, 255);
    s2_tint_dark  := dev_gui_rgba(8, 18, 38);
    s2_tint_mid   := dev_gui_rgba(18, 40, 80);

    s.Colors[ImGui.Col.Text]                  = p;
    s.Colors[ImGui.Col.TextDisabled]          = dev_gui_rgba(110, 40, 35);
    s.Colors[ImGui.Col.WindowBg]              = bg;
    s.Colors[ImGui.Col.ChildBg]               = bg_alt;
    s.Colors[ImGui.Col.PopupBg]               = bg;
    s.Colors[ImGui.Col.Border]                = p_dim;
    s.Colors[ImGui.Col.BorderShadow]          = dev_gui_rgba(0, 0, 0, 0);
    s.Colors[ImGui.Col.FrameBg]               = p_tint_dark;
    s.Colors[ImGui.Col.FrameBgHovered]        = s2_tint_dark;
    s.Colors[ImGui.Col.FrameBgActive]         = s2_tint_mid;
    s.Colors[ImGui.Col.TitleBg]               = p_tint_dark;
    s.Colors[ImGui.Col.TitleBgActive]         = p_tint_mid;
    s.Colors[ImGui.Col.TitleBgCollapsed]      = bg;
    s.Colors[ImGui.Col.MenuBarBg]             = p_tint_dark;
    s.Colors[ImGui.Col.ScrollbarBg]           = bg_alt;
    s.Colors[ImGui.Col.ScrollbarGrab]         = p_dim;
    s.Colors[ImGui.Col.ScrollbarGrabHovered]  = s2;
    s.Colors[ImGui.Col.ScrollbarGrabActive]   = s2_glow;
    s.Colors[ImGui.Col.CheckMark]             = s2;
    s.Colors[ImGui.Col.SliderGrab]            = p;
    s.Colors[ImGui.Col.SliderGrabActive]      = s2;
    s.Colors[ImGui.Col.Button]                = bg_alt;
    s.Colors[ImGui.Col.ButtonHovered]         = s2_tint_dark;
    s.Colors[ImGui.Col.ButtonActive]          = s2;
    s.Colors[ImGui.Col.Header]                = p_tint_mid;
    s.Colors[ImGui.Col.HeaderHovered]         = s2_tint_dark;
    s.Colors[ImGui.Col.HeaderActive]          = s2;
    s.Colors[ImGui.Col.Separator]             = p_dim;
    s.Colors[ImGui.Col.SeparatorHovered]      = s2;
    s.Colors[ImGui.Col.SeparatorActive]       = s2_glow;
    s.Colors[ImGui.Col.ResizeGrip]            = p_dim;
    s.Colors[ImGui.Col.ResizeGripHovered]     = s2;
    s.Colors[ImGui.Col.ResizeGripActive]      = s2_glow;
    s.Colors[ImGui.Col.Tab]                   = bg_alt;
    s.Colors[ImGui.Col.TabHovered]            = s2_tint_dark;
    s.Colors[ImGui.Col.TabSelected]           = p_tint_mid;
    s.Colors[ImGui.Col.TabSelectedOverline]   = s2;
    s.Colors[ImGui.Col.TabDimmed]             = bg_alt;
    s.Colors[ImGui.Col.TabDimmedSelected]     = p_tint_dark;
    s.Colors[ImGui.Col.PlotLines]             = p;
    s.Colors[ImGui.Col.PlotLinesHovered]      = s2;
    s.Colors[ImGui.Col.PlotHistogram]         = p_dim;
    s.Colors[ImGui.Col.PlotHistogramHovered]  = s2;
    s.Colors[ImGui.Col.TableHeaderBg]         = p_tint_dark;
    s.Colors[ImGui.Col.TableBorderStrong]     = p_dim;
    s.Colors[ImGui.Col.TableBorderLight]      = p_tint_mid;
    s.Colors[ImGui.Col.TableRowBg]            = dev_gui_rgba(0, 0, 0, 0);
    s.Colors[ImGui.Col.TableRowBgAlt]         = dev_gui_rgba(38, 8, 8, 80);
    s.Colors[ImGui.Col.TextLink]              = s2;
    s.Colors[ImGui.Col.TextSelectedBg]        = dev_gui_rgba(110, 160, 255, 110);
    s.Colors[ImGui.Col.DragDropTarget]        = s2_glow;
    s.Colors[ImGui.Col.NavCursor]             = s2;
    s.Colors[ImGui.Col.ModalWindowDimBg]      = dev_gui_rgba(0, 0, 0, 200);
    s.Colors[ImGui.Col.InputTextCursor]       = s2_glow;
}

// Saturated synthwave: midnight purple, magenta primaries, cyan/yellow
// secondaries. Big rounding and zero borders so widgets feel like soft
// glowing tiles instead of bordered rectangles.
dev_gui_set_theme_neon_synthwave :: () {
    s := ImGui.GetStyle();

    BIG_ROUND :: 10.0;
    s.WindowRounding    = BIG_ROUND;
    s.ChildRounding     = BIG_ROUND;
    s.PopupRounding     = BIG_ROUND;
    s.FrameRounding     = BIG_ROUND - 2.0;
    s.ScrollbarRounding = BIG_ROUND;
    s.GrabRounding      = BIG_ROUND - 2.0;
    s.TabRounding       = BIG_ROUND - 2.0;
    s.TreeLinesRounding = 4.0;

    s.WindowBorderSize  = 0.0;
    s.ChildBorderSize   = 0.0;
    s.PopupBorderSize   = 0.0;
    s.FrameBorderSize   = 0.0;
    s.TabBorderSize     = 0.0;

    s.WindowPadding     = .{18, 16};
    s.FramePadding      = .{12, 8};
    s.ItemSpacing       = .{12, 10};
    s.ItemInnerSpacing  = .{8, 6};
    s.IndentSpacing     = 22.0;
    s.ScrollbarSize     = 12.0;
    s.GrabMinSize       = 16.0;

    s.WindowTitleAlign   = .{0.5, 0.5};
    s.ButtonTextAlign    = .{0.5, 0.5};
    s.SelectableTextAlign = .{0.0, 0.5};

    midnight    := dev_gui_rgba(15, 8, 35);
    panel       := dev_gui_rgba(28, 18, 60);
    panel_alt   := dev_gui_rgba(40, 25, 80);
    magenta     := dev_gui_rgba(255, 60, 200);
    magenta_dim := dev_gui_rgba(180, 40, 140);
    cyan        := dev_gui_rgba(80, 240, 250);
    yellow      := dev_gui_rgba(255, 230, 90);
    text        := dev_gui_rgba(240, 230, 255);

    s.Colors[ImGui.Col.Text]                  = text;
    s.Colors[ImGui.Col.TextDisabled]          = dev_gui_rgba(140, 120, 180);
    s.Colors[ImGui.Col.WindowBg]              = midnight;
    s.Colors[ImGui.Col.ChildBg]               = dev_gui_rgba(20, 12, 45, 200);
    s.Colors[ImGui.Col.PopupBg]               = dev_gui_rgba(28, 18, 60, 245);
    s.Colors[ImGui.Col.Border]                = dev_gui_rgba(255, 60, 200, 0);
    s.Colors[ImGui.Col.BorderShadow]          = dev_gui_rgba(0, 0, 0, 0);
    s.Colors[ImGui.Col.FrameBg]               = panel;
    s.Colors[ImGui.Col.FrameBgHovered]        = panel_alt;
    s.Colors[ImGui.Col.FrameBgActive]         = dev_gui_rgba(60, 35, 110);
    s.Colors[ImGui.Col.TitleBg]               = dev_gui_rgba(20, 12, 45);
    s.Colors[ImGui.Col.TitleBgActive]         = dev_gui_rgba(40, 20, 80);
    s.Colors[ImGui.Col.TitleBgCollapsed]      = dev_gui_rgba(15, 8, 35, 200);
    s.Colors[ImGui.Col.MenuBarBg]             = dev_gui_rgba(20, 12, 45);
    s.Colors[ImGui.Col.ScrollbarBg]           = dev_gui_rgba(0, 0, 0, 80);
    s.Colors[ImGui.Col.ScrollbarGrab]         = magenta_dim;
    s.Colors[ImGui.Col.ScrollbarGrabHovered]  = magenta;
    s.Colors[ImGui.Col.ScrollbarGrabActive]   = cyan;
    s.Colors[ImGui.Col.CheckMark]             = cyan;
    s.Colors[ImGui.Col.SliderGrab]            = magenta;
    s.Colors[ImGui.Col.SliderGrabActive]      = yellow;
    s.Colors[ImGui.Col.Button]                = dev_gui_rgba(255, 60, 200, 200);
    s.Colors[ImGui.Col.ButtonHovered]         = dev_gui_rgba(255, 90, 220, 255);
    s.Colors[ImGui.Col.ButtonActive]          = dev_gui_rgba(80, 240, 250, 255);
    s.Colors[ImGui.Col.Header]                = dev_gui_rgba(80, 40, 140, 200);
    s.Colors[ImGui.Col.HeaderHovered]         = dev_gui_rgba(140, 60, 200, 220);
    s.Colors[ImGui.Col.HeaderActive]          = dev_gui_rgba(80, 240, 250, 180);
    s.Colors[ImGui.Col.Separator]             = dev_gui_rgba(255, 60, 200, 80);
    s.Colors[ImGui.Col.SeparatorHovered]      = magenta;
    s.Colors[ImGui.Col.SeparatorActive]       = cyan;
    s.Colors[ImGui.Col.ResizeGrip]            = dev_gui_rgba(255, 60, 200, 80);
    s.Colors[ImGui.Col.ResizeGripHovered]     = magenta;
    s.Colors[ImGui.Col.ResizeGripActive]      = yellow;
    s.Colors[ImGui.Col.Tab]                   = dev_gui_rgba(40, 25, 80, 220);
    s.Colors[ImGui.Col.TabHovered]            = magenta;
    s.Colors[ImGui.Col.TabSelected]           = dev_gui_rgba(255, 60, 200, 220);
    s.Colors[ImGui.Col.TabSelectedOverline]   = cyan;
    s.Colors[ImGui.Col.TabDimmed]             = dev_gui_rgba(28, 18, 60);
    s.Colors[ImGui.Col.TabDimmedSelected]     = dev_gui_rgba(80, 40, 140);
    s.Colors[ImGui.Col.PlotLines]             = magenta;
    s.Colors[ImGui.Col.PlotLinesHovered]      = yellow;
    s.Colors[ImGui.Col.PlotHistogram]         = cyan;
    s.Colors[ImGui.Col.PlotHistogramHovered]  = yellow;
    s.Colors[ImGui.Col.TableHeaderBg]         = dev_gui_rgba(40, 20, 80);
    s.Colors[ImGui.Col.TableBorderStrong]     = dev_gui_rgba(255, 60, 200, 120);
    s.Colors[ImGui.Col.TableBorderLight]      = dev_gui_rgba(80, 240, 250, 50);
    s.Colors[ImGui.Col.TableRowBg]            = dev_gui_rgba(0, 0, 0, 0);
    s.Colors[ImGui.Col.TableRowBgAlt]         = dev_gui_rgba(255, 60, 200, 18);
    s.Colors[ImGui.Col.TextLink]              = cyan;
    s.Colors[ImGui.Col.TextSelectedBg]        = dev_gui_rgba(255, 60, 200, 140);
    s.Colors[ImGui.Col.DragDropTarget]        = yellow;
    s.Colors[ImGui.Col.NavCursor]             = cyan;
    s.Colors[ImGui.Col.ModalWindowDimBg]      = dev_gui_rgba(15, 8, 35, 200);
    s.Colors[ImGui.Col.InputTextCursor]       = cyan;
}

// Engineer's blueprint paper: deep cyan-blue field, white drafting ink,
// crisp 90-degree corners, thin borders everywhere. Reads like a technical
// drawing rather than a UI panel.
dev_gui_set_theme_blueprint :: () {
    s := ImGui.GetStyle();

    s.WindowRounding    = 0.0;
    s.ChildRounding     = 0.0;
    s.PopupRounding     = 0.0;
    s.FrameRounding     = 0.0;
    s.ScrollbarRounding = 0.0;
    s.GrabRounding      = 0.0;
    s.TabRounding       = 0.0;
    s.TreeLinesRounding = 0.0;

    s.WindowBorderSize  = 1.0;
    s.ChildBorderSize   = 1.0;
    s.PopupBorderSize   = 1.0;
    s.FrameBorderSize   = 1.0;
    s.TabBorderSize     = 1.0;
    s.SeparatorTextBorderSize = 1.0;

    s.WindowPadding     = .{16, 14};
    s.FramePadding      = .{8, 5};
    s.ItemSpacing       = .{12, 8};
    s.ItemInnerSpacing  = .{6, 4};
    s.IndentSpacing     = 24.0;
    s.ScrollbarSize     = 12.0;
    s.GrabMinSize       = 12.0;

    s.WindowTitleAlign   = .{0.0, 0.5};
    s.ButtonTextAlign    = .{0.5, 0.5};
    s.SelectableTextAlign = .{0.0, 0.5};

    paper       := dev_gui_rgba(18, 50, 110);
    paper_dark  := dev_gui_rgba(10, 32, 75);
    line_dim    := dev_gui_rgba(120, 180, 240);
    line_strong := dev_gui_rgba(200, 230, 255);
    ink         := dev_gui_rgba(245, 250, 255);
    accent      := dev_gui_rgba(255, 200, 80);

    s.Colors[ImGui.Col.Text]                  = ink;
    s.Colors[ImGui.Col.TextDisabled]          = dev_gui_rgba(140, 170, 210);
    s.Colors[ImGui.Col.WindowBg]              = paper;
    s.Colors[ImGui.Col.ChildBg]               = paper_dark;
    s.Colors[ImGui.Col.PopupBg]               = paper_dark;
    s.Colors[ImGui.Col.Border]                = line_dim;
    s.Colors[ImGui.Col.BorderShadow]          = dev_gui_rgba(0, 0, 0, 0);
    s.Colors[ImGui.Col.FrameBg]               = dev_gui_rgba(255, 255, 255, 18);
    s.Colors[ImGui.Col.FrameBgHovered]        = dev_gui_rgba(255, 255, 255, 38);
    s.Colors[ImGui.Col.FrameBgActive]         = dev_gui_rgba(255, 200, 80, 70);
    s.Colors[ImGui.Col.TitleBg]               = paper_dark;
    s.Colors[ImGui.Col.TitleBgActive]         = dev_gui_rgba(15, 42, 95);
    s.Colors[ImGui.Col.TitleBgCollapsed]      = paper_dark;
    s.Colors[ImGui.Col.MenuBarBg]             = paper_dark;
    s.Colors[ImGui.Col.ScrollbarBg]           = paper_dark;
    s.Colors[ImGui.Col.ScrollbarGrab]         = line_dim;
    s.Colors[ImGui.Col.ScrollbarGrabHovered]  = line_strong;
    s.Colors[ImGui.Col.ScrollbarGrabActive]   = ink;
    s.Colors[ImGui.Col.CheckMark]             = accent;
    s.Colors[ImGui.Col.SliderGrab]            = line_strong;
    s.Colors[ImGui.Col.SliderGrabActive]      = accent;
    s.Colors[ImGui.Col.Button]                = dev_gui_rgba(255, 255, 255, 22);
    s.Colors[ImGui.Col.ButtonHovered]         = dev_gui_rgba(255, 255, 255, 60);
    s.Colors[ImGui.Col.ButtonActive]          = dev_gui_rgba(255, 200, 80, 200);
    s.Colors[ImGui.Col.Header]                = dev_gui_rgba(255, 255, 255, 30);
    s.Colors[ImGui.Col.HeaderHovered]         = dev_gui_rgba(255, 255, 255, 60);
    s.Colors[ImGui.Col.HeaderActive]          = dev_gui_rgba(255, 200, 80, 160);
    s.Colors[ImGui.Col.Separator]             = line_dim;
    s.Colors[ImGui.Col.SeparatorHovered]      = line_strong;
    s.Colors[ImGui.Col.SeparatorActive]       = accent;
    s.Colors[ImGui.Col.ResizeGrip]            = line_dim;
    s.Colors[ImGui.Col.ResizeGripHovered]     = line_strong;
    s.Colors[ImGui.Col.ResizeGripActive]      = accent;
    s.Colors[ImGui.Col.Tab]                   = paper_dark;
    s.Colors[ImGui.Col.TabHovered]            = dev_gui_rgba(255, 255, 255, 50);
    s.Colors[ImGui.Col.TabSelected]           = paper;
    s.Colors[ImGui.Col.TabSelectedOverline]   = accent;
    s.Colors[ImGui.Col.TabDimmed]             = paper_dark;
    s.Colors[ImGui.Col.TabDimmedSelected]     = paper;
    s.Colors[ImGui.Col.PlotLines]             = line_strong;
    s.Colors[ImGui.Col.PlotLinesHovered]      = accent;
    s.Colors[ImGui.Col.PlotHistogram]         = line_dim;
    s.Colors[ImGui.Col.PlotHistogramHovered]  = accent;
    s.Colors[ImGui.Col.TableHeaderBg]         = paper_dark;
    s.Colors[ImGui.Col.TableBorderStrong]     = line_strong;
    s.Colors[ImGui.Col.TableBorderLight]      = line_dim;
    s.Colors[ImGui.Col.TableRowBg]            = dev_gui_rgba(0, 0, 0, 0);
    s.Colors[ImGui.Col.TableRowBgAlt]         = dev_gui_rgba(255, 255, 255, 14);
    s.Colors[ImGui.Col.TextLink]              = accent;
    s.Colors[ImGui.Col.TextSelectedBg]        = dev_gui_rgba(255, 200, 80, 110);
    s.Colors[ImGui.Col.DragDropTarget]        = accent;
    s.Colors[ImGui.Col.NavCursor]             = accent;
    s.Colors[ImGui.Col.ModalWindowDimBg]      = dev_gui_rgba(10, 32, 75, 220);
    s.Colors[ImGui.Col.InputTextCursor]       = accent;
}

// Frosted-glass minimalism. Translucent panels, very low-alpha frames, soft
// muted accents, large rounding. Looks more like macOS sidebar/Vision OS
// glass than the usual flat imgui slab.
dev_gui_set_theme_carbon_frost :: () {
    s := ImGui.GetStyle();

    s.WindowRounding    = 14.0;
    s.ChildRounding     = 12.0;
    s.PopupRounding     = 12.0;
    s.FrameRounding     = 8.0;
    s.ScrollbarRounding = 12.0;
    s.GrabRounding      = 8.0;
    s.TabRounding       = 8.0;
    s.TreeLinesRounding = 4.0;

    s.WindowBorderSize  = 1.0;
    s.ChildBorderSize   = 0.0;
    s.PopupBorderSize   = 1.0;
    s.FrameBorderSize   = 0.0;
    s.TabBorderSize     = 0.0;

    s.WindowPadding     = .{20, 18};
    s.FramePadding      = .{12, 8};
    s.ItemSpacing       = .{14, 12};
    s.ItemInnerSpacing  = .{10, 8};
    s.IndentSpacing     = 24.0;
    s.ScrollbarSize     = 12.0;
    s.GrabMinSize       = 18.0;

    s.WindowTitleAlign   = .{0.0, 0.5};
    s.ButtonTextAlign    = .{0.5, 0.5};
    s.SelectableTextAlign = .{0.0, 0.5};

    glass_bg     := dev_gui_rgba(20, 24, 32, 215);
    glass_child  := dev_gui_rgba(255, 255, 255, 14);
    glass_frame  := dev_gui_rgba(255, 255, 255, 22);
    glass_hover  := dev_gui_rgba(255, 255, 255, 40);
    glass_active := dev_gui_rgba(255, 255, 255, 70);
    edge         := dev_gui_rgba(255, 255, 255, 35);
    text_main    := dev_gui_rgba(240, 244, 250);
    text_dim     := dev_gui_rgba(160, 170, 190);
    accent       := dev_gui_rgba(120, 200, 255);
    accent_warm  := dev_gui_rgba(255, 170, 140);

    s.Colors[ImGui.Col.Text]                  = text_main;
    s.Colors[ImGui.Col.TextDisabled]          = text_dim;
    s.Colors[ImGui.Col.WindowBg]              = glass_bg;
    s.Colors[ImGui.Col.ChildBg]               = glass_child;
    s.Colors[ImGui.Col.PopupBg]               = dev_gui_rgba(20, 24, 32, 235);
    s.Colors[ImGui.Col.Border]                = edge;
    s.Colors[ImGui.Col.BorderShadow]          = dev_gui_rgba(0, 0, 0, 0);
    s.Colors[ImGui.Col.FrameBg]               = glass_frame;
    s.Colors[ImGui.Col.FrameBgHovered]        = glass_hover;
    s.Colors[ImGui.Col.FrameBgActive]         = glass_active;
    s.Colors[ImGui.Col.TitleBg]               = dev_gui_rgba(0, 0, 0, 0);
    s.Colors[ImGui.Col.TitleBgActive]         = dev_gui_rgba(255, 255, 255, 10);
    s.Colors[ImGui.Col.TitleBgCollapsed]      = dev_gui_rgba(0, 0, 0, 0);
    s.Colors[ImGui.Col.MenuBarBg]             = dev_gui_rgba(255, 255, 255, 8);
    s.Colors[ImGui.Col.ScrollbarBg]           = dev_gui_rgba(0, 0, 0, 0);
    s.Colors[ImGui.Col.ScrollbarGrab]         = dev_gui_rgba(255, 255, 255, 60);
    s.Colors[ImGui.Col.ScrollbarGrabHovered]  = dev_gui_rgba(255, 255, 255, 110);
    s.Colors[ImGui.Col.ScrollbarGrabActive]   = dev_gui_rgba(255, 255, 255, 160);
    s.Colors[ImGui.Col.CheckMark]             = accent;
    s.Colors[ImGui.Col.SliderGrab]            = dev_gui_rgba(255, 255, 255, 200);
    s.Colors[ImGui.Col.SliderGrabActive]      = accent;
    s.Colors[ImGui.Col.Button]                = glass_frame;
    s.Colors[ImGui.Col.ButtonHovered]         = glass_hover;
    s.Colors[ImGui.Col.ButtonActive]          = dev_gui_rgba(120, 200, 255, 180);
    s.Colors[ImGui.Col.Header]                = dev_gui_rgba(120, 200, 255, 40);
    s.Colors[ImGui.Col.HeaderHovered]         = dev_gui_rgba(120, 200, 255, 80);
    s.Colors[ImGui.Col.HeaderActive]          = dev_gui_rgba(120, 200, 255, 140);
    s.Colors[ImGui.Col.Separator]             = dev_gui_rgba(255, 255, 255, 30);
    s.Colors[ImGui.Col.SeparatorHovered]      = dev_gui_rgba(255, 255, 255, 80);
    s.Colors[ImGui.Col.SeparatorActive]       = accent;
    s.Colors[ImGui.Col.ResizeGrip]            = dev_gui_rgba(255, 255, 255, 30);
    s.Colors[ImGui.Col.ResizeGripHovered]     = dev_gui_rgba(255, 255, 255, 80);
    s.Colors[ImGui.Col.ResizeGripActive]      = accent;
    s.Colors[ImGui.Col.Tab]                   = glass_child;
    s.Colors[ImGui.Col.TabHovered]            = glass_hover;
    s.Colors[ImGui.Col.TabSelected]           = glass_active;
    s.Colors[ImGui.Col.TabSelectedOverline]   = accent;
    s.Colors[ImGui.Col.TabDimmed]             = glass_child;
    s.Colors[ImGui.Col.TabDimmedSelected]     = glass_frame;
    s.Colors[ImGui.Col.PlotLines]             = accent;
    s.Colors[ImGui.Col.PlotLinesHovered]      = accent_warm;
    s.Colors[ImGui.Col.PlotHistogram]         = dev_gui_rgba(120, 200, 255, 200);
    s.Colors[ImGui.Col.PlotHistogramHovered]  = accent_warm;
    s.Colors[ImGui.Col.TableHeaderBg]         = glass_frame;
    s.Colors[ImGui.Col.TableBorderStrong]     = dev_gui_rgba(255, 255, 255, 50);
    s.Colors[ImGui.Col.TableBorderLight]      = dev_gui_rgba(255, 255, 255, 20);
    s.Colors[ImGui.Col.TableRowBg]            = dev_gui_rgba(0, 0, 0, 0);
    s.Colors[ImGui.Col.TableRowBgAlt]         = dev_gui_rgba(255, 255, 255, 8);
    s.Colors[ImGui.Col.TextLink]              = accent;
    s.Colors[ImGui.Col.TextSelectedBg]        = dev_gui_rgba(120, 200, 255, 120);
    s.Colors[ImGui.Col.DragDropTarget]        = accent_warm;
    s.Colors[ImGui.Col.NavCursor]             = accent;
    s.Colors[ImGui.Col.ModalWindowDimBg]      = dev_gui_rgba(10, 12, 18, 180);
    s.Colors[ImGui.Col.InputTextCursor]       = accent;
}

draw_dev_gui :: (cmd: VkCommandBuffer) {
    ImplVulkan_NewFrame();
    ImplWin32_NewFrame();
    NewFrame();

    if context.renderer.user_imgui_callback != null {
        context.renderer.user_imgui_callback();
    }

    Render();
    ImGui.ImplVulkan_RenderDrawData(ImGui.GetDrawData(), cmd);
}

#scope_module


imgui_update_key_modifiers :: (using io: *IO, event: *Event) {
    AddKeyEvent(io, .Mod_Ctrl,  event.ctrl_pressed);
    AddKeyEvent(io, .Mod_Shift, event.shift_pressed);
    AddKeyEvent(io, .Mod_Alt,   event.alt_pressed);
    AddKeyEvent(io, .Mod_Super, event.cmd_meta_pressed);
}

input_key_to_imgui_key :: (using io: *IO, key_code: Key_Code) -> Key {
    if key_code >= #char "A" && key_code <= #char "Z" {
        letter_diff := key_code.(s32) - #char "A";
        return xx (Key.A.(s32) + letter_diff);
    }
    if key_code >= #char "0" && key_code <= #char "9" {
        number_diff := key_code.(s32) - #char "0";
        return xx (Key._0.(s32) + number_diff);
    }
    if key_code >= .F1 && key_code <= .F24 {
        fkey_diff := key_code.(s32) - Key_Code.F1.(s32);
        return xx (Key.F1.(s32) + fkey_diff);
    }
    if key_code == {
    case .UNKNOWN; 
        return .None;
    case .BACKSPACE;
        return .Backspace;
    case .TAB;
        return .Tab;
    case .LINEFEED;
        return .None;
    case .ENTER;
        return .Enter;
    case .ESCAPE;
        return .Escape;
    case .SPACEBAR;
        return .Space;
    // The letters A-Z live in here as well and may be returned
    // by keyboard events.
    case .DELETE;
        return .Delete;
    case .ARROW_UP;
        return .UpArrow;
    case .ARROW_DOWN;
        return .DownArrow;
    case .ARROW_LEFT;
        return .LeftArrow;
    case .ARROW_RIGHT;
        return .RightArrow;
    case .PAGE_UP;
        return .PageUp;
    case .PAGE_DOWN;
        return .PageDown;
    case .HOME;
        return .Home;
    case .END;
        return .End;
    case .INSERT;
        return .Insert;
    case .PAUSE;
        return .Pause;
    case .SCROLL_LOCK;
        return .ScrollLock;
    case .ALT;
        return .LeftAlt; 
    case .CTRL;
        return .LeftCtrl;
    case .SHIFT;
        return .LeftShift;
    case .CMD; // case .META;
        return .LeftSuper;
    case .PRINT_SCREEN;
        return .PrintScreen;
    case .MOUSE_BUTTON_LEFT;
        return .MouseLeft;
    case .MOUSE_BUTTON_MIDDLE;
        return .MouseMiddle;
    case .MOUSE_BUTTON_RIGHT;
        return .MouseRight;
    // case .MOUSE_WHEEL_UP;
    //     return .MouseWheelY;
    // case .MOUSE_WHEEL_DOWN;
    //     return .MouseWheelX;
    }
    // TODO:
    // from:
    // case .GAMEPAD_0_BEGIN;
    // case .GAMEPAD_0_END :: GAMEPAD_0_BEGIN + xx GAMEPAD_BUTTON_COUNT;
    // case .GAMEPAD_1_BEGIN;
    // case .GAMEPAD_1_END :: GAMEPAD_1_BEGIN + xx GAMEPAD_BUTTON_COUNT;
    // case .GAMEPAD_2_BEGIN;
    // case .GAMEPAD_2_END :: GAMEPAD_2_BEGIN + xx GAMEPAD_BUTTON_COUNT;
    // case .GAMEPAD_3_BEGIN;
    // case .GAMEPAD_3_END :: GAMEPAD_3_BEGIN + xx GAMEPAD_BUTTON_COUNT;
    // to:
    // GamepadStart        :: 632;
    // GamepadBack         :: 633;
    // GamepadFaceLeft     :: 634;
    // GamepadFaceRight    :: 635;
    // GamepadFaceUp       :: 636;
    // GamepadFaceDown     :: 637;
    // GamepadDpadLeft     :: 638;
    // GamepadDpadRight    :: 639;
    // GamepadDpadUp       :: 640;
    // GamepadDpadDown     :: 641;
    // GamepadL1           :: 642;
    // GamepadR1           :: 643;
    // GamepadL2           :: 644;
    // GamepadR2           :: 645;
    // GamepadL3           :: 646;
    // GamepadR3           :: 647;
    // GamepadLStickLeft   :: 648;
    // GamepadLStickRight  :: 649;
    // GamepadLStickUp     :: 650;
    // GamepadLStickDown   :: 651;
    // GamepadRStickLeft   :: 652;
    // GamepadRStickRight  :: 653;
    // GamepadRStickUp     :: 654;
    // GamepadRStickDown   :: 655;
    return .None;
}

#scope_file

using ImGui;
