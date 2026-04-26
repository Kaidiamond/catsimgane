# cat_base.gd
# Attach to a CharacterBody3D. Replaces test_cat.gd entirely.
# Requires a CatData resource assigned in the Inspector.
#
# SCENE SETUP:
#   CharacterBody3D       ← this script
#   ├── MeshInstance3D    (CapsuleMesh placeholder)
#   ├── CollisionShape3D  (CapsuleShape3D radius 0.3 height 1.0)
#   └── NavigationAgent3D
extends CharacterBody3D

# ── Data ──────────────────────────────────────────────────────────────────────
@export var data: CatData

# ── Node refs ─────────────────────────────────────────────────────────────────
# Using find_child instead of $path so the node name casing doesn't matter.
var _nav_agent: NavigationAgent3D = null

# ── Need decay rates (per in-game day) ───────────────────────────────────────
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

const NEED_URGENT_THRESHOLD: float   = 0.35
const NEED_CRITICAL_THRESHOLD: float = 0.15

# ── Movement ──────────────────────────────────────────────────────────────────
const WALK_SPEED: float        = 2.5
const GRAVITY: float           = 9.8
const AI_THINK_INTERVAL: float = 4.0

var _current_destination: Vector3 = Vector3.ZERO
var _is_moving: bool               = false
var _ai_timer: float               = 0.0

# ── Computed property shortcuts ───────────────────────────────────────────────
# These let location_base.gd and rumor_manager.gd read cat properties
# the same way they did on test_cat.gd.

var cat_name: String :
	get: return data.cat_name if data else ""

var mood: float :
	get: return data.mood if data else 0.0

var traits: Dictionary :
	get: return data.traits if data else {}

var reputation: float :
	get: return data.reputation if data else 0.0
	set(v):
		if data:
			data.reputation = v

var current_location_id: String = ""

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	if data == null:
		push_error("[CatBase] No CatData assigned to '%s'. Assign a CatData .tres in the Inspector." % name)
		return

	# Strip whitespace and normalise case — catches Inspector typos like "pisces ".
	data.zodiac_sign = data.zodiac_sign.strip_edges().to_lower()

	ZodiacSystem.apply_caps(data)
	data.recalculate_mood()

	# Find NavigationAgent3D by type — immune to node name differences.
	for child in get_children():
		if child is NavigationAgent3D:
			_nav_agent = child
			break
	if _nav_agent == null:
		push_warning("[CatBase] No NavigationAgent3D found on '%s'. Add one as a child node." % name)

	add_to_group("cat")

	# Stagger AI timers so cats don't all think on the same frame.
	_ai_timer = randf_range(0.5, AI_THINK_INTERVAL)

	# Defer first destination by one frame.
	# NavigationAgent3D's map isn't ready on frame 0 — setting target_position
	# before the map is ready silently does nothing.
	call_deferred("_first_move")


func _first_move() -> void:
	_personality_wander()


func _physics_process(delta: float) -> void:
	if data == null:
		return
	_apply_gravity(delta)
	_move()


func _process(delta: float) -> void:
	if data == null:
		return
	_ai_timer -= delta
	if _ai_timer <= 0.0:
		_ai_timer = AI_THINK_INTERVAL
		_ai_think()


# ── Daily tick ────────────────────────────────────────────────────────────────
# Called by location_base.gd test mode and eventually by TimeManager.

func daily_tick() -> void:
	if data == null:
		return
	_decay_needs()
	data.recalculate_mood()
	_tick_aspiration()


# ── Need decay ────────────────────────────────────────────────────────────────

func _decay_needs() -> void:
	for need in NEED_DECAY_RATES:
		var base_rate: float        = NEED_DECAY_RATES[need]
		var zodiac_mod: float       = ZodiacSystem.need_decay_mod(data.zodiac_sign, need)
		var personality_mod: float  = _personality_decay_mod(need)
		data.set_need(need, data.get_need(need) - base_rate * zodiac_mod * personality_mod)


