//This file handles backwards compatibility for old animated prop entities that have all been replaced by prop_animated

AddCSLuaFile()

if CLIENT then return end
//if SERVER then return end //uncomment this when we need to use the old tool for something

duplicator.RegisterEntityClass("animprop_generic", function(ply, data)

	//Create a dummy entity with the data table and convert it into an animprop
	data.Class = "base_gmodentity"
	data.PhysicsObjects = nil //don't copy this, it'll break stuff
	local EntityMods = data.EntityMods //the duplicator will apply entitymods to the new animprop after this function finishes; don't pre-apply them to the dummy, or they'll get applied twice
	local BoneMods = data.BoneMods //this too
	data.EntityMods = nil
	data.BoneMods = nil
	local dummy = duplicator.GenericDuplicatorFunction(ply, data)
	data.EntityMods = EntityMods
	data.BoneMods = BoneMods
	if !IsValid(dummy) then return end
	local animprop = ConvertEntityToAnimprop(dummy, ply, true, true)
	if !IsValid(animprop) then dummy:Remove() return end

	//Convert animation settings
	animprop:SetChannel1Sequence(animprop:LookupSequence(data.MyAnim)) //sequence is stored as name string instead of id number
	animprop:SetChannel1Speed(data.MyPlaybackRate)
	animprop:SetChannel1Pause(data.IsPaused)
	animprop:SetChannel1PauseFrame(data.PauseFrame)

	//Convert the gesture, if applicable
	if data.EntityMods and data.EntityMods.GesturizerEntity and data.EntityMods.GesturizerEntity.AnimName then
		animprop:SetChannel2Sequence(animprop:LookupSequence(data.EntityMods.GesturizerEntity.AnimName)) //sequence is stored as name string instead of id number
		data.EntityMods.GesturizerEntity = nil
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
			default = data.StoredAimPitch or 0
		elseif name == "aim_yaw" then
			default = data.StoredAimYaw or 0
		elseif name == "body_pitch" then
			default = data.StoredAimPitch or 0
		elseif name == "body_yaw" then
			default = data.StoredAimYaw or 0
		elseif name == "move_x" then
			default = data.StoredMoveX or 1
		elseif name == "move_y" then
			default = data.StoredMoveY or 0
		elseif name == "move_yaw" then
			default = data.StoredMoveYaw or 0
		end
		animprop.PoseParams[i] = default
	end

	//Physics
	animprop:SetModelScale(data.MyModelScale) //scale is stored in a separate value for no reason
	if data.IsPhysified and data.ConfirmationID then
		animprop.ConfirmationID = data.ConfirmationID  //this was used by the "physmodel" entity to associate itself with the animprop - we don't need a separate entity 
		animprop:SetPhysicsMode(0) //use prop physics  //for this any more, but we still need to match them up so we can move the constraints over to the animprop (see below)
		//don't worry about EnableMotion; in the old addon, physified animprops don't load this value and always spawn unfrozen
	else
		animprop:SetPhysicsMode(2) //use effect physics
		animprop:SetCollisionGroup(COLLISION_GROUP_WORLD) //make sure we don't push anything away now that we're physical
		local phys = animprop:GetPhysicsObject()
		if IsValid(phys) then phys:EnableMotion(false) end //also make sure we don't get pushed away by the world if we're flush against it
	end

	return animprop

end, "Data")

