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
static var SKY := Color("#A9B8B0")

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

static var ITEM_COLORS := {
	"wool": Color("#ECEAE2"), "mutton": Color("#C2645A"), "berries": Color("#B23A5A"),
	"bread": Color("#D9A35A"), "cooked_mutton": Color("#8C4A32"),
	"log": Color("#7A5634"), "plank": Color("#C49A62"), "stick": Color("#9C7A4E"), "cobble": Color("#7F827C"),
	"wood_axe": Color("#C49A62"), "wood_pick": Color("#C49A62"), "stone_axe": Color("#8A8D86"), "stone_pick": Color("#8A8D86"),
}
