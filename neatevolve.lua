-- MarI/O by SethBling
-- Feel free to use this code, but please do not redistribute it.

-- Port to FCEUX.
-- Tested on FCEUX 2.2.2 (Ubuntu 16.04).

-- #############################################################################
-- ### Instructions ############################################################
-- #############################################################################
-- 1. Save this script somewhere on your computer.
-- 2. Open Super Mario Bros. in FCEUX.
-- 3. Go to some level and make a saveste at the beginning of the level. Use
--    savestate slot 1 or edit the settings below.
-- 4. Load the script in FCEUX (File -> Load Lua Script)
-- 5. Enjoy!'

-- There's no GUI like in Bizhawk but you can edit the following settings
-- manually.


-- #############################################################################
-- ### SETTINGS ################################################################
-- #############################################################################

-- File name for a previously saved MarI/O pool. Use nil to start a new pool.
-- Backups for every generation will be saved in a folder called "backups".
LOAD_FROM_FILE = nil
--LOAD_FROM_FILE = "backups/backup.5.SMB1-1.state.pool"

-- HUD options. Use "false" to hide elements (might improve performance).
SHOW_NETWORK = true
SHOW_MUTATION_RATES = true

-- #############################################################################
-- #############################################################################
-- #############################################################################

SAVE_LOAD_FILE = "SMB1-1.state.pool"
RECORD_LOAD_FILE = "SMB1-1.rec"

os.execute("mkdir backups")

ButtonNames = {
	"A",
	"B",
	"up",
	"down",
	"left",
	"right",
}

BoxRadius = 6
InputSize = (BoxRadius*2+1)*(BoxRadius*2+1)

Inputs = InputSize+1
Outputs = #ButtonNames

Population = 300
DeltaDisjoint = 2.0
DeltaWeights = 0.4
DeltaThreshold = 1.0

StaleSpecies = 15

MutateConnectionsChance = 0.25
PerturbChance = 0.90
CrossoverChance = 0.75
LinkMutationChance = 2.0
NodeMutationChance = 0.50
BiasMutationChance = 0.40
StepSize = 0.1
DisableMutationChance = 0.4
EnableMutationChance = 0.2

TimeoutConstant = 20

MaxNodes = 1000000

-- recording

SaveGenerationRecords = false -- save unique replays for each generation to disk
MaxPlayedRecords = 1024 -- max simultaneously displaying records
SynchronizedPlayback = false -- should all records play simultaneously
PauseAfterDeath = true -- should game pause for some time, so collision with enemy will not end recording abruptly

DrawRecordAsSprite = true -- draw record using character sprite during playback
DrawRecordAsBox = false -- draw record using simple colored box during playback
DrawRecordTrail = false -- draw record trajectory trail during playback

RecordColors = { "red", "green", "blue", "cyan", "magenta", "yellow", "purple", "white", "orange" } -- colors used to display boxes and trails
RecordTrailFrameCount = 30 -- trail length in frames
DissolveAnimationFrames = 15 -- fade out animation duration in frames
PlayerCloseFadeDistance = 32 -- objects will start to fade at this distance to player, so player can be visible in very crowded environment. 0 to disable
PlayerCloseMaxFade = 0.1 -- maximum fade amount, so record still can be visible, even if its on same spot as player
CrossFadeOnRestart = false

GenerationRecordsList = {}
PlayingRecordsList = {}
CurrentRecord = {}
ScriptQueueSchedule = {}
LastFrameScreenshot = nil
LastFrameScreenshotVisibility = 0

CheckboxOnSprite = nil
CheckboxOffSprite = nil
SettingsButtonSprite = nil
ReplayCharacterSprites = {} -- table which hold every loaded sprite
ReplayCharacterSpriteCount = 160 -- amount of characters in sprites folder
ReplayCharacterFrameNames = { 
	"idle", 	-- 1
	"walk1", 	-- 2
	"walk2", 	-- 3
	"walk3", 	-- 4
	"jump", 	-- 5
	"skid", 	-- 6
	"climb1", 	-- 7
	"climb2", 	-- 8
	"swim1", 	-- 9
	"swim2", 	-- 10
	"swim3", 	-- 11
	"swim4", 	-- 12
	"swim5", 	-- 13
	"swim6" 	-- 14
}
IsMousePressed = false
IsMouseReleased = false
IsMouseClicked = false
IsGUIVisible = true
IsSettingsOpened = false
GUIVisibility = 1.0 
GUIOffset = 0
FocusedControlId = -1
CurrentControlId = 0
MouseX = 0
MouseY = 0

-- Game state
CurrentLocationId = nil
CurrentWorld = nil
CurrentLevel = nil
CurrentLevelLayout = nil
CurrentEnemyLayout = nil
PlayerX = nil
PlayerY = nil
ScreenX = nil

LevelStartSaveFile = nil
LocationStartSaveFile = nil

-- Sprite management functions

function loadGUISprites()
	CheckboxOnSprite = loadSprite("checkbox_on")
	CheckboxOffSprite = loadSprite("checkbox_off")
	SettingsButtonSprite = loadSprite("settings_button")
end

function loadCharacterSprites()
	for c = 1, ReplayCharacterSpriteCount do
		for i, name in pairs(ReplayCharacterFrameNames) do
			loadCharacterSprite(i, false, c)
			loadCharacterSprite(i, true, c)
		end	
	end
end

function getCharacterSprite(animFrame, mirrored, character)
	local index = getCharacterSpriteIndex(animFrame, mirrored, character)
	return ReplayCharacterSprites[index]
end

function getCharacterSpriteName(animFrame, mirrored, character)

	local side = "_r_"

	if mirrored then
		side = "_l_"
	end

	return ReplayCharacterFrameNames[animFrame] .. side.. character
end

function getCharacterSpriteIndex(animFrame, mirrored, character)
	return getCharacterSpriteName(animFrame, mirrored, character)
end

function loadCharacterSprite(animFrame, mirrored, character)

	local name = getCharacterSpriteName(animFrame, mirrored, character)
	local index = getCharacterSpriteIndex(animFrame, mirrored, character)
	ReplayCharacterSprites[index] = loadSprite(name)
end

function loadSprite(name) 
	local f = io.open("sprites/" .. name .. ".gd", "rb")
	local img = f:read("*all")
	f:close()
	return img
end

-- Game data parsing

function isGameStarted()
	return memory.readbyte(0x0764) == 1
end

function isCutscenePlaying()
	return memory.readbyte(0x757) == 1
end

function getCurrentLocationId()
	return CurrentLocationId
end

function isPlayerLoaded()
	return memory.readbyte(0x06C9) == 0xff and memory.readbyte(0x0490) ~= 0x00 -- TODO: check if this is a proper way to detect that player is loaded into level
end

function readCharacterAnimationDirection()
	return memory.readbyte(0x0033) == 2
end

