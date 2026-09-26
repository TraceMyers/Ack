# =====================================================================
# TRM Mesh Exporter
# Usage: blender --background --python convert_mesh.py -- <input> <output.trm>
# optional arg: you can repeatedly use --exclude <node name> to exclude that node
# optional arg: you can repeatedly use --include <node name> to include only those nodes
#               (mutually exclusive with --exclude)
# optional arg: --static skips joint/animation extraction entirely
# =====================================================================
# leverage blender to convert other mesh file formats to the term mesh file format
# for format specs / ai tool codegen instructions, see end of file

# supported extensions of input files:
# blend, gltf, glb, fbx, obj, dae, stl, ply, usd, usda, usdc, usdz, abc

import sys
import importlib

def ensure_deps():
    """Install any missing packages into Blender's bundled Python."""
    import site
    # Blender excludes user site-packages from sys.path; add it so pip's
    # --user installs (the default when the system dir isn't writable) work.
    user_site = site.getusersitepackages()
    if user_site not in sys.path:
        sys.path.append(user_site)

    required = [('numpy', 'numpy'), ('png', 'pypng')]
    missing = []
    for mod_name, pip_name in required:
        try:
            importlib.import_module(mod_name)
        except ImportError:
            missing.append(pip_name)
    if not missing:
        return

    try:
        subprocess.check_call(
            [sys.executable, '-m', 'ensurepip', '--upgrade'],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        pass
    subprocess.check_call(
        [sys.executable, '-m', 'pip', 'install', '--quiet'] + missing)
    importlib.invalidate_caches()

ensure_deps()

import os
import subprocess
import bpy
import struct
import bmesh
import numpy as np
import png
import io


def action_fcurves(action):
    """Return fcurves from an Action, compatible with Blender 4.4+ layered actions."""
    if hasattr(action, 'fcurves'):
        return action.fcurves
    curves = []
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                curves.extend(bag.fcurves)
    return curves


HEADER_SIZE = 56
SECTION_FILE_SIZE = 168
ANIM_FILE_SIZE = 16
JOINT_FILE_SIZE = 112


def fatal(msg):
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def pad4(data):
    r = len(data) % 4
    return data + b'\x00' * ((4 - r) % 4) if r else data


def mat4_rows(m):
    """Blender Matrix -> 16 floats in row-major order (matches Jai Matrix4 layout)."""
    return [m[r][c] for r in range(4) for c in range(4)]


# ---- Buffer management ----

class Bufs:
    def __init__(self):
        self._b = []

    def _add(self, t, n, sz, d):
        self._b.append(pad4(struct.pack('<iii', t, n, sz) + d))
        return len(self._b) - 1

    def string(self, s):
        e = s.encode('utf-8')
        return self._add(0, len(e), 1, e)

    def idx16(self, v):
        return self._add(1, len(v), 2, struct.pack(f'<{len(v)}H', *v))

    def idx32(self, v):
        return self._add(2, len(v), 4, struct.pack(f'<{len(v)}I', *v))

    def static_verts(self, vs):
        return self._add(4, len(vs), 72,
                         b''.join(struct.pack('<18f', *v) for v in vs))

    def skinned_verts(self, vs):
        return self._add(5, len(vs), 96, b''.join(
            struct.pack('<18f4H4f', *v[:18],
                        int(v[18]), int(v[19]), int(v[20]), int(v[21]),
                        *v[22:26])
            for v in vs))

    def floats(self, fs):
        return self._add(3, len(fs), 4, struct.pack(f'<{len(fs)}f', *fs))

    def joint_transforms(self, ts):
        return self._add(6, len(ts), 40,
                         b''.join(struct.pack('<10f', *t) for t in ts))

    def texture(self, w, h, rgba):
        rows = [rgba[y * w * 4:(y + 1) * w * 4] for y in range(h)]
        buf = io.BytesIO()
        png.Writer(width=w, height=h, alpha=True, greyscale=False).write_packed(buf, rows)
        png_data = buf.getvalue()
        return self._add(0, len(png_data), 1, png_data)

    def total(self):
        return sum(len(b) for b in self._b)

    def offsets(self, base):
        o, p = [], base
        for b in self._b:
            o.append(p)
            p += len(b)
        return o

    def data(self):
        return b''.join(self._b)


# ---- File import ----

def do_import(path):
    ext = os.path.splitext(path)[1].lower()
    try:
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
        elif ext == '.stl':
            try:
                bpy.ops.wm.stl_import(filepath=path)
            except AttributeError:
                bpy.ops.import_mesh.stl(filepath=path)
        elif ext == '.ply':
            try:
                bpy.ops.wm.ply_import(filepath=path)
            except AttributeError:
                bpy.ops.import_mesh.ply(filepath=path)
        elif ext in ('.usd', '.usda', '.usdc', '.usdz'):
            bpy.ops.wm.usd_import(filepath=path)
        elif ext == '.abc':
            bpy.ops.wm.alembic_import(filepath=path)
        else:
            fatal(f"Unsupported format: {ext}")
    except Exception as e:
        fatal(f"Import failed: {e}")


# ---- Scene traversal ----

def find_objects():
    mesh_objs = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    if not mesh_objs:
        fatal("No mesh found in scene")
    arm = None
    for mesh_obj in mesh_objs:
        for mod in mesh_obj.modifiers:
            if mod.type == 'ARMATURE' and mod.object:
                arm = mod.object
                break
        if arm:
            break
        if mesh_obj.parent and mesh_obj.parent.type == 'ARMATURE':
            arm = mesh_obj.parent
            break
    return mesh_objs, arm


# ---- Texture helpers ----

_tex_cache = {}


def trace_img(socket):
    """Walk links backward to find an Image Texture node."""
    if not socket or not socket.is_linked:
        return None
    n = socket.links[0].from_node
    if n.type == 'TEX_IMAGE' and n.image:
        return n
    for i in n.inputs:
        if i.type in ('RGBA', 'VECTOR') and i.is_linked:
            found = trace_img(i)
            if found:
                return found
    return None


def tex_settings(node):
    """(mag_filter, min_filter, h_wrap, v_wrap) from an Image Texture node."""
    if not node:
        return 0, 0, 2, 2
    f = 1 if node.interpolation == 'Closest' else 0
    wm = {'EXTEND': 0, 'CLIP': 0, 'MIRROR': 1, 'REPEAT': 2}
    w = wm.get(getattr(node, 'extension', 'REPEAT'), 2)
    return f, f, w, w


def img_rgba(image):
    """Returns (width, height, bytes) with RGBA uint8 pixels, top-down."""
    w, h = image.size
    if w == 0 or h == 0:
        fatal(f"Image '{image.name}' has zero dimensions")
    px = np.array(image.pixels[:], dtype=np.float32).reshape(h, w, 4)
    px = np.flipud(px)
    return w, h, (np.clip(px, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8).tobytes()


def img_channel(image, ch):
    """Single channel as float array (h, w), flipped to top-down."""
    w, h = image.size
    px = np.array(image.pixels[:], dtype=np.float32).reshape(h, w, 4)
    return np.flipud(px[:, :, ch])


def uv_idx(node, layers):
    """Which UV layer (0 or 1) does this texture node reference?"""
    if not node:
        return 0
    v = node.inputs.get('Vector')
    if v and v.is_linked and v.links[0].from_node.type == 'UVMAP':
        name = v.links[0].from_node.uv_map
        for i, l in enumerate(layers):
            if l.name == name:
                return min(i, 1)
    return 0


def cached_tex(image, bufs):
    """Add image to buffers with dedup. Returns buffer index."""
    k = image.filepath or image.name
    if k in _tex_cache:
        return _tex_cache[k]
    w, h, d = img_rgba(image)
    idx = bufs.texture(w, h, d)
    _tex_cache[k] = idx
    return idx


def merge_orm(occ, rough, met, bufs):
    """Merge separate O/R/M images into one ORM texture."""
    ref = occ or rough or met
    if not ref:
        return -1
    w, h = ref.size
    out = np.zeros((h, w, 4), dtype=np.uint8)
    out[:, :, 3] = 255
    for img, ch in [(occ, 0), (rough, 1), (met, 2)]:
        if not img:
            continue
        data = img_channel(img, 0)
        iw, ih = img.size
        if ih != h or iw != w:
            data = np.array(
                [[data[min(int(row * ih / h), ih - 1)]
                      [min(int(col * iw / w), iw - 1)]
                  for col in range(w)] for row in range(h)],
                dtype=np.float32)
        out[:, :, ch] = (np.clip(data, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)
    return bufs.texture(w, h, out.tobytes())


# ---- Material processing ----

def process_mat(mat, uv_layers, bufs):
    r = dict(
        name_buf=bufs.string(mat.name if mat else "default"),
        alpha_mode=0, uv=[0] * 6, alpha_cutoff=0.5,
        albedo_f=[1.0, 0.0, 1.0, 1.0], met_f=0.0, rough_f=0.5,
        emit_f=[0.0, 0.0, 0.0, 1.0],
        albedo_t=(-1, 0, 0, 2, 2), normal_t=(-1, 0, 0, 2, 2),
        emissive_t=(-1, 0, 0, 2, 2), orm_t=(-1, 0, 0, 2, 2),
    )
    if not mat or not mat.use_nodes:
        return r
    bsdf = next((n for n in mat.node_tree.nodes
                 if n.type == 'BSDF_PRINCIPLED'), None)
    if not bsdf:
        return r

    # Alpha mode
    a_in = bsdf.inputs.get('Alpha')
    if a_in and (a_in.is_linked or a_in.default_value < 1.0):
        if hasattr(mat, 'blend_method') and mat.blend_method == 'CLIP':
            r['alpha_mode'] = 1
            r['alpha_cutoff'] = getattr(mat, 'alpha_threshold', 0.5)
        else:
            r['alpha_mode'] = 2
            r['alpha_cutoff'] = 0.0

    # Albedo
    bc_in = bsdf.inputs.get('Base Color')
    bc_node = trace_img(bc_in) if bc_in else None
    if bc_node:
        r['albedo_t'] = (cached_tex(bc_node.image, bufs),) + tex_settings(bc_node)
        r['uv'][0] = uv_idx(bc_node, uv_layers)
        r['albedo_f'] = [1.0, 1.0, 1.0, 1.0]
    elif bc_in:
        v = list(bc_in.default_value)
        r['albedo_f'] = v[:4] if len(v) >= 4 else v[:3] + [1.0]
    if a_in and not a_in.is_linked:
        r['albedo_f'][3] = a_in.default_value

    # Metallic + Roughness
    m_in = bsdf.inputs.get('Metallic')
    r_in = bsdf.inputs.get('Roughness')
    m_node = trace_img(m_in) if m_in else None
    r_node = trace_img(r_in) if r_in else None
    if m_in:
        r['met_f'] = 1.0 if m_in.is_linked else m_in.default_value
    if r_in:
        r['rough_f'] = 1.0 if r_in.is_linked else r_in.default_value

    # ORM texture
    if m_node and r_node and m_node.image == r_node.image:
        r['orm_t'] = (cached_tex(m_node.image, bufs),) + tex_settings(m_node)
        u = uv_idx(m_node, uv_layers)
        r['uv'][1] = r['uv'][2] = r['uv'][4] = u
    elif m_node or r_node:
        bi = merge_orm(None,
                       r_node.image if r_node else None,
                       m_node.image if m_node else None, bufs)
        if bi >= 0:
            ref_n = m_node or r_node
            r['orm_t'] = (bi,) + tex_settings(ref_n)
            u = uv_idx(ref_n, uv_layers)
            r['uv'][1] = r['uv'][2] = r['uv'][4] = u

    # Normal
    n_in = bsdf.inputs.get('Normal')
    n_node = trace_img(n_in) if n_in else None
    if n_node:
        r['normal_t'] = (cached_tex(n_node.image, bufs),) + tex_settings(n_node)
        r['uv'][3] = uv_idx(n_node, uv_layers)

    # Emissive
    e_in = (bsdf.inputs.get('Emission Color')
            or bsdf.inputs.get('Emission'))
    e_node = trace_img(e_in) if e_in else None
    if e_in and not e_in.is_linked:
        v = list(e_in.default_value)
        r['emit_f'] = (v[:3] if len(v) >= 3 else v) + [1.0]
    if e_node:
        r['emissive_t'] = (cached_tex(e_node.image, bufs),) + tex_settings(e_node)
        r['uv'][5] = uv_idx(e_node, uv_layers)
        if all(c == 0.0 for c in r['emit_f'][:3]):
            r['emit_f'] = [1.0, 1.0, 1.0, 1.0]
    s_in = bsdf.inputs.get('Emission Strength')
    if s_in and not s_in.is_linked:
        s = s_in.default_value
        r['emit_f'] = [r['emit_f'][i] * s if i < 3
                       else r['emit_f'][i] for i in range(4)]

    return r


# ---- Vertex helpers ----

def joint_weights(vert, g2j):
    inf = sorted(
        [(g2j[g.group], g.weight)
         for g in vert.groups if g.group in g2j],
        key=lambda x: -x[1])[:4]
    while len(inf) < 4:
        inf.append((0, 0.0))
    t = sum(w for _, w in inf)
    if t > 0:
        inf = [(j, w / t) for j, w in inf]
    return [j for j, _ in inf], [w for _, w in inf]


def loop_color(mesh, li):
    try:
        if hasattr(mesh, 'color_attributes') and mesh.color_attributes.active:
            a = mesh.color_attributes.active
            if a.domain == 'CORNER':
                return tuple(a.data[li].color)[:4]
            vi = mesh.loops[li].vertex_index
            return tuple(a.data[vi].color)[:4]
    except (IndexError, AttributeError):
        pass
    try:
        if mesh.vertex_colors and mesh.vertex_colors.active:
            return tuple(mesh.vertex_colors.active.data[li].color)[:4]
    except (IndexError, AttributeError):
        pass
    return (1.0, 1.0, 1.0, 1.0)


# ---- Mesh section extraction ----

def extract_sections(mesh_obj, arm_obj, bufs):
    # Set armature to rest pose so the evaluated mesh gives bind-pose
    # vertex positions (not deformed by the current animation frame).
    if arm_obj:
        old_pose_position = arm_obj.data.pose_position
        arm_obj.data.pose_position = 'REST'
        bpy.context.view_layer.update()

    dg = bpy.context.evaluated_depsgraph_get()
    eo = mesh_obj.evaluated_get(dg)
    me = eo.to_mesh()

    # Triangulate
    bm_temp = bmesh.new()
    bm_temp.from_mesh(me)
    bmesh.ops.triangulate(bm_temp, faces=bm_temp.faces)
    bm_temp.to_mesh(me)
    bm_temp.free()

    if len(me.polygons) == 0:
        fatal("Mesh has no faces")

    if not me.uv_layers:
        me.uv_layers.new(name="UVMap")
    if hasattr(me, 'calc_normals_split'):
        me.calc_normals_split()
    me.calc_tangents()

    # Object world transform — apply to positions, normals, tangents
    world = mesh_obj.matrix_world
    nmat = world.to_3x3().inverted_safe().transposed()

    skinned = arm_obj is not None
    g2j = {}
    if skinned:
        b2j = {b.name: i for i, b in enumerate(arm_obj.data.bones)}
        for i, vg in enumerate(mesh_obj.vertex_groups):
            if vg.name in b2j:
                g2j[i] = b2j[vg.name]

    sections = []
    n_mats = max(1, len(me.materials))

    for mi in range(n_mats):
        vmap, verts, idxs = {}, [], []
        for poly in me.polygons:
            if poly.material_index != mi:
                continue
            for li in poly.loop_indices:
                lp = me.loops[li]
                vt = me.vertices[lp.vertex_index]
                pos = tuple(world @ vt.co)
                n = (nmat @ lp.normal).normalized()
                nrm = tuple(n)
                t = (nmat @ lp.tangent).normalized()
                tan = tuple(t) + (lp.bitangent_sign,)
                u0_raw = me.uv_layers[0].data[li].uv
                u0 = (u0_raw[0], 1.0 - u0_raw[1])
                if len(me.uv_layers) > 1:
                    u1_raw = me.uv_layers[1].data[li].uv
                    u1 = (u1_raw[0], 1.0 - u1_raw[1])
                else:
                    u1 = (0.0, 0.0)
                col = loop_color(me, li)
                key = pos + nrm + tan + u0 + u1 + col
                if skinned:
                    js, ws = joint_weights(vt, g2j)
                    key += tuple(js) + tuple(ws)
                if key in vmap:
                    idxs.append(vmap[key])
                else:
                    vmap[key] = len(verts)
                    idxs.append(len(verts))
                    verts.append(key)
        if not verts:
            continue

        vb = (bufs.skinned_verts(verts) if skinned
              else bufs.static_verts(verts))
        ib = (bufs.idx16(idxs) if len(verts) <= 65535
              else bufs.idx32(idxs))
        mat = me.materials[mi] if mi < len(me.materials) else None
        sections.append(dict(name_buf=bufs.string(mesh_obj.name), ib=ib, vb=vb,
                             mat=process_mat(mat, me.uv_layers, bufs)))

    eo.to_mesh_clear()

    if arm_obj:
        arm_obj.data.pose_position = old_pose_position
        bpy.context.view_layer.update()

    return sections


# ---- Skeleton extraction ----

def extract_joints(arm, bufs):
    if not arm:
        return []
    bones = list(arm.data.bones)
    bi = {b.name: i for i, b in enumerate(bones)}
    world = arm.matrix_world
    joints = []
    for b in bones:
        par = bi[b.parent.name] if b.parent else -1
        inv = mat4_rows((world @ b.matrix_local).inverted())
        lm = (b.parent.matrix_local.inverted() @ b.matrix_local
               if b.parent else world @ b.matrix_local)
        loc, rot, scl = lm.decompose()
        joints.append(dict(
            name_buf=bufs.string(b.name), parent=par, inv_bind=inv,
            t=(loc.x, loc.y, loc.z),
            r=(rot.x, rot.y, rot.z, rot.w),
            s=(scl.x, scl.y, scl.z)))
    return joints


def extract_anims(arm, bufs):
    if not arm or not arm.animation_data:
        return []
    bones = list(arm.data.bones)
    fps = bpy.context.scene.render.fps / bpy.context.scene.render.fps_base

    # bpy.data.actions iterates alphabetically, not in creation order, so we
    # can't recover input order from it directly. combine_animations.py writes
    # the canonical order to scene["term_anim_order"]; honor it when present.
    actions = []
    seen = set()
    def add_action(a):
        if a is not None and a not in seen:
            seen.add(a)
            actions.append(a)

    bone_prefix = 'pose.bones["'
    ordered_names = bpy.context.scene.get("term_anim_order")
    print(f"  [anim-order] term_anim_order scene prop: {ordered_names!r}")
    print(f"  [anim-order] bpy.data.actions: {[a.name for a in bpy.data.actions]}")
    if ordered_names is not None:
        ordered_names = list(ordered_names)
        for name in ordered_names:
            act = bpy.data.actions.get(name)
            if act is not None:
                add_action(act)
            else:
                print(f"  [anim-order] WARNING: '{name}' listed in term_anim_order but not in bpy.data.actions")

    # Pick up any remaining actions that drive this armature's bones but
    # weren't listed in term_anim_order (e.g. blend files edited by hand).
    for act in bpy.data.actions:
        if act in seen:
            continue
        for fc in action_fcurves(act):
            if fc.data_path.startswith(bone_prefix):
                add_action(act)
                break
    if arm.animation_data.action:
        add_action(arm.animation_data.action)
    for track in (arm.animation_data.nla_tracks or []):
        for strip in track.strips:
            if strip.action:
                add_action(strip.action)
    orig_action = arm.animation_data.action
    anims = []

    print(f"  [anim-order] final emit order: {[a.name for a in actions]}")
    for action in actions:
        arm.animation_data.action = action
        frames = sorted({round(kf.co[0])
                         for fc in action_fcurves(action)
                         for kf in fc.keyframe_points})
        if not frames:
            continue
        timestamps = [f / fps for f in frames]
        interp = (0 if any(kf.interpolation == 'CONSTANT'
                           for fc in action_fcurves(action)
                           for kf in fc.keyframe_points) else 1)

        xforms = []
        world = arm.matrix_world
        for fr in frames:
            bpy.context.scene.frame_set(int(fr))
            bpy.context.view_layer.update()
            for bone in bones:
                pb = arm.pose.bones[bone.name]
                lm = (pb.parent.matrix.inverted() @ pb.matrix
                       if pb.parent else world @ pb.matrix)
                loc, rot, scl = lm.decompose()
                xforms.append((loc.x, loc.y, loc.z,
                                rot.x, rot.y, rot.z, rot.w,
                                scl.x, scl.y, scl.z))

        anims.append(dict(
            name_buf=bufs.string(action.name), interp=interp,
            ts_buf=bufs.floats(timestamps),
            xf_buf=bufs.joint_transforms(xforms)))

    arm.animation_data.action = orig_action
    return anims


# ---- Write TRM file ----

def write_trm(path, sections, joints, anims, bufs):
    bo = bufs.offsets(HEADER_SIZE)
    s_off = HEADER_SIZE + bufs.total()
    a_off = s_off + len(sections) * SECTION_FILE_SIZE
    j_off = a_off + len(anims) * ANIM_FILE_SIZE

    with open(path, 'wb') as f:
        # Header
        f.write(b'TeRM-Mesh\x00\x00\x00\x00\x00\x00\x00')  # 16 bytes
        f.write(struct.pack('<i', 1))                          # version
        f.write(struct.pack('<iii',
                            len(sections), SECTION_FILE_SIZE, s_off))
        f.write(struct.pack('<iii',
                            len(anims), ANIM_FILE_SIZE, a_off))
        f.write(struct.pack('<iii',
                            len(joints), JOINT_FILE_SIZE, j_off))

        # All buffers
        f.write(bufs.data())

        # Mesh sections
        for s in sections:
            m = s['mat']
            f.write(struct.pack('<iiii',
                                bo[s['name_buf']], bo[s['ib']], bo[s['vb']],
                                bo[m['name_buf']]))
            f.write(struct.pack('<i', m['alpha_mode']))
            for u in m['uv']:
                f.write(struct.pack('<i', u))
            f.write(struct.pack('<f', m['alpha_cutoff']))
            f.write(struct.pack('<4f', *m['albedo_f']))
            f.write(struct.pack('<f', m['met_f']))
            f.write(struct.pack('<f', m['rough_f']))
            f.write(struct.pack('<4f', *m['emit_f']))
            for key in ('albedo_t', 'normal_t', 'emissive_t', 'orm_t'):
                bi, mag, mn, hw, vw = m[key]
                f.write(struct.pack('<iiiii',
                                    bo[bi] if bi >= 0 else -1,
                                    mag, mn, hw, vw))

        # Animations
        for a in anims:
            f.write(struct.pack('<iiii',
                                bo[a['name_buf']], a['interp'],
                                bo[a['ts_buf']], bo[a['xf_buf']]))

        # Joints
        for j in joints:
            f.write(struct.pack('<ii', bo[j['name_buf']], j['parent']))
            f.write(struct.pack('<16f', *j['inv_bind']))
            f.write(struct.pack('<3f', *j['t']))
            f.write(struct.pack('<4f', *j['r']))
            f.write(struct.pack('<3f', *j['s']))


# ---- Entry point ----

def main():
    try:
        args = sys.argv[sys.argv.index('--') + 1:]
    except ValueError:
        print(f"args: {sys.argv}")
        fatal("Usage: blender --background --python convert_mesh.py "
              "-- <input> <output.trm>")
    if len(args) < 2:
        fatal("Expected at least 2 arguments: input_path output_path "
              "[--exclude name ... | --include name ...] [--static]")

    inp, out = os.path.abspath(args[0]), os.path.abspath(args[1])
    excludes = set()
    includes = set()
    static = False
    i = 2
    while i < len(args):
        if args[i] == '--exclude' and i + 1 < len(args):
            excludes.add(args[i + 1])
            i += 2
        elif args[i] == '--include' and i + 1 < len(args):
            includes.add(args[i + 1])
            i += 2
        elif args[i] == '--static':
            static = True
            i += 1
        else:
            fatal(f"Unknown argument: {args[i]}")
            i += 1
    if excludes and includes:
        fatal("--include and --exclude cannot be used together")
    if not os.path.isfile(inp):
        fatal(f"Input not found: {inp}")
    if not out.lower().endswith('.trm'):
        fatal("Output must have .trm extension")

    bpy.ops.wm.read_homefile(use_empty=True)
    # Ensure scene is truly empty — some Blender versions/configs
    # don't respect use_empty=True, leaving default objects behind.
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)

    if os.path.splitext(inp)[1].lower() == '.blend':
        # open_mainfile preserves the source file's saved depsgraph state, and in
        # Blender 5.x that state can be "stuck" — frame_set stops re-evaluating
        # the action, so every sampled frame returns the same pose. Appending
        # into the fresh empty scene rebuilds the depsgraph from scratch.
        with bpy.data.libraries.load(os.path.abspath(inp), link=False) as (src, dst):
            dst.objects = list(src.objects)
            dst.actions = list(src.actions)
            dst.scenes  = list(src.scenes)
        for obj in dst.objects:
            if obj is not None:
                bpy.context.scene.collection.objects.link(obj)
        # term_anim_order is stored on the source scene; copy it forward so
        # extract_anims can use it.
        for src_scene in (dst.scenes or []):
            if src_scene is not None and "term_anim_order" in src_scene:
                bpy.context.scene["term_anim_order"] = list(src_scene["term_anim_order"])
                break
    else:
        do_import(inp)

    mesh_objs, arm_obj = find_objects()
    if static:
        arm_obj = None

    if excludes:
        before = len(mesh_objs)
        mesh_objs = [o for o in mesh_objs if o.name not in excludes]
        skipped = before - len(mesh_objs)
        if skipped:
            print(f"  Excluded {skipped} object(s): {excludes}")
    elif includes:
        before = len(mesh_objs)
        mesh_objs = [o for o in mesh_objs if o.name in includes]
        missing = includes - {o.name for o in mesh_objs}
        if missing:
            print(f"  WARNING: --include names not found in scene: {missing}")
        print(f"  Included {len(mesh_objs)} of {before} object(s): {includes}")

    print(f"  Found {len(mesh_objs)} mesh objects:")
    for i, o in enumerate(mesh_objs):
        me = o.data
        loc = o.matrix_world.translation
        n_mats = len(me.materials) if me else 0
        n_verts = len(me.vertices) if me else 0
        n_polys = len(me.polygons) if me else 0
        mat_names = [m.name if m else "(None)" for m in me.materials] if me else []
        print(f"    [{i}] \"{o.name}\"  verts={n_verts}  polys={n_polys}  "
              f"mats={n_mats} {mat_names}  "
              f"pos=({loc.x:.3f}, {loc.y:.3f}, {loc.z:.3f})  "
              f"hide_viewport={o.hide_viewport}  hide_render={o.hide_render}")

    bufs = Bufs()
    bufs.string(inp)  # buffer 0 is always the origin file path

    sections = []
    for mesh_obj in mesh_objs:
        sections.extend(extract_sections(mesh_obj, arm_obj, bufs))
    if not sections:
        fatal("No geometry found")
    joints = [] if static else extract_joints(arm_obj, bufs)
    anims = [] if static else extract_anims(arm_obj, bufs)
    write_trm(out, sections, joints, anims, bufs)

    print(f"OK: {len(sections)} sections, {len(joints)} joints, "
          f"{len(anims)} animations -> {out}")



if __name__ == '__main__':
    main()


# ------------------------------------------

# instructions for claude codegen / format documentation
# how to create this script:

# use the blender python api and the other above libraries if needed
# use 'numpy' for fast pixel data work and 'struct' for fast file writing.
# use others as needed

# read module.jai in this folder to understand what format the data will be loaded into.
# read further here to understand the exact data that will go into the file, and its layout.

# this script will be used to export only a single mesh.
# it will be used in the command line with blender, headless.
# there are two cli parameters: input file path, output file path
# the input file can be any acceptable blender mesh import type
# the output file must have the extension 'trm'

# variably sized data (strings, vertex buffer, index buffer, image/texture buffer) each go into
# a single buffer, always starting at a 4 byte alignment. alignment padding must always be 0.
# things point to these buffers via offsets, which are 4 byte ints describing an offset from
# the beginning of the file, which must itself be aligned to 4 bytes.

# ------------------------------------------

# a buffer is laid out like this (binary, no whitespace):

# type (4 byte int, 0=bytes, 1=u16s, 2=u32s, 3=floats, 4=static vertices, 5=skinned vertices, 6=joint transform)
# count
# size of one data item in bytes
# data item 1
# data item 2
# ...

# all texture buffers must be stored as r8g8b8a8 png-encoded data.
# count is the size of the png data in bytes.

# a static mesh vertex buffer with 2 vertices will look like this (imagine the binary floats/ints instead of the text):

# 4
# 2
# position 0 x, y, z
# normal   0 x, y, z
# tangent  0 x, y, z, w
# uv0      0 u, v
# uv1      0 u, v
# color    0 r, g, b, a (1.0, 1.0, 1.0, 1.0 if not specified)
# position 1 x, y, z
# normal   1 x, y, z
# tangent  1 x, y, z, w
# uv0      1 u, v
# uv1      1 u, v
# color    1 r, g, b, a (1.0, 1.0, 1.0, 1.0 if not specified)

# a skinned mesh vertex looks like this
# position x, y, z
# normal   x, y, z
# tangent  x, y, z, w
# uv0      u, v
# uv1      u, v
# color    r, g, b, a
# 4 joints (u16's)
# 4 weights (floats)

# joint transform looks like this:
# translation x, y, z
# rotation x, y, z, w
# scale x, y, z

# all rotations must be converted to these axes:
# x right, y forward, z up

# ------------------------------------------

# if the file has lights or non-mesh things, ignore those. export with the first mesh found.
# error if no mesh. in general, report errors and sys.exit(1) when the data is invalid.

# all integers (except index buffer data) should be signed 4 byte values. this includes enums in the
# 'module.jai' structs.

# ------------------------------------------
# the file format will look like this (without newlines/readability whitespace):

# TeRM-Mesh (padded with zeroes so that the header takes 16 bytes)
# version (right now, 1)

# number of mesh sections
# size of one mesh section in file
# offset to mesh section 0 (from head of file)

# number of animations
# size of one animation in file
# offset to animation 0 (from head of file)

# number of joints
# size of one joint in file
# offset to joint 0 (from head of file)

# buffer 0 data (always the origin file path)
# buffer 1 data
# ...

# mesh section 0
# mesh section 1
# ...

# animation 0
# animation 1
# ...

# joint 0: offset to buffer for name
# joint 0: parent joint index     (1 int) (-1 since joint 0 is root) 
# joint 0: mat4 inverse bind pose (16 floats)
# joint 0: local rest translation (3 floats)
# joint 0: local rest rotation    (4 floats)
# joint 0: local rest scale       (3 floats)
# joint 1: offset to buffer for name
# joint 1: parent joint index
# joint 1: mat4 inverse bind pose (16 floats)
# joint 1: local rest translation (3 floats)
# joint 1: local rest rotation    (4 floats)
# joint 1: local rest scale       (3 floats)
# ...

# ------------------------------------------

# a 'mesh section' looks like this:

# offset to buffer data for name
# offset to buffer data for indices
# offset to buffer data for vertices
# offset to buffer data for material name
# alpha mode (0=opaque, 1=mask, 2=blend)
# which uv on vertex to use for albedo    (0 or 1)
# which uv on vertex to use for metallic  (0 or 1)
# which uv on vertex to use for roughness (0 or 1)
# which uv on vertex to use for normal    (0 or 1)
# which uv on vertex to use for occlusion (0 or 1)
# which uv on vertex to use for emissive  (0 or 1)
# alpha cutoff for fragment discard if alpha=masked else 0.0
# albedo factor (4 floats: rgba)
    # if specified, use the specified value. if alpha not specified, make alpha 1.
    # else if albedo texture, white
    # else magenta.
# metallic factor (1 float)
    # if specified, use specified value
    # else if orm texture, 1.0
    # else 0.0
# roughness factor (1 float)
    # if specified, use specified value
    # else if orm texture, 1.0
    # else 0.5
# emissive factor (4 floats: rgba)
    # if specified, use the specified value. if alpha not specified, make alpha 1.
    # else if emissive texture, 1.0
    # else 0.0
# albedo texture buffer offset, or -1 if no albedo texture
# albedo texture mag filter (0=linear, 1=nearest)
# albedo texture min filter
# albedo texture horizontal wrap (0=clamp to edge, 1=mirrored repeat, 2=repeat)
# albedo texture vertical wrap
# normal texture buffer offset, or -1 if no normal texture
# normal texture mag filter
# normal texture min filter
# normal texture horizontal wrap
# normal texture vertical wrap
# emissive texture buffer offset, or -1 if no emissive texture
# emissive texture mag filter
# emissive texture min filter
# emissive texture horizontal wrap
# emissive texture vertical wrap
# orm texture buffer offset, or -1 if no orm texture
# orm texture mag filter
# orm texture min filter
# orm texture horizontal wrap
# orm texture vertical wrap

# if the input mesh does not have an ORM texture, but does have an occlusion and/or roughness and/or metallic,
# said textures should be merged into a single texture with occlusion in r, roughness in g and metallic in b.
# any missing textures should have a channel of all zeroes.

# ------------------------------------------

# an 'animation' looks like this:

# offset to buffer for name of this animation
# whether the animation wants interpolation (0 or 1, 4 byte int)
# offset to buffer of timestamps for each transform
# offset to buffer of joint transforms, one transform per joint per timestamp

# ------------------------------------------
