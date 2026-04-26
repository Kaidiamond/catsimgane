# location_base.gd
# Attach to the root Node3D of location_base.tscn.
# Every specific location scene inherits this scene and overrides the
# virtual methods below to add its own flavour.
#
# TEST MODE: set `test_mode = true` in the Inspector on the root node.
# It will auto-register any cats in the scene, print all signals to Output,
# show a live debug overlay, and fire a rumor day tick every few seconds.
# No second script needed — everything lives here.
#
# AUTOLOAD SETUP REQUIRED (Project → Project Settings → Autoload):
#   rumor_manager.gd  →  name: "RumorManager"
extends Node3D

# ── Inspector exports ─────────────────────────────────────────────────────────
@export var location_id: String           = "location_base"
@export var location_display_name: String = "Unknown Location"
@export var rumor_spread_modifier: float  = 1.0
@export var rumor_decay_modifier: float   = 1.0

## Turn on to auto-register cats, print signals, and show the debug overlay.
@export var test_mode: bool               = false
@export var test_day_tick_interval: float = 10.0

# ── Node refs ─────────────────────────────────────────────────────────────────
@onready var _spawn_points: Node3D           = $SpawnPoints
@onready var _interaction_zones: Node3D      = $InteractionZones
@onready var _ui_layer: CanvasLayer          = $UILayer
@onready var _location_label: Label          = $UILayer/LocationLabel

# ── Runtime state ─────────────────────────────────────────────────────────────
## Key = cat_name (String), value = cat Node3D.
var cats_present: Dictionary = {}

## Key = "catA:catB" sorted, value = seconds remaining on cooldown.
var _interaction_cooldowns: Dictionary = {}

const INTERACTION_COOLDOWN_SEC: float = 12.0

# ── Test-mode state ───────────────────────────────────────────────────────────
var _test_tick_timer: float     = 0.0
var _debug_label: RichTextLabel = null

# ── Signals ───────────────────────────────────────────────────────────────────
signal cat_entered(cat: Node3D)
signal cat_exited(cat: Node3D)
signal interaction_started(cat_a: Node3D, cat_b: Node3D, zone: Area3D)
signal location_event_fired(event: Dictionary)

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	_location_label.text = location_display_name
	_connect_zone_signals()
	_on_location_ready()

	if test_mode:
		_test_setup()


func _process(delta: float) -> void:
	_tick_cooldowns(delta)
	_on_location_process(delta)

	if test_mode:
		_test_process(delta)


# ── Spawn point API ───────────────────────────────────────────────────────────

func get_free_spawn_point() -> Marker3D:
	var all_points: Array[Marker3D] = []
	for child in _spawn_points.get_children():
		if child is Marker3D:
			all_points.append(child)

	all_points.shuffle()
	for point in all_points:
		if not _spawn_point_is_occupied(point):
			return point

	if all_points.size() > 0:
		return all_points[0]
	return null


func _spawn_point_is_occupied(point: Marker3D) -> bool:
	for cat in cats_present.values():
		if (cat as Node3D).global_position.distance_to(point.global_position) < 1.2:
			return true
	return false


# ── Cat presence ──────────────────────────────────────────────────────────────

func register_cat(cat: Node3D) -> void:
	if cat.cat_name in cats_present:
		return
	cats_present[cat.cat_name] = cat
	cat_entered.emit(cat)
	_on_cat_entered(cat)
	_maybe_trigger_special(cat)


func unregister_cat(cat: Node3D) -> void:
	if not cat.cat_name in cats_present:
		return
	cats_present.erase(cat.cat_name)
	cat_exited.emit(cat)
	_on_cat_exited(cat)


func get_cats() -> Array:
	return cats_present.values()


func get_location_key() -> String:
	return location_id


func get_location_map_slice() -> Dictionary:
	var slice: Dictionary = {}
	for cat_name in cats_present:
		slice[cat_name] = location_id
	return slice


# ── Interaction zone wiring ───────────────────────────────────────────────────

func _connect_zone_signals() -> void:
	for child in _interaction_zones.get_children():
		if child is Area3D:
			child.body_entered.connect(_on_zone_body_entered.bind(child))
			child.body_exited.connect(_on_zone_body_exited.bind(child))


