class_name Job
extends RefCounted
## One unit of work a resident has claimed: a list of steps plus the reservations ("holds") it keeps.
##
## Steps are plain Dictionaries with an "op" (goto, pickup, pickup_tool, deposit, work, haul_drop,
## move_in) that Sim interprets each tick. Holds are reservations such as a claimed tree or items
## promised to a site. A step that uses up a hold removes it; whatever is left is undone when the
## job ends, finished or not. Jobs are never saved: on load, residents simply claim work again.

var kind: String          ## gather, deliver, build, craft, haul, move, arrive
var label: String         ## Shown as the resident's status.
var what: String          ## Used in "Can't reach <what>".
var target = null         ## The entity Dictionary this job is about, if any.
var work := ""            ## The resident job it counts as (mine, haul, farm...), for skills; "" for walking and eating.
var ordered := false      ## A direct or queued order: switching its job off doesn't stop it.
var steps: Array = []
var i := 0
var holds: Array = []


func _init(p_kind: String, p_label: String, p_what: String) -> void:
	kind = p_kind
	label = p_label
	what = p_what


func hold(h: Dictionary) -> Dictionary:
	holds.append(h)
	return h


func step(s: Dictionary) -> Job:
	steps.append(s)
	return self
