game.AddParticles("particles/elevator_particles.pcf")
game.AddParticles("particles/slappy_titfuck_goddamn.pcf")
game.AddParticles("particles/suna_fire.pcf")
AddCSLuaFile("cl_init.lua")
AddCSLuaFile("cl_legs.lua")
AddCSLuaFile("scoreboard/controls/cl_list.lua")
AddCSLuaFile("scoreboard/cl_playerlist.lua")
AddCSLuaFile("scoreboard/cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")
include("sv_download.lua")
include("sv_player.lua")
include("sv_seats.lua")
include("billiards/sv_billiards.lua")
include("billiards/billiards_files.lua")
AddCSLuaFile("billiards/cl_billiards.lua")
include("postprocess/init.lua")
AddCSLuaFile("postprocess/init.lua")

--=====================================================
-- CUSTOMIZABLES
-- range of random time before next floor (in seconds)
GM.IntermissionTime = {45, 60}

GM.RemoveNPCsAfter = 300 -- automatically remove NPCs after 5 minutes (5 * 60)
GM.LobbyName = "elevator_lobby" -- entity name of lobby elevator
GM.IntermissionName = "elevator_main" -- entity name of intermission elevator
GM.EndingName = "elevator_end" -- entity name of end elevator

GM.Floors = {"elevator_1", "elevator_2", "elevator_3", "elevator_4", "elevator_5", "elevator_6", "elevator_7", "elevator_8", "elevator_9", "elevator_10", "elevator_11", "elevator_12", "elevator_13", "elevator_14", "elevator_15", "elevator_16", "elevator_17", "elevator_18", "elevator_19", "elevator_20", "elevator_21", "elevator_22", "elevator_23", "elevator_24", "elevator_25", "elevator_26_top",}

--Apartment hallway
--Creep
--Monochrome room
--Dungeon
--Circles
--Party
--Fiesta time
--Burning House
--gm_apartment
--GMT Suite
--Forest
--Snow City
--Creature
--Robot Factory
--Film Noir
--Elception
--CATS!!!!!!!
--Factory
--Get Smart
--Elevator Void
--Supply Closet
--Concrete Tunnel
--Beach
--Dino
--Space
--Fall
GM.MaxFloorsToPlay = #GM.Floors -- max number of floors to play before the game ends

-- entities that are allowed to be teleported by the elevator
GM.ValidEnts = {"prop_physics", "human_gib"}

-- CONSTANTS
STATE_WAITING = 0 -- waiting for players to get on the elevator
STATE_INTERMISSION = 1 -- in between elevator floors
STATE_FLOOR = 2 -- elevator floor active
STATE_GAMEOVER = 3 -- elevator game over
-- GAMEMODE
GM.State = STATE_WAITING -- game state
GM.Time = 0 -- current time (used for intermission time)
-- VARIABLES
GM.PlayedFloors = {} -- stores list of played floors
GM.CurrentFloor = nil -- entity of current floor
GM.CurrentFloorName = nil -- current floor name
GM.Lobby = nil -- entity of lobby elevator
GM.Intermission = nil -- entity of intermission elevator
GM.Ending = nil -- entity of end elevator
GM.LastSongID = 0 -- last intermission song played
GM.CurrentSongID = 0 -- current intermission song
GM.CurrentSongTime = 0 -- time before the next song
-- NET STRINGS
util.AddNetworkString("Elevator_Sound")
util.AddNetworkString("Elevator_Music")
util.AddNetworkString("Elevator_UpdateNPCName") -- remove later

--=====================================================
--[[
--  Sets the gamemode to waiting and gathers entity data
--]]
function GM:Initalize()
	self.State = STATE_WAITING
end

--[[
--  Gets the entities of the lobby, intermission, and ending floors
--]]
function GM:GatherEntityData()
	self.Lobby = ents.FindByName(self.LobbyName)[1]
	self.Intermission = ents.FindByName(self.IntermissionName)[1]
	self.Ending = ents.FindByName(self.EndingName)[1]
end

