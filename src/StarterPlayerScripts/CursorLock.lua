-- Frees the mouse for clickable menus (minigames, the death/respawn
-- screen). A one-time MouseBehavior/CameraMode set isn't reliable: while
-- the camera is in LockFirstPerson, Roblox's own core camera script
-- re-locks the mouse to screen-center on its own render step, and whether
-- our one-time set or its re-lock "wins" a given frame is a race -- which
-- is exactly why the mouse worked sometimes and not others. So instead we
-- keep re-asserting our desired state every frame for as long as a menu
-- needs the cursor, guaranteeing we always win.
--
-- Push/Pop is reference-counted so two menus opening back-to-back (or one
-- opening while another is already up) can't clobber each other's saved
-- state.

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local CursorLock = {}
local depth = 0
local savedCameraMode, savedMouseBehavior, savedMouseIconEnabled
local renderConn

function CursorLock.Push(player)
	if depth == 0 then
		savedCameraMode = player.CameraMode
		savedMouseBehavior = UserInputService.MouseBehavior
		savedMouseIconEnabled = UserInputService.MouseIconEnabled

		renderConn = RunService.RenderStepped:Connect(function()
			if player.CameraMode ~= Enum.CameraMode.Classic then
				player.CameraMode = Enum.CameraMode.Classic
			end
			if UserInputService.MouseBehavior ~= Enum.MouseBehavior.Default then
				UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			end
			if not UserInputService.MouseIconEnabled then
				UserInputService.MouseIconEnabled = true
			end
		end)
	end
	depth += 1
end

function CursorLock.Pop(player)
	if depth <= 0 then
		return
	end
	depth -= 1
	if depth == 0 then
		if renderConn then
			renderConn:Disconnect()
			renderConn = nil
		end
		player.CameraMode = savedCameraMode
		UserInputService.MouseBehavior = savedMouseBehavior
		UserInputService.MouseIconEnabled = savedMouseIconEnabled
	end
end

return CursorLock