func _personality_decay_mod(need: String) -> float:
	match need:
		"social":
			return 0.5 + data.traits.get("sociability", 0.5)
		"belonging":
			return 0.7 + data.traits.get("empathy", 0.5) * 0.6
		"expression":
			return 0.6 + data.traits.get("creativity", 0.5) * 0.8
		"fun":
			return 0.7 + data.traits.get("mischief", 0.5) * 0.6
		_:
			return 1.0


# ── AI ────────────────────────────────────────────────────────────────────────

func _ai_think() -> void:
	var lowest: String = data.lowest_need()
	if data.get_need(lowest) < NEED_URGENT_THRESHOLD:
		_seek_need_location(lowest)
	else:
		_personality_wander()


func _seek_need_location(_need: String) -> void:
	# TODO: query GameState for best location once map screen is built.
	_personality_wander()


func _personality_wander() -> void:
	var sociability: float = data.traits.get("sociability", 0.5)
	var rand_offset: float = 5.0

	var target_x: float = randf_range(-rand_offset, rand_offset)
	var target_z: float = randf_range(-rand_offset, rand_offset)

	# Shy cats (low sociability) spread to edges.
	# Bold cats (high sociability) drift toward centre.
	target_x = lerp(target_x, 0.0, sociability * 0.5)
	target_z = lerp(target_z, 0.0, sociability * 0.5)
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


func _move() -> void:
	if not _is_moving:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return

	var next_pos: Vector3

	var use_nav: bool = _nav_agent != null \
		and _nav_agent.is_target_reachable() \
		and not _nav_agent.is_navigation_finished()

	if use_nav:
		next_pos = _nav_agent.get_next_path_position()
	else:
		# Nav mesh not baked or not reachable — walk directly.
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

func _tick_aspiration() -> void:
	var gain: float = 0.0
	match data.aspiration_type:
		"fame":
			if data.reputation > 20.0:
				gain = 0.01
		"love":
			for rel in data.relationships.values():
				if rel > 70.0:
					gain = 0.01
					break
		"chaos":
			gain = data.traits.get("mischief", 0.0) * 0.005
		"peace":
			if data.mood > 0.2:
				gain = 0.008
		"mastery", "knowledge":
			if data.get_need("expression") > 0.7:
				gain = 0.007
		"wealth":
			gain = 0.002

	data.aspiration_progress = minf(data.aspiration_progress + gain, 1.0)
	data.fill_need("aspiration", gain * 2.0)


# ── Public API ────────────────────────────────────────────────────────────────
# Interface matches test_cat.gd so LocationBase and RumorManager work unchanged.

func get_relationship_score(other_name: String) -> float:
	if data == null:
		return 50.0
	# CatData stores -100..100, callers expect 0..100 — shift by 50.
	return clamp(data.get_relationship(other_name) + 50.0, 0.0, 100.0)


func adjust_relationship(other_name: String, delta: float) -> void:
	if data == null:
		return
	var other: Node3D       = _find_other_cat(other_name)
	var compat_mod: float   = 0.0
	if other != null and "data" in other and other.data != null:
		compat_mod = ZodiacSystem.compatibility(data.zodiac_sign, other.data.zodiac_sign)
	data.adjust_relationship(other_name, delta * (1.0 + compat_mod))
	data.recalculate_mood()


func adjust_mood(delta: float) -> void:
	if data == null:
		return
	data.fill_need("social", delta * 0.3)
	data.fill_need("belonging", delta * 0.2)
	data.recalculate_mood()


func fill_need(need: String, amount: float) -> void:
	if data == null:
		return
	data.fill_need(need, amount)
	data.recalculate_mood()


func mood_label() -> String:
	if data == null:
		return "unknown"
	return data.mood_label()


# ── Helpers ───────────────────────────────────────────────────────────────────

func _find_other_cat(other_name: String) -> Node3D:
	for cat in get_tree().get_nodes_in_group("cat"):
		if cat.cat_name == other_name:
			return cat
	return null