--[[
--  Loops through list of floors and checks if they are valid.
--  If not, they are removed from the list of playable floors.
--]]
function GM:ValidateFloors()
	local InvalidFloors = {}

	-- Find invalid floors
	for _, floor in pairs(self.Floors) do
		local floorEnt = ents.FindByName(floor)[1]

		-- Not valid, removing from list
		if not IsValid(floorEnt) or floorEnt:GetClass() ~= "info_elevator_floor" then
			Msg("Floor is invalid: " .. floor, "\n")
			table.insert(InvalidFloors, floor)
		end
	end

	-- Remove invalid floors
	for _, floor in pairs(InvalidFloors) do
		if table.HasValue(self.Floors, floor) then
			local id = table.KeyFromValue(self.Floors, floor)
			table.remove(self.Floors, id)
		end
	end

	-- Update max floors to play
	self.MaxFloorsToPlay = #self.Floors
end

--[[
--  Loops through the entire map and finds custom floors to add to the play list.
--  Note: Custom floors names must start with elevator_custom to be valid.
--]]
function GM:LocateCustomFloors()
	for _, ent in pairs(ents.GetAll()) do
		if IsValid(ent) and ent:GetClass() == "info_elevator_floor" then
			local floor = ent:GetName()

			if string.find(tostring(floor), "elevator_custom") then
				-- Add to table
				if not table.HasValue(self.Floors, floor) then
					table.insert(self.Floors, floor)
				end

				Msg("Custom floor: " .. floor .. " was successfully added!", "\n")
			end
		end
	end

	-- Update max floors to play
	self.MaxFloorsToPlay = #self.Floors
end

--[[
--  Returns if the elevator is valid to play. (ie. all entity data is there)
--]]
function GM:IsElevatorValid()
	return self.Lobby and self.Intermission and self.Ending
end

--[[
--  Returns if the gamemode is active/playing
--]]
function GM:IsPlaying()
	return self.State == STATE_FLOOR or self.State == STATE_INTERMISSION
end

--[[
--  Updates the gamemode:
--		Handles intermission think while intermission is active.
--		Checks if players are still playing, if no - restarts the game.
--]]
function GM:Think()
	-- Update intermission
	if self.State == STATE_INTERMISSION then
		self:IntermissionThink()
	end

	-- Remove NPCs after awhile
	self:NPCRemoveThink()

	-- Check if everyone left
	if self:IsPlaying() then
		if #team.GetPlayers(TEAM_ELEVATOR) == 0 then
			self:Restart()
		end
	end

	-- Check if everyone left
	for _, ply in pairs(team.GetPlayers(TEAM_END)) do
		if IsValid(ply:GetSaveTable().m_hUseEntity) then
			ply.LastPickup = CurTime()
		end
	end
end

--[[
--  Sends a player to the elevator.
--  Starts the gamemode if needed.
--]]
function GM:SendPlayer(ply)
	-- Only alive players
	if not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() then return end

	if not self:IsElevatorValid() then
		-- Gather entity data
		self:GatherEntityData()

		-- If data was invalid...
		if not self:IsElevatorValid() then
			self:PlayerMessage(ply, "Error!", "Something is terribly wrong with the elevator! Make sure you have the gamemode properly installed!")

			return
		end
	end

	-- The game is over, send them to the ending
	if self.State == STATE_GAMEOVER then
		ply:SetTeam(TEAM_END)
		self:PlaySound(ply, SOUND_BELL)
		self:Teleport(ply, self.Lobby, self.Ending)

		return
	end

	-- Only non-elevator players
	if ply:Team() == TEAM_ELEVATOR then return end
	-- Set to elevator player
	ply:SetTeam(TEAM_ELEVATOR)

	-- Determine where to send the player
	-- Start the gamemode
	if self.State == STATE_WAITING then
		self:Start()
		self:Teleport(ply, self.Lobby, self.Intermission)
		-- Send the player to intermission
	elseif self.State == STATE_INTERMISSION then
		self:SendCurrentMusic(ply)
		self:Teleport(ply, self.Lobby, self.Intermission)
	else -- Send the player to the current floor
		if self.CurrentFloor then
			self:Teleport(ply, self.Lobby, self.CurrentFloor)
		else
			self:PlayerMessage(ply, "Error!", "An error occured, please exit the elevator and re-enter.\nIf the error persists, please restart the gamemode.")
		end
	end
end

--[[
--  Starts the gamemode
--]]
function GM:Start()
	self:LocateCustomFloors()
	self:ValidateFloors()
	self:IntermissionStart()
	self:MoveAllEnts(self.Lobby, self.Intermission)
end