function readCharacterAnimationSprite()

	local anim = memory.readbyte(0x06d5)
	local swimLegs = 0

	if AND(memory.readbyte(0x0009), 0x04) == 0x04 then
		swimLegs = 1
	end

	if anim == 0x68 or anim == 0x00 then return 2 end -- walk1
	if anim == 0x70 or anim == 0x10 then return 3 end -- walk2
	if anim == 0x60 or anim == 0x08 then return 4 end -- walk3
	if anim == 0x80 or anim == 0x20 then return 5 end -- jump
	if anim == 0x78 or anim == 0x18 then return 6 end -- skid
	if anim == 0xa0 or anim == 0x40 then return 7 end -- climb2
	if anim == 0xa8 or anim == 0x48 then return 8 end -- climb2

	if anim == 0x88 or anim == 0x28 then return 9 + swimLegs end -- swim1 or swim2
	if anim == 0x90 or anim == 0x30 then return 11 + swimLegs end -- swim3 or swim4
	if anim == 0x98 or anim == 0x38 then return 13 + swimLegs end -- swim5 or swim6

	-- if anim == 0x50 ... crouch
	-- if anim == 0x58 ... fire
	-- if anim == 0xe0 ... dead

	return 1
end

function updateGameInfo()

	local world = memory.readbyte(0x075F)
	local level = memory.readbyte(0x0760)
	local levelLayout = memory.readbyte(0x00E7) * 256 + memory.readbyte(0x00E8)
	local enemyLayout = memory.readbyte(0x00E9) * 256 + memory.readbyte(0x00EA)
	local isLevelChanged = world ~= CurrentWorld or level ~= CurrentLevel
	local isLayoutChanged = levelLayout ~= CurrentLevelLayout or enemyLayout ~= CurrentEnemyLayout

	if isLevelChanged or isLayoutchanged then

		local hexLevel = string.format("%x", levelLayout)
		local hexEnemy = string.format("%x", enemyLayout)

		CurrentLocationId = world .. "-" .. level .. "-" .. hexLevel .. hexEnemy
		CurrentWorld = world
		CurrentLevel = level
		CurrentLevelLayout = levelLayout
		CurrentEnemyLayout = enemyLayout

		if isLevelChanged then
			onNewLevel(CurrentWorld, CurrentLevel)
		end

		if isLayoutChanged then
			onNewLocation(CurrentLocationId)
		end

	end

	PlayerX = memory.readbyte(0x6D) * 0x100 + memory.readbyte(0x86)
	PlayerY = memory.readbyte(0x03B8) + (memory.readbyte(0xB5) - 1) * 0xFF
	ScreenX = memory.readbyte(0x03AD)

end

-- Record management functions

function newFrame(xPosition, yPosition, animation, direction, level, isVisible)
	local frame = {}
	frame.x = xPosition
	frame.y = yPosition
	frame.animation = animation
	frame.direction = direction
	frame.level = level
	frame.isVisible = isVisible
	return frame
end

function newRecording()
	local recording = {}

	recording.generation = 0
	recording.species = 0
	recording.genome = 0
	recording.fitness = 0
	recording.hash = 0
	recording.frames = {}
	recording.skin = getRecordSkin()
	recording.color = getRecordColor()

	return recording;
end

function getRecordSkin()
	return math.random(1, ReplayCharacterSpriteCount)
end

