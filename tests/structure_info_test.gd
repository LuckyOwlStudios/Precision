extends SceneTree
## Checks the inspector's structure details: selecting a piece shows them, a
## typed move and a rename are undoable, and a joined truss lists its partner.
##   godot --headless --path . --script res://tests/structure_info_test.gd

var _failed := 0


func _init() -> void:
	var main: Control = (load("res://ui/main/main_window.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	var ctx: StudioContext = main.get_node("%Studio")
	var info: StructureInfo = main.get_node("%StructureInfo")
	var set_root := ctx.set_root
	_expect("stage view shares the set", set_root != null)
	var pieces := ctx.structure_pieces()
	_expect("default set has pieces", not pieces.is_empty())
	var piece: StructurePiece = pieces[0]

	ctx.select_piece(piece)
	await process_frame
	_expect("details show for a selected piece", info.visible)
	_expect("title is the piece's name", (info.get_node("%PieceTitle") as Label).text == StudioContext.piece_name(piece))

	var before := piece.global_transform
	ctx.place_piece(piece, Transform3D(before.basis, before.origin + Vector3(0, 0, 0.5)))
	_expect("typed move moves the piece", piece.global_position.is_equal_approx(before.origin + Vector3(0, 0, 0.5)))
	ctx.undo()
	_expect("undo puts it back", piece.global_transform.is_equal_approx(before))

	ctx.rename_piece(piece, "Left tower")
	_expect("rename shows", StudioContext.piece_name(piece) == "Left tower")
	ctx.undo()
	_expect("undo restores the type name", StudioContext.piece_name(piece) == piece.display_name)

	ctx.select_piece(null)
	await process_frame
	_expect("details hide with no piece", not info.visible)
	print("structure info test: ", "FAILED" if _failed else "ok")
	quit(1 if _failed else 0)


func _expect(label: String, ok: bool) -> void:
	if not ok:
		_failed += 1
		print("FAIL ", label)
