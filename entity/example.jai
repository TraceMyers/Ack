// an entity is a transform-having component, which itself can have child components.
// non-entity components can't be parents. 
//
// components don't need to have parents. they can exist in a detached state. e.g. most entities 
// will not have parent entities in most games unless your world is an entity or something 
// like that.

Example_Entity :: struct {
    using #as base: Entity;
    input: *Input;
    camera: *Camera;
    child: *Example_Child_Entity;
}

Example_Child_Entity :: struct {
    using #as base: Entity;
    input: *Input;
    physics: *Physics_Body;
}

example_entity_proc :: () {
    add_entity_type(Example_Entity);
    add_entity_type(Example_Child_Entity);

    // make_entity returns *Example_Entity. points to a particular allotment within component 
    // storage for all components of type Example_Entity.
    guy := make_entity(Example_Entity);

    // allocate an input and a camera component for guy
    add_component(guy, *guy.input);
    add_component(guy, *guy.camera);

    // you can create an entity as a component. 'child' is an entity type.
    add_component(guy, *guy.child);

    // add_component is never automatically called (it's not worth it to add the complexity).
    add_component(guy.child, *guy.child.physics);

    guy.child.position.x = 100;
    guy.position.x = 100;
    child_position := get_position(*guy.child);
    // the x position of the child is relative to the x position of the parent. 100 + 100 = 200.
    engine_log("guy x pos: %, child x pos: %", guy.position.x, child_position.x);

    // after this, child is no longer a child. it's detached like a more typical entity.
    // it retains its x world position (200) on detach.
    child_id := detach_component(guy, *guy.child);

    // get_entity returns the entity type-stripped down to the base Entity class
    detached_child: *Entity = get_entity(child_id);

    // you can also get it correctly typed in one of these ways...
    // detached_child := get_component(child_id, Example_Child_Entity);
    // detached_child := get_entity(child_id, Example_Child_Entity);

    engine_log("detached child x pos: %", guy.position.x, child_position.x);
    
    // we could just directly cast(*Example_Child_Entity), but here is how you can do
    // a dynamic cast from Entity to Example_Child_Entity
    other_guy := cast_entity(detached_child, Example_Child_Entity);

    // this does the same thing, since entities are components.
    // other_guy := cast_component(detached_child, Example_Child_Entity);

    // you can transfer ownership of a component in a single call
    // after this, guy.input is null and other_guy.input points to the allocated input component
    // this is not incredibly expensive (particularly for components without transform),
    // and so can be used creatively for gameplay systems.
    transfer_component(guy, *guy.input, other_guy, *other_guy.input);

    // all remaining components are hierarchically destroyed using the entity as a root when you 
    // destroy it. meaning: if guy has a child and that child has a child, the whole tree of 
    // entities and their components will be freed back to the system.
    destroy_entity(guy);

    // here we detach the input component before destroying...
    input_id := detach_component(other_guy, *other_guy.input);
    destroy_entity(other_guy);

    // ... which means the component still needs to be freed
    remove_component(input_id);
}
