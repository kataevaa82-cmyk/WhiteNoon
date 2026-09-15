import bpy
import math
import os
import random
from mathutils import Vector


def midpoint(a, b):
    return (Vector(a) + Vector(b)) * 0.5


def distance(a, b):
    return (Vector(b) - Vector(a)).length


def limb_euler(direction):
    """Поворот (rx, ry, 0), после которого локальная ось Z цилиндра/конуса
    смотрит вдоль direction. Раньше углы для рук подбирались вручную под
    конкретные координаты локтя и запястья — стоило их сдвинуть, и подбор
    начинался заново. Теперь любая точка сама тянет за собой правильный
    поворот кости."""
    n = -Vector(direction).normalized()
    ry = math.atan2(n.x, n.z)
    rx = math.atan2(-n.y, math.hypot(n.x, n.z))
    return (rx, ry, 0.0)


ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'models')
os.makedirs(OUT, exist_ok=True)

# Общий множитель разрешения оболочек. Пропорции, подобранные для каждой
# детали вручную, сохраняются: множитель поднимает их все разом.
DETAIL = 1.6


def ring_count(count, minimum=6):
    """Число сегментов по окружности после подъёма детализации."""
    return max(minimum, int(round(count * DETAIL)))


def clear():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for block in bpy.data.materials:
        bpy.data.materials.remove(block)


def material(name, color, roughness=0.82, metallic=0.0, emission=None):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1.0)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = (*color, 1.0)
    bsdf.inputs['Roughness'].default_value = roughness
    bsdf.inputs['Metallic'].default_value = metallic
    if emission:
        bsdf.inputs['Emission Color'].default_value = (*emission, 1.0)
        bsdf.inputs['Emission Strength'].default_value = 1.8
    return mat


def finish(obj, name, mat=None):
    obj.name = name
    if mat:
        obj.data.materials.append(mat)
    for poly in obj.data.polygons:
        poly.use_smooth = False
    return obj


def weather_rock(obj, phase=0.0, ridges=5, strength=0.17):
    """Разбивает ровный конус на рёбра и распадки. Сдвиг только радиальный и
    только по углу: снежная шапка строится по радиусу конуса на своей высоте,
    и при вертикальном смещении она бы с него съехала."""
    for vertex in obj.data.vertices:
        radius = math.hypot(vertex.co.x, vertex.co.y)
        if radius < 1e-5:
            continue
        angle = math.atan2(vertex.co.y, vertex.co.x)
        factor = 1.0 + strength * (
            math.sin(angle * ridges + phase)
            + 0.45 * math.sin(angle * (ridges * 2 + 1) - phase * 1.7)
            + 0.25 * math.sin(angle * (ridges * 3 + 2) + phase * 0.6))
        vertex.co.x *= factor
        vertex.co.y *= factor
    return obj


def shade_barrel(obj, smooth=True):
    """Гладкая боковая поверхность у точёных деталей и плоские торцы.
    Кольца стали вдвое чаще, и без этого они читались бы как гранёный столб,
    а не как круглое бревно. Крышки узнаём по нормали вдоль оси объекта."""
    for poly in obj.data.polygons:
        poly.use_smooth = smooth and abs(poly.normal.z) < 0.99
    return obj


def apply_scale(obj, scale):
    """Немундирный масштаб после создания: без него сфера/цилиндр остаются
    круглыми в локальных осях и наклонённые копии (вроде яйцевидной головы)
    расползаются при экспорте."""
    obj.scale = scale
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return obj


def cube(name, loc, scale, mat, rotation=(0, 0, 0), bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(location=loc, rotation=rotation)
    obj = finish(bpy.context.object, name, mat)
    obj.scale = (scale[0] / 2, scale[1] / 2, scale[2] / 2)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        mod = obj.modifiers.new('Soft edges', 'BEVEL')
        mod.width = bevel
        mod.segments = 3
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return obj


def cylinder(name, loc, radius, depth, mat, vertices=16, rotation=(0, 0, 0), smooth=True):
    bpy.ops.mesh.primitive_cylinder_add(vertices=ring_count(vertices), radius=radius, depth=depth, location=loc, rotation=rotation)
    return shade_barrel(finish(bpy.context.object, name, mat), smooth)


def cone(name, loc, r1, r2, depth, mat, vertices=16, rotation=(0, 0, 0), smooth=True):
    bpy.ops.mesh.primitive_cone_add(vertices=ring_count(vertices), radius1=r1, radius2=r2, depth=depth, location=loc, rotation=rotation)
    return shade_barrel(finish(bpy.context.object, name, mat), smooth)


def sphere(name, loc, radius, mat, segments=18, rings=10):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=ring_count(segments), ring_count=ring_count(rings, 4), radius=radius, location=loc)
    obj = finish(bpy.context.object, name, mat)
    for poly in obj.data.polygons:
        poly.use_smooth = True
    return obj


def torus(name, loc, major, minor, mat, rotation=(0, 0, 0)):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor,
                                     major_segments=ring_count(24), minor_segments=ring_count(8),
                                     location=loc, rotation=rotation)
    obj = finish(bpy.context.object, name, mat)
    for poly in obj.data.polygons:
        poly.use_smooth = True
    return obj


def detail_torus(name, loc, major, minor, mat, rotation=(0, 0, 0),
                 major_segments=20, minor_segments=6):
    """Lightweight torus for small bindings and jewellery."""
    bpy.ops.mesh.primitive_torus_add(
        major_radius=major,
        minor_radius=minor,
        major_segments=major_segments,
        minor_segments=minor_segments,
        location=loc,
        rotation=rotation,
    )
    obj = finish(bpy.context.object, name, mat)
    for poly in obj.data.polygons:
        poly.use_smooth = True
    return obj


def custom_mesh(name, vertices, faces, mat, smooth=True):
    """Create a materialised mesh from explicit vertices and faces."""
    data = bpy.data.meshes.new(name + ' Mesh')
    data.from_pydata([tuple(vertex) for vertex in vertices], [], faces)
    data.update()
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    data.materials.append(mat)
    for poly in data.polygons:
        poly.use_smooth = smooth and len(poly.vertices) == 4
    return obj


def ring_body(name, rings, mat, segments=20):
    """Single oval torso surface. Rings are (z, x_radius, y_radius, y_offset)."""
    vertices = []
    for z, radius_x, radius_y, y_offset in rings:
        for index in range(segments):
            angle = math.tau * index / segments
            organic = 1.0 + 0.012 * math.sin(angle * 3.0 + z * 1.7)
            vertices.append(Vector((
                math.cos(angle) * radius_x * organic,
                y_offset + math.sin(angle) * radius_y * organic,
                z,
            )))
    faces = []
    for ring_index in range(len(rings) - 1):
        for index in range(segments):
            next_index = (index + 1) % segments
            lower = ring_index * segments
            upper = (ring_index + 1) * segments
            faces.append((
                lower + index,
                lower + next_index,
                upper + next_index,
                upper + index,
            ))
    bottom = len(vertices)
    vertices.append(Vector((0, rings[0][3], rings[0][0])))
    top = len(vertices)
    vertices.append(Vector((0, rings[-1][3], rings[-1][0])))
    for index in range(segments):
        next_index = (index + 1) % segments
        faces.append((bottom, next_index, index))
        upper = (len(rings) - 1) * segments
        faces.append((top, upper + index, upper + next_index))
    return custom_mesh(name, vertices, faces, mat)


def curved_tube(name, points, radii, mat, segments=14, depth_scale=0.88):
    """Continuous tapered tube used for a naturally bent arm."""
    points = [Vector(point) for point in points]
    vertices = []
    previous_axis = None
    for index, (point, radius) in enumerate(zip(points, radii)):
        if index == 0:
            tangent = (points[1] - points[0]).normalized()
        elif index == len(points) - 1:
            tangent = (points[-1] - points[-2]).normalized()
        else:
            tangent = (points[index + 1] - points[index - 1]).normalized()
        reference = Vector((0, 1, 0)) if abs(tangent.dot(Vector((0, 1, 0)))) < 0.92 else Vector((1, 0, 0))
        axis_x = reference.cross(tangent).normalized()
        if previous_axis is not None and axis_x.dot(previous_axis) < 0:
            axis_x = -axis_x
        axis_y = tangent.cross(axis_x).normalized()
        previous_axis = axis_x
        for segment in range(segments):
            angle = math.tau * segment / segments
            vertices.append(
                point
                + axis_x * (math.cos(angle) * radius)
                + axis_y * (math.sin(angle) * radius * depth_scale)
            )
    faces = []
    for ring_index in range(len(points) - 1):
        for index in range(segments):
            next_index = (index + 1) % segments
            lower = ring_index * segments
            upper = (ring_index + 1) * segments
            faces.append((
                lower + index,
                lower + next_index,
                upper + next_index,
                upper + index,
            ))
    start_center = len(vertices)
    vertices.append(points[0])
    end_center = len(vertices)
    vertices.append(points[-1])
    for index in range(segments):
        next_index = (index + 1) % segments
        faces.append((start_center, next_index, index))
        upper = (len(points) - 1) * segments
        faces.append((end_center, upper + index, upper + next_index))
    return custom_mesh(name, vertices, faces, mat)


def oval_rope(name, z, radius_x, radius_y, minor, mat, phase=0.0,
              major_segments=40, minor_segments=8):
    """A thin rope band that follows an oval torso instead of a circular torus."""
    vertices = []
    for major_index in range(major_segments):
        angle = math.tau * major_index / major_segments
        center = Vector((
            math.cos(angle) * radius_x,
            math.sin(angle) * radius_y,
            z + 0.012 * math.sin(angle * 2 + phase),
        ))
        outward = Vector((
            math.cos(angle) / radius_x,
            math.sin(angle) / radius_y,
            0,
        )).normalized()
        for minor_index in range(minor_segments):
            ring_angle = math.tau * minor_index / minor_segments
            vertices.append(
                center
                + outward * (math.cos(ring_angle) * minor)
                + Vector((0, 0, math.sin(ring_angle) * minor))
            )
    faces = []
    for major_index in range(major_segments):
        next_major = (major_index + 1) % major_segments
        for minor_index in range(minor_segments):
            next_minor = (minor_index + 1) % minor_segments
            faces.append((
                major_index * minor_segments + minor_index,
                next_major * minor_segments + minor_index,
                next_major * minor_segments + next_minor,
                major_index * minor_segments + next_minor,
            ))
    return custom_mesh(name, vertices, faces, mat)


def cone_between(name, start, end, radius_start, radius_end, mat, vertices=12):
    start = Vector(start)
    end = Vector(end)
    direction = end - start
    return cone(
        name,
        midpoint(start, end),
        radius_start,
        radius_end,
        direction.length,
        mat,
        vertices,
        rotation=limb_euler(-direction),
    )


def robe_point(ring, angle):
    """Point on a flared robe ring with folds and a slightly ragged hem."""
    z, radius_x, radius_y, fold = ring
    factor = (
        1.0
        + fold * math.sin(angle * 6.0 + 0.35)
        + 0.018 * math.sin(angle * 3.0 - 0.4)
    )
    hem_offset = (
        0.035 * math.sin(angle * 5.0 + 0.7)
        + 0.018 * math.sin(angle * 9.0)
        if z < 0.2 else 0.0
    )
    return Vector((
        math.cos(angle) * radius_x * factor,
        math.sin(angle) * radius_y * factor,
        z + hem_offset,
    ))


def folded_robe(name, rings, mat, segments=28):
    vertices = []
    for ring in rings:
        for index in range(segments):
            vertices.append(robe_point(ring, math.tau * index / segments))
    faces = []
    for ring_index in range(len(rings) - 1):
        for index in range(segments):
            next_index = (index + 1) % segments
            lower = ring_index * segments
            upper = (ring_index + 1) * segments
            faces.append((
                lower + index,
                lower + next_index,
                upper + next_index,
                upper + index,
            ))
    return custom_mesh(name, vertices, faces, mat)


def robe_ribbon(name, rings, angle, mat, half_width=math.radians(2.3)):
    vertices = []
    for ring in rings:
        for edge_angle in (angle - half_width, angle + half_width):
            point = robe_point(ring, edge_angle)
            normal = Vector((
                math.cos(edge_angle) / ring[1],
                math.sin(edge_angle) / ring[2],
                0,
            )).normalized()
            vertices.append(point + normal * 0.010)
    faces = []
    for ring_index in range(len(rings) - 1):
        base = ring_index * 2
        faces.append((base, base + 1, base + 3, base + 2))
    return custom_mesh(name, vertices, faces, mat, smooth=False)


def robe_hem(name, top_ring, bottom_ring, mat, segments=28):
    vertices = []
    for ring in (top_ring, bottom_ring):
        for index in range(segments):
            angle = math.tau * index / segments
            point = robe_point(ring, angle)
            normal = Vector((
                math.cos(angle) / ring[1],
                math.sin(angle) / ring[2],
                0,
            )).normalized()
            vertices.append(point + normal * 0.007)
    faces = []
    for index in range(segments):
        next_index = (index + 1) % segments
        faces.append((
            index,
            next_index,
            segments + next_index,
            segments + index,
        ))
    return custom_mesh(name, vertices, faces, mat)


def diamond_plane(name, x, y, z, width, height, mat):
    return custom_mesh(
        name,
        (
            (x, y, z + height * 0.5),
            (x + width * 0.5, y, z),
            (x, y, z - height * 0.5),
            (x - width * 0.5, y, z),
        ),
        ((0, 1, 2, 3),),
        mat,
        smooth=False,
    )


def cloth_strip(name, points, width, thickness, mat):
    """Low-cost wavy cloth strip following (x, y, z) centre points."""
    vertices = []
    for point in points:
        x, y, z = point
        vertices.extend((
            (x - width * 0.5, y - thickness * 0.5, z),
            (x + width * 0.5, y - thickness * 0.5, z),
            (x - width * 0.5, y + thickness * 0.5, z),
            (x + width * 0.5, y + thickness * 0.5, z),
        ))
    faces = []
    for index in range(len(points) - 1):
        a = index * 4
        b = (index + 1) * 4
        faces.extend((
            (a, a + 1, b + 1, b),
            (a + 3, a + 2, b + 2, b + 3),
            (a, b, b + 2, a + 2),
            (a + 1, a + 3, b + 3, b + 1),
        ))
    faces.append((0, 2, 3, 1))
    last = (len(points) - 1) * 4
    faces.append((last, last + 1, last + 3, last + 2))
    return custom_mesh(name, vertices, faces, mat, smooth=False)


def bevel_object(obj, width=0.006, segments=2):
    modifier = obj.modifiers.new('Small crafted bevel', 'BEVEL')
    modifier.width = width
    modifier.segments = segments
    modifier.limit_method = 'ANGLE'
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    return obj


def export(name):
    path = os.path.join(OUT, name + '.glb')
    mesh_objects = [obj for obj in bpy.context.scene.objects if obj.type == 'MESH']
    bpy.ops.object.select_all(action='DESELECT')
    for obj in mesh_objects:
        obj.select_set(True)
    if mesh_objects:
        bpy.context.view_layer.objects.active = mesh_objects[0]
        bpy.ops.object.join()
        merged = bpy.context.object
        merged.name = name
        bpy.context.scene.cursor.location = (0, 0, 0)
        bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_apply=True, export_materials='EXPORT')
    print('Exported', path)


def make_ground():
    clear()
    grass = material('dry summer grass', (0.33, 0.46, 0.12), 0.94)
    grass_light = material('sun bleached grass', (0.50, 0.57, 0.18), 0.96)
    earth = material('pale packed earth', (0.58, 0.42, 0.20), 0.98)
    pebble = material('path pebbles', (0.38, 0.34, 0.25), 0.99)

    grid = 64
    size = 60.0
    vertices = []
    faces = []
    for iy in range(grid + 1):
        y = -size / 2 + size * iy / grid
        for ix in range(grid + 1):
            x = -size / 2 + size * ix / grid
            path_x = math.sin(y * 0.105) * 0.8
            height = -0.10 + math.sin(x * 0.29) * math.cos(y * 0.21) * 0.055
            height += math.sin((x + y) * 0.13) * 0.025
            # Мелкая октава: на прежней сетке она была мельче ячейки, теперь
            # частые вершины несут её и луг перестаёт быть гладкой плоскостью.
            height += math.sin(x * 0.83 + 1.3) * math.cos(y * 0.71 - 0.6) * 0.018
            if abs(x - path_x) < 3.3 or math.hypot(x, y + 2.0) < 7.0:
                height *= 0.25
            vertices.append((x, y, height))
    for iy in range(grid):
        for ix in range(grid):
            a = iy * (grid + 1) + ix
            faces.append((a, a + 1, a + grid + 2, a + grid + 1))
    mesh = bpy.data.meshes.new('rolling meadow mesh')
    mesh.from_pydata(vertices, [], faces)
    mesh.materials.append(grass)
    terrain = bpy.data.objects.new('rolling meadow', mesh)
    bpy.context.collection.objects.link(terrain)

    path_vertices = []
    path_faces = []
    steps = 216
    for i in range(steps + 1):
        # Continue well past the northern gate so it reads as a road through the pass.
        y = -27.5 + 74.0 * i / steps
        center = math.sin(y * 0.105) * 0.8
        width = 2.35 + 0.22 * math.sin(i * 1.7)
        road_height = 0.025 + max(0.0, y - 27.0) * 0.021
        path_vertices.extend([(center - width, y, road_height), (center + width, y, road_height)])
    for i in range(steps):
        a = i * 2
        path_faces.append((a, a + 1, a + 3, a + 2))
    path_mesh = bpy.data.meshes.new('winding path mesh')
    path_mesh.from_pydata(path_vertices, [], path_faces)
    path_mesh.materials.append(earth)
    path = bpy.data.objects.new('winding ritual path', path_mesh)
    bpy.context.collection.objects.link(path)

    cylinder('village clearing', (0, -2.0, 0.018), 6.6, 0.035, earth, 64)
    for x, y, sx, sy in [(-11, 20, 6, 3), (12, 18, 5, 2.5), (-13, -10, 5, 2.2), (13, -14, 6, 2.6)]:
        bpy.ops.mesh.primitive_uv_sphere_add(segments=ring_count(24), ring_count=ring_count(12), radius=1, location=(x, y, -0.02))
        patch = finish(bpy.context.object, 'sunlit grass patch', grass_light)
        patch.scale = (sx, sy, 0.035)
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    random.seed(701)
    for index in range(42):
        x = random.uniform(-26.5, 26.5)
        y = random.uniform(-26.5, 26.5)
        if abs(x - math.sin(y * 0.105) * 0.8) < 4.2 or math.hypot(x, y + 2.0) < 7.5:
            continue
        height = random.uniform(0.20, 0.48)
        for blade in range(3):
            angle = blade * math.tau / 3 + random.uniform(-0.18, 0.18)
            cone('meadow grass blade', (x + math.cos(angle) * 0.08, y + math.sin(angle) * 0.08, height / 2 - 0.02),
                 0.045, 0.006, height, grass_light, 5,
                 rotation=(math.radians(random.uniform(-8, 8)), math.radians(random.uniform(-8, 8)), angle),
                 smooth=False)
    for index in range(18):
        y = -24.0 + index * 2.8
        path_x = math.sin(y * 0.105) * 0.8
        side = -1 if index % 2 == 0 else 1
        x = path_x + side * (2.55 + 0.18 * math.sin(index * 1.9))
        cylinder('path edge stone', (x, y, 0.06), 0.13 + 0.04 * (index % 3), 0.10, pebble, 12)
    export('ground')


