# test_location_setup.gd
# Attach this script to the ROOT NODE of whichever location scene you're
# testing (e.g. the Node3D root of location_base.tscn or fog_pier.tscn).
# It will:
#   - Find every test cat in the scene and register them with the location
#   - Print every signal the location fires so you can verify the system works
#   - Show a live debug overlay (cat names, moods, relationship scores)
#   - Simulate a day tick every N seconds so you can watch rumors spread
#
# Remove this script (or just don't attach it) in production.
extends Node

# How often (seconds) to fire a simulated daily_tick on RumorManager.
@export var day_tick_interval: float = 10.0

var _location: Node3D = null
var _tick_timer: float = 0.0
var _debug_label: RichTextLabel = null

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	# The script must be on the location root itself, or a direct child.
	_location = _find_location()
	if _location == null:
		push_error("[TestSetup] Could not find a location node with register_cat(). " +
			"Attach this script to the location's root node.")
		return

	_build_debug_overlay()
	_register_all_test_cats()
	_connect_location_signals()

	print("[TestSetup] Location '%s' ready. %d cat(s) registered." % [
		_location.location_display_name,
		_location.cats_present.size()
	])


func _process(delta: float) -> void:
	_tick_timer += delta
	if _tick_timer >= day_tick_interval:
		_tick_timer = 0.0
		_fire_day_tick()
	_update_debug_overlay()


# ── Location discovery ────────────────────────────────────────────────────────

func _find_location() -> Node3D:
	# Identify a CatLocation by a method only it has.
	# (class_name removed to avoid Godot global registry collision.)
	if get_parent().has_method("register_cat"):
		return get_parent()
	for sibling in get_parent().get_children():
		if sibling.has_method("register_cat"):
			return sibling
	return null


# ── Cat registration ──────────────────────────────────────────────────────────

func _register_all_test_cats() -> void:
	# Walk the entire scene tree looking for nodes in the "cat" group.
	var cats: Array = get_tree().get_nodes_in_group("cat")
	if cats.is_empty():
		push_warning("[TestSetup] No nodes found in group 'cat'. " +
			"Select a CharacterBody3D → Node tab → Groups → add 'cat'.")
		return

	for cat in cats:
		_location.register_cat(cat)
		print("[TestSetup] Registered cat: '%s' (mood: %s)" % [
			cat.cat_name, cat.mood_label()
		])


# ── Signal connections ────────────────────────────────────────────────────────

func _connect_location_signals() -> void:
	_location.cat_entered.connect(_on_cat_entered)
	_location.cat_exited.connect(_on_cat_exited)
	_location.interaction_started.connect(_on_interaction_started)
	_location.location_event_fired.connect(_on_location_event_fired)


func _on_cat_entered(cat: Node) -> void:
	print("[TestSetup] ▶ cat_entered  → '%s'" % cat.cat_name)


func _on_cat_exited(cat: Node) -> void:
	print("[TestSetup] ◀ cat_exited   → '%s'" % cat.cat_name)


func _on_interaction_started(cat_a: Node, cat_b: Node, zone: Area3D) -> void:
	print("[TestSetup] ⚡ interaction  → '%s' + '%s' in zone '%s'" % [
		cat_a.cat_name, cat_b.cat_name, zone.name
	])


func _on_location_event_fired(event: Dictionary) -> void:
	print("[TestSetup] 📢 event fired  → subject:'%s'  type:'%s'" % [
		event.get("subject", "?"), event.get("type", "?")
	])
	print("             description: %s" % event.get("description", ""))


# ── Day tick simulation ───────────────────────────────────────────────────────

func _fire_day_tick() -> void:
	var rumor_manager: Node = get_node_or_null("/root/RumorManager")
	if rumor_manager == null:
		print("[TestSetup] ⚠ RumorManager autoload not found — skipping day tick.")
		return

	# Build location_map from the current location only.
	var location_map: Dictionary = _location.get_location_map_slice()
	var cats: Array = _location.get_cats()

	rumor_manager.daily_tick(cats, location_map)

	var rumor_count: int = rumor_manager.active_rumors.size()
	print("[TestSetup] 🕐 Day tick fired. Active rumors: %d" % rumor_count)
	for rumor in rumor_manager.active_rumors:
		print("   • [%s] '%s' — heat:%.2f  known_by:%d cats  crystallized:%s" % [
			rumor.type,
			rumor.content,
			rumor.heat,
			rumor.known_by.size(),
			str(rumor.crystallized)
		])


# ── Debug overlay ─────────────────────────────────────────────────────────────

func _build_debug_overlay() -> void:
	# Find the UILayer CanvasLayer on the location, add a RichTextLabel to it.
	var ui_layer: CanvasLayer = _location.get_node_or_null("UILayer")
	if ui_layer == null:
		return

	_debug_label = RichTextLabel.new()
	_debug_label.name = "DebugOverlay"
	_debug_label.bbcode_enabled = true
	_debug_label.fit_content = true
	_debug_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Anchor to bottom-left.
	_debug_label.anchor_left   = 0.0
	_debug_label.anchor_top    = 1.0
	_debug_label.anchor_right  = 0.0
	_debug_label.anchor_bottom = 1.0
	_debug_label.offset_left   = 12.0
	_debug_label.offset_top    = -200.0
	_debug_label.offset_right  = 360.0
	_debug_label.offset_bottom = -12.0

	ui_layer.add_child(_debug_label)


func _update_debug_overlay() -> void:
	if _debug_label == null or _location == null:
		return

	var lines: PackedStringArray = PackedStringArray()
	lines.append("[b][color=aqua]── cats present ──[/color][/b]")

	for cat_name in _location.cats_present:
		var cat: Node = _location.cats_present[cat_name]
		var mood_str: String = cat.mood_label() if cat.has_method("mood_label") else "?"
		var mood_val: float  = cat.mood if "mood" in cat else 0.0
		var mood_color: String = _mood_color(mood_val)

		lines.append("  [b]%s[/b]  mood:[color=%s]%s[/color]  rep:%.0f" % [
			cat_name,
			mood_color,
			mood_str,
			cat.reputation if "reputation" in cat else 0.0
		])

		# Show up to 3 relationship scores.
		if cat.has_method("get_relationship_score"):
			var shown: int = 0
			for other_name in _location.cats_present:
				if other_name == cat_name:
					continue
				if shown >= 3:
					break
				var score: float = cat.get_relationship_score(other_name)
				lines.append("    → %s : %.0f" % [other_name, score])
				shown += 1

	# Rumor summary.
	var rm: Node = get_node_or_null("/root/RumorManager")
	if rm != null:
		lines.append("[b][color=aqua]── rumors ──[/color][/b]")
		var rumors: Array = rm.active_rumors
		if rumors.is_empty():
			lines.append("  [color=gray](none)[/color]")
		else:
			for rumor in rumors.slice(0, 5):		# show at most 5
				var crystal: String = " [color=gold]★[/color]" if rumor.crystallized else ""
				lines.append("  [%s] heat:%.2f  known:%d%s" % [
					rumor.type, rumor.heat, rumor.known_by.size(), crystal
				])

	# Next tick countdown.
	var remaining: float = day_tick_interval - _tick_timer
	lines.append("[color=gray]next tick in %.1fs[/color]" % remaining)

	_debug_label.text = "\n".join(lines)


func _mood_color(mood: float) -> String:
	if mood >= 0.6:  return "lime"
	if mood >= 0.2:  return "yellow"
	if mood >= -0.2: return "white"
	if mood >= -0.6: return "orange"
	return "tomato"
