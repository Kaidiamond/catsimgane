# rumor_manager.gd
# Add as an Autoload singleton (Project → Project Settings → Autoload).
# Depends on: Rumor (rumor.gd), CatBase (your cat node/resource),
#             RumorTemplates (rumor_templates.gd, optional helper).
extends Node

# ── Active state ──────────────────────────────────────────────────────────────
var active_rumors: Array[Rumor] = []

# ── Location modifiers ────────────────────────────────────────────────────────
## decay_mod < 1.0  → rumor stays hot longer (Theater keeps drama alive)
## decay_mod > 1.0  → rumor cools faster    (Market buries it underground)
const LOCATION_DECAY_MOD: Dictionary = {
	"abandoned_theater":     0.5,
	"mushroom_market":       1.8,
	"clocktower_cafe":       0.7,
	"lighthouse_laundromat": 0.9,
	"fog_pier":              1.2,
	"sunken_greenhouse":     1.1,
	"rooftop_observatory":   0.8,
	"noodle_cart_alley":     0.85,
	"tide_pool_arcade":      1.0,
	"memory_garden":         0.95,
}

## spread_amp > 1.0 → more likely to pass along during a conversation
## spread_amp < 1.0 → gossip stays muffled
const LOCATION_SPREAD_AMP: Dictionary = {
	"abandoned_theater":     2.0,
	"mushroom_market":       0.4,
	"clocktower_cafe":       1.5,
	"lighthouse_laundromat": 1.3,
	"fog_pier":              0.6,
	"sunken_greenhouse":     0.8,
	"rooftop_observatory":   1.1,
	"noodle_cart_alley":     1.2,
}

## Base decay rates per rumor type.
## Trait rumors linger longest; fabricated action rumors burn fast.
const BASE_DECAY: Dictionary = {
	"action":       0.09,
	"trait":        0.05,
	"relationship": 0.10,
	"secret":       0.06,
}

# Crystallization thresholds
const CRYSTAL_SPREAD_RATIO: float = 0.5	# 1 out of 2 cats = crystallizes
const CRYSTAL_AVG_BELIEF:   float = 0.4	# lowered so test cats can trigger it
const MIN_BELIEF_TO_SPREAD: float = 0.2	# lowered from 0.3
const BASE_SPREAD_CHANCE:   float = 0.8	# raised from 0.35 — ensures spread with 2 cats

# ── Public API ────────────────────────────────────────────────────────────────

## Call once per in-game day from your main game loop.
## cats        – Array of all CatBase nodes/resources on the island
## location_map – Dictionary mapping cat_name → current location key (String)
func daily_tick(cats: Array, location_map: Dictionary) -> void:
	_pass_decay(location_map)
	_pass_spread(cats, location_map)
	_pass_crystallize(cats)


## Create a rumor from something that actually happened.
## event must contain: subject, type, description, witness, location
func create_from_event(event: Dictionary) -> Rumor:
	var r := Rumor.new()
	r.id               = "rumor_%d" % randi()
	r.subject          = event.get("subject", "")
	r.type             = event.get("type", "action")
	r.content          = event.get("description", "")
	r.is_true          = true
	r.origin           = event.get("witness", "")
	r.origin_location  = event.get("location", "")
	r.heat             = 1.0
	r.decay_rate       = BASE_DECAY.get(r.type, 0.08)
	r.known_by         = { r.origin: 1.0 }
	active_rumors.append(r)
	return r


## Create a deliberately false rumor from a jealous or malicious cat.
## fabricator – CatBase of the cat making it up
## subject_name – cat_name of the target
func create_fabricated(fabricator: Object, subject_name: String, cats: Array) -> Rumor:
	var r := Rumor.new()
	r.id              = "rumor_fab_%d" % randi()
	r.subject         = subject_name
	r.type            = (["action", "trait", "relationship"] as Array).pick_random()
	r.is_true         = false
	r.origin          = fabricator.cat_name
	r.origin_location = ""          # will be set to wherever fabricator currently is
	r.heat            = 0.7         # starts a bit cooler than real events
	r.decay_rate      = 0.12        # false rumors burn out faster once doubted
	r.known_by        = { fabricator.cat_name: 1.0 }

	var subject: Object = _find_cat(cats, subject_name)
	r.content = _generate_false_content(r.type, subject, fabricator)

	active_rumors.append(r)
	return r


## Returns all rumors known by a specific cat above a belief threshold.
func rumors_known_by(cat_name: String, min_belief: float = 0.1) -> Array[Rumor]:
	var result: Array[Rumor] = []
	for rumor in active_rumors:
		if rumor.known_by.get(cat_name, 0.0) >= min_belief:
			result.append(rumor)
	return result


## Returns all crystallized rumors about a subject (for reputation display).
func crystallized_about(subject_name: String) -> Array[Rumor]:
	var result: Array[Rumor] = []
	for rumor in active_rumors:
		if rumor.subject == subject_name and rumor.crystallized:
			result.append(rumor)
	return result