func _on_zone_body_entered(body: Node3D, zone: Area3D) -> void:
	if not body.is_in_group("cat"):
		return
	for other_cat in cats_present.values():
		if other_cat == body:
			continue
		if _zone_contains(zone, other_cat):
			_try_trigger_interaction(body, other_cat, zone)


func _on_zone_body_exited(_body: Node3D, _zone: Area3D) -> void:
	pass


func _zone_contains(_zone: Area3D, cat: Node3D) -> bool:
	# The zone covers the whole floor — any registered cat counts as "in" it.
	return cat.cat_name in cats_present


# ── Interaction triggering ────────────────────────────────────────────────────

func _try_trigger_interaction(cat_a: Node3D, cat_b: Node3D, zone: Area3D) -> void:
	var key: String = _cooldown_key(cat_a, cat_b)
	if _interaction_cooldowns.get(key, 0.0) > 0.0:
		return

	_interaction_cooldowns[key] = INTERACTION_COOLDOWN_SEC
	interaction_started.emit(cat_a, cat_b, zone)
	_on_interaction_triggered(cat_a, cat_b, zone)

	var event: Dictionary = _build_interaction_event(cat_a, cat_b)
	if event.size() > 0:
		location_event_fired.emit(event)
		var rm: Node = get_node_or_null("/root/RumorManager")
		if rm != null:
			rm.create_from_event(event)


func _build_interaction_event(cat_a: Node3D, cat_b: Node3D) -> Dictionary:
	var rel: float = cat_a.get_relationship_score(cat_b.cat_name)

	# Nudge relationship a little each interaction so scores drift over time.
	var nudge: float = 3.0 if rel >= 50.0 else -3.0
	cat_a.adjust_relationship(cat_b.cat_name, nudge)
	cat_b.adjust_relationship(cat_a.cat_name, nudge)

	# Always return an event so test mode can see interactions firing.
	var event_type: String  = "action" if rel < 50.0 else "relationship"
	var description: String = ""

	if rel < 50.0:
		description = "%s and %s had a tense exchange at %s" % [
			cat_a.cat_name, cat_b.cat_name, location_display_name
		]
	else:
		description = "%s and %s seemed friendly at %s" % [
			cat_a.cat_name, cat_b.cat_name, location_display_name
		]

	return {
		"subject":     cat_a.cat_name,
		"type":        event_type,
		"description": description,
		"witness":     cat_b.cat_name,
		"location":    location_id,
	}


# ── Cooldown helpers ──────────────────────────────────────────────────────────

func _cooldown_key(cat_a: Node3D, cat_b: Node3D) -> String:
	var names: Array = [cat_a.cat_name, cat_b.cat_name]
	names.sort()
	return "%s:%s" % [names[0], names[1]]


func _tick_cooldowns(delta: float) -> void:
	for key in _interaction_cooldowns.keys():
		_interaction_cooldowns[key] -= delta
		if _interaction_cooldowns[key] <= 0.0:
			_interaction_cooldowns.erase(key)


# ── Virtual methods ───────────────────────────────────────────────────────────

func _on_location_ready() -> void:
	pass

func _on_location_process(_delta: float) -> void:
	pass

func _on_cat_entered(_cat: Node3D) -> void:
	pass

func _on_cat_exited(_cat: Node3D) -> void:
	pass

func _on_interaction_triggered(_cat_a: Node3D, _cat_b: Node3D, _zone: Area3D) -> void:
	pass

func _maybe_trigger_special(_cat: Node3D) -> void:
	pass


# ══ TEST MODE ═════════════════════════════════════════════════════════════════
# Everything below only runs when test_mode = true in the Inspector.

