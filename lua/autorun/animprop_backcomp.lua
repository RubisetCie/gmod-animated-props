//This file handles backwards compatibility for old animated prop entities that have all been replaced by prop_animated

AddCSLuaFile()

local IsValid = IsValid
local conversion_funcs = {}
conversion_funcs = {
	animprop_generic = function(ent, ply)
		local par = ent:GetParent()
		if !IsValid(par) or !ent.IsPhysified or par:GetClass() != "animprop_generic_physmodel" or par.ConfirmationID != ent.ConfirmationID then par = nil end
		local animprop = ConvertEntityToAnimprop(ent, ply, true, false)
		if IsValid(animprop) then 
			//Convert animation settings
			animprop:SetChannel1Sequence(animprop:LookupSequence(ent.MyAnim)) //sequence is stored as name string instead of id number
			animprop:SetChannel1Speed(ent.MyPlaybackRate)
			animprop:SetChannel1Pause(ent.IsPaused)
			animprop:SetChannel1PauseFrame(ent.PauseFrame)

			//Convert the gesture, if applicable
			if ent.EntityMods and ent.EntityMods.GesturizerEntity and ent.EntityMods.GesturizerEntity.AnimName then //TODO: does it work this way for a spawned entity?
				animprop:SetChannel2Sequence(animprop:LookupSequence(ent.EntityMods.GesturizerEntity.AnimName)) //sequence is stored as name string instead of id number
				ent.EntityMods.GesturizerEntity = nil
				duplicator.ClearEntityModifier(animprop, "GesturizerEntity")
			end

			//Convert pose parameters, if applicable
			animprop.PoseParams = {} //create a new poseparams table, and use either the duped values, or if those are nil, the hard-coded default values from the old entity
			for i = 0, animprop:GetNumPoseParameters() - 1 do
				local name = animprop:GetPoseParameterName(i)

				local default = animprop:GetPoseParameter(name)
				if name == "move_scale" then
					default = 1
				elseif name == "aim_pitch" then
					default = ent.StoredAimPitch or 0
				elseif name == "aim_yaw" then
					default = ent.StoredAimYaw or 0
				elseif name == "body_pitch" then
					default = ent.StoredAimPitch or 0
				elseif name == "body_yaw" then
					default = ent.StoredAimYaw or 0
				elseif name == "move_x" then
					default = ent.StoredMoveX or 1
				elseif name == "move_y" then
					default = ent.StoredMoveY or 0
				elseif name == "move_yaw" then
					default = ent.StoredMoveYaw or 0
				end
				animprop.PoseParams[i] = default
			end

			//Physics
			if par then
				animprop:SetPhysicsMode(0) //use prop physics (or box physics for non-props)
				animprop:UpdateAnimpropPhysics() //update the physics immediately so we can freeze it
				//Freeze the animprop if the old ent's physmodel was frozen
				if IsValid(animprop:GetPhysicsObject()) and IsValid(par:GetPhysicsObject()) and !par:GetPhysicsObject():IsMotionEnabled() then
					animprop:GetPhysicsObject():EnableMotion(false)
				end
				//The old ent gives animprops physics by parenting them to a separate physmodel entity.
				//Grab the constraints from the parent and transfer them over to the new prop.
				for k, const in pairs (table.Copy(constraint.GetTable(par))) do
					if const.Entity then
						//If any of the values in the constraint table are the physmodel, switch them over to the animprop
						for key, val in pairs (const) do
							if type(val) == "Entity" then
								if key == par then const[key] = animprop end
								//MsgN(key, ": ", val)
							end
						end

						local entstab = {}

						//Also switch over any instances of physmodel to animprop inside the entity subtable
						for tabnum, tab in pairs (const.Entity) do
							if tab.Entity == par then
								const.Entity[tabnum].Entity = animprop
								const.Entity[tabnum].Index = animprop:EntIndex()	
							end
							entstab[const.Entity[tabnum].Index] = const.Entity[tabnum].Entity
						end

						duplicator.CreateConstraintFromTable(table.Copy(const), table.Copy(entstab))
					end
				end
			else
				animprop:SetPhysicsMode(2) //use effect physics
				animprop:UpdateAnimpropPhysics() //also necessary here to fix an issue where some props still have full-sized physboxes as effects
				animprop:SetCollisionGroup(COLLISION_GROUP_WORLD) //make sure we don't push anything away now that we're physical
				local phys = animprop:GetPhysicsObject()
				if IsValid(phys) then phys:EnableMotion(false) end //also make sure we don't get pushed away by the world if we're flush against it
			end
		end
		return IsValid(animprop)
	end,
	//animprop_generic_physmodel doesn't need a func here, it's handled by its child animprop
	//"Premade" animprops were originally made because it wasn't possible to add their particle effects or multiple models yourself at the time. 
	//Nowadays, though, we have Particle Effects+/Adv. Particle Controller for particle effects, and Advanced Bonemerge for multiple models,
	//so they really aren't necessary any more. Spawn regular animprops modified with those tools instead.
	animprop_spawnacarrier = function(ent, ply)
		local animprop = ConvertEntityToAnimprop(ent, ply, true, false)
		if IsValid(animprop) then
			//Create a second animprop for the detail parts
			local dummy = ents.Create("prop_dynamic")
			if !IsValid(dummy) then return end
			dummy:SetPos(animprop:GetPos())
			dummy:SetAngles(animprop:GetAngles())
			dummy:SetModel("models/bots/boss_bot/carrier_parts.mdl")
			local animprop2 = ConvertEntityToAnimprop(dummy, ply, true, true)
			if !IsValid(animprop2) then dummy:Remove() return end
			animprop2:SetChannel1Sequence(animprop2:LookupSequence("radar_idles"))

			if CreateAdvBonemergeEntity then
				//Attach the parts with adv bonemerge tool
				animprop2 = CreateAdvBonemergeEntity(animprop2, animprop, ply, false, false, true)
				constraint.AdvBoneMerge(animprop, animprop2, ply)
				animprop2.AdvBone_BoneInfo_IsDefault = false
			else
				//If the adv bonemerge addon isn't installed, then weld the parts as a fallback
				animprop2:SetPhysicsMode(2) //use effect physics
				animprop2:UpdateAnimpropPhysics() //update the physics immediately so we can weld it
				animprop2:SetCollisionGroup(COLLISION_GROUP_WORLD) //make sure we don't push anything away now that we're physical
				local phys = animprop2:GetPhysicsObject()
				//if IsValid(phys) then phys:EnableMotion(false) end //also make sure we don't get pushed away by the world if we're flush against it
				animprop2:SetPos(animprop:GetPos())
				animprop2:SetAngles(animprop:GetAngles())
				constraint.Weld(animprop, animprop2, 0, 0, 0, true, false)
			end
		end
		return IsValid(animprop)
	end,
	_animprop_spawnteleporter_ = function(ent, ply, team, lv, entrance)
		local animprop = ConvertEntityToAnimprop(ent, ply, true, false)
		if IsValid(animprop) then
			local phys = animprop:GetPhysicsObject()
			if IsValid(phys) then phys:EnableMotion(false) end

			//Add particle effects
			if team then
				team = "blue"
			else
				team = "red"
			end
			lv = tostring(lv)
			if entrance then
				entrance = "entrance"
			else
				entrance = "exit"
			end
			if PEPlus_SpawnParticle then
				//Attach the particles with Particle Effects+

				//Charged effect
				local p = PEPlus_SpawnParticle(ply, animprop:GetPos(), "teleporter_" .. team .. "_charged_level" .. lv, "particles/teleport_status.pcf", "tf", true)
				if IsValid(p) then
					for k, v in pairs (p.ParticleInfo) do
						if v.ent then
							p:AttachToEntity(animprop, k, 0, ply, false)
						end
					end
				end

				//Direction effect
				local p = PEPlus_SpawnParticle(ply, animprop:GetPos(), "teleporter_" .. team .. "_" .. entrance .. "_level" .. lv, "particles/teleport_status.pcf", "tf", true)
				if IsValid(p) then
					for k, v in pairs (p.ParticleInfo) do
						if v.ent then
							p:AttachToEntity(animprop, k, 0, ply, false)
						end
					end
				end

				//Arm effect 1 (apparently charged teleporters have these as well https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/game/client/tf/c_obj_teleporter.cpp#L96-L129)
				local p = PEPlus_SpawnParticle(ply, animprop:GetPos(), "teleporter_arms_circle_" .. team, "particles/teleport_status.pcf", "tf", true)
				if IsValid(p) then
					for k, v in pairs (p.ParticleInfo) do
						if v.ent then
							p:AttachToEntity(animprop, k, 1, ply, false)
						end
					end
				end

				//Arm effect 2
				local p = PEPlus_SpawnParticle(ply, animprop:GetPos(), "teleporter_arms_circle_" .. team, "particles/teleport_status.pcf", "tf", true)
				if IsValid(p) then
					for k, v in pairs (p.ParticleInfo) do
						if v.ent then
							p:AttachToEntity(animprop, k, 3, ply, false)
						end
					end
				end
			elseif AttachParticleControllerNormal then
				//Attach the particles with old Adv. Particle Controller as a fallback
				local genericparticletable = {
					RepeatRate = 0,
					RepeatSafety = 1,

					Toggle = 1,
					StartOn = 1,
					NumpadKey = 0,

					UtilEffectInfo = Vector(1,1,1),
					ColorInfo = Color(1,1,1,1)
				}

				//Charged effect
				local tab = table.Copy(genericparticletable)
				tab.EffectName = "teleporter_" .. team .. "_charged_level" .. lv
				tab.AttachNum = 0
				AttachParticleControllerNormal(ply, animprop, {NewTable = tab})

				//Direction effect
				local tab = table.Copy(genericparticletable)
				tab.EffectName = "teleporter_" .. team .. "_" .. entrance .. "_level" .. lv
				tab.AttachNum = 0
				AttachParticleControllerNormal(ply, animprop, {NewTable = tab})

				//Arm effect 1
				local tab = table.Copy(genericparticletable)
				tab.EffectName = "teleporter_arms_circle_" .. team
				tab.AttachNum = 1
				AttachParticleControllerNormal(ply, animprop, {NewTable = tab})

				//Arm effect 2
				local tab = table.Copy(genericparticletable)
				tab.EffectName = "teleporter_arms_circle_" .. team
				tab.AttachNum = 3
				AttachParticleControllerNormal(ply, animprop, {NewTable = tab})
			end
		end
		return IsValid(animprop)
	end,
	animprop_spawnentrance_blue = function(ent, ply) return conversion_funcs["_animprop_spawnteleporter_"](ent, ply, true, 1, true) end,
	animprop_spawnentrance_blue3 = function(ent, ply) return conversion_funcs["_animprop_spawnteleporter_"](ent, ply, true, 3, true) end,
	animprop_spawnentrance_red = function(ent, ply) return conversion_funcs["_animprop_spawnteleporter_"](ent, ply, false, 1, true) end,
	animprop_spawnentrance_red3 = function(ent, ply) return conversion_funcs["_animprop_spawnteleporter_"](ent, ply, false, 3, true) end,
	animprop_spawnexit_blue = function(ent, ply) return conversion_funcs["_animprop_spawnteleporter_"](ent, ply, true, 1, false) end,
	animprop_spawnexit_blue3 = function(ent, ply) return conversion_funcs["_animprop_spawnteleporter_"](ent, ply, true, 3, false) end,
	animprop_spawnexit_red = function(ent, ply) return conversion_funcs["_animprop_spawnteleporter_"](ent, ply, false, 1, false) end,
	animprop_spawnexit_red3 = function(ent, ply) return conversion_funcs["_animprop_spawnteleporter_"](ent, ply, false, 3, false) end,
	_animprop_spawnminisentry_ = function(ent, ply, team)
		local animprop = ConvertEntityToAnimprop(ent, ply, true, false)
		if IsValid(animprop) then
			local phys = animprop:GetPhysicsObject()
			if IsValid(phys) then phys:EnableMotion(false) end

			//Add particle effects
			if team then
				team = ""
			else
				team = "_red"
			end
			if PEPlus_SpawnParticle then
				//Attach the particles with Particle Effects+
				//Light effect
				local p = PEPlus_SpawnParticle(ply, animprop:GetPos(), "cart_flashinglight" .. team, "particles/flag_particles.pcf", "tf", true)
				if IsValid(p) then
					for k, v in pairs (p.ParticleInfo) do
						if v.ent then
							p:AttachToEntity(animprop, k, 3, ply, false)
						end
					end
				end
			elseif AttachParticleControllerNormal then
				//Attach the particles with old Adv. Particle Controller as a fallback
				//Light effect
				AttachParticleControllerNormal(ply, animprop, {NewTable = {
					EffectName = "cart_flashinglight" .. team,
					AttachNum = 3,

					RepeatRate = 0,
					RepeatSafety = 1,

					Toggle = 1,
					StartOn = 1,
					NumpadKey = 0,

					UtilEffectInfo = Vector(1,1,1),
					ColorInfo = Color(1,1,1,1)
				}})
			end
		end
		return IsValid(animprop)
	end,
	animprop_spawnminisentry_blue = function(ent, ply) return conversion_funcs["_animprop_spawnminisentry_"](ent, ply, true) end,
	animprop_spawnminisentry_red = function(ent, ply) return conversion_funcs["_animprop_spawnminisentry_"](ent, ply, false) end,
	_animprop_spawntank_ = function(ent, ply, treadseq, bombseq)
		local par = ent:GetParent()
		if !IsValid(par) or !ent.IsPhysified or par:GetClass() != "animprop_generic_physmodel" or par.ConfirmationID != ent.ConfirmationID then par = nil end
		local animprop = ConvertEntityToAnimprop(ent, ply, true, false)
		if IsValid(animprop) then
			//Create more animprops for the detail parts
			local function CreateDetailAnimprop(model, seqstr, fallbackpos)
				local dummy = ents.Create("prop_dynamic")
				if !IsValid(dummy) then return end
				dummy:SetPos(animprop:GetPos())
				dummy:SetAngles(animprop:GetAngles())
				dummy:SetModel(model)
				local animprop2 = ConvertEntityToAnimprop(dummy, ply, true, true)
				if !IsValid(animprop2) then dummy:Remove() return end
				animprop2:SetChannel1Sequence(animprop2:LookupSequence(seqstr))

				if CreateAdvBonemergeEntity then
					//Attach the parts with adv bonemerge tool
					//animprop2.IsAdvBonemerged = true
					animprop2 = CreateAdvBonemergeEntity(animprop2, animprop, ply, false, false, true)
					//MsgN(animprop2.IsAdvBonemerged)
					constraint.AdvBoneMerge(animprop, animprop2, ply)
					animprop2.AdvBone_BoneInfo_IsDefault = false
					animprop2:UpdateAnimpropPhysics()
				else
					//If the adv bonemerge addon isn't installed, then weld the parts as a fallback
					animprop2:SetPhysicsMode(2) //use effect physics
					animprop2:UpdateAnimpropPhysics() //update the physics immediately so we can weld it
					animprop2:SetCollisionGroup(COLLISION_GROUP_WORLD) //make sure we don't push anything away now that we're physical
					local phys = animprop2:GetPhysicsObject()
					//if IsValid(phys) then phys:EnableMotion(false) end //also make sure we don't get pushed away by the world if we're flush against it
					animprop2:SetPos(LocalToWorld(fallbackpos, Angle(), animprop:GetPos(), animprop:GetAngles()))
					animprop2:SetAngles(animprop:GetAngles())
					constraint.Weld(animprop, animprop2, 0, 0, 0, true, false)
				end
			end
			CreateDetailAnimprop("models/bots/boss_bot/bomb_mechanism.mdl", bombseq, vector_origin)
			CreateDetailAnimprop("models/bots/boss_bot/tank_track_l.mdl", treadseq, Vector(0,56,0))
			CreateDetailAnimprop("models/bots/boss_bot/tank_track_r.mdl", treadseq, Vector(0,-56,0))

			//Physics; do this after CreateDetailAnimprop to prevent weird physics interaction
			if par then
				//animprop:SetPhysicsMode(0) //use prop physics (or box physics for non-props)
				//animprop:UpdateAnimpropPhysics() //update the physics immediately so we can freeze it
				//Freeze the animprop if the old ent's physmodel was frozen
				if IsValid(animprop:GetPhysicsObject()) and IsValid(par:GetPhysicsObject()) and !par:GetPhysicsObject():IsMotionEnabled() then
					animprop:GetPhysicsObject():EnableMotion(false)
				end
				//The old ent gives animprops physics by parenting them to a separate physmodel entity.
				//Grab the constraints from the parent and transfer them over to the new prop.
				for k, const in pairs (table.Copy(constraint.GetTable(par))) do
					if const.Entity then
						//If any of the values in the constraint table are the physmodel, switch them over to the animprop
						for key, val in pairs (const) do
							if type(val) == "Entity" then
								if key == par then const[key] = animprop end
							end
						end

						local entstab = {}

						//Also switch over any instances of physmodel to animprop inside the entity subtable
						for tabnum, tab in pairs (const.Entity) do
							if tab.Entity == par then
								const.Entity[tabnum].Entity = animprop
								const.Entity[tabnum].Index = animprop:EntIndex()
							end
							entstab[const.Entity[tabnum].Index] = const.Entity[tabnum].Entity
						end

						duplicator.CreateConstraintFromTable(table.Copy(const), table.Copy(entstab))
					end
				end
			end
		end
		return IsValid(animprop)
	end,
	animprop_spawntank = function(ent, ply) return conversion_funcs["_animprop_spawntank_"](ent, ply, "ref", "ref") end,
	animprop_spawntank_deploy = function(ent, ply) return conversion_funcs["_animprop_spawntank_"](ent, ply, "ref", "deploy") end,
	animprop_spawntank_moving = function(ent, ply) return conversion_funcs["_animprop_spawntank_"](ent, ply, "forward", "ref") end,
}

