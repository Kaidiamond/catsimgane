# cat_data.gd
# Pure Resource — no Node, no scene. Holds everything persistent about one cat.
# Save a cat by saving this resource to disk with ResourceSaver.save().
# Load it back with ResourceLoader.load().
class_name CatData
extends Resource

# ── Identity ──────────────────────────────────────────────────────────────────
@export var cat_name: String        = ""
@export var display_name: String    = ""	# shown in UI, can differ from cat_name
@export var age_days: int           = 0

# ── Zodiac ────────────────────────────────────────────────────────────────────
## One of 12 string keys matching ZodiacSystem.SIGNS.
@export var zodiac_sign: String     = "libra"

# ── Personality traits ────────────────────────────────────────────────────────
## All floats 0.0–1.0. These are the BASE values before zodiac caps are applied.
## ZodiacSystem.apply_caps(cat_data) clamps them on first load.
@export var traits: Dictionary = {
	"sociability":   0.5,	# how much they seek out other cats
	"stubbornness":  0.5,	# resistance to relationship changes
	"creativity":    0.5,	# mutates rumors, expressive outbursts
	"credulity":     0.5,	# believes rumors readily
	"gossip":        0.5,	# spreads rumors actively
	"memory":        0.5,	# remembers rumors accurately
	"mischief":      0.5,	# chance to fabricate rumors when fun is low
	"empathy":       0.5,	# belonging need decay rate modifier
}

# ── Personality type ──────────────────────────────────────────────────────────
## Broad label used to gate certain interactions.
## One of: "bold", "shy", "mischievous", "gentle", "dramatic", "stoic"
@export var personality_type: String = "gentle"

# ── Quirk ─────────────────────────────────────────────────────────────────────
## One weird specific trait. Drives unique dialogue and unexpected conflicts.
## Examples: "only_eats_fish", "hates_rain", "collects_bottlecaps", "sleeps_north"
@export var quirk: String           = ""

# ── Aspiration ────────────────────────────────────────────────────────────────
## What this cat is working toward. Feeds the Aspiration need.
## One of: "fame", "love", "mastery", "chaos", "peace", "wealth", "knowledge"
@export var aspiration_type: String = "peace"

## 0.0–1.0 progress toward the aspiration. Fills slowly via goal-aligned actions.
@export var aspiration_progress: float = 0.0

# ── Memory object ─────────────────────────────────────────────────────────────
## Key identifying this cat's treasured object. Shown at the Memory Garden.
## When two cats visit at the same time and see each other's objects,
## it unlocks deep relationship dialogue.
@export var memory_object_key: String = ""

# ── Needs ─────────────────────────────────────────────────────────────────────
## All values 0.0 (empty) to 1.0 (fully satisfied).
## CatBase decays these each game tick based on NEED_DECAY_RATES.
@export var needs: Dictionary = {
	"hunger":     1.0,
	"sleep":      1.0,
	"social":     1.0,
	"fun":        1.0,
	"expression": 1.0,
	"belonging":  1.0,
	"hygiene":    1.0,
	"aspiration": 1.0,
}

# ── Mood ──────────────────────────────────────────────────────────────────────
## Derived each tick from needs. -1.0 (miserable) to 1.0 (happy).
## Not exported — recalculated at runtime, never saved directly.
var mood: float = 0.0

# ── Relationships ─────────────────────────────────────────────────────────────
## Key = other cat_name, value = float -100.0 to 100.0.
## Positive = friendly, negative = rival.
@export var relationships: Dictionary = {}

# ── Reputation ────────────────────────────────────────────────────────────────
## Island-wide reputation score. Modified by crystallized rumors.
@export var reputation: float = 0.0

# ── Home location ─────────────────────────────────────────────────────────────
## Which location this cat "lives" at. Used for sleep and hygiene filling.
@export var home_location_id: String = "clocktower_cafe"

# ── Helpers ───────────────────────────────────────────────────────────────────

func get_relationship(other_name: String) -> float:
	return relationships.get(other_name, 0.0)


func set_relationship(other_name: String, value: float) -> void:
	relationships[other_name] = clamp(value, -100.0, 100.0)


func adjust_relationship(other_name: String, delta: float) -> void:
	# Stubbornness resists change in both directions.
	var resistance: float = traits.get("stubbornness", 0.5)
	var actual_delta: float = delta * (1.0 - resistance * 0.5)
	set_relationship(other_name, get_relationship(other_name) + actual_delta)


func get_need(need: String) -> float:
	return needs.get(need, 1.0)


func set_need(need: String, value: float) -> void:
	needs[need] = clamp(value, 0.0, 1.0)


func fill_need(need: String, amount: float) -> void:
	set_need(need, get_need(need) + amount)


func lowest_need() -> String:
	var lowest_key: String = ""
	var lowest_val: float  = 1.1
	for key in needs:
		if needs[key] < lowest_val:
			lowest_val = needs[key]
			lowest_key = key
	return lowest_key


## Recalculates mood from current needs. Call after any need changes.
## Weighted so hunger and sleep matter most, aspiration matters least acutely.
func recalculate_mood() -> void:
	var weights: Dictionary = {
		"hunger":     0.25,
		"sleep":      0.20,
		"social":     0.15,
		"fun":        0.12,
		"expression": 0.10,
		"belonging":  0.10,
		"hygiene":    0.05,
		"aspiration": 0.03,
	}
	var total: float = 0.0
	for need in weights:
		total += needs.get(need, 1.0) * weights[need]
	# Map 0–1 weighted average to -1..1 mood range.
	mood = clamp((total - 0.5) * 2.0, -1.0, 1.0)


func mood_label() -> String:
	if mood >= 0.6:   return "happy"
	if mood >= 0.2:   return "content"
	if mood >= -0.2:  return "neutral"
	if mood >= -0.6:  return "sad"
	return "miserable"
