-- Tiny shared value, not a real module boundary: stamina itself is tracked
-- entirely inside SprintController.lua (a private local, same as the
-- sprint toggle always was), but ViewBobController.lua also needs to read
-- its current level for the low-stamina shake boost. Both are LocalScripts
-- on the same client, so requiring this same table from both gives them a
-- shared singleton with zero replication/attribute plumbing needed.

return {
	Fraction = 1, -- 0 (empty) .. 1 (full), written by SprintController.lua every frame
}
