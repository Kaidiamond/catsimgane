# fog_pier.gd
# Attach to the root node of fog_pier.tscn (which inherits location_base.tscn).
# The Fog Pier suppresses normal rumor spread and queues dream entry for sad cats.
#
# WHY extends with a file path:
#   GDScript 4 resolves class_name declarations only after the editor has fully
#   indexed the project. Using the explicit path guarantees resolution even on a
#   fresh project open or before a full reimport.
class_name FogPier
extends "res://scripts/locations/location_base.gd"

# ── Dream entry signal ────────────────────────────────────────────────────────
## Emitted when a sad cat lingers here long enough to fall asleep.
## DreamManager (not yet written) listens for this.
signal dream_entry_available(cat: Node3D)

## Mood threshold below which a cat is considered "sad enough" for dream entry.
const DREAM_MOOD_THRESHOLD: float = -0.4

## How many seconds a sad cat must stay before dream entry is offered.
const DREAM_LINGER_SECONDS: float = 8.0

## Tracks how long each sad cat has been lingering. Key = cat_name, value = float.
var _linger_timers: Dictionary = {}

# ── Setup ─────────────────────────────────────────────────────────────────────

func _on_location_ready() -> void:
	location_id           = "fog_pier"
	location_display_name = "Fog Pier"
	rumor_spread_modifier = 0.6		# Rumors shared here spread less — feels private.
	rumor_decay_modifier  = 1.2		# But they also fade faster; secrets stay at the pier.


# ── Per-frame linger tracking ─────────────────────────────────────────────────

func _on_location_process(delta: float) -> void:
	for cat_name in cats_present:
		var cat: Node3D = cats_present[cat_name]
		if _is_sad(cat):
			_linger_timers[cat_name] = _linger_timers.get(cat_name, 0.0) + delta
			if _linger_timers[cat_name] >= DREAM_LINGER_SECONDS:
				_linger_timers.erase(cat_name)
				emit_signal("dream_entry_available", cat)
		else:
			_linger_timers.erase(cat_name)


func _is_sad(cat: Node3D) -> bool:
	# mood is a float normalised to -1.0..1.0 on CatBase.
	return cat.mood <= DREAM_MOOD_THRESHOLD


# ── Cat entry ─────────────────────────────────────────────────────────────────

func _on_cat_entered(cat: Node3D) -> void:
	# Sad cats get a subtle visual cue: a dream-portal glow appears above them.
	# The glow node lives on the cat itself; we just enable it.
	if _is_sad(cat) and cat.has_node("DreamGlow"):
		cat.get_node("DreamGlow").visible = true


func _on_cat_exited(cat: Node3D) -> void:
	_linger_timers.erase(cat.cat_name)
	if cat.has_node("DreamGlow"):
		cat.get_node("DreamGlow").visible = false


# ── Interaction override ───────────────────────────────────────────────────────

func _on_interaction_triggered(cat_a: Node3D, cat_b: Node3D, zone: Area3D) -> void:
	# Two lonely cats bumping into each other at the Fog Pier is meaningful.
	# Force the relationship event regardless of their score, but keep it quiet —
	# don't call super(), so no rumor fires from the base class.
	# Instead, give both cats a small mood boost (shared loneliness = connection).
	cat_a.adjust_mood(0.12)
	cat_b.adjust_mood(0.12)

	# Quietly nudge their relationship score toward each other.
	cat_a.adjust_relationship(cat_b.cat_name, 5.0)
	cat_b.adjust_relationship(cat_a.cat_name, 5.0)