MOUNTAIN_RINGS = (
    (28.0, -0.45),
    (31.5, 3.2),
    (36.0, 11.0),
    (40.5, 5.2),
    (47.0, 0.0),
)


def mountain_ring_point(ring_index, angle):
    """Радиус и высота кольца оболочки в этом направлении."""
    radius, base_height = MOUNTAIN_RINGS[ring_index]
    ridge_noise = math.sin(angle * 7.0 + 0.8) * 1.7 + math.sin(angle * 13.0 - 0.4) * 0.9
    # Blender +Y becomes Godot -Z: this is the northern gate, not the spawn side.
    pass_delta = abs(math.atan2(math.sin(angle - math.pi / 2), math.cos(angle - math.pi / 2)))
    height = base_height
    if ring_index in (1, 2, 3):
        full_height = base_height + ridge_noise * (1.0 if ring_index == 2 else 0.45)
        pass_blend = min(1.0, pass_delta / 0.42)
        pass_blend = pass_blend * pass_blend * (3.0 - 2.0 * pass_blend)
        valley_height = (0.16, 0.34, 0.24)[ring_index - 1]
        height = valley_height + (full_height - valley_height) * pass_blend
    radial_jitter = math.sin(angle * 11.0 + ring_index * 1.9) * (0.65 if ring_index not in (0, 4) else 0.25)
    return radius + radial_jitter, height


def mountain_surface(angle, radius):
    """Высота склона в точке: по ней сажаются отдельные вершины и ели, иначе
    они стоят на фиксированной высоте и повисают над гребнем."""
    points = [mountain_ring_point(index, angle) for index in range(len(MOUNTAIN_RINGS))]
    if radius <= points[0][0]:
        return points[0][1]
    for near, far in zip(points, points[1:]):
        if radius <= far[0]:
            span = max(1e-5, far[0] - near[0])
            return near[1] + (far[1] - near[1]) * (radius - near[0]) / span
    return points[-1][1]


def mountain_seat(angle, radius, footprint, tilt=0.0):
    """Самая низкая точка склона под основанием конуса. Плоское основание на
    склоне всегда приподнимается нижним краем, поэтому сажать надо по нему,
    а не по высоте под центром."""
    lowest = mountain_surface(angle, radius)
    centre_x = math.cos(angle) * radius
    centre_y = math.sin(angle) * radius
    steps = 24
    for i in range(steps):
        rim_angle = math.tau * i / steps
        x = centre_x + math.cos(rim_angle) * footprint
        y = centre_y + math.sin(rim_angle) * footprint
        lowest = min(lowest, mountain_surface(math.atan2(y, x), math.hypot(x, y)))
    return lowest - footprint * math.sin(abs(tilt))


def tilted_offset(height, rotation):
    """Куда уезжает вершина конуса, если его наклонить: шапка должна сесть
    именно туда, а не на место невернутой макушки."""
    rx, ry, rz = rotation
    x = height * math.cos(rx) * math.sin(ry)
    y = -height * math.sin(rx)
    z = height * math.cos(rx) * math.cos(ry)
    return (x * math.cos(rz) - y * math.sin(rz), x * math.sin(rz) + y * math.cos(rz), z)


def make_mountains():
    clear()
    pine = material('forest foothills', (0.12, 0.20, 0.07), 1.0)
    rock = material('warm mountain rock', (0.27, 0.24, 0.18), 0.96)
    rock_shadow = material('shadowed mountain rock', (0.21, 0.20, 0.17), 0.97)
    high_rock = material('sunlit ridge rock', (0.45, 0.39, 0.28), 0.93)
    high_rock_soft = material('weathered ridge rock', (0.37, 0.34, 0.27), 0.94)
    haze = material('distant blue ridge', (0.20, 0.27, 0.26), 1.0)
    snow = material('old snow caps', (0.76, 0.80, 0.76), 0.92)
    mats = [pine, rock, rock_shadow, high_rock, high_rock_soft, haze]
    segments = 288
    rings = MOUNTAIN_RINGS
    vertices = []
    for ring_index in range(len(rings)):
        for i in range(segments):
            angle = math.tau * i / segments
            r, height = mountain_ring_point(ring_index, angle)
            vertices.append((math.cos(angle) * r, math.sin(angle) * r, height))
    faces = []
    face_materials = []
    for ring_index in range(len(rings) - 1):
        for i in range(segments):
            nxt = (i + 1) % segments
            a = ring_index * segments + i
            b = ring_index * segments + nxt
            c = (ring_index + 1) * segments + nxt
            d = (ring_index + 1) * segments + i
            faces.append((a, b, c, d))
            # break up broad procedural bands with restrained, deterministic rock variation
            if ring_index == 0:
                material_index = 0
            elif ring_index == 1:
                material_index = 2 if math.sin(angle * 3.0 + 0.7) > 0.84 else 1
            elif ring_index == 2:
                material_index = 4 if math.sin(angle * 2.0 - 0.8) > 0.86 else 3
            elif ring_index == 3:
                material_index = 4 if math.sin(angle * 3.0 + 1.2) > 0.90 else 1
            else:
                material_index = 5
            face_materials.append(material_index)
    mesh = bpy.data.meshes.new('mountain amphitheatre mesh')
    mesh.from_pydata(vertices, [], faces)
    for mat in mats:
        mesh.materials.append(mat)
    for poly, mat_index in zip(mesh.polygons, face_materials):
        poly.material_index = mat_index
    obj = bpy.data.objects.new('mountain amphitheatre', mesh)
    bpy.context.collection.objects.link(obj)

    random.seed(1604)
    for i in range(22):
        angle = math.tau * (i + 0.18) / 22.0
        pass_delta = abs(math.atan2(math.sin(angle - math.pi / 2), math.cos(angle - math.pi / 2)))
        if pass_delta < 0.42:
            continue
        radius = random.uniform(34.5, 39.0)
        peak_height = random.uniform(4.6, 8.2)
        peak_radius = random.uniform(6.5, 10.5)
        tip_radius = random.uniform(0.10, 0.42)
        sides = random.choice((12, 13, 14))
        tilt = (random.uniform(-0.05, 0.05), random.uniform(-0.07, 0.07), angle)
        peak_x = math.cos(angle) * radius
        peak_y = math.sin(angle) * radius

        # Основание уходит в сам склон: раньше конус стоял на постоянной
        # высоте 2.0 и над гребнем повисал в воздухе.
        # Макушка поднимается над гребнем на свою высоту, а основание уходит
        # ниже самой низкой точки склона под ним: раньше конус стоял на
        # постоянной отметке 2.0 и краем основания повисал в воздухе.
        apex_z = mountain_surface(angle, radius) + peak_height
        base_z = mountain_seat(angle, radius, peak_radius, max(abs(tilt[0]), abs(tilt[1]))) - 1.0
        depth = apex_z - base_z
        centre = (peak_x, peak_y, (base_z + apex_z) / 2)
        rock_phase = i * 1.37
        weather_rock(cone('individual mountain peak', centre,
                          peak_radius, tip_radius, depth, high_rock if i % 3 else haze,
                          sides, rotation=tilt, smooth=False),
                     rock_phase, 4 + i % 3)
        if peak_height > 6.6:
            cap_height = peak_height * 0.32
            # Шапка повторяет радиус конуса на своей высоте и его наклон:
            # прежняя была шире вершины и висела над ней полями шляпы.
            cap_bottom = tip_radius + (peak_radius - tip_radius) * cap_height / depth
            offset = tilted_offset(depth / 2 - cap_height / 2, tilt)
            weather_rock(cone('snow cap', (centre[0] + offset[0], centre[1] + offset[1], centre[2] + offset[2]),
                              cap_bottom, tip_radius, cap_height, snow, sides, rotation=tilt, smooth=False),
                         rock_phase, 4 + i % 3)
    for i in range(26):
        angle = math.tau * (i + 0.35) / 26.0
        if abs(math.atan2(math.sin(angle - math.pi / 2), math.cos(angle - math.pi / 2))) < 0.46:
            continue
        radius = 29.0 + random.uniform(-0.5, 1.4)
        height = random.uniform(2.6, 5.8)
        # Ели тоже садятся на склон, а не на нулевую отметку.
        foot_z = mountain_seat(angle, radius, 1.35) - 0.2
        cone('foothill pine', (math.cos(angle) * radius, math.sin(angle) * radius, foot_z + height / 2),
             random.uniform(0.8, 1.35), 0.08, height, pine, 12, smooth=False)
        if i % 3 == 0:
            cone('pine lower branches', (math.cos(angle) * radius, math.sin(angle) * radius, foot_z + height * 0.24),
                 random.uniform(0.9, 1.5), 0.10, height * 0.48, pine, 12, smooth=False)

    # Broken rock shoulders frame the open road without closing its silhouette.
    for side in (-1, 1):
        for depth_index, road_y in enumerate((29.5, 34.0, 39.0)):
            shoulder_x = side * (5.2 + depth_index * 1.35)
            shoulder_height = 2.6 + depth_index * 1.15
            weather_rock(cone('pass shoulder rock', (shoulder_x, road_y, shoulder_height * 0.5 - 0.05),
                              2.35 + depth_index * 0.55, 0.22, shoulder_height,
                              high_rock if depth_index % 2 == 0 else rock, 10,
                              rotation=(side * 0.04, -side * 0.10, side * 0.08), smooth=False),
                         side * 0.9 + depth_index * 2.1, 4, 0.13)
    export('mountain_ring')


