extends Node3D
## Солнце солнцестояния: один билборд-квад с процедурной короной.
##
## Прежний вариант был низкополигональной сферой, приколоченной к точке
## сцены, пока DirectionalLight3D светил совсем с другой стороны: были видны
## грани, «затмение» разваливалось стоило обойти его сбоку, а тени падали не
## туда. Здесь диск всегда развёрнут к камере и всегда стоит ровно в той
## стороне, откуда падает свет.
##
## Диск считает шейдер, а не процедурная текстура: перекраска картинки 128×128
## стоила около 25 мс, а в сюжетном режиме солнце меняется на каждой печати —
## это был заметный рывок кадра прямо в момент подбора.

const DISTANCE := 88.0 # внутри far-плоскости камеры игрока (125 м)
const QUAD_SIZE := 34.0 # ~21 градус вместе с короной

const SUN_SHADER := "
shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, shadows_disabled, fog_disabled, depth_draw_opaque;

uniform vec3 core_color : source_color = vec3(1.0, 0.95, 0.8);
uniform vec3 ring_color : source_color = vec3(1.0, 0.85, 0.5);
uniform vec3 corona_color : source_color = vec3(1.0, 0.6, 0.25);
uniform float eclipse : hint_range(0.0, 1.0) = 0.0;
uniform float core_radius : hint_range(0.05, 0.6) = 0.3;
uniform float ray_count = 10.0;
uniform float ray_phase = 0.0;
uniform float ray_drift = 0.05;

void vertex() {
	// Разворот к камере с сохранением масштаба узла.
	mat4 facing = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	mat4 keep_scale = mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * facing * keep_scale;
}

void fragment() {
	vec2 offset = UV * 2.0 - 1.0;
	float radius = length(offset);
	if (radius >= 1.0) {
		discard;
	}
	float angle = atan(offset.y, offset.x);
	// Тело диска с мягким краем — без граней, в отличие от сферы.
	float body = 1.0 - smoothstep(core_radius - 0.014, core_radius + 0.014, radius);
	// Хромосфера: узкий раскалённый ободок по краю диска.
	float rim_offset = (radius - core_radius) / 0.038;
	float rim = exp(-rim_offset * rim_offset);
	// Корона живёт только снаружи диска: иначе она засвечивает середину и
	// затмение никогда не темнеет.
	float reach = clamp(1.0 - (radius - core_radius) / (1.0 - core_radius), 0.0, 1.0);
	float drift = ray_phase + TIME * ray_drift;
	float ray = 0.5 + 0.34 * sin(angle * ray_count + drift)
		+ 0.2 * sin(angle * (ray_count * 2.0 + 1.0) - drift * 1.7);
	float glow = pow(reach, 3.3) * (0.52 + 0.48 * clamp(ray, 0.0, 1.0)) * (1.0 - body);
	vec3 inner = mix(core_color, vec3(0.020, 0.014, 0.030), eclipse);
	float rim_weight = rim * (0.55 + 0.85 * eclipse);
	ALBEDO = inner * body + ring_color * rim_weight + corona_color * glow;
	ALPHA = clamp(body + rim * 0.85 + glow * 0.62, 0.0, 1.0);
}
"

var light: DirectionalLight3D
var disk: MeshInstance3D
var material: ShaderMaterial

var _time := 0.0
var _breath_speed := 0.42
var _breath_amount := 0.014

func setup(target_light: DirectionalLight3D) -> void:
	light = target_light
	var shader := Shader.new()
	shader.code = SUN_SHADER
	material = ShaderMaterial.new()
	material.shader = shader

	var quad := QuadMesh.new()
	quad.size = Vector2(QUAD_SIZE, QUAD_SIZE)
	quad.material = material

	disk = MeshInstance3D.new()
	disk.name = "SolsticeDisk"
	disk.mesh = quad
	disk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Билборд разворачивается в вершинном шейдере, AABB об этом не знает.
	disk.extra_cull_margin = QUAD_SIZE
	add_child(disk)

func set_look(core: Color, ring: Color, corona: Color, eclipse: float, rays: int, phase: float) -> void:
	if material == null:
		return
	var depth := clampf(eclipse, 0.0, 1.0)
	material.set_shader_parameter("core_color", core)
	material.set_shader_parameter("ring_color", ring)
	material.set_shader_parameter("corona_color", corona)
	material.set_shader_parameter("eclipse", depth)
	material.set_shader_parameter("ray_count", float(maxi(rays, 3)))
	material.set_shader_parameter("ray_phase", phase)
	material.set_shader_parameter("ray_drift", 0.035 + depth * 0.05)

func set_breath(speed: float, amount: float) -> void:
	_breath_speed = speed
	_breath_amount = amount

func _process(delta: float) -> void:
	_time += delta
	if not is_instance_valid(light):
		return
	var toward_sun := light.global_transform.basis.z.normalized()
	var anchor := Vector3.ZERO
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		anchor = camera.global_position
	global_position = anchor + toward_sun * DISTANCE
	scale = Vector3.ONE * (1.0 + sin(_time * _breath_speed) * _breath_amount)

## Поворот DirectionalLight3D, при котором солнце стоит в заданной точке неба.
static func light_rotation_for(azimuth_degrees: float, elevation_degrees: float) -> Vector3:
	return Vector3(-elevation_degrees, 180.0 - azimuth_degrees, 0.0)
