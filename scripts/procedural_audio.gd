extends Node

const SAMPLE_RATE := 22050
const VOICE_COUNT := 8

var sounds: Dictionary = {}
var base_volumes := {
	"step": -18.0,
	"seal": -7.0,
	"pulse": -5.5,
	"hit": -4.5,
	"attack": -10.0,
	"charge": -8.0,
	"gate": -6.0,
	"sunset": -7.0,
	"totem": -6.0,
}
var voices: Array[AudioStreamPlayer] = []
var voice_cursor := 0
var step_variant := 0
var event_play_count := 0
var last_event := ""
var generated_sample_bytes := 0

func _ready() -> void:
	_build_sound_bank()
	for index in range(VOICE_COUNT):
		var voice := AudioStreamPlayer.new()
		voice.name = "Voice%d" % (index + 1)
		voice.bus = "Master"
		add_child(voice)
		voices.append(voice)

func play_step(intensity: float) -> void:
	step_variant += 1
	var pitch := (0.94 if step_variant % 2 == 0 else 1.06) + clampf(intensity - 0.7, 0.0, 0.3) * 0.12
	play_event("step", pitch, lerpf(-2.0, 1.5, clampf(intensity, 0.0, 1.0)))

func play_event(event_name: String, pitch_scale := 1.0, volume_offset_db := 0.0) -> void:
	var stream := sounds.get(event_name) as AudioStreamWAV
	if stream == null or voices.is_empty():
		return
	var voice := voices[voice_cursor]
	voice_cursor = (voice_cursor + 1) % voices.size()
	voice.stop()
	voice.stream = stream
	voice.pitch_scale = pitch_scale
	voice.volume_db = float(base_volumes.get(event_name, -8.0)) + volume_offset_db
	voice.play()
	event_play_count += 1
	last_event = event_name

func active_voice_count() -> int:
	var count := 0
	for voice in voices:
		if voice.playing:
			count += 1
	return count

func stop_all() -> void:
	for voice in voices:
		voice.stop()
		voice.stream = null

func _exit_tree() -> void:
	stop_all()
	sounds.clear()

func _build_sound_bank() -> void:
	sounds["step"] = _make_sound(0.10, 78.0, 44.0, 0.42, 0.006, 0.075, 0.14, 0.0, 11)
	sounds["seal"] = _make_sound(0.56, 410.0, 830.0, 0.015, 0.018, 0.20, 0.44, 0.0, 17)
	sounds["pulse"] = _make_sound(0.40, 122.0, 38.0, 0.13, 0.004, 0.30, 0.27, 0.0, 23)
	sounds["hit"] = _make_sound(0.21, 92.0, 35.0, 0.58, 0.003, 0.18, 0.10, 0.0, 29)
	sounds["attack"] = _make_sound(0.34, 185.0, 355.0, 0.045, 0.012, 0.12, 0.24, 8.0, 31)
	sounds["charge"] = _make_sound(0.68, 215.0, 690.0, 0.025, 0.018, 0.14, 0.38, 11.0, 37)
	sounds["gate"] = _make_sound(0.90, 250.0, 535.0, 0.015, 0.015, 0.32, 0.62, 3.0, 41)
	sounds["sunset"] = _make_sound(1.12, 96.0, 39.0, 0.08, 0.03, 0.42, 0.30, 2.2, 43)
	sounds["totem"] = _make_sound(0.76, 325.0, 675.0, 0.02, 0.012, 0.30, 0.52, 5.0, 47)

func _make_sound(duration: float, start_frequency: float, end_frequency: float, noise_mix: float,
		attack: float, release: float, harmonic_mix: float, pulse_rate: float, seed: int) -> AudioStreamWAV:
	var sample_count := maxi(1, int(duration * SAMPLE_RATE))
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var phase := 0.0
	var noise_state := seed
	for index in range(sample_count):
		var time := float(index) / SAMPLE_RATE
		var progress := float(index) / maxf(1.0, float(sample_count - 1))
		var frequency := lerpf(start_frequency, end_frequency, progress)
		phase += TAU * frequency / SAMPLE_RATE
		noise_state = int((noise_state * 1103515245 + 12345) & 0x7fffffff)
		var noise := float(noise_state) / 1073741824.0 - 1.0
		var tone := sin(phase) + sin(phase * 2.01) * harmonic_mix
		var sample := tone * (1.0 - noise_mix) + noise * noise_mix
		var attack_envelope := minf(1.0, time / maxf(0.001, attack))
		var release_envelope := minf(1.0, (duration - time) / maxf(0.001, release))
		var envelope := minf(attack_envelope, release_envelope) * exp(-progress * 0.72)
		if pulse_rate > 0.0:
			envelope *= 0.72 + sin(time * TAU * pulse_rate) * 0.28
		var value := clampi(int(sample * envelope * 22000.0), -32768, 32767)
		data.encode_s16(index * 2, value)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = data
	generated_sample_bytes += data.size()
	return stream