def make_house(variant='green'):
    clear()
    configs = {
        'green': {
            'size': (5.2, 4.2, 2.95), 'wall': (0.34, 0.52, 0.37),
            'trim': (0.88, 0.83, 0.60), 'roof': (0.40, 0.29, 0.10),
            'angle': 31, 'door_x': 0.0, 'windows': (-1.55, 1.55), 'style': 'cottage',
        },
        'blue': {
            'size': (4.75, 4.0, 3.38), 'wall': (0.16, 0.35, 0.52),
            'trim': (0.86, 0.90, 0.82), 'roof': (0.075, 0.12, 0.18),
            'angle': 39, 'door_x': -1.25, 'windows': (0.65, 1.55), 'style': 'tall',
        },
        'red': {
            'size': (5.9, 3.75, 2.62), 'wall': (0.56, 0.16, 0.075),
            'trim': (0.83, 0.66, 0.37), 'roof': (0.16, 0.075, 0.035),
            'angle': 25, 'door_x': 0.65, 'windows': (-1.65,), 'style': 'log',
        },
        'ochre': {
            'size': (4.65, 5.05, 3.02), 'wall': (0.82, 0.54, 0.13),
            'trim': (0.93, 0.78, 0.35), 'roof': (0.48, 0.29, 0.075),
            'angle': 34, 'door_x': 0.0, 'windows': (-1.35, 1.35), 'style': 'veranda',
        },
    }
    config = configs[variant]
    width, depth, wall_height = config['size']
    wall_top = 0.42 + wall_height
    roof_angle = math.radians(config['angle'])
    roof_half_run = depth / 2 + 0.42
    roof_rise = roof_half_run * math.tan(roof_angle)
    roof_length = math.sqrt(roof_half_run ** 2 + roof_rise ** 2)

    wood = material(variant + ' painted timber', config['wall'], 0.90)
    wood_light = material(variant + ' sun worn trim', config['trim'], 0.88)
    dark = material('dark carved oak', (0.12, 0.055, 0.022), 0.94)
    roof = material(variant + ' roof', config['roof'], 0.96)
    roof_light = material('roof edge highlights', tuple(min(1.0, value * 1.32) for value in config['roof']), 0.94)
    white = material('chalk carved ornament', (0.90, 0.87, 0.70), 0.86)
    glass = material('blue window glass', (0.018, 0.060, 0.075), 0.28, 0.12)
    stone = material('mixed fieldstone foundation', (0.27, 0.28, 0.24), 0.99)
    iron = material('black iron fittings', (0.035, 0.04, 0.035), 0.40, 0.55)
    vermilion = material('house vermilion paint', (0.62, 0.035, 0.016), 0.92)
    folk_blue = material('house folk blue paint', (0.08, 0.22, 0.38), 0.93)
    foliage = material('house birch garland', (0.18, 0.36, 0.075), 0.98)
    petal_white = material('house white flowers', (0.94, 0.90, 0.68), 0.96)
    petal_blue = material('house cornflower petals', (0.15, 0.32, 0.56), 0.94)
    petal_yellow = material('house flower centres', (0.96, 0.56, 0.035), 0.86)

    cube('stone foundation', (0, 0, 0.21), (width + 0.28, depth + 0.28, 0.42), stone, bevel=0.08)
    cube('main walls', (0, 0, 0.42 + wall_height / 2), (width, depth, wall_height), wood, bevel=0.055)

    seam_count = 7 if config['style'] == 'log' else 5
    for index in range(seam_count):
        z = 0.62 + index * (wall_height - 0.35) / max(1, seam_count - 1)
        seam_depth = 0.09 if config['style'] == 'log' else 0.04
        cylinder('front wall log' if config['style'] == 'log' else 'front timber seam',
                 (0, -depth / 2 - 0.025, z), seam_depth, width - 0.12, wood_light, 8,
                 rotation=(0, math.radians(90), 0))
        if config['style'] == 'log':
            cylinder('back wall log', (0, depth / 2 + 0.025, z), seam_depth, width - 0.12,
                     wood_light, 8, rotation=(0, math.radians(90), 0))
            # Сруб был из брёвен только с лицевой и задней стены, с торцов
            # оставалась гладкая доска. Справа стена закрыта пристройкой,
            # туда венцы не кладём — они вылезали сквозь её переднюю стенку.
            for side in (-1,):
                cylinder('side wall log', (side * (width / 2 + 0.025), 0, z), seam_depth,
                         depth - 0.12, wood_light, 8, rotation=(math.radians(90), 0, 0))

    roof_center_z = wall_top + 0.14 + roof_rise / 2
    roof_center_y = roof_half_run / 2
    cube('front roof slope', (0, -roof_center_y, roof_center_z),
         (width + 0.86, roof_length, 0.34), roof, rotation=(roof_angle, 0, 0), bevel=0.04)
    cube('back roof slope', (0, roof_center_y, roof_center_z),
         (width + 0.86, roof_length, 0.34), roof, rotation=(-roof_angle, 0, 0), bevel=0.04)
    ridge_z = wall_top + 0.14 + roof_rise
    cube('roof ridge beam', (0, 0, ridge_z), (width + 1.0, 0.18, 0.20), roof_light, bevel=0.04)

    # Close both gable ends under the two roof planes. Without these shallow
    # triangular walls the house reads as a hollow stage set from the side.
    gable_x_inner = width / 2 - 0.015
    gable_x_outer = width / 2 + 0.045
    gable_points = (
        (-depth / 2 - 0.02, wall_top - 0.02),
        (depth / 2 + 0.02, wall_top - 0.02),
        (0.0, ridge_z - 0.10),
    )
    for side in (-1, 1):
        x_inner = side * gable_x_inner
        x_outer = side * gable_x_outer
        vertices = []
        for x in (x_inner, x_outer):
            vertices.extend((
                (x, gable_points[0][0], gable_points[0][1]),
                (x, gable_points[1][0], gable_points[1][1]),
                (x, gable_points[2][0], gable_points[2][1]),
            ))
        faces = (
            (0, 2, 1), (3, 4, 5),
            (0, 1, 4, 3), (1, 2, 5, 4), (2, 0, 3, 5),
        )
        custom_mesh('closed side gable', vertices, faces, wood, smooth=False)
        # A pale trim follows the triangular silhouette and makes the closure
        # intentional instead of looking like a flat patched wall.
        cone_between('gable left trim',
                     (x_outer, gable_points[0][0] - 0.02, gable_points[0][1] + 0.02),
                     (x_outer, gable_points[2][0] - 0.02, gable_points[2][1] + 0.02),
                     0.045, 0.035, wood_light, 8)
        cone_between('gable right trim',
                     (x_outer, gable_points[2][0] + 0.02, gable_points[2][1] + 0.02),
                     (x_outer, gable_points[1][0] + 0.02, gable_points[1][1] + 0.02),
                     0.035, 0.045, wood_light, 8)
        side_sun = Vector((x_outer + side * 0.035, 0.0, wall_top + roof_rise * 0.36))
        torus('side gable folk sun', side_sun, 0.24, 0.032, folk_blue,
              rotation=(0, math.radians(90), 0))
        sphere('side gable sun centre', side_sun + Vector((side * 0.045, 0, 0)),
               0.065, vermilion, 8, 4)
        for ray_index in range(6):
            angle = math.tau * ray_index / 6
            direction = Vector((0, math.cos(angle), math.sin(angle)))
            cone_between('side gable sun ray', side_sun + direction * 0.10,
                         side_sun + direction * 0.21, 0.018, 0.004,
                         white if ray_index % 2 == 0 else vermilion, 6)
    # Обрешётка сидела на средней плоскости плиты и целиком тонула в её
    # толщине. Теперь она лежит на скате и рядов вдвое больше.
    course_lift = 0.17 / math.cos(roof_angle) + 0.025
    course_steps = 12
    for step in range(1, course_steps):
        y = -roof_half_run + step * roof_half_run * 2 / course_steps
        z = wall_top + 0.14 + (roof_half_run - abs(y)) * math.tan(roof_angle) + course_lift
        cylinder('roof course', (0, y, z), 0.05, width + 0.80, roof_light, 10,
                 rotation=(0, math.radians(90), 0))

    # Стропильные ноги под свесом: раньше кровля обрывалась голой плитой.
    rafter_count = max(4, int(width / 0.85))
    eaves_drop = 0.17 / math.cos(roof_angle) + 0.07
    for slope in (-1, 1):
        for index in range(rafter_count):
            rafter_x = -width / 2 + 0.28 + index * (width - 0.56) / max(1, rafter_count - 1)
            cube('rafter tail', (rafter_x, slope * (roof_half_run - 0.26),
                                 wall_top + 0.14 + 0.26 * math.tan(roof_angle) - eaves_drop),
                 (0.10, 0.62, 0.13), dark, rotation=(slope * roof_angle, 0, 0))
        cube('eaves fascia board', (0, slope * (roof_half_run + 0.06), wall_top + 0.08 - eaves_drop * 0.4),
             (width + 0.86, 0.10, 0.26), wood_light, bevel=0.02)

    chimney_x = width * (0.31 if variant != 'red' else -0.31)
    chimney_y = depth * 0.14
    cube('stone chimney', (chimney_x, chimney_y, ridge_z - 0.08), (0.58, 0.58, 1.58), stone, bevel=0.07)
    cube('chimney crown', (chimney_x, chimney_y, ridge_z + 0.73), (0.74, 0.74, 0.18), dark, bevel=0.04)
    for side in (-1, 1):
        cube('chimney iron brace', (chimney_x + side * 0.20, chimney_y - 0.305, ridge_z + 0.12),
             (0.055, 0.035, 0.58), iron)

    door_x = config['door_x']
    front_y = -depth / 2
    cube('front step', (door_x, front_y - 0.54, 0.15), (1.85, 0.72, 0.22), stone, bevel=0.05)
    cube('porch deck', (door_x, front_y - 0.25, 0.34), (1.55, 0.62, 0.28), dark, bevel=0.04)
    cube('plank door', (door_x, front_y - 0.075, 1.47), (1.10, 0.14, 2.28), dark, bevel=0.045)
    for plank_x in (-0.40, -0.20, 0.0, 0.20, 0.40):
        cube('door board seam', (door_x + plank_x, front_y - 0.151, 1.47), (0.025, 0.025, 2.08), wood_light)
    torus('door sun ornament', (door_x, front_y - 0.17, 1.55), 0.21, 0.035, white,
          rotation=(math.radians(90), 0, 0))
    sphere('iron door handle', (door_x + 0.40, front_y - 0.18, 1.40), 0.055, iron, 8, 4)

    for x in config['windows']:
        cube('carved window frame', (x, front_y - 0.085, 1.75), (1.13, 0.12, 1.10), white, bevel=0.04)
        cube('window glass', (x, front_y - 0.155, 1.75), (0.78, 0.035, 0.74), glass)
        cube('window vertical bar', (x, front_y - 0.18, 1.75), (0.052, 0.025, 0.74), white)
        cube('window horizontal bar', (x, front_y - 0.18, 1.75), (0.78, 0.025, 0.052), white)
        cube('window sill', (x, front_y - 0.20, 1.17), (1.34, 0.28, 0.10), white, bevel=0.025)
        cube('window cornice', (x, front_y - 0.17, 2.36), (1.30, 0.22, 0.11), white, bevel=0.025)
        for notch in (-0.42, 0.0, 0.42):
            cube('cornice tooth', (x + notch, front_y - 0.20, 2.46), (0.16, 0.16, 0.09), white)
        if variant != 'red':
            for side in (-1, 1):
                cube('painted shutter', (x + side * 0.68, front_y - 0.10, 1.75),
                     (0.23, 0.09, 1.03), wood_light, rotation=(0, 0, math.radians(side * 5)))
        if variant in ('green', 'ochre'):
            cube('flower window box', (x, front_y - 0.30, 1.10), (1.05, 0.32, 0.23), dark, bevel=0.035)

    for x in (-width / 2 - 0.07, width / 2 + 0.07):
        for y in (-depth / 2 - 0.04, depth / 2 + 0.04):
            cube('corner beam', (x, y, 0.42 + wall_height / 2), (0.15, 0.17, wall_height + 0.08),
                 wood_light)

    side_values = (-1,) if variant == 'red' else (-1, 1)
    for side in side_values:
        side_x = side * (width / 2 + 0.085)
        cube('side window frame', (side_x, 0.18, 1.72), (0.12, 1.10, 1.04), white, bevel=0.035)
        cube('side window glass', (side_x + side * 0.07, 0.18, 1.72), (0.025, 0.76, 0.70), glass)
        cube('side window vertical bar', (side_x + side * 0.09, 0.18, 1.72), (0.025, 0.052, 0.70), white)
        cube('side window horizontal bar', (side_x + side * 0.09, 0.18, 1.72), (0.025, 0.76, 0.052), white)

    if config['style'] == 'tall':
        dormer_x = 0.75
        dormer_y = -0.95
        # Слуховое окно стояло на фиксированной высоте и целиком уходило под
        # скат: наружу торчал только край его кровли. Сажаем его на реальную
        # поверхность ската.
        dormer_seat = (wall_top + 0.14 + (roof_half_run - abs(dormer_y)) * math.tan(roof_angle)
                       + 0.17 / math.cos(roof_angle))
        cube('dormer body', (dormer_x, dormer_y, dormer_seat + 0.30), (1.45, 1.20, 1.18), wood, bevel=0.04)
        cube('dormer roof left', (dormer_x, dormer_y - 0.33, dormer_seat + 0.98), (1.72, 1.00, 0.20), roof,
             rotation=(math.radians(30), 0, 0), bevel=0.025)
        cube('dormer roof right', (dormer_x, dormer_y + 0.32, dormer_seat + 0.98), (1.72, 1.00, 0.20), roof,
             rotation=(math.radians(-30), 0, 0), bevel=0.025)
        cube('attic window frame', (dormer_x, dormer_y - 0.615, dormer_seat + 0.36), (0.75, 0.08, 0.65), white)
        cube('attic window glass', (dormer_x, dormer_y - 0.67, dormer_seat + 0.36), (0.51, 0.025, 0.42), glass)
        # The blue house becomes a quiet ceremonial outpost: crisp white trim,
        # vermilion sun marks and a small garland make the clean geometry feel
        # hand-kept, while the dark roof and windows keep the unease intact.
        dormer_front_y = dormer_y - 0.73
        dormer_sun = Vector((dormer_x, dormer_front_y, dormer_seat + 0.78))
        torus('blue house attic sun', dormer_sun, 0.25, 0.035, vermilion,
              rotation=(math.radians(90), 0, 0))
        sphere('blue house attic sun heart', dormer_sun + Vector((0, -0.045, 0)),
               0.065, petal_yellow, 8, 4)
        for ray_index in range(8):
            angle = math.tau * ray_index / 8
            direction = Vector((math.cos(angle), 0, math.sin(angle)))
            cone_between('blue house attic sun ray', dormer_sun + direction * 0.10,
                         dormer_sun + direction * 0.20, 0.016, 0.004,
                         petal_yellow if ray_index % 2 == 0 else white, 6)
        curved_tube('blue house front garland',
                    ((-1.92, front_y - 0.18, wall_top - 0.28),
                     (-1.02, front_y - 0.21, wall_top - 0.13),
                     (-0.10, front_y - 0.23, wall_top - 0.18),
                     (0.82, front_y - 0.21, wall_top - 0.12),
                     (1.70, front_y - 0.18, wall_top - 0.26)),
                    (0.030, 0.034, 0.036, 0.034, 0.030), foliage, 7, 0.55)
        for flower_index, x in enumerate((-1.55, -0.78, 0.0, 0.78, 1.50)):
            z = wall_top - 0.18 - 0.035 * abs(x)
            sphere('blue house garland centre', (x, front_y - 0.25, z),
                   0.035, petal_yellow, 7, 4)
            for petal_index in range(5):
                petal_angle = math.tau * petal_index / 5
                petal = sphere('blue house garland petal',
                               (x + math.cos(petal_angle) * 0.048,
                                front_y - 0.245,
                                z + math.sin(petal_angle) * 0.048),
                               0.034, petal_white if flower_index % 2 == 0 else petal_blue, 6, 3)
                apply_scale(petal, (1.12, 0.42, 0.72))
        for x in config['windows']:
            for stripe_index, stripe_mat in enumerate((vermilion, petal_yellow, vermilion)):
                cube('blue house painted window stripe',
                     (x + (stripe_index - 1) * 0.28, front_y - 0.215, 1.20),
                     (0.045, 0.025, 0.26), stripe_mat,
                     rotation=(0, 0, math.radians(8 if stripe_index % 2 == 0 else -8)),
                     bevel=0.006)
    elif config['style'] == 'log':
        extension_x = width / 2 + 0.82
        cube('side log extension', (extension_x, 0.20, 1.16), (1.75, 2.85, 1.90), wood, bevel=0.05)
        cube('lean to roof', (extension_x + 0.08, 0.20, 2.25), (2.20, 3.30, 0.24), roof,
             rotation=(0, math.radians(-11), 0), bevel=0.035)
        for z in (0.62, 1.08, 1.54):
            cylinder('extension log seam', (extension_x, -1.25, z), 0.075, 1.55, wood_light, 8,
                     rotation=(0, math.radians(90), 0))
        cylinder('stacked firewood', (extension_x + 0.52, -1.40, 0.45), 0.16, 0.72, wood_light, 8,
                 rotation=(0, math.radians(90), 0))
        # A red Hårga-like log house needs a clear ritual face so it belongs to
        # the same village as the gate and guardian, not a generic shed.
        red_sun = Vector((0, front_y - 0.22, wall_top - 0.25))
        torus('red house folk sun', red_sun, 0.30, 0.045, folk_blue,
              rotation=(math.radians(90), 0, 0))
        sphere('red house sun heart', red_sun + Vector((0, -0.055, 0)),
               0.075, petal_yellow, 8, 4)
        for ray_index in range(8):
            angle = math.tau * ray_index / 8
            direction = Vector((math.cos(angle), 0, math.sin(angle)))
            cone_between('red house sun ray', red_sun + direction * 0.13,
                         red_sun + direction * 0.24, 0.018, 0.004,
                         petal_yellow if ray_index % 2 == 0 else white, 6)
        curved_tube('red house front garland',
                    ((-2.28, front_y - 0.23, wall_top - 0.30),
                     (-1.15, front_y - 0.25, wall_top - 0.18),
                     (0, front_y - 0.26, wall_top - 0.22),
                     (1.15, front_y - 0.25, wall_top - 0.18),
                     (2.28, front_y - 0.23, wall_top - 0.30)),
                    (0.028, 0.032, 0.034, 0.032, 0.028), foliage, 7, 0.55)
        for x in (-2.0, -1.0, 0.0, 1.0, 2.0):
            sphere('red house garland flower centre', (x, front_y - 0.27,
                                                        wall_top - 0.23 - 0.03 * abs(x)),
                   0.032, petal_yellow, 7, 4)
        for side in (-1, 1):
            for stripe_index, stripe_mat in enumerate((folk_blue, petal_yellow, folk_blue)):
                cube('red house corner paint',
                     (side * (width / 2 + 0.09), front_y - 0.11,
                      0.95 + stripe_index * 0.32),
                     (0.045, 0.025, 0.20), stripe_mat,
                     rotation=(0, 0, math.radians(side * 7)), bevel=0.006)
    elif config['style'] == 'veranda':
        veranda_y = front_y - 0.72
        cube('wide veranda deck', (0, veranda_y, 0.34), (width + 0.35, 1.42, 0.28), dark, bevel=0.04)
        cube('veranda canopy', (0, veranda_y, 2.76), (width + 0.62, 1.58, 0.22), roof,
             rotation=(math.radians(7), 0, 0), bevel=0.035)
        for x in (-width / 2 + 0.28, 0, width / 2 - 0.28):
            cylinder('veranda post', (x, veranda_y - 0.46, 1.50), 0.09, 2.35, dark, 8)
            torus('post carving', (x, veranda_y - 0.46, 1.02), 0.13, 0.026, white)
            for stripe_index, stripe_mat in enumerate((vermilion, folk_blue, vermilion)):
                cube('veranda folk paint stripe',
                     (x, veranda_y - 0.555, 1.08 + stripe_index * 0.30),
                     (0.12, 0.018, 0.11), stripe_mat,
                     rotation=(0, 0, math.radians(8 if stripe_index % 2 == 0 else -8)),
                     bevel=0.008)
        cube('veranda rail', (0, veranda_y - 0.48, 0.90), (width - 0.35, 0.09, 0.11), wood_light)

        # A bright ceremonial face on the roof makes the building read as the
        # village's ritual house, while the empty dark windows keep it uncanny.
        roof_emblem_y = -roof_half_run * 0.43
        roof_emblem_z = wall_top + 0.14 + (roof_half_run - abs(roof_emblem_y)) * math.tan(roof_angle) + 0.10
        roof_normal = Vector((0, -math.sin(roof_angle), math.cos(roof_angle)))
        roof_tangent = Vector((0, math.cos(roof_angle), math.sin(roof_angle)))
        roof_emblem_center = Vector((0, roof_emblem_y, roof_emblem_z)) + roof_normal * 0.10
        torus('ochre house solar emblem', roof_emblem_center,
              0.48, 0.065, folk_blue, rotation=(roof_angle, 0, 0))
        sphere('ochre house sun heart', roof_emblem_center + roof_normal * 0.045,
               0.14, vermilion, 10, 5)
        for ray_index in range(8):
            angle = math.tau * ray_index / 8
            direction = Vector((1, 0, 0)) * math.cos(angle) + roof_tangent * math.sin(angle)
            cone_between('ochre house sun ray',
                         roof_emblem_center + roof_normal * 0.035 + direction * 0.20,
                         roof_emblem_center + roof_normal * 0.035 + direction * 0.38,
                         0.026, 0.006,
                         vermilion if ray_index % 2 == 0 else white, 7)
        curved_tube('ochre house roof garland',
                    ((-1.72, roof_emblem_center.y, roof_emblem_center.z - 0.24),
                     (-0.86, roof_emblem_center.y, roof_emblem_center.z - 0.10),
                     (0, roof_emblem_center.y, roof_emblem_center.z - 0.06),
                     (0.86, roof_emblem_center.y, roof_emblem_center.z - 0.10),
                     (1.72, roof_emblem_center.y, roof_emblem_center.z - 0.24)),
                    (0.035, 0.040, 0.043, 0.040, 0.035), foliage, 7, 0.55)
        for flower_index, x in enumerate((-1.42, -0.72, 0.0, 0.72, 1.42)):
            sphere('ochre house flower centre', Vector((x, roof_emblem_center.y,
                                                  roof_emblem_z - 0.13 + 0.035 * abs(x)),
                                                  ) + Vector((0, -0.03, 0)),
                   0.042, petal_yellow, 7, 4)
            petal_mat = petal_white if flower_index % 2 == 0 else petal_blue
            for petal_index in range(5):
                petal_angle = math.tau * petal_index / 5
                petal = sphere('ochre house flower petal',
                               Vector((x, roof_emblem_center.y,
                                roof_emblem_z - 0.13 + 0.035 * abs(x))) + Vector((0, -0.03, 0))
                               + Vector((math.cos(petal_angle) * 0.060, 0, math.sin(petal_angle) * 0.060)),
                               0.044, petal_mat, 6, 3)
                apply_scale(petal, (1.1, 0.42, 0.70))

        for x in (-1.35, 1.35):
            for flower_index in range(5):
                flower_x = x + (flower_index - 2) * 0.17
                flower_z = 1.22 + 0.045 * math.sin(flower_index * 1.7 + x)
                cylinder('veranda flower stem', (flower_x, front_y - 0.37, flower_z),
                         0.012, 0.30, foliage, 6)
                sphere('veranda flower centre', (flower_x, front_y - 0.37, flower_z + 0.17),
                       0.026, petal_yellow, 6, 3)
                sphere('veranda flower head', (flower_x + 0.035, front_y - 0.37,
                                               flower_z + 0.17),
                       0.043, petal_white if flower_index % 2 == 0 else petal_blue, 6, 3)
    else:
        torus('gable sun carving', (0, front_y - 0.21, wall_top + roof_rise * 0.48), 0.34, 0.05, white,
              rotation=(math.radians(90), 0, 0))
        for angle in range(0, 360, 45):
            radians = math.radians(angle)
            cube('gable sun ray', (math.cos(radians) * 0.51, front_y - 0.22,
                 wall_top + roof_rise * 0.48 + math.sin(radians) * 0.51),
                 (0.28, 0.06, 0.055), white, rotation=(0, -radians, 0))
        if variant == 'green':
            # Cottage folk-horror pass: a welcoming garland and hand-painted
            # marks sit against the blank sage wall, while the dark door keeps
            # the house from feeling like a toy prop.
            porch_y = front_y - 0.245
            garland_z = wall_top - 0.24
            curved_tube('green house front garland',
                        ((-1.90, porch_y, garland_z - 0.14),
                         (-0.95, porch_y - 0.025, garland_z - 0.03),
                         (0, porch_y - 0.035, garland_z),
                         (0.95, porch_y - 0.025, garland_z - 0.03),
                         (1.90, porch_y, garland_z - 0.14)),
                        (0.030, 0.034, 0.036, 0.034, 0.030), foliage, 7, 0.55)
            for flower_index, x in enumerate((-1.52, -0.76, 0, 0.76, 1.52)):
                z = garland_z - 0.02 - 0.035 * abs(x)
                sphere('green house flower centre', (x, porch_y - 0.05, z),
                       0.036, petal_yellow, 7, 4)
                for petal_index in range(5):
                    angle = math.tau * petal_index / 5
                    petal = sphere('green house flower petal',
                                   (x + math.cos(angle) * 0.050, porch_y - 0.047,
                                    z + math.sin(angle) * 0.050),
                                   0.036, petal_white if flower_index % 2 == 0 else petal_blue, 6, 3)
                    apply_scale(petal, (1.12, 0.42, 0.72))
            for x in config['windows']:
                for stripe_index, stripe_mat in enumerate((vermilion, petal_yellow, vermilion)):
                    cube('green house window paint',
                         (x + (stripe_index - 1) * 0.28, front_y - 0.22, 1.16),
                         (0.040, 0.022, 0.24), stripe_mat,
                         rotation=(0, 0, math.radians(8 if stripe_index % 2 == 0 else -8)),
                         bevel=0.006)

    export('house_' + variant)


