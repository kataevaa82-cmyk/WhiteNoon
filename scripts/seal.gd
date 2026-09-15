extends Area3D

signal collected(seal: Area3D)

var base_height := 0.0
var time := 0.0
var taken := false

func _ready() -> void:
	base_height = position.y
	body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	time += delta
	rotation.y += delta * 1.2
	position.y = base_height + sin(time * 2.0) * 0.16
	$Halo.rotation.y -= delta * 1.7
	var pulse := 0.96 + sin(time * 3.1) * 0.08
	$Halo.scale = Vector3.ONE * pulse
	$Glow.light_energy = 1.25 + sin(time * 2.6) * 0.22

func _on_body_entered(body: Node3D) -> void:
	if not taken and body.is_in_group("player"):
		taken = true
		set_deferred("monitoring", false)
		collected.emit(self)
		var tween := create_tween().set_parallel(true)
		tween.tween_property($Model, "scale", Vector3.ZERO, 0.28).set_trans(Tween.TRANS_BACK)
		tween.tween_property($Halo, "scale", Vector3.ZERO, 0.28).set_trans(Tween.TRANS_BACK)
		tween.tween_property($Glow, "light_energy", 0.0, 0.22)
		tween.chain()
		tween.tween_callback(queue_free)