local function UpdateOldProp(ent, ply)
	if CLIENT then return end
	if !IsValid(ent) then return nil end
	if conversion_funcs[ent:GetClass()] then return conversion_funcs[ent:GetClass()](ent, ply) end
end

properties.Add("animprop_backcomp", {
	MenuLabel = "Convert old Animated Prop to new addon",
	Order = 1599,
	PrependSpacer = false,
	MenuIcon = "icon16/film_add.png",

	Filter = function(self, ent, ply)

		if !IsValid(ent) then return false end
		if !gamemode.Call("CanProperty", ply, "animprop_backcomp", ent) then return false end

		if conversion_funcs[ent:GetClass()] then
			return true
		else
			local function CheckForChildProps(ent2)
				for _, v in pairs (ent2:GetChildren()) do
					if conversion_funcs[v:GetClass()] then
						return true
					else
						local val = CheckForChildProps(v)
						if val then return val end
					end
				end
			end
			return CheckForChildProps(ent)
		end

	end,

	Action = function(self, ent)

		self:MsgStart()
			net.WriteEntity(ent)
		self:MsgEnd()

	end,

	Receive = function(self, length, ply)

		local ent = net.ReadEntity()
		if !IsValid(ent) or !IsValid(ply) or !properties.CanBeTargeted(ent, ply) or !self:Filter(ent, ply) then return end

		local results = {}
		local result = UpdateOldProp(ent, ply)
		if isbool(result) then
			results[result] = (results[result] or 0) + 1
		else
			local function CheckForChildProps(ent2)
				for _, v in pairs (ent2:GetChildren()) do
					local result = UpdateOldProp(v, ply)
					if isbool(result) then
						results[result] = (results[result] or 0) + 1
					else
						CheckForChildProps(v)
					end
				end
			end
			CheckForChildProps(ent)
		end
		//Show on-screen notifications for all props we converted or failed to convert
		ply:SendLua("surface.PlaySound('common/wpn_select.wav')")
		if results[true] then
			MsgN("Successfully converted " .. results[true] .. " prop(s)!")
			ply:SendLua("GAMEMODE:AddNotify('Successfully converted " .. results[true] .. " prop(s)!', NOTIFY_GENERIC, 4)")
			ply:SendLua("surface.PlaySound('ambient/water/drip" .. math.random(1, 4) .. ".wav')")
		end
		if results[false] then
			MsgN("Failed to convert " .. results[false] .. " prop(s)!")
			ply:SendLua("GAMEMODE:AddNotify('Failed to convert " .. results[false] .. " prop(s)!', NOTIFY_ERROR, 4)")
			ply:SendLua("surface.PlaySound('buttons/button11.wav')")
		end

	end
})