duplicator.RegisterEntityClass("animprop_generic_physmodel", function(ply, data)

	//Create a dummy entity with the data table
	data.Class = "base_gmodentity"
	local EntityMods = data.EntityMods //the duplicator will apply entitymods to the new animprop after this function finishes; don't pre-apply them to the dummy, or they'll get applied twice
	local BoneMods = data.BoneMods //this too
	data.EntityMods = nil
	data.BoneMods = nil
	local dummy = duplicator.GenericDuplicatorFunction(ply, data)
	data.EntityMods = EntityMods
	data.BoneMods = BoneMods
	if !IsValid(dummy) then return end

	//Give it a physics object so all constraints attached to it are created properly
	dummy:PhysicsInitBox(Vector(-2,-2,-2), Vector(2,2,2))
	local phys = dummy:GetPhysicsObject()
	if IsValid(phys) then phys:EnableMotion(false) end
	dummy:SetCollisionGroup(COLLISION_GROUP_WORLD)

	dummy.Think = function()

		//Physmodel ents are associated with their animprops with a randomly generated ID assigned to both of them, as well as a nocollide constraint.
		//This function tries to find and return an entity's associated animprop, or if it can't find it, return the entity.
		local function FindPhysmodelAnimprop(ent)

			if ent.ConfirmationID and ent:GetClass() == "base_gmodentity" then

				local constrainedents = table.Copy(constraint.GetAllConstrainedEntities(ent))
				for _, ent2 in pairs (constrainedents) do
					if ent2 != ent and ent2.ConfirmationID and ent2.ConfirmationID == ent.ConfirmationID then
						return ent2, true
					end
				end

				return ent, false

			else

				return ent, false

			end

		end

		//If the physmodel is orphaned somehow and doesn't have an associated animprop, then remove it and stop here
		local ouranimprop = FindPhysmodelAnimprop(dummy)
		if ouranimprop == dummy then dummy:Remove() return end

		//We need to move all the constraints from the physmodel to its animprop, but some of the constraints won't be created correctly for some reason if we apply them 
		//in the first think, so instead we're making a table of constraints in the first think, and then checking for that table here so it gets used in the second think.
		if dummy.ConstraintsToMove then
			//Fix some old animprops falling through the world because they're nocollided with it using an advballsocket constraint.
			//constraint.RemoveConstraints won't affect the original constraint for some reason, so instead we need to make an identical one here 
			//and remove it immediately after, and that'll fix it somehow. Yes, this works.
			local const = constraint.AdvBallsocket(ouranimprop, game.GetWorld(), 0, 0, ouranimprop:GetPos(), Vector(0,0,0), 0, 0, -180, -180, -180, 180, 180, 180, 0, 0, 0, 1, 1)
			const:Remove()

			for k, v in pairs (dummy.ConstraintsToMove) do
				duplicator.CreateConstraintFromTable(v.const, v.entstab)
			end
			dummy:Remove()
			return
		end

		//Make a table of constraints we want to move
		local constraints = table.Copy(constraint.GetTable(dummy))
		dummy.ConstraintsToMove = {}
		for k, const in pairs (constraints) do
			if const.Entity then
				//If any of the values in the constraint table are physmodels, switch them over to their animprops
				for key, val in pairs (const) do
					if type(val) == "Entity" then
						const[key] = FindPhysmodelAnimprop(val)
						//MsgN(key, ": ", val)
					end
				end

				local entstab = {}

				//Also switch over any instances of physmodels to animprops inside the entity subtable
				for tabnum, tab in pairs (const.Entity) do
					if tab.Entity then
						local animprop, foundanimprop = FindPhysmodelAnimprop(const.Entity[tabnum].Entity)
						//MsgN(tab.Entity, " ", animprop, " ", foundanimprop)
						if foundanimprop then
							const.Entity[tabnum].Entity = animprop
							const.Entity[tabnum].Index = animprop:EntIndex()	
						end
					end
					entstab[const.Entity[tabnum].Index] = const.Entity[tabnum].Entity
				end

				dummy.ConstraintsToMove[k] = {const = table.Copy(const), entstab = table.Copy(entstab)}
			end
		end

	end

	return dummy

end, "Data")

//"Premade" animprops were originally made because it wasn't possible to add their particle effects or multiple models yourself at the time. Nowadays, though, we have the adv particle
//controller (for particle effects) and the adv bonemerge tool (for multiple models), so they really aren't necessary any more. Spawn regular animprops modified with those tools instead.

