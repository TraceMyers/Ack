Component :: struct {
    parent: Entity_ID;
}

Spatial_Component :: struct {
    using #as component_base: Component;
    using transform: Transform_No_Scale;
}

Scalable_Spatial_Component :: struct {
    using #as component_base: Component;
    using transform: Transform;
}

Transform :: struct {
    position: Vector3;
    orientation: Quaternion;
    scale := Vector3.{1,1,1};
}

Transform_No_Scale :: struct {
    position: Vector3;
    orientation: Quaternion;
}

Input :: struct {
    using #as base: Component;
    move: Vector2;
    received_move_input_last_physics_step: bool;
    last_nonzero_move_input: Vector2;

    look: Vector2i;
    look_smoothed: Vector2;
}

Camera :: struct {
    using #as base: Spatial_Component;
    using info: Camera_Info;

    translation_speed := 1.0;
    rotation_speed := 2.5;
    look_up_degree_limit := 85.0;

    free_fly_toggle: bool;
}

get_parent :: (component: *$C/Component) -> *Entity {
    if is_null(component.parent) {
        return null;
    }
    parent := get_component_data(component.parent);
    return cast(*Entity) parent;
}

// try to cast component to type C. null if failure. if 'exact_match', then
// the component must be of type T. if not, then T can be a superclass of the component's type.
cast_component :: inline (component: *Component, $T: Type, $exact_match := false) -> *T {
    component_tinfo := engine.components[component.id.type_handle].tinfo;
    if component_tinfo == type_info(T) {
        return xx component;
    }
    #if !exact_match {
        T_NAME :: #run tprint("%", T);
        if is_subclass_of(component_tinfo, T_NAME) {
            return xx component;
        }
    } 
    return null;
}

// same as cast_component, but the cast must succeed.
cast_component_checked :: inline (component: *Component, $C/Component, $exact_match := false) -> *C {
    ptr := cast_component(component, exact_match);
    engine_check(ptr != null);
    return ptr;
}

component_has_position_and_orientation :: ($C/Component: Type) -> bool {
    return is_subclass_of(C, "Spatial_Component") || is_subclass_of(C, "Scalable_Spatial_Component");
}

component_has_scale :: ($C/Component: Type) -> bool {
    return is_subclass_of(C, "Scalable_Spatial_Component");
}

get_transform :: (component: *$C/Component, tform: *Transform) {
    IS_SPATIAL :: #run (is_subclass_of(C, "Spatial_Component");
    IS_SCALABLE_SPATIAL :: #run (is_subclass_of(C, "Scalable_Spatial_Component");

    parent := get_parent(component);

    if parent != null {
        get_transform(parent, tform);

        #if IS_SPATIAL {
            tform.position += rotate(component.position, tform.orientation);
            tform.orientation *= component.orientation;
        } else #if IS_SCALABLE_SPATIAL {
            tform.position += rotate(component.position, tform.orientation);
            tform.orientation *= component.orientation;
            tform.scale *= component.scale;
        }
    } else {
        #if IS_SPATIAL {
            tform.position = component.position;
            tform.orientation = component.orientation;
            tform.scale = {1,1,1};
        } else #if IS_SCALABLE_SPATIAL {
            tform.position = component.position;
            tform.orientation = component.orientation;
            tform.scale = component.scale;
        } else {
            tform.* = {};
        }
    }
}

get_transform_no_scale :: (component: *$C/Component, tform: *Transform_No_Scale) {
    IS_ANY_SPATIAL :: #run component_has_position_and_orientation(C);
    parent := get_parent(component);

    if parent != null {
        get_transform_no_scale(parent, tform);

        #if IS_ANY_SPATIAL {
            tform.position += rotate(component.position, tform.orientation);
            tform.orientation *= component.orientation;
        }
    } else {
        #if IS_ANY_SPATIAL {
            tform.position = component.position;
            tform.orientation = component.orientation;
        } else {
            tform.* = {};
        }
    }
}

get_position :: (component: *$T) -> Vector3 
#modify { 
    return T != Physics_Body;
} {
    tform: Transform_No_Scale = ---;
    get_transform_no_scale(component, *tform);
    return tform.position;
}

get_orientation :: (component: *$T) -> Quaternion {
    IS_ANY_SPATIAL :: #run component_has_position_and_orientation(C);

    orientation: Quaternion = ---;
    parent := get_parent(component);

    if parent != null {
        orientation = get_orientation(parent);

        #if IS_ANY_SPATIAL {
            orientation *= component.orientation;
        }
    } else {
        #if IS_ANY_SPATIAL {
            orientation = component.orientation;
        } else {
            orientation = {};
        }
    }

    return orientation;
}

get_scale :: (component: *$T) -> Vector3 {
    IS_ANY_SPATIAL :: #run component_has_position_and_orientation(C);

    scale: Vector3 = ---;
    parent := get_parent(component);

    if parent != null {
        scale = get_scale(parent);

        #if IS_ANY_SPATIAL {
            scale *= component.scale;
        }
    } else {
        #if IS_ANY_SPATIAL {
            scale = component.scale;
        } else {
            scale = {1,1,1};
        }
    }

    return scale;

}

get_axes :: inline (component: *$T) -> x: Vector3, y: Vector3, z: Vector3 {
    x, y, z: Vector3 = ---;
    calculate_axes(get_orientation(component), *x, *y, *z);
    return x, y, z;
}