function getRecordColor()
	return RecordColors[math.random(1, #RecordColors)]
end

function recordCurrentFrame(record)
	record.frames[#record.frames + 1] = newFrame(PlayerX, PlayerY, 
		readCharacterAnimationSprite(), 
		readCharacterAnimationDirection(),
		getCurrentLocationId(),
		isPlayerLoaded());
	record.hash = record.hash + PlayerX * PlayerY
end

function saveGenerationRecord(record, generation, species, genome, fitness)

	record.generation = generation
	record.species = species
	record.genome = genome
	record.fitness = fitness

	for i, record in pairs(GenerationRecordsList) do
		if isRecordsSame(record, CurrentRecord) then return end
	end

	table.insert(GenerationRecordsList, record)
	emu.print("New unique record #" .. record.hash .. " added to generation record list, " .. #GenerationRecordsList .. " total" )
end

function clearGenerationRecords()
	GenerationRecordsList = {}
	collectgarbage()
end

-- Record playback functions

function addRecordToPlayback(record)

	for i, playback in ipairs(PlayingRecordsList) do
		if isRecordsSame(playback.record, record) then return end -- record is not unique
	end	

	local playback = {}

	playback.record = record
	playback.currentFrame = 1
	playback.totalFrames = #record.frames
	playback.frameSprites = {}

	for i, frame in ipairs(record.frames) do
		table.insert(playback.frameSprites, getCharacterSprite(frame.animation, frame.direction, record.skin))
	end

	table.insert(PlayingRecordsList, playback)

	if #PlayingRecordsList > MaxPlayedRecords then
		table.remove(PlayingRecordsList, 1)
	end
end

function resetPlaybackFrames()
	for i, playback in ipairs(PlayingRecordsList) do
		playback.currentFrame = 1
	end	
end

function updatePlaybackFrame(currentFrame)
	for i, playback in ipairs(PlayingRecordsList) do

		if SynchronizedPlayback then
			playback.currentFrame = currentFrame
		else
			local respawnDelay = DissolveAnimationFrames

			if DrawRecordTrail then
				respawnDelay = math.max(DissolveAnimationFrames, RecordTrailFrameCount)
			end

			playback.currentFrame = playback.currentFrame + 1
			if playback.totalFrames + respawnDelay < playback.currentFrame then
				playback.currentFrame = 1
			end
		end
	end	
end

function clearPlayingRecords()
	PlayingRecordsList = {}
end

-- GUI Drawing functions

function updateGUIInput()

	local i = input.get()
	local pressed = i.click == 1
	IsMouseClicked = pressed and pressed ~= IsMousePressed
	IsMouseReleased = not pressed and pressed ~= IsMousePressed
	IsMousePressed = pressed
	MouseX = i.xmouse
	MouseY = i.ymouse

	if IsMouseReleased then 
		FocusedControlId = -1
	end

	CurrentControlId = 0
end

function drawButton(x, y, w, text, color)
	gui.box(x, y, x + w, y + 8, color, color)
	gui.text(x + 1, y + 1, text, "white", "clear")

	if IsGUIVisible then
		return checkButton(x, y, w, 8)
	end

	return false
end

function drawSlider(x, y, w, value, minValue, maxValue, text)

	if not text then text = "" end

	gui.box(x, y, x + w, y + 8, { 0, 0, 0, 128 }, "white")
	local offset = 1 + ((value - minValue) / (maxValue - minValue)) * (w - 2)
	local t = 0

	if checkButton(x, y, w, 8, true) then
		t = (MouseX - x - 1) / (w - 2)

		if t < 0 then t = 0 end
		if t > 1 then t = 1 end

		value = math.floor(minValue + (maxValue - minValue) * t)
	end

	gui.text(x + 4, y + 1, value .. " " .. text, "#4CFF00aa", "clear")

	if offset < 1 then offset = 1 end
	if offset > w - 1 then offset = w - 1 end

	gui.line(x + offset, y + 1, x + offset, y + 7, "#4CFF00")

	return value
end

function drawCheckbox(x, y, w, isChecked, text)

	if checkButton(x, y, w, 7) then
		isChecked = not isChecked
	end

	if isChecked then
		gui.image(x, y, CheckboxOnSprite)
	else
		gui.image(x, y, CheckboxOffSprite)
	end

	drawShadedText(x + 10, y, text)

	return isChecked
end

function drawShadedText(x, y, text, color)

	if not color then color = white end

	gui.text(x + 1, y + 1, text, { 0, 0, 0, 128 }, "clear")
	gui.text(x, y, text, color, "clear")
end

function checkButton(x, y, w, h, continous)

	local isClicked = IsMouseClicked
	CurrentControlId = CurrentControlId + 1

	if continous then
		if FocusedControlId == CurrentControlId then
			return true
		end
	end

	if isClicked and MouseX >= x and MouseX < x + w and MouseY >= y and MouseY < y + h then
		IsMouseClicked = false
		FocusedControlId = CurrentControlId
		return true
	end

	return false
end

function updateGUIParams()
	if IsGUIVisible then
		if GUIVisibility < 1 then
			GUIVisibility = GUIVisibility + 0.05
		end
	else 
		if GUIVisibility > 0 then 
			GUIVisibility = GUIVisibility - 0.05
		end
	end

	local targetOffset = 0
	if IsSettingsOpened then targetOffset = -133 end
	GUIOffset = GUIOffset + (targetOffset - GUIOffset)  * 0.15
end

function startScreenCrossFade()
	LastFrameScreenshot = gui.gdscreenshot()
	LastFrameScreenshotVisibility = 1
end

function updateScreenCrossFade()
	if LastFrameScreenshotVisibility > 0 then
		LastFrameScreenshotVisibility = LastFrameScreenshotVisibility - 0.05
		if LastFrameScreenshotVisibility < 0 then LastFrameScreenshotVisibility = 0 end
	end
end

function formatFitness(fitness, appendSign) 

	local sign = "+"

	if appendSign then
		sign = getNumberSign(fitness)
	else
		sign = " "
	end

	return sign .. string.format("%04d", math.abs(math.floor(fitness)))
end

function getNumberSign(number)
	if number < 0 then return "-" else return "+" end
end

function drawGUI()

	if SHOW_NETWORK then
		gui.opacity(1)
		displayGenome(getCurrentGenome())
	end

	updateGUIParams()
	updateGUIInput()

	if GUIVisibility > 0 then
		gui.opacity(0.3 * GUIVisibility)
		gui.box(-1, 211 + GUIOffset, 256, 256, "black", "clear")

		gui.opacity(GUIVisibility)

		drawShadedText(8, 215 + GUIOffset, "Gen: " .. pool.generation .. 
			" Species: " .. pool.currentSpecies .. 
			" Genome: " .. pool.currentGenome .. 
			" (" .. getGenerationPercentage() .. "%)")

		
		local fitness = getTotalFitness()
		drawShadedText(8, 223 + GUIOffset, "Fitness: " .. formatFitness(fitness, false) .. 
			" / " .. formatFitness(pool.maxFitness, true))
		drawShadedText(49, 223 + GUIOffset, getNumberSign(fitness)) -- this is to prevent situation, when rapidly changing +- shakes whole text

		drawShadedText(136, 223 + GUIOffset, "Records: " .. math.min(#PlayingRecordsList, MaxPlayedRecords))

		gui.image(232, 214 + GUIOffset, SettingsButtonSprite)

		if IsGUIVisible and checkButton(232, 214 + GUIOffset, 16, 16) then IsSettingsOpened = not IsSettingsOpened end

		if GUIOffset < -0.1 then

			local bottomOffset = 232 + GUIOffset

			gui.opacity(GUIVisibility * 0.3)
			gui.box(0, bottomOffset, 255, bottomOffset - GUIOffset - 1, "black", "clear")
			gui.opacity(GUIVisibility)

			drawShadedText(8, 4 + bottomOffset, "Record display options", "red")
			gui.line(8, 12 + bottomOffset, 112, 12 + bottomOffset, "red")

			DrawRecordAsSprite = drawCheckbox(8, 16 + bottomOffset, 64, DrawRecordAsSprite, "Draw sprite")
			DrawRecordAsBox = drawCheckbox(96, 16 + bottomOffset, 64, DrawRecordAsBox, "Draw box")
			DrawRecordTrail = drawCheckbox(184, 16 + bottomOffset , 64, DrawRecordTrail, "Draw trail")

			drawShadedText(8, 26 + bottomOffset, "Trail length: ")
			RecordTrailFrameCount = drawSlider(96, 26 + bottomOffset, 150, RecordTrailFrameCount, 0, 120, "frames")

			drawShadedText(8, 36 + bottomOffset, "Death fade: ")
			DissolveAnimationFrames = drawSlider(96, 36 + bottomOffset, 150, DissolveAnimationFrames, 0, 60, "frames")

			drawShadedText(8, 46 + bottomOffset, "Fade distance: ")
			PlayerCloseFadeDistance = drawSlider(96, 46 + bottomOffset, 150, PlayerCloseFadeDistance, 0, 120, "pixels")

			drawShadedText(8, 58 + bottomOffset, "Record playback options", "red")
			gui.line(8, 66 + bottomOffset, 120, 66 + bottomOffset, "red")

			SynchronizedPlayback = drawCheckbox(8, 70 + bottomOffset, 64, SynchronizedPlayback, "Synchronous")

			drawShadedText(8, 80 + bottomOffset, "Maximum: ")
			MaxPlayedRecords = drawSlider(52, 80 + bottomOffset, 194, MaxPlayedRecords, 0, 2048, "records")

			drawShadedText(8, 92 + bottomOffset, "Misc", "red")
			gui.line(8, 100 + bottomOffset, 27, 100 + bottomOffset, "red")

			SaveGenerationRecords = drawCheckbox(8, 104 + bottomOffset, 96, SaveGenerationRecords, "Save records")
			PauseAfterDeath = drawCheckbox(8, 112 + bottomOffset, 96, PauseAfterDeath, "Pause after death")
			CrossFadeOnRestart = drawCheckbox(8, 120 + bottomOffset, 96, CrossFadeOnRestart, "Cross fade on restart")

			if drawButton(170, 120 + bottomOffset, 40, "Play Top", { 0, 255, 0, 128 }) then 
				IsSettingsOpened = false
				schedule(playTop)
			end
			if drawButton(212, 120 + bottomOffset, 34, "Restart", { 255, 0, 0, 128 }) then
				IsSettingsOpened = false
				schedule(restart)
			end
		end
	end

	-- This check order is intentional, so panel will block clicks
	if checkButton(0, 212 + GUIOffset, 256, 256) and not IsSettingsOpened then IsGUIVisible = not IsGUIVisible end 
	if checkButton(0, 26, 256, 76) then SHOW_NETWORK = not SHOW_NETWORK end
	if checkButton(0, 103, 256, 128) then SHOW_MUTATION_RATES = not SHOW_MUTATION_RATES end
end

-- Record drawing functions

function forEachPlayingRecord(func)

	local xScreenOffset = PlayerX - ScreenX
	local yScreenOffset = 0
	local levelLayoutId = getCurrentLocationId()

	for i, playback in ipairs(PlayingRecordsList) do

		if i > MaxPlayedRecords then return end

		local currentFrame = playback.currentFrame
		local lastFrame = currentFrame
		local firstFrame = currentFrame - RecordTrailFrameCount
		local frameCount = playback.totalFrames

		if lastFrame > frameCount then lastFrame = frameCount end

		func(playback, lastFrame, currentFrame, xScreenOffset, yScreenOffset, levelLayoutId)
	end	
end

function calculateProximityOpacity(frameData)
	local opacityScale = 1

	if PlayerCloseFadeDistance > 0 then
		opacityScale = getProximity(frameData.x, frameData.y, PlayerX, PlayerY) / PlayerCloseFadeDistance
		if opacityScale > 1 then opacityScale = 1 end
		if opacityScale < PlayerCloseMaxFade then opacityScale = PlayerCloseMaxFade end
	end	

	return opacityScale
end

function drawRecordTrail(playback, lastFrame, currentFrame, xScreenOffset, yScreenOffset, currentLayout)

	local record = playback.record
	local firstFrame = currentFrame - RecordTrailFrameCount

	if firstFrame > lastFrame then firstFrame = lastFrame end
	if firstFrame < 1 then firstFrame = 1 end

	local prevXPosition
	local prevYPosition

	for frame = firstFrame, lastFrame do

		local frameData = record.frames[frame]

		if frameData.level == currentLayout and frameData.isVisible then 
			local xPosition = frameData.x - xScreenOffset + 8
			local yPosition = frameData.y - yScreenOffset + 24

			if prevXPosition and (xPosition ~= prevXPosition or yPosition ~= prevYPosition) and isInScreenBounds(xPosition, yPosition, 4) then

				local proximityScale = calculateProximityOpacity(frameData)
				local colorScale = (frame - firstFrame + 1) / RecordTrailFrameCount

				gui.opacity(colorScale * proximityScale)
				gui.line(prevXPosition, prevYPosition, xPosition, yPosition, record.color, false)
			end	

			prevXPosition = xPosition
			prevYPosition = yPosition
		else
			prevXPosition = nil
			prevYPosition = nil
		end	
	end
end

function drawRecordBox(playback, lastFrame, currentFrame, xScreenOffset, yScreenOffset, currentLayout)

	local record = playback.record
	local frameData = record.frames[lastFrame]

	if not frameData.isVisible or frameData.level ~= currentLayout then return end

	local xPosition = frameData.x - xScreenOffset + 8
	local yPosition = frameData.y - yScreenOffset + 24
	local frameCount = playback.totalFrames

	if isInScreenBounds(xPosition, yPosition, 12) and (frameCount + DissolveAnimationFrames) > currentFrame then 

		local size = 1
		local proximityScale = calculateProximityOpacity(frameData)

		if frameCount > currentFrame then
			gui.opacity(proximityScale)
		else
			local t = (currentFrame - frameCount) / DissolveAnimationFrames
			gui.opacity((1 - t) * proximityScale)
			size = 1 + 10 * t
		end	

		gui.box(xPosition - size, yPosition - size, xPosition + size, yPosition + size, record.color, { 0, 0, 0, 128 })

	end	
end

function drawRecordCharacter(playback, lastFrame, currentFrame, xScreenOffset, yScreenOffset, currentLayout)
	
	local record = playback.record
	local frameData = record.frames[lastFrame]

	if not frameData.isVisible or frameData.level ~= currentLayout then return end

	local xPosition = frameData.x - xScreenOffset - 4
	local yPosition = frameData.y - yScreenOffset + 9	
	local animImage = playback.frameSprites[lastFrame]
	local frameCount = playback.totalFrames
	local proximityScale = calculateProximityOpacity(frameData)

	if isInScreenBounds(xPosition, yPosition, 24) and (frameCount + DissolveAnimationFrames) > currentFrame and animImage then
		
		if frameCount > currentFrame then
			gui.opacity(proximityScale)
		else
			local t = (currentFrame - frameCount) / DissolveAnimationFrames
			gui.opacity((1 - t) * proximityScale)
		end
		
		gui.image(xPosition, yPosition, animImage)
	end
end

function drawPlayingRecords()

	if not isPlayerLoaded() or isCutscenePlaying() then
		return -- if player is not loaded, then probably it is a blank screen, so dont display replays here
	end

	if DrawRecordTrail then
		forEachPlayingRecord(drawRecordTrail)
	end

	if DrawRecordAsSprite then
		forEachPlayingRecord(drawRecordCharacter)
	end

	if DrawRecordAsBox then
		forEachPlayingRecord(drawRecordBox)
	end	
end

function drawScreenCrossFade()
	if LastFrameScreenshot and LastFrameScreenshotVisibility ~= 0 then 
		gui.opacity(LastFrameScreenshotVisibility)
		gui.image(0, 0, LastFrameScreenshot)
		drawShadedText(108, 108, "RESTARTING...")
	end
end

-- Saving, Loading

function writeRecordsBackupFile()
	writeRecordsFile("backups/backup." .. pool.generation .. "." .. RECORD_LOAD_FILE, GenerationRecordsList)
end

function writeGenerationBackupFile() 
	writeFile("backups/backup." .. pool.generation .. "." .. SAVE_LOAD_FILE)
end

function writeRecordsFile(filename, recordList)

	local file = io.open(filename, "w")
	file:write("2\n") -- format version
	file:write(#recordList .. "\n")
	for i, record in ipairs(recordList) do
		local r, g, b, a = gui.parsecolor(record.color)
		file:write("--- record [" .. i .. "] ---\n")

		file:write(record.hash .. "\n")
		file:write(record.fitness .. "\n")
		file:write(#record.frames .. "\n")

		file:write(record.generation .. "\n")
		file:write(record.species .. "\n")
		file:write(record.genome .. "\n")
		file:write(record.skin .. "\n")
		file:write(r .. ", " .. g .. ", " .. b .. ", " .. a .. "\n")

		for j, frame in ipairs(record.frames) do

			local anim = -1

			if frame.isVisible then
				anim = frame.animation

				if frame.direction then 
					anim = anim + 0x20
				end
			end

			file:write(frame.x .. " " .. frame.y .. " " .. anim .. " " .. frame.level .. "\n")
		end	
	end

	file:close()
end


-- Utility functions

function schedule(func)
	table.insert(ScriptQueueSchedule, func)
end

function getProximity(x1, y1, x2, y2)
	return math.max(math.abs(x1 - x2), math.abs(y1 - y2))
end

function isInScreenBounds(x, y, radius)
	return x > -radius and x < 256 + radius and y > -radius and y < 256 + radius
end

function isRecordsSame(record1, record2)
	return record1.hash == record2.hash and record1.fitness == record2.fitness and #record1.frames == #record2.frames
end	

function runScheduledFunctions()
	if #ScriptQueueSchedule ~= 0 then 
		for i, f in ipairs(ScriptQueueSchedule) do
			f()
		end
		ScriptQueueSchedule = {}
	end
end

function waitForFrames(frameCount)
	for i = 1,frameCount do
		emu.frameadvance()
	end
end

-- Original algorithm

function toRGBA(ARGB)
	return bit.lshift(ARGB, 8) + bit.rshift(ARGB, 24)
end

function isDead()

	local playerState = memory.readbyte(0x000E)

	return playerState == 0x0B or 		-- Dying
		   playerState == 0x06 or 		-- Dead
		   memory.readbyte(0x00B5) > 1	-- Below viewport (in pit)
end

function getTile(dx, dy)
	local x = PlayerX + dx + 8
	local y = PlayerY + dy
	local page = math.floor(x/256)%2

	local subx = math.floor((x%256)/16)
	local suby = math.floor((y - 32)/16)
	local addr = 0x500 + page*13*16+suby*16+subx

	if suby >= 13 or suby < 0 then
		return 0
	end

	if memory.readbyte(addr) ~= 0 then
		return 1
	else
		return 0
	end
end

function getSprites()
	local sprites = {}
	for slot=0,4 do
		local enemy = memory.readbyte(0xF+slot)
		if enemy ~= 0 then
			local ex = memory.readbyte(0x6E + slot)*0x100 + memory.readbyte(0x87+slot)
			local ey = memory.readbyte(0xCF + slot)+24
			sprites[#sprites+1] = {["x"]=ex,["y"]=ey}
		end
	end

	return sprites
end

function getInputs()

	local sprites = getSprites()

	local inputs = {}

	for dy=-BoxRadius*16,BoxRadius*16,16 do
		for dx=-BoxRadius*16,BoxRadius*16,16 do
			inputs[#inputs+1] = 0

			tile = getTile(dx, dy)
			if tile == 1 and PlayerY+dy + 16 < 0x1B0 then
				inputs[#inputs] = 1
			end

			for i = 1,#sprites do
				distx = math.abs(sprites[i]["x"] - (PlayerX+dx))
				disty = math.abs(sprites[i]["y"] - (PlayerY+dy + 16))
				if distx <= 8 and disty <= 8 then
					inputs[#inputs] = -1
				end
			end
		end
	end

	--mariovx = memory.read_s8(0x7B)
	--mariovy = memory.read_s8(0x7D)

	return inputs
end

function sigmoid(x)
	return 2/(1+math.exp(-4.9*x))-1
end

function newInnovation()
	pool.innovation = pool.innovation + 1
	return pool.innovation
end

function newPool()
	local pool = {}
	pool.species = {}
	pool.generation = 0
	pool.innovation = Outputs
	pool.currentSpecies = 1
	pool.currentGenome = 1
	pool.currentFrame = 1
	pool.maxFitness = 0

	return pool
end

function newSpecies()
	local species = {}
	species.topFitness = 0
	species.staleness = 0
	species.genomes = {}
	species.averageFitness = 0

	return species
end

function newGenome()
	local genome = {}
	genome.genes = {}
	genome.fitness = 0
	genome.adjustedFitness = 0
	genome.network = {}
	genome.maxneuron = 0
	genome.globalRank = 0
	genome.mutationRates = {}
	genome.mutationRates["connections"] = MutateConnectionsChance
	genome.mutationRates["link"] = LinkMutationChance
	genome.mutationRates["bias"] = BiasMutationChance
	genome.mutationRates["node"] = NodeMutationChance
	genome.mutationRates["enable"] = EnableMutationChance
	genome.mutationRates["disable"] = DisableMutationChance
	genome.mutationRates["step"] = StepSize

	return genome
end

function copyGenome(genome)
	local genome2 = newGenome()
	for g=1,#genome.genes do
		table.insert(genome2.genes, copyGene(genome.genes[g]))
	end
	genome2.maxneuron = genome.maxneuron
	genome2.mutationRates["connections"] = genome.mutationRates["connections"]
	genome2.mutationRates["link"] = genome.mutationRates["link"]
	genome2.mutationRates["bias"] = genome.mutationRates["bias"]
	genome2.mutationRates["node"] = genome.mutationRates["node"]
	genome2.mutationRates["enable"] = genome.mutationRates["enable"]
	genome2.mutationRates["disable"] = genome.mutationRates["disable"]

	return genome2
end

function basicGenome()
	local genome = newGenome()
	local innovation = 1

	genome.maxneuron = Inputs
	mutate(genome)

	return genome
end

function newGene()
	local gene = {}
	gene.into = 0
	gene.out = 0
	gene.weight = 0.0
	gene.enabled = true
	gene.innovation = 0

	return gene
end

function copyGene(gene)
	local gene2 = newGene()
	gene2.into = gene.into
	gene2.out = gene.out
	gene2.weight = gene.weight
	gene2.enabled = gene.enabled
	gene2.innovation = gene.innovation

	return gene2
end

function newNeuron()
	local neuron = {}
	neuron.incoming = {}
	neuron.value = 0.0

	return neuron
end

function generateNetwork(genome)
	local network = {}
	network.neurons = {}

	for i=1,Inputs do
		network.neurons[i] = newNeuron()
	end

	for o=1,Outputs do
		network.neurons[MaxNodes+o] = newNeuron()
	end

	table.sort(genome.genes, function (a,b)
		return (a.out < b.out)
	end)
	for i=1,#genome.genes do
		local gene = genome.genes[i]
		if gene.enabled then
			if network.neurons[gene.out] == nil then
				network.neurons[gene.out] = newNeuron()
			end
			local neuron = network.neurons[gene.out]
			table.insert(neuron.incoming, gene)
			if network.neurons[gene.into] == nil then
				network.neurons[gene.into] = newNeuron()
			end
		end
	end

	genome.network = network
end

function evaluateNetwork(network, inputs)
	table.insert(inputs, 1)
	if #inputs ~= Inputs then
		emu.print("Incorrect number of neural network inputs.")
		return {}
	end

	for i=1,Inputs do
		network.neurons[i].value = inputs[i]
	end

	for _,neuron in pairs(network.neurons) do
		local sum = 0
		for j = 1,#neuron.incoming do
			local incoming = neuron.incoming[j]
			local other = network.neurons[incoming.into]
			sum = sum + incoming.weight * other.value
		end

		if #neuron.incoming > 0 then
			neuron.value = sigmoid(sum)
		end
	end

	local outputs = {}
	for o=1,Outputs do
		local button = ButtonNames[o]
		if network.neurons[MaxNodes+o].value > 0 then
			outputs[button] = true
		else
			outputs[button] = false
		end
	end

	return outputs
end

function crossover(g1, g2)
	-- Make sure g1 is the higher fitness genome
	if g2.fitness > g1.fitness then
		tempg = g1
		g1 = g2
		g2 = tempg
	end

	local child = newGenome()

	local innovations2 = {}
	for i=1,#g2.genes do
		local gene = g2.genes[i]
		innovations2[gene.innovation] = gene
	end

	for i=1,#g1.genes do
		local gene1 = g1.genes[i]
		local gene2 = innovations2[gene1.innovation]
		if gene2 ~= nil and math.random(2) == 1 and gene2.enabled then
			table.insert(child.genes, copyGene(gene2))
		else
			table.insert(child.genes, copyGene(gene1))
		end
	end

	child.maxneuron = math.max(g1.maxneuron,g2.maxneuron)

	for mutation,rate in pairs(g1.mutationRates) do
		child.mutationRates[mutation] = rate
	end

	return child
end

function randomNeuron(genes, nonInput)
	local neurons = {}
	if not nonInput then
		for i=1,Inputs do
			neurons[i] = true
		end
	end
	for o=1,Outputs do
		neurons[MaxNodes+o] = true
	end
	for i=1,#genes do
		if (not nonInput) or genes[i].into > Inputs then
			neurons[genes[i].into] = true
		end
		if (not nonInput) or genes[i].out > Inputs then
			neurons[genes[i].out] = true
		end
	end

	local count = 0
	for _,_ in pairs(neurons) do
		count = count + 1
	end
	local n = math.random(1, count)

	for k,v in pairs(neurons) do
		n = n-1
		if n == 0 then
			return k
		end
	end

	return 0
end

function containsLink(genes, link)
	for i=1,#genes do
		local gene = genes[i]
		if gene.into == link.into and gene.out == link.out then
			return true
		end
	end
end

function pointMutate(genome)
	local step = genome.mutationRates["step"]

	for i=1,#genome.genes do
		local gene = genome.genes[i]
		if math.random() < PerturbChance then
			gene.weight = gene.weight + math.random() * step*2 - step
		else
			gene.weight = math.random()*4-2
		end
	end
end

function linkMutate(genome, forceBias)
	local neuron1 = randomNeuron(genome.genes, false)
	local neuron2 = randomNeuron(genome.genes, true)

	local newLink = newGene()
	if neuron1 <= Inputs and neuron2 <= Inputs then
		--Both input nodes
		return
	end
	if neuron2 <= Inputs then
		-- Swap output and input
		local temp = neuron1
		neuron1 = neuron2
		neuron2 = temp
	end

	newLink.into = neuron1
	newLink.out = neuron2
	if forceBias then
		newLink.into = Inputs
	end

	if containsLink(genome.genes, newLink) then
		return
	end
	newLink.innovation = newInnovation()
	newLink.weight = math.random()*4-2

	table.insert(genome.genes, newLink)
end

function nodeMutate(genome)
	if #genome.genes == 0 then
		return
	end

	genome.maxneuron = genome.maxneuron + 1

	local gene = genome.genes[math.random(1,#genome.genes)]
	if not gene.enabled then
		return
	end
	gene.enabled = false

	local gene1 = copyGene(gene)
	gene1.out = genome.maxneuron
	gene1.weight = 1.0
	gene1.innovation = newInnovation()
	gene1.enabled = true
	table.insert(genome.genes, gene1)

	local gene2 = copyGene(gene)
	gene2.into = genome.maxneuron
	gene2.innovation = newInnovation()
	gene2.enabled = true
	table.insert(genome.genes, gene2)
end

function enableDisableMutate(genome, enable)
	local candidates = {}
	for _,gene in pairs(genome.genes) do
		if gene.enabled == not enable then
			table.insert(candidates, gene)
		end
	end

	if #candidates == 0 then
		return
	end

	local gene = candidates[math.random(1,#candidates)]
	gene.enabled = not gene.enabled
end

function mutate(genome)
	for mutation,rate in pairs(genome.mutationRates) do
		if math.random(1,2) == 1 then
			genome.mutationRates[mutation] = 0.95*rate
		else
			genome.mutationRates[mutation] = 1.05263*rate
		end
	end

	if math.random() < genome.mutationRates["connections"] then
		pointMutate(genome)
	end

	local p = genome.mutationRates["link"]
	while p > 0 do
		if math.random() < p then
			linkMutate(genome, false)
		end
		p = p - 1
	end

	p = genome.mutationRates["bias"]
	while p > 0 do
		if math.random() < p then
			linkMutate(genome, true)
		end
		p = p - 1
	end

	p = genome.mutationRates["node"]
	while p > 0 do
		if math.random() < p then
			nodeMutate(genome)
		end
		p = p - 1
	end

	p = genome.mutationRates["enable"]
	while p > 0 do
		if math.random() < p then
			enableDisableMutate(genome, true)
		end
		p = p - 1
	end

	p = genome.mutationRates["disable"]
	while p > 0 do
		if math.random() < p then
			enableDisableMutate(genome, false)
		end
		p = p - 1
	end
end

function disjoint(genes1, genes2)
	local i1 = {}
	for i = 1,#genes1 do
		local gene = genes1[i]
		i1[gene.innovation] = true
	end

	local i2 = {}
	for i = 1,#genes2 do
		local gene = genes2[i]
		i2[gene.innovation] = true
	end

	local disjointGenes = 0
	for i = 1,#genes1 do
		local gene = genes1[i]
		if not i2[gene.innovation] then
			disjointGenes = disjointGenes+1
		end
	end

	for i = 1,#genes2 do
		local gene = genes2[i]
		if not i1[gene.innovation] then
			disjointGenes = disjointGenes+1
		end
	end

	local n = math.max(#genes1, #genes2)

	return disjointGenes / n
end

function weights(genes1, genes2)
	local i2 = {}
	for i = 1,#genes2 do
		local gene = genes2[i]
		i2[gene.innovation] = gene
	end

	local sum = 0
	local coincident = 0
	for i = 1,#genes1 do
		local gene = genes1[i]
		if i2[gene.innovation] ~= nil then
			local gene2 = i2[gene.innovation]
			sum = sum + math.abs(gene.weight - gene2.weight)
			coincident = coincident + 1
		end
	end

	return sum / coincident
end

function sameSpecies(genome1, genome2)
	local dd = DeltaDisjoint*disjoint(genome1.genes, genome2.genes)
	local dw = DeltaWeights*weights(genome1.genes, genome2.genes)
	return dd + dw < DeltaThreshold
end

function rankGlobally()
	local global = {}
	for s = 1,#pool.species do
		local species = pool.species[s]
		for g = 1,#species.genomes do
			table.insert(global, species.genomes[g])
		end
	end
	table.sort(global, function (a,b)
		return (a.fitness < b.fitness)
	end)

	for g=1,#global do
		global[g].globalRank = g
	end
end

function calculateAverageFitness(species)
	local total = 0

	for g=1,#species.genomes do
		local genome = species.genomes[g]
		total = total + genome.globalRank
	end

	species.averageFitness = total / #species.genomes
end

function totalAverageFitness()
	local total = 0
	for s = 1,#pool.species do
		local species = pool.species[s]
		total = total + species.averageFitness
	end

	return total
end

function cullSpecies(cutToOne)
	for s = 1,#pool.species do
		local species = pool.species[s]

		table.sort(species.genomes, function (a,b)
			return (a.fitness > b.fitness)
		end)

		local remaining = math.ceil(#species.genomes/2)
		if cutToOne then
			remaining = 1
		end
		while #species.genomes > remaining do
			table.remove(species.genomes)
		end
	end
end

function breedChild(species)
	local child = {}
	if math.random() < CrossoverChance then
		g1 = species.genomes[math.random(1, #species.genomes)]
		g2 = species.genomes[math.random(1, #species.genomes)]
		child = crossover(g1, g2)
	else
		g = species.genomes[math.random(1, #species.genomes)]
		child = copyGenome(g)
	end

	mutate(child)

	return child
end

function removeStaleSpecies()
	local survived = {}

	for s = 1,#pool.species do
		local species = pool.species[s]

		table.sort(species.genomes, function (a,b)
			return (a.fitness > b.fitness)
		end)

		if species.genomes[1].fitness > species.topFitness then
			species.topFitness = species.genomes[1].fitness
			species.staleness = 0
		else
			species.staleness = species.staleness + 1
		end
		if species.staleness < StaleSpecies or species.topFitness >= pool.maxFitness then
			table.insert(survived, species)
		end
	end

	pool.species = survived
end

function removeWeakSpecies()
	local survived = {}

	local sum = totalAverageFitness()
	for s = 1,#pool.species do
		local species = pool.species[s]
		breed = math.floor(species.averageFitness / sum * Population)
		if breed >= 1 then
			table.insert(survived, species)
		end
	end

	pool.species = survived
end


function addToSpecies(child)
	local foundSpecies = false
	for s=1,#pool.species do
		local species = pool.species[s]
		if not foundSpecies and sameSpecies(child, species.genomes[1]) then
			table.insert(species.genomes, child)
			foundSpecies = true
		end
	end

	if not foundSpecies then
		local childSpecies = newSpecies()
		table.insert(childSpecies.genomes, child)
		table.insert(pool.species, childSpecies)
	end
end

function newGeneration()
	cullSpecies(false) -- Cull the bottom half of each species
	rankGlobally()
	removeStaleSpecies()
	rankGlobally()
	for s = 1,#pool.species do
		local species = pool.species[s]
		calculateAverageFitness(species)
	end
	removeWeakSpecies()
	local sum = totalAverageFitness()
	local children = {}
	for s = 1,#pool.species do
		local species = pool.species[s]
		breed = math.floor(species.averageFitness / sum * Population) - 1
		for i=1,breed do
			table.insert(children, breedChild(species))
		end
	end
	cullSpecies(true) -- Cull all but the top member of each species
	while #children + #pool.species < Population do
		local species = pool.species[math.random(1, #pool.species)]
		table.insert(children, breedChild(species))
	end
	for c=1,#children do
		local child = children[c]
		addToSpecies(child)
	end

	pool.generation = pool.generation + 1
	writeGenerationBackupFile()

	onNewGeneration()
end

function initializePool()
	pool = newPool()

	for i=1,Population do
		basic = basicGenome()
		addToSpecies(basic)
	end

	initializeRun()
end

function clearJoypad()
	controller = {}
	for b = 1,#ButtonNames do
		controller[ButtonNames[b]] = false
	end
	joypad.set(1, controller)
end

function initializeRun()
	CurrentRecord = onNewRecord()

	savestate.load(LocationStartSaveFile);
	rightmost = 0
	pool.currentFrame = 1
	timeout = TimeoutConstant
	clearJoypad()

	local species = pool.species[pool.currentSpecies]
	local genome = species.genomes[pool.currentGenome]
	generateNetwork(genome)

	updateGameInfo()
	evaluateCurrent()
end

function evaluateCurrent()
	local genome = getCurrentGenome()

	inputs = getInputs()
	controller = evaluateNetwork(genome.network, inputs)

	if controller["left"] and controller["right"] then
		controller["left"] = false
		controller["right"] = false
	end
	if controller["up"] and controller["down"] then
		controller["up"] = false
		controller["down"] = false
	end

	joypad.set(1, controller)
end

function nextGenome()
	pool.currentGenome = pool.currentGenome + 1
	if pool.currentGenome > #pool.species[pool.currentSpecies].genomes then
		pool.currentGenome = 1
		pool.currentSpecies = pool.currentSpecies+1
		if pool.currentSpecies > #pool.species then
			newGeneration()
			pool.currentSpecies = 1
		end
	end
end

function fitnessAlreadyMeasured()
	local species = pool.species[pool.currentSpecies]
	local genome = species.genomes[pool.currentGenome]

	return genome.fitness ~= 0
end

function displayGenome(genome)

	if not genome then return end

	local network = genome.network
	local cells = {}
	local i = 1
	local cell = {}
	for dy=-BoxRadius,BoxRadius do
		for dx=-BoxRadius,BoxRadius do
			cell = {}
			cell.x = 50+5*dx
			cell.y = 70+5*dy
			cell.value = network.neurons[i].value
			cells[i] = cell
			i = i + 1
		end
	end
	local biasCell = {}
	biasCell.x = 80
	biasCell.y = 110
	biasCell.value = network.neurons[Inputs].value
	cells[Inputs] = biasCell

	for o = 1,Outputs do
		cell = {}
		cell.x = 220
		cell.y = 30 + 8 * o
		cell.value = network.neurons[MaxNodes + o].value
		cells[MaxNodes+o] = cell
		local color
		if cell.value > 0 then
			color = 0xFF0000FF
		else
			color = 0xFF000000
		end
		gui.drawtext(225, 26+8*o, ButtonNames[o], toRGBA(color), 0x0)
	end

	for n,neuron in pairs(network.neurons) do
		cell = {}
		if n > Inputs and n <= MaxNodes then
			cell.x = 140
			cell.y = 40
			cell.value = neuron.value
			cells[n] = cell
		end
	end

	for n=1,4 do
		for _,gene in pairs(genome.genes) do
			if gene.enabled then
				local c1 = cells[gene.into]
				local c2 = cells[gene.out]
				if gene.into > Inputs and gene.into <= MaxNodes then
					c1.x = 0.75*c1.x + 0.25*c2.x
					if c1.x >= c2.x then
						c1.x = c1.x - 40
					end
					if c1.x < 90 then
						c1.x = 90
					end

					if c1.x > 220 then
						c1.x = 220
					end
					c1.y = 0.75*c1.y + 0.25*c2.y

				end
				if gene.out > Inputs and gene.out <= MaxNodes then
					c2.x = 0.25*c1.x + 0.75*c2.x
					if c1.x >= c2.x then
						c2.x = c2.x + 40
					end
					if c2.x < 90 then
						c2.x = 90
					end
					if c2.x > 220 then
						c2.x = 220
					end
					c2.y = 0.25*c1.y + 0.75*c2.y
				end
			end
		end
	end

	gui.drawbox(50-BoxRadius*5-3,70-BoxRadius*5-3,50+BoxRadius*5+2,70+BoxRadius*5+2,toRGBA(0x80808080),toRGBA(0xFF000000))
	for n,cell in pairs(cells) do
		if n > Inputs or cell.value ~= 0 then
			local color = math.floor((cell.value+1)/2*256)
			if color > 255 then color = 255 end
			if color < 0 then color = 0 end
			local opacity = 0xFF000000
			if cell.value == 0 then
				opacity = 0x50000000
			end
			color = opacity + color*0x10000 + color*0x100 + color
			gui.drawbox(cell.x-2,cell.y-2,cell.x+2,cell.y+2,toRGBA(color),toRGBA(opacity))
		end
	end
	for _,gene in pairs(genome.genes) do
		if gene.enabled then
			local c1 = cells[gene.into]
			local c2 = cells[gene.out]
			local opacity = 0xA0000000
			if c1.value == 0 then
				opacity = 0x20000000
			end

			local color = 0x80-math.floor(math.abs(sigmoid(gene.weight))*0x80)
			if gene.weight > 0 then
				color = opacity + 0x8000 + 0x10000*color
			else
				color = opacity + 0x800000 + 0x100*color
			end
			gui.drawline(c1.x+1, c1.y, c2.x-3, c2.y, toRGBA(color))
		end
	end

	gui.drawbox(49,71,51,78,toRGBA(0x80FF0000),toRGBA(0x00000000))

	if SHOW_MUTATION_RATES then
		local pos = 120
		for mutation,rate in pairs(genome.mutationRates) do
			gui.drawtext(16, pos, mutation .. ": " .. rate, toRGBA(0xFF000000), 0x0)
			pos = pos + 8
		end
	end
end

function writeFile(filename)
	local file = io.open(filename, "w")
	file:write(pool.generation .. "\n")
	file:write(pool.maxFitness .. "\n")
	file:write(#pool.species .. "\n")
	for n,species in pairs(pool.species) do
		file:write(species.topFitness .. "\n")
		file:write(species.staleness .. "\n")
		file:write(#species.genomes .. "\n")
		for m,genome in pairs(species.genomes) do
			file:write(genome.fitness .. "\n")
			file:write(genome.maxneuron .. "\n")
			for mutation,rate in pairs(genome.mutationRates) do
				file:write(mutation .. "\n")
				file:write(rate .. "\n")
			end
			file:write("done\n")

			file:write(#genome.genes .. "\n")
			for l,gene in pairs(genome.genes) do
				file:write(gene.into .. " ")
				file:write(gene.out .. " ")
				file:write(gene.weight .. " ")
				file:write(gene.innovation .. " ")
				if(gene.enabled) then
					file:write("1\n")
				else
					file:write("0\n")
				end
			end
		end
	end
	file:close()
end

function savePool()
	local filename = SAVE_LOAD_FILE
	writeFile(filename)
end

function loadFile(filename)
	local file = io.open(filename, "r")
	pool = newPool()
	pool.generation = file:read("*number")
	pool.maxFitness = file:read("*number")
	--forms.settext(maxFitnessLabel, "Max Fitness: " .. math.floor(pool.maxFitness))
	local numSpecies = file:read("*number")
	for s=1,numSpecies do
		local species = newSpecies()
		table.insert(pool.species, species)
		species.topFitness = file:read("*number")
		species.staleness = file:read("*number")
		local numGenomes = file:read("*number")
		for g=1,numGenomes do
			local genome = newGenome()
			table.insert(species.genomes, genome)
			genome.fitness = file:read("*number")
			genome.maxneuron = file:read("*number")
			local line = file:read("*line")
			while line ~= "done" do
				genome.mutationRates[line] = file:read("*number")
				line = file:read("*line")
			end
			local numGenes = file:read("*number")
			for n=1,numGenes do
				local gene = newGene()
				table.insert(genome.genes, gene)
				local enabled
				gene.into, gene.out, gene.weight, gene.innovation, enabled = file:read("*number", "*number", "*number", "*number", "*number")
				if enabled == 0 then
					gene.enabled = false
				else
					gene.enabled = true
				end

			end
		end
	end
	file:close()

	while fitnessAlreadyMeasured() do
		nextGenome()
	end
	initializeRun()
end

function loadPool()
	loadFile(LOAD_FROM_FILE)
end

function playTop()
	local maxfitness = 0
	local maxs, maxg
	for s,species in pairs(pool.species) do
		for g,genome in pairs(species.genomes) do
			if genome.fitness > maxfitness then
				maxfitness = genome.fitness
				maxs = s
				maxg = g
			end
		end
	end

	pool.currentSpecies = maxs
	pool.currentGenome = maxg
	pool.maxFitness = maxfitness
	--forms.settext(maxFitnessLabel, "Max Fitness: " .. math.floor(pool.maxFitness))
	initializeRun()
	return
end

function restart()
	if input.popup("Are you sure you want to restart?") == "yes" then
		onRestart()
		initializePool()
	end
end

function getCurrentGenome()
	local species = pool.species[pool.currentSpecies]
	return species.genomes[pool.currentGenome]
end

function getTotalFitness()

	local framesPenalty = 0

	if isDead() then
		framesPenalty = getEstimatedTimeoutFramesLeft()

		if framesPenalty < 0 then
			framesPenalty = 0
		end

	end

	local fitness = rightmost - (pool.currentFrame + framesPenalty) / 2

	if rightmost > 3186 then
		fitness = fitness + 1000
	end

	if fitness == 0 then
		fitness = -1
	end

	return fitness
end

function getGenerationPercentage()

	local measured = 0
	local total = 0
	for _,species in pairs(pool.species) do
		for _,genome in pairs(species.genomes) do
			total = total + 1
			if genome.fitness ~= 0 then
				measured = measured + 1
			end
		end
	end

	return math.floor(measured / total * 100)
end

function isRunFinished()
	return isTimeOut() or isDead() 
end

function isTimeOut()
	return timeout + pool.currentFrame / 4 <= 0
end

function getEstimatedTimeoutFramesLeft()
	local time = timeout
	local frame = pool.currentFrame
	local count = 0

	-- TODO better algorithm without loop

	while true do
		time = time - 1
		frame = frame + 1

		if time + frame / 4 <= 0 then
			return count
		else
			count = count + 1
		end
	end
end

function updateTimeout()
	if PlayerX > rightmost then
		rightmost = PlayerX
		timeout = TimeoutConstant
	end

	timeout = timeout - 1
end

function onRestart()
	clearPlayingRecords()
	clearGenerationRecords()
end	

function onNewRecord()
	if SynchronizedPlayback then resetPlaybackFrames() end
	return newRecording();
end

function onNewGeneration()
	if SaveGenerationRecords then 
		writeRecordsBackupFile()
	end

	clearGenerationRecords()
end

function onRecordCompleted(record, generation, species, genome, fitness)

	if CrossFadeOnRestart then
		startScreenCrossFade()
	end

	if SaveGenerationRecords then
		saveGenerationRecord(record, generation, species, genome, fitness)
	end

	addRecordToPlayback(record)
end

function onDraw()
	drawPlayingRecords()
	drawScreenCrossFade()
	drawGUI()
end

function onFrameCompleted(currentRecord, currentFrame)
	recordCurrentFrame(currentRecord)
	updatePlaybackFrame(currentFrame)
	updateScreenCrossFade()
end

function onNewLevel(world, level) 

	emu.print("New level! " .. world .. "-" .. level)

	LevelStartSaveFile = savestate.create()
	savestate.save(LevelStartSaveFile)

end

function onNewLocation(location)

	emu.print("New location! " .. location)

	LocationStartSaveFile = savestate.create()
	savestate.save(LocationStartSaveFile)

	initializePool()

end


-- Main logic

loadGUISprites()
loadCharacterSprites()

gui.register(onDraw)

-- State dependent logic

function tryToStartGame()
	local controller = {}

	controller.start = true
	joypad.set(1, controller)

	waitForFrames(10)

	controller.start = false
	joypad.set(1, controller)

	waitForFrames(10)
end

function evaluateNormalFrame()

	if pool.currentFrame % 5 == 0 then
		evaluateCurrent()
	end

	joypad.set(1, controller)

	updateTimeout()

	pool.currentFrame = pool.currentFrame + 1
	onFrameCompleted(CurrentRecord, pool.currentFrame)

	if isRunFinished() then
		
		local genome = getCurrentGenome()
		local fitness = getTotalFitness()
		
		genome.fitness = fitness

		if fitness > pool.maxFitness then
			pool.maxFitness = fitness
			emu.print("New Max Fitness: " .. math.floor(pool.maxFitness))
			writeGenerationBackupFile()
		end

		emu.print("Gen: " 	.. pool.generation 	..
			"  Species: " 	.. pool.currentSpecies 	..
			"  Genome: " 	.. pool.currentGenome 	..
			"  Fitness: " 	.. fitness)

		if PauseAfterDeath and isDead() then
			waitForFrames(15)
		end

		pool.currentSpecies = 1
		pool.currentGenome = 1

		while fitnessAlreadyMeasured() do
			nextGenome()
		end

		onRecordCompleted(CurrentRecord, pool.generation, pool.currentSpecies, pool.currentGenome, fitness)
		initializeRun()
	end

	runScheduledFunctions()
end

-- Main Game Loop

while true do

	if not isGameStarted() then
		tryToStartGame()
	end

	if not isCutscenePlaying() and isPlayerLoaded() then
		updateGameInfo()
		evaluateNormalFrame()
	end

	emu.frameadvance()
end