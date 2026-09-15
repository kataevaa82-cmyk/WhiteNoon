"""Generate the remaining lightweight Blender environment props for White Noon.

Run inside the project's connected Blender instance.  Each asset is exported as a
single multi-material mesh so repeated props stay cheap to instance in Godot.
"""

import bpy
import math
import os
import random
from mathutils import Vector


ROOT = r"C:\whitenoon"
MODEL_DIR = os.path.join(ROOT, "models")
BUILD_DIR = os.path.join(ROOT, "build")
RNG = random.Random(260821)
RESULTS = []


def reset_scene():
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def material(name, color, roughness=0.9, metallic=0.0):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1.0)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (*color, 1.0)
        bsdf.inputs["Roughness"].default_value = roughness
        bsdf.inputs["Metallic"].default_value = metallic
    return mat


def finish_object(obj, bevel=0.0):
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel > 0.0:
        mod = obj.modifiers.new("hand worn edges", "BEVEL")
        mod.width = bevel
        mod.segments = 1
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return obj


def cube(name, location, dimensions, mat, rotation=(0.0, 0.0, 0.0), bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    obj.data.materials.append(mat)
    return finish_object(obj, bevel)


def cylinder(name, location, radius, depth, mat, vertices=10, rotation=(0.0, 0.0, 0.0), bevel=0.0):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(mat)
    return finish_object(obj, bevel)


def cone(name, location, radius_bottom, radius_top, depth, mat, vertices=10, rotation=(0.0, 0.0, 0.0), bevel=0.0):
    bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=radius_bottom, radius2=radius_top, depth=depth, location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(mat)
    return finish_object(obj, bevel)


def ico(name, location, scale, mat, subdivisions=1, rotation=(0.0, 0.0, 0.0)):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdivisions, radius=1.0, location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    obj.data.materials.append(mat)
    return finish_object(obj)


def torus(name, location, major, minor, mat, major_segments=16, minor_segments=5, rotation=(0.0, 0.0, 0.0)):
    bpy.ops.mesh.primitive_torus_add(
        major_radius=major,
        minor_radius=minor,
        major_segments=major_segments,
        minor_segments=minor_segments,
        location=location,
        rotation=rotation,
    )
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(mat)
    return finish_object(obj)


def rod_between(name, start, end, radius, mat, vertices=7):
    start = Vector(start)
    end = Vector(end)
    direction = end - start
    obj = cylinder(name, (start + end) * 0.5, radius, direction.length, mat, vertices)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0.0, 0.0, 1.0)).rotation_difference(direction.normalized())
    return obj


def join_export(asset_name):
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for obj in meshes:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.join()
    asset = bpy.context.object
    asset.name = asset_name
    bpy.context.scene.cursor.location = (0.0, 0.0, 0.0)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    asset["white_noon_asset"] = asset_name

    glb_path = os.path.join(MODEL_DIR, f"{asset_name}.glb")
    blend_path = os.path.join(BUILD_DIR, f"{asset_name}_refined.blend")
    bpy.ops.object.select_all(action="DESELECT")
    asset.select_set(True)
    bpy.context.view_layer.objects.active = asset
    bpy.ops.export_scene.gltf(filepath=glb_path, export_format="GLB", use_selection=True, export_apply=True)
    bpy.ops.wm.save_as_mainfile(filepath=blend_path)
    triangles = sum(max(0, len(poly.vertices) - 2) for poly in asset.data.polygons)
    RESULTS.append({
        "asset": asset_name,
        "triangles": triangles,
        "bytes": os.path.getsize(glb_path),
        "dimensions": [round(value, 3) for value in asset.dimensions],
    })
    return asset


