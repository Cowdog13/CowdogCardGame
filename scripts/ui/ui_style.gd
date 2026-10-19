class_name UiStyle
extends RefCounted
## Shared look: the Gluten font, element colour palettes, panel styles and the global theme.

const FONT_PATH := "res://assets/fonts/Gluten.ttf"
const CREAM := Color(0.99, 0.96, 0.88)
const FONT_WEIGHT := 650
const INK := Color(0.22, 0.15, 0.10)
const INK_SOFT := Color(0.42, 0.33, 0.26)

static var _font: Font = null


static func font() -> Font:
	if _font == null:
		if ResourceLoader.exists(FONT_PATH):
			# Gluten is a variable font; a heavier weight reads better at small card sizes.
			var fv := FontVariation.new()
			fv.base_font = load(FONT_PATH)
			fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): FONT_WEIGHT}
			_font = fv
		else:
			_font = ThemeDB.fallback_font
	return _font


## Colours for card frames. frame = border, dark = text/accents on cream, light = art window tint.
static func palette(element: String) -> Dictionary:
	match element:
		"fire": return {"frame": Color(0.84, 0.31, 0.14), "dark": Color(0.55, 0.16, 0.06), "light": Color(1.0, 0.86, 0.66)}
		"water": return {"frame": Color(0.17, 0.46, 0.80), "dark": Color(0.08, 0.27, 0.52), "light": Color(0.76, 0.91, 1.0)}
		"nature": return {"frame": Color(0.30, 0.62, 0.28), "dark": Color(0.14, 0.38, 0.14), "light": Color(0.80, 0.94, 0.72)}
		"light": return {"frame": Color(0.90, 0.74, 0.20), "dark": Color(0.55, 0.40, 0.04), "light": Color(1.0, 0.95, 0.70)}
		"shadow": return {"frame": Color(0.44, 0.30, 0.60), "dark": Color(0.25, 0.14, 0.38), "light": Color(0.84, 0.76, 0.94)}
		"void": return {"frame": Color(0.22, 0.20, 0.30), "dark": Color(0.10, 0.09, 0.16), "light": Color(0.74, 0.72, 0.84)}
		"metal": return {"frame": Color(0.56, 0.60, 0.65), "dark": Color(0.28, 0.31, 0.35), "light": Color(0.88, 0.90, 0.93)}
		"air": return {"frame": Color(0.42, 0.78, 0.82), "dark": Color(0.17, 0.46, 0.50), "light": Color(0.85, 0.97, 0.98)}
		"electric": return {"frame": Color(0.93, 0.68, 0.10), "dark": Color(0.52, 0.36, 0.02), "light": Color(1.0, 0.94, 0.62)}
		"super": return {"frame": Color(0.76, 0.27, 0.62), "dark": Color(0.46, 0.10, 0.36), "light": Color(0.96, 0.80, 0.92)}
		"spell": return {"frame": Color(0.40, 0.33, 0.62), "dark": Color(0.22, 0.17, 0.42), "light": Color(0.86, 0.82, 0.96)}
	return {"frame": Color(0.60, 0.56, 0.50), "dark": Color(0.30, 0.27, 0.23), "light": Color(0.92, 0.90, 0.85)}


static func box(bg: Color, radius := 8, border := Color(0, 0, 0, 0), border_w := 0, margin := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_content_margin_all(margin)
	return sb


static func build_theme() -> Theme:
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 16
	var teal := Color(0.14, 0.31, 0.38)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var bg := teal
		var border := Color(0.85, 0.72, 0.38)
		match state:
			"hover": bg = teal.lightened(0.18)
			"pressed": bg = teal.darkened(0.25)
			"disabled":
				bg = Color(0.2, 0.22, 0.24, 0.8)
				border = Color(0.4, 0.4, 0.4)
			"focus":
				bg = Color(0, 0, 0, 0)
		var sb := box(bg, 10, border, 2, 8)
		sb.content_margin_left = 14
		sb.content_margin_right = 14
		t.set_stylebox(state, "Button", sb)
	t.set_color("font_color", "Button", CREAM)
	t.set_color("font_hover_color", "Button", Color(1, 1, 1))
	t.set_color("font_disabled_color", "Button", Color(0.6, 0.6, 0.6))
	return t