def make_guardian():
    clear()
    straw = material('pale midsummer straw', (0.74, 0.59, 0.27), 0.92)
    straw_dark = material('woven willow shadow', (0.36, 0.24, 0.085), 0.96)
    cloth = material('unbleached ritual linen', (0.78, 0.71, 0.56), 0.97)
    cloth_light = material('vermilion folk embroidery', (0.67, 0.052, 0.022), 0.92)
    cloth_shadow = material('oatmeal linen fold', (0.48, 0.39, 0.27), 0.98)
    ochre = material('midsummer ochre thread', (0.92, 0.48, 0.050), 0.87)
    folk_blue = material('midsummer folk blue', (0.10, 0.25, 0.43), 0.94)
    mask = material('white birch ritual mask', (0.87, 0.82, 0.67), 0.78)
    brow = material('carved brow shadow', (0.18, 0.12, 0.07), 0.93)
    black = material('hollow eyes', (0.015, 0.01, 0.008), 0.95)
    ember = material('ember eyes', (0.65, 0.025, 0.008), 0.35, 0.0, (1.0, 0.015, 0.002))
    rope = material('hemp bindings', (0.38, 0.24, 0.08), 0.98)
    bone = material('pale ancestor charms', (0.78, 0.73, 0.57), 0.90)
    iron = material('aged ritual iron', (0.15, 0.075, 0.032), 0.76, 0.48)
    foliage = material('fresh birch wreath leaves', (0.20, 0.39, 0.095), 0.98)
    flower_white = material('white midsummer petals', (0.95, 0.93, 0.77), 0.96)
    flower_blue = material('blue cornflower petals', (0.16, 0.34, 0.58), 0.94)
    flower_yellow = material('gold flower centres', (0.96, 0.58, 0.045), 0.86)

    def ritual_flower(name, location, petal_mat, size=1.0):
        location = Vector(location)
        sphere(name + ' centre', location, 0.034 * size, flower_yellow, 7, 4)
        for petal_index in range(5):
            angle = math.tau * petal_index / 5
            petal = sphere(
                name + ' petal',
                location + Vector((math.cos(angle) * 0.050 * size, -0.006,
                                   math.sin(angle) * 0.050 * size)),
                0.038 * size,
                petal_mat,
                6,
                3,
            )
            apply_scale(petal, (1.15, 0.42, 0.72))

    # Юбка: раньше ровный конус читался как дорожный, теперь по кругу идёт
    # волна складок ткани — тот же приём, что и для горных пород, но мягче
    # и без огранки (сама юбка остаётся гладкой).
    robe_rings = (
        (1.88, 0.32, 0.24, 0.010),
        (1.55, 0.39, 0.30, 0.025),
        (1.10, 0.49, 0.38, 0.045),
        (0.55, 0.59, 0.46, 0.065),
        (0.12, 0.67, 0.52, 0.085),
    )
    folded_robe('folded ritual robe', robe_rings, cloth)
    oval_rope('robe waist cord', 1.83, 0.34, 0.255, 0.022, rope)
    # Hand-tied waist ends: the two sides are deliberately a little uneven,
    # like a real woven garment assembled from plant fibre.
    for side, length, tilt in ((-1, 0.23, -0.10), (1, 0.19, 0.08)):
        knot = sphere('waist cord knot', (side * 0.37, -0.265, 1.80), 0.036, rope, 10, 6)
        apply_scale(knot, (1.15, 0.72, 0.92))
        detail_torus(
            'waist cord loop',
            (side * 0.39, -0.272, 1.74),
            0.052,
            0.009,
            ochre,
            rotation=(math.radians(90), 0, tilt),
            major_segments=16,
            minor_segments=5,
        )
        curved_tube(
            'waist tassel cord',
            ((side * 0.40, -0.27, 1.71), (side * 0.42, -0.285, 1.61),
             (side * 0.39, -0.27, 1.58 - (0.03 if side < 0 else 0.0))),
            (0.008, 0.007, 0.006),
            rope,
            7,
            0.45,
        )
        sphere('waist tassel bead', (side * 0.39, -0.27, 1.56 - (0.03 if side < 0 else 0.0)),
               0.018, bone, 8, 4)
    for offset in (-14, 0, 14):
        robe_ribbon(
            'woven front stripe',
            robe_rings,
            -math.pi / 2 + math.radians(offset),
            cloth_light,
        )
    for offset in (-42, 42):
        robe_ribbon(
            'blue side robe trim',
            robe_rings,
            -math.pi / 2 + math.radians(offset),
            folk_blue,
            half_width=math.radians(3.2),
        )
    robe_hem(
        'weighted dark robe hem',
        (0.235, 0.635, 0.495, 0.074),
        robe_rings[-1],
        folk_blue,
    )
    for index, x in enumerate((-0.22, -0.11, 0.0, 0.11, 0.22)):
        diamond_plane('waist embroidery', x, -0.252, 1.765, 0.052, 0.062,
                      cloth_light if index % 2 == 0 else folk_blue)
    for index, x in enumerate((-0.42, -0.28, -0.14, 0.0, 0.14, 0.28, 0.42)):
        y = -0.495 * math.sqrt(max(0.0, 1.0 - (x / 0.635) ** 2)) - 0.014
        diamond_plane('hem embroidery', x, y, 0.335, 0.050, 0.064,
                      cloth_light if index % 2 == 0 else folk_blue)
    for side in (-1, 1):
        foot = sphere('straw foot', (side * 0.20, -0.02, 0.075), 0.13, straw_dark, 14, 8)
        apply_scale(foot, (1.20, 1.35, 0.42))

    # Торс собран из двух сужающихся частей — грудь шире плеч, талия уже:
    # раньше это был один прямоугольный блок без силуэта тела под одеждой.
    torso_rings = (
        (1.78, 0.28, 0.20, 0.020),
        (1.95, 0.33, 0.23, 0.012),
        (2.18, 0.38, 0.25, 0.005),
        (2.42, 0.43, 0.27, 0.000),
        (2.60, 0.45, 0.27, 0.004),
        (2.70, 0.38, 0.24, 0.010),
        (2.77, 0.27, 0.20, 0.012),
    )
    ring_body('natural woven torso', torso_rings, straw)
    detail_torus(
        'woven neck collar',
        (0, 0.0, 2.76),
        0.245,
        0.014,
        rope,
        major_segments=24,
        minor_segments=6,
    )
    oval_rope('lower torso binding', 1.96, 0.334, 0.232, 0.013, rope, 0.2)
    oval_rope('mid torso binding', 2.27, 0.398, 0.258, 0.012, rope, 1.1)
    oval_rope('upper torso binding', 2.57, 0.446, 0.272, 0.012, rope, 2.0)
    # Rear reed ribs and a small spine plate make the woven construction read
    # from behind as well; each rib is intentionally slightly off-register.
    for x, drift in ((-0.17, 0.018), (0.0, -0.012), (0.17, 0.010)):
        cone_between(
            'rear reed rib',
            (x, 0.266, 1.99),
            (x + drift, 0.292, 2.60),
            0.012,
            0.009,
            straw_dark,
            6,
        )
    spine_plate = cube(
        'carved rear spine plate',
        (0, 0.296, 2.30),
        (0.105, 0.032, 0.23),
        straw_dark,
        rotation=(0, math.radians(-4), math.radians(2)),
        bevel=0.008,
    )
    diamond_plane('rear ochre spine mark', 0, 0.314, 2.30, 0.040, 0.072, ochre)
    curved_tube(
        'front ritual lashing',
        ((-0.31, -0.225, 2.61), (0, -0.282, 2.31), (0.22, -0.195, 1.96)),
        (0.013, 0.014, 0.012),
        rope,
        10,
        0.62,
    )
    detail_torus(
        'bone chest medallion',
        (0, -0.290, 2.31),
        0.055,
        0.010,
        bone,
        rotation=(math.radians(90), 0, 0),
        major_segments=18,
        minor_segments=6,
    )
    medallion_boss = sphere('ochre medallion boss', (0, -0.306, 2.31), 0.027, ochre, 8, 4)
    apply_scale(medallion_boss, (0.85, 0.45, 1.0))
    curved_tube(
        'front ritual lashing',
        ((0.31, -0.225, 2.61), (0, -0.284, 2.31), (-0.22, -0.195, 1.96)),
        (0.013, 0.014, 0.012),
        rope,
        10,
        0.62,
    )

    # Голова: вытянутый овал вместо идеального шара — так на нём читаются
    # скулы и подбородок, а не просто рисунок лица на мяче.
    curved_tube(
        'small chest flower garland',
        ((-0.34, -0.255, 2.61), (-0.17, -0.286, 2.56),
         (0, -0.296, 2.58), (0.17, -0.286, 2.56), (0.34, -0.255, 2.61)),
        (0.016, 0.018, 0.019, 0.018, 0.016),
        foliage,
        7,
        0.58,
    )
    for flower_index, x in enumerate((-0.25, 0.0, 0.25)):
        ritual_flower('chest garland blossom', (x, -0.312, 2.585),
                      flower_white if flower_index != 1 else flower_blue, 0.66)

    hood = sphere('bound straw hood', (0, 0.13, 3.17), 0.36, straw_dark, 20, 12)
    apply_scale(hood, (0.96, 0.78, 1.06))
    head_rings = (
        (2.72, 0.13, 0.156, 0.000),
        (2.82, 0.27, 0.234, -0.005),
        (3.03, 0.36, 0.281, -0.005),
        (3.25, 0.38, 0.296, 0.000),
        (3.43, 0.33, 0.265, 0.008),
        (3.55, 0.24, 0.218, 0.015),
    )
    ring_body('carved humanoid mask', head_rings, mask)
    for side in (-1, 1):
        eye_socket = sphere('deep eye socket', (side * 0.145, -0.310, 3.22), 0.095, black, 16, 8)
        apply_scale(eye_socket, (0.95, 0.24, 0.55))
        pupil = sphere('ember pupil', (side * 0.145, -0.337, 3.215), 0.031, ember, 12, 7)
        apply_scale(pupil, (0.82, 0.42, 1.0))
        curved_tube(
            'engraved brow',
            (
                (side * 0.255, -0.292, 3.342),
                (side * 0.158, -0.307, 3.327),
                (side * 0.065, -0.312, 3.302),
            ),
            (0.018, 0.019, 0.014),
            brow,
            8,
            0.50,
        )
        curved_tube(
            'carved cheek slash',
            (
                (side * 0.235, -0.325, 3.05),
                (side * 0.205, -0.315, 2.88),
            ),
            (0.018, 0.012),
            cloth_light,
            8,
            0.55,
        )
    nose = custom_mesh(
        'faceted carved nose',
        (
            (-0.047, -0.292, 3.205),
            (0.047, -0.292, 3.205),
            (-0.038, -0.302, 3.060),
            (0.038, -0.302, 3.060),
            (0.000, -0.405, 3.010),
        ),
        ((0, 1, 3, 2), (0, 2, 4), (2, 3, 4), (3, 1, 4), (1, 0, 4)),
        mask,
        smooth=False,
    )
    bevel_object(nose, 0.006, 2)
    curved_tube(
        'carved stern mouth',
        (
            (-0.105, -0.315, 2.885),
            (0, -0.345, 2.918),
            (0.105, -0.315, 2.885),
        ),
        (0.011, 0.013, 0.011),
        black,
        8,
        0.62,
    )
    curved_tube(
        'mask hairline crack',
        (
            (-0.276, -0.298, 3.115),
            (-0.305, -0.312, 3.055),
            (-0.270, -0.310, 2.997),
        ),
        (0.006, 0.0055, 0.0035),
        brow,
        7,
        0.48,
    )
    detail_torus(
        'forehead sun ring',
        (0, -0.273, 3.445),
        0.050,
        0.008,
        ochre,
        rotation=(math.radians(90), 0, 0),
    )
    sun_center = Vector((0, -0.274, 3.445))
    for angle in (0, math.pi / 2, math.pi, 3 * math.pi / 2):
        direction = Vector((math.cos(angle), 0, math.sin(angle)))
        cone_between(
            'forehead sun ray',
            sun_center + direction * 0.064,
            sun_center + direction * 0.092,
            0.006,
            0.004,
            ochre,
            8,
        )
    curved_tube(
        'mask wood grain',
        ((0.265, -0.280, 3.15), (0.292, -0.292, 3.07), (0.270, -0.288, 2.99)),
        (0.0045, 0.004, 0.003),
        brow,
        7,
        0.45,
    )
    curved_tube(
        'mask wood grain',
        ((-0.205, -0.275, 3.39), (-0.180, -0.292, 3.36), (-0.155, -0.298, 3.34)),
        (0.0035, 0.0035, 0.0025),
        brow,
        7,
        0.45,
    )
    # Small ochre pigment dots make the face feel painted by hand rather than
    # procedurally stamped, while remaining almost free in the asset budget.
    for side in (-1, 1):
        for index, z in enumerate((3.05, 3.115)):
            pigment = sphere(
                'ochre face pigment',
                (side * (0.255 - index * 0.018), -0.323, z),
                0.012,
                ochre,
                8,
                4,
            )
            apply_scale(pigment, (0.72, 0.38, 1.0))

    # Руки: плечо уходит вниз и чуть в сторону, а локоть заметно подгибает
    # предплечье вперёд и к центру — раньше оба сегмента шли почти по одной
    # прямой (плечо-локоть-кисть был скорее слегка изломанным шестом, чем
    # согнутой рукой), и от жеста "тянется когтями" ничего не читалось.
    # Каждая сторона задана отдельными точками, а не зеркалом: у настоящего
    # тела руки никогда не висят идеально одинаково.
    arm_specs = (
        (-1, (
            (-0.46, 0.00, 2.58), (-0.51, 0.01, 2.48), (-0.58, 0.045, 2.25),
            (-0.60, 0.040, 2.10), (-0.56, -0.070, 1.92), (-0.49, -0.190, 1.72),
        )),
        (1, (
            (0.46, 0.00, 2.58), (0.52, 0.01, 2.47), (0.59, 0.035, 2.23),
            (0.61, 0.025, 2.08), (0.57, -0.060, 1.91), (0.50, -0.180, 1.71),
        )),
    )
    arm_radii = (0.120, 0.116, 0.103, 0.086, 0.073, 0.052)
    for side, raw_points in arm_specs:
        points = [Vector(point) for point in raw_points]
        shoulder = sphere('soft shoulder bundle', points[0], 0.16, straw_dark, 18, 10)
        apply_scale(shoulder, (1.0, 0.66, 0.77))
        curved_tube('continuous woven arm', points, arm_radii, straw, 14, 0.86)
        elbow = sphere('subtle elbow knot', points[3], 0.074, straw_dark, 14, 8)
        apply_scale(elbow, (0.95, 0.82, 1.04))
        elbow_tangent = (points[4] - points[2]).normalized()
        torus(
            'elbow binding',
            points[3],
            0.090,
            0.008,
            rope,
            rotation=limb_euler(-elbow_tangent),
        )

        wrist = points[-1]
        wrist_tangent = (points[-1] - points[-2]).normalized()
        for offset in (-0.012, 0.012):
            torus(
                'wrist cord',
                wrist + wrist_tangent * offset,
                0.058,
                0.009,
                rope,
                rotation=limb_euler(-wrist_tangent),
            )

        palm = wrist + Vector((-side * 0.006, -0.040, -0.090))
        palm_obj = sphere('small wooden palm', palm, 0.090, straw_dark, 16, 9)
        apply_scale(palm_obj, (0.72, 0.52, 1.06))
        for offset, length_factor in ((-0.047, 0.84), (-0.016, 1.00), (0.017, 0.96), (0.047, 0.80)):
            root = palm + Vector((offset, -0.032, -0.055))
            joint = root + Vector((offset * 0.14, -0.034, -0.060 * length_factor))
            tip = joint + Vector((offset * 0.10, -0.032, -0.050 * length_factor))
            knuckle = sphere('finger knuckle', root, 0.014, straw_dark, 8, 5)
            apply_scale(knuckle, (1.0, 0.88, 1.0))
            cone_between('finger proximal', root, joint, 0.014, 0.009, straw_dark, 10)
            finger_joint = sphere('finger joint', joint, 0.011, straw_dark, 8, 5)
            apply_scale(finger_joint, (1.0, 0.88, 1.0))
            cone_between('finger distal', joint, tip, 0.010, 0.004, straw_dark, 10)

        thumb_root = palm + Vector((-side * 0.052, -0.004, -0.006))
        thumb_joint = thumb_root + Vector((-side * 0.050, -0.030, -0.025))
        thumb_tip = thumb_joint + Vector((-side * 0.036, -0.026, -0.040))
        thumb_knuckle = sphere('thumb knuckle', thumb_root, 0.016, straw_dark, 8, 5)
        apply_scale(thumb_knuckle, (1.0, 0.88, 1.0))
        cone_between('thumb proximal', thumb_root, thumb_joint, 0.016, 0.010, straw_dark, 10)
        thumb_bend = sphere('thumb joint', thumb_joint, 0.012, straw_dark, 8, 5)
        apply_scale(thumb_bend, (1.0, 0.88, 1.0))
        cone_between('thumb distal', thumb_joint, thumb_tip, 0.011, 0.0045, straw_dark, 10)

    # Венец: у каждой стороны своя длина и угол веток — правильная симметрия
    # читалась как антенны, а не как ломаные берёзовые прутья.
    crown_specs = (
        (-1, (
            (-0.15, 0.13, 3.46), (-0.23, 0.12, 3.70),
            (-0.31, 0.07, 3.94), (-0.42, 0.03, 4.14),
        )),
        (1, (
            (0.15, 0.13, 3.46), (0.24, 0.15, 3.72),
            (0.32, 0.18, 3.97), (0.44, 0.11, 4.16),
        )),
    )
    for side, raw_points in crown_specs:
        points = [Vector(point) for point in raw_points]
        radii = ((0.058, 0.050), (0.050, 0.039), (0.039, 0.024))
        for index, (start, end) in enumerate(zip(points, points[1:])):
            cone_between(
                'crown main branch',
                start,
                end,
                radii[index][0],
                radii[index][1],
                straw_dark,
                12,
            )
            if index < 2:
                knot = sphere(
                    'crown branch knot',
                    end,
                    radii[index][1] * 1.12,
                    straw_dark,
                    12,
                    7,
                )
                apply_scale(knot, (1.0, 0.92, 1.0))
        outer_a = Vector((side * 0.49, -0.015, 3.91 if side < 0 else 3.95))
        outer_b = Vector((side * 0.57, 0.16 if side > 0 else -0.06, 4.13 if side < 0 else 4.18))
        inner = Vector((side * 0.10, -0.06, 3.96 if side < 0 else 4.00))
        cone_between('crown lower tine', points[1], outer_a, 0.037, 0.018, straw_dark, 10)
        cone_between('crown upper tine', points[2], outer_b, 0.031, 0.014, straw_dark, 10)
        cone_between('bone inner tine', points[1], inner, 0.030, 0.012, bone, 10)
        root_tangent = (points[1] - points[0]).normalized()
        detail_torus(
            'crown root binding',
            points[0] + root_tangent * 0.055,
            0.065,
            0.010,
            rope,
            rotation=limb_euler(-root_tangent),
        )

    for ribbon_index, ribbon_points in enumerate((
        ((-0.31, 0.07, 3.94), (-0.29, -0.015, 3.80), (-0.32, -0.035, 3.68)),
        ((0.33, 0.18, 3.97), (0.39, 0.08, 3.84), (0.38, 0.03, 3.72)),
        ((0.49, -0.015, 3.94), (0.53, -0.06, 3.81), (0.51, -0.08, 3.70)),
    )):
        curved_tube(
            'crown cloth ribbon',
            ribbon_points,
            (0.013, 0.012, 0.009),
            cloth_light if ribbon_index % 2 == 0 else folk_blue,
            8,
            0.48,
        )

    # A living flower crown replaces the generic antler silhouette with a
    # recognisable midsummer festival shape, while the twigs keep it uncanny.
    curved_tube(
        'living flower crown vine',
        ((-0.34, -0.25, 3.48), (-0.18, -0.29, 3.54), (0, -0.305, 3.57),
         (0.18, -0.29, 3.54), (0.34, -0.25, 3.48)),
        (0.025, 0.028, 0.030, 0.028, 0.025),
        foliage,
        7,
        0.60,
    )
    for flower_index, (x, z) in enumerate(((-0.30, 3.50), (-0.15, 3.56),
                                            (0, 3.585), (0.16, 3.55), (0.30, 3.49))):
        ritual_flower('flower crown blossom', (x, -0.326, z),
                      flower_white if flower_index % 2 == 0 else flower_blue,
                      0.82 if flower_index != 2 else 0.94)
    for side in (-1, 1):
        for x, y, z, tilt in (
            (side * 0.26, 0.105, 3.76, side * 0.20),
            (side * 0.36, 0.075, 3.98, -side * 0.18),
            (side * 0.50, 0.015, 4.10, side * 0.12),
        ):
            leaf = sphere('crown birch leaf', (x, y, z), 0.046, foliage, 7, 4)
            apply_scale(leaf, (1.25, 0.42, 0.66))
            leaf.rotation_euler.z = tilt
        ritual_flower('crown tip flower', (side * 0.52, -0.035, 4.10),
                      flower_blue if side < 0 else flower_white, 0.78)

    for side in (-1, 1):
        cylinder('lowered charm cord', (side * 0.48, -0.28, 1.42), 0.012, 0.34, rope, 10)
        torus(
            'lowered bone charm',
            (side * 0.48, -0.30, 1.18),
            0.085,
            0.018,
            bone,
            rotation=(math.radians(90), 0, 0),
        )

    # The solar halo sits clear of the torso and is held by four short
    # stand-offs.  Its outer ring is now a living wreath over a forged frame:
    # pastoral in daylight, unnerving once the eyes and shadows take over.
    halo_center = Vector((0, 0.42, 2.72))
    torus(
        'ritual sun halo',
        halo_center,
        0.72,
        0.035,
        foliage,
        rotation=(math.radians(90), 0, 0),
    )
    detail_torus(
        'ochre inner sun ring',
        halo_center + Vector((0, -0.006, 0)),
        0.47,
        0.018,
        ochre,
        rotation=(math.radians(90), 0, 0),
        major_segments=28,
        minor_segments=6,
    )
    for index in range(12):
        angle = math.tau * index / 12
        inner = halo_center + Vector((math.cos(angle) * 0.48, 0, math.sin(angle) * 0.48))
        outer = halo_center + Vector((math.cos(angle) * 0.68, 0, math.sin(angle) * 0.68))
        cone_between('sun ray spoke', inner, outer, 0.012, 0.008, ochre, 6)
        ray_length = 0.88 if index % 3 == 0 else 0.82
        ray_root = halo_center + Vector((math.cos(angle) * 0.745, 0, math.sin(angle) * 0.745))
        ray_tip = halo_center + Vector((math.cos(angle) * ray_length, 0, math.sin(angle) * ray_length))
        cone_between(
            'outer sun ray',
            ray_root,
            ray_tip,
            0.032 if index % 3 == 0 else 0.024,
            0.004,
            bone if index % 2 == 0 else ochre,
            6,
        )
    for side in (-1, 1):
        for z, x in ((2.56, 0.31), (2.22, 0.23)):
            start = Vector((side * x, 0.225, z))
            end = Vector((side * x, 0.405, z))
            cone_between('halo stand-off', start, end, 0.021, 0.018, iron, 10)
            front_rivet = sphere('halo mounting rivet', start, 0.034, iron, 8, 4)
            apply_scale(front_rivet, (0.86, 0.52, 0.86))
            back_rivet = sphere('halo mounting rivet', end, 0.031, iron, 8, 4)
            apply_scale(back_rivet, (0.82, 0.52, 0.82))
    for binding_index, angle in enumerate((
        math.radians(45),
        math.radians(135),
        math.radians(225),
        math.radians(315),
    )):
        point = halo_center + Vector((math.cos(angle) * 0.72, 0, math.sin(angle) * 0.72))
        tangent = Vector((-math.sin(angle), 0, math.cos(angle)))
        detail_torus(
            'painted halo binding',
            point,
            0.044,
            0.008,
            cloth_light if binding_index % 2 == 0 else folk_blue,
            rotation=limb_euler(-tangent),
        )
    for flower_index, angle in enumerate((math.radians(20), math.radians(64),
                                          math.radians(116), math.radians(160),
                                          math.radians(205), math.radians(335))):
        point = halo_center + Vector((math.cos(angle) * 0.735, -0.020,
                                     math.sin(angle) * 0.735))
        ritual_flower('halo wreath blossom', point,
                      flower_white if flower_index % 2 == 0 else flower_blue, 0.74)
    for side in (-1, 1):
        curved_tube(
            'halo harness strap',
            (
                (side * 0.32, 0.225, 2.63),
                (side * 0.28, 0.270, 2.33),
                (side * 0.22, 0.225, 1.96),
            ),
            (0.015, 0.014, 0.013),
            rope,
            8,
            0.65,
        )
    export('guardian')


