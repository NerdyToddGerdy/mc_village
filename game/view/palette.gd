class_name Palette
extends RefCounted
## "Carpenter's chalk" tokens (slice-1-spec.md §12) plus the world's block colours.

# HUD
static var SLATE := Color("#2F3B37", 0.93)
static var SLATE_DEEP := Color("#232C29")
static var CHALK := Color("#ECEAE2")
static var CHALK_DIM := Color("#B3B8AF")
static var RED := Color("#F25C54")
static var BLUE := Color("#6FA8DC")
static var GREEN := Color("#8CC084")
static var YELLOW := Color("#E8C547")
static var WHEAT := Color("#D8B65A")   ## Farm plots and the Farm order (issue #74); yellow stays for stuck.
static var SKY := Color("#A9B8B0")

# Type scale (issue #80): every HUD text size is one of these, and nothing is smaller than CAPTION.
# Bricolage Grotesque's condensed shapes get hard to read below 13 px at 1280×720.
const CAPTION := 13   ## Notes, hints, counts, keycaps
const BODY := 15      ## Panel text, rows and buttons
const HEADING := 18   ## Panel and section titles
const TITLE := 24     ## The selected thing's name

# World
static var GRASS := Color("#6F8F4E")
static var DIRT := Color("#7B5E42")
static var STONE := Color("#8A8D86")
static var COBBLE := Color("#7F827C")
static var LOG := Color("#7A5634")
static var LEAVES := Color("#4E7A3A")
static var PLANK := Color("#C49A62")
static var ROOF := Color("#8E5E3C")
static var LEGS := Color("#3A3B45")
static var SKIN := Color("#D9A77C")
static var STICK := Color("#9C7A4E")

## The mine levels' cold look (issue #206): blocks are multiplied by the grade, and their textures
## are this much stronger (1 is the village's).
static var MINE_GRADE := Color("#E0EAFF")
const MINE_CONTRAST := 1.35
## The Nether's warm, dark red look (issues #148, #206): a grade like the mine's, but red.
static var NETHER_GRADE := Color("#E8A590")

## An item's colour; an enchanted one is its base item's.
static func item_color(type: String) -> Color:
	return ITEM_COLORS.get(type.get_slice("+", 0), CHALK)


static var ITEM_COLORS := {
	"wool": Color("#ECEAE2"), "mutton": Color("#C2645A"), "berries": Color("#B23A5A"), "wheat": Color("#D8B65A"),
	"bread": Color("#D9A35A"), "cooked_mutton": Color("#8C4A32"),
	"leather": Color("#9A5B33"), "beef": Color("#B5473F"), "cooked_beef": Color("#6E3A26"),
	"porkchop": Color("#E39A8E"), "cooked_porkchop": Color("#A8643F"),
	"leather_cap": Color("#9A5B33"), "leather_tunic": Color("#9A5B33"), "leather_trousers": Color("#9A5B33"), "leather_boots": Color("#9A5B33"),
	"log": Color("#7A5634"), "plank": Color("#C49A62"), "stick": Color("#9C7A4E"), "cobble": Color("#7F827C"), "stone_brick": Color("#9A9C94"), "chest": Color("#8E6A3E"), "sapling": Color("#5E9A3C"),
	"coal": Color("#34312F"), "iron_ore": Color("#C08A68"), "iron_ingot": Color("#C9D0D6"), "diamond": Color("#7FD8E0"),
	"book_efficiency": Color("#7A4FB5"), "book_unbreaking": Color("#7A4FB5"), "book_protection": Color("#7A4FB5"), "book_fire_protection": Color("#7A4FB5"), "lapis": Color("#3E5FC8"), "redstone": Color("#D6382E"), "string": Color("#E8E2D0"), "fire_resistance": Color("#E27B2C"), "quartz": Color("#ECE6DA"), "glowstone": Color("#F5D470"), "magma_cream": Color("#E8742A"), "bone": Color("#E6E0CC"), "blaze_rod": Color("#F2B531"), "gold_ore": Color("#E8C547"), "gold_ingot": Color("#F0CE55"), "obsidian": Color("#2B2038"), "flint": Color("#4A4A4E"), "flint_and_steel": Color("#8A8D93"),
	"rail": Color("#A7AFB5"), "minecart": Color("#6E777E"),
	"wood_axe": Color("#C49A62"), "wood_pick": Color("#C49A62"), "stone_axe": Color("#8A8D86"), "stone_pick": Color("#8A8D86"),
	"iron_axe": Color("#C9D0D6"), "iron_pick": Color("#C9D0D6"), "diamond_axe": Color("#7FD8E0"), "diamond_pick": Color("#7FD8E0"),
}
