# cat_base.gd
# Attach to a CharacterBody3D. This replaces test_cat.gd entirely.
# Reads from a CatData resource and runs the live simulation:
# need decay, mood, AI navigation, and interaction readiness.
#
# SCENE SETUP for each cat:
#   CharacterBody3D  ← this script
#   ├── MeshInstance3D  (placeholder CapsuleMesh until real model is ready)
#   ├── CollisionShape3D (CapsuleShape3D radius 0.3 height 1.0)
#   ├── NavigationAgent3D
#   └── DreamGlow (OmniLight3D, visible = false — enabled by FogPier)
extends CharacterBody3D

# ── Data ──────────────────────────────────────────────────────────────────────
## Assign a CatData resource in the Inspector.
## Create one per cat: right-click in FileSystem → New Resource → CatData.
@export var data: CatData

# ── Node refs ─────────────────────────────────────────────────────────────────
@onready var _nav_agent: NavigationAgent3D = $NavigationAgent3D

# ── Need decay rates ──────────────────────────────────────────────────────────
## Base amount each need drops per in-game day (0.0–1.0).
## Multiplied by ZodiacSystem.need_decay_mod() and personality modifiers.
const NEED_DECAY_RATES: Dictionary = {
	"hunger":     0.30,
	"sleep":      0.20,
	"social":     0.15,
	"fun":        0.14,
	"expression": 0.10,
	"belonging":  0.09,
	"hygiene":    0.07,
	"aspiration": 0.03,
}

## How low a need must fall before the cat actively tries to fill it.
const NEED_URGENT_THRESHOLD: float = 0.35

## How low a need must fall before mood takes a serious hit.
const NEED_CRITICAL_THRESHOLD: float = 0.15

# ── Movement ──────────────────────────────────────────────────────────────────
const WALK_SPEED: float = 2.5
const GRAVITY:    float = 9.8

## Set by the AI each time a new destination is chosen.
var _current_destination: Vector3 = Vector3.ZERO
var _is_moving: bool               = false

## Seconds until the AI picks a new destination.
var _ai_timer: float               = 0.0
const AI_THINK_INTERVAL: float     = 4.0

# ── State ─────────────────────────────────────────────────────────────────────
## Shortcut property so location_base.gd and rumor_manager.gd can read cat_name
## directly without going through data.
var cat_name: String :
	get: return data.cat_name if data else ""

var mood: float :
	get: return data.mood if data else 0.0

var traits: Dictionary :
	get: return data.traits if data else {}

var reputation: float :
	get: return data.reputation if data else 0.0
	set(v):
		if data: data.reputation = v

## Which location this cat is currently registered at. Set by LocationBase.
var current_location_id: String = ""

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	if data == null:
		push_error("[CatBase] No CatData assigned to '%s'. Attach a CatData resource in the Inspector." % name)
		return

	# Apply zodiac caps and boosts to trait values.
	ZodiacSystem.apply_caps(data)

	add_to_group("cat")
	_ai_timer = randf_range(0.0, AI_THINK_INTERVAL)	# stagger so all cats don't think at once


func _physics_process(delta: float) -> void:
	if data == null:
		return
	_apply_gravity(delta)
	_move(delta)


func _process(delta: float) -> void:
	if data == null:
		return
	_ai_timer -= delta
	if _ai_timer <= 0.0:
		_ai_timer = AI_THINK_INTERVAL
		_ai_think()


# ── Daily tick (called by GameState / TimeManager once per in-game day) ───────

func daily_tick() -> void:
	if data == null:
		return
	_decay_needs()
	data.recalculate_mood()
	_check_aspiration_progress()


# ── Need decay ────────────────────────────────────────────────────────────────

func _decay_needs() -> void:
	for need in NEED_DECAY_RATES:
		var base_rate: float   = NEED_DECAY_RATES[need]
		var zodiac_mod: float  = ZodiacSystem.need_decay_mod(data.zodiac_sign, need)
		var personality_mod: float = _personality_decay_mod(need)
		var final_rate: float  = base_rate * zodiac_mod * personality_mod
		data.set_need(need, data.get_need(need) - final_rate)


func _personality_decay_mod(need: String) -> float:
	match need:
		"social":
			# Introverted cats (low sociability) need social less urgently.
			return 0.5 + data.traits.get("sociability", 0.5) * 1.0
		"belonging":
			# High empathy cats feel belonging more acutely.
			return 0.7 + data.traits.get("empathy", 0.5) * 0.6
		"expression":
			# High creativity cats need expression more urgently.
			return 0.6 + data.traits.get("creativity", 0.5) * 0.8
		"fun":
			# High mischief cats need fun constantly.
			return 0.7 + data.traits.get("mischief", 0.5) * 0.6
		_:
			return 1.0


# ── AI decision-making ────────────────────────────────────────────────────────