duplicator.RegisterEntityClass("animprop_spawnacarrier", function(ply, data)

	data.Model = "models/bots/boss_bot/carrier.mdl"

	//Create a dummy entity with the data table and convert it into an animprop
	data.Class = "base_gmodentity"
	data.PhysicsObjects = nil //don't copy this, it'll break stuff
	local EntityMods = data.EntityMods //the duplicator will apply entitymods to the new animprop after this function finishes; don't pre-apply them to the dummy, or they'll get applied twice
	local BoneMods = data.BoneMods //this too
	data.EntityMods = nil
	data.BoneMods = nil
	local dummy = duplicator.GenericDuplicatorFunction(ply, data)
	data.EntityMods = EntityMods
	data.BoneMods = BoneMods
	if !IsValid(dummy) then return end
	local animprop = ConvertEntityToAnimprop(dummy, ply, true, true)
	if !IsValid(animprop) then dummy:Remove() return end

	animprop:SetPhysicsMode(2) //use effect physics
	animprop:SetCollisionGroup(COLLISION_GROUP_WORLD) //make sure we don't push anything away now that we're physical
	local phys = animprop:GetPhysicsObject()
	if IsValid(phys) then phys:EnableMotion(false) end //also make sure we don't get pushed away by the world if we're flush against it

	//Create a second animprop for the detail parts
	local dummy2 = ents.Create("prop_dynamic")
	if !IsValid(dummy2) then return end
	dummy2:SetPos(animprop:GetPos())
	dummy2:SetAngles(animprop:GetAngles())
	dummy2:SetModel("models/bots/boss_bot/carrier_parts.mdl")
	local animprop2 = ConvertEntityToAnimprop(dummy2, ply, true, true)
	if !IsValid(animprop2) then dummy2:Remove() return end
	animprop2:SetChannel1Sequence(animprop2:LookupSequence("radar_idles"))

	if CreateAdvBonemergeEntity then
		//Attach the parts with adv bonemerge tool
		animprop2 = CreateAdvBonemergeEntity(animprop2, animprop, ply, false, false, true)
		constraint.AdvBoneMerge(animprop, animprop2, ply)
		animprop2.AdvBone_BoneInfo_IsDefault = false
	else
		//If the adv bonemerge addon isn't installed, then weld the parts as a fallback
		animprop2:SetPhysicsMode(2) //use effect physics
		animprop2:SetCollisionGroup(COLLISION_GROUP_WORLD) //make sure we don't push anything away now that we're physical
		local phys = animprop2:GetPhysicsObject()
		if IsValid(phys) then phys:EnableMotion(false) end //also make sure we don't get pushed away by the world if we're flush against it
		animprop2:SetPos(animprop:GetPos())
		animprop2:SetAngles(animprop:GetAngles())
		constraint.Weld(animprop, animprop2, 0, 0, 0, true, false)
	end

	return animprop
	
end, "Data")

local function SpawnTeleporter(ply, data, team, level, entrance)

	data.Model = "models/buildables/teleporter_light.mdl"
	data.Skin = team

	//Create a dummy entity with the data table and convert it into an animprop
	data.Class = "base_gmodentity"
	data.PhysicsObjects = nil //don't copy this, it'll break stuff
	local EntityMods = data.EntityMods //the duplicator will apply entitymods to the new animprop after this function finishes; don't pre-apply them to the dummy, or they'll get applied twice
	local BoneMods = data.BoneMods //this too
	data.EntityMods = nil
	data.BoneMods = nil
	local dummy = duplicator.GenericDuplicatorFunction(ply, data)
	data.EntityMods = EntityMods
	data.BoneMods = BoneMods
	if !IsValid(dummy) then return end
	local animprop = ConvertEntityToAnimprop(dummy, ply, true, true)
	if !IsValid(animprop) then dummy:Remove() return end

	animprop:SetChannel1Sequence(animprop:LookupSequence("running"))
	local phys = animprop:GetPhysicsObject()
	if IsValid(phys) then phys:EnableMotion(false) end

	animprop:SetBodygroup(1,1) //blur
	if entrance then animprop:SetBodygroup(2,1) end //arrow

	//Add particle effects with adv particle controller
	if AttachParticleControllerNormal then
		if team == 0 then
			team = "red"
		else
			team = "blue"
		end
		level = tostring(level)
		if entrance then
			entrance = "entrance"
		else
			entrance = "exit"
		end

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
		tab.EffectName = "teleporter_" .. team .. "_charged_level" .. level
		tab.AttachNum = 0
		AttachParticleControllerNormal(ply, animprop, {NewTable = tab})

		//Direction effect
		local tab = table.Copy(genericparticletable)
		tab.EffectName = "teleporter_" .. team .. "_" .. entrance .. "_level" .. level
		tab.AttachNum = 0
		AttachParticleControllerNormal(ply, animprop, {NewTable = tab})

		//Arm effect 1 (apparently teleporters have these at all times. why not?)
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

	return animprop

