# =====================================================================
# Animation Combiner
# Usage: blender --background --python combine_animations.py -- <output.blend> <input1> <input2> ...
# =====================================================================
# Takes multiple mesh/animation files that share the same armature and
# combines them into a single .blend with one armature and all animations.
# Animation names are derived from input filenames.

import sys
import os
import bpy


def fatal(msg):
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def action_name_from_path(path):
    """Derive a clean animation name from a file path.
    e.g. 'mouse_old_man_idle.fbx' -> 'old_man_idle'
    Strips the common prefix shared with other files if possible,
    but falls back to the full stem."""
    return os.path.splitext(os.path.basename(path))[0]


def do_import(path):
    ext = os.path.splitext(path)[1].lower()
    if ext in ('.gltf', '.glb'):
        bpy.ops.import_scene.gltf(filepath=path)
    elif ext == '.fbx':
        bpy.ops.import_scene.fbx(filepath=path)
    elif ext == '.obj':
        try:
            bpy.ops.wm.obj_import(filepath=path)
        except AttributeError:
            bpy.ops.import_scene.obj(filepath=path)
    elif ext == '.dae':
        bpy.ops.wm.collada_import(filepath=path)
    else:
        fatal(f"Unsupported format: {ext}")


def get_armature_from_selection():
    """Find the armature among the just-imported selected objects."""
    for obj in bpy.context.selected_objects:
        if obj.type == 'ARMATURE':
            return obj
    return None


def collect_actions():
    """Return all actions currently in the blend file."""
    return set(bpy.data.actions)


def parse_args():
    argv = sys.argv
    if '--' not in argv:
        fatal("Usage: blender --background --python combine_animations.py -- <output.blend> <input1> <input2> ...")
    args = argv[argv.index('--') + 1:]
    if len(args) < 3:
        fatal("Need at least an output path and two input files.")
    return args[0], args[1:]


def main():
    output_path, input_files = parse_args()

    for f in input_files:
        if not os.path.isfile(f):
            fatal(f"Input file not found: {f}")

    # Clear default scene
    bpy.ops.wm.read_factory_settings(use_empty=True)

    primary_armature = None
    all_actions = {}

    for i, filepath in enumerate(input_files):
        print(f"\n--- Importing [{i+1}/{len(input_files)}]: {filepath} ---")

        actions_before = collect_actions()
        bpy.ops.object.select_all(action='DESELECT')

        do_import(filepath)

        armature = get_armature_from_selection()
        if armature is None:
            fatal(f"No armature found in {filepath}")

        # Grab new actions that appeared from this import
        actions_after = collect_actions()
        new_actions = actions_after - actions_before

        anim_name = action_name_from_path(filepath)

        if i == 0:
            # First file: keep armature and meshes as the primary
            primary_armature = armature
            if new_actions:
                action = list(new_actions)[0]
                action.name = anim_name
                all_actions[anim_name] = action
                print(f"  Primary armature: {primary_armature.name}")
                print(f"  Animation: {action.name}")
            else:
                # Check if the armature already has an action
                if armature.animation_data and armature.animation_data.action:
                    action = armature.animation_data.action
                    action.name = anim_name
                    all_actions[anim_name] = action
                    print(f"  Primary armature: {primary_armature.name}")
                    print(f"  Animation: {action.name}")
                else:
                    print(f"  WARNING: No animation found in {filepath}")
        else:
            # Subsequent files: grab the action, then delete imported objects
            if new_actions:
                action = list(new_actions)[0]
            elif armature.animation_data and armature.animation_data.action:
                action = armature.animation_data.action
            else:
                print(f"  WARNING: No animation found in {filepath}, skipping")
                # Clean up imported objects
                for obj in list(bpy.context.selected_objects):
                    bpy.data.objects.remove(obj, do_unlink=True)
                continue

            action.name = anim_name
            all_actions[anim_name] = action
            print(f"  Animation: {action.name}")

            # Unlink action from the imported armature before deleting it
            if armature.animation_data:
                armature.animation_data.action = None

            # Delete all imported objects from this file (armature, meshes, etc.)
            # Collect names first, then delete — references can go stale mid-loop
            imported_names = [obj.name for obj in bpy.context.selected_objects]
            bpy.ops.object.select_all(action='DESELECT')
            for name in imported_names:
                obj = bpy.data.objects.get(name)
                if obj is not None:
                    bpy.data.objects.remove(obj, do_unlink=True)

    if primary_armature is None:
        fatal("No armature found in any input file.")

    # Ensure the primary armature has animation data
    if not primary_armature.animation_data:
        primary_armature.animation_data_create()

    # Store all animations as actions with fake users so they persist in the file.
    # The user can switch between them in the Action Editor dropdown.
    # We intentionally do NOT push them to NLA tracks, because active NLA strips
    # override the selected action and prevent switching.
    print(f"\n--- Combining {len(all_actions)} animations ---")
    first_action = True
    for name, action in all_actions.items():
        action.use_fake_user = True
        print(f"  {name}: {action.frame_range[0]:.0f} - {action.frame_range[1]:.0f}")

        if first_action:
            primary_armature.animation_data.action = action
            first_action = False

    # Record the canonical animation order on the scene. bpy.data.actions
    # iterates alphabetically, so convert_mesh.py can't recover input order
    # from the action collection alone.
    bpy.context.scene["term_anim_order"] = list(all_actions.keys())

    # Clean up orphan data
    for mesh in bpy.data.meshes:
        if mesh.users == 0:
            bpy.data.meshes.remove(mesh)
    for arm in bpy.data.armatures:
        if arm.users == 0:
            bpy.data.armatures.remove(arm)

    # Save
    bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(output_path))
    print(f"\nSaved: {os.path.abspath(output_path)}")
    print(f"Animations: {list(all_actions.keys())}")


if __name__ == '__main__':
    main()