if SERVER then
	concommand.Add("sv_animprop_backcomp_convert_all", function(ply, cmd, args)
		//Only let server owners run this command because it converts everyone's spawned ents
		if !game.SinglePlayer() and IsValid(ply) and !ply:IsListenServerHost() and !ply:IsSuperAdmin() then
			return false
		end
		local results = {}
		for _, ent in pairs (ents.GetAll()) do
			local result = UpdateOldProp(ent, ply)
			if isbool(result) then
				results[result] = (results[result] or 0) + 1
			end
		end
		//Show on-screen notifications for all fx we converted or failed to convert
		ply:SendLua("surface.PlaySound('common/wpn_select.wav')")
		if results[true] then
			MsgN("Successfully converted " .. results[true] .. " prop(s)!")
			ply:SendLua("GAMEMODE:AddNotify('Successfully converted " .. results[true] .. " prop(s)!', NOTIFY_GENERIC, 4)")
			ply:SendLua("surface.PlaySound('ambient/water/drip" .. math.random(1, 4) .. ".wav')")
		end
		if results[false] then
			MsgN("Failed to convert " .. results[false] .. " prop(s)!")
			ply:SendLua("GAMEMODE:AddNotify('Failed to convert " .. results[false] .. " prop(s)!', NOTIFY_ERROR, 4)")
			ply:SendLua("surface.PlaySound('buttons/button11.wav')")
		end
	end, nil, "Update all old Animated Props on the map to the new addon")
end
