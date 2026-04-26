# zodiac_system.gd
# Autoload singleton — add as "ZodiacSystem" in Project Settings → Autoload.
# Handles sign-based stat caps, compatibility modifiers, and trait flavour.
#
# Cats believe in astrology and act on it. This system gives that belief
# real mechanical weight — not just flavour text.
extends Node

# ── Sign definitions ──────────────────────────────────────────────────────────
## Each sign defines:
##   trait_caps    – maximum value each trait can reach for this sign
##   trait_boosts  – small additive bonus applied on top of base trait values
##   need_mod      – which need decays faster or slower (key = need, val = multiplier)
##   description   – shown in the Observatory UI

const SIGNS: Dictionary = {
	"aries": {
		"trait_caps":   { "sociability": 0.9, "stubbornness": 0.8, "mischief": 0.85 },
		"trait_boosts": { "sociability": 0.1, "mischief": 0.1 },
		"need_mod":     { "fun": 1.3, "sleep": 0.8 },	# needs fun faster, sleeps less
		"description":  "Bold and impulsive. Quick to act, quick to forget.",
	},
	"taurus": {
		"trait_caps":   { "stubbornness": 0.95, "empathy": 0.8, "hygiene": 0.9 },
		"trait_boosts": { "stubbornness": 0.15 },
		"need_mod":     { "hygiene": 1.2, "belonging": 1.1 },
		"description":  "Stubborn but loyal. Values comfort above all.",
	},
	"gemini": {
		"trait_caps":   { "sociability": 0.95, "gossip": 0.9, "stubbornness": 0.6 },
		"trait_boosts": { "gossip": 0.15, "creativity": 0.1 },
		"need_mod":     { "social": 1.3, "sleep": 1.2 },
		"description":  "Endlessly curious. Talks to everyone, remembers nothing.",
	},
	"cancer": {
		"trait_caps":   { "empathy": 0.95, "credulity": 0.85, "belonging": 0.9 },
		"trait_boosts": { "empathy": 0.15 },
		"need_mod":     { "belonging": 1.4, "social": 0.9 },
		"description":  "Deeply feeling. Needs closeness, bruises easily.",
	},
	"leo": {
		"trait_caps":   { "sociability": 0.9, "creativity": 0.9, "gossip": 0.8 },
		"trait_boosts": { "sociability": 0.1, "creativity": 0.1 },
		"need_mod":     { "expression": 1.4, "fun": 1.2 },
		"description":  "Dramatic and magnetic. Must be seen.",
	},
	"virgo": {
		"trait_caps":   { "memory": 0.95, "credulity": 0.4, "hygiene": 0.9 },
		"trait_boosts": { "memory": 0.15 },
		"need_mod":     { "hygiene": 1.3, "aspiration": 1.1 },
		"description":  "Precise and skeptical. Hard to fool, hard to satisfy.",
	},
	"libra": {
		"trait_caps":   { "sociability": 0.85, "empathy": 0.85, "stubbornness": 0.5 },
		"trait_boosts": { "empathy": 0.1, "sociability": 0.05 },
		"need_mod":     { "social": 1.1, "belonging": 1.1 },
		"description":  "Harmony-seeking. Dislikes conflict, loves company.",
	},
	"scorpio": {
		"trait_caps":   { "stubbornness": 0.95, "memory": 0.9, "mischief": 0.8 },
		"trait_boosts": { "stubbornness": 0.1, "memory": 0.1 },
		"need_mod":     { "belonging": 0.8, "aspiration": 1.2 },
		"description":  "Intense and private. Remembers everything, forgives rarely.",
	},
	"sagittarius": {
		"trait_caps":   { "sociability": 0.8, "mischief": 0.75, "credulity": 0.7 },
		"trait_boosts": { "mischief": 0.1 },
		"need_mod":     { "fun": 1.4, "hygiene": 0.8 },
		"description":  "Free-spirited and restless. Always looking for the next thing.",
	},
	"capricorn": {
		"trait_caps":   { "stubbornness": 0.8, "memory": 0.85, "gossip": 0.5 },
		"trait_boosts": { "memory": 0.05 },
		"need_mod":     { "aspiration": 1.4, "fun": 0.8 },
		"description":  "Quietly ambitious. Driven, reserved, patient.",
	},
	"aquarius": {
		"trait_caps":   { "creativity": 0.95, "sociability": 0.7, "credulity": 0.5 },
		"trait_boosts": { "creativity": 0.15 },
		"need_mod":     { "expression": 1.3, "belonging": 0.8 },
		"description":  "Eccentric and independent. Marches to their own beat.",
	},
	"pisces": {
		"trait_caps":   { "credulity": 0.95, "empathy": 0.9, "memory": 0.6 },
		"trait_boosts": { "credulity": 0.15, "empathy": 0.1 },
		"need_mod":     { "sleep": 0.8, "aspiration": 1.2 },
		"description":  "Dreamy and open. Believes everything, forgets half.",
	},
}