func _test_setup() -> void:
	cat_entered.connect(_test_on_cat_entered)
	cat_exited.connect(_test_on_cat_exited)
	interaction_started.connect(_test_on_interaction_started)
	location_event_fired.connect(_test_on_event_fired)

	# Register every cat that is a direct child of this node.
	for child in get_children():
		if child.is_in_group("cat"):
			register_cat(child)

	# Also catch cats nested anywhere deeper in the tree.
	for cat in get_tree().get_nodes_in_group("cat"):
		if not cat.cat_name in cats_present:
			register_cat(cat)

	_test_build_overlay()

	print("[TestMode] '%s' ready — %d cat(s) registered." % [
		location_display_name, cats_present.size()
	])

	if cats_present.is_empty():
		push_warning("[TestMode] No cats found. Make sure each CharacterBody3D " +
			"has test_cat.gd attached, cat_name set in the Inspector, " +
			"and is added to the 'cat' group (Node tab → Groups → 'cat').")


var _proximity_timer: float = 0.0
const PROXIMITY_CHECK_INTERVAL: float = 2.0
const PROXIMITY_TRIGGER_DISTANCE: float = 3.0

func _test_process(delta: float) -> void:
	_test_tick_timer  += delta
	_proximity_timer  += delta

	if _test_tick_timer >= test_day_tick_interval:
		_test_tick_timer = 0.0
		_test_fire_day_tick()

	# Proximity check — fire interactions when two cats are close enough.
	# This bypasses Area3D signal issues during testing.
	if _proximity_timer >= PROXIMITY_CHECK_INTERVAL:
		_proximity_timer = 0.0
		_test_check_proximity()

	_test_update_overlay()


func _test_check_proximity() -> void:
	var cat_list: Array = get_cats()
	for i in range(cat_list.size()):
		for j in range(i + 1, cat_list.size()):
			var cat_a: Node3D = cat_list[i]
			var cat_b: Node3D = cat_list[j]
			var dist: float   = cat_a.global_position.distance_to(cat_b.global_position)
			if dist <= PROXIMITY_TRIGGER_DISTANCE:
				var zone: Area3D = _interaction_zones.get_node_or_null("ZoneCentre")
				_try_trigger_interaction(cat_a, cat_b, zone)


func _test_fire_day_tick() -> void:
	var rm: Node = get_node_or_null("/root/RumorManager")
	if rm == null:
		print("[TestMode] ⚠ RumorManager not found. " +
			"Add rumor_manager.gd in Project → Project Settings → Autoload.")
		return

	# Decay needs and update mood on every cat before the rumor tick.
	for cat in get_cats():
		if cat.has_method("daily_tick"):
			cat.daily_tick()

	rm.daily_tick(get_cats(), get_location_map_slice())

	print("[TestMode] 🕐 Day tick — active rumors: %d" % rm.active_rumors.size())
	for r in rm.active_rumors:
		print("   [%s] heat:%.2f  known_by:%d  crystallized:%s — %s" % [
			r.type, r.heat, r.known_by.size(), str(r.crystallized), r.content
		])


func _test_build_overlay() -> void:
	# Outer panel anchored to left side, fixed height.
	var panel := PanelContainer.new()
	panel.name           = "DebugPanel"
	panel.anchor_left    = 0.0
	panel.anchor_top     = 0.0
	panel.anchor_right   = 0.0
	panel.anchor_bottom  = 0.0
	panel.offset_left    = 8.0
	panel.offset_top     = 8.0
	panel.offset_right   = 280.0
	panel.offset_bottom  = 500.0
	_ui_layer.add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.name                              = "Scroll"
	scroll.custom_minimum_size               = Vector2(260.0, 480.0)
	scroll.horizontal_scroll_mode           = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	_debug_label              = RichTextLabel.new()
	_debug_label.name         = "DebugOverlay"
	_debug_label.bbcode_enabled = true
	_debug_label.fit_content  = true
	_debug_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_debug_label.custom_minimum_size = Vector2(240.0, 0.0)
	scroll.add_child(_debug_label)