func _ai_think() -> void:
	var lowest: String = data.lowest_need()

	if data.get_need(lowest) < NEED_URGENT_THRESHOLD:
		# Urgent need — go somewhere that fills it.
		_seek_need_location(lowest)
	else:
		# No urgent need — wander based on personality.
		_personality_wander()


func _seek_need_location(need: String) -> void:
	# In the full game, this queries GameState for available locations
	# and picks the best one. For now, just wander — the location system
	# will hook in here once the map screen is built.
	# TODO: replace with GameState.get_best_location_for_need(need, self)
	_personality_wander()


func _personality_wander() -> void:
	var sociability: float = data.traits.get("sociability", 0.5)

	# Shy cats (low sociability) pick destinations near the edges.
	# Bold cats (high sociability) drift toward the centre where others are.
	var centre_pull: float = sociability * 6.0	# 0 = full edge, 6 = strong centre pull
	var rand_offset: float = 5.0

	var target_x: float = randf_range(-rand_offset, rand_offset)
	var target_z: float = randf_range(-rand_offset, rand_offset)

	# Bias toward or away from centre based on sociability.
	target_x = lerp(target_x, 0.0, sociability * 0.5)
	target_z = lerp(target_z, 0.0, sociability * 0.5)

	# Clamp within room bounds.
	target_x = clamp(target_x, -8.0, 8.0)
	target_z = clamp(target_z, -8.0, 8.0)

	_set_destination(Vector3(target_x, 0.1, target_z))


func _set_destination(pos: Vector3) -> void:
	_current_destination = pos
	_is_moving           = true
	if _nav_agent != null:
		_nav_agent.target_position = pos


# ── Movement ──────────────────────────────────────────────────────────────────

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta


func _move(delta: float) -> void:
	if not _is_moving:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return

	var next_pos: Vector3

	if _nav_agent != null and not _nav_agent.is_navigation_finished():
		next_pos = _nav_agent.get_next_path_position()
	else:
		# NavigationMesh not baked yet — fall back to direct movement.
		next_pos = _current_destination

	var diff: Vector3 = next_pos - global_position
	diff.y = 0.0

	if diff.length() < 0.3:
		_is_moving = false
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return

	var dir: Vector3 = diff.normalized()
	velocity.x = dir.x * WALK_SPEED
	velocity.z = dir.z * WALK_SPEED
	move_and_slide()


# ── Aspiration progress ───────────────────────────────────────────────────────

func _check_aspiration_progress() -> void:
	# Called each daily tick. Each aspiration type has different conditions.
	# For now, a small passive fill. Full logic added when dialogue system lands.
	var gain: float = 0.0

	match data.aspiration_type:
		"fame":
			# Fame grows when reputation is high.
			if data.reputation > 20.0:
				gain = 0.01
		"love":
			# Love grows when any relationship is above 70.
			for rel in data.relationships.values():
				if rel > 70.0:
					gain = 0.01
					break
		"chaos":
			# Chaos grows when mischief actions happen (tracked elsewhere).
			gain = data.traits.get("mischief", 0.0) * 0.005
		"peace":
			# Peace grows passively when mood is positive.
			if data.mood > 0.2:
				gain = 0.008
		"mastery", "knowledge":
			# Grows when expression need is well-filled.
			if data.get_need("expression") > 0.7:
				gain = 0.007
		"wealth":
			# Placeholder — will hook into item/trade system.
			gain = 0.002

	data.aspiration_progress = minf(data.aspiration_progress + gain, 1.0)
	data.fill_need("aspiration", gain * 2.0)


# ── Public API (matches test_cat.gd interface) ────────────────────────────────
# These are called by LocationBase, RumorManager, and FogPier.

func get_relationship_score(other_name: String) -> float:
	if data == null:
		return 0.0
	return data.get_relationship(other_name) + 50.0	# shift -100..100 to 0..100


func adjust_relationship(other_name: String, delta: float) -> void:
	if data == null:
		return

	# Apply zodiac compatibility modifier to the delta.
	var other: Node3D = _find_other_cat(other_name)
	var compat_mod: float = 0.0
	if other != null and other.data != null:
		compat_mod = ZodiacSystem.compatibility(data.zodiac_sign, other.data.zodiac_sign)

	var final_delta: float = delta * (1.0 + compat_mod)
	data.adjust_relationship(other_name, final_delta)
	data.recalculate_mood()


func adjust_mood(delta: float) -> void:
	if data == null:
		return
	# Mood is derived — nudge the belonging and social needs as a proxy.
	data.fill_need("social", delta * 0.3)
	data.fill_need("belonging", delta * 0.2)
	data.recalculate_mood()


func fill_need(need: String, amount: float) -> void:
	if data == null:
		return
	data.fill_need(need, amount)
	data.recalculate_mood()


# ── Helpers ───────────────────────────────────────────────────────────────────

func _find_other_cat(other_name: String) -> Node3D:
	for cat in get_tree().get_nodes_in_group("cat"):
		if cat.cat_name == other_name:
			return cat
	return null