# ── Pass 1: Decay ─────────────────────────────────────────────────────────────

func _pass_decay(location_map: Dictionary) -> void:
	var to_remove: Array[Rumor] = []

	for rumor in active_rumors:
		rumor.age_days += 1

		# Crystallized rumors are permanent — skip heat decay.
		if rumor.crystallized:
			continue

		var loc_mod: float = _dominant_location_decay_mod(rumor, location_map)
		rumor.heat -= rumor.decay_rate * loc_mod
		rumor.heat = maxf(rumor.heat, 0.0)

		if rumor.heat <= 0.0:
			to_remove.append(rumor)

	for r in to_remove:
		active_rumors.erase(r)


## Find whichever location currently holds the most believers of this rumor,
## then return that location's decay modifier.
func _dominant_location_decay_mod(rumor: Rumor, location_map: Dictionary) -> float:
	var loc_counts: Dictionary = {}

	for cat_name in rumor.known_by:
		var loc: String = location_map.get(cat_name, "")
		if loc.is_empty():
			continue
		loc_counts[loc] = loc_counts.get(loc, 0) + 1

	if loc_counts.is_empty():
		return 1.0

	# Find the key with the highest count.
	var best_loc: String = ""
	var best_count: int = -1
	for loc in loc_counts:
		if loc_counts[loc] > best_count:
			best_count = loc_counts[loc]
			best_loc   = loc

	return LOCATION_DECAY_MOD.get(best_loc, 1.0)


# ── Pass 2: Spread ────────────────────────────────────────────────────────────

func _pass_spread(cats: Array, location_map: Dictionary) -> void:
	# Work on a snapshot so mutations appended mid-loop don't iterate themselves.
	var snapshot: Array[Rumor] = active_rumors.duplicate()

	for rumor in snapshot:
		# Collect cats who believe it strongly enough to repeat it.
		var spreaders: Array = []
		for cat_name in rumor.known_by:
			if rumor.known_by[cat_name] >= MIN_BELIEF_TO_SPREAD:
				spreaders.append(cat_name)

		for teller_name in spreaders:
			var teller: Object = _find_cat(cats, teller_name)
			if teller == null:
				continue

			var teller_loc: String = location_map.get(teller_name, "")
			if teller_loc.is_empty():
				continue

			# Collect listeners: same location, not the teller, not the subject.
			var listeners: Array = []
			for cat in cats:
				var cat_loc: String = location_map.get(cat.cat_name, "")
				if cat_loc == teller_loc \
						and cat.cat_name != teller_name \
						and cat.cat_name != rumor.subject:
					listeners.append(cat)

			for listener in listeners:
				_attempt_transfer(rumor, teller, listener, teller_loc)


func _attempt_transfer(
		rumor: Rumor,
		teller: Object,
		listener: Object,
		location: String) -> void:

	# Chance this topic even comes up in conversation.
	var gossip_stat: float   = teller.traits.get("gossip", 0.5)
	var spread_chance: float = BASE_SPREAD_CHANCE + gossip_stat * 0.3
	spread_chance           *= LOCATION_SPREAD_AMP.get(location, 1.0)

	if randf() > spread_chance:
		return

	# ── Belief calculation ────────────────────────────────────────────────────

	# How much does the listener trust the teller? (relationship score 0–100 → 0–1)
	var raw_trust: float     = listener.get_relationship_score(teller.cat_name)
	var teller_trust: float  = clamp(raw_trust / 100.0, 0.1, 1.0)

	# How readily does this listener believe things in general?
	var credulity: float = listener.traits.get("credulity", 0.5)

	# Bias: listeners who dislike the subject are quicker to believe bad rumors.
	var bias: float = 1.0
	if not rumor.is_true:
		var rel_to_subject: float = listener.get_relationship_score(rumor.subject) / 100.0
		# rel_to_subject near 1.0 → bias < 1 (they resist the rumor)
		# rel_to_subject near 0.0 → bias up to 1.4 (they eagerly believe it)
		bias = clamp(1.0 - rel_to_subject * 0.6, 0.2, 1.4)

	var teller_belief: float     = rumor.known_by.get(teller.cat_name, 0.5)
	var transferred_belief: float = clamp(
		teller_belief * teller_trust * credulity * bias,
		0.0,
		1.0
	)

	# ── Mutation check ────────────────────────────────────────────────────────
	# Creative or forgetful cats accidentally garble details, forking the rumor.
	var creativity: float = listener.traits.get("creativity", 0.3)
	var memory: float     = listener.traits.get("memory", 0.7)
	var mutation_threshold: float = creativity * 0.4 + (1.0 - memory) * 0.3

	if randf() < mutation_threshold:
		# Fork: the listener will spread the mutated version, not the original.
		var mutated: Rumor = _fork_rumor(rumor, listener)
		mutated.known_by[listener.cat_name] = transferred_belief
		return   # listener now "knows" the mutation, not the parent

	# ── Update known_by ───────────────────────────────────────────────────────
	if rumor.known_by.has(listener.cat_name):
		# Heard it before — average in the reinforcing belief.
		var existing: float = rumor.known_by[listener.cat_name]
		rumor.known_by[listener.cat_name] = (existing + transferred_belief) / 2.0
	else:
		rumor.known_by[listener.cat_name] = transferred_belief

	# Spreading the rumor gives it a small heat bump.
	rumor.heat = minf(rumor.heat + 0.1, 1.0)