func _test_update_overlay() -> void:
	if _debug_label == null:
		return

	var lines: PackedStringArray = PackedStringArray()
	lines.append("[b][color=#40c8c8]── cats ──[/color][/b]")

	for cname in cats_present:
		var cat: Node3D      = cats_present[cname]
		var mood_val: float  = cat.get("mood") if cat.get("mood") != null else 0.0
		var mood_str: String = cat.call("mood_label") if cat.has_method("mood_label") else "?"
		var rep: float       = cat.get("reputation") if cat.get("reputation") != null else 0.0

		# Header line.
		lines.append("  [b]%s[/b]  %s  rep:%.0f" % [
			cname, _test_mood_colored(mood_val, mood_str), rep
		])

		# Needs — read from cat.data if it's a CatBase, fall back gracefully.
		var cat_data = cat.get("data") if "data" in cat else null
		if cat_data != null and "needs" in cat_data:
			var needs: Dictionary = cat_data.needs
			for need in ["hunger", "sleep", "social", "fun", "expression", "belonging", "hygiene", "aspiration"]:
				var val: float  = needs.get(need, 1.0)
				var bar: String = _need_bar(val)
				var color: String = "lime" if val > 0.5 else ("orange" if val > 0.25 else "tomato")
				lines.append("    [color=#888]%s[/color] [color=%s]%s[/color] %.0f%%" % [
					need.left(6).rpad(6), color, bar, val * 100.0
				])

			# Aspiration progress.
			var asp_type: String     = cat_data.get("aspiration_type") if "aspiration_type" in cat_data else "?"
			var asp_prog: float      = cat_data.get("aspiration_progress") if "aspiration_progress" in cat_data else 0.0
			var zodiac: String       = cat_data.get("zodiac_sign") if "zodiac_sign" in cat_data else "?"
			lines.append("    [color=#888]aspire[/color] [color=#c8a0ff]%s[/color] %.0f%%" % [asp_type, asp_prog * 100.0])
			lines.append("    [color=#888]sign  [/color] [color=#a0c8ff]%s[/color]" % zodiac)

		# Relationships.
		for other in cats_present:
			if other == cname:
				continue
			var score: float = cat.get_relationship_score(other) \
				if cat.has_method("get_relationship_score") else 0.0
			var rel_color: String = "lime" if score > 60 else ("orange" if score > 40 else "tomato")
			lines.append("    [color=#888]↔[/color] %s [color=%s]%.0f[/color]" % [other, rel_color, score])

		lines.append("")	# spacer between cats

	# Rumors.
	var rm: Node = get_node_or_null("/root/RumorManager")
	if rm != null:
		lines.append("[b][color=#40c8c8]── rumors ──[/color][/b]")
		if rm.active_rumors.is_empty():
			lines.append("  [color=#888](none yet)[/color]")
		for r in rm.active_rumors.slice(0, 5):
			var star: String = " [color=gold]★[/color]" if r.crystallized else ""
			lines.append("  [%s] heat:%.2f  known:%d%s" % [
				r.type, r.heat, r.known_by.size(), star
			])

	lines.append("[color=#555]tick in %.1fs[/color]" % (test_day_tick_interval - _test_tick_timer))
	_debug_label.text = "\n".join(lines)


func _need_bar(val: float) -> String:
	var filled: int = int(round(val * 8.0))
	return "█".repeat(filled) + "░".repeat(8 - filled)


func _test_mood_colored(val: float, label: String) -> String:
	var color: String = "white"
	if val >= 0.6:    color = "lime"
	elif val >= 0.2:  color = "yellow"
	elif val >= -0.2: color = "white"
	elif val >= -0.6: color = "orange"
	else:             color = "tomato"
	return "[color=%s]%s[/color]" % [color, label]


func _test_on_cat_entered(cat: Node3D) -> void:
	print("[TestMode] ▶ entered  '%s'" % cat.cat_name)

func _test_on_cat_exited(cat: Node3D) -> void:
	print("[TestMode] ◀ exited   '%s'" % cat.cat_name)

func _test_on_interaction_started(cat_a: Node3D, cat_b: Node3D, zone: Area3D) -> void:
	print("[TestMode] ⚡ interaction  '%s' + '%s'  zone:'%s'" % [
		cat_a.cat_name, cat_b.cat_name, zone.name
	])

func _test_on_event_fired(event: Dictionary) -> void:
	print("[TestMode] 📢 event  subject:'%s'  type:'%s'" % [
		event.get("subject", "?"), event.get("type", "?")
	])