def build_burnt_stump():
    reset_scene()
    char = material("charred birch bark", (0.055, 0.045, 0.043))
    bark = material("smoke grey bark", (0.18, 0.16, 0.145))
    heart = material("exposed burnt heartwood", (0.30, 0.18, 0.09))
    lichen = material("dry ochre lichen", (0.40, 0.34, 0.12))

    cone("irregular charred trunk", (0, 0, 0.60), 0.56, 0.43, 1.20, char, 11, rotation=(0.03, -0.04, 0.02), bevel=0.025)
    cylinder("broken top", (0, 0, 1.195), 0.42, 0.05, heart, 11)
    for index, angle in enumerate((0.2, 1.55, 2.8, 4.25, 5.35)):
        root = Vector((math.cos(angle) * 0.43, math.sin(angle) * 0.43, 0.16))
        tip = Vector((math.cos(angle) * 0.88, math.sin(angle) * 0.88, 0.04))
        rod_between(f"black root {index}", root, tip, 0.12, char, 6)
    for index, angle in enumerate((0.55, 2.2, 3.7, 5.1)):
        loc = (math.cos(angle) * 0.49, math.sin(angle) * 0.49, 0.58 + 0.12 * (index % 2))
        strip = cube(f"split bark {index}", loc, (0.12, 0.055, 0.66), bark, rotation=(0.0, 0.10 * (-1 if index % 2 else 1), angle), bevel=0.015)
        strip.rotation_euler.z = angle
    for index, (x, y, height) in enumerate(((-0.20, 0.02, 0.52), (0.08, 0.10, 0.64), (0.24, -0.06, 0.43))):
        cone(f"splinter {index}", (x, y, 1.17 + height * 0.5), 0.085, 0.014, height, heart, 5, rotation=(0.08 * index, -0.10 + 0.08 * index, 0.0))
    for index, angle in enumerate((0.7, 2.9, 4.9)):
        ico(f"lichen patch {index}", (math.cos(angle) * 0.52, math.sin(angle) * 0.52, 0.48 + index * 0.17), (0.12, 0.035, 0.08), lichen, 1, rotation=(0, 0, angle))
    return join_export("burnt_stump")


def build_straw_doll():
    reset_scene()
    pole = material("weathered birch rods", (0.20, 0.145, 0.09))
    straw = material("sun dried rye straw", (0.61, 0.47, 0.18))
    straw_light = material("fresh straw highlights", (0.79, 0.64, 0.27))
    cord = material("madder red binding", (0.36, 0.035, 0.028))
    dark = material("stitched face", (0.055, 0.035, 0.028))
    flower = material("faded solstice flowers", (0.76, 0.70, 0.39))

    cylinder("buried support", (0, 0.04, 1.22), 0.065, 2.44, pole, 7, rotation=(0.015, 0.02, 0))
    rod_between("cross branch", (-0.86, 0, 1.72), (0.86, 0.03, 1.76), 0.055, pole, 7)
    cone("bound torso", (0, 0, 1.48), 0.31, 0.24, 0.80, straw, 10, rotation=(0.03, 0.0, -0.02))
    cone("ritual straw skirt", (0, 0, 0.85), 0.54, 0.25, 0.82, straw, 12)
    ico("linen wrapped head", (0, -0.015, 2.10), (0.27, 0.235, 0.33), straw_light, 2, rotation=(0.04, 0.05, -0.04))
    for side in (-1, 1):
        rod_between(f"straw arm {side}", (side * 0.24, -0.01, 1.70), (side * 0.82, 0.01, 1.75), 0.13, straw, 8)
        torus(f"wrist binding {side}", (side * 0.73, 0.01, 1.745), 0.125, 0.022, cord, 10, 4, rotation=(0, math.pi / 2, 0))
    torus("waist binding", (0, 0, 1.22), 0.275, 0.027, cord, 14, 4)
    torus("flower crown wicker", (0, -0.005, 2.31), 0.255, 0.025, pole, 14, 4)
    for index, angle in enumerate((0.25, 1.2, 2.35, 3.45, 4.65, 5.55)):
        ico(f"crown bloom {index}", (math.cos(angle) * 0.255, math.sin(angle) * 0.23, 2.31), (0.055, 0.035, 0.055), flower, 1)
    cube("stitched eye left", (-0.085, -0.222, 2.15), (0.075, 0.018, 0.022), dark, rotation=(0, 0, 0.2), bevel=0.006)
    cube("stitched eye right", (0.085, -0.222, 2.15), (0.075, 0.018, 0.022), dark, rotation=(0, 0, -0.2), bevel=0.006)
    cube("stitched mouth", (0, -0.235, 2.02), (0.15, 0.018, 0.018), dark, bevel=0.005)
    for index in range(12):
        angle = index * math.tau / 12 + RNG.uniform(-0.10, 0.10)
        radius = RNG.uniform(0.31, 0.47)
        start = (math.cos(angle) * radius, math.sin(angle) * radius, 0.48)
        end = (math.cos(angle) * (radius + RNG.uniform(-0.05, 0.08)), math.sin(angle) * radius, RNG.uniform(0.16, 0.32))
        rod_between(f"loose skirt straw {index}", start, end, 0.012, straw_light, 5)
    return join_export("straw_doll")