def make_seal():
    clear()
    gold = material('sun brass', (0.93, 0.52, 0.06), 0.35, 0.35, (1.0, 0.28, 0.01))
    dark = material('carved wood', (0.21, 0.07, 0.025))
    torus('sun ring', (0, 0, 0.15), 0.46, 0.09, gold, rotation=(math.radians(90), 0, 0))
    cylinder('wood core', (0, 0, 0.15), 0.31, 0.10, dark, 16, rotation=(math.radians(90), 0, 0))
    sphere('sun centre boss', (0, -0.09, 0.15), 0.14, gold, 12, 6)
    for i in range(8):
        a = i * math.tau / 8
        cube('sun ray', (math.cos(a) * 0.68, 0, 0.15 + math.sin(a) * 0.68), (0.28, 0.08, 0.08), gold, rotation=(0, -a, 0))
    for i in range(4):
        a = math.pi / 4 + i * math.pi / 2
        sphere('seal rivet', (math.cos(a) * 0.31, -0.075, 0.15 + math.sin(a) * 0.31), 0.045, gold, 8, 4)
    export('sun_seal')


def make_gate_legacy():
    clear()
    wood = material('blackened oak', (0.15, 0.075, 0.025))
    gold = material('sun paint', (0.95, 0.58, 0.08), 0.7, 0.0, (0.6, 0.18, 0.01))
    stone = material('gate foundation stones', (0.29, 0.31, 0.27), 0.99)
    rope = material('gate rope', (0.42, 0.27, 0.09), 0.96)
    for x in (-2.4, 2.4):
        cylinder('gate footing', (x, 0, 0.26), 0.52, 0.52, stone, 10)
        cylinder('gate post', (x, 0, 2.4), 0.24, 4.8, wood, 10)
        cone('post cap', (x, 0, 5.0), 0.48, 0.0, 0.55, gold, 8)
        torus('post rope binding', (x, 0, 3.70), 0.29, 0.045, rope)
    cube('lintel', (0, 0, 4.35), (5.3, 0.35, 0.38), wood, bevel=0.06)
    cube('upper carved lintel', (0, 0, 4.83), (4.55, 0.24, 0.20), gold, bevel=0.04)
    for x, tilt in ((-1.55, -24), (1.55, 24)):
        cylinder('gate diagonal brace', (x, 0, 3.65), 0.08, 2.20, wood, 8,
                 rotation=(0, math.radians(tilt), 0))
    torus('gate sun', (0, 0, 4.35), 0.72, 0.10, gold, rotation=(math.radians(90), 0, 0))
    sphere('gate sun centre', (0, -0.13, 4.35), 0.22, gold, 12, 6)
    for x in (-1.35, 1.35):
        cone('hanging ritual bell', (x, 0, 4.0), 0.16, 0.08, 0.30, gold, 10)
        cylinder('bell cord', (x, 0, 4.24), 0.025, 0.30, rope, 6)
    export('ritual_gate')