end

duplicator.RegisterEntityClass("animprop_spawnentrance_blue", function(ply, data)
	return SpawnTeleporter(ply, data, 1, 1, true)
end, "Data")

duplicator.RegisterEntityClass("animprop_spawnentrance_blue3", function(ply, data)
	return SpawnTeleporter(ply, data, 1, 3, true)
end, "Data")

duplicator.RegisterEntityClass("animprop_spawnentrance_red", function(ply, data)
	return SpawnTeleporter(ply, data, 0, 1, true)
end, "Data")

duplicator.RegisterEntityClass("animprop_spawnentrance_red3", function(ply, data)
	return SpawnTeleporter(ply, data, 0, 3, true)
end, "Data")

duplicator.RegisterEntityClass("animprop_spawnexit_blue", function(ply, data)
	return SpawnTeleporter(ply, data, 1, 1, false)
end, "Data")

duplicator.RegisterEntityClass("animprop_spawnexit_blue3", function(ply, data)
	return SpawnTeleporter(ply, data, 1, 3, false)
end, "Data")

duplicator.RegisterEntityClass("animprop_spawnexit_red", function(ply, data)
	return SpawnTeleporter(ply, data, 0, 1, false)
end, "Data")

duplicator.RegisterEntityClass("animprop_spawnexit_red3", function(ply, data)
	return SpawnTeleporter(ply, data, 0, 3, false)
end, "Data")

local function SpawnMiniSentry(ply, data, team)

	data.Model = "models/buildables/sentry1.mdl"
	data.Skin = team + 2

	//Create a dummy entity with the data table and convert it into an animprop
	data.Class = "base_gmodentity"
	data.PhysicsObjects = nil //don't copy this, it'll break stuff
	local EntityMods = data.EntityMods //the duplicator will apply entitymods to the new animprop after this function finishes; don't pre-apply them to the dummy, or they'll get applied twice
	local BoneMods = data.BoneMods //this too
	data.EntityMods = nil
	data.BoneMods = nil
	local dummy = duplicator.GenericDuplicatorFunction(ply, data)
	data.EntityMods = EntityMods
	data.BoneMods = BoneMods
	if !IsValid(dummy) then return end
	local animprop = ConvertEntityToAnimprop(dummy, ply, true, true)
	if !IsValid(animprop) then dummy:Remove() return end

	local phys = animprop:GetPhysicsObject()
	if IsValid(phys) then phys:EnableMotion(false) end

	animprop:SetModelScale(0.75)
	animprop:SetBodygroup(2,1) //light

	//Add particle effects with adv particle controller
	if AttachParticleControllerNormal then
		if team == 0 then
			team = "_red"
		else
			team = ""
		end

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

	return animprop

end

duplicator.RegisterEntityClass("animprop_spawnminisentry_blue", function(ply, data)
	return SpawnMiniSentry(ply, data, 1)
end, "Data")

duplicator.RegisterEntityClass("animprop_spawnminisentry_red", function(ply, data)
	return SpawnMiniSentry(ply, data, 0)
end, "Data")