--[[
--  Starts a new floor
--]]
function GM:StartFloor(Floor)
	--Msg( "Starting Floor... " .. Floor .. "\n" )
	-- End current floor, if needed
	if self.CurrentFloor then
		self:EndFloor()
	end

	-- Set state
	self.State = STATE_FLOOR
	-- Sets the current floor
	self.CurrentFloorName = Floor
	self.CurrentFloor = ents.FindByName(Floor)[1]
	-- Start current floor
	self.CurrentFloor:Start()
	-- Move all players/ents
	self:MoveAllPlayers(self.Intermission, self.CurrentFloor)
	self:MoveAllEnts(self.Intermission, self.CurrentFloor)
	-- Effects
	self:PlaySoundAll(SOUND_BELL)
	self:SetFloorEffects(Floor, true)
end

--[[
--  Ends the current floor
--]]
function GM:EndFloor()
	if not self.CurrentFloor then return end
	--Msg( "Ending Floor... " .. self.CurrentFloor .. "\n" )
	-- End current floor
	self.CurrentFloor:End()
	-- Insert into played floors
	table.insert(self.PlayedFloors, self.CurrentFloorName)
	-- Move all players/ents
	self:MoveAllPlayers(self.CurrentFloor, self.Intermission)
	self:MoveAllEnts(self.CurrentFloor, self.Intermission)
	-- Effects
	self:SetFloorEffects(self.CurrentFloorName, false)
	-- Remove reference to current floor
	self.CurrentFloor = nil
	self.CurrentFloorName = nil
	-- Start intermission
	self:IntermissionStart()
end

--[[
--  Starts intermission (between floors)
--]]
function GM:IntermissionStart()
	--Msg( "Intermission start\n" )
	-- Set delay between floors
	self.Time = CurTime() + math.random(self.IntermissionTime[1], self.IntermissionTime[2])
	-- Set state
	self.State = STATE_INTERMISSION
	-- Set and play new song
	self:SetNewSong()
	self:StartMusicAll()
	-- Start up sound
	self:PlaySoundAll(SOUND_START)
end

--[[
--  Handles intermission timer and changes intermission song tracks when needed
--]]
function GM:IntermissionThink()
	-- Time is up, end intermission
	if CurTime() > self.Time then
		self:IntermissionEnd()

		return
	end

	-- Song ended, start new song
	if CurTime() > self.CurrentSongTime then
		self:SetNewSong()
		self:StartMusicAll()
	end
end

--[[
--  Ends intermission (between floors) and starts a new floor
--]]
function GM:IntermissionEnd()
	--Msg( "Intermission end\n" )
	-- Stop music and play stop sound
	self:StopMusicAll()
	self:PlaySoundAll(SOUND_STOP)

	-- Determine if the game should end
	if #self.PlayedFloors >= self.MaxFloorsToPlay then
		self:End()

		return
	end

	-- Start a new floor
	self:StartFloor(self:GetNextFloor())
end

--[[
--  Game is over, they went through max floors.
--  Sends them to the ending floor.
--]]
function GM:End()
	--Msg( "Ending game..." )
	-- Move to awesome ending floor and stuff
	self.State = STATE_GAMEOVER
	-- Move players/ents
	self:MoveAllPlayers(self.Intermission, self.Ending)
	self:MoveAllEnts(self.Intermission, self.Ending)
	-- Clear floor references
	self.CurrentFloor = nil
	self.CurrentFloorName = nil
	-- Handle sound
	self:PlaySoundAll(SOUND_BELL)
	self:StopMusicAll()

	-- Open ending floor
	if self.Ending then
		self.Ending:Start()
	end

	-- Set to winners
	for _, ply in pairs(team.GetPlayers(TEAM_ELEVATOR)) do
		ply:SetTeam(TEAM_END)
	end
end

--[[
--  Restarts the entire gamemode and map
--]]
function GM:Restart()
	self.State = STATE_WAITING
	self.CurrentFloor = nil
	self.CurrentFloorName = nil
	self.PlayedFloors = {}
	self:StopMusicAll()
	--[[ for _, ply in pairs( player.GetAll() ) do
		self:PlayerMessage( ply, "Elevator", "The game has been restarted!" )
	end ]]
end

--[[
--  Hard resets the map.  This is very dangerous and can crash the game.
--]]
function GM:HardRestart()
	game.CleanUpMap(true, {"npc_citizen", "npc_monk", "billiard_ball", "billiard_cue", "billiard_static", "billiard_table", "elevator_billiards", "prop_vehicle_prisoner_pod", "slotmachine", "slotmachine_light", "elevator_blender", "elevator_drink", "elevator_ingredient", "trigger_elevator", "info_elevator_floor", "logic_relay", "logic_timer", "point_template"})

	self.Lobby = nil
	self.Intermission = nil
	self.Ending = nil
	self:GatherEntityData()