def make_gate():
    clear()
    oak = material('sun bleached birch gate', (0.53, 0.39, 0.20), 0.96)
    oak_light = material('whitewashed carved wood', (0.78, 0.69, 0.48), 0.94)
    iron = material('aged hand forged iron', (0.12, 0.060, 0.030), 0.78, 0.38)
    ochre = material('gate sun ochre', (0.88, 0.28, 0.020), 0.87)
    blue = material('folk blue gate paint', (0.11, 0.25, 0.42), 0.91)
    bone = material('pale ancestor carving', (0.77, 0.71, 0.55), 0.92)
    stone = material('pale gate fieldstone', (0.35, 0.36, 0.30), 0.99)
    stone_light = material('sun worn stone face', (0.54, 0.51, 0.40), 0.98)
    rope = material('gate hemp lashings', (0.31, 0.18, 0.055), 0.99)
    red = material('festival vermilion binding', (0.58, 0.025, 0.012), 0.96)
    red_light = material('faded cinnabar embroidery', (0.74, 0.080, 0.025), 0.93)
    linen = material('sun festival linen', (0.83, 0.77, 0.62), 0.97)
    foliage = material('birch garland leaves', (0.20, 0.37, 0.095), 0.98)
    flower_white = material('midsummer white petals', (0.92, 0.90, 0.72), 0.95)
    flower_yellow = material('midsummer flower centres', (0.95, 0.56, 0.045), 0.88)

    # Threshold and clustered foundations give the gate real weight at ground level.
    for index, x in enumerate((-1.55, -0.78, 0.0, 0.78, 1.55)):
        slab = cube('ritual threshold slab', (x, -0.03 * (index % 2), 0.10),
                    (0.72, 0.75, 0.20 + 0.025 * (index % 3)),
                    stone_light if index == 2 else stone,
                    rotation=(0, math.radians((index % 3 - 1) * 3), math.radians((index % 2) * 4 - 2)),
                    bevel=0.035)
    for side in (-1, 1):
        x = side * 2.42
        footing = cylinder('rough gate footing', (x, 0, 0.23), 0.62, 0.46,
                           stone, 9, rotation=(0, 0, math.radians(side * 8)), smooth=False)
        apply_scale(footing, (1.0, 0.82, 1.0))
        for angle, scale in ((0.35, 0.19), (2.40, 0.16), (4.55, 0.18)):
            rock = sphere('gate footing rubble',
                          (x + math.cos(angle) * 0.48, math.sin(angle) * 0.38, 0.28),
                          scale, stone_light, 9, 5)
            apply_scale(rock, (1.25, 0.85, 0.72))
            for polygon in rock.data.polygons:
                polygon.use_smooth = False

        # Slightly leaning, irregular hand-hewn post.
        rings = (
            (0.38, 0.00, 0.00, 0.32, 0.27, 0.00),
            (1.20, side * 0.012, 0.008, 0.29, 0.24, 0.11),
            (2.25, -side * 0.018, -0.005, 0.27, 0.23, 0.22),
            (3.35, side * 0.022, 0.006, 0.255, 0.215, 0.34),
            (4.35, -side * 0.028, -0.004, 0.245, 0.205, 0.46),
            (4.86, -side * 0.045, 0.008, 0.225, 0.19, 0.56),
        )
        vertices = []
        segments = 10
        for z, dx, dy, rx, ry, twist in rings:
            for index in range(segments):
                angle = math.tau * index / segments + twist
                irregular = 1.0 + 0.028 * math.sin(angle * 3.0 + z + side)
                vertices.append((x + dx + math.cos(angle) * rx * irregular,
                                 dy + math.sin(angle) * ry * irregular, z))
        faces = []
        for ring_index in range(len(rings) - 1):
            for index in range(segments):
                nxt = (index + 1) % segments
                a = ring_index * segments
                b = (ring_index + 1) * segments
                faces.append((a + index, a + nxt, b + nxt, b + index))
        custom_mesh('hand hewn gate post', vertices, faces, oak)
        for z in (1.30, 3.52, 4.30):
            detail_torus('post rope lashing', (x, 0, z), 0.285, 0.027, rope,
                         major_segments=20, minor_segments=6)
        for z, tilt in ((2.05, side * 0.12), (2.72, -side * 0.15)):
            cube('post folk painted stroke', (x, -0.235, z), (0.105, 0.020, 0.23),
                 blue, rotation=(0, 0, tilt), bevel=0.005)
            diamond_plane('post vermilion rune', x, -0.248, z, 0.048, 0.075, red_light)

        # Forked ancestor finials replace the generic triangular caps.
        root = Vector((x - side * 0.03, 0, 4.78))
        outer = Vector((x + side * 0.38, 0.03, 5.48))
        inner = Vector((x - side * 0.30, -0.02, 5.36))
        cone_between('forked oak gate finial', root, outer, 0.115, 0.028, oak_light, 9)
        cone_between('bone gate finial tine', root + Vector((0, -0.02, 0.10)),
                     inner, 0.080, 0.018, bone, 8)
        detail_torus('finial red binding', root + Vector((0, 0, 0.13)),
                     0.12, 0.018, red, major_segments=16, minor_segments=5)

    # Layered lintel and braces retain a 4.2 m clear gameplay passage.
    cube('massive lower gate lintel', (0, 0, 4.38), (5.45, 0.42, 0.46),
         oak, bevel=0.075)
    cube('carved upper gate lintel', (0, -0.015, 4.88), (5.05, 0.30, 0.24),
         oak_light, bevel=0.045)
    cone_between('left sloped crown beam', (-2.55, 0.02, 4.94), (0, 0.02, 5.28),
                 0.14, 0.11, oak, 9)
    cone_between('right sloped crown beam', (2.55, 0.02, 4.94), (0, 0.02, 5.28),
                 0.14, 0.11, oak, 9)
    for side in (-1, 1):
        cone_between('tapered gate brace', (side * 2.20, 0.02, 3.18),
                     (side * 1.32, 0.02, 4.30), 0.095, 0.070, oak_light, 8)
        detail_torus('brace binding', (side * 1.50, 0.02, 4.08),
                     0.095, 0.014, rope, rotation=(0, math.radians(38 * side), 0),
                     major_segments=16, minor_segments=5)

    # Central forged sun seal with teeth, layered rings and a bone boss.
    sun_center = Vector((0, -0.27, 4.48))
    torus('forged gate sun ring', sun_center, 0.76, 0.075, iron,
          rotation=(math.radians(90), 0, 0))
    detail_torus('ochre gate sun ring', sun_center + Vector((0, -0.018, 0)),
                 0.43, 0.040, ochre, rotation=(math.radians(90), 0, 0),
                 major_segments=24, minor_segments=6)
    disk = cylinder('gate ancestor sun disk', (0, -0.35, 4.48), 0.22, 0.070,
                    bone, 12, rotation=(math.radians(90), 0, 0))
    for index in range(8):
        angle = math.tau * index / 8
        direction = Vector((math.cos(angle), 0, math.sin(angle)))
        cone_between('gate sun spoke', sun_center + direction * 0.46,
                     sun_center + direction * 0.70, 0.022, 0.012,
                     bone if index % 2 == 0 else blue, 6)
        cone_between('gate sun tooth', sun_center + direction * 0.80,
                     sun_center + direction * (0.94 if index % 2 == 0 else 0.89),
                     0.035, 0.004, ochre, 6)

    # Bells and long cloth strips introduce controlled asymmetry and motion.
    for x, z, drop in ((-1.42, 4.18, 0.42), (0.92, 4.20, 0.34), (1.58, 4.12, 0.48)):
        curved_tube('gate bell cord', ((x, -0.20, z + 0.22), (x + 0.025, -0.24, z),
                    (x - 0.018, -0.22, z - drop * 0.35)),
                    (0.012, 0.010, 0.008), rope, 7, 0.44)
        cone('ancestor bell', (x - 0.018, -0.22, z - drop * 0.35 - 0.13),
             0.115, 0.055, 0.22, bone, 9)
        sphere('bell clapper', (x - 0.018, -0.22, z - drop * 0.35 - 0.27),
               0.032, iron, 8, 4)
    cloth_strip('left gate linen banner', ((-1.92, -0.18, 4.48), (-2.02, -0.22, 4.12),
                (-1.91, -0.20, 3.75), (-2.08, -0.17, 3.35), (-1.96, -0.15, 2.95)),
                0.18, 0.028, linen)
    cloth_strip('left banner red embroidery', ((-1.92, -0.198, 4.47), (-2.02, -0.238, 4.11),
                (-1.91, -0.218, 3.74), (-2.08, -0.188, 3.34), (-1.96, -0.168, 2.96)),
                0.045, 0.010, red)
    cloth_strip('right gate linen banner', ((1.93, -0.16, 4.45), (2.04, -0.20, 4.10),
                (1.94, -0.18, 3.78), (2.10, -0.15, 3.46)),
                0.16, 0.026, linen)
    cloth_strip('right banner blue embroidery', ((1.93, -0.178, 4.44), (2.04, -0.218, 4.09),
                (1.94, -0.198, 3.77), (2.10, -0.168, 3.47)),
                0.040, 0.010, blue)

    # Bright midsummer garland: pretty at first glance, unsettling against the
    # black iron and ancestor bells when the light changes.
    curved_tube('leaf garland over gate', ((-2.32, -0.25, 4.98), (-1.25, -0.29, 5.12),
                (0, -0.31, 5.27), (1.25, -0.29, 5.12), (2.32, -0.25, 4.98)),
                (0.045, 0.050, 0.052, 0.050, 0.045), foliage, 8, 0.58)
    for flower_index, (x, z) in enumerate(((-2.02, 5.02), (-1.02, 5.16),
                                           (0, 5.29), (1.02, 5.16), (2.02, 5.02))):
        sphere('flower gold centre', (x, -0.335, z), 0.050, flower_yellow, 8, 4)
        petal_mat = flower_white if flower_index % 2 == 0 else blue
        for petal_index in range(5):
            petal_angle = math.tau * petal_index / 5
            petal = sphere('gate garland petal',
                           (x + math.cos(petal_angle) * 0.075, -0.325,
                            z + math.sin(petal_angle) * 0.075),
                           0.055, petal_mat, 8, 4)
            apply_scale(petal, (1.15, 0.45, 0.72))
    export('ritual_gate')


def make_gate_door():
    """One mirrored leaf for the playable exit gate, with its origin at the hinge."""
    clear()
    birch = material('whitewashed birch door', (0.67, 0.55, 0.34), 0.96)
    birch_light = material('sun bleached door carving', (0.84, 0.76, 0.58), 0.94)
    wicker = material('woven hazel door', (0.43, 0.29, 0.13), 0.98)
    iron = material('forged door iron', (0.11, 0.055, 0.025), 0.78, 0.36)
    linen = material('festival door linen', (0.86, 0.81, 0.67), 0.98)
    red = material('vermilion door paint', (0.66, 0.030, 0.014), 0.94)
    blue = material('folk blue door paint', (0.10, 0.25, 0.43), 0.93)
    yellow = material('midsummer door ochre', (0.94, 0.55, 0.035), 0.87)
    green = material('door garland leaves', (0.19, 0.36, 0.085), 0.98)
    white = material('door daisy petals', (0.94, 0.92, 0.76), 0.96)

    # A pale linen backing makes the entrance unmistakably closed, while the
    # exposed hazel lattice keeps it handmade rather than fortress-like.
    cube('door linen backing', (1.00, 0.075, 1.93), (1.58, 0.035, 2.86),
         linen, bevel=0.018)
    for x, height, tilt in ((0.12, 3.48, -0.8), (1.88, 3.36, 0.9)):
        cube('door hand hewn stile', (x, 0, 1.86), (0.22, 0.22, height),
             birch, rotation=(0, math.radians(tilt), 0), bevel=0.035)
    for z, thickness in ((0.33, 0.20), (1.78, 0.16), (3.38, 0.19)):
        cube('door cross rail', (1.00, -0.015, z), (1.88, 0.20, thickness),
             birch_light, rotation=(0, 0, math.radians(0.7 if z < 2.0 else -0.9)),
             bevel=0.030)

    for index, x in enumerate((0.36, 0.62, 0.88, 1.14, 1.40, 1.66)):
        cylinder('split hazel upright', (x, 0.025 + 0.012 * (index % 2), 1.89),
                 0.038, 2.82 + 0.05 * (index % 3), wicker, 6,
                 rotation=(0, math.radians((index % 3 - 1) * 1.3), 0), smooth=False)
    for index, z in enumerate((0.60, 0.86, 1.12, 1.38, 2.16, 2.43, 2.70, 2.97, 3.20)):
        cube('woven hazel band', (1.00, -0.082 - 0.012 * (index % 2), z),
             (1.55, 0.075, 0.075), wicker,
             rotation=(0, 0, math.radians(1.2 if index % 2 else -1.0)), bevel=0.018)
    cone_between('door diagonal brace', (0.23, -0.125, 0.48), (1.76, -0.125, 3.20),
                 0.080, 0.060, birch, 8)

    # Forged hinge straps stay near x=0, so the leaf pivots convincingly in game.
    for z in (0.66, 2.96):
        cube('forged hinge strap', (0.34, -0.145, z), (0.64, 0.055, 0.105),
             iron, bevel=0.018)
        detail_torus('hinge pin collar', (0.035, -0.145, z), 0.085, 0.022, iron,
                     rotation=(0, math.radians(90), 0), major_segments=14, minor_segments=5)

    # Painted solar rosette: cheerful midsummer craft at first glance, a ward
    # when the two leaves meet and repeat the symbol across the passage.
    sun = Vector((1.00, -0.175, 1.83))
    detail_torus('painted door sun ring', sun, 0.42, 0.044, blue,
                 rotation=(math.radians(90), 0, 0), major_segments=24, minor_segments=6)
    cylinder('painted door sun centre', (sun.x, sun.y - 0.035, sun.z), 0.15, 0.035,
             yellow, 12, rotation=(math.radians(90), 0, 0))
    for index in range(8):
        angle = math.tau * index / 8
        direction = Vector((math.cos(angle), 0, math.sin(angle)))
        cone_between('painted door sun ray', sun + direction * 0.20,
                     sun + direction * 0.36, 0.026, 0.008,
                     red if index % 2 == 0 else blue, 6)

    # Centre handles and a small flower garland make the locked entrance read
    # clearly from gameplay distance without needing textures.
    detail_torus('ritual door pull', (1.70, -0.185, 1.44), 0.105, 0.026, iron,
                 rotation=(math.radians(90), 0, 0), major_segments=16, minor_segments=5)
    curved_tube('door flower garland', ((0.24, -0.17, 3.45), (0.66, -0.20, 3.34),
                (1.08, -0.21, 3.42), (1.52, -0.19, 3.31), (1.84, -0.17, 3.39)),
                (0.032, 0.036, 0.038, 0.035, 0.030), green, 7, 0.55)
    for x, z, petal_mat in ((0.48, 3.38, white), (1.05, 3.42, blue), (1.60, 3.34, white)):
        sphere('door flower centre', (x, -0.225, z), 0.042, yellow, 8, 4)
        for petal_index in range(5):
            angle = math.tau * petal_index / 5
            petal = sphere('door flower petal',
                           (x + math.cos(angle) * 0.060, -0.218,
                            z + math.sin(angle) * 0.060),
                           0.044, petal_mat, 8, 4)
            apply_scale(petal, (1.12, 0.42, 0.72))
    export('ritual_gate_door')


def make_totem_legacy():
    clear()
    wood = material('peeled birch', (0.77, 0.68, 0.47))
    wood_dark = material('charred birch marks', (0.20, 0.14, 0.075), 0.98)
    red = material('red ribbons', (0.58, 0.02, 0.015))
    red_dark = material('shadowed red cloth', (0.25, 0.012, 0.008), 0.98)
    gold = material('totem gold', (0.92, 0.53, 0.08), 0.58, 0.12)
    ochre = material('altar ochre paint', (0.86, 0.30, 0.035), 0.88)
    rope = material('altar hemp bindings', (0.33, 0.21, 0.075), 0.98)
    stone = material('totem base stone', (0.30, 0.31, 0.25), 0.99)
    stone_light = material('worn altar stone', (0.43, 0.42, 0.33), 0.98)
    cylinder('totem stone base', (0, 0, 0.24), 0.72, 0.48, stone, 12)
    cylinder('totem lower altar step', (0, 0, 0.51), 0.60, 0.12, stone_light, 12)
    cylinder('totem upper altar step', (0, 0, 0.62), 0.46, 0.10, stone, 10)
    for angle in (0, math.radians(90), math.radians(180), math.radians(270)):
        x, y = math.cos(angle) * 0.52, math.sin(angle) * 0.52
        cube('altar corner offering stone', (x, y, 0.72), (0.18, 0.18, 0.16), stone_light,
             rotation=(0, 0, angle + math.radians(12)), bevel=0.015)
    for x, z, angle in ((-0.12, 0.31, -0.18), (0.08, 0.46, 0.12), (0.18, 0.68, -0.10)):
        cube('altar stone chisel mark', (x, -0.705, z), (0.16, 0.018, 0.035), wood_dark,
             rotation=(0, 0, angle))
    cylinder('totem pole', (0, 0, 2.7), 0.18, 5.4, wood, 10)
    for z, tilt in ((1.35, -0.08), (2.08, 0.06), (2.76, -0.04)):
        detail_torus('pole hemp binding', (0, 0, z), 0.185, 0.018, rope,
                     major_segments=20, minor_segments=6)
        cube('pole ochre slash', (0, -0.185, z + 0.08), (0.11, 0.018, 0.028), ochre,
             rotation=(0, 0, tilt))
    for z, angle in ((1.10, -0.20), (1.72, 0.16), (2.34, -0.12), (2.95, 0.18)):
        cube('carved pole rune', (0, -0.184, z), (0.075, 0.020, 0.16), wood_dark,
             rotation=(0, 0, angle), bevel=0.006)
    torus('sun wheel', (0, 0, 4.2), 1.2, 0.10, red, rotation=(math.radians(90), 0, 0))
    torus('inner sun wheel', (0, -0.02, 4.2), 0.50, 0.065, gold, rotation=(math.radians(90), 0, 0))
    sphere('sun wheel boss', (0, -0.10, 4.2), 0.20, gold, 12, 6)
    detail_torus('sun boss binding', (0, -0.105, 4.2), 0.235, 0.014, rope,
                 rotation=(math.radians(90), 0, 0), major_segments=20, minor_segments=6)
    for i in range(12):
        a = i * math.tau / 12
        spoke_mat = red if i % 2 == 0 else ochre
        cube('wheel spoke', (math.cos(a) * 0.56, 0, 4.2 + math.sin(a) * 0.56),
             (1.08, 0.075, 0.075), spoke_mat, rotation=(0, -a, 0), bevel=0.006)
    for a in (0, math.radians(90), math.radians(180), math.radians(270)):
        diamond_plane('sun wheel cardinal mark', math.cos(a) * 0.88, -0.115,
                      4.2 + math.sin(a) * 0.88, 0.10, 0.16, gold)
    for z in (1.4, 2.0, 2.6):
        cube('ribbon', (0.42, 0, z), (0.85, 0.06, 0.10), red, rotation=(0, 0, math.radians(12)), bevel=0.008)
    for x in (-0.66, 0.66):
        cube('hanging long ribbon', (x, 0, 3.22), (0.12, 0.05, 1.18), red,
             rotation=(0, 0, math.radians(x * 9)), bevel=0.012)
        sphere('ribbon bead', (x, 0, 2.62), 0.09, gold, 8, 4)
        curved_tube('ribbon tie cord', ((x * 0.72, -0.02, 3.80), (x, -0.04, 3.58),
                                        (x * 1.02, -0.02, 3.42)),
                    (0.010, 0.008, 0.007), rope, 7, 0.42)
    for x, z in ((-0.52, 1.12), (0.58, 1.33)):
        sphere('offering bead', (x, -0.23, z), 0.055, gold, 8, 4)
        cylinder('offering cord', (x, -0.17, z + 0.18), 0.012, 0.34, rope, 8)
    export('sun_totem')


