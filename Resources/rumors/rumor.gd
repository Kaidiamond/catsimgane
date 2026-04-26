# rumor.gd
# Attach as a Resource — one instance per active rumor in the game.
class_name Rumor
extends Resource

# ── Identity ─────────────────────────────────────────────────────────────────
var id: String                  # unique, e.g. "rumor_042"
var subject: String             # cat_name of the cat being talked about
var type: String                # "action" | "trait" | "relationship" | "secret"
var content: String             # human-readable display string
var is_true: bool               # false = fabricated or mutated

# ── Origin ────────────────────────────────────────────────────────────────────
var origin: String              # cat_name who first spoke it
var origin_location: String     # location where it was born

# ── Spread state ──────────────────────────────────────────────────────────────
## known_by maps cat_name → belief (0.0–1.0).
## 0.0 = heard it but disbelieves entirely
## 1.0 = completely convinced
var known_by: Dictionary = {}

# ── Heat ──────────────────────────────────────────────────────────────────────
## heat drives how actively this rumor circulates.
## decays each day; reaches 0 and the rumor is forgotten (unless crystallized).
var heat: float = 1.0
var decay_rate: float = 0.08

# ── Mutation trail ────────────────────────────────────────────────────────────
## Each entry: { "mutated_id": String, "mutator": String, "day": int }
var mutations: Array = []

# ── Lifecycle ─────────────────────────────────────────────────────────────────
var age_days: int = 0
var crystallized: bool = false  # true = permanent reputation effect locked in
