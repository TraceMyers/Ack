// todo: table of material interactions (use 32 bit key so no need for hashing proc, sort values high-low so key-values are unique)
// todo: make it so users can make new materials.

Physics_Material :: struct {
    // scale of height variation (0 to 1)
    roughness: float;
    // springiness of contact (0 to 1)
    elasticity: float;
    // how slippery (0 to 1)
    slipperiness: float;
}

Friction_Data :: struct {
    mu_static: float;    // static  friction coef
    mu_coulomb: float;   // dynamic friction coef
    inv_stribeck: float; // .
}

#insert #run generate_parallel_enum_and_array(

    {"CONCRETE", {
        roughness = 0.95,
        elasticity = 0.01,
        slipperiness = 0.1 // particulation/dust
    }},
    {"SKIN", {
        roughness = 0.2,
        elasticity = 0.3,
        slipperiness = 0.3 // oil
    }},
    {"ROUGH_WOOD", {
        roughness = 0.7,
        elasticity = 0.12,
        slipperiness = 0.05
    }},
    {"SMOOTH_WOOD", {
        roughness = 0.05,
        elasticity = 0.05,
        slipperiness = 0.1
    }},
    {"GLASS", {
        roughness = 0.025,
        elasticity = 0.02,
        slipperiness = 0.1
    }},
    {"OILED_SMOOTH_METAL", {
        roughness = 0.05,
        elasticity = 0.04,
        slipperiness = 1.0
    }},
    {"SMOOTH_METAL", {
        roughness = 0.05,
        elasticity = 0.04,
        slipperiness = 0.05
    }},
    {"RUBBER", {
        roughness = 0.2,
        elasticity = 1.0,
        slipperiness = 0.001
    }},
    {"ASPHALT", {
        roughness = 0.85,
        elasticity = 0.5,
        slipperiness = 0.05
    }},

    enum_name="Physics_Material_Name", u8, "PHYSICS_MATERIALS", "Physics_Material", true
);

FRICTION_DEFAULT :: #run make_friction_data(physics_material(.SKIN), physics_material(.ROUGH_WOOD));

physics_material :: inline (name: Physics_Material_Name) -> Physics_Material {
    return PHYSICS_MATERIALS[name];
}

calculate_friction :: inline (mu: float, normal_force: float) -> float {
    return mu * normal_force;
}

calculate_viscous_friction :: inline (mu: float, normal_force: float, speed: float) -> float {
    return mu * normal_force * speed;
}

calculate_stribeck_friction :: inline (using friction: Friction_Data, normal_force: float, speed: float) -> float {
    return calculate_stribeck_friction(inv_stribeck, mu_static, mu_coulomb, normal_force, speed);
}

calculate_stribeck_friction :: (inv_stribeck_speed: float, mu_s: float, mu_c: float, normal_force: float, speed: float) -> float {
    f_c := calculate_friction(mu_c, normal_force);
    f_s := calculate_friction(mu_s, normal_force);
    f_v := calculate_viscous_friction(mu_c, normal_force, speed);
    return f_c + (f_s - f_c) / (1 + square(speed * inv_stribeck_speed)) + f_v;
}

// this was slapped together incrementally by just adjusting the calculations until
// their outputs matched tables pretty well. it is kind of a mess, but if you read
// through it you'll see there's some sense to it.
make_friction_data :: (material_a: Physics_Material, material_b: Physics_Material, stribeck_factor := 1.0) -> Friction_Data {
    // max value > 1 to account for the fact that static friction is sometimes > 1
    // also it just made the outputs more like the tables I saw online.
    roughness := (material_a.roughness + material_b.roughness) * 0.6;

    // smooth things with very similar roughness can get somewhat stuck together.
    // it's not simulated very strongly here, but to the extent that it is simulated,
    // it's done by increasing static friction and slightly reducing slipperiness.
    min_roughness, max_roughness := min_and_max(material_a.roughness, material_b.roughness);
    rough_likeness := min_roughness / max_roughness;
    same_roughness_factor := rough_likeness * square(max(0.1 - roughness, 0) * 10);

    // conflating oil, water and particulation here, the user just needs to know 
    // how 'slippery' the surface is. base slipperiness maxes out at 1. slipperiness maxes 
    // out at 0.5. slipperiness both reduces both friction coefficients, and quickens the 
    // transition between static and dynamic friction.
    base_slipperiness := min(material_a.slipperiness + material_b.slipperiness, 1.0);
    slipperiness := max(base_slipperiness - same_roughness_factor * 0.25, 0);

    // elasticity is how much the contact can deform while staying static, like rubber
    // deforming on a rough surface but returning to where it was when force is taken away.
    // also factors into dynamic friction because I figure the elastic component is
    // applying little partial spring forces during a slide. But, the contribution
    // is less to dynamic friction because surfaces conform to eachother more at full rest.
    elasticity := (material_a.elasticity + material_b.elasticity) * 0.5;

    mu_s_numerator_partial := roughness * (1 + elasticity * 1.5);
    mu_s := (mu_s_numerator_partial + same_roughness_factor) / (slipperiness * 2 + 1.0);
    mu_c := (roughness * (0.5 + elasticity)) / (slipperiness * 2 + 0.5 + roughness * elasticity);
    inv_stribeck := stribeck_factor * (3 - mu_s_numerator_partial) + base_slipperiness * (stribeck_factor * 30);

    return {mu_s, mu_c, inv_stribeck};
}

// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.