def make_totem():
    clear()
    wood = material('weathered birch altar', (0.66, 0.52, 0.30), 0.94)
    wood_dark = material('charred carvings', (0.13, 0.075, 0.035), 0.99)
    red = material('madder red votive cloth', (0.46, 0.018, 0.012), 0.96)
    red_light = material('worn cinnabar cloth', (0.72, 0.065, 0.025), 0.92)
    ochre = material('sun ochre paint', (0.90, 0.31, 0.025), 0.86)
    rope = material('altar hemp bindings', (0.31, 0.19, 0.065), 0.99)
    iron = material('blackened ritual iron', (0.095, 0.045, 0.025), 0.76, 0.42)
    bone = material('old offering bone', (0.71, 0.65, 0.47), 0.90)
    ember = material('altar ember coals', (0.58, 0.018, 0.004), 0.46, 0.0,
                     (1.0, 0.025, 0.003))
    stone = material('altar fieldstone', (0.26, 0.27, 0.23), 0.99)
    stone_light = material('worn altar edge', (0.43, 0.40, 0.31), 0.98)

    # Broad, irregular offering platform instead of a manufactured pedestal.
    lower = cylinder('rough altar foundation', (0, 0, 0.20), 0.84, 0.40, stone, 10,
                     rotation=(0, 0, math.radians(7)), smooth=False)
    apply_scale(lower, (1.0, 0.84, 1.0))
    middle = cylinder('worn altar slab', (0.02, -0.01, 0.45), 0.67, 0.18,
                      stone_light, 9, rotation=(0, 0, math.radians(-9)), smooth=False)
    apply_scale(middle, (1.0, 0.82, 1.0))
    upper = cylinder('charred offering ledge', (-0.01, 0.0, 0.61), 0.48, 0.16,
                     stone, 8, rotation=(0, 0, math.radians(10)), smooth=False)
    apply_scale(upper, (1.0, 0.80, 1.0))
    for angle, radius, size in ((0.30, 0.60, 0.17), (2.10, 0.57, 0.14),
                                (3.65, 0.61, 0.16), (5.15, 0.55, 0.13)):
        cube('loose offering stone', (math.cos(angle) * radius, math.sin(angle) * radius, 0.60),
             (size * 1.35, size, size * 0.75), stone_light,
             rotation=(0, math.radians(8), angle), bevel=0.018)
    # A shallow iron offering bowl makes the object read as an altar at ground
    # level and catches the warm light already supplied by the game scene.
    cylinder('offering bowl tray', (0, -0.54, 0.78), 0.25, 0.055, iron, 12,
             rotation=(0, 0, 0), smooth=False)
    detail_torus('offering bowl rim', (0, -0.54, 0.815), 0.235, 0.038, iron,
                 major_segments=24, minor_segments=6)
    for x, y, radius in ((-0.10, -0.55, 0.055), (0.02, -0.58, 0.065),
                         (0.11, -0.51, 0.048), (-0.02, -0.48, 0.045)):
        coal = sphere('glowing offering coal', (x, y, 0.84), radius, ember, 8, 4)
        apply_scale(coal, (1.15, 0.85, 0.65))

    # Hand-hewn birch pole with a subtle bend, taper and changing cross-section.
    pole_rings = (
        (0.62, 0.00, 0.00, 0.23, 0.18, 0.00),
        (1.25, -0.025, 0.008, 0.21, 0.17, 0.10),
        (2.05, 0.020, -0.006, 0.195, 0.16, 0.20),
        (2.85, -0.018, 0.006, 0.185, 0.15, 0.31),
        (3.65, 0.012, -0.004, 0.18, 0.145, 0.40),
        (4.55, -0.010, 0.010, 0.17, 0.14, 0.50),
        (5.30, 0.005, 0.018, 0.145, 0.125, 0.58),
    )
    vertices = []
    segments = 12
    for z, xoff, yoff, rx, ry, twist in pole_rings:
        for index in range(segments):
            angle = math.tau * index / segments + twist
            irregular = 1.0 + 0.035 * math.sin(angle * 3.0 + z)
            vertices.append((xoff + math.cos(angle) * rx * irregular,
                             yoff + math.sin(angle) * ry * irregular, z))
    faces = []
    for ring_index in range(len(pole_rings) - 1):
        for index in range(segments):
            next_index = (index + 1) % segments
            a = ring_index * segments
            b = (ring_index + 1) * segments
            faces.append((a + index, a + next_index, b + next_index, b + index))
    custom_mesh('hand hewn birch pillar', vertices, faces, wood)

    for z in (1.22, 2.05, 2.82, 3.48):
        detail_torus('hemp pole binding', (0, 0, z), 0.198, 0.017, rope,
                     major_segments=20, minor_segments=6)
    for x, z, angle in ((-0.035, 1.58, -0.16), (0.045, 2.40, 0.13),
                        (-0.025, 3.12, -0.10)):
        cube('deep carved pole rune', (x, -0.171, z), (0.080, 0.018, 0.18),
             wood_dark, rotation=(0, 0, angle), bevel=0.005)
        diamond_plane('ochre rune centre', x, -0.182, z, 0.035, 0.060, ochre)

    # Forged sun: tapered spokes and exterior points produce a sacred solar
    # silhouette rather than a cart wheel.
    sun_center = Vector((0, -0.01, 4.22))
    torus('black iron sun frame', sun_center, 1.16, 0.085, iron,
          rotation=(math.radians(90), 0, 0))
    detail_torus('red wrapped sun rim', sun_center + Vector((0, -0.015, 0)),
                 1.16, 0.042, red, rotation=(math.radians(90), 0, 0),
                 major_segments=36, minor_segments=7)
    detail_torus('inner ochre sun ring', sun_center + Vector((0, -0.035, 0)),
                 0.45, 0.052, ochre, rotation=(math.radians(90), 0, 0),
                 major_segments=24, minor_segments=7)
    cylinder('carved sun disk', (0, -0.105, 4.22), 0.255, 0.075, bone, 14,
             rotation=(math.radians(90), 0, 0))
    sun_boss = sphere('sun ember boss', (0, -0.155, 4.22), 0.115, ochre, 12, 6)
    apply_scale(sun_boss, (1.0, 0.50, 1.0))
    for index in range(12):
        angle = math.tau * index / 12
        direction = Vector((math.cos(angle), 0, math.sin(angle)))
        cone_between('tapered forged spoke', sun_center + direction * 0.48,
                     sun_center + direction * 1.08, 0.026, 0.015,
                     ochre if index % 2 else bone, 6)
        ray_end = 1.36 if index % 3 == 0 else 1.29
        cone_between('outer altar sun ray', sun_center + direction * 1.19,
                     sun_center + direction * ray_end,
                     0.040 if index % 3 == 0 else 0.030, 0.004,
                     bone if index % 2 == 0 else ochre, 6)
    for angle in (math.radians(45), math.radians(135),
                  math.radians(225), math.radians(315)):
        point = sun_center + Vector((math.cos(angle) * 1.16, 0, math.sin(angle) * 1.16))
        tangent = Vector((-math.sin(angle), 0, math.cos(angle)))
        detail_torus('sun rim cloth knot', point, 0.052, 0.010, red_light,
                     rotation=limb_euler(-tangent), major_segments=16, minor_segments=5)

    # Organic votive strips and asymmetric offerings replace the old rigid bars.
    cloth_strip('left votive ribbon', ((-0.63, -0.08, 3.70), (-0.78, -0.10, 3.45),
                (-0.72, -0.09, 3.17), (-0.84, -0.08, 2.88), (-0.76, -0.07, 2.55)),
                0.13, 0.025, red)
    cloth_strip('right votive ribbon', ((0.67, -0.07, 3.62), (0.79, -0.10, 3.35),
                (0.70, -0.08, 3.08), (0.82, -0.06, 2.83)),
                0.115, 0.023, red_light)
    for side, z, drop in ((-1, 2.45, 0.42), (1, 1.83, 0.34)):
        peg_root = Vector((side * 0.14, -0.02, z))
        peg_tip = Vector((side * 0.46, -0.05, z + 0.07 * side))
        cone_between('carved offering peg', peg_root, peg_tip, 0.040, 0.025, wood_dark, 8)
        curved_tube('offering cord', (peg_tip, peg_tip + Vector((0, -0.02, -drop * 0.55)),
                    peg_tip + Vector((-side * 0.04, 0, -drop))),
                    (0.011, 0.009, 0.007), rope, 7, 0.46)
        bead = sphere('bone offering bead', peg_tip + Vector((-side * 0.04, -0.01, -drop - 0.055)),
                      0.060, bone, 8, 4)
        apply_scale(bead, (0.80, 0.65, 1.15))
    export('sun_totem')


def make_burial_altar_legacy():
    """Compact ritual brazier used by the challenge levels from level two."""
    clear()
    stone = material('burial altar stone', (0.255, 0.245, 0.205), 0.99)
    stone_light = material('worn burial stone edges', (0.43, 0.39, 0.29), 0.98)
    charcoal = material('charred offering wood', (0.075, 0.045, 0.025), 0.99)
    iron = material('blackened burial iron', (0.09, 0.042, 0.022), 0.79, 0.40)
    rope = material('burial hemp cord', (0.30, 0.18, 0.055), 0.99)
    cloth = material('burial red binding', (0.42, 0.014, 0.010), 0.96)
    ochre = material('burial ochre marks', (0.82, 0.25, 0.025), 0.90)
    bone = material('burial bone offering', (0.69, 0.63, 0.45), 0.92)

    foundation = cylinder('burial fire foundation', (0, 0, 0.09), 0.92, 0.18,
                          stone, 11, rotation=(0, 0, math.radians(8)), smooth=False)
    apply_scale(foundation, (1.0, 0.88, 1.0))
    for index in range(7):
        angle = math.tau * index / 7 + 0.18
        radius = 0.67 + 0.035 * math.sin(index * 2.1)
        block = cube(
            'rough burial ring stone',
            (math.cos(angle) * radius, math.sin(angle) * radius, 0.29 + 0.025 * (index % 2)),
            (0.34, 0.27, 0.36 + 0.045 * (index % 3)),
            stone_light if index % 3 == 0 else stone,
            rotation=(math.radians((index % 2) * 4), math.radians((index % 3 - 1) * 5), angle),
            bevel=0.035,
        )
        if index in (1, 4):
            detail_torus('red stone binding', block.location + Vector((0, 0, 0.03)),
                         0.145, 0.014, cloth, major_segments=16, minor_segments=5)

    cylinder('iron offering bowl', (0, 0, 0.43), 0.43, 0.18, iron, 12, smooth=False)
    detail_torus('forged bowl rim', (0, 0, 0.535), 0.42, 0.050, iron,
                 major_segments=24, minor_segments=6)
    for angle in (math.radians(-58), math.radians(4), math.radians(62)):
        cylinder('crossed offering log', (0, 0, 0.62), 0.055, 0.67, charcoal, 8,
                 rotation=(0, math.radians(90), angle), smooth=False)
    for x, y, radius in ((-0.14, -0.06, 0.075), (0.02, -0.10, 0.085),
                         (0.15, 0.01, 0.065), (-0.04, 0.11, 0.060)):
        coal = sphere('burial coal', (x, y, 0.67), radius, charcoal, 8, 4)
        apply_scale(coal, (1.12, 0.90, 0.70))

    for side, angle in ((-1, math.radians(205)), (1, math.radians(-22))):
        anchor = Vector((math.cos(angle) * 0.72, math.sin(angle) * 0.72, 0.55))
        curved_tube('bone charm cord', (anchor, anchor + Vector((0, 0, -0.16)),
                    anchor + Vector((side * 0.035, 0, -0.27))),
                    (0.010, 0.008, 0.006), rope, 7, 0.44)
        detail_torus('bone burial charm', anchor + Vector((side * 0.035, 0, -0.33)),
                     0.060, 0.012, bone, rotation=(math.radians(90), 0, 0),
                     major_segments=16, minor_segments=5)
    for angle in (0, math.radians(120), math.radians(240)):
        diamond_plane('ochre burial mark', math.cos(angle) * 0.62, -0.80,
                      0.28 + math.sin(angle) * 0.04, 0.075, 0.095, ochre)
    export('burial_altar')


def make_burial_altar():
    """Faceted, hand-built burial brazier for challenge-level ritual fires."""
    clear()
    stone = material('smoke dark burial stone', (0.19, 0.185, 0.16), 0.99)
    stone_mid = material('worn fieldstone faces', (0.34, 0.31, 0.245), 0.98)
    lichen = material('old altar lichen', (0.26, 0.32, 0.13), 0.99)
    charcoal = material('charred offering wood', (0.055, 0.032, 0.018), 0.99)
    ash = material('cold ritual ash', (0.125, 0.115, 0.105), 0.99)
    iron = material('hammered burial iron', (0.075, 0.032, 0.018), 0.76, 0.46)
    rope = material('burial hemp cord', (0.29, 0.17, 0.05), 0.99)
    cloth = material('madder burial binding', (0.47, 0.012, 0.008), 0.96)
    ochre = material('grave ochre marks', (0.84, 0.24, 0.018), 0.90)
    bone = material('weathered grave offerings', (0.67, 0.60, 0.42), 0.93)

    foundation = cylinder('sunken burial foundation', (0, 0, 0.07), 0.98, 0.14,
                          stone, 11, rotation=(0, 0, math.radians(7)), smooth=False)
    apply_scale(foundation, (1.0, 0.88, 1.0))
    inner_slab = cylinder('cracked inner altar slab', (0.015, -0.01, 0.17), 0.78, 0.13,
                          stone_mid, 9, rotation=(0, 0, math.radians(-8)), smooth=False)
    apply_scale(inner_slab, (1.0, 0.86, 1.0))

    stones = []
    for index in range(8):
        angle = math.tau * index / 8 + 0.16
        radius = 0.68 + 0.045 * math.sin(index * 1.9)
        height = 0.44 + 0.09 * ((index * 3) % 4) / 3.0
        rock = sphere(
            'faceted burial standing stone',
            (math.cos(angle) * radius, math.sin(angle) * radius, 0.25 + height * 0.38),
            0.22,
            stone_mid if index in (0, 3, 6) else stone,
            10,
            6,
        )
        apply_scale(rock, (0.95 + 0.10 * (index % 2), 0.72 + 0.08 * ((index + 1) % 3),
                           height / 0.44))
        rock.rotation_euler = (math.radians((index % 3 - 1) * 7),
                               math.radians((index % 2) * 6 - 3), angle * 0.20)
        for polygon in rock.data.polygons:
            polygon.use_smooth = False
        stones.append(rock)
        if index in (1, 5):
            for band_z in (0.31, 0.38):
                detail_torus('double red stone binding',
                             (rock.location.x, rock.location.y, band_z),
                             0.17, 0.016, cloth, major_segments=16, minor_segments=5)
        elif index in (3, 7):
            detail_torus('hemp stone binding',
                         (rock.location.x, rock.location.y, 0.35),
                         0.165, 0.013, rope, major_segments=16, minor_segments=5)

    for x, width, height in ((-0.34, 0.070, 0.11), (0.0, 0.082, 0.13),
                             (0.34, 0.070, 0.10)):
        diamond_plane('front grave ochre glyph', x, -0.735, 0.34, width, height, ochre)
    for x, z, size in ((-0.53, 0.26, 0.055), (0.47, 0.31, 0.045), (0.18, 0.20, 0.040)):
        spot = sphere('altar lichen spot', (x, -0.69, z), size, lichen, 8, 4)
        apply_scale(spot, (1.45, 0.25, 0.70))

    # The bowl has a foot, hammered rim and visible bed of ash rather than a
    # single smooth cylinder.
    cylinder('forged bowl foot', (0, 0, 0.30), 0.27, 0.16, iron, 10, smooth=False)
    bowl = cylinder('hammered offering basin', (0, 0, 0.43), 0.45, 0.20, iron, 12,
                    rotation=(0, 0, math.radians(5)), smooth=False)
    apply_scale(bowl, (1.0, 0.94, 1.0))
    detail_torus('thick forged bowl rim', (0, 0, 0.545), 0.44, 0.052, iron,
                 major_segments=24, minor_segments=6)
    cylinder('cold ash bed', (0, 0, 0.565), 0.35, 0.055, ash, 12, smooth=False)
    for angle, length, z in ((-0.92, 0.73, 0.635), (0.08, 0.76, 0.65), (0.98, 0.68, 0.625)):
        cylinder('crossed charred log', (0, 0, z), 0.052, length, charcoal, 8,
                 rotation=(0, math.radians(90), angle), smooth=False)
    for x, y, radius in ((-0.15, -0.07, 0.075), (0.01, -0.11, 0.088),
                         (0.16, 0.00, 0.064), (-0.05, 0.12, 0.060), (0.08, 0.10, 0.050)):
        coal = sphere('burial coal', (x, y, 0.69), radius, charcoal, 8, 4)
        apply_scale(coal, (1.15, 0.90, 0.66))

    # Three forged warding prongs frame the fire and give the silhouette a
    # distinctive ritual crown without blocking the player's view.
    for angle in (math.radians(35), math.radians(145), math.radians(270)):
        direction = Vector((math.cos(angle), math.sin(angle), 0))
        root = direction * 0.44 + Vector((0, 0, 0.48))
        tip = direction * 0.52 + Vector((0, 0, 0.98 if angle != math.radians(270) else 0.87))
        cone_between('forged warding prong', root, tip, 0.030, 0.010, iron, 7)
        cone_between('bone prong tooth', tip, tip + Vector((0, 0, 0.10)),
                     0.018, 0.003, bone, 6)

    for side, angle, drop in ((-1, math.radians(205), 0.34), (1, math.radians(-18), 0.30)):
        anchor = Vector((math.cos(angle) * 0.75, math.sin(angle) * 0.75, 0.52))
        curved_tube('grave charm cord', (anchor, anchor + Vector((0, 0, -drop * 0.55)),
                    anchor + Vector((side * 0.045, -0.01, -drop))),
                    (0.011, 0.009, 0.006), rope, 7, 0.44)
        detail_torus('large bone grave charm',
                     anchor + Vector((side * 0.045, -0.01, -drop - 0.075)),
                     0.072, 0.014, bone, rotation=(math.radians(90), 0, 0),
                     major_segments=18, minor_segments=5)
    export('burial_altar')