end

--[[
--  Recursively gets a random next floor (filters out played floors)
--]]
function GM:GetNextFloor()
	local nextFloor = table.Random(self.Floors)
	if table.HasValue(self.PlayedFloors, nextFloor) then return self:GetNextFloor() end

	return nextFloor
end

--[[
--  Recursively gets a new intermission song that isn't the same as the last one
--]]
function GM:GetNextSong()
	local song = math.random(#self.Music)
	if song == self.LastSongID then return self:GetNextSong() end

	return song
end

--[[
--  Sets a new intermission song
--]]
function GM:SetNewSong()
	self.LastSongID = self.CurrentSongID
	self.CurrentSongID = self:GetNextSong()
	self.CurrentSongTime = CurTime() + self.Music[self.CurrentSongID][2]
end

--[[
--  Moves all elevator players from one floor to another
--]]
function GM:MoveAllPlayers(fromFloor, toFloor)
	if not IsValid(fromFloor) or not IsValid(toFloor) then return end

	for _, ply in pairs(team.GetPlayers(TEAM_ELEVATOR)) do
		self:Teleport(ply, fromFloor, toFloor)
	end
end

--[[*
 * Moves all entities from one floor to another
 ]]
function GM:MoveAllEnts(fromFloor, toFloor)
	if not IsValid(fromFloor) or not IsValid(toFloor) then return end
	--Msg( "Teleporting ents..\n")
	local pos = fromFloor:GetPos() + Vector(0, 0, ELEVATOR_WIDTH / 2)

	-- Get all entities from point
	for _, ent in pairs(ents.FindInSphere(pos, ELEVATOR_WIDTH / 2)) do
		-- Teleport only valid entities
		if table.HasValue(self.ValidEnts, ent:GetClass()) or ent:IsNPC() then
			self:Teleport(ent, fromFloor, toFloor)
		end
	end
end

--[[
--  Teleports an entity from one floor to a new floor
--]]
function GM:Teleport(ent, fromFloor, toFloor)
	if not IsValid(ent) or not IsValid(fromFloor) or not IsValid(toFloor) then return end
	-- Gather position data
	local pos = ent:GetPos()
	local old = fromFloor:GetPos()
	local new = toFloor:GetPos()
	-- Offset position
	local vec = new + pos - old

	-- Handle if entity is player
	if ent:IsPlayer() then
		-- The clamps use the clamps!
		local dist = pos:DistToSqr(old)

		-- NO LEAVING, EVER
		-- ELEVATOR_WIDTH ^ 2
		if dist > 36864 then
			vec = new
		end

		ent:SetPos(vec)
		ent.DesiredPosition = vec -- required hack due to SetPos sometimes failing
	else
		-- store last sequence
		if ent:IsNPC() then
			ent.LastSequence = ent:GetSequence()
		end

		ent:SetPos(vec)

		-- set sequence
		if ent.LastSequence then
			ent:ResetSequence(ent.LastSequence)
			--[[umsg.Start( "Elevator_SetNPCSequence", ply )
				umsg.Entity( ent )
				umsg.Char( ent.LastSequence )
			umsg.End()]]
		end
	end
end

--[[
--  Hooks into move to set the origin of the player (hack to fix broken SetPos)
--]]
hook.Add("Move", "MoveElevator", function(ply, move)
	if ply.DesiredPosition ~= nil then
		ply.OldVel = ply:GetVelocity()
		move:SetOrigin(ply.DesiredPosition)
		ply:SetLocalVelocity(ply.OldVel)
		ply.OldVel = nil
		ply.DesiredPosition = nil
	end
end)

--[[
--  Sends current music to all elevator players
--]]
function GM:StartMusicAll()
	self:SendCurrentMusic(team.GetPlayers(TEAM_ELEVATOR))
end

--[[
--  Ends the current music to all elevator players
--]]
function GM:StopMusicAll()
	self:EndCurrentMusic(team.GetPlayers(TEAM_ELEVATOR))
end

--[[
--  Plays a sound to all elevator players
--]]
function GM:PlaySoundAll(sound)
	self:PlaySound(team.GetPlayers(TEAM_ELEVATOR), sound)
end

--[[
--  Plays a sound for a player
--]]
function GM:PlaySound(ply, sound)
	net.Start("Elevator_Sound")
	net.WriteUInt(sound, 3)
	net.Send(ply)
end

--[[
--  Sends the current music to a player
--]]
function GM:SendCurrentMusic(ply)
	net.Start("Elevator_Music")
	net.WriteUInt(self.CurrentSongID, 5)
	net.Send(ply)
end

--[[
--  Ends the current music of a player
--]]
function GM:EndCurrentMusic(ply)
	net.Start("Elevator_Music")
	net.WriteUInt(0, 5)
	net.Send(ply)
end

--[[
--  Sets up NPCs, disabling their collision and setting their names.
--]]
function GM:OnEntityCreated(ent)
	if not IsValid(ent) or not ent:IsNPC() then return end
	-- Disable player collision
	ent:SetCollisionGroup(COLLISION_GROUP_DEBRIS_TRIGGER)

	-- Give them a name
	-- we need to delay this a bit
	timer.Simple(.1, function()
		self:SetNPCName(ent)
	end)

	-- HUSH THE PREACHER
	if ent:GetClass() == "npc_monk" then
		ent:AddRelationship("player D_NU 999")
	end
end

--[[
--  Sends a player all the NPC names (if they connected late)
--]]
function GM:SendNPCNames(ply)
	if not IsValid(ply) or not ply:IsPlayer() then return end

	for _, ent in pairs(ents.GetAll()) do
		if IsValid(ent) and ent:IsNPC() and ent.RealNameID then
			net.Start("Elevator_UpdateNPCName")
			net.WriteEntity(ent)
			net.WriteUInt(ent.RealNameID, 6)
			net.Send(ply)
		end
	end
end

--[[
--  Sets and sends an NPC's name
--]]
-- replace with NWString or NW2String later
function GM:SetNPCName(ent)
	if not IsValid(ent) or not ent:IsNPC() then return end
	-- store server side
	ent.RealNameID = self:GetRandomNPCNameID(ent:GetModel())
	-- send to all clients
	net.Start("Elevator_UpdateNPCName")
	net.WriteEntity(ent)
	net.WriteUInt(ent.RealNameID, 6)
	net.Broadcast()
end

--[[
--  Finds and returns a random NPC on the current floor
--]]
function GM:GetRandomElevatorNPC()
	if not GAMEMODE.CurrentFloor then return nil end
	local pos = GAMEMODE.CurrentFloor:GetPos() + Vector(0, 0, ELEVATOR_WIDTH / 2) --Get the current elevator location

	--Loop through all the entities in the elevator
	for _, ent in RandomPairs(ents.FindInSphere(pos, ELEVATOR_WIDTH / 2)) do
		if IsValid(ent) and ent:IsNPC() then return ent end
	end

	return nil
end

--[[
--  Handles any lua events/effects that occur on a specific floor.
--]]
function GM:SetFloorEffects(FloorName, bEnable)
	-- Monochrome floor
	if FloorName == "elevator_3" then
		if bEnable then
			for _, ply in pairs(team.GetPlayers(TEAM_ELEVATOR)) do
				PostEvent(ply, "pBWOn")
			end
		else
			for _, ply in pairs(team.GetPlayers(TEAM_ELEVATOR)) do
				PostEvent(ply, "pBWOff")
			end
		end
	end

	-- The dungeon floor
	if FloorName == "elevator_4" then
		local ent = ents.FindByName("skeleton")[1]

		if IsValid(ent) and bEnable then
			ent:SetSkin(math.random(1, 4)) -- set random skin on skeleton model
		end
	end

	-- The party floor
	if FloorName == "elevator_6" then
		if bEnable then
			local function PartyPeopleTimer()
				local partiers = ents.FindByName("partypeople")
				if #partiers == 0 then return end
				local npc = partiers[math.random(1, #partiers)]
				npc:EmitSound(self:RandomDefinedSound(SOUNDS_CHEER), 100, 100)
				timer.Adjust("CitizenCheering", math.random(1, 3), 0, PartyPeopleTimer)
			end

			-- Partiers make cheer noises
			timer.Create("CitizenCheering", math.random(1, 3), 0, PartyPeopleTimer)
			timer.Start("CitizenCheering")
		else
			timer.Remove("CitizenCheering")
		end
	end

	-- The snow city floor
	if FloorName == "elevator_12" then
		if bEnable then
			-- Random player coughing
			timer.Create("RandomSnifflesCough", 5, 0, function()
				for _, ply in pairs(team.GetPlayers(TEAM_ELEVATOR)) do
					local watch = ply:GetWatch()

					if IsValid(watch) then
						watch.iNextCough = CurTime() + math.random(2, 4)
					end
				end
			end)

			timer.Start("RandomSnifflesCough")
		else
			timer.Remove("RandomSnifflesCough")
		end
	end

	-- The void floor
	if FloorName == "elevator_20" then
		self:SetSpinPlayersWatches(bEnable)
		self:SetPlayerRandomNames(bEnable)
	end

	-- The space floor
	if FloorName == "elevator_25" then
		if bEnable then end		 --[[timer.Simple(5, function()
				-- kill off a random npc to be dragged into space (WIP)
				local npc = self:GetRandomElevatorNPC()
				if IsValid(npc) then
					local dmginfo = DamageInfo()
						dmginfo:SetDamage(100)
						dmginfo:SetDamageType(DMG_GENERIC)
						dmginfo:SetInflictor(npc)
						dmginfo:SetAttacker(npc)
						
					npc:TakeDamageInfo(dmginfo)
				end
			end)]]
	end

	-- The fall floor
	if FloorName == "elevator_26_top" then
		-- Insert top floor to played
		table.insert(self.PlayedFloors, "elevator_26_top")
		-- Change position to bottom
		self.CurrentFloorName = "elevator_26_bottom"
		self.CurrentFloor = ents.FindByName(self.CurrentFloorName)[1]
	end

	-- Get smart floor
	-- Force end it after 35 seconds
	if FloorName == "elevator_19" then
		if bEnable then
			timer.Create("ForceRemoveGetSmart", 35, 1, function()
				self.CurrentFloor:End()
			end)

			timer.Start("ForceRemoveGetSmart")
		else
			timer.Remove("ForceRemoveGetSmart")
		end
	end
end

--[[
--  Disables/enables names and legs
--]]
function GM:SetSleepTime(bSleep)
	for _, ply in pairs(team.GetPlayers(TEAM_ELEVATOR)) do
		umsg.Start("Elevator_ToggleSleep", ply)
		umsg.Bool(bSleep)
		umsg.Bool(bSleep)
		umsg.End()
	end
end

--[[
--  Spins the players' watches
--]]
function GM:SetSpinPlayersWatches(bSpin)
	for _, ply in pairs(team.GetPlayers(TEAM_ELEVATOR)) do
		local watch = ply:GetWatch()

		if IsValid(watch) then
			watch:SetSpinning(bSpin)
		end
	end
end

--[[
-- Sets the NPCs to cycle through all names
--]]
function GM:SetPlayerRandomNames(bEnable) -- fix later
	for _, ply in pairs(team.GetPlayers(TEAM_ELEVATOR)) do
		umsg.Start("Elevator_RandomNames", ply)
		umsg.Bool(bEnable)
		umsg.End()
	end
end

--[[
--  Remove NPCs on end floor after 5 minutes
--]]
function GM:NPCRemoveThink()
	if not self:IsElevatorValid() then return end

	-- Check for removal of NPCs
	for _, ent in pairs(ents.GetAll()) do
		if IsValid(ent) and ent:IsNPC() then
			local dist = self.Ending:GetPos():Distance(ent:GetPos())

			if not ent.RemoveDelay and dist <= (ELEVATOR_WIDTH / 2) then
				-- Tag NPC for removal after 5 minutes
				ent.RemoveDelay = CurTime() + self.RemoveNPCsAfter
			end

			if ent.RemoveDelay and CurTime() > ent.RemoveDelay then
				self:RemoveNPC(ent)
			end
		end
	end
end

--[[
--  Removes an NPC
--]]
function GM:RemoveNPC(npc)
	local dmginfo = DamageInfo()
	dmginfo:SetDamage(100)
	dmginfo:SetDamageType(DMG_DISSOLVE)
	dmginfo:SetInflictor(npc)
	dmginfo:SetAttacker(npc)
	npc:TakeDamageInfo(dmginfo)
end

--[[
--  Disable fall damage and player damage
--]]
function GM:EntityTakeDamage(ent, dmginfo)
	if dmginfo:IsFallDamage() then
		dmginfo:ScaleDamage(0.0)
	end

	if ent:IsPlayer() then
		dmginfo:ScaleDamage(0.0)
	end
end