local function SpawnTank(ply, data, bodyseq, treadseq, bombseq)

	//data.Model = "models/bots/boss_bot/boss_tank.mdl" //this pre-made prop actually had an editable model and skin so players could use damaged tank models or the final tank skin

	//Create a dummy entity with the data table and convert it into an animprop
	data.Class = "base_gmodentity"
	data.PhysicsObjects = nil //don't copy this, it'll break stuff
	local EntityMods = data.EntityMods //the duplicator will apply entitymods to the new animprop after this function finishes; don't pre-apply them to the dummy, or they'll get applied twice
	local BoneMods = data.BoneMods //this too
	data.EntityMods = nil
	data.BoneMods = nil
	local dummy = duplicator.GenericDuplicatorFunction(ply, data)
	data.EntityMods = EntityMods
	data.BoneMods = BoneMods
	if !IsValid(dummy) then return end
	local animprop = ConvertEntityToAnimprop(dummy, ply, true, true)
	if !IsValid(animprop) then dummy:Remove() return end

	animprop:SetChannel1Sequence(animprop:LookupSequence(bodyseq))
	animprop:SetPhysicsMode(0) //use prop physics
	if data.IsPhysified and data.ConfirmationID then
		animprop.ConfirmationID = data.ConfirmationID  //this was used by the "physmodel" entity to associate itself with the animprop - we don't need a separate entity 
	end

	//Create more animprops for the detail parts
	local function CreateDetailAnimprop(model, seqstr)
		local dummy2 = ents.Create("prop_dynamic")
		if !IsValid(dummy2) then return end
		dummy2:SetPos(animprop:GetPos())
		dummy2:SetAngles(animprop:GetAngles())
		dummy2:SetModel(model)
		local animprop2 = ConvertEntityToAnimprop(dummy2, ply, true, true)
		if !IsValid(animprop2) then dummy2:Remove() return end
		animprop2:SetChannel1Sequence(animprop2:LookupSequence(seqstr))

		return animprop2
	end
	local animprop2 = CreateDetailAnimprop("models/bots/boss_bot/bomb_mechanism.mdl", bombseq)
	local animprop3 = CreateDetailAnimprop("models/bots/boss_bot/tank_track_l.mdl", treadseq)
	local animprop4 = CreateDetailAnimprop("models/bots/boss_bot/tank_track_r.mdl", treadseq)
	if !IsValid(animprop2) or !IsValid(animprop3) or !IsValid(animprop4) then return end

	if CreateAdvBonemergeEntity then
		//Attach the parts with adv bonemerge tool
		local function DoAdvBonemerge(ent)
			ent = CreateAdvBonemergeEntity(ent, animprop, ply, false, false, true)
			constraint.AdvBoneMerge(animprop, ent, ply)
			ent.AdvBone_BoneInfo_IsDefault = false
		end
		DoAdvBonemerge(animprop2)
		DoAdvBonemerge(animprop3)
		DoAdvBonemerge(animprop4)
	else
		//If the adv bonemerge addon isn't installed, then weld the parts as a fallback
		local function DoFallback(ent, posoffset)
			ent:SetPos(LocalToWorld(posoffset, Angle(), animprop:GetPos(), animprop:GetAngles()))
			ent:SetAngles(animprop:GetAngles())
			constraint.Weld(animprop, ent, 0, 0, 0, true, false)
		end
		DoFallback(animprop2, vector_origin)
		DoFallback(animprop3, Vector(0,56,0))
		DoFallback(animprop4, Vector(0,-56,0))
	end

	return animprop

end

duplicator.RegisterEntityClass("animprop_spawntank", function(ply, data)
	return SpawnTank(ply, data, "movement", "ref", "ref")
end, "Data")

duplicator.RegisterEntityClass("animprop_spawntank_deploy", function(ply, data)
	return SpawnTank(ply, data, "deploy", "ref", "deploy")
end, "Data")

duplicator.RegisterEntityClass("animprop_spawntank_moving", function(ply, data)
	return SpawnTank(ply, data, "movement", "forward", "ref")
end, "Data")