def make_tree():
    clear()
    bark = material('pale birch bark', (0.79, 0.78, 0.70), 0.95)
    bark_shadow = material('birch branch bark', (0.50, 0.49, 0.42), 0.97)
    bark_dark = material('birch lenticels', (0.075, 0.068, 0.055), 0.98)
    leaves = material('deep birch leaves', (0.075, 0.25, 0.055), 0.97)
    leaves_mid = material('summer birch leaves', (0.16, 0.37, 0.075), 0.96)
    leaves_light = material('sunlit birch leaves', (0.34, 0.51, 0.11), 0.94)

    def limb(points, radii, branch_material=bark_shadow):
        for index in range(len(points) - 1):
            cone_between('natural birch limb', points[index], points[index + 1],
                         radii[index], radii[index + 1], branch_material, 10)

    trunk_points = [
        Vector((0.00, 0.00, 0.00)), Vector((0.035, 0.012, 1.20)),
        Vector((-0.025, 0.035, 2.35)), Vector((0.060, 0.018, 3.45)),
        Vector((0.105, 0.055, 4.45)), Vector((0.075, 0.015, 5.35)),
        Vector((0.150, 0.040, 6.20)),
    ]
    limb(trunk_points, (0.35, 0.31, 0.26, 0.21, 0.155, 0.105, 0.045), bark)

    main_limbs = [
        ([Vector((0.02, 0.02, 2.85)), Vector((-0.42, 0.10, 3.62)), Vector((-1.08, 0.20, 4.35))], (0.15, 0.10, 0.035)),
        ([Vector((0.05, 0.01, 3.28)), Vector((0.52, -0.13, 3.95)), Vector((1.24, -0.28, 4.62))], (0.14, 0.09, 0.032)),
        ([Vector((0.08, 0.04, 3.88)), Vector((-0.32, -0.24, 4.62)), Vector((-0.76, -0.55, 5.38))], (0.12, 0.075, 0.027)),
        ([Vector((0.10, 0.05, 4.15)), Vector((0.43, 0.34, 4.92)), Vector((0.92, 0.66, 5.65))], (0.105, 0.065, 0.025)),
        ([Vector((0.09, 0.02, 4.72)), Vector((-0.23, 0.33, 5.42)), Vector((-0.54, 0.56, 6.08))], (0.085, 0.052, 0.022)),
    ]
    for points, radii in main_limbs:
        limb(points, radii)

    twig_paths = [
        (Vector((-0.43, 0.10, 3.62)), Vector((-0.70, -0.04, 4.28)), Vector((-0.88, -0.16, 4.75))),
        (Vector((-0.72, 0.15, 3.98)), Vector((-1.16, 0.34, 4.68)), Vector((-1.45, 0.45, 5.02))),
        (Vector((0.52, -0.13, 3.95)), Vector((0.82, 0.05, 4.60)), Vector((1.02, 0.18, 5.02))),
        (Vector((0.86, -0.20, 4.26)), Vector((1.34, -0.38, 4.92)), Vector((1.56, -0.48, 5.26))),
        (Vector((-0.32, -0.24, 4.62)), Vector((-0.10, -0.58, 5.22)), Vector((0.02, -0.75, 5.66))),
        (Vector((0.43, 0.34, 4.92)), Vector((0.22, 0.62, 5.52)), Vector((0.12, 0.80, 5.92))),
        (Vector((-0.23, 0.33, 5.42)), Vector((-0.05, 0.12, 6.02)), Vector((0.02, 0.02, 6.45))),
    ]
    for path in twig_paths:
        limb(list(path), (0.045, 0.026, 0.010), bark_shadow)

    # Horizontal lenticels and old scars wrap around different sides of the trunk.
    for index, z in enumerate((0.72, 1.08, 1.48, 1.92, 2.38, 2.86, 3.34, 3.82, 4.28)):
        angle = index * 2.17
        radius = 0.30 - z * 0.026
        mark = sphere('birch bark marking', (math.cos(angle) * radius, math.sin(angle) * radius, z),
                      0.065 if index % 3 else 0.085, bark_dark, 8, 4)
        mark.scale = (1.75, 0.30, 0.42)
        mark.rotation_euler[2] = angle

    cluster_data = [
        ((-1.10, 0.20, 4.42), (0.54, 0.34, 0.48), 0.15),
        ((-0.82, -0.12, 4.78), (0.48, 0.30, 0.42), -0.25),
        ((-1.43, 0.42, 5.02), (0.46, 0.28, 0.43), 0.35),
        ((1.23, -0.28, 4.64), (0.55, 0.33, 0.48), -0.18),
        ((1.02, 0.16, 5.03), (0.46, 0.29, 0.43), 0.28),
        ((1.55, -0.47, 5.25), (0.43, 0.26, 0.40), -0.42),
        ((-0.77, -0.54, 5.38), (0.54, 0.34, 0.52), 0.18),
        ((-0.18, -0.66, 5.55), (0.45, 0.30, 0.45), -0.32),
        ((0.03, -0.76, 5.78), (0.38, 0.25, 0.38), 0.44),
        ((0.91, 0.65, 5.64), (0.52, 0.33, 0.49), -0.12),
        ((0.31, 0.72, 5.82), (0.43, 0.28, 0.43), 0.32),
        ((-0.54, 0.56, 6.08), (0.49, 0.31, 0.46), -0.28),
        ((-0.10, 0.16, 6.22), (0.42, 0.28, 0.43), 0.20),
        ((0.18, 0.03, 6.48), (0.38, 0.25, 0.40), -0.08),
        ((0.52, 0.16, 5.40), (0.43, 0.28, 0.41), 0.40),
        ((-0.42, 0.02, 5.38), (0.41, 0.27, 0.40), -0.38),
    ]
    random.seed(2406)
    for index, (loc, spread, rotation) in enumerate(cluster_data):
        centre = Vector(loc)
        twig_root = Vector((centre.x * 0.84, centre.y * 0.84, centre.z - 0.28))
        cone_between('hidden crown twig', twig_root, centre, 0.016, 0.004, bark_shadow, 6)
        for leaf_index in range(13):
            offset = Vector((random.uniform(-spread[0], spread[0]),
                             random.uniform(-spread[1], spread[1]),
                             random.uniform(-spread[2], spread[2]))) * 0.72
            leaf_centre = centre + offset
            leaf_size = random.uniform(0.105, 0.165)
            angle = rotation + random.uniform(-1.25, 1.25)
            tilt = random.uniform(-0.5, 0.5)
            right = Vector((math.cos(angle), math.sin(angle), tilt * 0.18)) * leaf_size
            up = Vector((-math.sin(angle) * 0.20, math.cos(angle) * 0.20, 1.0)) * leaf_size * 1.45
            fold = Vector((math.cos(angle + math.pi / 2), math.sin(angle + math.pi / 2), 0)) * leaf_size * 0.10
            vertices = [leaf_centre - up * 0.78, leaf_centre - right, leaf_centre + up,
                        leaf_centre + right, leaf_centre + fold]
            faces = [(0, 1, 4), (1, 2, 4), (2, 3, 4), (3, 0, 4)]
            leaf_material = leaves_light if (index + leaf_index) % 7 == 0 else leaves_mid if leaf_index % 3 else leaves
            custom_mesh('individual birch leaf', vertices, faces, leaf_material)
    export('birch_tree')


def make_fence():
    clear()
    wood = material('weathered fence', (0.28, 0.17, 0.065), 0.97)
    cut = material('fresh cut wood', (0.52, 0.34, 0.13), 0.95)
    rope = material('fence lashings', (0.14, 0.10, 0.045), 0.98)
    vermilion = material('fence vermilion paint', (0.55, 0.08, 0.035), 0.96)
    folk_blue = material('fence folk blue', (0.08, 0.22, 0.28), 0.96)
    for index, x in enumerate((-2.2, -1.1, 0.0, 1.1, 2.2)):
        height = 1.55 + 0.12 * math.sin(index * 2.1)
        cylinder('fence post', (x, 0, height / 2), 0.105, height, wood, 8, rotation=(0.03 * index, 0, 0))
        cone('post cap', (x, 0, height + 0.10), 0.13, 0.02, 0.20, cut, 8)
        for z in (0.52, 1.06):
            torus('rail lashing', (x, 0, z), 0.14, 0.024, rope)
    for z in (0.52, 1.06):
        cylinder('fence rail', (0, 0, z), 0.075, 4.7, wood, 8, rotation=(0, math.radians(90), 0))
    cylinder('diagonal brace', (0, -0.02, 0.82), 0.06, 4.5, cut, 8, rotation=(0, math.radians(90), math.radians(14)))
    for x in (-1.65, -0.55, 0.55, 1.65):
        cube('rough bark scar', (x, -0.10, 0.79), (0.30, 0.025, 0.055), cut,
             rotation=(0, 0, math.radians(8 * math.sin(x))))
    # restrained folk-painted marks for a handmade midsummer feel
    for x, mat, ang in [(-1.65, vermilion, -8), (-0.55, folk_blue, 8), (0.55, vermilion, 8), (1.65, folk_blue, -8)]:
        cube('painted fence mark', (x, -0.085, 1.06), (0.22, 0.022, 0.035), mat,
             rotation=(0, 0, math.radians(ang)))
    export('fence')


def make_stone():
    clear()
    stone = material('ritual stone', (0.34, 0.35, 0.30), 0.94)

    # Раньше это была помятая икосфера: на редкой сетке её грани читались как
    # сколы, а на частой она расплылась бы в валун-яйцо. Камень собран как
    # гранёная призма — вертикальные рёбра держат силуэт при любой плотности.
    sides = ring_count(22)
    levels = ring_count(16)
    bottom, top = -0.38, 2.24
    span = top - bottom

    def girth(height_ratio):
        """Полуоси камня на этой высоте."""
        taper = 1.0 - 0.52 * height_ratio ** 1.45
        shoulder = 1.0 + 0.07 * math.sin(height_ratio * 4.2 - 0.5)
        base_flare = 1.0 + 0.10 * (1.0 - height_ratio) ** 4
        return 0.74 * taper * shoulder * base_flare, 0.50 * taper * shoulder

    def chip(angle, height_ratio):
        """Скол грани: постоянная часть по углу даёт сплошное ребро сверху
        донизу, дрожащая — неровный край."""
        return (1.0 + 0.055 * math.sin(angle * 3.0 + 0.7)
                + 0.025 * math.sin(angle * 7.0 - 1.2)
                + 0.018 * math.sin(angle * 2.0 + height_ratio * 6.1))

    def lean(height_ratio):
        return 0.08 * math.sin(height_ratio * 2.6) + 0.10 * height_ratio ** 2

    def surface(angle, height_ratio):
        rx, ry = girth(height_ratio)
        scale = chip(angle, height_ratio)
        outline = 1.0 + 0.055 * math.sin(height_ratio * 9.0 + 0.4) + 0.028 * math.sin(height_ratio * 19.0)
        side_sway = 0.055 * math.sin(height_ratio * 7.0 + angle * 0.45)
        horizontal_drift = 0.065 * math.sin(height_ratio * 5.2 - 0.3)
        crown_slope = (0.12 * math.cos(angle) + 0.035 * math.sin(angle * 2.0)) if height_ratio == 1.0 else 0.0
        return (math.cos(angle) * rx * scale * outline + lean(height_ratio) + side_sway + horizontal_drift,
                math.sin(angle) * ry * scale,
                bottom + span * height_ratio + crown_slope)

    vertices = []
    for level in range(levels + 1):
        height_ratio = level / levels
        for index in range(sides):
            vertices.append(surface(math.tau * index / sides, height_ratio))
    foot = len(vertices)
    vertices.append((0.0, 0.0, bottom - 0.12))

    faces = []
    for level in range(levels):
        for index in range(sides):
            nxt = (index + 1) % sides
            a = level * sides + index
            b = level * sides + nxt
            faces.append((a, b, (level + 1) * sides + nxt, (level + 1) * sides + index))
    faces.append(tuple(levels * sides + index for index in range(sides)))
    for index in range(sides):
        nxt = (index + 1) % sides
        faces.append((nxt, index, foot))

    mesh = bpy.data.meshes.new('standing stone mesh')
    mesh.from_pydata(vertices, [], faces)
    mesh.materials.append(stone)
    obj = bpy.data.objects.new('standing stone', mesh)
    bpy.context.collection.objects.link(obj)
    for poly in obj.data.polygons:
        poly.use_smooth = True
    bevel = obj.modifiers.new('worn softened edges', 'BEVEL')
    bevel.width = 0.025
    bevel.segments = 2
    bevel.limit_method = 'ANGLE'

    # Резьба и лишайник садятся на реальную поверхность камня, а не на
    # фиксированный отступ: у призмы он в этом месте другой.
    # Кольцо перекрывает несколько граней, поэтому берём самую выступающую
    # точку на его развороте, иначе край резьбы уходит внутрь камня.
    # small ritual wreath resting around the crown, clearly attached to the stone
    wreath_leaf = material('wreath deep greenery', (0.09, 0.24, 0.055), 0.98)
    wreath_leaf_light = material('wreath fresh greenery', (0.25, 0.43, 0.10), 0.98)
    petal_white = material('wreath white petals', (0.96, 0.92, 0.73), 0.92)
    petal_blue = material('wreath blue petals', (0.18, 0.34, 0.58), 0.95)
    flower_yellow = material('wreath flower centres', (0.92, 0.57, 0.055), 0.90)
    centre = Vector((0.12, -0.43, 1.88))
    torus('woven wreath base', centre, 0.31, 0.038, wreath_leaf,
          rotation=(math.radians(90), 0, 0))
    torus('woven wreath highlight', (centre.x, centre.y - 0.012, centre.z), 0.285, 0.018, wreath_leaf_light,
          rotation=(math.radians(90), 0, 0))
    for index in range(14):
        a = math.tau * index / 14 + 0.08
        radius = 0.305
        leaf = sphere('wreath leaf', (centre.x + radius * math.cos(a), centre.y - 0.025,
                                     centre.z + radius * math.sin(a)), 0.052,
                      wreath_leaf_light if index % 3 else wreath_leaf, 8, 4)
        leaf.scale = (1.55, 0.48, 0.68)
        leaf.rotation_euler[1] = -a + math.pi / 2
    for flower_index, a in enumerate((0.25, 1.48, 2.72, 3.95, 5.18)):
        flower_centre = Vector((centre.x + 0.31 * math.cos(a), centre.y - 0.075,
                                centre.z + 0.31 * math.sin(a)))
        petal_mat = petal_white if flower_index % 2 == 0 else petal_blue
        for petal_index in range(5):
            p = math.tau * petal_index / 5
            petal = sphere('wreath petal', (flower_centre.x + 0.040 * math.cos(p), flower_centre.y,
                                           flower_centre.z + 0.040 * math.sin(p)), 0.031,
                           petal_mat, 8, 4)
            petal.scale = (1.30, 0.58, 0.78)
            petal.rotation_euler[1] = -p
        sphere('wreath flower centre', flower_centre, 0.025, flower_yellow, 8, 4)
    export('standing_stone')


def make_flowers():
    clear()
    stem_green = material('slender flower stems', (0.11, 0.29, 0.055), 0.98)
    leaf_green = material('summer flower leaves', (0.18, 0.39, 0.075), 0.98)
    leaf_light = material('sunlit flower leaves', (0.31, 0.49, 0.10), 0.98)
    white = material('daisy petals', (0.96, 0.94, 0.80), 0.88)
    red = material('poppy petals', (0.63, 0.045, 0.025), 0.92)
    blue = material('cornflower petals', (0.12, 0.28, 0.56), 0.93)
    yellow = material('golden flower centres', (0.94, 0.58, 0.045), 0.86)
    dark_centre = material('poppy centres', (0.10, 0.075, 0.035), 0.98)
    plants = [
        (-0.84, -0.30, 'daisy', 0.42, 0.025, -0.018),
        (-0.70,  0.22, 'blue',  0.54, -0.030, 0.012),
        (-0.50, -0.02, 'poppy', 0.48, 0.020, -0.010),
        (-0.34,  0.40, 'daisy', 0.39, -0.015, 0.018),
        (-0.16, -0.38, 'blue',  0.50, 0.026, -0.014),
        ( 0.02,  0.13, 'daisy', 0.58, -0.018, 0.014),
        ( 0.22, -0.10, 'poppy', 0.44, 0.022, -0.008),
        ( 0.38,  0.42, 'blue',  0.52, -0.026, 0.016),
        ( 0.56, -0.34, 'daisy', 0.40, 0.018, -0.014),
        ( 0.69,  0.08, 'poppy', 0.55, -0.020, 0.012),
        ( 0.85,  0.36, 'daisy', 0.46, 0.015, 0.016),
    ]
    for index, (x, y, species, height, lean_x, lean_y) in enumerate(plants):
        base = Vector((x, y, 0.015))
        head = Vector((x + lean_x, y + lean_y, height))
        cone_between('natural flower stem', base, head, 0.012, 0.007, stem_green, 6)
        for side in (-1, 1):
            leaf_z = height * (0.34 if side < 0 else 0.53)
            leaf_x = x + side * (0.065 + 0.012 * (index % 3))
            leaf = sphere('lance flower leaf', (leaf_x, y + side * 0.008, leaf_z), 0.052,
                          leaf_green if (index + side) % 2 else leaf_light, 8, 4)
            leaf.scale = (1.65, 0.34, 0.52)
            leaf.rotation_euler[1] = math.radians(-side * (18 + index % 4 * 4))
        sphere('green flower sepal', (head.x, head.y + 0.014, head.z - 0.018), 0.034,
               stem_green, 8, 4)
        if species == 'daisy':
            petal_count, ring_radius, petal_radius, petal_mat = 8, 0.058, 0.034, white
            centre_mat, centre_radius = yellow, 0.030
        elif species == 'poppy':
            petal_count, ring_radius, petal_radius, petal_mat = 5, 0.045, 0.050, red
            centre_mat, centre_radius = dark_centre, 0.032
        else:
            petal_count, ring_radius, petal_radius, petal_mat = 7, 0.052, 0.030, blue
            centre_mat, centre_radius = dark_centre, 0.026
        for petal_index in range(petal_count):
            angle = math.tau * petal_index / petal_count + 0.17 * index
            petal_position = Vector((head.x + math.cos(angle) * ring_radius,
                                     head.y - 0.030 + math.sin(angle) * ring_radius * 0.38,
                                     head.z + math.sin(angle) * ring_radius * 0.82))
            petal = sphere('individual flower petal', petal_position, petal_radius,
                           petal_mat, 8, 4)
            petal.scale = (1.22 if species != 'poppy' else 1.05, 0.42, 0.70)
            petal.rotation_euler[1] = -angle
        sphere('flower centre', (head.x, head.y - 0.052, head.z), centre_radius,
               centre_mat, 10, 5)
    export('flower_patch')


if __name__ == '__main__':
    make_ground()
    make_mountains()
    make_house('green')
    make_house('blue')
    make_house('red')
    make_house('ochre')
    make_guardian()
    make_seal()
    make_gate()
    make_gate_door()
    make_totem()
    make_burial_altar()
    make_tree()
    make_fence()
    make_stone()
    make_flowers()
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ROOT, 'tools', 'solstice_assets.blend'))