## Fork a rumor: create a mutated child with altered content.
## The child is appended to active_rumors; the parent records the mutation.
func _fork_rumor(parent: Rumor, mutator: Object) -> Rumor:
	var child := Rumor.new()
	child.id              = "%s_mut%d" % [parent.id, randi() % 1000]
	child.subject         = parent.subject
	child.type            = parent.type
	child.is_true         = false                  # mutations are always false
	child.origin          = mutator.cat_name
	child.origin_location = parent.origin_location
	child.heat            = parent.heat * 0.7
	child.decay_rate      = parent.decay_rate * 1.2
	child.content         = _pick_mutation_content(parent, mutator)
	child.known_by        = {}                     # caller sets the listener entry

	parent.mutations.append({
		"mutated_id": child.id,
		"mutator":    mutator.cat_name,
		"day":        parent.age_days,
	})

	active_rumors.append(child)
	return child


# ── Pass 3: Crystallize ───────────────────────────────────────────────────────

func _pass_crystallize(cats: Array) -> void:
	var total_cats: float = float(cats.size())
	if total_cats == 0.0:
		return

	for rumor in active_rumors:
		if rumor.crystallized:
			continue

		var knowing_count: float = float(rumor.known_by.size())
		if knowing_count == 0.0:
			continue

		# Average belief across everyone who knows it.
		var belief_sum: float = 0.0
		for belief in rumor.known_by.values():
			belief_sum += belief
		var avg_belief: float = belief_sum / knowing_count

		var spread_ratio: float = knowing_count / total_cats

		if spread_ratio >= CRYSTAL_SPREAD_RATIO and avg_belief >= CRYSTAL_AVG_BELIEF:
			rumor.crystallized = true
			_apply_reputation_effect(rumor, cats)


func _apply_reputation_effect(rumor: Rumor, cats: Array) -> void:
	var subject: Object = _find_cat(cats, rumor.subject)
	if subject == null:
		return

	# Reputation delta — false/leaked secrets hurt more than good deeds help.
	var rep_delta: float
	match rumor.type:
		"action":
			rep_delta = 10.0 if rumor.is_true else -18.0
		"trait":
			rep_delta = 8.0  if rumor.is_true else -12.0
		"relationship":
			rep_delta = -8.0                           # exposure always stings
		"secret":
			rep_delta = -22.0                          # secrets hurt most
		_:
			rep_delta = -10.0

	subject.reputation = clamp(subject.reputation + rep_delta, -100.0, 100.0)

	# Each believer also adjusts their personal relationship with the subject.
	for cat_name in rumor.known_by:
		if cat_name == rumor.subject:
			continue
		var believer: Object = _find_cat(cats, cat_name)
		if believer == null:
			continue
		var belief: float    = rumor.known_by[cat_name]
		var rel_delta: float = rep_delta * belief * 0.4
		believer.adjust_relationship(rumor.subject, rel_delta)


# ── Content helpers ───────────────────────────────────────────────────────────
# Replace these stubs with lookups into your RumorTemplates resource.

func _pick_mutation_content(original: Rumor, _mutator: Object) -> String:
	# Example: pull from a template table keyed by original.type.
	# For now, append a generic embellishment so the game is at least playable.
	var embellishments: Array = [
		"and apparently it was even worse than that",
		"and it happened more than once",
		"and someone else was involved too",
		"but only at night, apparently",
	]
	return original.content + " — " + embellishments.pick_random()


func _generate_false_content(type: String, subject: Object, _fabricator: Object) -> String:
	# Replace with RumorTemplates.generate(type, subject) once that resource exists.
	if subject == null:
		return "someone did something suspicious"
	match type:
		"action":
			return "%s was seen doing something suspicious near the market" % subject.cat_name
		"trait":
			return "%s has been hiding something about their past" % subject.cat_name
		"relationship":
			return "%s has been secretly meeting someone after dark" % subject.cat_name
		_:
			return "%s is not who they seem" % subject.cat_name


# ── Utility ───────────────────────────────────────────────────────────────────

func _find_cat(cats: Array, cat_name: String) -> Object:
	for cat in cats:
		if cat.cat_name == cat_name:
			return cat
	return null