# ── Compatibility table ───────────────────────────────────────────────────────
## Modifier applied to relationship GROWTH RATE between two signs.
## +0.3 = natural affinity (grows faster), -0.3 = friction (grows slower).
## Stored as "sign_a:sign_b" with sign_a alphabetically first.
const COMPATIBILITY: Dictionary = {
	"aries:leo":          0.25,
	"aries:sagittarius":  0.20,
	"aries:cancer":      -0.20,
	"aries:capricorn":   -0.25,
	"taurus:virgo":       0.25,
	"taurus:capricorn":   0.20,
	"taurus:leo":        -0.15,
	"taurus:aquarius":   -0.30,
	"gemini:libra":       0.25,
	"gemini:aquarius":    0.20,
	"gemini:virgo":      -0.20,
	"gemini:pisces":     -0.15,
	"cancer:pisces":      0.30,
	"cancer:scorpio":     0.20,
	"cancer:aries":      -0.20,
	"cancer:capricorn":  -0.15,
	"leo:sagittarius":    0.25,
	"leo:aries":          0.25,
	"leo:scorpio":       -0.20,
	"leo:taurus":        -0.15,
	"virgo:capricorn":    0.25,
	"virgo:taurus":       0.25,
	"virgo:sagittarius": -0.25,
	"virgo:pisces":      -0.20,
	"libra:aquarius":     0.25,
	"libra:gemini":       0.25,
	"libra:cancer":      -0.15,
	"libra:capricorn":   -0.20,
	"scorpio:pisces":     0.30,
	"scorpio:cancer":     0.20,
	"scorpio:leo":       -0.20,
	"scorpio:aquarius":  -0.25,
	"sagittarius:aries":  0.20,
	"sagittarius:leo":    0.25,
	"sagittarius:virgo": -0.25,
	"sagittarius:pisces":-0.15,
	"capricorn:taurus":   0.20,
	"capricorn:virgo":    0.25,
	"capricorn:aries":   -0.25,
	"capricorn:libra":   -0.20,
	"aquarius:gemini":    0.20,
	"aquarius:libra":     0.25,
	"aquarius:taurus":   -0.30,
	"aquarius:scorpio":  -0.25,
	"pisces:cancer":      0.30,
	"pisces:scorpio":     0.30,
	"pisces:gemini":     -0.15,
	"pisces:virgo":      -0.20,
}

# ── Public API ────────────────────────────────────────────────────────────────

## Apply zodiac trait caps and boosts to a CatData resource.
## Call once when a cat is first created or loaded.
func apply_caps(data: CatData) -> void:
	# Strip any accidental whitespace from the Inspector field.
	data.zodiac_sign = data.zodiac_sign.strip_edges()
	var zodiac_sign: String = data.zodiac_sign

	if not SIGNS.has(zodiac_sign):
		push_warning("[ZodiacSystem] Unknown sign '%s' on cat '%s'. Valid signs: %s" % [
			zodiac_sign, data.cat_name, ", ".join(SIGNS.keys())
		])
		return

	var sign_data: Dictionary = SIGNS[zodiac_sign]

	# Apply caps.
	var caps: Dictionary = sign_data.get("trait_caps", {})
	for trait_name in caps:
		if data.traits.has(trait_name):
			data.traits[trait_name] = minf(data.traits[trait_name], caps[trait_name])

	# Apply boosts (additive, then re-clamp to cap).
	var boosts: Dictionary = sign_data.get("trait_boosts", {})
	for trait_name in boosts:
		if data.traits.has(trait_name):
			var cap: float = caps.get(trait_name, 1.0)
			data.traits[trait_name] = minf(
				data.traits[trait_name] + boosts[trait_name],
				cap
			)


## Returns the need decay multiplier for a given need on a given sign.
## 1.0 = normal rate. >1.0 = decays faster (needs it more). <1.0 = decays slower.
func need_decay_mod(zodiac_sign: String, need: String) -> float:
	if not SIGNS.has(zodiac_sign):
		return 1.0
	return SIGNS[zodiac_sign].get("need_mod", {}).get(need, 1.0)


## Returns the compatibility modifier between two signs (-0.3 to +0.3).
## Used by CatBase when adjusting relationship growth speed.
func compatibility(sign_a: String, sign_b: String) -> float:
	var key: String = _compat_key(sign_a, sign_b)
	return COMPATIBILITY.get(key, 0.0)


## Returns whether two cats are "compatible" by sign (positive modifier).
func are_compatible(sign_a: String, sign_b: String) -> bool:
	return compatibility(sign_a, sign_b) > 0.0


## Returns the display description for a sign.
func sign_description(zodiac_sign: String) -> String:
	return SIGNS.get(zodiac_sign, {}).get("description", "")


## Returns a random sign key.
func random_sign() -> String:
	return SIGNS.keys().pick_random()


# ── Internal ──────────────────────────────────────────────────────────────────

func _compat_key(sign_a: String, sign_b: String) -> String:
	var signs: Array = [sign_a, sign_b]
	signs.sort()
	return "%s:%s" % [signs[0], signs[1]]