def build_millstone():
    reset_scene()
    granite = material("weathered mill granite", (0.34, 0.33, 0.30))
    edge = material("pale chipped stone", (0.47, 0.45, 0.40))
    crack = material("deep stone fissures", (0.035, 0.03, 0.028))
    wood = material("broken oak spindle", (0.20, 0.12, 0.065))
    moss = material("dry mill moss", (0.25, 0.29, 0.10))

    # A proper annular mill stone: the central eye is real geometry, not a painted cylinder.
    segments = 32
    outer = 3.75
    inner = 0.48
    bottom = 0.10
    top = 0.88
    verts = []
    for z in (bottom, top):
        for radius in (outer, inner):
            for index in range(segments):
                angle = index * math.tau / segments
                wobble = 1.0 + (0.018 * math.sin(index * 2.3) if radius == outer else 0.0)
                verts.append((math.cos(angle) * radius * wobble, math.sin(angle) * radius * wobble, z))
    faces = []
    ob, ib, ot, it = 0, segments, segments * 2, segments * 3
    for index in range(segments):
        nxt = (index + 1) % segments
        faces.extend([
            (ot + index, ot + nxt, it + nxt, it + index),
            (ob + nxt, ob + index, ib + index, ib + nxt),
            (ob + index, ob + nxt, ot + nxt, ot + index),
            (ib + nxt, ib + index, it + index, it + nxt),
        ])
    mesh = bpy.data.meshes.new("annular millstone mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    body = bpy.data.objects.new("true holed millstone", mesh)
    bpy.context.collection.objects.link(body)
    body.data.materials.append(granite)
    finish_object(body, 0.045)
    for index in range(12):
        angle = index * math.tau / 12 + 0.08
        start = Vector((math.cos(angle) * 0.62, math.sin(angle) * 0.62, 0.905))
        end = Vector((math.cos(angle + 0.22) * 3.40, math.sin(angle + 0.22) * 3.40, 0.905))
        rod_between(f"grinding furrow {index}", start, end, 0.035, crack, 5)
    for index, angle in enumerate((0.1, 0.22, 0.37)):
        start = (math.cos(angle) * (0.45 + index * 0.55), math.sin(angle) * (0.45 + index * 0.55), 0.93)
        end = (math.cos(angle + 0.18) * (1.15 + index * 0.75), math.sin(angle + 0.18) * (1.15 + index * 0.75), 0.93)
        rod_between(f"broken fissure {index}", start, end, 0.085 - index * 0.012, crack, 5)
    cone("splintered spindle", (0, 0, 1.23), 0.31, 0.24, 0.72, wood, 8, rotation=(0.04, -0.05, 0.06))
    for index, angle in enumerate((1.1, 2.7, 4.4, 5.5)):
        ico(f"chipped rim {index}", (math.cos(angle) * 3.68, math.sin(angle) * 3.68, 0.52), (0.25, 0.12, 0.18), edge, 1, rotation=(0, 0, angle))
    for index, angle in enumerate((0.8, 3.2, 5.0)):
        ico(f"moss stain {index}", (math.cos(angle) * 2.7, math.sin(angle) * 2.7, 0.92), (0.42, 0.20, 0.035), moss, 1, rotation=(0, 0, angle))
    return join_export("millstone")


def build_kurgan():
    reset_scene()
    turf = material("summer burial turf", (0.31, 0.34, 0.14))
    earth = material("exposed grave soil", (0.18, 0.12, 0.075))
    stone = material("burial entrance stone", (0.36, 0.35, 0.32))
    flower = material("small grave flowers", (0.69, 0.62, 0.30))

    segments = 20
    rings = ((0.0, 1.0), (0.18, 0.98), (0.44, 0.88), (0.68, 0.65), (0.88, 0.35))
    verts = []
    for ring_index, (height, radius) in enumerate(rings):
        for index in range(segments):
            angle = index * math.tau / segments
            jitter = 1.0 + 0.045 * math.sin(index * 2.7 + ring_index * 1.4)
            verts.append((math.cos(angle) * radius * jitter, math.sin(angle) * radius * jitter, height))
    top_index = len(verts)
    verts.append((0.08, -0.05, 1.0))
    faces = []
    for ring_index in range(len(rings) - 1):
        start = ring_index * segments
        next_start = (ring_index + 1) * segments
        for index in range(segments):
            nxt = (index + 1) % segments
            faces.append((start + index, start + nxt, next_start + nxt, next_start + index))
    last = (len(rings) - 1) * segments
    for index in range(segments):
        faces.append((last + index, last + (index + 1) % segments, top_index))
    mesh = bpy.data.meshes.new("irregular turf mound")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    mound = bpy.data.objects.new("hand raised kurgan", mesh)
    bpy.context.collection.objects.link(mound)
    mound.data.materials.append(turf)
    finish_object(mound)
    ico("dark entrance", (0, -0.91, 0.28), (0.33, 0.10, 0.32), earth, 1)
    cube("entrance stone left", (-0.34, -0.86, 0.30), (0.18, 0.26, 0.60), stone, rotation=(0.03, -0.10, -0.06), bevel=0.035)
    cube("entrance stone right", (0.34, -0.86, 0.30), (0.18, 0.26, 0.60), stone, rotation=(-0.02, 0.08, 0.07), bevel=0.035)
    cube("entrance lintel", (0, -0.86, 0.59), (0.84, 0.28, 0.17), stone, rotation=(0.02, 0, -0.03), bevel=0.035)
    for index, angle in enumerate((0.3, 1.35, 2.5, 3.8, 5.0)):
        ico(f"grave flower {index}", (math.cos(angle) * 0.72, math.sin(angle) * 0.72, 0.62 + 0.08 * math.sin(angle)), (0.035, 0.035, 0.055), flower, 1)
    return join_export("kurgan")


def build_silent_tower():
    reset_scene()
    stone = material("sun bleached tower stone", (0.42, 0.39, 0.34))
    dark_stone = material("weathered tower seams", (0.23, 0.22, 0.20))
    roof = material("tarred shingle roof", (0.105, 0.075, 0.06))
    door = material("sealed oak doorway", (0.18, 0.105, 0.055))
    void = material("lightless openings", (0.012, 0.010, 0.014))
    ochre = material("faded sun sign", (0.62, 0.30, 0.055))

    cone("lower taper", (0, 0, 1.75), 2.30, 2.12, 3.50, stone, 10, bevel=0.045)
    cone("middle taper", (0, 0, 5.15), 2.08, 1.87, 3.30, stone, 10, rotation=(0, 0, 0.04), bevel=0.04)
    cone("upper taper", (0, 0, 8.28), 1.84, 1.64, 2.95, stone, 10, rotation=(0, 0, -0.035), bevel=0.035)
    for z, radius in ((3.48, 2.18), (6.78, 1.94), (9.72, 1.73)):
        cylinder(f"stone course {z}", (0, 0, z), radius, 0.17, dark_stone, 10, bevel=0.025)
    cylinder("wide roof eave", (0, 0, 9.94), 2.10, 0.20, roof, 10, rotation=(0, 0, 0.03), bevel=0.025)
    cone("closed steep roof", (0, 0, 11.28), 2.08, 0.08, 2.55, roof, 10, rotation=(0, 0, 0.03))
    cube("door shadow", (0, -2.20, 1.18), (1.30, 0.08, 2.25), void, bevel=0.05)
    for index in range(5):
        x = -0.48 + index * 0.24
        cube(f"door board {index}", (x, -2.25, 1.12), (0.20, 0.12, 2.05), door, rotation=(0, 0, RNG.uniform(-0.025, 0.025)), bevel=0.025)
    cube("door cross brace", (0, -2.33, 1.18), (1.12, 0.10, 0.15), door, rotation=(0, 0, -0.11), bevel=0.02)
    for index, (x, y, z, rz) in enumerate(((0, -1.91, 5.30, 0), (1.75, 0, 7.98, math.pi / 2), (-1.68, 0, 8.76, math.pi / 2))):
        cube(f"narrow window {index}", (x, y, z), (0.42 if abs(y) > 0 else 0.08, 0.08 if abs(y) > 0 else 0.42, 1.10), void, rotation=(0, 0, rz), bevel=0.03)
    torus("sun wheel", (0, -1.73, 8.88), 0.50, 0.055, ochre, 18, 5, rotation=(math.pi / 2, 0, 0))
    for index in range(8):
        angle = index * math.tau / 8
        rod_between(f"sun ray {index}", (math.cos(angle) * 0.15, -1.74, 8.88 + math.sin(angle) * 0.15), (math.cos(angle) * 0.72, -1.74, 8.88 + math.sin(angle) * 0.72), 0.034, ochre, 5)
    return join_export("silent_tower")


def build_sun_trap():
    reset_scene()
    rope = material("sun trap hemp", (0.55, 0.39, 0.16))
    wood = material("sun trap pegs", (0.19, 0.115, 0.06))
    chalk = material("sun trap chalk", (0.69, 0.64, 0.48))
    cloth = material("sun trap red knots", (0.48, 0.035, 0.028))

    torus("outer woven snare", (0, 0, 0.075), 1.55, 0.055, rope, 24, 5)
    torus("inner sun ring", (0, 0, 0.07), 0.58, 0.038, chalk, 18, 4)
    cylinder("central sun seal", (0, 0, 0.055), 0.22, 0.08, chalk, 12, bevel=0.02)
    for index in range(8):
        angle = index * math.tau / 8
        start = (math.cos(angle) * 0.22, math.sin(angle) * 0.22, 0.09)
        end = (math.cos(angle) * 1.47, math.sin(angle) * 1.47, 0.09)
        rod_between(f"woven sun ray {index}", start, end, 0.028, rope, 5)
        peg = cone(
            f"anchoring peg {index}",
            (math.cos(angle) * 1.68, math.sin(angle) * 1.68, 0.18),
            0.095,
            0.045,
            0.36,
            wood,
            6,
            rotation=(0.08 * math.sin(angle), -0.08 * math.cos(angle), angle),
        )
        if index % 2 == 0:
            torus(
                f"red binding knot {index}",
                (math.cos(angle) * 1.56, math.sin(angle) * 1.56, 0.10),
                0.085,
                0.018,
                cloth,
                8,
                4,
                rotation=(0, math.pi / 2, angle),
            )
    return join_export("sun_trap")


def build_cursed_effigy():
    reset_scene()
    birch = material("blackened birch bones", (0.095, 0.072, 0.060))
    straw = material("ritual rye bundle", (0.54, 0.39, 0.13))
    cloth = material("madder and violet bindings", (0.34, 0.018, 0.15))
    bone = material("chalk ritual mask", (0.70, 0.66, 0.56))
    mark = material("tar painted marks", (0.025, 0.015, 0.018))
    stone = material("effigy footing stones", (0.30, 0.29, 0.27))

    cylinder("buried black stake", (0, 0, 1.38), 0.085, 2.76, birch, 8, rotation=(0.02, -0.025, 0))
    torus("woven ritual sun", (0, 0, 1.76), 0.67, 0.055, birch, 20, 5, rotation=(math.pi / 2, 0, 0))
    for index in range(8):
        angle = index * math.tau / 8
        rod_between(f"woven sun spoke {index}", (0, 0, 1.76), (math.cos(angle) * 0.62, 0, 1.76 + math.sin(angle) * 0.62), 0.034, birch, 6)
    cone("bound body", (0, -0.03, 1.45), 0.25, 0.19, 0.70, straw, 9, rotation=(0.04, 0.01, -0.03))
    rod_between("crooked arm left", (-0.16, 0, 1.60), (-0.76, 0.02, 1.94), 0.065, birch, 7)
    rod_between("crooked arm right", (0.16, 0, 1.60), (0.73, -0.01, 1.88), 0.065, birch, 7)
    ico("faceless chalk mask", (0, -0.075, 2.28), (0.22, 0.13, 0.29), bone, 2, rotation=(0.02, 0.03, -0.05))
    cube("mask eye left", (-0.075, -0.195, 2.33), (0.065, 0.018, 0.025), mark, rotation=(0, 0, 0.25), bevel=0.005)
    cube("mask eye right", (0.075, -0.195, 2.33), (0.065, 0.018, 0.025), mark, rotation=(0, 0, -0.25), bevel=0.005)
    cube("mask vertical sign", (0, -0.205, 2.22), (0.024, 0.018, 0.18), mark, bevel=0.004)
    torus("waist curse binding", (0, -0.03, 1.26), 0.23, 0.027, cloth, 12, 4)
    for index, x in enumerate((-0.17, 0.13)):
        ribbon = cube(f"hanging curse ribbon {index}", (x, -0.10, 0.82), (0.08, 0.025, 0.88 - index * 0.14), cloth, rotation=(0.04, 0.06 * (-1 if index else 1), 0.08 * (-1 if index else 1)), bevel=0.01)
        ribbon.rotation_euler.z += 0.04 * index
    for index, angle in enumerate((0.4, 2.4, 4.5)):
        ico(f"footing stone {index}", (math.cos(angle) * 0.34, math.sin(angle) * 0.25, 0.12), (0.32, 0.24, 0.17), stone, 1, rotation=(0, 0, angle))
    return join_export("cursed_effigy")


def add_presentation(asset):
    bpy.ops.object.camera_add(location=(4.8, -7.2, 3.7))
    camera = bpy.context.object
    camera.name = "Presentation Camera"
    target = Vector((0.0, 0.0, 1.35))
    camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera.data.lens = 58
    bpy.context.scene.camera = camera
    for name, location, energy, color, size in (
        ("Warm Key", (-3.5, -4.5, 5.5), 900, (1.0, 0.67, 0.42), 3.0),
        ("Cool Fill", (4.0, -1.0, 3.5), 650, (0.45, 0.62, 1.0), 3.0),
        ("Sun Rim", (0.0, 4.0, 5.0), 1100, (1.0, 0.32, 0.18), 2.5),
    ):
        bpy.ops.object.light_add(type="AREA", location=location)
        light = bpy.context.object
        light.name = name
        light.data.energy = energy
        light.data.color = color
        light.data.shape = "DISK"
        light.data.size = size
        light.rotation_euler = (target - light.location).to_track_quat("-Z", "Y").to_euler()
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 900
    scene.render.resolution_y = 900
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = os.path.join(BUILD_DIR, "cursed_effigy_preview.png")
    scene.world.color = (0.025, 0.018, 0.032)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(BUILD_DIR, "cursed_effigy_refined.blend"))
    bpy.ops.render.render(write_still=True)
    bpy.ops.object.select_all(action="DESELECT")
    asset.select_set(True)
    bpy.context.view_layer.objects.active = asset


os.makedirs(MODEL_DIR, exist_ok=True)
os.makedirs(BUILD_DIR, exist_ok=True)
build_burnt_stump()
build_straw_doll()
build_millstone()
build_kurgan()
build_silent_tower()
build_sun_trap()
last_asset = build_cursed_effigy()
add_presentation(last_asset)

result = RESULTS
