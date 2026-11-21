class_name PixelAttackBudget
extends Node
## Shared "attack slots" (a.k.a. attack tokens) for all enemies in an encounter.
## An enemy must acquire slots BEFORE it starts a telegraph, and release them
## when the attack (incl. recovery, or projectile lifetime) ends.
## Add as an autoload (e.g. name it "AttackBudget") or as a child of the arena.

signal slots_changed(used: int, capacity: int)

## Max total cost of attacks active at the same time.
@export var capacity: int = 3
## Safety net: tickets older than this (seconds) are reclaimed automatically.
@export var default_timeout: float = 8.0

var _next_id := 1
var _tickets := {}   # id -> {cost, owner_ref, age, timeout}


func used() -> int:
	var n := 0
	for id in _tickets:
		n += _tickets[id].cost
	return n


func available() -> int:
	return capacity - used()


## Returns a ticket id (> 0) on success, or 0 if there is not enough room.
## Never start a warning and cancel it later: ask first, then telegraph.
func try_acquire(owner: Object, cost: int = 1, timeout: float = -1.0) -> int:
	if cost > available():
		return 0
	var id := _next_id
	_next_id += 1
	_tickets[id] = {"cost": cost, "owner_ref": weakref(owner) if owner else null,
		"age": 0.0, "timeout": default_timeout if timeout <= 0.0 else timeout}
	slots_changed.emit(used(), capacity)
	return id


func release(ticket: int) -> void:
	if _tickets.erase(ticket):
		slots_changed.emit(used(), capacity)


## Call when an enemy dies / is removed / its phase resets.
func release_all_for(owner: Object) -> void:
	var gone := []
	for id in _tickets:
		var ref: WeakRef = _tickets[id].owner_ref
		if ref != null and ref.get_ref() == owner:
			gone.append(id)
	for id in gone:
		_tickets.erase(id)
	if not gone.is_empty():
		slots_changed.emit(used(), capacity)


func clear() -> void:
	_tickets.clear()
	slots_changed.emit(0, capacity)


func _process(delta: float) -> void:
	tick(delta)


## Ages tickets; frees timed-out ones and ones whose owner was freed.
func tick(delta: float) -> void:
	var gone := []
	for id in _tickets:
		var t: Dictionary = _tickets[id]
		t.age += delta
		var ref: WeakRef = t.owner_ref
		if t.age >= t.timeout or (ref != null and ref.get_ref() == null):
			gone.append(id)
	for id in gone:
		_tickets.erase(id)
	if not gone.is_empty():
		slots_changed.emit(used(), capacity)
