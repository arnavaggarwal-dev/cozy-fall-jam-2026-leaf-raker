class_name ItemData
extends Resource

@export var id := &""
@export var display_name := ""
@export_multiline var description := ""
@export_file("*.glb") var model := ""
@export var world_size := 0.25
@export var max_stack := 1
@export var action := &""
@export var effect := &""
@export var effect_seconds := 0.0
@export_file("*.tscn") var placed_scene := ""
@export var lost_index := -1
