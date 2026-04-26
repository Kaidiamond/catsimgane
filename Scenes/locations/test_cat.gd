# test_cat.gd
# Attach to a CharacterBody3D in any location scene.
# This is a throwaway test script — it stubs every method that
# location_base.gd calls on a cat so the full location system can
# run without CatBase being written yet.
#
# SETUP CHECKLIST (do this once per test cat node):
#   1. Create a CharacterBody3D in the scene
#   2. Attach this script to it
#   3. Add the node to the "cat" group (Node tab → Groups → Add "cat")
#   4. Set cat_name in the Inspector
#   5. Add a CollisionShape3D child (CapsuleShape3D, radius 0.3 height 1.0)
#   6. Add a MeshInstance3D child (CapsuleMesh as placeholder body)
#   7. Call location.register_cat(self) from the location's _ready,
#      OR use the test_location_setup.gd autorun script below.
extends CharacterBody3D

# ── Identity (set in Inspector) ───────────────────────────────────────────────
@export var cat_name: String = "test_cat"
@export var start_mood: float = 0.0
@export var start_relationship: float = 50.0

# ── Traits (used by RumorManager) ────────────────────────────────────────────
## All values 0.0–1.0. RumorManager reads these via .get() so they must exist.
var traits: Dictionary = {
	"gossip":     0.7,	# high = spreads rumors readily
	"credulity":  0.6,	# high = believes rumors easily
	"creativity": 0.3,	# high = mutates rumors when retelling
	"memory":     0.8,	# high = remembers rumors accurately
}

# ── State ─────────────────────────────────────────────────────────────────────
var mood: float = 0.0

## Relationship scores. Key = other cat_name, value = float 0–100.
var _relationships: Dictionary = {}

## Where this cat wants to walk next.
var _target_position: Vector3 = Vector3.ZERO
var _is_moving: bool = false

# ── Movement tuning ───────────────────────────────────────────────────────────
const WALK_SPEED: float       = 2.5
const ARRIVE_DISTANCE: float  = 0.3
const WANDER_INTERVAL_MIN: float = 3.0
const WANDER_INTERVAL_MAX: float = 8.0

## How far from origin the cat is allowed to wander (half-extents of the room).
@export var wander_radius: float = 7.0

var _wander_timer: float = 0.0

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	mood = start_mood
	add_to_group("cat")			# belt-and-suspenders in case group wasn't set in editor
	_wander_timer = randf_range(WANDER_INTERVAL_MIN, WANDER_INTERVAL_MAX)
	_pick_new_target()


func _physics_process(delta: float) -> void:
	_tick_wander(delta)
	_move_toward_target(delta)


# ── Wander loop ───────────────────────────────────────────────────────────────

func _tick_wander(delta: float) -> void:
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_wander_timer = randf_range(WANDER_INTERVAL_MIN, WANDER_INTERVAL_MAX)
		_pick_new_target()


func _pick_new_target() -> void:
	# Pick a random point clamped to the room interior (floor is 20x20).
	var half: float = wander_radius
	_target_position = Vector3(
		clamp(global_position.x + randf_range(-half, half), -8.0, 8.0),
		0.1,
		clamp(global_position.z + randf_range(-half, half), -8.0, 8.0)
	)
	_is_moving = true


func _move_toward_target(delta: float) -> void:
	# Gravity accumulates every frame regardless of movement state.
	if not is_on_floor():
		velocity.y -= 9.8 * delta

	if not _is_moving:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return

	var diff: Vector3 = _target_position - global_position
	diff.y = 0.0

	if diff.length() < ARRIVE_DISTANCE:
		_is_moving = false
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return

	var direction := diff.normalized()
	velocity.x = direction.x * WALK_SPEED
	velocity.z = direction.z * WALK_SPEED
	move_and_slide()


# ── API stubs (called by location_base.gd) ────────────────────────────────────

## Returns this cat's relationship score with another cat (0–100).
## location_base.gd calls this to decide if an interaction is rumor-worthy.
func get_relationship_score(other_cat_name: String) -> float:
	return _relationships.get(other_cat_name, start_relationship)


## Shifts the relationship score with another cat by delta (positive or negative).
func adjust_relationship(other_cat_name: String, delta: float) -> void:
	var current: float = _relationships.get(other_cat_name, start_relationship)
	_relationships[other_cat_name] = clamp(current + delta, 0.0, 100.0)
	print("[TestCat] %s → %s relationship: %.1f" % [
		cat_name, other_cat_name, _relationships[other_cat_name]
	])


## Shifts mood by delta. Clamped to -1..1.
func adjust_mood(delta: float) -> void:
	mood = clamp(mood + delta, -1.0, 1.0)
	print("[TestCat] %s mood: %.2f" % [cat_name, mood])


## Convenience: returns mood as a readable label for the debug overlay.
func mood_label() -> String:
	if mood >= 0.6:   return "happy"
	if mood >= 0.2:   return "content"
	if mood >= -0.2:  return "neutral"
	if mood >= -0.6:  return "sad"
	return "miserable"


# ── Reputation stub ───────────────────────────────────────────────────────────
# RumorManager._apply_reputation_effect() writes to cat.reputation.
# Declare it here so the assignment doesn't crash.
var reputation: float = 0.0
