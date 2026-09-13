-- Frees the mouse for clickable menus (minigames, the death/respawn
-- screen). Just setting UserInputService.MouseBehavior isn't enough on its
-- own: while the camera is in LockFirstPerson mode, Roblox's core camera
-- script re-locks the mouse to screen-center every single frame, silently
-- undoing that. The actual fix is to drop out of LockFirstPerson while a
-- menu needs clicking, and restore whatever mode was active before.
--
-- Push/Pop is reference-counted so two menus opening back-to-back (or a
-- menu opening while another is already up) can't clobber each other's
-- saved state.

local UserInputService = game:GetService("UserInputService")

local CursorLock = {}
local depth = 0
local savedCameraMode, savedMouseBehavior, savedMouseIconEnabled

function CursorLock.Push(player)
	if depth == 0 then
		savedCameraMode = player.CameraMode
		savedMouseBehavior = UserInputService.MouseBehavior
		savedMouseIconEnabled = UserInputService.MouseIconEnabled
	end
	depth += 1
	player.CameraMode = Enum.CameraMode.Classic
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true
end

function CursorLock.Pop(player)
	if depth <= 0 then
		return
	end
	depth -= 1
	if depth == 0 then
		player.CameraMode = savedCameraMode
		UserInputService.MouseBehavior = savedMouseBehavior
		UserInputService.MouseIconEnabled = savedMouseIconEnabled
	end
end

return CursorLock
