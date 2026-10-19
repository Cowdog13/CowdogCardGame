extends SceneTree
## The rulebook opens, every section renders, and a screenshot can be taken with SHOTS=dir.
func _init() -> void:
	var main: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main._show_rulebook()
	await process_frame
	var book: RulebookScreen = main._menu
	var fails := 0
	for i in RulebookScreen.SECTIONS.size():
		book._list.select(i)
		book._show_section(i)
		await process_frame
		if book._text.get_parsed_text().length() < 100:
			fails += 1
			print("section %d is empty" % i)
	book._list.select(6)
	book._show_section(6)
	await create_timer(0.4).timeout
	if OS.get_environment("SHOTS") != "":
		root.get_texture().get_image().save_png(OS.get_environment("SHOTS") + "/rulebook.png")
	print("rulebook_test failures=%d" % fails)
	quit(fails)
