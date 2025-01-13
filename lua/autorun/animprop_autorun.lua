AddCSLuaFile()

if SERVER then

	util.AddNetworkString("AnimProp_OpenEditMenu_SendToCl")

else

	local h_min = 167
	local h_max = ScrH()
	local w_min = 411	  //set to perfectly fit minimum width of both left and right sides of animation options divider
	local w_max = ScrW()
	local d_min = 125         //NOTE: value is from divider min left width in animprop editor, make sure these numbers match!
	local d_max = w_max - 250 //NOTE: value is from divider min right width in animprop editor, make sure these numbers match!
	local d2_min = 187.5	  //NOTE: same as above but for poseparam divider
	local d2_max = w_max - 187.5//NOTE: same as above but for poseparam divider
	local d3_min = 125         //NOTE: same as above but for remapping divider
	local d3_max = w_max - 250 //NOTE: same as above but for remapping divider

	CreateClientConVar("cl_animprop_editor_h", "500", true, false, "Height of the animated prop edit window", h_min, h_max) //default is min height to fit all remapping options without a scrollbar
	CreateClientConVar("cl_animprop_editor_w", "600", true, false, "Width of the animated prop edit window", w_min, w_max)  //default is wide enough for anim and anim option names to be legible (seconds between repeats especially)
	CreateClientConVar("cl_animprop_editor_d", "200", true, false, "Position of the central divider in the animated prop editor's animation page", d_min, d_max) //^
	CreateClientConVar("cl_animprop_editor_d2", "346", true, false, "Position of the central divider in the animated prop editor's poseparam page", d2_min, d2_max) //default is wide enough to snugly fit poseparam options
	CreateClientConVar("cl_animprop_editor_d3", "200", true, false, "Position of the central divider in the animated prop editor's remapping page", d3_min, d3_max) //default is wide enough for bone and option names to be legible

	animpropwindows = {}

	function OpenAnimpropEditor(ent)

		if IsValid(ent.AnimpropControlWindow) then return end

		local window = g_ContextMenu:Add("DFrame")
		window:SetSize(GetConVar("cl_animprop_editor_w"):GetInt(), GetConVar("cl_animprop_editor_h"):GetInt())
		window:Center()
		window:SetSizable(true)
		window:SetMinHeight(h_min)
		window:SetMinWidth(w_min)

		//When opening multiple edit windows, move the default position slightly for each window open so they don't get completely hidden by each other until the player moves them
		local x, y = window:GetPos()
		local xmax, ymax = g_ContextMenu:GetSize()
		window:SetPos(math.min(x + (#animpropwindows * 25), xmax - 25), math.min(y + (#animpropwindows * 25), ymax - 25))

		local control = window:Add("AnimpropEditor")
		window.Control = control
		control:SetEntity(ent)
		control:Dock(FILL)

		table.insert(animpropwindows, window)

		control.OnEntityLost = function()
			window:Remove()
		end

		//On close, save window dimensions to convars so it'll be the same size when the player opens it back up
		window.OnRemove = function()
			local w, h = window:GetSize()
			LocalPlayer():ConCommand("cl_animprop_editor_h " .. tostring(h))
			LocalPlayer():ConCommand("cl_animprop_editor_w " .. tostring(w))
			if control then
				if control.AnimChannels then
					local d = control.AnimChannels[1].Divider:GetLeftWidth()
					LocalPlayer():ConCommand("cl_animprop_editor_d " .. tostring(d))
				end
				if control.PoseParameters then
					local d2 = control.PoseParameters.Divider:GetLeftWidth()
					LocalPlayer():ConCommand("cl_animprop_editor_d2 " .. tostring(d2))
				end
				if control.Remapping then
					//this divider will only exist if the prop is doing remapping
					if control.Remapping.Divider then
						local d3 = control.Remapping.Divider:GetLeftWidth()
						LocalPlayer():ConCommand("cl_animprop_editor_d3 " .. tostring(d3))
					end
				end
			end
			table.remove(animpropwindows, table.KeyFromValue(animpropwindows, window))
		end

		//Fix: If the control window is created while the context menu is closed (by clicking "convert to animated prop" and immediately letting go of C) then it'll be unclickable
		//and get stuck on the screen until the entity is removed, so we have to manually enable mouse input here to stop that from happening
		window:SetMouseInputEnabled(true)
		control:SetMouseInputEnabled(true)

	end

	net.Receive("AnimProp_OpenEditMenu_SendToCl", function()

		local ent = net.ReadEntity()

		if !IsValid(ent) then return end
		if ent:GetClass() != "prop_animated" then return end
		if !gamemode.Call("CanProperty", LocalPlayer(), "editanimprop", ent) then return end

		OpenAnimpropEditor(ent)

	end)

end

properties.Add("editanimprop", {
	MenuLabel = "Edit Animated Prop..",
	Order = 90002,
	PrependSpacer = true,
	MenuIcon = "icon16/film_edit.png",
	
	Filter = function(self, ent, ply)

		if !IsValid(ent) then return false end
		if ent:GetClass() != "prop_animated" then return false end
		if !gamemode.Call("CanProperty", ply, "editanimprop", ent) then return false end

		return true

	end,

	Action = function(self, ent)
	
		OpenAnimpropEditor(ent)

	end
})

properties.Add("makeanimprop", {
	MenuLabel = "Convert to Animated Prop",
	Order = 1600,
	MenuIcon = "icon16/film_add.png",
	Filter = function(self, ent, ply)

		if !IsValid(ent) then return false end
		if !util.IsValidModel(ent:GetModel()) then return false end
		if ent:IsPlayer() then return false end
		if ent:GetClass() == "prop_animated" then return false end

		if !gamemode.Call("CanProperty", ply, "makeanimprop", ent) then return false end

		//This option removes the old ent and replaces it with an animated prop, so if players aren't allowed 
		//to remove things, then they shouldn't be allowed to turn things into animated props either
		if !gamemode.Call("CanProperty", ply, "remover", ent) then return false end

		return true

	end,

	Action = function(self, ent)

		self:MsgStart()
			net.WriteEntity(ent)
		self:MsgEnd()

		surface.PlaySound("common/wpn_select.wav")

	end,

	Receive = function(self, length, ply)

		local ent = net.ReadEntity()

		if !IsValid(ent) then return false end
		if !properties.CanBeTargeted(ent, ply) then return false end
		if !util.IsValidModel(ent:GetModel()) then return false end
		if !IsValid(ply) then return false end
		if ent:IsPlayer() then return false end
		if ent:GetClass() == "prop_animated" then return false end
		if !self:Filter(ent, ply) then return false end

		ConvertEntityToAnimprop(ent, ply, false, false, true)

	end
} )

if SERVER then

	function ConvertEntityToAnimprop(ent, ply, disableeditmenu, disableundo, freeze, ispuppeteer)

		if !IsValid(ent) then return end
		//if !IsValid(ply) then return end
		if ent:IsPlayer() then return end
		if ent:GetClass() == "prop_animated" then return end
		if IsValid(ply) then 
			if !ispuppeteer then //puppeteers are internal entities, we shouldn't care about players having "permission" to spawn them
				if !gamemode.Call("CanProperty", ply, "makeanimprop", ent) then return end
				//this option removes the old ent and replaces it with an animated prop, so if players aren't allowed 
				//to remove things, then they shouldn't be allowed to turn things into animated props either
				if !gamemode.Call("CanProperty", ply, "remover", ent) then return end
			end
			if !ply:CheckLimit("animprops") then return false end
		end

		local oldent = ent
		if ent:GetClass() == "prop_effect" and ent.AttachedEntity then ent = ent.AttachedEntity end

		local prop = ents.Create("prop_animated")
		prop:SetPos(ent:GetPos())
		if ent:GetClass() == "prop_ragdoll" and IsValid(ply) then
			//Rotate animprops converted from ragdolls to face the player, because they'll always face the same direction otherwise
			local ang = (prop:GetPos() - ply:GetPos()):Angle()
			prop:SetAngles(Angle(0,ang.y-180,0))
		else
			prop:SetAngles(ent:GetAngles())
		end
		if IsValid(ply) then prop:SetPlayer(ply) end

		//Copy all of the ent's information to the animprop
		prop:SetModel(ent:GetModel() or "models/error.mdl")
		prop:SetSkin(ent:GetSkin() or 0)
		//Copy bodygroups
		if ent:GetNumBodyGroups() then
			for i = 0, ent:GetNumBodyGroups() - 1 do
				prop:SetBodygroup(i, ent:GetBodygroup(i)) 
			end
		end
		//Copy flexes
		if ent:HasFlexManipulatior() then
			prop:SetFlexScale(ent:GetFlexScale())
			for i = 0, ent:GetFlexNum() - 1 do 
				prop:SetFlexWeight(i, ent:GetFlexWeight(i)) 
			end
		end
		//Copy bonemanips
		prop.AdvBone_BoneManips = ent.AdvBone_BoneManips or {}
		for i = 0, ent:GetBoneCount() - 1 do
			if ent:GetManipulateBonePosition(i) != vector_origin then prop:ManipulateBonePosition(i, ent:GetManipulateBonePosition(i)) end
			if ent:GetManipulateBoneAngles(i) != angle_zero then prop:ManipulateBoneAngles(i, ent:GetManipulateBoneAngles(i)) end
			if ent:GetManipulateBoneScale(i) != Vector(1,1,1) then prop:ManipulateBoneScale(i, ent:GetManipulateBoneScale(i)) end
			//prop:ManipulateBoneJiggle(i, ent:GetManipulateBoneJiggle(i))  //broken?
		end
		//(Advanced Bonemerge) Copy boneinfo table
		if ent.AdvBone_BoneInfo then
			prop.AdvBone_BoneInfo = table.Copy(ent.AdvBone_BoneInfo)
			prop.AdvBone_BoneInfo_IsDefault = false //if it's not an animprop and it has a boneinfo table while unmerged, then it's not default
		end
		//(Advanced Bonemerge (I Guess)) Copy over DisableBeardFlexifier, just in case we're an unmerged ent that inherited this value
		prop:SetNWBool("DisableBeardFlexifier", ent:GetNWBool("DisableBeardFlexifier"))
		//Try to convert resized ragdoll scale to advbone/bonemanip scale
		if ent:GetClass() == "prop_ragdoll" and ent.ClassOverride == "prop_resizedragdoll_physparent" then
			//First off, if all the values in all the vectors are the same (player just used the Ragdoll Scale slider to linearly scale the whole model), 
			//then just change our model scale instead.
			local same = true
			local val = nil
			for physbone, scale in pairs (ent.PhysObjScales) do
				if same then
					for xyz, val2 in pairs ( {scale.x, scale.y, scale.z} ) do
						if !val then val = val2 end
						if val2 != val then same = false break end
					end
				else
					break
				end
			end

			if same then
				prop:SetModelScale(val)
			else
				//Now for the real part - if the physobjs have separate scales, then apply those scales to their corresponding bones while having their child bones scale 
				//with them. This is by no means perfect and will probably mess up in a few ways if the ragdoll has any bone manips, but it's the best we can do.
				if duplicator.FindEntityClass("ent_advbonemerge") then //this relies on the adv bonemerge addon's scaling features, so we'll need it for this
					if !prop.AdvBone_BoneInfo then prop:CreateAdvBoneInfoTable(nil, false) end
					local PhysBoneScalesByBone = {}
					for physbone, scale in pairs (ent.PhysObjScales) do
						PhysBoneScalesByBone[ ent:TranslatePhysBoneToBone(physbone) ] = scale
					end
					for i = 0, ent:GetBoneCount() - 1 do
						if PhysBoneScalesByBone[i] then
							local manipscale = ent:GetManipulateBoneScale(i)
							prop:ManipulateBoneScale(i, Vector(PhysBoneScalesByBone[i].x * manipscale.x, PhysBoneScalesByBone[i].y * manipscale.y, PhysBoneScalesByBone[i].z * manipscale.z))
							prop.AdvBone_BoneInfo[i].scale = false
						else
							prop.AdvBone_BoneInfo[i].scale = true
						end
					end
				end
			end
		else
			prop:SetModelScale(ent:GetModelScale())
		end

		//Set NWVar defaults
		for i = 1, 4 do
			prop["SetChannel" .. i .. "Sequence"](prop, -1)
			prop["SetChannel" .. i .. "Pause"](prop, false)
			prop["SetChannel" .. i .. "PauseFrame"](prop, 0)
			prop["SetChannel" .. i .. "Speed"](prop, 1)
			prop["SetChannel" .. i .. "LoopMode"](prop, 1)
			prop["SetChannel" .. i .. "LoopDelay"](prop, 0)
			prop["SetChannel" .. i .. "Numpad"](prop, 0)
			prop["SetChannel" .. i .. "NumpadToggle"](prop, true)
			prop["SetChannel" .. i .. "NumpadStartOn"](prop, true)
			prop["SetChannel" .. i .. "StartPoint"](prop, 0)
			prop["SetChannel" .. i .. "EndPoint"](prop, 1)
		end
		for i = 2, 4 do
			prop["SetChannel" .. i .. "LayerSettings"](prop, Vector(0,0,1))
		end
		//carry over the sequence if we convert something like an npc, but make sure ragdolls and the like still start out with no sequence
		if ent:SequenceDuration() > 0 then
			prop:SetChannel1Sequence(ent:GetSequence())
		end

		prop:SetControlMovementPoseParams(false)
		prop:SetEnableAnimEventEffects(true)

		//Set default physics mode
		local mdl = prop:GetModel()
		if util.IsValidProp(mdl) and !util.IsValidRagdoll(mdl) then
			//Use phys mode 0 (physics prop) for prop models
			prop:SetPhysicsMode(0)
		else
			local min, max = prop:GetModelBounds()
			local size = max - min
			if size.x > 1000 or size.y > 1000 or size.z > 1000 then
				//Use phys mode 2 (effect) for really big models
				prop:SetPhysicsMode(2)
			else
				//Use phys mode 1 (physics box) otherwise
				prop:SetPhysicsMode(1)
			end
		end

		//Try to guess if our model is a character model and should have NoPhysicsBelowOrigin default to true
		local min, max = prop:GetModelBounds()
		//This method is by no means perfect - these are all models from HL2 or TF2 that return false to the bestguess check but should still default to true
		local overrides = {
			"models/headcrabblack.mdl", "models/headcrabclassic.mdl", "models/lamarr.mdl", "models/zombie/classic_torso.mdl", "models/props_combine/combine_mine01.mdl",
			"models/crow.mdl", "models/pigeon.mdl", "models/antlion_grub.mdl", "models/buildables/sentry1_range.mdl", "models/buildables/sentry1_blueprint.mdl",
			"models/buildables/sentry2.mdl", "models/buildables/sentry2_heavy.mdl",
		}
		local bestguess = max.z > 1 and min.z <= 0 and (min.z * -4) < max.z
		for _, v in pairs(overrides) do
			if mdl == v then bestguess = true end
		end
		prop:SetNoPhysicsBelowOrigin(bestguess)

		//If converting a ragdoll, lower the animprop down to the bottom of the ragdoll's bounding box until it hits the floor, instead of keeping it at the ragdoll's origin, 
		//so the animprop spawns flush on the ground instead of floating in midair.
		//We have to do this all the way down here because NoPhysicsBelowOrigin sets where the "bottom" of the animprop is.
		if ent:GetClass() == "prop_ragdoll" then
			local mins, maxs = ent:GetCollisionBounds()
			local pos = ent:GetPos()
			local tr = util.TraceLine({start = pos + Vector(0,0,maxs.z), endpos = pos + Vector(0,0,mins.z), filter = {ent, prop}})
			local newpos = tr.HitPos
			if !bestguess then
				newpos = newpos - Vector(0,0,min.z) //"min" of prop model bounds, not "mins" of ragdoll collision bounds
			end
			prop:SetPos(newpos)
		end

		//If this animprop is a puppeteer, then store that value on us NOW, so that initialize doesn't try to give up a physics object
		if ispuppeteer then prop.IsPuppeteer = true end

		//Carry over DisableBeardFlexifier
		prop:SetNWBool("DisableBeardFlexifier", ent:GetNWBool("DisableBeardFlexifier"))

		if IsValid(ply) then
			//Tell the entity to open up the clientside edit menu for this player once it's done spawning
			if !disableeditmenu then
				prop.EditMenuPlayer = ply
			end
		end

		//Spawn the entity and then apply entity modifiers - we need to spawn the entity for these to work, so do these last
		prop:Spawn()
		prop.EntityMods = ent.EntityMods
		prop.BoneMods = ent.BoneMods
		duplicator.ApplyEntityModifiers(ply, prop)
		duplicator.ApplyBoneModifiers(ply, prop)

		//Copy certain non-physics constraints over to the animprop
		local ConstraintsToPreserve = {
			["AdvBoneMerge"] = true,
			["AttachParticleControllerBeam"] = true, //Advanced Particle Controller addon
			["PartCtrl_Ent"] = true, //ParticleControlOverhaul
			//["BoneMerge"] = true, //Bone Merger addon
			["EasyBonemerge"] = true, //Easy Bonemerge Tool addon
			["CompositeEntities_Constraint"] = true, //Composite Bonemerge addon
		}
		local oldentconsts = constraint.GetTable(oldent)
		for k, const in pairs (oldentconsts) do
			if const.Entity then
				if ConstraintsToPreserve[const.Type] then
					//If any of the values in the constraint table are oldent, switch them over to the prop
					for key, val in pairs (const) do
						if val == oldent then 
							const[key] = prop 
						//Transfer over bonemerged ents from other addons' bonemerge constraints, and make sure they don't get DeleteOnRemoved
						elseif (const.Type == "EasyBonemerge" or const.Type == "CompositeEntities_Constraint" or const.Type == "PartCtrl_Ent") //doesn't work for BoneMerge, bah
						and isentity(val) and IsValid(val) and val:GetParent() == oldent then
							//MsgN("reparenting ", val:GetModel())
							if const.Type == "CompositeEntities_Constraint" then
								val:SetParent(prop)
							end
							oldent:DontDeleteOnRemove(val)
						end

					end

					local entstab = {}

					//Also switch over any instances of oldent to prop inside the entity subtable
					for tabnum, tab in pairs (const.Entity) do
						if tab.Entity and tab.Entity == oldent then 
							const.Entity[tabnum].Entity = prop
							const.Entity[tabnum].Index = prop:EntIndex()
						end
						entstab[const.Entity[tabnum].Index] = const.Entity[tabnum].Entity
					end

					if const.Type == "PartCtrl_Ent" and IsValid(const.Ent1) then
						oldent:DontDeleteOnRemove(const.Ent1) //Make sure we also clear deleteonremove for unparented cpoints
						//Tell clients to retrieve the updated info table (the constraint func will change the relevant value to point to our ent)
						timer.Simple(0.1, function() //do this on a timer, otherwise the advbonemerge ent might not exist on the client yet when they receive the new table
							net.Start("PartCtrl_InfoTableUpdate_SendToCl")
								net.WriteEntity(const.Ent1)
							net.Broadcast()
						end)
					end

					//Now copy the constraint over to the prop
					duplicator.CreateConstraintFromTable(const, entstab)
				end
			end
		end

		//Freeze the prop
		if freeze then
			local phys = prop:GetPhysicsObject()
			if IsValid(phys) then 
				phys:EnableMotion(false)
				if ply then
					ply:AddFrozenPhysicsObject(nil, phys)  //the entity argument needs to be nil, or else it'll make unnecessary halo effects and lag up the game
				end
			end
		end

		//Add an undo entry
		if IsValid(ply) then
			if !disableundo then
				undo.Create("Animprop")
					undo.AddEntity(prop)
					undo.SetPlayer(ply)
				undo.Finish("Animated Prop (" .. tostring(ent:GetModel() or "models/error.mdl") .. ")")
				ply:AddCleanup("animprops", prop)
			end
			ply:AddCount("animprops", prop)
		end

		oldent:Remove()

		DoPropSpawnedEffect(prop)
		return prop

	end

end

//Cleanup and limit
cleanup.Register("animprops")
if SERVER then
	CreateConVar("sbox_maxanimprops", "8", {FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED}, "Maximum animated props a single player can create")
end

//Draw name and position of selected bones if editor window's remapping tab is open
//And the award for ugliest nested "if x then" checks goes to...
if CLIENT then
	hook.Add("HUDPaint", "AnimProp_HUDPaint_DrawRemappingBones", function()
		if g_ContextMenu and g_ContextMenu:IsVisible() then
			for _, window in pairs(animpropwindows) do
				if window.Control and window.Control.TabPanel and window.Control.TabPanel:GetActiveTab():GetText() == "Remapping" then

					local ent = window.Control.m_Entity
					if IsValid(ent) then
						local ent2 = ent:GetPuppeteer()
						if IsValid(ent2) then

							local back = window.Control.Remapping
							if back and back.BoneList then
								local id1 = back.BoneList.selectedbone
								local id2 = -1
								local targetbonestr = ent.RemapInfo[id1]["parent"]
								if targetbonestr != "" then id2 = ent2:LookupBone(targetbonestr) end

								local function DrawBonePos(_ent, id)
									local _pos = nil
									local matr = _ent:GetBoneMatrix(id)
									if matr then 
										_pos = matr:GetTranslation() 
									else
										_pos = _ent:GetBonePosition(id) 
									end
									_name = _ent:GetBoneName(id)

									if !_pos then return end
									local _pos = _pos:ToScreen()
									local textpos = {x = _pos.x+5,y = _pos.y-5}

									draw.RoundedBox(0,_pos.x - 2,_pos.y - 2,4,4,Color(0,0,0,255))
									draw.RoundedBox(0,_pos.x - 1,_pos.y - 1,2,2,Color(255,255,255,255))
									draw.SimpleTextOutlined(_name,"Default",textpos.x,textpos.y,Color(255,255,255,255),TEXT_ALIGN_LEFT,TEXT_ALIGN_BOTTOM,1,Color(0,0,0,255))
								end
								DrawBonePos(ent, id1)
								if id2 != -1 then
									DrawBonePos(ent2, id2)
								end
							end

						end
					end

				end
			end
		end
	end)
end

//Keepupright constraint variant (from lua/includes/modules/constraint.lua) for prop_animated, to get around its restriction to prop_physics only
function Keepupright_animprop( Ent, Ang, Bone, angularlimit )

	if CLIENT then return end

	if ( !constraint.CanConstrain( Ent, Bone ) ) then return false end
	if ( Ent:GetClass() != "prop_animated" ) then return false end
	if ( !angularlimit or angularlimit < 0 ) then return end

	local Phys = Ent:GetPhysicsObjectNum( Bone )

	-- Remove any KU's already on entity
	constraint.RemoveConstraints( Ent, "Keepupright_animprop" )

	//onStartConstraint( Ent )

	local Constraint = ents.Create( "phys_keepupright" )
	//ConstraintCreated( Constraint )
	Constraint:SetAngles( Ang )
	Constraint:SetKeyValue( "angularlimit", angularlimit )
	Constraint:SetPhysConstraintObjects( Phys, Phys )
	Constraint:Spawn()
	Constraint:Activate()

	//onFinishConstraint( Ent )
	constraint.AddConstraintTable( Ent, Constraint )

	local ctable = {
		Type = "Keepupright_animprop",
		Ent1 = Ent,
		Ang = Ang,
		Bone = Bone,
		angularlimit = angularlimit
	}
	Constraint:SetTable( ctable )

	--
	-- This is a hack to keep the KeepUpright context menu in sync..
	--
	Ent:SetNWBool( "IsUpright", true )

	return Constraint

end
if SERVER then
	duplicator.RegisterConstraint( "Keepupright_animprop", Keepupright_animprop, "Ent1", "Ang", "Bone", "angularlimit" )
end

//Copy of lua/autorun/properties/keep_upright.lua, but with references to prop_physics replaced with prop_animated
properties.Add( "keepupright_animprop", {
	MenuLabel = "#keepupright",
	Order = 900,
	MenuIcon = "icon16/arrow_up.png",

	Filter = function( self, ent, ply )

		if ( !IsValid( ent ) ) then return false end
		if ( ent:GetClass() != "prop_animated" ) then return false end
		if ( ent:GetNWBool( "IsUpright" ) ) then return false end
		if ( !gamemode.Call( "CanProperty", ply, "keepupright", ent ) ) then return false end
		if ( !gamemode.Call( "CanProperty", ply, "keepupright_animprop", ent ) ) then return false end

		return true
	end,

	Action = function( self, ent )

		self:MsgStart()
			net.WriteEntity( ent )
		self:MsgEnd()

	end,

	Receive = function( self, length, ply )

		local ent = net.ReadEntity()

		if ( !IsValid( ent ) ) then return end
		if ( !IsValid( ply ) ) then return end
		if ( !properties.CanBeTargeted( ent, ply ) ) then return end
		if ( ent:GetClass() != "prop_animated" ) then return end
		if ( ent:GetNWBool( "IsUpright" ) ) then return end
		if ( !self:Filter( ent, ply ) ) then return end

		local Phys = ent:GetPhysicsObjectNum( 0 )
		if ( !IsValid( Phys ) ) then return end

		local constraint = Keepupright_animprop( ent, Phys:GetAngles(), 0, 999999 )

		-- I feel like this is not stable enough
		-- This cannot be implemented without a custom constraint.Keepupright function or modification for proper duplicator support.
		--print( constraint:GetSaveTable().m_worldGoalAxis )
		--constraint:SetSaveValue( "m_localTestAxis", constraint:GetSaveTable().m_worldGoalAxis ) --ent:GetAngles():Up() )
		--constraint:SetSaveValue( "m_worldGoalAxis", Vector( 0, 0, 1 ) )
		--constraint:SetSaveValue( "m_bDampAllRotation", true )

		if ( constraint ) then

			ply:AddCleanup( "constraints", constraint )
			ent:SetNWBool( "IsUpright", true )

		end

	end

} )

properties.Add( "keepupright_animprop_stop", {
	MenuLabel = "#keepupright_stop",
	Order = 900,
	MenuIcon = "icon16/arrow_rotate_clockwise.png",

	Filter = function( self, ent )
		if ( !IsValid( ent ) ) then return false end
		if ( ent:GetClass() != "prop_animated" ) then return false end
		if ( !ent:GetNWBool( "IsUpright" ) ) then return false end
		return true
	end,

	Action = function( self, ent )

		self:MsgStart()
			net.WriteEntity( ent )
		self:MsgEnd()

	end,

	Receive = function( self, length, ply )

		local ent = net.ReadEntity()

		if ( !IsValid( ent ) ) then return end
		if ( !IsValid( ply ) ) then return end
		if ( !properties.CanBeTargeted( ent, ply ) ) then return end
		if ( ent:GetClass() != "prop_animated" ) then return end
		if ( !ent:GetNWBool( "IsUpright" ) ) then return end

		constraint.RemoveConstraints( ent, "Keepupright_animprop" )

		ent:SetNWBool( "IsUpright", false )

	end

} )

//Add a convar to show physboxes to the context menu's menubar
if CLIENT then
	CreateClientConVar("cl_animprop_drawphysboxes", "0", true, false, "Should animated props draw their physics box?", 0, 1)

	hook.Add("PopulateMenuBar", "zzz_Animprop_MenuBar", function(menubar)
		local m = menubar:AddOrGetMenu("#menubar.drawing")
		m:AddSpacer()
		m:AddCVar("Draw Animated Prop Physics Boxes", "cl_animprop_drawphysboxes", "1", "0")
	end)
end