AddCSLuaFile()

ENT.Base 			= "base_gmodentity"
ENT.PrintName			= "Animated Prop"

ENT.Spawnable			= false
ENT.AdminSpawnable		= false

ENT.Type			= "ai" //was necessary for working animation layers
//ENT.Type			= "anim" //apparently has working animation layers as of 2-26-18 update, but when tested, a couple other things (collisions, eyes) need fixing with no noticeable benefits, so i think we'll stick with ai for now
ENT.AutomaticFrameAdvance	= true
ENT.RenderGroup			= false //let the engine set the rendergroup by itself

//prevent ukplayer from interacting with animprops like npcs instead of props
ENT.UK_NoDashSlideThru		= true
ENT.UK_OverrideAllowWallJump	= true

if CLIENT then
	killicon.AddAlias("prop_animated", "prop_physics")
	language.Add("Undone_Animprop", "Undone Animated Prop")
	language.Add("prop_animated", "Animated Prop")  //for killfeed notices
    	language.Add("Cleanup_animprops", "Animated Props")
   	language.Add("Cleaned_animprops", "Cleaned up all Animated Props")
	language.Add("SBoxLimit_animprops", "You've hit the Animated Prop limit!")
   	language.Add("max_animprops", "Max Animated Props:")
end

//For ragdollize-on-damage PhysicsCollide damage (physics damage isn't actually implemented on scripted entities or npcs by default, we have to recreate the valve code from scratch)
local phys_impactforcescale
local phys_upimpactforcescale
local dmgTable
local ReadDamageTable
if SERVER then
	phys_impactforcescale = GetConVar("phys_impactforcescale")
	phys_upimpactforcescale = GetConVar("phys_upimpactforcescale")

	//Physics impact damage from (https://github.com/ValveSoftware/source-sdk-2013/blob/master/mp/src/game/server/physics_impact_damage.cpp#L107); this is probably completely overkill since the 
	//animprop only has 1 health, but we already had the table sitting around from a scrapped project, and this way players get to see cool big damage numbers when they hit us with props real hard.
	dmgTable = {
		linearTable = {
			{ impulse = 150*150, damage = 5, },
			{ impulse = 250*250, damage = 10 },
			{ impulse = 350*350, damage = 50 },
			{ impulse = 500*500, damage = 100 },
			{ impulse = 1000*1000, damage = 500 }
		},
		angularTable = {
			{ impulse = 100*100, damage = 10 },
			{ impulse = 150*150, damage = 25 },
			{ impulse = 200*200, damage = 50 },
			{ impulse = 250*250, damage = 500 },
		},
	
		minSpeedSqr = 24*24,		//minimum linear speed squared
		minRotSpeedSqr =  360*360,	//minimum angular speed squared (360 deg/s to cause spin/slice damage)
		minMass = 2,			//can't take damage from anything under 2kg
	
		smallMassMax = 5,		//anything less than 5kg is "small"
		smallMassCap = 5,		//never take more than 5 pts of damage from anything under 5kg
		smallMassMinSpeedSqr = 36*36,	//<5kg objects must go faster than 36 in/s to do damage
	
		largeMassMin = 500,		//large mass in kg 
		largeMassScale = 4,		//large mass scale (anything over 500kg does 4X as much energy to read from damage table)
		largeMassFallingScale = 5,	//large mass falling scale (emphasize falling/crushing damage over sideways impacts since the stress will kill you anyway)
		myMinVelocity = 0,		//min vel
	}

	ReadDamageTable = function(tab, energy)
		if tab then
			local damage = 0
			for _, subtable in SortedPairs(tab) do
				if subtable.impulse <= energy then
					damage = subtable.damage
				end
			end
			return damage
		end
	end

	function ENT:PhysicsCollide(data)
		//Based loosely off CBaseCombatCharacter::VPhysicsShadowCollision (https://github.com/ValveSoftware/source-sdk-2013/blob/master/mp/src/game/server/basecombatcharacter.cpp#L3080)
		//That function is the one used by standard NPCs, not physics objects, so it has a bunch of criteria that we don't want, like not taking collision damage non-vphysics objects, 
		//frozen objects, or the world.
		if !IsValid(self) then return end
		if !self:GetRagdollizeOnDamage() then return end

		local damageType = DMG_CRUSH
		//Based off CalculatePhysicsImpactDamage (https://github.com/ValveSoftware/source-sdk-2013/blob/master/mp/src/game/server/physics_impact_damage.cpp#L249)
		local function CalculatePhysicsImpactDamage()
			local energyScale = 1
			local allowStaticDamage = true

			//Take dissolve damage from combine balls (we do this a little differently from the valve code - we always have EFL_NO_DISSOLVE set, 
			//so that the prop itself doesn't get dissolved, but then we take dissolve damage here anyway, so that the ragdoll does)
			if data.HitObject:HasGameFlag(FVPHYSICS_DMG_DISSOLVE) then
				damageType = DMG_DISSOLVE
				return 1000
			end

			//Don't take damage if they're a non-moving object due to a constraint, or if they're just set not to deal impact damage
			if data.HitObject:HasGameFlag(FVPHYSICS_CONSTRAINT_STATIC) or data.HitObject:HasGameFlag(FVPHYSICS_NO_IMPACT_DMG) then
				return 0
			end
			//Don't take damage from held objects (use key, gravity gun, physgun)
			if data.HitObject:HasGameFlag(FVPHYSICS_PLAYER_HELD) then
				return 0
			end
			//If they're a multi-object entity like a ragdoll or vehicle, then don't take damage if ANY of their physobjs are set not to deal impact damage
			if data.HitObject:HasGameFlag(FVPHYSICS_MULTIOBJECT_ENTITY) then
				for i = 0, data.HitEntity:GetPhysicsObjectCount() - 1 do
					local phys = data.HitEntity:GetPhysicsObjectNum(i)
					if phys:HasGameFlag(FVPHYSICS_CONSTRAINT_STATIC) or phys:HasGameFlag(FVPHYSICS_NO_IMPACT_DMG) then
						return 0
					end
				end
			end
			//Don't take damage from players or the world (static damage) if we're being held
			if data.PhysObject:HasGameFlag(FVPHYSICS_PLAYER_HELD) then
				if data.HitEntity:IsPlayer() then
					return 0
				end
				allowStaticDamage = false
			end

			local otherSpeedSqr = data.TheirOldVelocity:LengthSqr()
			local otherAngSqr = 0
			//Only factor in angular velocity when we're colliding with 'sharp' objects (things marked specifically as dealing this sort of damage, like whirling fanblades)
			if data.HitObject:HasGameFlag(FVPHYSICS_DMG_SLICE) then
				otherAngSqr = data.TheirOldAngularVelocity:LengthSqr()
			end
			local otherMass = data.HitObject:GetMass()
			//If they're a multi-object entity then get their total mass for the purpose of damage
			if data.HitObject:HasGameFlag(FVPHYSICS_MULTIOBJECT_ENTITY) then
				local mass = 0
				for i = 0, data.HitEntity:GetPhysicsObjectCount() - 1 do
					local phys = data.HitEntity:GetPhysicsObjectNum(i)
					mass = (mass + phys:GetMass())
				end
				otherMass = mass
			end
			//If they're flagged as a 'heavy' object then override the mass and exaggerate the energy scale - what actually uses this?
			if data.HitObject:HasGameFlag(FVPHYSICS_HEAVY_OBJECT) then
				otherMass = dmgTable.largeMassMin
				//if energyScale < 2 then
					energyScale = 2
				//end
			end
			if !allowStaticDamage then
				if otherMass < dmgTable.minMass then return 0 end
				if otherMass < dmgTable.smallMassMax and otherSpeedSqr < dmgTable.smallMassMinSpeedSqr then return 0 end
				if otherSpeedSqr < dmgTable.minSpeedSqr and otherAngSqr < dmgTable.minRotSpeedSqr then return 0 end
			end
			//"Add extra oomph for floating objects"
			if self:WaterLevel() > 0 and !(data.HitEntity:IsWorld()) then
				if energyScale < 3 then
					energyScale = 3
				end
			end


			local damage = 0

			//Take angular damage (if enabled) from them if they're spinning fast enough
			if otherAngSqr > dmgTable.minRotSpeedSqr then
				local otherInertia = data.HitObject:GetInertia()

				local vel = data.TheirOldAngularVelocity
				local angularMomentum = math.abs(otherInertia.x*vel.x) + math.abs(otherInertia.y*vel.y) + math.abs(otherInertia.z*vel.z) //vec_t DotProductAbs (https://github.com/ValveSoftware/source-sdk-2013/blob/master/mp/src/public/mathlib/vector.h#L1223)

				damage = ReadDamageTable(dmgTable.angularTable, angularMomentum * energyScale)
				if damage > 0 then
					damageType = bit.bor(damageType, DMG_SLASH)
				end
			end

			local deltaV = data.OurOldVelocity:Length() - data.OurNewVelocity:Length()
			local mass = data.PhysObject:GetMass()
			//If I lost speed, and I lost less than min velocity, then filter out this energy
			if deltaV > 0 and deltaV < dmgTable.myMinVelocity then
				deltaV = 0
			end
			local eliminatedEnergy = deltaV * deltaV * mass
			deltaV = data.TheirOldVelocity:Length() - data.TheirNewVelocity:Length()
			otherEliminatedEnergy = deltaV * deltaV * otherMass

			//Esaggerate the effects of really large objects
			if otherMass >= dmgTable.largeMassMin then
				otherEliminatedEnergy = otherEliminatedEnergy * dmgTable.largeMassScale
				local dz = data.TheirOldVelocity.z - data.TheirNewVelocity.z
				if deltaV > 0 and dz < 0 and data.TheirOldVelocity.z < 0 then
					local factor = math.abs(dz / deltaV)
					otherEliminatedEnergy = otherEliminatedEnergy * (1 + factor * (dmgTable.largeMassFallingScale - 1))
				end
			end
			eliminatedEnergy = eliminatedEnergy + otherEliminatedEnergy

			//"now in units of this character's speed squared"
			local invMass = data.PhysObject:GetInvMass()
			if !data.PhysObject:IsMoveable() then
				invMass = 1 / data.PhysObject:GetMass()
			end
			//note: valve code here retrieves the "real" mass of our object if it's being held by a player, but i dont think we have a way to retrieve that in lua
			eliminatedEnergy = eliminatedEnergy * (invMass * energyScale)
			damage = damage + ReadDamageTable(dmgTable.linearTable, eliminatedEnergy)
			//Don't take more than a certain amount of damage from really small objects
			if !(data.HitEntity:IsWorld() or data.HitEntity:IsFlagSet(FL_STATICPROP)) then //valve code here checks if data.HitObject:IsStatic(), which isn't anything in lua. seems to make sure we can still take damage from stuff like the world, which has 1 mass but obviously shouldn't count as small. TODO: is there anything else we should be checking for here?
				if otherMass < dmgTable.smallMassMax and dmgTable.smallMassCap > 0 then
					damage = math.Clamp(damage, 0, dmgTable.smallMassCap)
				end
			end

			return damage
		end
		local damage = CalculatePhysicsImpactDamage()

		if damage <= 0 then return end

		local damageForce = data.OurNewVelocity * data.PhysObject:GetMass() * phys_impactforcescale:GetFloat()
		if damageForce == Vector(0,0,0) then  //If we're immovable then get the velocity of the object that hit us instead, this sucks bad but it's better than nothing
			damageForce = data.TheirNewVelocity * data.HitObject:GetMass() * phys_impactforcescale:GetFloat()
		end
		//if hit by vehicle driven by player, add some upward velocity to force
		if data.HitEntity:IsVehicle() and IsValid(data.HitEntity:GetPassenger(0)) then
			damageType = bit.bor(damageType, DMG_VEHICLE)
			local len = damageForce:Length()
			damageForce.z = damageForce.z + (len*phys_upimpactforcescale:GetFloat())
		end

		local dmgInfo = DamageInfo()
		dmgInfo:SetAttacker(data.HitEntity)
		dmgInfo:SetInflictor(data.HitEntity)
		dmgInfo:SetDamageForce(damageForce)
		dmgInfo:SetDamagePosition(data.HitPos)
		dmgInfo:SetDamage(damage)
		dmgInfo:SetDamageType(damageType)
		local player = data.HitEntity:GetPhysicsAttacker()
		if IsValid(player) then
			dmgInfo:SetAttacker(player)
		end
		//valve code here sets m_nForceBone = 0; we should have this too since we'll be taking damage but not calling the trace damage func

		data.PhysObject:EnableMotion(true)
		self:TakeDamageInfo(dmgInfo)
	end
end




function ENT:SetupDataTables()

	self:NetworkVar("Int", 0, "Channel1Sequence")
	self:NetworkVar("Bool", 0, "Channel1Pause")
	self:NetworkVar("Float", 0, "Channel1PauseFrame")
	self:NetworkVar("Float", 1, "Channel1Speed")
	self:NetworkVar("Int", 1, "Channel1LoopMode")
	self:NetworkVar("Float", 2, "Channel1LoopDelay")
	self:NetworkVar("Int", 2, "Channel1Numpad")
	self:NetworkVar("Bool", 1, "Channel1NumpadToggle")
	self:NetworkVar("Bool", 2, "Channel1NumpadStartOn")
	self:NetworkVar("Int", 3, "Channel1NumpadMode")
	self:NetworkVar("Float", 3, "Channel1StartPoint")
	self:NetworkVar("Float", 4, "Channel1EndPoint")

	self:NetworkVar("Int", 4, "Channel2Sequence")
	self:NetworkVar("Bool", 3, "Channel2Pause")
	self:NetworkVar("Float", 5, "Channel2PauseFrame")
	self:NetworkVar("Float", 6, "Channel2Speed")
	self:NetworkVar("Int", 5, "Channel2LoopMode")
	self:NetworkVar("Float", 7, "Channel2LoopDelay")
	self:NetworkVar("Int", 6, "Channel2Numpad")
	self:NetworkVar("Bool", 4, "Channel2NumpadToggle")
	self:NetworkVar("Bool", 5, "Channel2NumpadStartOn")
	self:NetworkVar("Int", 7, "Channel2NumpadMode")
	self:NetworkVar("Float", 8, "Channel2StartPoint")
	self:NetworkVar("Float", 9, "Channel2EndPoint")

	self:NetworkVar("Int", 8, "Channel3Sequence")
	self:NetworkVar("Bool", 6, "Channel3Pause")
	self:NetworkVar("Float", 10, "Channel3PauseFrame")
	self:NetworkVar("Float", 11, "Channel3Speed")
	self:NetworkVar("Int", 9, "Channel3LoopMode")
	self:NetworkVar("Float", 12, "Channel3LoopDelay")
	self:NetworkVar("Int", 10, "Channel3Numpad")
	self:NetworkVar("Bool", 7, "Channel3NumpadToggle")
	self:NetworkVar("Bool", 8, "Channel3NumpadStartOn")
	self:NetworkVar("Int", 11, "Channel3NumpadMode")
	self:NetworkVar("Float", 13, "Channel3StartPoint")
	self:NetworkVar("Float", 14, "Channel3EndPoint")

	self:NetworkVar("Int", 12, "Channel4Sequence")
	self:NetworkVar("Bool", 9, "Channel4Pause")
	self:NetworkVar("Float", 15, "Channel4PauseFrame")
	self:NetworkVar("Float", 16, "Channel4Speed")
	self:NetworkVar("Int", 13, "Channel4LoopMode")
	self:NetworkVar("Float", 17, "Channel4LoopDelay")
	self:NetworkVar("Int", 14, "Channel4Numpad")
	self:NetworkVar("Bool", 10, "Channel4NumpadToggle")
	self:NetworkVar("Bool", 11, "Channel4NumpadStartOn")
	self:NetworkVar("Int", 15, "Channel4NumpadMode")
	self:NetworkVar("Float", 18, "Channel4StartPoint")
	self:NetworkVar("Float", 19, "Channel4EndPoint")

	self:NetworkVar("Int", 16, "Channel2LayerID")
	self:NetworkVar("Int", 17, "Channel3LayerID")
	self:NetworkVar("Int", 18, "Channel4LayerID")
	//Squish LayerBlendIn, LayerBlendOut, and LayerWeight into a vector together to save on nwvar floats
	self:NetworkVar("Vector", 0, "Channel2LayerSettings")
	self:NetworkVar("Vector", 1, "Channel3LayerSettings")
	self:NetworkVar("Vector", 2, "Channel4LayerSettings")

	self:NetworkVar("Bool", 12, "Channel1NumpadState")
	self:NetworkVar("Bool", 13, "Channel2NumpadState")
	self:NetworkVar("Bool", 14, "Channel3NumpadState")
	self:NetworkVar("Bool", 15, "Channel4NumpadState")

	self:NetworkVar("Bool", 16, "ControlMovementPoseParams")

	self:NetworkVar("Int", 19, "PhysicsMode")
	self:NetworkVar("Bool", 17, "NoPhysicsBelowOrigin")

	self:NetworkVar("Bool", 18, "EnableAnimEventEffects")
	self:NetworkVar("Bool", 19, "RagdollizeOnDamage")
	self:NetworkVar("Entity", 0, "DeathRagdoll")

	self:NetworkVar("Entity", 1, "Puppeteer")
	self:NetworkVar("Bool", 20, "PuppeteerAlpha")
	self:NetworkVar("Vector", 3, "PuppeteerPos")

end




function ENT:Initialize()

	if SERVER then

		//Set up tables used for animation looping
		self.AnimNextStop = {
			[1] = -1,
			[2] = -1,
			[3] = -1,
			[4] = -1,
		}
		self.AnimNextLoop = {
			[1] = -1,
			[2] = -1,
			[3] = -1,
			[4] = -1,
		}

		for i = 2, 4 do
			self["SetChannel" .. i .. "LayerID"](self, -1)
		end

		//Set up physics
		self:UpdateAnimpropPhysics()
		self.ThinkUpdateAnimpropPhysicsTime = 0
		self.CurModelScale = self:GetModelScale()

		//Set up numpad controls
		for i = 1, 4 do
			//Numpad states should always start off as false
			self["SetChannel" .. i .. "NumpadState"](self, false)

			//Different from NumpadState. These values are always true when the key is held down and false when it's not, even if the numpad state is set to toggle instead.
			//Used when changing the numpadkey or numpadtoggle vars to make sure stuff doesn't cause problems.
			self["NumpadKeyDown" .. i] = false

			//Set up numpad functions
			local ply = self:GetPlayer() //NOTE: this still works if ply doesn't exist
			local key = self["GetChannel" .. i .. "Numpad"](self)
			self["NumDown" .. i] = numpad.OnDown(ply, key, "Animprop_Numpad", self, i, true)
			self["NumUp" .. i] = numpad.OnUp(ply, key, "Animprop_Numpad", self, i, false)
		end

		//If we're a newly spawned animprop, then have the player who spawned us open the clientside edit menu now that we're done spawning.
		if self.EditMenuPlayer then
			//Delay this slightly, or the entity won't be valid yet on clients in multiplayer
			timer.Simple(0.1, function()
				if IsValid(self) then
					net.Start("AnimProp_OpenEditMenu_SendToCl")
						net.WriteEntity(self)
					net.Send(self.EditMenuPlayer)

					//Don't do this again if we're pasted from a save or dupe
					self.EditMenuPlayer = nil
				end
			end)
		end

		//Tell the think function to set up pose parameters and anything else we can't set up here for whatever reason
		self.SetupInThink = true

		//Use FollowBone hack on self to fix an edge case where if an animprop is bonemanipped by something other than the advbone tool (i.e. ragdollize with resize, other addons), then once 
		//it starts doing the expensive version of BuildBonePositions, if the animprop is paused, moved offscreen, then goes to sleep offscreen. a bunch of bones like detail props and fingers 
		//will appear in bad places (the last places they were when the model was rendered onscreen)
		local lol = ents.Create("base_point")
		if IsValid(lol) then
			lol:SetPos(self:GetPos())
			lol:SetAngles(self:GetAngles())
			lol:FollowBone(self,0)
			lol:Spawn()
			lol:Remove() //We don't need the ent to stick around. All we needed was for it to use FollowBone once.
		end

		//(Advanced Bonemerge) Create a serverside boneinfo table if we don't have one already
		if !self.AdvBone_BoneInfo then
			self:CreateAdvBoneInfoTable(nil, false)
		end

		//Do physics collision damage stuff for ragdollize-on-damage
		self:AddEFlags(EFL_NO_DISSOLVE)
		self:AddCallback("PhysicsCollide", self.PhysicsCollide)

	else

		self.GripMaterial = Material("sprites/grip")
		self.GripMaterialHover = Material("sprites/grip_hover")

		self:SetLOD(0)
		self:SetupBones()
		self:InvalidateBoneCache()

		//Check if we can do the in-code tf2 minigun spin animation (this'll break if the model is changed via model manipulator or something, but it's not worth the effort to fix)
		if self:LookupBone("barrel") and self:LookupSequence("fire_loop") >= 0 then
			self.MinigunAnimBone = self:LookupBone("barrel")
			self.MinigunAnimSpeed = 0
			self.MinigunAnimAngle = 0
		end

		self:DoAdvBonemerge()

		self.RagdollizeDoManips = true //store these as clientside vars, don't bother networking or saving them to dupes, it's not important
		self.RagdollizeUseRagdollResizer = tobool(duplicator.FindEntityClass("prop_resizedragdoll_physparent"))

	end

	//NOTE: This was disabled due to bugs (see Think func), but is included for reference in case the bugs are fixed
	--[[//this makes clientside traces like properties work anywhere you click on a hitbox, instead of requiring an overlap of both the collision bounds and hitboxes. 
	//this is a lot better in most cases because it fixes the editor window being hard to open for some models and most effects. doesn't effect toolgun or physgun.
	if self:GetHitBoxCount(0) > 0 and self:GetBoneName(0) != "static_prop" then //don't let this run if the model has 0 hitboxes, or it'll break everything on clients; also don't run it on static props, because it either doesn't do anything or actually breaks physgun hit detection like on HL2 bridges (note that SetSurroundingBounds doesn't work on them either)
		self:SetSurroundingBoundsType(BOUNDS_HITBOXES)
	end]]

end




//Ignore certain non-physics constraints for effect physics
local ConstraintsToPreserve = {
	["AdvBoneMerge"] = true,
	["AttachParticleControllerBeam"] = true, //Advanced Particle Controller addon
	["PartCtrl_Ent"] = true, //ParticleControlOverhaul
	["PartCtrl_SpecialEffect"] = true, //ParticleControlOverhaul
	["BoneMerge"] = true, //Bone Merger addon
	["EasyBonemerge"] = true, //Easy Bonemerge Tool addon
	["CompositeEntities_Constraint"] = true, //Composite Bonemerge addon
}

function ENT:Think()

	if SERVER then

		local time = CurTime()


		//Set up a few things here instead of in Initialize.
		//If we do these in Initialize, the entity won't exist clientside yet, and clients will receive the changes but discard them.
		if self.SetupInThink then
			//Set up pose parameters
			if !self.PoseParams then self.PoseParams = {} end
			for i = 0, self:GetNumPoseParameters() - 1 do
				local name = self:GetPoseParameterName(i)
				if !self.PoseParams[i] then
					local default = self:GetPoseParameter(name)
					if name == "move_x" or name == "move_scale" then
						default = 1
						self:SetPoseParameter(name, default)
					end
					self.PoseParams[i] = default
				else
					self:SetPoseParameter(name, self.PoseParams[i])
				end
			end

			//Send saved eyetarget to clients if we've got one
			if self.EyeTargetLocal then
				net.Start("AnimProp_EyeTargetLocal_SendToCl")
					net.WriteEntity(self)
					net.WriteVector(self.EyeTargetLocal)
				net.Broadcast()
			end
			
			self.SetupInThink = nil
		end


		//If the player changed the model scale, then update physics
		local scale = self:GetModelScale()
		if scale != self.CurModelScale then
			if scale == 1 then
				self:SetModelScale(1.0000001)
			//In multiplayer, don't let players make props too big or small and grief the server
			//We hard cap scale at 16 to avoid a physics bug that can cause the game to freeze - past this point, the performance impact of moving a prop around starts to increase exponentially with its scale (check +showbudget), to the point where setting any model's scale to about 50 or so will reduce the game to multiple seconds per frame.
			//TODO: I'm not sure what's causing this bug, I thought it was mass-based (smaller models like the HL2 grenade need higher scale values to start bugging out, while something like the TF2 crate starts chugging even at 16), but the differences between models also apply to effects even though they should all have identical physobjs, and even changing effect physobjs to not scale with the model STILL results in this bug happening, so what's even going on here? This probably isn't the best way to check for this.
			elseif !game.SinglePlayer() then
				if scale > 16 then
					self:SetModelScale(16)
				elseif scale < 0.05 then
					self:SetModelScale(0.05)
				end
			end
			self.ThinkUpdateAnimpropPhysics = true
			self.CurModelScale = self:GetModelScale()

			//Advanced Bonemerge: We're updating the prop's bone positions, make sure BuildBonePositions starts running again
			AdvBone_ResetBoneChangeTime(self)
		end


		//Update physics
		if self.ThinkUpdateAnimpropPhysics and time >= self.ThinkUpdateAnimpropPhysicsTime then
			self:UpdateAnimpropPhysics()
			self.ThinkUpdateAnimpropPhysics = false
			self.ThinkUpdateAnimpropPhysicsTime = time + 0.35 //throttle physics updates so they don't update a ton of times whenever someone uses the scale slider
		end


		//Effect physics (ai ents don't run ENT:PhysicsUpdate() so we have to do it here)
		if self:GetPhysicsMode() == 2 then
			local phys = self:GetPhysicsObject()
			if IsValid(phys) and !phys:IsAsleep() and !self:IsPlayerHolding() then //and !self:IsConstrained() then
				local constrained = false
				for k, v in pairs (constraint.GetTable(self)) do
					if !ConstraintsToPreserve[v.Type] then
						constrained = true
						break
					end
				end
				if !constrained then
					phys:SetVelocity(vector_origin)
					phys:AddAngleVelocity( -(phys:GetAngleVelocity()) ) //since SetAngleVelocity doesn't exist
					phys:Sleep() //this doesn't work well when called in think; the position of the physobj can get out of sync with the entity visuals if it was moving
					//phys:EnableMotion(false)
					//calling phys:Sleep() in think can cause the position of the physobj to get out of sync with the entity visuals if it was moving, so let's fix that
					phys:SetPos(self:GetPos())
					phys:SetAngles(self:GetAngles())
				end
			end
		end


		//Loop the animation channels
		for i = 1, 4 do

			//If we were just spawned then start off all the animation channels
			if self.AnimNextLoop[i] == -1 then
				self.AnimNextStop[i] = 0
				self.AnimNextLoop[i] = 0
				self:StartAnimation(i)
			end

			local seq = self["GetChannel" .. i .. "Sequence"](self)

			local numpadisdisabling = false
			if self["GetChannel" .. i .. "NumpadMode"](self) == 0 then
				numpadisdisabling = self["GetChannel" .. i .. "NumpadState"](self)
				if !self["GetChannel" .. i .. "NumpadStartOn"](self) then
					numpadisdisabling = !numpadisdisabling
				end
			end

			if !(seq <= 0)								//not an invalid animation
			and self:SequenceDuration(seq) > 0					//not a single-frame animation
			and !self["GetChannel" .. i .. "Pause"](self)				//not paused
			and !numpadisdisabling  						//not disabled by numpad
			and (self["GetChannel" .. i .. "Speed"](self) != 0) then		//not at 0 speed

				if self["GetChannel" .. i .. "LoopMode"](self) > 0 and time >= self.AnimNextLoop[i] then

					//Restart the animation
					self:StartAnimation(i)

				elseif time >= self.AnimNextStop[i] then

					//End any animations that are still playing but shouldn't be
					if i == 1 then
						if self:GetPlaybackRate() != 0 then
							self:SetPlaybackRate(0)
							if self["GetChannel" .. i .. "Speed"](self) >= 0 then
								self:SetCycle(self["GetChannel" .. i .. "EndPoint"](self))
							else
								self:SetCycle(self["GetChannel" .. i .. "StartPoint"](self))
							end
						end
					else
						local id = self["GetChannel" .. i .. "LayerID"](self)
						if id != -1 and self:IsValidLayer(id) then
							if self:GetLayerPlaybackRate(id) != 0 then
								self:SetLayerPlaybackRate(id, 0)
								self:SetLayerWeight(id, 0)
								self:SetLayerBlendIn(id, 0)
								self:SetLayerBlendOut(id, 0)
								if self["GetChannel" .. i .. "Speed"](self) >= 0 then
									self:SetLayerCycle(id, self["GetChannel" .. i .. "EndPoint"](self))
								else
									self:SetLayerCycle(id, self["GetChannel" .. i .. "StartPoint"](self))
								end
							end
						end
					end

				end

			end

		end


		//(Advanced Bonemerge) If we had to give our parent entity a placeholder name to get our lighting origin to work properly (see advbonemerge constraint function), then remove it here
		local parent = self:GetParent()
		if IsValid(parent) and parent.AdvBone_PlaceholderName then
			//unlike ent_advbonemerge, we have to do this on a timer or else the lighting origin change might not have been applied yet 
			//(issue only applies to pre-existing prop_animated ents being attached, not to dupes that are attached as soon as they spawn)
			timer.Simple(0.1, function()
				if IsValid(parent) then
					parent:SetName("")
				end
			end)
			parent.AdvBone_PlaceholderName = nil
		end


		//Detect whether we're in the 3D skybox, and network that to clients to use in the Draw function because they can't detect it themselves
		//(sky_camera ent is serverside only and ent:IsEFlagSet(EFL_IN_SKYBOX) always returns false)
		local skycamera = ents.FindByClass("sky_camera")
		if istable(skycamera) then skycamera = skycamera[1] end
		if IsValid(skycamera) then
			local inskybox = self:TestPVS(skycamera)
			if self:GetNWBool("IsInSkybox") != inskybox then
				self:SetNWBool("IsInSkybox", inskybox)
			end
		end


		//If we want to ragdollize on damage, then make sure we have a health value, because some sources of damage check for this before actually inflicting damage (example: hl1 sweps crossbow)
		if self:GetRagdollizeOnDamage() then
			self:SetMaxHealth(1)
			self:SetHealth(1)
		else
			self:SetMaxHealth(0)
			self:SetHealth(0)
		end
		//there's an edge case where if a prop gets killed offscreen, and ply can't run ragdollize (doesn't have the boneinfo table yet?), the prop stays alive, but
		//because the above table exists, the ragdollize-on-damage is still queued up and will kill the prop as soon as someone tries to run ragdollize normally. this is silly
		//and isn't a big deal but should probably be fixed anyway. clobber the table after a bit so that it doesn't stay queued up forever.
		if self.DoRagdollizeOnDamage and time >= self.DoRagdollizeOnDamage.time then
			self.DoRagdollizeOnDamage = nil
		end


		//Control movement pose parameters
		local sequence = self:GetChannel1Sequence()
		local playbackrate = self:GetChannel1Speed()

		if self:GetControlMovementPoseParams() then

			//First set all the pose params to 0, because otherwise GetSequenceGroundSpeed returns the wrong number
			self:SetPoseParameter("move_x", 0)
			self:SetPoseParameter("move_y", 0)
			self:SetPoseParameter("move_yaw", 0)
			self:SetPoseParameter("move_scale", 0)

			local speed = self:GetSequenceGroundSpeed(sequence)
			if speed == 0 then
				speed = 300  //totally arbitrary fallback value
			end
			speed = Vector(speed,speed,speed)
			speed = speed * playbackrate * self:GetModelScale() * self:GetManipulateBoneScale(-1)
			//make sure we don't divide the velocity by 0
			if speed.x == 0 then speed.x = 1 end
			if speed.y == 0 then speed.y = 1 end
			if speed.z == 0 then speed.z = 1 end

			local vel = nil
			if IsValid(self:GetParent()) then
				vel = self:GetParent():GetVelocity()
			else
				vel = self:GetVelocity()
			end
			local ang = self:GetAngles()
			local localvel = Vector( vel:Dot(ang:Forward()) / speed.x, -vel:Dot(ang:Right()) / speed.y, vel:Dot(ang:Up()) / speed.z )
			local localvel_angle = localvel:Angle()
			localvel_angle:Normalize()

			//Now apply the correct pose params
			self:SetPoseParameter("move_x", localvel.x)
			self:SetPoseParameter("move_y", -localvel.y)
			self:SetPoseParameter("move_yaw", localvel_angle.y)
			self:SetPoseParameter("move_scale", math.abs(localvel.x) + math.abs(localvel.y))

		end


		//Set the surrounding bounds (area where you can click on the model with traces, like properties) to be larger than the collision bounds 
		//if necessary. This fixes the editor window being too hard to open for some models and almost all effects. 
		//BUG: We were using BOUNDS_HITBOXES prior to this, but that setting is buggy and causes a number of problems, such as breaking attached
		//particles (https://github.com/Facepunch/garrysmod-issues/issues/6028). This solution is less elegant and won't work in cases where
		//models get bonemanipped out of bounds, but we're limited in what we can do here since this needs to be called serverside to function
		//(no using the bone bounds from BuildBonePositions, sadly) Revert this if the issues with BOUNDS_HITBOXES are ever fixed!
		if self:GetHitBoxCount(0) > 0 then
			local tab = self:GetSequenceInfo(self:GetChannel1Sequence(self))
			local min, max
			if tab then
				min = tab.bbmin
				max = tab.bbmax
			end
			if min and max then
				min, max = self:GetRotatedAABB(tab.bbmin, tab.bbmax)
				local min2, max2 = self:GetRotatedAABB(self:GetCollisionBounds())
				self:SetSurroundingBounds(
					Vector(math.min(min.x,min2.x), math.min(min.y,min2.y), math.min(min.z,min2.z)), 
					Vector(math.max(max.x,max2.x), math.max(max.y,max2.y), math.max(max.z,max2.z))
				)
			else
				self:SetSurroundingBounds(self:GetRotatedAABB(self:GetCollisionBounds()))
			end
		end


		self:NextThink(time)
		return true

	else

		//Fix for demo recording and playback - when demos are recorded, they wipe a bunch of clientside settings like LODs and our BuildBonePositions callback, so redo those by running Initialize.
		//They also don't seem to record clientside values set on the entity before recording, so tell the server to send us a new BoneInfo and RemapInfo table so we can actually record these ones.
		//Note 10/16/24: Newly connected players also do this, they run Initialize but then wipe the callback and LOD setting right after.
		//However, unlike ent_advbonemerge and prop_resizedragdoll_physparent, this entity still gets the chance to run BuildBonePositions 1-3 times before it gets wiped, so we can't rely 
		//on checking if it's already run the function. Instead, we have to check this all the time, and make GetCallbacks create a new table every frame. >:(
		if --[[(!self.BuildBonePositions_HasRun or engine.IsRecordingDemo()) and]] #self:GetCallbacks("BuildBonePositions") == 0 and self.GetPuppeteer then
			self:Initialize()
			self.AdvBone_BoneInfo_Received = false
			timer.Simple(1, function() 		//we have to do this one on a timer - otherwise, if the ent was spawned before recording, upon playback the recorded remapinfo 
				self.RemapInfo_Received = false	//receive func will run BEFORE the ent has nwvars set up, so the receive func won't be able to get the puppeteer
			end)
		end

		local time = CurTime()
		local parent = self:GetParent()


		//(Advanced Bonemerge) (Remapping) If an animation is playing, don't let BuildBonePositions fall asleep
		if self.IsPuppeteer or (table.Count(self.AdvBone_BoneManips) > 0 and !IsValid(self:GetPuppeteer())) then //don't do all these checks if we're not running buildbonepositions, or if our puppeteer is doing it for us
			local animplaying = false
			for i = 1, 4 do
				local seq = self["GetChannel" .. i .. "Sequence"](self)

				local numpadisdisabling = false
				if self["GetChannel" .. i .. "NumpadMode"](self) == 0 then
					numpadisdisabling = self["GetChannel" .. i .. "NumpadState"](self)
					if !self["GetChannel" .. i .. "NumpadStartOn"](self) then
						numpadisdisabling = !numpadisdisabling
					end
				end

				if !(seq <= 0)								//not an invalid animation
				and self:SequenceDuration(seq) > 0					//not a single-frame animation
				and !self["GetChannel" .. i .. "Pause"](self)				//not paused
				and !numpadisdisabling  						//not disabled by numpad
				and (self["GetChannel" .. i .. "Speed"](self) != 0) then		//not at 0 speed
					animplaying = true
					break
				end
			end
			if animplaying then
				self.LastBoneChangeTime = time
				//Puppeteers can run this too, so make sure they wake up their parent as well
				if self.IsPuppeteer then 
					if IsValid(parent) then
						parent.LastBoneChangeTime = time
					end
				end
			end
		end

		//(Advanced Bonemerge) If we don't have a clientside boneinfo table, or need to update it, then request it from the server
		if !self.AdvBone_BoneInfo_Received and duplicator.FindEntityClass("ent_advbonemerge") then
			net.Start("AdvBone_EntBoneInfoTable_GetFromSv", true)
				net.WriteEntity(self)
			net.SendToServer()
		end

		//(Advanced Bonemerge)
		//Note: Animated props don't use a workaround for static_prop models. Instead, unmerged static_prop animprops use garrymanips for scaling (the manipulatebonescale override
		//has an exception for them) and merged static_prop animprops are automatically converted to ent_advbonemerge since they don't have any animations.

		//test: draw surrounding bounds
		--[[local min, max = self:GetSurroundingBounds()
		//MsgN(min, ", ", max)
		debugoverlay.BoxAngles(Vector(), min, max, Angle(), 0.05, Color(0,255,150,0))]]

		//(Advanced Bonemerge) Set the render bounds (TODO: advbone checks to make sure the BuildBonePositions func isn't "asleep" before doing this, to prevent running this unnecessarily, but it might be more complicated for animprops)
		if !self.IsPuppeteer and self.AdvBone_RenderBounds_BoneMins and self.AdvBone_RenderBounds_HighestBoneScale then
			local bloat = nil
			if self.AdvBone_RenderBounds_Bloat then
				bloat = self.AdvBone_RenderBounds_Bloat * self.AdvBone_RenderBounds_HighestBoneScale
				bloat = Vector(bloat, bloat, bloat)
			end
			local min, max = self.AdvBone_RenderBounds_BoneMins, self.AdvBone_RenderBounds_BoneMaxs
			if IsValid(parent) then
				local min2, max2 = parent:GetRenderBounds()
				//adding the parent's render bounds is necessary in order to prevent shadows from getting cut off in some cases i.e. when merged to ragdolls or animprops
				min, max = Vector(math.min(min.x,min2.x),math.min(min.y,min2.y),math.min(min.z,min2.z)), Vector(math.max(max.x,max2.x),math.max(max.y,max2.y),math.max(max.z,max2.z))
			end
			self:SetRenderBounds(min, max, bloat)

			//debug: draw render bounds
			--[[local min, max = self:GetRenderBounds()
			if IsValid(parent) then
				debugoverlay.BoxAngles(parent:GetPos(), min, max, parent:GetAngles(), 0.1, Color(0,255,150,0))
			else
				debugoverlay.BoxAngles(self:GetPos(), min, max, self:GetAngles(), 0.1, Color(0,255,150,0))
			end]]
		end
		local focus = system.HasFocus()
		if focus == nil or focus == true then //fix: updating shadows out of focus can cause a crash with the GPU Saver addon
			if IsValid(parent) then
				//TODO: this doesn't set the size of the shadow properly unless we set EF_BONEMERGE on the merged ent, but doing that applies the
				//default bonemerge effect to the model and squashes the animation on any matching bones, so we can't do that
				//if !parent:IsEffectActive(EF_NOSHADOW) then
					parent:UpdateShadow()
				//end
			else
				//MsgN(self:GetEffects())
				//if !self:IsEffectActive(EF_NOSHADOW) then
					self:UpdateShadow()
				//end
			end
		end

		//(Advanced Bonemerge) If we're unmerged then clear our render origin and angles so we don't get stuck in that spot
		if !IsValid(self:GetParent()) and self:GetRenderOrigin() then
			self:SetRenderOrigin()
			self:SetRenderAngles()
		end



		//(Remapping) Set puppeteer's offset from parent and render bounds
		if self.IsPuppeteer then
			local parent = self:GetParent()
			if IsValid(parent) then
				//Copy parent's scale
				local scale = parent:GetModelScale()
				self:SetModelScale(scale)

				//Move our model origin with some code mostly copied from BuildBonePositions
				local posmanip, _ = LocalToWorld(self:GetPuppeteerPos() * parent:GetModelScale(), Angle(), Vector(), parent:GetAngles())
				local newpos = parent:GetPos() + posmanip
				if self:GetPos() != newpos then //don't move us if we don't have to, otherwise we'll set off CalcAbsolutePosition every frame
					self:SetPos(newpos)
				end
				local newang = parent:GetAngles()
				if self:GetAngles() != newang then
					self:SetAngles(newang)
				end
				//Also move our render origin - setpos alone is unreliable since the position can get reasserted if the parent moves or something like that
				self:SetRenderOrigin(newpos)
				self:SetRenderAngles(newang)

				//Set puppeteer's render bounds to always render if looking at the parent
				local seqinfo = self:GetSequenceInfo(self:GetSequence())
				if !seqinfo then //someone reported a bug where seqinfo returned nil (bad sequence?); not sure what would make this happen, but just use modelbounds as a fallback
					local mins, maxs = self:GetModelBounds()
					seqinfo = {
						["bbmin"] = mins,
						["bbmax"] = maxs
					}
				end
				local min, max = seqinfo.bbmin * scale, seqinfo.bbmax * scale
				local min2, max2 = parent:GetRenderBounds()
				min2 = WorldToLocal(parent:GetPos() + min2, parent:GetAngles(), self:GetPos(), self:GetAngles())
				max2 = WorldToLocal(parent:GetPos() + max2, parent:GetAngles(), self:GetPos(), self:GetAngles())
				//This isn't the perfect way to account for weird angles like the ones we mighr get from -1 angle manips, and the render bounds get a bit big sometimes,
				//but it gets the job done and it's cheaper than WorldToLocaling every corner of the parent's render box.
				self:SetRenderBounds( Vector(math.min(min.x,min2.x,max2.x),math.min(min.y,min2.y,max2.y),math.min(min.z,min2.z,max2.z)), Vector(math.max(max.x,min2.x,max2.x),math.max(max.y,min2.y,max2.y),math.max(max.z,min2.z,max2.z)) )

				//debug: draw render bounds
				--[[local min, max = self:GetRenderBounds()
				debugoverlay.BoxAngles(self:GetPos(), min, max, self:GetAngles(), 0.1, Color(0,255,150,0))]]
			end
		end

		//(Remapping)
		//If we have a puppeteer, but don't have a clientside remapinfo table, or need to update it, then request it from the server
		if IsValid(self:GetPuppeteer()) then 
			if !self.RemapInfo_Received then
				net.Start("AnimProp_RemapInfoTable_GetFromSv", true)
					net.WriteEntity(self)
				net.SendToServer()
			end
		else
			//If our puppeteer is removed, clear the received value so we request a new one if we get a new puppeteer
			if self.RemapInfo_Received then
				self.RemapInfo_Received = nil
			end
		end

		//We can't remove the clientside model inside the BuildBonePositions callback, or else it'll cause a crash for some reason - do it here instead
		if self.csmodeltoremove then
			self.csmodeltoremove:Remove()
			self.csmodeltoremove = nil
		end


		//Control in-code TF2 minigun animation
		if self.MinigunAnimBone and self.MinigunAnimFrame != time then
			//Don't do this more than once per frame or else it'll mess up
			self.MinigunAnimFrame = time

			//To keep things simple, if multiple channels are all playing the spin animation, then the highest channel will control it.
			//Sorry, no playing the same animation on multiple channels to make the spin speed stack.
			local i = nil
			for i2 = 1, 4 do
				if self["GetChannel" .. tostring(i2) .. "Sequence"](self) == self:LookupSequence("fire_loop") then
					i = i2
				end
			end
			if !i then
				//If none of the channels are playing the animation, then reset the values and don't spin
				self.MinigunAnimSpeed = 0
				self.MinigunAnimAngle = 0
			else
				local speed = self["GetChannel" .. i .. "Speed"](self)

				if self["GetChannel" .. i .. "Pause"](self) or speed == 0 then
					//Don't spin or update the values if the animation is paused
					//TODO: figure out a good way to handle the animation being paused at a certain frame and the user moving around the seekbar - i could see someone 
					//trying to use this feature to rotate the barrel to some specific angle (on a custom model where the angle difference is a lot more noticeable, i 
					//guess) and then getting mad when the angle isn't saved
				else
					local speedtarget = 20
					//If the animation is disabled by the numpad, then spin it down. Otherwise, spin it up.
					local numpadisdisabling = false
					if self["GetChannel" .. i .. "NumpadMode"](self) == 0 then
						numpadisdisabling = self["GetChannel" .. i .. "NumpadState"](self)
						if !self["GetChannel" .. i .. "NumpadStartOn"](self) then
							numpadisdisabling = !numpadisdisabling
						end
					end
					if numpadisdisabling then speedtarget = 0 end
					
					//Based on tf2 code https://github.com/mastercomfig/team-comtress-2/blob/master/src/game/shared/tf/tf_weapon_minigun.cpp#L1080
					if self.MinigunAnimSpeed != speedtarget then
						//tf2 code says +/-0.1 speed per frame and doesn't account for frametime, but in-game testing shows that it's the same regardless of framerate.
						//scaling it to 60FPS gives accurate results.
						self.MinigunAnimSpeed = math.Approach(self.MinigunAnimSpeed, speedtarget, 0.1 * math.abs(speed) * (FrameTime() * 60))
					end
					self.MinigunAnimAngle = math.NormalizeAngle( self.MinigunAnimAngle + ( ( math.deg(self.MinigunAnimSpeed) * speed ) * FrameTime() ) )

					//(Advanced Bonemerge) If we moved, wake up the buildbonepositions function of anything advbonemerged to us (festive minigun attachment is jittery otherwise)
					if self.MinigunAnimSpeed > 0 then
						self.LastBoneChangeTime = time
						if AdvBone_ResetBoneChangeTimeOnChildren then AdvBone_ResetBoneChangeTimeOnChildren(self) end
					end
				end
			end
		end

	end

end




if SERVER then

	function ENT:StartAnimation(i,startframe)

		//Advanced Bonemerge: We're updating the animation, make sure BuildBonePositions starts running again
		AdvBone_ResetBoneChangeTime(self)
		//Puppeteers can run this too, so make sure they wake up their parent as well
		if self.IsPuppeteer then 
			local parent = self:GetParent()
			if IsValid(parent) then
				AdvBone_ResetBoneChangeTime(parent)
			end
		end

		local seq = self["GetChannel" .. i .. "Sequence"](self)
		local speed = self["GetChannel" .. i .. "Speed"](self)
		local startpoint = self["GetChannel" .. i .. "StartPoint"](self)
		local endpoint = self["GetChannel" .. i .. "EndPoint"](self)

		if !startframe then 
			if speed >= 0 then
				startframe = startpoint
			else
				startframe = endpoint
			end
		else
			startframe = math.Clamp(startframe, startpoint, endpoint)
		end

		local duration = self:SequenceDuration(seq)
		if speed >= 0 then
			duration = ( duration - (duration * (1 - endpoint)) ) / math.abs(speed)
		else
			duration = ( duration - (duration * startpoint) ) / math.abs(speed)
		end
		local durationfull = self:SequenceDuration(seq) / math.abs(speed)


		//Set the next stop time and loop time for this channel
		if speed >= 0 then
			self.AnimNextStop[i] = CurTime() + duration - (durationfull * startframe)
		else
			self.AnimNextStop[i] = CurTime() + duration - (durationfull * math.abs(startframe - 1))
		end
		local loopmode = self["GetChannel" .. i .. "LoopMode"](self)
		local loopdelay = self["GetChannel" .. i .. "LoopDelay"](self)
		if loopmode == 1 then
			self.AnimNextLoop[i] = self.AnimNextStop[i] + loopdelay
		elseif loopmode == 2 then
			self.AnimNextLoop[i] = CurTime() + loopdelay
		end


		local numpadisdisabling = false
		if self["GetChannel" .. i .. "NumpadMode"](self) == 0 then
			numpadisdisabling = self["GetChannel" .. i .. "NumpadState"](self)
			if !self["GetChannel" .. i .. "NumpadStartOn"](self) then
				numpadisdisabling = !numpadisdisabling
			end
		end

		//Channel 1 uses the entity's sequence
		if i == 1 then

			self:ResetSequence(seq)

			if numpadisdisabling then

				self:SetPlaybackRate(0)
				self:SetCycle(startpoint)

			elseif self["GetChannel" .. i .. "Pause"](self) then

				self:SetPlaybackRate(0)
				self:SetCycle( math.Clamp(self["GetChannel" .. i .. "PauseFrame"](self), startpoint, endpoint) )

			else

				self:SetPlaybackRate(speed)
				self:SetCycle(startframe)

			end

		//The rest of the channels use gestures/animation layers
		else

			//Check if we already have a valid layer to use
			local id = nil
			local oldid = self["GetChannel" .. i .. "LayerID"](self)
			if oldid != -1 and self:IsValidLayer(oldid) then
				id = oldid
			end
			//If we don't have a layer for this channel, then create one, otherwise just set the sequence of the existing layer
			if !id then
				id = self:AddLayeredSequence(seq, i)
				self["SetChannel" .. i .. "LayerID"](self, id)
				self:SetLayerLooping(id, true)
			elseif self:GetLayerSequence(id) != seq then
				self:SetLayerSequence(id, seq)
			end

			if numpadisdisabling then

				self:SetLayerPlaybackRate(id, 0)
				self:SetLayerCycle(id, startpoint)

				self:SetLayerWeight(id, 0)
				self:SetLayerBlendIn(id, 0)
				self:SetLayerBlendOut(id, 0)

			elseif self["GetChannel" .. i .. "Pause"](self) then

				self:SetLayerPlaybackRate(id, 0)
				self:SetLayerCycle( id, math.Clamp(self["GetChannel" .. i .. "PauseFrame"](self), startpoint, endpoint) )

				local layersettings = self["GetChannel" .. i .. "LayerSettings"](self) or Vector(0,0,1) //vector; x = layerblendin, y = layerblendout, z = layerweight
				self:SetLayerWeight(id, layersettings.z)
				self:SetLayerBlendIn(id, layersettings.x)
				self:SetLayerBlendOut(id, layersettings.y)

			else

				self:SetLayerPlaybackRate(id, speed / 2)  //gesture/animlayer playback rate is doubled for some reason
				self:SetLayerCycle(id, startframe)

				local layersettings = self["GetChannel" .. i .. "LayerSettings"](self) or Vector(0,0,1) //vector; x = layerblendin, y = layerblendout, z = layerweight
				self:SetLayerWeight(id, layersettings.z)
				self:SetLayerBlendIn(id, layersettings.x)
				self:SetLayerBlendOut(id, layersettings.y)

			end

		end

	end




	function ENT:NumpadSetState(i, newstate)

		local mode = self["GetChannel" .. i .. "NumpadMode"](self)

		if mode == 0 then

			//Mode 0: Disable/enable animation
			self["SetChannel" .. i .. "NumpadState"](self, newstate)
			self:StartAnimation(i)

		elseif mode == 1 then

			//Mode 1: Pause/unpause animation
			local pause = !self["GetChannel" .. i .. "Pause"](self)

			//TODO: Currently this is all just copied from the net.Receive for "AnimProp_EditMenuInput_SendToSv", should we make this into a function for both of them to use?
			self["SetChannel" .. i .. "Pause"](self, pause)
			if pause then

				local frame = 0
				if i == 1 then
					frame = self:GetCycle()
				else
					local id = self["GetChannel" .. i .. "LayerID"](self)
					if id != -1 and self:IsValidLayer(id) then
						frame = self:GetLayerCycle(id)
					end
				end

				self["SetChannel" .. i .. "PauseFrame"](self, frame)
				self:StartAnimation(i)

			else

				local frame = self["GetChannel" .. i .. "PauseFrame"](self)

				self:StartAnimation(i, frame)

			end

		elseif mode == 2 then

			//Mode 2: Restart animation
			self:StartAnimation(i)

		end

	end

	function AnimpropNumpadFunction(pl, ent, i, keydown)

		if !IsValid(ent) then return end
		if !ent["GetChannel" .. i .. "NumpadState"] then return end  //if the function doesn't exist yet, not if the function returns false
	
		if ent["GetChannel" .. i .. "NumpadToggle"](ent) then
			if keydown then
				local state = ent["GetChannel" .. i .. "NumpadState"](ent)
				ent:NumpadSetState(i, !state)
			end
		else
			if keydown then
				ent:NumpadSetState(i, true)
			else
				ent:NumpadSetState(i, false)
			end
		end

		ent["NumpadKeyDown" .. i] = keydown
	
	end

	numpad.Register("Animprop_Numpad", AnimpropNumpadFunction)




	function ENT:UpdateAnimpropPhysics()

		//(Advanced Bonemerge) We shouldn't have a physics object if we're parented
		if IsValid(self:GetParent()) or (duplicator.FindEntityClass("ent_advbonemerge") and self.IsAdvBonemerged) or self.IsPuppeteer then
			self:SetCollisionBounds(vector_origin,vector_origin) //stop merged animprops from bloating up duplicator bounds or getting hit by clientside traces (i.e. context menu properties)

			self:SetMoveType(MOVETYPE_NONE)
			self:SetSolid(SOLID_NONE)

			local phys = self:GetPhysicsObject()
			if IsValid(phys) then
				self:SetVelocity(vector_origin)
				self:PhysicsDestroy()
			end

			//This value is only used here, when we paste a save/dupe of this entity. Without it, when the ent first spawns, our parent won't be valid and we'll create a physobj
			//by mistake. It gets removed an instant later when the constraint function kicks in, parents the entity, and calls this function again, but having that physobj at 
			//first somehow causes weird physics on the parent if it's also an animprop. If we add this value and then check for it when we paste the ent, none of that happens.
			//TODO: This causes problems if a merged animprop is pasted successfully but its parent isn't - because the value is still true, it'll still be nonphysical even though
			//it has no parent, making it impossible to interact with. What's a good way to tell the difference between these two cases?
			if !self.IsPuppeteer then
				self.IsAdvBonemerged = true
			end

			return
		end

		//If our model scale is exactly 1, EnableCustomCollisions won't work, and player collisions and traces will still use the default collision mesh 
		//instead of the custom collision mesh (why?)
		if self:GetModelScale() == 1 then
			self:SetModelScale(1.0000001)
		//In multiplayer, don't let players make props too big or small and grief the server
		//(see ENT:Think() comments for why we cap this at 16)
		elseif !game.SinglePlayer() then
			if self:GetModelScale() > 16 then
				self:SetModelScale(16)
			elseif self:GetModelScale() < 0.05 then
				self:SetModelScale(0.05)
			end
		end
		local scale = self:GetModelScale()

		//Save whether or not the physobj is frozen so we can reapply that state to the new physobj
		local motion = true
		local phys = self:GetPhysicsObject()
		if IsValid(phys) then
			motion = phys:IsMotionEnabled()
		end

		//Get some info from util.GetModelInfo that we'll need for the new physics object
		local modelinforaw = util.GetModelInfo(self:GetModel())
		local solidinfo = nil
		if modelinforaw and modelinforaw.KeyValues then	//getmodelinfo will silently fail on some models with a bad modelname (http://wiki.garrysmod.com/page/util/GetModelInfo)
			for _, tab in pairs (util.KeyValuesToTablePreserveOrder(modelinforaw.KeyValues)) do
				if tab.Key == "solid" then
					solidinfo = solidinfo or {}

					local tabprocessed = {}
					for _, tab2 in pairs (tab.Value) do
						tabprocessed[tab2.Key] = tab2.Value
					end

					if tabprocessed["index"] == 0 then solidinfo = tabprocessed end
				end
			end
		end

		//Remove the old physics object, otherwise the prop can become "unstable" under certain conditions and freeze the game upon being removed
		if IsValid(phys) then
			self:PhysicsDestroy()
		end


		//Physics prop
		local mode = self:GetPhysicsMode()
		if mode == 0 then

			//Only allow this option for prop models, otherwise use a physics box instead
			local mdl = self:GetModel()
			if !( util.IsValidProp(mdl) and !util.IsValidRagdoll(mdl) ) then
				self:SetPhysicsMode(1)
				self:UpdateAnimpropPhysics()
				return
			end

			//Make the standard physics object so we can grab the mesh from it
			self:PhysicsInit(SOLID_VPHYSICS)
			local phys = self:GetPhysicsObject()
			if !IsValid(phys) then
				self:SetPhysicsMode(1)
				self:UpdateAnimpropPhysics()
				return
			end

			local min, max = Vector(0,0,0), Vector(0,0,0)
			local physmesh = {}
			local maxverts = 0
			for convexnum, convextab in pairs (phys:GetMeshConvexes()) do
				maxverts = math.max(maxverts, table.Count(convextab))
				physmesh[convexnum] = {}
				for k, v in pairs (convextab) do
					physmesh[convexnum][k] = v.pos * scale
					min = Vector( math.min(min.x, physmesh[convexnum][k].x), math.min(min.y, physmesh[convexnum][k].y), math.min(min.z, physmesh[convexnum][k].z) )
					max = Vector( math.max(max.x, physmesh[convexnum][k].x), math.max(max.y, physmesh[convexnum][k].y), math.max(max.z, physmesh[convexnum][k].z) )
				end
			end
			//Collision meshes with too many vertices on a single convex will make the game hang or even crash when calling PhysicsInitMultiConvex, so make
			//those ones use box physics instead. Compare phx gumball or tf2 c_boxing gloves (high vert count on single convex, causes hangs) to phx pipes or ep2 
			//advisor_pod_crash (high vert count spread across many convexes, doesn't cause hangs)
			if maxverts > 1000 then
				//MsgN(self:GetModel(), " max physmodel vertices ", maxverts)
				self:SetPhysicsMode(1)
				self:UpdateAnimpropPhysics()
				return
			end
			local size = max - min
			if size.x < 2 or size.y < 2 or size.z < 2 or size.x > 30000 or size.y > 30000 or size.z > 30000 then
				self:SetPhysicsMode(1)
				self:UpdateAnimpropPhysics()
				return
			end

			self:PhysicsDestroy()
			self:PhysicsInitMultiConvex(physmesh)
			//self:PhysicsInit(SOLID_VPHYSICS) //new "make PhysicsInit scale with ModelScale", functionality, doesn't seem to do anything. are we using this wrong?
			//self:Activate() //supposed to force the physobj to scale

			self:SetCollisionBounds(self:GetModelBounds())
			self:SetCollisionGroup(COLLISION_GROUP_NONE)
			self:SetMoveType(MOVETYPE_VPHYSICS)
			self:SetSolid(SOLID_VPHYSICS)
			self:EnableCustomCollisions(true)

			local phys = self:GetPhysicsObject()
			if !IsValid(phys) then
				self:SetPhysicsMode(1)
				self:UpdateAnimpropPhysics()
			else
				if solidinfo then
					phys:SetMass(solidinfo["mass"] * scale * scale * scale)
					phys:SetMaterial(solidinfo["surfaceprop"] or "")
					phys:SetDamping(solidinfo["damping"], solidinfo["rotdamping"])
					local inertia = solidinfo["inertia"]
					if inertia > 0 then phys:SetInertia(phys:GetInertia() * inertia) end
				end

				phys:Sleep()
				phys:Wake()
			end

			

		//Physics box
		elseif mode == 1 then

			local min, max = self:GetModelBounds()
			if self:GetNoPhysicsBelowOrigin() and min.z < 0 and max.z > 0 then //If the model bounds don't go above the origin, then ignore this option
				min.z = 0				     		   //because otherwise we'll have no physics object at all
			end
			min = min * scale
			max = max * scale

			local size = max - min
			if size.x < 2 or size.y < 2 or size.z < 2 or size.x > 30000 or size.y > 30000 or size.z > 30000 then
				self:SetPhysicsMode(2)
				self:UpdateAnimpropPhysics()
				return
			end

			self:PhysicsInitBox(min, max)

			self:SetCollisionBounds(min / scale, max / scale)
			self:SetCollisionGroup(COLLISION_GROUP_NONE)
			self:SetMoveType(MOVETYPE_VPHYSICS)
			self:SetSolid(SOLID_VPHYSICS)
			self:EnableCustomCollisions(true)

			local phys = self:GetPhysicsObject()
			if !IsValid(phys) then
				self:SetPhysicsMode(2)
				self:UpdateAnimpropPhysics()
			else
				local newmass = phys:GetVolume() * 0.0005990614 * 2  //physobjs made by PhysInitBox are stupid heavy by default, so set the mass ourselves
				if newmass < 1 then newmass = 1 end
				phys:SetMass(newmass)

				if solidinfo then
					phys:SetMaterial(solidinfo["surfaceprop"] or "")
				end

				phys:Sleep()
				phys:Wake()
			end

		//Effect
		elseif mode == 2 then

			local radius = Vector(5.5, 5.5, 5.5) * math.Clamp(1 + ((scale - 1) * 0.5), 1, 50) //effect grip scales up half as fast as the prop itself
			local min, max = -radius, radius
			//if self:GetNoPhysicsBelowOrigin() then
				//Nudge the box up a bit so the bottom is at the model origin
				max.z = max.z - min.z
				min.z = 0
			//end

			self:PhysicsInitBox(min, max)

			self:SetCollisionBounds(min / scale, max / scale)
			self:SetCollisionGroup(COLLISION_GROUP_WEAPON)
			self:SetMoveType(MOVETYPE_VPHYSICS)
			self:SetSolid(SOLID_VPHYSICS)
			self:EnableCustomCollisions(true)

			local phys = self:GetPhysicsObject()
			if IsValid(phys) then
				phys:EnableGravity(false)
				phys:EnableDrag(false)
				phys:SetMass(math.Clamp(scale, 1, 50) * 10)

				phys:Sleep()
				phys:Wake()
			end

		end


		local phys = self:GetPhysicsObject()
		if IsValid(phys) and !motion then
			phys:EnableMotion(false)
			local ply = self:GetPlayer()
			if IsValid(ply) then
				ply:AddFrozenPhysicsObject(nil, phys)  //the entity argument needs to be nil, or else it'll make a halo effect
			end
		end

		self:RemoveSolidFlags(FSOLID_NOT_STANDABLE)


		//Fix keepupright constraint breaking when recreating physobj
		local consttab = constraint.FindConstraint(self, "Keepupright_animprop")
		if consttab and IsValid(phys) then
			//loosely based off code from animprop_autorun.lua, from the keepupright_animprop property receive func
			local constraint = Keepupright_animprop(self, consttab.Ang, consttab.Bone, consttab.angularlimit)
			if constraint then
				local ply = self:GetPlayer()
				if IsValid(ply) then
					ply:AddCleanup("constraints", constraint)
				end
				//self:SetNWBool("IsUpright", true) //this is almost certainly already true, so we can safely omit this so as to not spam net msgs when player scrubs the scale slider; worst case, the keep upright property gets out of sync, which isn't a big deal
			end
		end

	end

end




//Networking for edit menu inputs
local EditMenuInputs = {
	[0] = "channel_sequence",
	"channel_pause",
	"channel_frame",
	"channel_speed",
	"channel_loop_mode",
	"channel_loop_delay",
	"channel_numpad_num",
	"channel_numpad_toggle",
	"channel_numpad_starton",
	"channel_numpad_mode",
	"channel_startendpoint",
	"channel_layersetting",
	"poseparam_set",
	"poseparam_drive",
	"phys_scale",
	"phys_mode",
	"phys_beloworigin",
	"remap_getwithtool",
	"remap_model",
	"remap_alpha",
	"remap_pos",
	"misc_animeventfx",
	"misc_ragdollizeondmg"
}
local EditMenuInputs_bits = 5 //max 31
EditMenuInputs = table.Flip(EditMenuInputs)
//How this works:
//- table.Flip sets the table to {["channel_sequence"] = 0}, and so on
//- net.Write retrieves the corresponding number of a string with EditMenuInputs[input], then sends that number
//- net.Read gets the number, then retrieves its corresponding string with table.KeyFromValue(EditMenuInputs, input)
//This lets us add as many networkable strings to this table as we want, without having to manually assign each one a number.


if CLIENT then

	function ENT:DoInput(input, ...)

		net.Start("AnimProp_EditMenuInput_SendToSv")
	
			net.WriteEntity(self)
			local args = {...}
	
			net.WriteUInt(EditMenuInputs[input], EditMenuInputs_bits)

			if string.StartsWith(input, "channel_") then
				net.WriteUInt(args[1], 3) //animation channel, 1-4
			end
	
			//Animation menu inputs
			if input == "channel_sequence" then
	
				net.WriteInt(args[2], 16) //sequence id (no idea what the max number of sequences is so we'll say it's 32767 to be extra safe (gmod playermodel with all wOS addons installed has 4428))
	
			elseif input == "channel_pause" then
	
				net.WriteBool(args[2]) //enable/disable pause
	
			elseif input == "channel_frame" then
	
				net.WriteFloat(args[2]) //cycle
	
			elseif input == "channel_speed" then
	
				net.WriteFloat(args[2]) //playback rate
	
			elseif input == "channel_loop_mode" then
	
				net.WriteUInt(args[2], 2) //loop mode id
	
			elseif input == "channel_loop_delay" then
	
				net.WriteFloat(args[2]) //loop delay
	
			elseif input == "channel_numpad_num" then
	
				net.WriteInt(args[2], 11) //numpad key id (again, no idea what the max number of keys is so we'll say it's 1024 just to be safe)
	
			elseif input == "channel_numpad_toggle" then
	
				net.WriteBool(args[2]) //enable/disable numpad toggle
	
			elseif input == "channel_numpad_starton" then
	
				net.WriteBool(args[2]) //enable/disable numpad start on
	
			elseif input == "channel_numpad_mode" then
	
				net.WriteUInt(args[2], 2) //numpad mode id
	
			elseif input == "channel_startendpoint" then
	
				net.WriteBool(args[2]) //false = start point, true = end point
				net.WriteFloat(args[3]) //new point

			elseif input == "channel_layersetting" then
	
				net.WriteUInt(args[2], 2) //which value in the vector to change: 0 = x/layerblendin, 1 = y/layerblendout, 2 = z/layerweight
				net.WriteFloat(args[3]) //setting value
	
			//Pose Parameter inputs
			elseif input == "poseparam_set" then
	
				net.WriteInt(args[1], 11) //pose parameter id (again, no idea what the max number of keys is so we'll say it's 1024 just to be safe)
				net.WriteFloat(args[2]) //pose value
	
			elseif input == "poseparam_drive" then
	
				net.WriteBool(args[1]) //enable/disable control movement pose params
	
			//Physics inputs
			elseif input == "phys_scale" then
	
				net.WriteFloat(args[1]) //model scale
	
			elseif input == "phys_mode" then
	
				net.WriteUInt(args[1], 2) //physics mode id
	
			elseif input == "phys_beloworigin" then
	
				net.WriteBool(args[1]) //enable/disable physics below model origin
	
			//Remapping inputs
			//elseif input == "remap_getwithtool" then
	
			elseif input == "remap_model" then
	
				net.WriteString(args[1]) //puppeteer model path
	
			elseif input == "remap_alpha" then
	
				net.WriteBool(args[1]) //0/1 puppeteer alpha value
	
			elseif input == "remap_pos" then
	
				net.WriteVector(args[1])
	
			//Misc inputs
			elseif input == "misc_animeventfx" then
	
				net.WriteBool(args[1]) //enable/disable animevent effects
	
			elseif input == "misc_ragdollizeondmg" then
				
				net.WriteBool(args[1]) //enable/disable ragdollize on damage
	
			end
	
		net.SendToServer()
	
	end
	
else

	util.AddNetworkString("AnimProp_EditMenuInput_SendToSv")

	//Respond to inputs from the clientside edit menu
	net.Receive("AnimProp_EditMenuInput_SendToSv", function(_, ply)

		local self = net.ReadEntity()
		if !IsValid(self) or self:GetClass() != "prop_animated" then return end

		local input = net.ReadUInt(EditMenuInputs_bits)
		if !input then return end
		input = table.KeyFromValue(EditMenuInputs, input)

		local i = nil
		if string.StartsWith(input, "channel_") then
			i = net.ReadUInt(3) //animation channel, 1-4
		end

		if input == "channel_sequence" then

			self["SetChannel" .. i .. "Sequence"](self, net.ReadInt(16))
			self["SetChannel" .. i .. "PauseFrame"](self, 0)
			self:StartAnimation(i)

		elseif input == "channel_pause" then

			local pause = net.ReadBool()
			self["SetChannel" .. i .. "Pause"](self, pause)
			if pause then

				local frame = 0
				if i == 1 then
					frame = self:GetCycle()
				else
					local id = self["GetChannel" .. i .. "LayerID"](self)
					if id != -1 and self:IsValidLayer(id) then
						frame = self:GetLayerCycle(id)
					end
				end

				self["SetChannel" .. i .. "PauseFrame"](self, frame)
				self:StartAnimation(i)

			else

				local frame = self["GetChannel" .. i .. "PauseFrame"](self)

				self:StartAnimation(i, frame)

			end

		elseif input == "channel_frame" then

			local frame = net.ReadFloat()
			self["SetChannel" .. i .. "PauseFrame"](self, frame)
			self:StartAnimation(i, frame)

		elseif input == "channel_speed" then

			self["SetChannel" .. i .. "Speed"](self, net.ReadFloat())
			if !self["GetChannel" .. i .. "Pause"](self) then

				local frame = 0
				if i == 1 then
					frame = self:GetCycle()
				else
					local id = self["GetChannel" .. i .. "LayerID"](self)
					if id != -1 and self:IsValidLayer(id) then
						frame = self:GetLayerCycle(id)
					end
				end

				self:StartAnimation(i, frame)

			end

		elseif input == "channel_loop_mode" then

			self["SetChannel" .. i .. "LoopMode"](self, net.ReadUInt(2))
			self:StartAnimation(i)

		elseif input == "channel_loop_delay" then

			self["SetChannel" .. i .. "LoopDelay"](self, net.ReadFloat())
			self:StartAnimation(i)

		elseif input == "channel_numpad_num" then

			local ply = self:GetPlayer() //NOTE: this still works if ply doesn't exist

			local key = net.ReadInt(11)
			self["SetChannel" .. i .. "Numpad"](self, key)

			numpad.Remove(self["NumDown" .. i])
			numpad.Remove(self["NumUp" .. i])

			self["NumDown" .. i] = numpad.OnDown(ply, key, "Animprop_Numpad", self, i, true)
			self["NumUp" .. i] = numpad.OnUp(ply, key, "Animprop_Numpad", self, i, false)

			//If the player is holding down the old key then let go of it
			if self["NumpadKeyDown" .. i] then
				AnimpropNumpadFunction(ply, self, i, false)
			end

		elseif input == "channel_numpad_toggle" then

			local ply = self:GetPlayer() //NOTE: this still works if ply doesn't exist

			local toggle = net.ReadBool()
			self["SetChannel" .. i .. "NumpadToggle"](self, toggle)

			//If the player switches to non-toggle mode, update the numpad state if necessary so it reflects whether or not the key is being held down 
			//(don't wait for the player to press/release the key again)
			if !toggle then
				local keydown = self["NumpadKeyDown" .. i]
				if keydown != self["GetChannel" .. i .. "NumpadState"](self) then
					AnimpropNumpadFunction(ply, self, i, keydown)
				end
			end

		elseif input == "channel_numpad_starton" then

			self["SetChannel" .. i .. "NumpadStartOn"](self, net.ReadBool())
			self:StartAnimation(i)

		elseif input == "channel_numpad_mode" then

			local mode = net.ReadUInt(2)
			self["SetChannel" .. i .. "NumpadMode"](self, mode)

			//Only mode 0 uses and updates the numpad state, so don't save numpad state between modes, and update it if switching back to mode 0
			if mode == 0 then
				local toggle = self["GetChannel" .. i .. "NumpadToggle"](self)
				if !toggle then
					self:NumpadSetState(i, self["NumpadKeyDown" .. i])
				else
					self:NumpadSetState(i, false)
				end
			else
				self["SetChannel" .. i .. "NumpadState"](self, false)
				self:StartAnimation(i)
			end

		elseif input == "channel_startendpoint" then

			local isend = net.ReadBool() //false = start point, true = end point
			local newpoint = net.ReadFloat()

			local frame = 0
			if i == 1 then
				frame = self:GetCycle()
			else
				local id = self["GetChannel" .. i .. "LayerID"](self)
				if id != -1 and self:IsValidLayer(id) then
					frame = self:GetLayerCycle(id)
				end
			end

			if !isend then 
				self["SetChannel" .. i .. "StartPoint"](self, newpoint)
				if frame < newpoint then
					self:StartAnimation(i)
				else
					self:StartAnimation(i, frame) //we still need to update the animation to apply the new start point
				end
			else
				self["SetChannel" .. i .. "EndPoint"](self, newpoint)
				if frame > newpoint then
					self:StartAnimation(i)
				else
					self:StartAnimation(i, frame) //we still need to update the animation to apply the new end point
				end
			end

		elseif input == "channel_layersetting" then

			local vec = self["GetChannel" .. i .. "LayerSettings"](self)
			local which = net.ReadUInt(2)
			if which == 0 then
				which = "x" //layerblendin
			elseif which == 1 then
				which = "y" //layerblendout
			else
				which = "z" //layerweight
			end
			vec[which] = net.ReadFloat()

			self["SetChannel" .. i .. "LayerSettings"](self, vec)
			self:StartAnimation(i)

		elseif input == "poseparam_set" then

			local i = net.ReadInt(11)

			local name = self:GetPoseParameterName(i)
			local value = net.ReadFloat()
			self:SetPoseParameter(name, value)
			self.PoseParams[i] = value

			//Advanced Bonemerge: We're updating the animation, make sure BuildBonePositions starts running again
			AdvBone_ResetBoneChangeTime(self)
			//Puppeteers can run this too, so make sure they wake up their parent as well
			if self.IsPuppeteer and IsValid(self:GetParent()) then
				AdvBone_ResetBoneChangeTime(self:GetParent())
			end

		elseif input == "poseparam_drive" then

			self:SetControlMovementPoseParams(net.ReadBool())

		elseif input == "phys_scale" then

			local scale = net.ReadFloat()
			if scale == 1 then scale = 1.0000001 end
			if self:GetModelScale() != scale then
				//Just update the scale and let the think function take care of the rest (we want other scaling methods like Biggify/Smallify to work too)
				self:SetModelScale(scale)
			end

		elseif input == "phys_mode" then

			local newvalue = net.ReadUInt(2)

			//Only allow mode 0 (physics prop) for prop models
			local mdl = self:GetModel()
			if newvalue == 0 and !( util.IsValidProp(mdl) and !util.IsValidRagdoll(mdl) ) then
				newvalue = 1
			end

			if self:GetPhysicsMode() != newvalue then
				self:SetPhysicsMode(newvalue)
				//self:UpdateAnimpropPhysics()
				self.ThinkUpdateAnimpropPhysics = true
			end

		elseif input == "phys_beloworigin" then

			local newvalue = net.ReadBool()
			if self:GetNoPhysicsBelowOrigin() != newvalue then
				self:SetNoPhysicsBelowOrigin(newvalue)
				//self:UpdateAnimpropPhysics()
				self.ThinkUpdateAnimpropPhysics = true
			end

		elseif input == "remap_getwithtool" then

			if !IsValid(ply) then return end
			if !GetConVar("toolmode_allow_animprops"):GetBool() then return end //TODO: this was copied from advbonemerge, which also does a CanTool check with a fake trace. is that necessary here?

			local tool = ply:GetTool("animprops")
			if !istable(tool) or !IsValid(tool:GetWeapon()) then return end

			ply:ConCommand("gmod_tool animprops")
			//Fix: The tool's holster function clears the nwentity, and if animprops is already the toolgun's selected tool, it'll "holster" the tool before "deploying" it again.
			//To make this worse, it's different if the toolgun is the active weapon or not (if active, it holsters then deploys; if not active, it deploys, holsters, then deploys again)
			//so instead of having to deal with any of that, just set the entity on a delay so we're sure the tool is already done equipping.
			timer.Simple(0.1, function()
				if !IsValid(self) or !IsValid(ply) then return end
				tool:GetWeapon():SetNWEntity("Animprops_CurEntity", self)
			end)

		elseif input == "remap_model" then

			self:SetPuppeteerModel(net.ReadString()) //don't worry about checking if the model name is any good, we'll do that in the function

		elseif input == "remap_alpha" then

			self:SetPuppeteerAlpha(net.ReadBool())

		elseif input == "remap_pos" then

			self:SetPuppeteerPos(net.ReadVector())

		elseif input == "misc_animeventfx" then

			self:SetEnableAnimEventEffects(net.ReadBool())

		elseif input == "misc_ragdollizeondmg" then

			self:SetRagdollizeOnDamage(net.ReadBool())

		end

	end)

end




if CLIENT then

	function ENT:Ragdollize()

		if !util.IsValidRagdoll(self:GetModel()) then return end

		local time = CurTime()
		self.LastBuildBonePositionsTime = 0
		self:DrawModel()
		self:SetupBones()

		//Get the model's info table and process it so we can get more info on the physobjs (what their parent physobjs are)
		local modelinforaw = util.GetModelInfo(self:GetModel())
		local ModelInfo = {}
		local BoneToPhysBone = {}
		if modelinforaw and modelinforaw.KeyValues then
			for _, tab in pairs (util.KeyValuesToTablePreserveOrder(modelinforaw.KeyValues)) do
				--[[MsgN(tab.Key)
				for _, tab2 in pairs (tab.Value) do
					MsgN( tab2.Key .. " = " .. tab2.Value )
				end
				MsgN("")]]

				if tab.Key == "solid" then
					ModelInfo.Solids = ModelInfo.Solids or {}

					local tabprocessed = {}
					for _, tab2 in pairs (tab.Value) do
						tabprocessed[tab2.Key] = tab2.Value
					end

					ModelInfo.Solids[tabprocessed["index"]] = tabprocessed
				end
			end

			//self:TranslateBoneToPhysBone() just doesn't work at all on some models (i.e. some "hexed" models like "team fortress 2 improved physics ragdolls hexed" return
			//the original model's values even if the hexed model should give different ones, resulting in garbage), so we can't rely on it - make a table to use instead
			for i = 0, table.Count(ModelInfo.Solids) - 1 do
				BoneToPhysBone[self:LookupBone(ModelInfo.Solids[i]["name"])] = i
			end
		else
			//Can't get model info, so do error handling stuff copied from ragdoll resizer code and then end here
			GAMEMODE:AddNotify("Can't ragdollize this model - check the console for details", NOTIFY_ERROR, 5)
			surface.PlaySound("buttons/button11.wav")
			if IsUselessModel(self:GetModel()) then
				//util.GetModelInfo will silently fail on models with a bad modelname (http://wiki.garrysmod.com/page/util/GetModelInfo), (example model from bug report: 
				//https://steamcommunity.com/sharedfiles/filedetails/?id=747597416), so don't ragdollize and instead send the player a notification telling them what the problem is
				MsgN("RAGDOLLIZE:")
				MsgN("The model ", self:GetModel(), " couldn't be ragdollized because we can't get its model info due to a bad file name.")
				MsgN("")
				MsgN("")
				MsgN("WHY DID THIS HAPPEN?:")
				MsgN("")
				MsgN("The ragdollize feature uses a function called util.GetModelInfo() to get all the info we need about the ragdoll's different physics objects, meaning we can't pose the new ragdoll without it.")
				MsgN("The problem is, util.GetModelInfo() will FAIL if the model name contains any of the following:")
				MsgN("_gesture")
				MsgN("_anim")
				MsgN( "_gst")
				MsgN("_pst")
				MsgN("_shd")
				MsgN("_ss")
				MsgN("_posture")
				MsgN("_anm")
				MsgN("ghostanim")
				MsgN("_paths")
				MsgN("_shared")
				MsgN("anim_")
				MsgN("gestures_")
				MsgN("shared_ragdoll_")
				MsgN("Usually, model files with these names are \"useless models\" that only exist to store animations for other models, and don't need to be spawned by themselves. They're automatically filtered out of the spawn menu and search bar, so you normally won't run into them.")
				MsgN("Unfortunately, with the thousands and THOUSANDS of custom models people create for Gmod, someone's bound to make one that has one of these phrases in its name even though it's a totally normal, legitimate model. This means it'll get caught in the \"useless model\" filter anyway and util.GetModelInfo() won't work on it.")
				MsgN("")
				MsgN("")
				MsgN("HOW CAN I FIX IT?:")
				MsgN("")
				MsgN("If you created this model, then you'll have to change the name of the file so it doesn't contain any of the phrases above.")
				MsgN("If you downloaded this model off the workshop, then you'll probably have to ask the creator to fix it. They might not want to, because changing the file name will break any old saves or dupes that were already using the model. Alternatively, if you know what you're doing, you might be able to decompile the addon and change the file name yourself.")
				MsgN("")
				MsgN("")
			else
				//util.GetModelInfo failed for some other reason, throw a different error
				MsgN("RAGDOLLIZE:")
				MsgN("The model \"" .. self:GetModel() .. "\" can't be ragdollized because we can't get its model info for an unknown reason.")
			end
			return
		end

		net.Start("AnimProp_Ragdollize_SendToSv")

			net.WriteEntity(self)

			//BuildBonePositions doesn't run serverside, so send a table of the physbones' matrices to tell the server where the client thinks the bones are
			local tab = {}
			for i = 0, self:GetBoneCount() - 1 do
				if BoneToPhysBone[i] != nil then
					local matr = self:GetBoneMatrix(i)
					if matr then
						tab[i] = matr
					end
				end
			end
			net.WriteUInt(table.Count(tab), 9)
			for k, v in pairs (tab) do
				net.WriteUInt(k, 9)
				net.WriteMatrix(v)
			end

			//note: we'd really like to use the FollowBone hack here, because the resize code uses ManipulateBoneScale (see Initialize), but that's serverside, 
			//so we'll just have to hope the time we used it in Initialize worked for all clients
			local resize = self.RagdollizeUseRagdollResizer
			net.WriteBool(resize)
			//note: non-physbone scale manips need to be generated a bit differently depending on if this is enabled or not, because of how the different ragdoll
			//entities handle bone scaling: if using a resized ragdoll, then the bones will inherit scale from their parent physbone; but if using a normal ragdoll, 
			//then the bones won't inherit scale from anything

			local domanips = self.RagdollizeDoManips
			net.WriteBool(domanips)
			if domanips then
				//Also send info to manip non-physics bones into place that don't have a physics bone above them in the hierarchy
				//(i.e. move/rotate non-physics finger bones, but don't move/rotate non-physics shoulder bones, because they'll just become unaligned with the physics arm bones attached to them
	
				//Temporarily get rid of scale manips so they don't screw everything up, then make the animprop update its bones so we can get their unscaled pos/ang
				local scales = {}
				if resize then
					for i = 0, self:GetBoneCount() - 1 do
						scales[i] = self:GetManipulateBoneScale(i)
						self:ManipulateBoneScale(i, Vector(1,1,1))
					end
					self.LastBuildBonePositionsTime = 0
					self:InvalidateBoneCache()
					self:DrawModel()
					self:SetupBones()
				end
				local tab2 = {}
				for i = 0, self:GetBoneCount() - 1 do
					local shouldpose = true //!self:BoneHasFlag(i,BONE_ALWAYS_PROCEDURAL) //don't pose jigglebones
					local function LookForPhysChildren(bone)
						if BoneToPhysBone[bone] != nil then
							shouldpose = false
						elseif shouldpose then
							for _, bone2 in pairs (self:GetChildBones(bone)) do
								if shouldpose then
									LookForPhysChildren(bone2)
								end
							end
						end
					end
					LookForPhysChildren(i)

					if shouldpose then
						local matr = self:GetBoneMatrix(i)
						local parentmatr = self:GetBoneMatrix(self:GetBoneParent(i))
						if matr and parentmatr and self.RemapInfo_DefaultBoneOffsets then
							local subtab = {}
							local pscl = parentmatr:GetScale()
							local newpos, newang = WorldToLocal(matr:GetTranslation(), matr:GetAngles(), parentmatr:GetTranslation(), parentmatr:GetAngles())
							//we've already got rid of this ent's scale manips, but we still have to counteract the model scale
							//TODO: this'll almost certainly break if we're advbonemerged and inheriting uneven scale from a terget bone, but that's super complicated to deal with, and that's a really niche situation anyway
							newpos.x = newpos.x / pscl.x
							newpos.y = newpos.y / pscl.y
							newpos.z = newpos.z / pscl.z
							subtab["pos"] = newpos - self.RemapInfo_DefaultBoneOffsets[i].posoffset

							//From the perspective of the bone we want to rotate, get how much the new offset rotates the bone compared to the default offset, and use that as our ang manip
							local newmatr2 = Matrix()
							newmatr2:Translate(self.RemapInfo_DefaultBoneOffsets[self:GetBoneParent(i)].pos)
							newmatr2:Rotate(self.RemapInfo_DefaultBoneOffsets[self:GetBoneParent(i)].ang)
							newmatr2:Rotate(newang)
							local newpos2, newang2 = WorldToLocal(newmatr2:GetTranslation(), newmatr2:GetAngles(), self.RemapInfo_DefaultBoneOffsets[i].pos, self.RemapInfo_DefaultBoneOffsets[i].ang)
							subtab["ang"] = newang2

							tab2[i] = subtab
						end
					end
				end

				if resize then
					//Restore scale manips, except on physbones, and then make the animprop update its bones again, 
					//so we can get the non-physbone scales without the physbone scales interfering (for bones that scale with the physparent only)
					for i = 0, self:GetBoneCount() - 1 do
						if BoneToPhysBone[i] == nil then
							self:ManipulateBoneScale(i, scales[i])
						end
					end
					self.LastBuildBonePositionsTime = 0
					self:InvalidateBoneCache()
					self:DrawModel()
					self:SetupBones()
				end
				//Get non-physbone scales
				for i = 0, self:GetBoneCount() - 1 do
					if BoneToPhysBone[i] == nil and self.AdvBone_BoneInfo and (self.AdvBone_BoneInfo[i].scale or !resize) then
						local matr = self:GetBoneMatrix(i)
						if matr then
							local scl = matr:GetScale() / self:GetModelScale()
							scl.x = math.Round(scl.x,4)
							scl.y = math.Round(scl.y,4)
							scl.z = math.Round(scl.z,4)
							if scl.x != 1 or scl.y != 1 or scl.z != 1 then
								//MsgN(self:GetBoneName(i), " scaled to ", scl)
								tab2[i] = tab2[i] or {}
								tab2[i]["scl"] = scl
							end
						end
					end
				end

				if resize then
					//Restore all scale manips now
					for i = 0, self:GetBoneCount() - 1 do
						self:ManipulateBoneScale(i, scales[i])
					end
					self.LastBuildBonePositionsTime = 0
					self:InvalidateBoneCache()
					self:DrawModel()
					self:SetupBones()
				
					//Now get scale values for non-physbones with "Scale with target bone" turned off, which need to scale against their parent physbone;
					//this is mostly futile unless the physparent is scaled evenly, because of the difference in the axes the bones are scaled on
					local function GetPhysParent(bone)
						local par = self:GetBoneParent(bone)
						if BoneToPhysBone[par] != nil then
							return par
						elseif par == -1 then
							return nil
						else
							//go up the hierarchy until we hit a physbone
							return GetPhysParent(par)
						end
					end
					for i = 0, self:GetBoneCount() - 1 do
						if BoneToPhysBone[i] == nil and self.AdvBone_BoneInfo and !self.AdvBone_BoneInfo[i].scale then
							local physparent = GetPhysParent(i)
							if physparent != nil then
								local matr = self:GetBoneMatrix(i)
								local physparentmatr = self:GetBoneMatrix(physparent)
								if matr and physparentmatr then
									local scl = matr:GetScale()
									//physparentmatr:SetAngles(matr:GetAngles()) //gives bad results
									physparentmatr:Rotate(physparentmatr:GetAngles() - matr:GetAngles()) //gives acceptable results
									//physparentmatr:Rotate(matr:GetAngles() - physparentmatr:GetAngles()) //seems to give same results as above??
									local pscl = physparentmatr:GetScale()
									//MsgN("pscl (", self:GetBoneName(physparent), ") = ", pscl)
									scl.x = math.Round(scl.x / pscl.x, 4) // self:GetModelScale()
									scl.y = math.Round(scl.y / pscl.y, 4) // self:GetModelScale()
									scl.z = math.Round(scl.z / pscl.z, 4) // self:GetModelScale()
									if scl.x != 1 or scl.y != 1 or scl.z != 1 then
										//MsgN(self:GetBoneName(i), " scaled to ", scl)
										tab2[i] = tab2[i] or {}
										tab2[i]["scl"] = scl
									end
								end
							end
						end
					end
				end

				net.WriteUInt(table.Count(tab2), 9)
				for k, v in pairs (tab2) do
					net.WriteUInt(k, 9)
					net.WriteVector(v.pos or Vector())
					net.WriteAngle(v.ang or Angle())
					net.WriteVector(v.scl or Vector(1,1,1))
				end
			end

			//Also send the physobj velocities if we're doing ragdollize on damage
			local dophysvel = self:GetRagdollizeOnDamage()
			net.WriteBool(dophysvel)
			if dophysvel then
				local physvel = {}
				for k, _ in pairs (tab) do
					physvel[k] = {
						vel = Vector(0,0,0),
						angVel = Vector(0,0,0),
					}
				end

				//Based off CreateServerRagdoll (https://github.com/ValveSoftware/source-sdk-2013/blob/master/mp/src/game/server/physics_prop_ragdoll.cpp#L1308), which is called by some other funcs (see serverside ragdollize func)
				local dt = 0.1
				
				//Rewind the animation in each channel by 0.1 secs
				local oldcycles = {}
				local ent2 = self:GetPuppeteer()
				if !IsValid(ent2) then ent2 = nil end
				local animent = ent2 or self //animation settings use the puppeteer if one exists, or ent otherwise
				for i = 1, 4 do
					local seq = animent["GetChannel" .. i .. "Sequence"](animent)
					local speed = animent["GetChannel" .. i .. "Speed"](animent)

					local numpadisdisabling = false
					if animent["GetChannel" .. i .. "NumpadMode"](animent) == 0 then
						numpadisdisabling = animent["GetChannel" .. i .. "NumpadState"](animent)
						if !animent["GetChannel" .. i .. "NumpadStartOn"](animent) then
							numpadisdisabling = !numpadisdisabling
						end
					end
		
					local id = nil
					if i != 1 then
						id = animent["GetChannel" .. i .. "LayerID"](animent)
					end

					if !(seq <= 0)								//not an invalid animation
					and animent:SequenceDuration(seq) > 0					//not a single-frame animation
					and !animent["GetChannel" .. i .. "Pause"](animent)			//not paused
					and !numpadisdisabling  						//not disabled by numpad
					and (speed != 0)							//not at 0 speed
					and (1 == 1 or (id != -1 and animent:IsValidLayer(id)))	then		//not an invalid animation layer
						local cycle = nil
						if i == 1 then
							cycle = animent:GetCycle()
						else
							cycle = animent:GetLayerCycle(id)
						end
						//store the current cycle
						oldcycles[i] = cycle

						//rewind the animation by 0.1 secs
						local startpoint = animent["GetChannel" .. i .. "StartPoint"](animent)
						local endpoint = animent["GetChannel" .. i .. "EndPoint"](animent)
						local dt2 = (-dt * speed) / animent:SequenceDuration(seq) //desired rewind amount as a proportion of the cycle (0-1)
						//loop back around if we've passed the startpoint/endpoint (TODO: does this break if seqdir is so short/dt2 is so long that we need to loop around more than once? do we care?)
						local newcycle = cycle + dt2
						if newcycle > endpoint then
							newcycle = startpoint + (newcycle - endpoint)
						elseif newcycle < startpoint then
							newcycle = endpoint - (startpoint - newcycle)
						end
						//TODO: handle loopmode stuff? seems like overkill for a 0.1 sec rewind.
						if i == 1 then
							animent:SetCycle(newcycle)
						else
							animent:SetLayerCycle(id, newcycle)
						end
					end
				end
				//Get the rewound bone positions
				if animent != self then
					animent.LastBuildBonePositionsTime = 0
					animent:InvalidateBoneCache()
					animent:DrawModel()
					animent:SetupBones()
				end
				self.LastBuildBonePositionsTime = 0
				self:InvalidateBoneCache()
				self:DrawModel()
				self:SetupBones()
				local oldmatrs = {}
				for k, _ in pairs (physvel) do
					local matr = self:GetBoneMatrix(k)
					if matr then
						oldmatrs[k] = matr
					end
				end
				//Now restore the current cycle
				for i = 1, 4 do
					if oldcycles[i] != nil then
						if i == 1 then
							animent:SetCycle(oldcycles[i])
						else
							local id = animent["GetChannel" .. i .. "LayerID"](animent) //dont check id validity, because we wouldnt have oldcycles[i] otherwise
							animent:SetLayerCycle(id, oldcycles[i])
						end
					end
				end
				if animent != self then
					animent.LastBuildBonePositionsTime = 0
					animent:InvalidateBoneCache()
					animent:DrawModel()
					animent:SetupBones()
				end
				self.LastBuildBonePositionsTime = 0
				self:InvalidateBoneCache()
				self:DrawModel()
				self:SetupBones()

				//Move the past bone positions backward by our velocity
				//The Valve code here also inherits the value from GetSequenceVelocity, but that's returning consistently bad valocities for us so we won't be doing that
				local vel = self:GetVelocity()
				if vel:LengthSqr() > 0 then
					vel:Mul(-dt)
					for k, matr in pairs (oldmatrs) do
						local pos, _ = WorldToLocal(vel, Angle(), Vector(), matr:GetAngles())
						matr:Translate(pos)
					end
				end

				//Calculate how much the bones moved as a velocity, so that the ragdoll physbones can inherit it
				//Based off CalcBoneDerivatives (https://github.com/ValveSoftware/source-sdk-2013/blob/master/mp/src/public/bone_setup.cpp#L2522)
				local vscl = 1/dt
				for k, matr in pairs (tab) do
					local tr1 = matr:GetTranslation()
					local tr2 = oldmatrs[k]:GetTranslation()
					physvel[k].vel.x = (tr1.x - tr2.x) * vscl
					physvel[k].vel.y = (tr1.y - tr2.y) * vscl
					physvel[k].vel.z = (tr1.z - tr2.z) * vscl

					//Based off RotationDeltaAxisAngle (https://github.com/ValveSoftware/source-sdk-2013/blob/master/sp/src/mathlib/mathlib_base.cpp#L3532)
					local srcQuat = Quaternion():SetAngle(oldmatrs[k]:GetAngles())
					local destQuat = Quaternion():SetAngle(matr:GetAngles())
					srcQuat:Invert()
					//srcQuat:MulScalar(-1)
					destQuat:Mul(srcQuat)
					destQuat:Normalize()
					local dang, daxis = destQuat:AngleAxis()

					daxis:Mul(-dang * vscl) //negating the value inexplicably makes this work better. no idea where i screwed up the math to make this necessary.
					physvel[k].angVel = daxis
				end

				//net.WriteUInt(table.Count(physvel), 9) //this is always the same number as tab so we dont have to send it again
				for bone, tab in pairs (physvel) do
					net.WriteUInt(bone, 9)
					net.WriteVector(tab.vel)
					net.WriteVector(tab.angVel)
				end
			end

		net.SendToServer()

	end

	net.Receive("AnimProp_Ragdollize_SendToCl", function()

		local self = net.ReadEntity()
		if !IsValid(self) or self:GetClass() != "prop_animated" then return end

		self:Ragdollize()

	end)

	//doesn't get called at all
	--[[function ENT:ImpactTrace(tr)
		MsgN("impact trace")
		//grab the last trace that hit us for ragdollize-on-damage; unfortunately this is the only function we have to retrieve this, and it's clientside
		PrintTable(tr)
		self.LastTracedPhysobj = tr.PhysicsBone
	end]]

else

	util.AddNetworkString("AnimProp_Ragdollize_SendToSv")

	net.Receive("AnimProp_Ragdollize_SendToSv", function(_, ply)

		local self = net.ReadEntity()
		if !IsValid(self) or self:GetClass() != "prop_animated" then return end

		local count = net.ReadUInt(9)
		local tab = {}
		for i = 1, count do
			tab[net.ReadUInt(9)] = net.ReadMatrix()
		end

		local allowresize = net.ReadBool()

		local domanips = net.ReadBool()
		local tab2 = nil
		if domanips then
			local count2 = net.ReadUInt(9)
			tab2 = {}
			for i = 1, count2 do
				tab2[net.ReadUInt(9)] = {
					["pos"] = net.ReadVector(),
					["ang"] = net.ReadAngle(),
					["scl"] = net.ReadVector(),
				}
			end
		end

		local dophysvel = net.ReadBool()
		local tab3 = nil
		if dophysvel then
			//local count3 = net.ReadUInt(9)
			tab3 = {}
			for i = 1, count do
				tab3[net.ReadUInt(9)] = {
					["vel"] = net.ReadVector(),
					["angVel"] = net.ReadVector(),
				}
			end
			self.PhysBoneVelocities = tab3
		end

		self:Ragdollize(ply, tab, tab2, allowresize)

	end)

	function ENT:Ragdollize(ply, tab, tab2, allowresize)

		if !util.IsValidRagdoll(self:GetModel()) then return end
		local ply = ply or self:GetPlayer()
		if IsValid(ply) and !self.DoRagdollizeOnDamage then
			if !gamemode.Call("PlayerSpawnRagdoll", ply, self:GetModel()) then return end //calls ply:CheckLimit("ragdolls")
		end

		//Get the model's info table and process it so we can get more info on the physobjs (what their parent physobjs are)
		local modelinforaw = util.GetModelInfo(self:GetModel())
		local ModelInfo = {}
		local BoneToPhysBone = {}
		if modelinforaw and modelinforaw.KeyValues then
			for _, tab in pairs (util.KeyValuesToTablePreserveOrder(modelinforaw.KeyValues)) do
				--[[MsgN(tab.Key)
				for _, tab2 in pairs (tab.Value) do
					MsgN( tab2.Key .. " = " .. tab2.Value )
				end
				MsgN("")]]

				if tab.Key == "solid" then
					ModelInfo.Solids = ModelInfo.Solids or {}

					local tabprocessed = {}
					for _, tab2 in pairs (tab.Value) do
						tabprocessed[tab2.Key] = tab2.Value
					end

					ModelInfo.Solids[tabprocessed["index"]] = tabprocessed
				end
			end

			//self:TranslateBoneToPhysBone() just doesn't work at all on some models (i.e. some "hexed" models like "team fortress 2 improved physics ragdolls hexed" return
			//the original model's values even if the hexed model should give different ones, resulting in garbage), so we can't rely on it - make a table to use instead
			for i = 0, table.Count(ModelInfo.Solids) - 1 do
				BoneToPhysBone[self:LookupBone(ModelInfo.Solids[i]["name"])] = i
			end
		else
			//Don't bother with all the error message crap again, it should've been caught clientside already
			return
		end

		local rag = ents.Create("prop_ragdoll")
		if !IsValid(rag) then return end
		rag:SetModel(self:GetModel())
		rag:Spawn()
		
		local resized = false
		//If the bones could potentially be scaled, check the matrix scales
		if math.Round(self:GetModelScale(),4) != 1 or IsValid(self:GetParent()) or self:HasBoneManipulations() then
			//MsgN("scale = ", math.Round(self:GetModelScale(),4) != 1, ", parent = ", IsValid(self:GetParent()), ", manips = ", self:HasBoneManipulations())
			local physobjscales = {}
			for i = 0, rag:GetPhysicsObjectCount() - 1 do
				local matr = tab[rag:TranslatePhysBoneToBone(i)] //TODO: does PhysBoneToBone work as intended on hexed models?
				if matr then
					//MsgN(i, " scale = ", matr:GetScale())
					local scl = matr:GetScale()
					if math.Round(scl.x,4) != 1 or math.Round(scl.y,4) != 1 or math.Round(scl.z,4) != 1 then
						resized = true
						physobjscales[i] = scl
					else
						physobjscales[i] = Vector(1,1,1)
					end
				end
			end
			if resized and allowresize and duplicator.FindEntityClass("prop_resizedragdoll_physparent") then
				//If ragdoll resizer is enabled and physbones have been resized, then replace rag with a resized ragdoll
				local newrag = ents.Create("prop_resizedragdoll_physparent")
				newrag.PhysObjScales = physobjscales
				newrag.ErrorRecipient = ply
				newrag:SetModel(self:GetModel())
				rag:Remove()
				rag = newrag
				rag:Spawn()
			else
				resized = false
				//If ragdoll resizer is disabled but physbones have still been resized, use manips instead
				//We cancel out the modelscale here because copying it with manips would have guaranteed bad results, but on the other hand,
				//rescaling physbones individually with manips still has legitimate uses on ragdolls, so we still want to carry those over.
				local mdlscl = self:GetModelScale()
				for i, scl in pairs (physobjscales) do
					scl.x = math.Round(scl.x/mdlscl,4)
					scl.y = math.Round(scl.y/mdlscl,4)
					scl.z = math.Round(scl.z/mdlscl,4)
					if scl.x != 1 or scl.y != 1 or scl.z != 1 then
						rag:ManipulateBoneScale(rag:TranslatePhysBoneToBone(i),scl)
					end
				end
			end
		end


		rag:SetSkin(self:GetSkin())
		//Copy bodygroups
		for i = 0, self:GetNumBodyGroups() - 1 do
			rag:SetBodygroup(i, self:GetBodygroup(i)) 
		end
		//Copy flexes
		if self:HasFlexManipulatior() then
			rag:SetFlexScale(self:GetFlexScale())
			for i = 0, self:GetFlexNum() - 1 do 
				rag:SetFlexWeight(i, self:GetFlexWeight(i)) 
			end
		end
		if IsValid(ply) and !self.DoRagdollizeOnDamage then
			if resized then
				undo.Create("ResizedRagdollPhys")
					undo.AddEntity(rag)
					undo.SetPlayer(ply)
				undo.Finish("Resized Ragdoll (" .. tostring(rag:GetModel() or "models/error.mdl") .. ")")
			else
				undo.Create("Ragdoll")
					undo.AddEntity(rag)
					undo.SetPlayer(ply)
				undo.Finish("Ragdoll (" .. tostring(rag:GetModel() or "models/error.mdl") .. ")")
			end
			ply:AddCleanup("ragdolls", rag)
		end

		if !IsValid(self:GetParent()) then //don't move us if we're parented
			local selfphys = self:GetPhysicsObject()
			if IsValid(selfphys) then
				selfphys:Wake()
				selfphys:EnableMotion(false)
				if IsValid(ply) then
					ply:AddFrozenPhysicsObject(nil, selfphys)  //the entity argument needs to be nil, or else it'll make a halo effect
				end
			end
		end

		//Get physics bone offsets from the ragdoll
		for i = 0, rag:GetPhysicsObjectCount() - 1 do
			local phys = rag:GetPhysicsObjectNum(i)
			if IsValid(phys) then
				phys:EnableMotion(false)
				if ModelInfo.Solids[i]["parent"] then
					local parphys = rag:GetPhysicsObjectNum( BoneToPhysBone[ rag:LookupBone(ModelInfo.Solids[i]["parent"]) ] )
					if IsValid(parphys) then
						local pos, _ = WorldToLocal(phys:GetPos(), phys:GetAngles(), parphys:GetPos(), parphys:GetAngles())
						ModelInfo.Solids[i]["parentoffset"] = pos
					end
				end
			end
		end
		//Move physics bones
		for i = 0, rag:GetPhysicsObjectCount() - 1 do
			local phys = rag:GetPhysicsObjectNum(i)
			local matr = tab[rag:TranslatePhysBoneToBone(i)] //TODO: does PhysBoneToBone work as intended on hexed models?
			if IsValid(phys) then
				phys:Wake()
				if matr then
					local pos = nil
					if ModelInfo.Solids[i]["parent"] and ModelInfo.Solids[i]["parentoffset"] and ModelInfo.Solids[i]["parent"] != ModelInfo.Solids[i]["name"] then
						//Physobj has a parent physobj, so maintain its pos offset from the parent so it doesn't end up in a position that doesn't match its visuals
						local parphys = rag:GetPhysicsObjectNum( BoneToPhysBone[ rag:LookupBone(ModelInfo.Solids[i]["parent"]) ] )
						if IsValid(parphys) then
							pos = LocalToWorld(ModelInfo.Solids[i]["parentoffset"], Angle(), parphys:GetPos(), parphys:GetAngles())
						end
					else
						//Physobj doesn't have a parent physobj, so move it to the location from the matrix
						pos = matr:GetTranslation()
					end
					phys:SetPos(pos)
					phys:SetAngles(matr:GetAngles())
					if resized and i == 0 then rag:SetPos(pos) end //this doesnt happen immediately for resized ragdolls, so do this here so the animprop gets moved to the right place below
				end
				if !self.DoRagdollizeOnDamage then
					phys:EnableMotion(false)
					if IsValid(ply) then
						ply:AddFrozenPhysicsObject(nil, phys)  //the entity argument needs to be nil, or else it'll make a halo effect
					end
				else
					phys:EnableMotion(true)
				end
			end
		end

		//Manipulate non-phys bones
		if tab2 then
			for k, v in pairs (tab2) do
				if v.pos != Vector(0,0,0) then
					rag:ManipulateBonePosition(k, v.pos)
				end
				if v.ang != Angle(0,0,0) then
					rag:ManipulateBoneAngles(k, v.ang)
				end
				if v.scl != Vector(1,1,1) then
					rag:ManipulateBoneScale(k, v.scl)
				end
			end
		end

		if !self.DoRagdollizeOnDamage then
			//Move the animprop somewhere so it's not occupying the same space as the ragdoll any more
			timer.Simple(0.1, function() //Do this on a timer so we can get the ragdoll's new collision bounds after moving its physobjs
				if !IsValid(self) or !IsValid(rag) or IsValid(self:GetParent()) then return end 	//don't move us if we're parented
				local _, bboxtop1 = rag:GetCollisionBounds()						//move the animprop above the ragdoll, with some height to spare,
				local bboxtop2, _ = self:GetCollisionBounds()						//using this code copied from the advbonemerge unmerge function -
				local height = ( Vector(0,0,bboxtop1.z) + Vector(0,0,-bboxtop2.z) ) + Vector(0,0,0)	//position is the center of the ragdoll + the ragdoll's height +
				self:SetPos(rag:GetPos() + height)							//the animprop's height

				//Also give BuildBonePositions a nudge to prevent cases where the origin manip would keep showing the animprop in its old location
				AdvBone_ResetBoneChangeTime(self)
			end)
		end

		//Apply entity modifiers - we need to spawn and pose the ragdoll for these to work, so do these last
		rag.EntityMods = table.Copy(self.EntityMods) or {}
		rag.BoneMods = table.Copy(self.BoneMods)
		//Convert eye target from animprop's custom relative-to-origin to ragdoll's relative-to-eyes
		rag.EntityMods.eyetarget = nil
		local eyepos = self:LocalToWorld(self.EyeTargetLocal or Vector(1000,0,0))
		//Convert relative to eye attachment
		local eyeattachment = rag:LookupAttachment("eyes")
		if eyeattachment != 0 then
			local attachment = rag:GetAttachment(eyeattachment)
			if attachment then
				local LocalPos = WorldToLocal(eyepos, angle_zero, attachment.Pos, attachment.Ang )
				rag.EntityMods.eyetarget = {EyeTarget = LocalPos} 
			end
		end
		duplicator.ApplyEntityModifiers(ply, rag)
		duplicator.ApplyBoneModifiers(ply, rag)

		if IsValid(ply) and !self.DoRagdollizeOnDamage then
			//make death ragdolls behave the same way regarding entity limits as normal npcs with keep ragdolls turned on - they don't interact with them at all, 
			//they stop counting towards the npc/animprop limit but don't contribute to the ragdoll limit either, so players can pile up unlimited ragdolls this way.
			//this is probably bad but it's consistent with how npcs do it, so we'll fix it if they do.
			gamemode.Call("PlayerSpawnedRagdoll", ply, self:GetModel(), rag) //calls ply:AddCount("ragdolls", rag)
		end
		if !self.DoRagdollizeOnDamage then
			DoPropSpawnedEffect(rag)
		else
			//We're ragdollizing on damage, apply damage forces to the newly spawned ragdoll
			//Emulate as much of the original Valve ragdollizing code here as possible, to make the ragdolls look natural

			//dissolve the ragdoll; valve code calls this https://github.com/ValveSoftware/source-sdk-2013/blob/master/sp/src/game/server/baseanimating.cpp#L3433 which then calls this https://github.com/ValveSoftware/source-sdk-2013/blob/master/sp/src/game/server/EntityDissolve.cpp#L195
			if (bit.band(self.DoRagdollizeOnDamage.type, DMG_DISSOLVE) == DMG_DISSOLVE) then
				local dissolvetype = 0 //ENTITY_DISSOLVE_NORMAL (https://github.com/ValveSoftware/source-sdk-2013/blob/master/sp/src/game/shared/shareddefs.h#L323)
				if (bit.band(self.DoRagdollizeOnDamage.type, DMG_SHOCK) == DMG_SHOCK) then
					dissolvetype = 1 //ENTITY_DISSOLVE_ELECTRICAL
				end
				rag:Dissolve(dissolvetype, 250) //250 is what the dissolve effect defaults to, i think (https://github.com/ValveSoftware/source-sdk-2013/blob/master/sp/src/game/server/EntityDissolve.cpp#L85-L89)
			end
			if !(bit.band(self.DoRagdollizeOnDamage.type, DMG_REMOVENORAGDOLL) == DMG_REMOVENORAGDOLL)  then
				//Based off CBaseCombatCharacter::BecomeRagdoll (https://github.com/ValveSoftware/source-sdk-2013/blob/master/mp/src/game/server/basecombatcharacter.cpp#L1491)

				//Based off CBaseEntity *CreateServerRagdoll (https://github.com/ValveSoftware/source-sdk-2013/blob/master/mp/src/game/server/physics_prop_ragdoll.cpp#L1294)
				if (bit.band(self.DoRagdollizeOnDamage.type, DMG_VEHICLE) == DMG_VEHICLE) then
					//apply vehicle forces
					//valve code just above here has alternate vehicle damage code for singleplayer that always creates serverside ragdolls; gmod doesn't seem to be running it in 
					//singleplayer, so we'll ignore it to save time (and also because the one below looks a whole lot better)

					//slightly inspired by CBaseAnimating::GetHitboxesFrontside (https://github.com/ValveSoftware/source-sdk-2013/blob/master/sp/src/game/server/baseanimating.cpp#L3217)
					//the valve func for this is super overcomplicated, and retrieves all of the *hitboxes* whose bones' matrices have centers below the point of impact (determined
					//using dot products for some reason?), and then retrieves the associated physobjs of those hitboxes' bones. we can't do this, because we might not even have 
					//access to all the bone matrices (tab2 might not exist if player disabled that option; can't grab them from the ragdoll because resized ragdolls only set bone 
					//matrices clientside), so instead we cut the middlemen and just check the positions of the physobjs themselves. this should have basically the same results, 
					//except for cases where one physobj has multiple hitboxes and its force gets doubled up, which according to valve's comments is a *bug* anyway.
					local vehiclebones = {}
					local massScale = 0
					//Get a list of bones with hitboxes below the plane of impact
					for i = 0, rag:GetPhysicsObjectCount() - 1 do
						local phys = rag:GetPhysicsObjectNum(i)
						if IsValid(phys) then
							local pos = phys:GetPos() + phys:LocalToWorldVector(phys:GetMassCenter())
							if pos.z <= self.DoRagdollizeOnDamage.pos.z then
								vehiclebones[i] = true
							end
							massScale = massScale + phys:GetMass()
						end
					end
					//distribute force over mass of entire character
					massScale = 1/massScale
					for i, _ in pairs (vehiclebones) do
						local phys = rag:GetPhysicsObjectNum(i)
						if IsValid(phys) then
							phys:ApplyForceCenter(self.DoRagdollizeOnDamage.force * phys:GetMass() * massScale)
						end
					end
				else
					//Based off CRagdollProp::InitRagdoll (https://github.com/ValveSoftware/source-sdk-2013/blob/master/mp/src/game/server/physics_prop_ragdoll.cpp#L677), which then calls RagdollCreate (https://github.com/ValveSoftware/source-sdk-2013/blob/master/mp/src/game/shared/ragdoll_shared.cpp#L406)
					
					local totalmass = 0
					for i = 0, rag:GetPhysicsObjectCount() - 1 do
						local phys = rag:GetPhysicsObjectNum(i)
						if IsValid(phys) then
							totalmass = totalmass + phys:GetMass()
						end
					end

					local forcebone = 0
					if self.DoRagdollizeOnDamage.doforcebone then
						//first, check and see if there's a hitbox right where the damage hit us - this won't hit resized ragdolls at all since they 
						//haven't set themselves up yet. we have to check the ragdoll and not the animprop, because A: traces hit its collision hull,
						//not its hitboxes, and B: the hitboxes wouldn't be in the right places anyway because of BuildBonePositions being clientside
						local tr = util.TraceLine({
							start = self.DoRagdollizeOnDamage.pos - self.DoRagdollizeOnDamage.force,
							endpos = self.DoRagdollizeOnDamage.pos + self.DoRagdollizeOnDamage.force,
							filter = function(ent)
								return ent == rag
							end,
							ignoreworld = true
						})
						//debugoverlay.Line(dmg:GetDamagePosition() - dmg:GetDamageForce(), dmg:GetDamagePosition() + dmg:GetDamageForce(), 10)
						//debugoverlay.Line(tr.StartPos, tr.HitPos, 10, Color(255,0,0,255))
						if tr.Entity == rag then
							forcebone = tr.PhysicsBone
							//MsgN("got force bone ", self:GetBoneName(self:TranslatePhysBoneToBone(forcebone)), " (check 1)")
						else
							//if the traceline check didn't work, then get the physbone closest to where we took damage, huntsman-style
							local dist = math.huge
							for i = 0, rag:GetPhysicsObjectCount() - 1 do
								local phys = rag:GetPhysicsObjectNum(i)
								if IsValid(phys) then
									local dist2 = self.DoRagdollizeOnDamage.pos:Distance(phys:GetPos())
									if dist2 < dist then
										dist = dist2
										forcebone = i
									end
								end
							end
							//MsgN("got force bone ", self:GetBoneName(self:TranslatePhysBoneToBone(forcebone)), " (check 2)")
						end
					end
					local phys = rag:GetPhysicsObjectNum(forcebone)
					if IsValid(phys) then
						phys:ApplyForceCenter(self.DoRagdollizeOnDamage.force)
						self.DoRagdollizeOnDamage.pos = phys:GetPos()
					end
					if self.DoRagdollizeOnDamage.pos != Vector(0,0,0) then
						for i = 0, rag:GetPhysicsObjectCount() - 1 do
							if i != forcebone then
								local phys = rag:GetPhysicsObjectNum(i)
								if IsValid(phys) then
									local scale = phys:GetMass() / totalmass
									phys:ApplyForceOffset(self.DoRagdollizeOnDamage.force * scale, self.DoRagdollizeOnDamage.pos)
								end
							end
						end
					end

					//inherit velocity from animation (yes, this is applied after damage force)
					//based off RagdollApplyAnimationAsVelocity (https://github.com/ValveSoftware/source-sdk-2013/blob/master/mp/src/game/shared/ragdoll_shared.cpp#L458)
					if istable(self.PhysBoneVelocities) then
						for bone, tab in pairs (self.PhysBoneVelocities) do
							local phys = rag:GetPhysicsObjectNum(rag:TranslateBoneToPhysBone(bone))
							if IsValid(phys) then
								phys:AddVelocity(tab.vel)
								phys:AddAngleVelocity(phys:WorldToLocalVector(tab.angVel))
								//phys:SetAngleVelocity(tab.angVel)
							end
						end
						//PrintTable(self.PhysBoneVelocities)
					end
				end
			end

			//do killfeed notice
			hook.Call("OnNPCKilled", GAMEMODE, self, self.DoRagdollizeOnDamage.attacker, self.DoRagdollizeOnDamage.inflictor)

			//We can't just delete ourselves immediately - there could be a delay between when the client sees us die, and when they start drawing the ragdoll, especially with resized
			//ragdolls which have to spend some more time networking their bone table from the server.
			self:SetDeathRagdoll(rag) //when the client receives this value, it'll stop rendering us in Draw()
			self:SetRagdollizeOnDamage(false)
			hook.Call("CreateEntityRagdoll", GAMEMODE, self, rag) //reassigns undo to remove the ragdoll instead of us; TODO: could resized ragdolls potentially break addons using this hook?

			self:SetCollisionBounds(vector_origin,vector_origin)
			self:SetMoveType(MOVETYPE_NONE)
			//self:SetSolid(SOLID_NONE)
			self:SetVelocity(vector_origin)
			self:PhysicsDestroy()
			self:Extinguish()
			self:DrawShadow(false)
			self:SetEnableAnimEventEffects(false)

			timer.Simple(1, function() if IsValid(self) then self:Remove() end end)
			rag:DeleteOnRemove(self) //failsafe for if the player undoes the ragdoll while we're still waiting to be removed - otherwise we'll start rendering again
		end
		return rag

	end

	util.AddNetworkString("AnimProp_Ragdollize_SendToCl")

	function ENT:OnTakeDamage(dmg)

		if self:GetRagdollizeOnDamage() and self:Health() > 0 and dmg:GetDamage() > 0 and !self.DoRagdollizeOnDamage and util.IsValidRagdoll(self:GetModel()) then

			//Our bone positions are controlled by BuildBonePositions, so they only exist clientside. This means if we want to die from serverside damage and
			//spawn a serverside ragdoll, we still need a client to give us the bone positions.
			local ply = nil
			if game.SinglePlayer() then
				ply = player.GetByID(1)
			else
				local nearbyPlayers = {}
				local allPlayers = player.GetHumans() //filter out bots, they can't do ragdollize (i don't *think* they have simulated clients at all?)
				for _, ply in pairs (allPlayers) do
					if self:TestPVS(ply) then
						table.insert(nearbyPlayers, ply)
					end
				end
				local function TryPlayer(tab, candidate)
					if !IsValid(ply) and table.KeyFromValue(tab, candidate) then
						ply = candidate
					end
				end

				//First, try to get our best candidate from the players that can see us, to try to make sure they've gotten our BoneInfo table
				TryPlayer(nearbyPlayers, self:GetPlayer()) //first, see if our owner is nearby
				TryPlayer(nearbyPlayers, dmg:GetAttacker()) //next, see if the attacker that killed us is a nearby player
				if !IsValid(ply) then
					ply = nearbyPlayers[1] //if those didn't work, then just try to get someone who can see us
				end
				if !IsValid(ply) then
					//There aren't any players who can see us, broaden our search to everyone in the server
					TryPlayer(allPlayers, self:GetPlayer()) //try our owner first, since they're the most likely to have seen us already and gotten our BoneInfo table
					TryPlayer(allPlayers, dmg:GetAttacker()) //now try our attacker again, maybe they spawned a dynamite or threw a grenade or something, then ran away
				end
				if !IsValid(ply) then
					ply = allPlayers[1] //we have no owner, weren't killed by a player, and no one can see us? things aren't looking good, but pick some random chump as a last
				end			    //ditch effort. if this doesn't work, then we just won't ragdollize.
			end

			if IsValid(ply) then

				//Try to ragdollize just like a default NPC, so we copy as much Valve ragdollizing code as possible
				//Based off CBaseCombatCharacter::Event_Killed (https://github.com/ValveSoftware/source-sdk-2013/blob/master/mp/src/game/server/basecombatcharacter.cpp#L1582)

				//Based off CBaseCombatCharacter::CalcDamageForceVector (https://github.com/ValveSoftware/source-sdk-2013/blob/master/mp/src/game/server/basecombatcharacter.cpp#L1582)
				local function CalcDamageForceVector()
					// Already have a damage force in the data, use that.
					local noforce = dmg:IsDamageType(DMG_PARALYZE + DMG_NERVEGAS + DMG_POISON + DMG_RADIATION + DMG_DROWNRECOVER + DMG_ACID + DMG_SLOWBURN //CMultiplayRules::Damage_GetTimeBased (https://github.com/ValveSoftware/source-sdk-2013/blob/master/sp/src/game/shared/multiplay_gamerules.cpp#L156)
					+ DMG_FALL + DMG_BURN + DMG_PLASMA + DMG_DROWN + DMG_CRUSH + DMG_PHYSGUN + DMG_PREVENT_PHYSICS_FORCE) //CMultiplayRules::Damage_NoPhysicsForce (https://github.com/ValveSoftware/source-sdk-2013/blob/master/sp/src/game/shared/multiplay_gamerules.cpp#L237)
					if dmg:GetDamageForce() != Vector(0,0,0) or noforce then
						if dmg:IsDamageType(DMG_BLAST) then
							// Fudge blast forces a little bit, so that each
							// victim gets a slightly different trajectory. 
							// This simulates features that usually vary from
							// person-to-person variables such as bodyweight,
							// which are all indentical for characters using the same model.
							local scale = math.Rand(0.85, 1.15)
							local force = dmg:GetDamageForce()
							force.x = force.x * scale
							force.y = force.y * scale
							// Try to always exaggerate the upward force because we've got pretty harsh gravity
							if force.z > 0 then
								force.z = force.z * 1.15
							else
								force.z = force.z * scale
							end
							return force
						end
						return dmg:GetDamageForce()
					end

					local pForce = dmg:GetInflictor()
					if !IsValid(pForce) then
						pForce = dmg:GetAttacker()
					end

					if IsValid(pForce) then
						// Calculate an impulse large enough to push a 75kg man 4 in/sec per point of damage
						local forceScale = dmg:GetDamage() * 75 * 4

						local forceVector = Vector()
						// If the damage is a blast, point the force vector higher than usual, this gives 
						// the ragdolls a bodacious "really got blowed up" look.
						if dmg:IsDamageType(DMG_BLAST) then
							// exaggerate the force from explosions a little (37.5%)
							forceVector = (self:GetPos() + Vector(0, 0, self:OBBMaxs().z - self.OBBMins().z) ) - pForce:GetPos()
							forceVector:Normalize()
							forceVector = forceVector * 1.375
						else
							// taking damage from self?  Take a little random force, but still try to collapse on the spot.
							if pForce == self then
								forceVector = Vector(math.Rand(-1,1), math.Rand(-1,1), 0)
								forceScale = math.Rand(1000,2000)
							else
								// UNDONE: Collision forces are baked in to CTakeDamageInfo now
								// UNDONE: Is this MOVETYPE_VPHYSICS code still necessary?
								if pForce:GetMoveType() == MOVETYPE_VPHYSICS then
									// killed by a physics object
									local phys = self:GetPhysicsObject()
									if !IsValid(phys) then
										phys = pForce:GetPhysicsObject()
									end
									forceVector = phys:GetVelocity()
									forceScale = phys:GetMass()
								else
									forceVector = self:GetPos() - pForce:GetPos()
									forceVector:Normalize()
								end
							end
						end
						return forceVector * forceScale
					end
				end
				local forceVector = CalcDamageForceVector()

				self.DoRagdollizeOnDamage = {
					["type"] = dmg:GetDamageType(),
					["force"] = forceVector or Vector(0,0,0),
					["pos"] = dmg:GetDamagePosition(),
					["doforcebone"] = self.LastTraceHit == CurTime(),
					["attacker"] = dmg:GetAttacker(),
					["inflictor"] = dmg:GetInflictor(),
					["time"] = CurTime() + 5
				}

				self:SetHealth(0) //try to make sure we can't get damaged more than once, which can happen in some cases like physics collisions

				net.Start("AnimProp_Ragdollize_SendToCl")
					net.WriteEntity(self)
				net.Send(ply)

				//the rest is performed in the serverside ragdollize function, once we get the info back from the client

			end

		end

	end

	hook.Add("ScaleNPCDamage", "Animprop_Ragdollize_ScaleNPCDamage", function(npc, hitgroup, dmg) 
		if npc:GetClass() == "prop_animated" then ///and hitgroup != 0 then //doesn't work, always returns hitgroup 0 because trace attacks hit our collision hull and not our hitboxes
			npc.LastTraceHit = CurTime()
		end
	end)

	//doesn't get called, why not?
	--[[function ENT:PhysicsCollide(data, phys2)
		MsgN("physicscollide")
		PrintTable(data)
	end]]

end




//TODO: hl1 scientist's c1a4_dying_speech, push_button2, and more don't seem to be using either of these to play sounds; i think the anim is playing a scene or something and i don't think we have a hook for that

if SERVER then

	function ENT:HandleAnimEvent(event, eventTime, cycle, type, options)

		--[[MsgN("event ", event)
		MsgN("type ", type)
		MsgN("options ", options)
		MsgN("")]]

		if event == 25 or event == 35 then //kill and ragdollize entity, found in several models' death anims (25 in zombine's alyx_zombie_fight2, hunter's death_stagger; 35 in heavy's diesimple)
			return true
		elseif !self:GetEnableAnimEventEffects() and (event == 1004) then //play sound, found on HL1 scientist's default anim
			return true
		end

	end

elseif CLIENT then

	function ENT:FireAnimationEvent(pos, ang, event, name)

		--[[MsgN("event ", event)
		MsgN("name ", name)
		MsgN("")]]

		if !self:GetEnableAnimEventEffects() and (event == 15 or event == 5004 //play sound, found on HL2 dog and newer TF2 taunt anims
		or event == 6004 or event == 6005 or event == 6006 or event == 6007 or event == 6008 or event == 6009 //play footstep sound, found on HL2 characters
		or event == 32) then //create particle effect, found on TF2 taunt anims
			return true
		end

	end

end




if CLIENT then

	local Animprop_IsSkyboxDrawing = false

	hook.Add("PreDrawSkyBox", "Animprop_IsSkyboxDrawing_Pre", function()
		Animprop_IsSkyboxDrawing = true
	end)

	hook.Add("PostDrawSkyBox", "Animprop_IsSkyboxDrawing_Post", function()
		Animprop_IsSkyboxDrawing = false
	end)

	function ENT:Draw(flag)

		//try to prevent this from being rendered additional times if it has a child with EF_BONEMERGE; TODO: i can't find any situation where this breaks anything, but it still feels like it could.
		if flag == 0 then
			return
		end

		//Stop drawing us once the client starts drawing our death ragdoll - for resized ragdolls, we have to wait a bit for the client to receive the scale table and set it up
		local rag = self:GetDeathRagdoll()
		if IsValid(rag) then
			if !(rag.ClassOverride == "prop_resizedragdoll_physparent") or rag.PhysBones then
				self:SetNoDraw(true)
				//self:DestroyShadow()
				return
			end
		end

		//Don't draw in the 3D skybox if our renderbounds are clipping into it but we're not actually in there
		//(common problem for ents with big renderbounds on gm_flatgrass, where the 3D skybox area is right under the floor)
		if Animprop_IsSkyboxDrawing and !self:GetNWBool("IsInSkybox") then return end
		//TODO: Fix opposite condition where ent renders in the world from inside the 3D skybox area (i.e. gm_construct) - we can't just do the opposite of this because
		//we still want the ent to render in the world if the player is also in the 3D skybox area with them, but we can't detect if the player is in that area clisntside

		//(Advanced Bonemerge) Don't render until we've got our boneinfo table 
		//(TODO: doesn't work, always returns true? changing it to !self.AdvBone_BoneInfo (which is a bad idea, causes problems if advbone addon isn't installed) doesn't work either.)
		if !self.AdvBone_BoneInfo_Received then return end

		//(Advanced Bonemerge) Don't draw ents attached to the player in first person view
		local function GetTopmostParentPlayer(ent)
			//Keep going up the parenting hierarchy until we get to localplayer.
			local par = ent:GetParent()
			if IsValid(par) then
				if par == LocalPlayer() then
					return par
				else
					return GetTopmostParentPlayer(par)
				end
			end
		end
		if !self.IsPuppeteer and GetTopmostParentPlayer(self) then
			shoulddraw = LocalPlayer():ShouldDrawLocalPlayer()
			//if !self:IsEffectActive(EF_NOSHADOW) then
				if !shoulddraw then
					if !self.RemovedLocalplayerShadow then
						self.RemovedLocalplayerShadow = true
						self:DestroyShadow()
					end
					return
				elseif shoulddraw and self.RemovedLocalplayerShadow then
					self.RemovedLocalplayerShadow = nil
					//if !self:IsEffectActive(EF_NOSHADOW) then
						self:CreateShadow()
					//end
				end
			//end
		end


		//Set the eye target: animprops have custom eye posing functionality that targets a point relative to the entity, 
		//instead of a point in worldspace (like npcs) or a point relative to our eye attachment (like ragdolls)
		local pos = self:LocalToWorld(self.EyeTargetLocal or Vector(1000,0,0))
		self.DontLocalizeEyePose = true
		self:SetEyeTarget(pos)
		self.DontLocalizeEyePose = nil


		//For some reason I can't explain, setting a puppeteer's alpha to 0 with SetColor causes its BuildBonePositions hook to stop running, making it useless as a puppeteer 
		//(this ONLY happens with puppeteers, not other animprops or advbonemerged stuff!), so we need to handle its transparency in-code here.
		if self.IsPuppeteer then
			if !self:GetPuppeteerAlpha() then
				//SetBlend(0) still renders some materials that don't support transparency like character's eyes and mouths, so set a material override as well
				render.SetBlend(0)
				self:SetMaterial("model_color")
			else
				self:SetMaterial("")
			end
		end
		self:DrawModel()
		if self.IsPuppeteer then
			//Reset blending value once we're done so it doesn't bleed into other draw funcs
			render.SetBlend(1)
		end


		if !IsValid(self:GetParent()) then
			//Don't draw the grip if there's no chance of us picking it up
			local ply = LocalPlayer()
			local wep = ply:GetActiveWeapon()
			if ( !IsValid( wep ) ) then return end
			local weapon_name = wep:GetClass()
			if ( weapon_name != "weapon_physgun" && weapon_name != "weapon_physcannon" && weapon_name != "gmod_tool" ) then return end

			local mode = self:GetPhysicsMode()
			if mode == 2 then
				//Draw the effect grip ring
				if GetConVarNumber("cl_draweffectrings") == 0 then return end

				local size = math.Clamp(1 + ((self:GetModelScale() - 1) * 0.5), 1, 50) //effect grip scales up half as fast as the prop itself
				local mins, maxs = self:GetCollisionBounds()
				if self:BoxBeingLookedAt(mins, maxs) then
					render.SetMaterial(self.GripMaterialHover)
				else
					render.SetMaterial(self.GripMaterial)
				end
				render.DrawSprite(self:GetPos() + (self:GetUp() * (maxs.z / 2)), 16 * size, 16 * size, color_white)
			elseif mode == 1 then
				//Draw physics box
				if GetConVarNumber("cl_animprop_drawphysboxes") == 0 then return end

				local mins, maxs = self:GetCollisionBounds()
				render.DrawWireframeBox(self:GetPos(), self:GetAngles(), mins, maxs, color_white, true)
			end
		end
		
	end

	function ENT:BoxBeingLookedAt(mins, maxs) //modified from ENT:BeingLookedAtByLocalPlayer() (https://github.com/Facepunch/garrysmod/blob/master/garrysmod/gamemodes/sandbox/entities/entities/base_gmodentity.lua#L10)
		
		local ply = LocalPlayer()
		if !IsValid(ply) then return false end

		local view = ply:GetViewEntity()
		local dist = self.MaxWorldTipDistance
		dist = dist * dist

		local pos, fwd
		if view:IsPlayer() then
			//If we're spectating a player, perform an eye trace
			pos = view:EyePos()
			fwd = view:GetAimVector()
		else
			//If we're not spectating a player, perform a manual trace from the entity's position
			pos = view:GetPos()
			fwd = view:GetAngles():Forward()
		end

		if pos:DistToSqr(self:GetPos()) <= dist then
			local tr1 = util.TraceLine({
				start = pos,
				endpos = pos + (fwd * dist),
				filter = {view, self}
			})
			local tr2_hit, _, tr2_frac = util.IntersectRayWithOBB(pos, fwd * dist, self:GetPos(), self:GetAngles(), mins, maxs)
			return tr2_hit and tr2_frac < tr1.Fraction //if the trace hits the prop's collision box BEFORE it hits another entity, then we're good!
		end
		
	end

	//function ENT:DrawTranslucent()
	//
	//	self:Draw()
	//
	//end

end




function ENT:OnEntityCopyTableFinish(data)

	//Don't store these DTvars
	if data.DT then
		for i = 1, 4 do
			data.DT["Channel" .. i .. "LayerID"] = nil
			data.DT["Channel" .. i .. "NumpadState"] = nil
		end
		data.DT["Puppeteer"] = nil
	end

	//Store sequences as strings instead of IDs - otherwise, if the model gets updated with new animations, the IDs will shift around and animprop dupes/saves will be playing the wrong 
	//animations since the sequence IDs correspond to different things now
	local tab = {}
	for i = 1, 4 do
		local sequencename = string.lower( self:GetSequenceName( self["GetChannel" .. i .. "Sequence"](self) ) or "" )
		if self["GetChannel" .. i .. "Sequence"](self) < 0 then sequencename = "" end
		tab[i] = sequencename
	end
	data.SequenceStrings = tab

	//Store puppeteer info
	//We won't use most of this, but using the duplicator function here is a lot more efficient than copying all of the code in this function to process stuff like the DTvars and sequence strings
	local puppeteer = self:GetPuppeteer()
	if IsValid(puppeteer) then
		local puppeteerinfo = table.Copy( duplicator.CopyEntTable(puppeteer) )
		data.PuppeteerInfo = puppeteerinfo
	end


	//(Advanced Bonemerge)
	//As it turns out, the game absolutely WILL store and even network ent:ManipulateBoneX(-1) (what we use for model origin manips) even though it's not a valid bone. 
	//However, entity saving glosses over it since it only searches bones 0 and onward, so we have to save the information ourselves:

	data.BoneManip = data.BoneManip or {}

	local t = {}
			
	local s = self:GetManipulateBoneScale(-1)
	local a = self:GetManipulateBoneAngles(-1)
	local p = self:GetManipulateBonePosition(-1)
			
	if ( s != Vector(1, 1, 1) ) then t[ 's' ] = s end //scale
	if ( a != angle_zero ) then t[ 'a' ] = a end //angle
	if ( p != vector_origin ) then t[ 'p' ] = p end //position
		
	if ( table.Count( t ) > 0 ) then
		data.BoneManip[-1] = t
	end


	data.AdvBone_BoneManips = nil //don't save this table, everything in it has already been saved in Data.BoneManip by the duplicator save function


	//Store DisableBeardFlexifier nwbool
	data.DisableBeardFlexifier = self:GetNWBool("DisableBeardFlexifier")

end

duplicator.RegisterEntityClass("prop_animated", function(ply, data)

	if IsValid(ply) and !ply:CheckLimit("animprops") then return false end

	local ent = ents.Create("prop_animated")
	if (!ent:IsValid()) then return false end

	//Handle stored sequence strings, convert them back to IDs
	ent:SetModel(data.Model) //set the model now so we can retrieve its sequences
	if data.SequenceStrings then
		for i = 1, 4 do
			local seq = ent:LookupSequence(data.SequenceStrings[i])
			data.DT["Channel" .. i .. "Sequence"] = seq
		end
	end

	//(Advanced Bonemerge)
	//NOTE: We rely on our own bonemanip system to store the values instead of garrymanips, because garrymanips mess up renderbounds and cap pos/scale values -
	//however, we still save them in data.BoneManip (when the entity is saved) and load them from data.BoneManip (with duplicator.DoGeneric) because we don't want 
	//things to mess up if the advbone addon is uninstalled when the entity is saved but installed when it's loaded, or vice versa (don't want two tables with conflicting information)
	ent.AdvBone_BoneManips = {}
	ent.AdvBone_BoneManips_DontNetwork = true //the entity hasn't been initialized on clients yet, so don't network the manips yet - they'll handle it themselves once they're ready

	//Handle eye poser dupes
	ent.EyeTargetLocal = data.EyeTargetLocal
	if data.EntityMods and data.EntityMods.eyetarget then data.EntityMods.eyetarget = nil end  //get rid of the saved eyetarget, it's useless for this ent and it'll break stuff

	//only applies to in-dev dupes from back when there were less numpad modes, won't apply to users once addon is released
	for i = 1, 4 do
		if isbool(data.DT["Channel" .. i .. "NumpadMode"]) then
			data.DT["Channel" .. i .. "NumpadMode"] = tonumber(data.DT["Channel" .. i .. "NumpadMode"])
		end
	end

	//duplicator.GenericDuplicatorFunction(ply, data) //if we use this function, the networkvars won't be networked to clients for some reason
	duplicator.DoGeneric(ent, data)

	ent:SetPlayer(ply) //NOTE: this still works if ply doesn't exist
	ent.PoseParams = data.PoseParams

	//(Advanced Bonemerge)
	ent.AdvBone_BoneManips_DontNetwork = nil
	ent.AdvBone_BoneInfo = data.AdvBone_BoneInfo
	if !data.IsAdvBonemerged then
		//If we're not merged, then we might still want this to be true if we've never modified the boneinfo table while merged before.
		ent.AdvBone_BoneInfo_IsDefault = data.AdvBone_BoneInfo_IsDefault
	else
		//But if we are merged, then we definitely want this to be false.
		ent.AdvBone_BoneInfo_IsDefault = false
	end
	if data.AdvBone_BoneInfo then
		//Fix for old dupes - if the model has since been updated to have more bones than it does now, then create default BoneInfo entries so that we won't get any errors
		//(the dupes will still be horribly broken since the bone indices won't match up any more, but there's not a whole lot we can do about that, short of rewriting 
		//the whole system to use bone name strings instead of bone index numbers for the table keys just to fix this one problem)
		for i = -1, ent:GetBoneCount() - 1 do
			if ent.AdvBone_BoneInfo[i] == nil and (ent:GetBoneName(i) != "__INVALIDBONE__" or i == -1) then
				//MsgN("added missing boneinfo entry for bone #" .. i .. " (" .. ent:GetBoneName(i) .. ")")
				ent.AdvBone_BoneInfo[i] = {
					parent = "",
					scale = true,
				}
			end
		end
	end
	ent.IsAdvBonemerged = data.IsAdvBonemerged
	ent:SetNWBool("DisableBeardFlexifier", data.DisableBeardFlexifier)

	ent:Spawn()
	ent:Activate()

	if IsValid(ply) then ply:AddCount("animprops", ent) end

	//Recreate puppeteer using saved info
	if data.PuppeteerInfo and data.PuppeteerInfo.Model and data.PuppeteerInfo.DT and (!IsValid(ply) or ply:CheckLimit("animprops")) then
		local puppeteer = ent:SetPuppeteerModel(data.PuppeteerInfo.Model, ply, data.RemapInfo) //calls ply:AddCount("animprops", prop) for puppeteer

		if IsValid(puppeteer) then
			//Repetition, bleh
			//Handle stored sequence strings, convert them back to IDs
			if data.PuppeteerInfo.SequenceStrings then
				for i = 1, 4 do
					local seq = puppeteer:LookupSequence(data.PuppeteerInfo.SequenceStrings[i])
					data.PuppeteerInfo.DT["Channel" .. i .. "Sequence"] = seq
				end
			end

			puppeteer.PoseParams = data.PuppeteerInfo.PoseParams

			if puppeteer.RestoreNetworkVars then
				puppeteer:RestoreNetworkVars(data.PuppeteerInfo.DT) //apparently this is how duplicator.DoGeneric restores the DT on regular animprops
			end

			//Fix: Numpad keys don't work on puppeteers created by the duplicator for some reason (thought it was because ply was nil when the puppeteer initialized,
			//but fixing that didn't change anything!) until we set them again, so do that now
			for i = 1, 4 do
				local key = data.PuppeteerInfo.DT["Channel" .. i .. "Numpad"]
				numpad.Remove(puppeteer["NumDown" .. i])
				numpad.Remove(puppeteer["NumUp" .. i])
				puppeteer["NumDown" .. i] = numpad.OnDown(ply, key, "Animprop_Numpad", puppeteer, i, true)
				puppeteer["NumUp" .. i] = numpad.OnUp(ply, key, "Animprop_Numpad", puppeteer, i, false)
			end
		end
	end

	duplicator.DoGenericPhysics(ent, ply, data)

	return ent

end, "Data")































///////////////////////
//REMAPPING FUNCTIONS//
///////////////////////

if SERVER then

	function ENT:SetPuppeteerModel(model, ply, remapinfo)

		//If we're setting to a bad model (i.e. a blank string) then clear the puppeteer if we have one. If we're setting to the model that our puppeteer already has, then do nothing.
		local oldent = self:GetPuppeteer()
		if !util.IsValidModel(model) or model == self:GetModel() then
			if IsValid(oldent) then
				oldent:Remove()
				self.RemapInfo = nil
			end
			return false
		elseif IsValid(oldent) and model == oldent:GetModel() then
			return false
		else
			if IsValid(oldent) then
				oldent:Remove()
				self:SetPuppeteer(NULL)
			end
			self.RemapInfo = nil
			//give clients a nudge telling them the remapinfo is out of date - otherwise, if we go straight from one puppeteer to another without it being NULL in between, the client
			//will never realize it needs to ask for a new table for the new puppeteer, and so the new puppeteer won't work at all since it doesn't set self.IsPuppeteer clientside
			net.Start("AnimProp_RemapInfoTableUpdate_SendToCl")
				net.WriteEntity(self)
			net.Broadcast()
		end
		if !IsValid(ply) then ply = self:GetPlayer() end

		local dummy = ents.Create("prop_dynamic")
		dummy:SetPos(self:GetPos())
		dummy:SetAngles(self:GetAngles())
		dummy:SetModel(model)
		dummy:Spawn()
		dummy:Activate()
		if !IsValid(dummy) then return false end

		local animprop = ConvertEntityToAnimprop(dummy, ply, true, true, false, true) //note: ent.IsPuppeteer is set serverside by this function, before initializing the entity
		if IsValid(dummy) then dummy:Remove() end
		if !IsValid(animprop) then self.RemapInfo = nil return false end
		animprop.DoNotDuplicate = true //TODO: why are there two of these? what's the difference? from https://wiki.facepunch.com/gmod/Structures/ENT
		animprop.DisableDuplicator = true

		//Stop all of our own animations
		//Try to make sure models with a non-reference default pose (i.e. HL2 zombies) use a reference pose instead
		local defaultact = self:GetSequenceActivity(0)
		if defaultact != ACT_INVALID and defaultact != ACT_DIERAGDOLL then
			local sequence = self:SelectWeightedSequence(ACT_DIERAGDOLL)
			if sequence != -1 then
				self["SetChannel1Sequence"](self, sequence)
			else
				self["SetChannel1Sequence"](self, -1)
			end
		else
			self["SetChannel1Sequence"](self, -1)
		end
		for i = 1, 4 do
			if i != 1 then
				self["SetChannel" .. i .. "Sequence"](self, -1)
			end
			self["SetChannel" .. i .. "PauseFrame"](self, 0)
			self:StartAnimation(i)
		end
		self:SetControlMovementPoseParams(false)

		//Do the same check for bad default poses on the puppeteer
		local defaultact = animprop:GetSequenceActivity(0)
		if defaultact != ACT_INVALID and defaultact != ACT_DIERAGDOLL then
			local sequence = animprop:SelectWeightedSequence(ACT_DIERAGDOLL)
			if sequence != -1 then
				animprop["SetChannel1Sequence"](animprop, sequence)
			end
		end

		animprop:SetParent(self)
		animprop:FollowBone(self, self:GetBoneCount() - 1) //this prevents some invisible bones (i.e. tf2 models' weapon_bone) from returning bad angles when remapped, through some arcane means
		self:SetPuppeteer(animprop)
		self:DeleteOnRemove(animprop)

		//Have a dummy ent use FollowBone to expose all of the entity's bones. If we don't do this, a whole bunch of bones can return as invalid clientside, 
		//as well as return the wrong locations serverside.
		local lol = ents.Create("base_point")
		if IsValid(lol) then
			lol:SetPos(animprop:GetPos())
			lol:SetAngles(animprop:GetAngles())
			lol:FollowBone(animprop,0)
			lol:Spawn()
			lol:Remove() //We don't need the ent to stick around. All we needed was for it to use FollowBone once.
		end


		if remapinfo then
			self.RemapInfo = table.Copy(remapinfo)
		else
			local function GetModelSkeletonID(ent)
				local mostmatches = 0
				local skeletonmatches = {}
				//Go through the whole table of skeletons and check how many of their bone names match the ones on our model
				for skeletonid, subtable in pairs(Animprop_RemapTranslationSkeletons) do
					local matches = 0
					for _, bonename in pairs(subtable) do
						if ent:LookupBone(bonename) then
							matches = matches + 1
						end
					end
					mostmatches = math.max(matches, mostmatches)
					skeletonmatches[skeletonid] = matches
				end
				if mostmatches == 0 then
					return nil
				else
					return table.KeyFromValue(skeletonmatches, mostmatches) //Resolve ties by using the first matching skeleton in the table
				end
			end
			local skeletonid_puppet = GetModelSkeletonID(self)
			local skeletonid_puppeteer = GetModelSkeletonID(animprop)

			local function GetMatchingBone(name)
				local answer = ""

				//Translate between different skeletons with different names for the same bone
				if skeletonid_puppet and skeletonid_puppeteer then
					local remapid = table.KeyFromValue(Animprop_RemapTranslationSkeletons[skeletonid_puppet], name)
					if remapid then
						answer = Animprop_RemapTranslationSkeletons[skeletonid_puppeteer][remapid]
					end
				end
				//Match by name for the rest of them
				if answer == "" and animprop:LookupBone(name) then
					//Don't do this if that bone on the puppeteer is already being remapped to another bone on the puppet (i.e. pelvis when HL2 fastzombie has HL2 human puppeteer)
					if !(skeletonid_puppet and skeletonid_puppeteer and table.KeyFromValue(Animprop_RemapTranslationSkeletons[skeletonid_puppeteer], name)) then
						answer = name
					end
				end

				return string.lower(answer)
			end

			local remapinfo = {}
			for i = 0, self:GetBoneCount() - 1 do
				local newsubtable = {
					parent = GetMatchingBone(self:GetBoneName(i)),
					ang = Angle(),
				}
				remapinfo[i] = newsubtable
			end
			self.RemapInfo = remapinfo
		end


		animprop:DrawShadow(false)
		animprop:SetPuppeteerAlpha(true)

		local min, max = self:GetModelBounds()
		local min2, max2 = animprop:GetModelBounds()
		animprop:SetPuppeteerPos(Vector(0, max.y + -min2.y + 10, 0))


		return animprop

	end


	util.AddNetworkString("AnimProp_RemapInfoTable_GetFromSv")
	util.AddNetworkString("AnimProp_RemapInfoTable_SendToCl")
	util.AddNetworkString("AnimProp_RemapInfoFromEditor_SendToSv")
	util.AddNetworkString("AnimProp_RemapInfoTableUpdate_SendToCl")


	//If we received a request for a remapinfo table, then send it to the client
	net.Receive("AnimProp_RemapInfoTable_GetFromSv", function(_, ply)
		local ent = net.ReadEntity()
		if !IsValid(ent) or ent:GetClass() != "prop_animated" or !ent.RemapInfo or !ent.GetPuppeteer or !IsValid(ent:GetPuppeteer()) then return end

		net.Start("AnimProp_RemapInfoTable_SendToCl", true)
			net.WriteEntity(ent)

			net.WriteInt(table.Count(ent.RemapInfo), 9)
			for key, entry in pairs (ent.RemapInfo) do
				net.WriteInt(key, 9)

				net.WriteInt(ent:GetPuppeteer():LookupBone( entry["parent"] ) or -1, 9)
				net.WriteAngle(entry["ang"])
			end
		net.Send(ply)
	end)


	//If we received remapinfo from the client (for one specific bone, sent by using the editor window), then apply it to the table
	net.Receive("AnimProp_RemapInfoFromEditor_SendToSv", function(_, ply)
		local ent = net.ReadEntity()
		local entbone = net.ReadInt(9)

		local newtargetbone = net.ReadInt(9)
		local newang = net.ReadAngle()

		local demofix = net.ReadBool()

		if IsValid(ent) and ent:GetClass() == "prop_animated" and IsValid(ent:GetPuppeteer()) and ent.RemapInfo and ent.RemapInfo[entbone] then
			if newtargetbone != -1 then
				ent.RemapInfo[entbone]["parent"] = ent:GetPuppeteer():GetBoneName(newtargetbone)
			else
				ent.RemapInfo[entbone]["parent"] = ""
			end

			ent.RemapInfo[entbone]["ang"] = newang

			//Tell all the other clients that they need to update their RemapInfo tables to receive the changes (the original client already has the changes applied)
			local filter = RecipientFilter()
			filter:AddAllPlayers()
			if !demofix then filter:RemovePlayer(ply) end //Fix for demo recording - demos don't record remapinfo changes made by the editor window, but they DO record network activity, so if ply was recording a demo, then send them a table update too
			net.Start("AnimProp_RemapInfoTableUpdate_SendToCl")
				net.WriteEntity(ent)
			net.Send(filter)
		end
	end)

else

	//If we received a remapinfo table from the server, then use it
	net.Receive("AnimProp_RemapInfoTable_SendToCl", function()
		local ent = net.ReadEntity()
		local puppeteer = nil

		if IsValid(ent) and ent.GetPuppeteer and IsValid(ent:GetPuppeteer()) then
			puppeteer = ent:GetPuppeteer()
			//Make sure we get the right results from GetBoneName - if the client hasn't seen the model yet then it might return __INVALIDBONE__ when it shouldn't
			puppeteer:DrawModel()
			puppeteer:SetupBones()
		end

		local count = net.ReadInt(9)
		local tab = {}
		for i = 1, count do
			local key = net.ReadInt(9)

			local parentstr = ""
			local parentint = net.ReadInt(9)
			if IsValid(ent) and IsValid(puppeteer) then
				parentstr = puppeteer:GetBoneName(parentint)
				if parentstr == "__INVALIDBONE__" then parentstr = "" end
			end

			tab[key] = {
				["parent"] = parentstr,
				["ang"] = net.ReadAngle(),
			}
		end

		if IsValid(ent) and IsValid(puppeteer) then
			ent.RemapInfo = tab
			ent.RemapInfo_Received = true
			puppeteer.IsPuppeteer = true

			//Wake up BuildBonePositions and get it to use the new info
			ent.RemapInfo_RemapAngOffsets = nil
			ent.LastBoneChangeTime = CurTime()
		end
	end)


	//If we received a message from the server telling us an ent's RemapInfo table is out of date, then change its RemapInfo_Received value so its Think function requests a new one
	net.Receive("AnimProp_RemapInfoTableUpdate_SendToCl", function()
		local ent = net.ReadEntity()
		if !IsValid(ent) or ent:GetClass() != "prop_animated" then return end

		ent.RemapInfo_Received = false
	end)

end































////////////////////////////////
//ADVANCED BONEMERGE FUNCTIONS//
////////////////////////////////

if CLIENT then

	function ENT:DoAdvBonemerge()

		//If the adv bonemerge addon isn't installed, then create a placeholder boneinfo table since the ent's not going to get one
		if !duplicator.FindEntityClass("ent_advbonemerge") and !self.AdvBone_BoneInfo_Received then
			local boneinfo = {}
			for i = -1, self:GetBoneCount() - 1 do
				local newsubtable = {
					parent = "",
					scale = false,
				}
				boneinfo[i] = newsubtable
			end
			self.AdvBone_BoneInfo = boneinfo
			self.AdvBone_BoneInfo_Received = true

			self.AdvBone_Uninstalled = true //save result of this to a var so we don't have every single bone check !duplicator.FindEntityClass("ent_advbonemerge") for scale stuff
		end

		//Create a clientside advbone manips table so that it gets filled when the server sends us values
		self.AdvBone_BoneManips = self.AdvBone_BoneManips or {}

		//Store hitbox bounds by bone; we use these to help with renderbounds
		self.AdvBone_BoneHitBoxes = {}
		for i = 0, self:GetHitboxSetCount() - 1 do
			for j = 0, self:GetHitBoxCount(i) - 1 do
				local id = self:GetHitBoxBone(j, i)
				local min, max = self:GetHitBoxBounds(j, i)
				if self.AdvBone_BoneHitBoxes[id] then
					local min2 = self.AdvBone_BoneHitBoxes[id].min
					local max2 = self.AdvBone_BoneHitBoxes[id].max
					self.AdvBone_BoneHitBoxes[id].min = Vector(math.min(min.x,min2.x), math.min(min.y,min2.y), math.min(min.z,min2.z))
					self.AdvBone_BoneHitBoxes[id].max = Vector(math.max(max.x,max2.x), math.max(max.y,max2.y), math.max(max.z,max2.z))
				else
					self.AdvBone_BoneHitBoxes[id] = {min = min, max = max}
				end
			end
		end
		self.SavedLocalHitBoxes = {}

		self.LastBuildBonePositionsTime = 0
		self.SavedBoneMatrices = {}
		self.SavedLocalBonePositions = {}
		self.LastBoneChangeTime = CurTime()

		self:AddCallback("BuildBonePositions", self.BuildBonePositions)

	end

	function ENT:BuildBonePositions(bonecount)
		if !IsValid(self) then return end
		//self.BuildBonePositions_HasRun = true //Newly connected players will add this callback, but then wipe it; this tells the think func that it actually went through
		local curtime = CurTime()

		//Handle in-code tf2 minigun animation, even if we don't want to do all the expensive advbonemerge stuff
		if self.MinigunAnimBone then
			local matr = self:GetBoneMatrix(self.MinigunAnimBone)
			if matr then
				matr:Rotate( Angle(0, self.MinigunAnimAngle, 0) )
				self:SetBoneMatrix(self.MinigunAnimBone, matr)
			end
		end

		//Remapping: We need a table of default bone offsets for both the parent and the puppeteer, using this code mostly copy-pasted from advbonemerge
		//Ragdollize uses this info too, so do this even if we're not remapping or doing all the expensive advbonemerge stuff
		//if (puppeteer or self.IsPuppeteer) and !self.RemapInfo_DefaultBoneOffsets then
		if !self.RemapInfo_DefaultBoneOffsets then
			//Grab the bone matrices from a clientside model instead - if we use ourselves, any bone manips we already have will be applied to the 
			//matrices, making the altered bones the new default (and then the manips will be applied again on top of them, basically "doubling" the manips)
			//NOTE: The comment below is from advbonemerge which we copied most of this from, but probably doesn't apply here since we could be running this addon without 
			//advbonemerge installed, which means we could be using garrymanips instead of advbonemerge's manip function overrides.
			//(UPDATE: this entity doesn't use garrymanips any more so using a separate ent is no longer necessary. should we change this to just use this entity now?
			//it's pretty inconsequential whether we keep using this method or not, unless some other factor i'm not aware of messes up our bones or model bounds or something)
			if !self.csmodel then
				//NOTE: This used ClientsideModel before, but users reported this causing crashes with very specific models (those with over max flexes?) (lordaardvark dazv5 overwatch pack h ttps://mega.nz/file/1vBjUQ6D#Yj72iK7eKAkIrnbwTVp66CEgu01nQ6wLNMFXoG-fvIw). This is clearly a much deeper issue, since this same function with the same models also crashes in other contexts (like rendering spawnicons, which the model author knew about and included a workaround for), but until it's fixed a workaround like this is necessary.
				self.csmodel = ents.CreateClientProp()
				self.csmodel:SetModel(self:GetModel())
				//self.csmodel = ClientsideModel(self:GetModel(),RENDERGROUP_TRANSLUCENT)
				self.csmodel:SetPos(self:GetPos())
				self.csmodel:SetAngles(self:GetAngles())
				self.csmodel:SetMaterial("null")  //invisible texture, so players don't see the csmodel for a split second while we're generating the table
				self.csmodel:SetLOD(0)

				//Try to make sure models with a non-reference default pose (i.e. HL2 zombies) use a reference pose instead
				local defaultact = self.csmodel:GetSequenceActivity(0)
				if defaultact != ACT_INVALID and defaultact != ACT_DIERAGDOLL then
					local sequence = self.csmodel:SelectWeightedSequence(ACT_DIERAGDOLL)
					if sequence != -1 then
						self.csmodel:SetSequence(sequence)
						self.csmodel:ResetSequence(sequence)
					end
				end
			end
			self.csmodel:DrawModel()
			self.csmodel:SetupBones()
			self.csmodel:InvalidateBoneCache()
			if self.csmodel and self.csmodel:GetBoneMatrix(0) == nil and self.csmodel:GetBoneMatrix(bonecount - 1) == nil then return end //the csmodel might need a frame or so to start returning the matrices; on some models like office workers from Black Mesa Character Expansion (https://steamcommunity.com/sharedfiles/filedetails/?id=2082334251), this always returns nil for the root bone but still works for the others, so make sure we check more than one bone

			local defaultboneoffsets = {}
			for i = 0, bonecount - 1 do
				local newentry = {}
				local ourmatr = self.csmodel:GetBoneMatrix(i)
				local parentboneid = self.csmodel:GetBoneParent(i)
				if parentboneid and parentboneid != -1 then
					//Get the bone's offset from its parent
					local parentmatr = self.csmodel:GetBoneMatrix(parentboneid)
					if ourmatr == nil then return end  //TODO: why does this happen? does the model need to be precached or something?
					newentry["posoffset"], newentry["angoffset"] = WorldToLocal(ourmatr:GetTranslation(), ourmatr:GetAngles(), parentmatr:GetTranslation(), parentmatr:GetAngles())
					newentry["pos"], newentry["ang"] = WorldToLocal(ourmatr:GetTranslation(), ourmatr:GetAngles(), self:GetPos(), self:GetAngles())
				else
					//If a bone doesn't have a parent, then get its offset from the model origin
					ourmatr = self.csmodel:GetBoneMatrix(i)
					if ourmatr != nil then
						newentry["posoffset"], newentry["angoffset"] = WorldToLocal(ourmatr:GetTranslation(), ourmatr:GetAngles(), self.csmodel:GetPos(), self.csmodel:GetAngles())
						newentry["pos"], newentry["ang"] = WorldToLocal(ourmatr:GetTranslation(), ourmatr:GetAngles(), self:GetPos(), self:GetAngles())
					end
				end
				if !newentry["posoffset"] then //note: if we end up using this placeholder table for the root bone, then remapping kind of sucks, but it's better than nothing i guess
					newentry["posoffset"] = Vector(0,0,0)
					newentry["angoffset"] = Angle(0,0,0)
					newentry["pos"] = Vector(0,0,0)
					newentry["ang"] = Angle(0,0,0)
				end
				table.insert(defaultboneoffsets, i, newentry)
			end

			self.RemapInfo_DefaultBoneOffsets = defaultboneoffsets

			//We'll remove the clientside model in our Think hook, because doing it here can cause a crash
			self.csmodeltoremove = self.csmodel
			self.csmodel = nil
		end

		if !self.AdvBone_BoneInfo then return end

		local parent = self:GetParent()
		if !IsValid(parent) then
			if table.Count(self.AdvBone_BoneManips) == 0 and !IsValid(self:GetPuppeteer()) then return end
			parent = nil
		else
			if parent.AttachedEntity then parent = parent.AttachedEntity end
			parent:SetLOD(0)
		end

		//This function is expensive, so make sure we aren't running it more often than we need to
		if !self.IsPuppeteer then
			local skip = false
			if self.LastBuildBonePositionsTime >= curtime then
				//If we've already run this function this frame (i.e. entity is getting drawn more than once) then skip
				skip = true
			else
				self.LastBuildBonePositionsTime = curtime

				//If our bones haven't changed position in a while, then fall asleep and skip until one of our parent's bones moves,
				//or until we/our parent get bonemanipped (see ent_advbonemerge function overrides)
				//This check isn't the cheapest, but it's still a whole lot better than updating all our bones.
				//Because prop_animated moves of its own accord unlike ent_advbonemerge, and might even be unparented, it also resets this value upon updating its pos/ang, animation, 
				//scale, or pose parameters, in various places in this file.
				//Also make sure SavedBoneMatrices isn't empty, so we don't start skipping before we've actually built our bone positions
				//(can happen with animprops that spawn offscreen, only seems to happen with unmerged props so no need to add this to ent_advbonemerge)
				if !self:GetControlMovementPoseParams() and !table.IsEmpty(self.SavedBoneMatrices) and self.LastBoneChangeTime + (FrameTime() * 10) < curtime then
					if !parent or (parent.AdvBone_LastParentBoneCheckTime and parent.AdvBone_LastParentBoneCheckTime >= curtime) then
						//This check only needs to be performed once per frame, even if there are multiple models merged to one parent
						skip = true
					else
						//Don't bother doing this if the parent has significantly more bones than we do
						local parbonecount = parent:GetBoneCount()
						if parbonecount / 2 <= bonecount then
							local parentbones = {}
							for i = -1, parbonecount - 1 do
								local matr = parent:GetBoneMatrix(i)
								if ismatrix(matr) then
									//parentbones[i] = matr:ToTable() //this func suuucks for perf when there's a lot at once
									local t = matr:GetTranslation()
									local a = matr:GetAngles()
									parentbones[i] = {
										//These values are sloppy; bones that move procedurally from jigglebones or IK always return a slightly
										//different value each frame, so round to the nearest hammer unit
										[1] = math.Round(t.x),
										[2] = math.Round(t.y),
										[3] = math.Round(t.z),
										[4] = math.Round(a.x),
										[5] = math.Round(a.y),
										[6] = math.Round(a.z),
									}
								end
							end

							if self.SavedParentBoneMatrices then
								local ParentNoChange = true
								for k, v in pairs (self.SavedParentBoneMatrices) do
									if !parentbones[k] then
										ParentNoChange = false
									elseif ParentNoChange then
										for k2, v2 in pairs (v) do
											if ParentNoChange then
												if v2 != parentbones[k][k2] then
													ParentNoChange = false
													break
												end
											else
												break
											end
										end
									end
								end
								//MsgN(self:GetModel(), " ParentNoChange = ", ParentNoChange)
								if !ParentNoChange then
									self.LastBoneChangeTime = curtime
									self.SavedParentBoneMatrices = nil
								else
									//MsgN(self, " ", ParentNoChange)
									skip = true
									parent.AdvBone_LastParentBoneCheckTime = curtime
								end

							else
								self.SavedParentBoneMatrices = parentbones
							end
						end
					end
				else
					self.SavedParentBoneMatrices = nil
				end
			end

			//TEST: Display sleep status
			--[[if skip then
				self:SetColor( Color(255,0,0,255) )
			else
				self:SetColor( Color(0,255,0,255) )
			end]]
			//If we're going to skip, then use cached bone matrices instead of computing new ones, and stop here
			if skip then
				if parent and self.AdvBone_OriginMatrix then
					local matr = self.AdvBone_OriginMatrix
					//Move our actual model origin with the origin control
					self:SetPos(matr:GetTranslation())
					self:SetAngles(self.AdvBone_Angs[-1] or matr:GetAngles())
					//Also move our render origin - setpos alone is unreliable since the position can get reasserted if the parent moves or something like that
					self:SetRenderOrigin(matr:GetTranslation())
					self:SetRenderAngles(self.AdvBone_Angs[-1] or matr:GetAngles())
				end
				for i = 0, bonecount - 1 do
					if self.SavedBoneMatrices and self.SavedBoneMatrices[i] and self:GetBoneName(i) != "__INVALIDBONE__" then
						self:SetBoneMatrix(i, self.SavedBoneMatrices[i])
					end
				end
				return
			end
		end
		//TODO: currently, puppeteers can't fall asleep, because they don't generate bone matrices to check for changes on.
		//figure out a way to let puppeteers fall asleep, by checking if their boneoffsets have changed or something?





		//TODO: Animated props can have a different scale than their parent entity. Are there any situations where we should be using the parent's scale instead of our scale?
		local mdlscl = math.Round(self:GetModelScale(),4) //we need to round these values or else the game won't think they're equal
		local mdlsclvec = Vector(mdlscl,mdlscl,mdlscl)

		local puppeteer = self:GetPuppeteer()
		if !IsValid(puppeteer) or !self.RemapInfo then puppeteer = nil end

		//Note: self.RemapInfo_DefaultBoneOffsets table creation was here until we moved it to the top of the function so ragdollize could use it

		//Remapping: Don't remap until the puppeteer has run its buildbonepositions function
		if puppeteer and (!puppeteer.RemapInfo_DefaultBoneOffsets or !puppeteer.BoneOffsets) then puppeteer = nil end

		//Remapping: Get the offset of each remapped bone from its target bone
		if puppeteer and !self.RemapInfo_RemapAngOffsets then
			//First, get the bone matrices of a reference-posed parent, but with RemapInfo ang applied
			local ref = {}
			for i, entry in pairs (self.RemapInfo_DefaultBoneOffsets) do
				local matr = Matrix()
				//TODO: This won't work properly if this bone's id is lower than its parent's id, is that possible?
				local parentboneid = self:GetBoneParent(i)
				if ref[parentboneid] then
					matr:Set(ref[parentboneid])
				end
				//matr:Translate(self.RemapInfo_DefaultBoneOffsets[i]["posoffset"]) //pos isn't necessary here
				matr:Rotate(self.RemapInfo_DefaultBoneOffsets[i]["angoffset"])
				matr:Rotate(self.RemapInfo[i]["ang"])
				ref[i] = matr
			end

			//Next, get the angle diff between each remapped bone and its target
			local remapangoffsets = {}
			for k, v in pairs (self.RemapInfo) do
				local remapboneid = puppeteer:LookupBone(self.RemapInfo[k].parent)
				if remapboneid then
					local _, ang = WorldToLocal(ref[k]:GetTranslation(), ref[k]:GetAngles(), puppeteer.RemapInfo_DefaultBoneOffsets[remapboneid]["pos"], puppeteer.RemapInfo_DefaultBoneOffsets[remapboneid]["ang"])
					remapangoffsets[k] = ang
				end
			end
			self.RemapInfo_RemapAngOffsets = remapangoffsets
		end

		//Get each bone's offset from its parent bone - we have to handle all this differently than standard advbonemerged ents
		//because the animations are constantly moving the bones around
		local boneoffsets = {}
		local bonemins, bonemaxs = nil, nil
		for i = 0, bonecount - 1 do
			local ourmatr = self:GetBoneMatrix(i)

			//We don't need to get the offset for bones that are attached to something, because those ones won't animate (unless we're remapping it, in which case we need it for later)
			local targetboneid = nil
			if parent then targetboneid = parent:LookupBone(self.AdvBone_BoneInfo[i].parent) end
			if !targetboneid or (puppeteer and puppeteer:LookupBone(self.RemapInfo[i]["parent"])) then  //TODO: from the testing we've done, remapping SEEMS to be okay if we don't have boneoffsets for nonremapped merged bones, but are there any weird edge cases we haven't found?
				local newentry = {}
				local parentboneid = self:GetBoneParent(i)
				if parentboneid and parentboneid != -1 then
					//Get the bone's offset from its parent
					local parentmatr = self:GetBoneMatrix(parentboneid)
					if ourmatr == nil then return end //TODO: why does this happen? does the model need to be precached or something?
					newentry["posoffset"], newentry["angoffset"] = WorldToLocal(ourmatr:GetTranslation(), ourmatr:GetAngles(), parentmatr:GetTranslation(), parentmatr:GetAngles())
				else
					//If a bone doesn't have a parent, then get its offset from the model origin
					if ourmatr != nil then
						newentry["posoffset"], newentry["angoffset"] = WorldToLocal(ourmatr:GetTranslation(), ourmatr:GetAngles(), self:GetPos(), self:GetAngles())
					end
				end

				if !newentry["posoffset"] then
					newentry["posoffset"] = Vector(0,0,0)
					newentry["angoffset"] = Angle(0,0,0)
				else
					newentry["posoffset"]:Div(mdlscl)
				end
				table.insert(boneoffsets, i, newentry)
			end

			if !self.IsPuppeteer and ourmatr then
				//Get the min and max positions of our bones ("bone bounds") for our render bounds calculation to use
				local bonepos = WorldToLocal(ourmatr:GetTranslation(), Angle(), self:GetPos(), self:GetAngles())
				if !bonemins and !bonemaxs then
					bonemins = Vector()
					bonemaxs = Vector()
					bonemins:Set(bonepos)
					bonemaxs:Set(bonepos)
				else
					bonemins.x = math.min(bonepos.x,bonemins.x)
					bonemins.y = math.min(bonepos.y,bonemins.y)
					bonemins.z = math.min(bonepos.z,bonemins.z)
					bonemaxs.x = math.max(bonepos.x,bonemaxs.x)
					bonemaxs.y = math.max(bonepos.y,bonemaxs.y)
					bonemaxs.z = math.max(bonepos.z,bonemaxs.z)
				end
			end
		end

		//Remapping: If we're a puppeteer, then store the table so our parent can access its values
		if self.IsPuppeteer then
			self.BoneOffsets = boneoffsets
		//Remapping: Create new boneoffsets for remapped bones, based off of an imaginary model where all remapped bones are moved/rotated to match their corresponding puppeteer bone.
		//These will be applied to the model in place of the normal boneoffsets.
		elseif puppeteer then
			local ref = {}
			for i, entry in pairs (boneoffsets) do
				local remapbonematr = nil
				local remapboneid = puppeteer:LookupBone(self.RemapInfo[i].parent)
				if remapboneid then
					remapbonematr = puppeteer:GetBoneMatrix(remapboneid)
				end

				local matr = Matrix()
				//TODO: This won't work properly if this bone's id is lower than its parent's id, is that possible?
				local parentboneid = self:GetBoneParent(i)
				if ref[parentboneid] then
					matr:Set(ref[parentboneid])
				else
					matr:SetTranslation(self:GetPos())
					matr:SetAngles(self:GetAngles())
					//matr:SetTranslation(puppeteer:GetPos())
					//matr:SetAngles(puppeteer:GetAngles())
				end

				matr:Translate(boneoffsets[i]["posoffset"])
				if remapbonematr then
					local diff_pos = puppeteer.BoneOffsets[remapboneid]["posoffset"] - puppeteer.RemapInfo_DefaultBoneOffsets[remapboneid]["posoffset"]
					matr:Translate(diff_pos)
					matr:SetAngles(remapbonematr:GetAngles())
					matr:Rotate(self.RemapInfo_RemapAngOffsets[i])
				else
					matr:Rotate(boneoffsets[i]["angoffset"])
				end

				if remapbonematr then
					local newentry = {}
					if ref[parentboneid] then
						//Get the bone's offset from its parent
						newentry["posoffset"], newentry["angoffset"] = WorldToLocal(matr:GetTranslation(), matr:GetAngles(), ref[parentboneid]:GetTranslation(), ref[parentboneid]:GetAngles())
					else
						//If a bone doesn't have a parent, then get its offset from the model origin
						newentry["posoffset"], newentry["angoffset"] = WorldToLocal(matr:GetTranslation(), matr:GetAngles(), self:GetPos(), self:GetAngles())
					end
					boneoffsets[i] = newentry
				end

				ref[i] = matr
			end
		end

		if !self.IsPuppeteer and !self.AdvBone_BoneHitBoxes then //Fallback in  case we don't have any hitboxes to use for render bounds
			//Calculate the amount of extra "bloat" to put around our bones when setting our render bounds
			local modelmins, modelmaxs = self:GetModelRenderBounds()
			//Get the largest amount of space between the bone and model bounds and use that as our bloat value - we have to use the largest size on all axes since players can 
			//rotate the model and bones however they please. If the bone bounds are somehow bigger than the model bounds, then use 0 instead.
			self.AdvBone_RenderBounds_Bloat = math.max(0, -(modelmins.x - bonemins.x), -(modelmins.y - bonemins.y), -(modelmins.z - bonemins.z), (modelmaxs.x - bonemaxs.x), (modelmaxs.y - bonemaxs.y), (modelmaxs.z - bonemaxs.z))
		end





		//these will be used to set our render bounds accordingly in the clientside think function
		local highestbonescale = 0
		local bonemins, bonemaxs = nil, nil

		//scaling a matrix down can distort its angles (or remove them entirely if scaled down to 0), so whenever we scale a matrix, we'll store its non-scaled angles in here first. 
		//whenever another bone wants to follow that matrix but NOT scale with it, it'll use the stored angles from this table instead.
		self.AdvBone_Angs = {}

		//check if the bone matrices have changed at all since the last call
		local BonesHaveChanged = false

		if self.IsPuppeteer then return end //puppeteer is never going to have any manips or any boneinfo telling it to merge, so we can stop here
		for i = -1, bonecount - 1 do

			local matr = nil
			local targetboneid = nil
			if parent then targetboneid = parent:LookupBone(self.AdvBone_BoneInfo[i].parent) end
			if targetboneid then

				//Set our bone to the matrix of its target bone on the other model

				local targetmatr = parent:GetBoneMatrix(targetboneid)
				if targetmatr then

					if parent.AdvBone_StaticPropMatrix and self.AdvBone_BoneInfo[i].parent == "static_prop" then
						//The static_prop workaround uses some nonsense with EnableMatrix/RenderMultiply to work, so the matrix we retrieve here 
						//won't have the right angles or scale. Use a stored matrix with the proper values instead.
						targetmatr:Set(parent.AdvBone_StaticPropMatrix)
					end

					matr = targetmatr

					if (self.AdvBone_BoneInfo[i].scale == false) then
						//Since we don't want to use the target bone's scale, rescale the matrix so it's back to normal
						matr:SetScale(mdlsclvec)  //we still want to inherit the overall model scale for things like npcs and animated props

						if parent.AdvBone_Angs and parent.AdvBone_Angs[targetboneid] then
							//Use our target bone's stored angles if possible
							matr:SetAngles(parent.AdvBone_Angs[targetboneid])
						end

						//If the target bone's scale is under 0.04 on any axis, then we can't scale it back up properly, so let's fix that
						//We can't just create a new matrix instead and copy over the translation and angles, since 0-scale matrices lose their angle info
						local scalevec = parent:GetManipulateBoneScale(targetboneid)
						local scalefix = false
						if scalevec.x < 0.04 then scalevec.x = 0.05 scalefix = true end
						if scalevec.y < 0.04 then scalevec.y = 0.05 scalefix = true end
						if scalevec.z < 0.04 then scalevec.z = 0.05 scalefix = true end
						if scalefix == true then parent:ManipulateBoneScale(targetboneid,scalevec) end
					else
						//Store a non-scaled version of our angles if we're scaling with our target bone
						local matrscl = matr:GetScale()
						if Vector(math.Round(matrscl.x,4), math.Round(matrscl.y,4), math.Round(matrscl.z,4)) != mdlsclvec then
							if parent.AdvBone_Angs and parent.AdvBone_Angs[targetboneid] then
								//Use our target bone's stored angles (plus our ang manip) as our own stored angles if possible
								local angmatr = Matrix()
								angmatr:SetAngles(parent.AdvBone_Angs[targetboneid])
								angmatr:Rotate(self:GetManipulateBoneAngles(i))
								self.AdvBone_Angs[i] = angmatr:GetAngles()
								angmatr = nil
							else
								//Otherwise, rescale the matrix so it's back to normal and store those angles (plus our ang manip)
								local angmatr = Matrix()
								angmatr:Set(matr)
								angmatr:SetScale(mdlsclvec)  //we still want to inherit the overall model scale for things like npcs and animated props
								angmatr:Rotate(self:GetManipulateBoneAngles(i))
								self.AdvBone_Angs[i] = angmatr:GetAngles()
								angmatr = nil
							end
						end
					end

					matr:Translate(self:GetManipulateBonePosition(i))
					matr:Rotate(self:GetManipulateBoneAngles(i))
				end

			else

				//Set our bone to its "default" position, relative to its parent bone on our model

				if i == -1 then
					//Create a matrix for the model origin
					matr = Matrix()
					//If our origin isn't following a bone, then that means it's actually following the parent's origin, so inherit origin manip stuff from it
					if parent and parent.AdvBone_OriginMatrix and self.AdvBone_BoneInfo[i].scale != false then
						matr:Set(parent.AdvBone_OriginMatrix)
				
						matr:Translate(self:GetManipulateBonePosition(-1))
						matr:Rotate(self:GetManipulateBoneAngles(-1))

						//Store a non-scaled version of our angles if we're scaling with the parent origin
						local matrscl = matr:GetScale()
						if Vector(math.Round(matrscl.x,4), math.Round(matrscl.y,4), math.Round(matrscl.z,4)) != mdlsclvec then
							//Use the parent origin's stored angles (plus our ang manip) as our own stored angles if possible
							if parent.AdvBone_Angs and parent.AdvBone_Angs[-1] then
								local angmatr = Matrix()
								angmatr:SetAngles(parent.AdvBone_Angs[-1])
								angmatr:Rotate(self:GetManipulateBoneAngles(-1))
								self.AdvBone_Angs[i] = angmatr:GetAngles()
								angmatr = nil
							end
						end
					else
						if parent then
							matr:SetTranslation(parent:GetPos())
							if parent:IsPlayer() and !parent:InVehicle() then
								//NOTE: Unlike everything else, ent:GetAngles() on players not in vehicles returns 
								//the angle they're facing, not the angle of their model origin, so correct this
								local ang = parent:GetAngles()
								ang.p = 0
								matr:SetAngles(ang)
							else
								matr:SetAngles(parent:GetAngles())
							end
						else
							matr:SetTranslation(self:GetPos())
							matr:SetAngles(self:GetAngles())
						end

						matr:Scale(mdlsclvec)

						//NOTE: Unmerged animprops won't actually move the entity itself with the origin manips,
						//but all of the other bones will still move with the origin matrix.
						matr:Translate(self:GetManipulateBonePosition(-1))
						matr:Rotate(self:GetManipulateBoneAngles(-1))
					end
				else
					local parentmatr = nil

					local parentboneid = self:GetBoneParent(i)
					if !parentboneid then parentboneid = -1 end
					if parentboneid != -1 then
						//Start with the matrix of our parent bone
						parentmatr = self:GetBoneMatrix(parentboneid)
					else
						//Start with the matrix of the model origin
						parentmatr = Matrix()
						parentmatr:Set(self.AdvBone_OriginMatrix)
					end
			
					if parentmatr then
						if (self.AdvBone_BoneInfo[i].scale != false) then
							//Start off with the parent bone matrix
							matr = parentmatr

							//Store a non-scaled version of our angles if we're scaling with our parent bone
							local matrscl = matr:GetScale()
							if Vector(math.Round(matrscl.x,4), math.Round(matrscl.y,4), math.Round(matrscl.z,4)) != mdlsclvec then
								local angmatr = Matrix()
								angmatr:SetAngles(self.AdvBone_Angs[parentboneid] or matr:GetAngles())
								angmatr:Rotate(boneoffsets[i]["angoffset"])
								angmatr:Rotate(self:GetManipulateBoneAngles(i))
								self.AdvBone_Angs[i] = angmatr:GetAngles()
								angmatr = nil
							end

							//Apply pos offset
							matr:Translate(boneoffsets[i]["posoffset"])
						else
							//Create a new matrix and just copy over the translation and angle
							matr = Matrix()

							matr:SetTranslation(parentmatr:GetTranslation())
							matr:SetAngles(self.AdvBone_Angs[parentboneid] or parentmatr:GetAngles()) //Use our parent bone's stored angles if possible

							matr:SetScale(mdlsclvec)

							if !self.AdvBone_Uninstalled then
								//Apply pos offset - we still want the offset to be multiplied by the parent bone's scale, even if we're not scaling this bone with it
								//(our distance from the parent bone should be the same regardless of whether we're scaling with it or not - otherwise we'd
								//end up embedded inside the parent bone if it was scaled up, or end up far away from it if it was scaled down)
								local tr1 = parentmatr:GetTranslation()
								parentmatr:Translate(boneoffsets[i]["posoffset"])
								local tr2 = parentmatr:GetTranslation()
								local posoffsetscaled = WorldToLocal(tr2, Angle(), tr1, matr:GetAngles())
								matr:Translate(posoffsetscaled / mdlscl)
							else
								//If the advbonemerge addon is uninstalled, then emulate the default garrymanip behavior, where parent's scale doesn't affect offset
								//(this code should only be running if we're remapping)
								matr:Translate(boneoffsets[i]["posoffset"])
							end
						end

						//Apply pos manip and ang offset/manip
						matr:Translate(self:GetManipulateBonePosition(i))
						matr:Rotate(boneoffsets[i]["angoffset"])
						matr:Rotate(self:GetManipulateBoneAngles(i))
					end
				end

			end


			if matr then  //matr can be nil if we're visible but our parent isn't

				//Store a non-scaled version of our angles if we're scaling
				local scale = self:GetManipulateBoneScale(i)
				if !self.AdvBone_Angs[i] and scale != Vector(1,1,1) then
					self.AdvBone_Angs[i] = matr:GetAngles()
				end
				//Apply scale manip (if advbonemerge is uninstalled, then garrymanips already handle this, so skip it)
				if !self.AdvBone_Uninstalled then
					matr:Scale(scale)
				end

				if !self.AdvBone_BoneHitBoxes then //used by bloat
					local ourscale = matr:GetScale()
					highestbonescale = math.max(ourscale.x,ourscale.y,ourscale.z,highestbonescale)
				end

				if i == -1 then
					self.AdvBone_OriginMatrix = matr

					if parent then
						//Move our actual model origin with the origin control
						self:SetPos(matr:GetTranslation())
						self:SetAngles(self.AdvBone_Angs[-1] or matr:GetAngles())
						//Also move our render origin - setpos alone is unreliable since the position can get reasserted if the parent moves or something like that
						self:SetRenderOrigin(matr:GetTranslation())
						self:SetRenderAngles(self.AdvBone_Angs[-1] or matr:GetAngles())
					end

					//If we're an effect, then keep our origin in the render bounds so that the effect ring doesn't disappear on models 
					//where the origin is really far away from the bones
					if self:GetPhysicsMode() == 2 then
						local localoriginpos = self.AdvBone_OriginMatrix:GetTranslation() - self:GetPos()
						bonemins = Vector()
						bonemaxs = Vector()
						bonemins:Set(localoriginpos)
						bonemaxs:Set(localoriginpos)
					end
				else
					//Get the min and max positions of our bones ("bone bounds") for our render bounds calculation to use
					local bonepos = nil
					local hitboxmin, hitboxmax = nil, nil
					if !self.SavedLocalBonePositions[i] or !self.SavedBoneMatrices[i] or matr:GetTranslation() != self.SavedBoneMatrices[i]:GetTranslation() or matr:GetAngles() != self.SavedBoneMatrices[i]:GetAngles() then
						if parent then
							bonepos = WorldToLocal(matr:GetTranslation(), Angle(), parent:GetPos(), parent:GetAngles())
						else
							bonepos = WorldToLocal(matr:GetTranslation(), Angle(), self:GetPos(), self:GetAngles())
						end
						if self.AdvBone_BoneHitBoxes[i] then
							//local pos = matr:GetTranslation()
							local scl = matr:GetScale()
							local pmins = self.AdvBone_BoneHitBoxes[i].min * scl
							local pmaxs = self.AdvBone_BoneHitBoxes[i].max * scl
							local vects = {
								pmins, Vector(pmaxs.x, pmins.y, pmins.z),
								Vector(pmins.x, pmaxs.y, pmins.z), Vector(pmaxs.x, pmaxs.y, pmins.z),
								Vector(pmins.x, pmins.y, pmaxs.z), Vector(pmaxs.x, pmins.y, pmaxs.z),
								Vector(pmins.x, pmaxs.y, pmaxs.z), pmaxs,
							}
							for i = 1, #vects do
								local wspos = LocalToWorld(vects[i], Angle(), matr:GetTranslation(), matr:GetAngles())
								if parent then
									wspos = WorldToLocal(wspos, Angle(), parent:GetPos(), parent:GetAngles()) //renderbounds are relative to the parent, because renderorigin/renderangles don't affect them
								else
									wspos = WorldToLocal(wspos, Angle(), self:GetPos(), self:GetAngles())
								end
								vects[i] = wspos
							end
							hitboxmin = Vector( math.min(vects[1].x, vects[2].x, vects[3].x, vects[4].x, 
									vects[5].x, vects[6].x, vects[7].x, vects[8].x),
									math.min(vects[1].y, vects[2].y, vects[3].y, vects[4].y, 
									vects[5].y, vects[6].y, vects[7].y, vects[8].y),
									math.min(vects[1].z, vects[2].z, vects[3].z, vects[4].z, 
									vects[5].z, vects[6].z, vects[7].z, vects[8].z) )
							hitboxmax = Vector( math.max(vects[1].x, vects[2].x, vects[3].x, vects[4].x, 
									vects[5].x, vects[6].x, vects[7].x, vects[8].x),
									math.max(vects[1].y, vects[2].y, vects[3].y, vects[4].y, 
									vects[5].y, vects[6].y, vects[7].y, vects[8].y),
									math.max(vects[1].z, vects[2].z, vects[3].z, vects[4].z, 
									vects[5].z, vects[6].z, vects[7].z, vects[8].z) )
							self.SavedLocalHitBoxes[i] = {min = hitboxmin, max = hitboxmax}
						end
						self.SavedLocalBonePositions[i] = bonepos
					else
						//If the bone hasn't moved at all then just use the old position instead of calling WorldToLocal again
						bonepos = self.SavedLocalBonePositions[i]
						if self.SavedLocalHitBoxes[i] then
							hitboxmin = self.SavedLocalHitBoxes[i].min
							hitboxmax = self.SavedLocalHitBoxes[i].max
						end
					end

					local function SetBoneMinsMaxs(vec)
						if !bonemins and !bonemaxs then
							bonemins = Vector()
							bonemaxs = Vector()
							bonemins:Set(vec)
							bonemaxs:Set(vec)
						else
							bonemins.x = math.min(vec.x,bonemins.x)
							bonemins.y = math.min(vec.y,bonemins.y)
							bonemins.z = math.min(vec.z,bonemins.z)
							bonemaxs.x = math.max(vec.x,bonemaxs.x)
							bonemaxs.y = math.max(vec.y,bonemaxs.y)
							bonemaxs.z = math.max(vec.z,bonemaxs.z)
						end
					end
					if hitboxmin and hitboxmax then
						SetBoneMinsMaxs(hitboxmin)
						SetBoneMinsMaxs(hitboxmax)
						--[[if parent then
							debugoverlay.BoxAngles(parent:GetPos(), hitboxmin, hitboxmax, parent:GetAngles(), 0.1, Color(255,255,0,0))
						else
							debugoverlay.BoxAngles(self:GetPos(), hitboxmin, hitboxmax, self:GetAngles(), 0.1, Color(255,255,0,0))
						end]]
					else
						SetBoneMinsMaxs(bonepos)
					end
					
					//Apply the bone matrix
					if self:GetBoneName(i) != "__INVALIDBONE__" then
						self:SetBoneMatrix(i,matr)

						if !BonesHaveChanged and matr != self.SavedBoneMatrices[i] then
							//Jigglebones always return a slightly different value, but we don't want to freeze them in place or have them hold the whole thing up.
							//Instead, compare rounded values using code recycled from earlier in the function.
							if !targetboneid and self:BoneHasFlag(i,BONE_ALWAYS_PROCEDURAL) then
								//local tab1 = matr:ToTable() //don't use matr:ToTable here either for consistency, though this barely makes a difference since procedural bones aren't that common
								//local tab2 = self.SavedBoneMatrices[i]:ToTable()
								local function FastMatrTab(m)
									local t = m:GetTranslation()
									local a = m:GetAngles()
									local tab = {
										[1] = math.Round(t.x),
										[2] = math.Round(t.y),
										[3] = math.Round(t.z),
										[4] = math.Round(a.x),
										[5] = math.Round(a.y),
										[6] = math.Round(a.z),
									}
									return tab
								end
								local tab1 = FastMatrTab(matr)
								local tab2 = FastMatrTab(self.SavedBoneMatrices[i])
								for k, v in pairs (tab1) do
									if !BonesHaveChanged then
										if v != tab2[k] then
											BonesHaveChanged = true
											break
										end
									else
										break
									end
								end
							else
								//MsgN(matr)
								//MsgN("!=")
								//MsgN(self.SavedBoneMatrices[i])
								//MsgN("")
								BonesHaveChanged = true
							end
						end

						self.SavedBoneMatrices[i] = matr
					end
					
				end

			end

		end

		self.AdvBone_RenderBounds_HighestBoneScale = highestbonescale
		self.AdvBone_RenderBounds_BoneMins = bonemins
		self.AdvBone_RenderBounds_BoneMaxs = bonemaxs
		--[[if parent then
			debugoverlay.BoxAngles(parent:GetPos(), bonemins, bonemaxs, parent:GetAngles(), 0.1, Color(0,255,0,0))
		else
			debugoverlay.BoxAngles(self:GetPos(), bonemins, bonemaxs, self:GetAngles(), 0.1, Color(0,255,0,0))
		end]]

		if BonesHaveChanged then
			self.LastBoneChangeTime = curtime
		end
	end

	function ENT:CalcAbsolutePosition(pos, ang)
		//Wake up the BuildBonePositions function whenever the entity moves
		//Note: This will be running every frame for animprops merged to animating entities because the advbonemerge constraint uses FollowBone for some reason I don't recall (exposes more bones?)
		if self.AdvBone_BoneInfo then
			self.LastPos = self.LastPos or pos
			self.LastAng = self.LastAng or ang
			if pos != self.LastPos or ang != self.LastAng then
				//MsgN(self:GetModel(), " calcabs: pos ", pos, " ang ", ang)
				self.LastBoneChangeTime = CurTime()
				self.LastPos = pos
				self.LastAng = ang
			end
		end
	end
end




if SERVER then

	function ENT:CreateAdvBoneInfoTable(par, keepparentempty, matchnames)

		local hasscalemanip = false
		if !duplicator.FindEntityClass("ent_advbonemerge") then
			hasscalemanip = true
		else
			for i = -1, self:GetBoneCount() - 1 do
				if self:GetManipulateBoneScale(i) != Vector(1,1,1) then
					hasscalemanip = true
					break
				end
			end
		end

		local boneinfo = {}
		for i = -1, self:GetBoneCount() - 1 do
			local newsubtable = {
				parent = "",
				scale = !hasscalemanip,	//If we're a newly converted ent with any scale manips, then turn this off by default so the manips look the same as they did before.
			}				//Also turn it off for animprops created without the advanced bonemerge tool installed.

			if self.AdvBone_BoneInfo and self.AdvBone_BoneInfo[i] then
				newsubtable["scale"] = self.AdvBone_BoneInfo[i]["scale"]
			end

			if !keepparentempty then
				if self.AdvBone_BoneInfo and !self.AdvBone_BoneInfo_IsDefault and self.AdvBone_BoneInfo[i] //NOTE: Unlike regular advbonemerged ents, we check for IsDefault here, because even if we're default we still keep our BoneInfo table on unmerge.
				and ( ( IsValid(par) and par:LookupBone( self.AdvBone_BoneInfo[i]["parent"] ) ) or self.AdvBone_BoneInfo[i]["parent"] == "" ) then
					//If we already have a BoneInfo table to use, then get the value from it, but only if the listed target bone exists/is an empty string
					newsubtable["parent"] = self.AdvBone_BoneInfo[i]["parent"]
				elseif matchnames and i != -1 and IsValid(par) and par:LookupBone( self:GetBoneName(i) ) then
					newsubtable["parent"] = string.lower( self:GetBoneName(i) )
				end

				//If we're not parented and we're making a new table, then replace the target bone entry with something 
				//that'll be overwritten if we get parented later and run this function again.
				//TODO: If the player changes any settings for this bone, this'll become an empty string instead and won't get overwritten. Is this good enough?
				//TODO: is this still necessary now that we've implemented self.AdvBone_BoneInfo_IsDefault?
				//if !IsValid(par) and !self.AdvBone_BoneInfo then
				//	newsubtable["parent"] = "null_overridethis"
				//end
			end

			boneinfo[i] = newsubtable
		end
		self.AdvBone_BoneInfo = boneinfo
		//MsgN("animprop doing CreateAdvBoneInfoTable, IsDefault = ", self.AdvBone_BoneInfo_IsDefault)
		if self.AdvBone_BoneInfo_IsDefault == nil then 
			self.AdvBone_BoneInfo_IsDefault = true
		end

	end




	function ENT:Unmerge(ply)

		if !IsValid(self) then return end
		if !self:GetBoneCount() then return end
		if !self:GetModelScale() then return end
		local parent = self:GetParent()
		if !IsValid(parent) then return end

		//Unlike other advbonemerged entities, we're not a replacement for a different entity, so all we have to do is unparent ourselves and restore the physics object.
		self:SetParent(nil)
		self.IsAdvBonemerged = nil
		self:UpdateAnimpropPhysics()

		local phys = self:GetPhysicsObject()
		if IsValid(phys) then
			phys:Wake()
			phys:EnableMotion(false)
			ply:AddFrozenPhysicsObject(nil, phys)  //the entity argument needs to be nil, or else it'll make unnecessary halo effects and lag up the game
		end

		//Remove the constraint
		self.AdvBone_ConstraintEnt:Remove()

		timer.Simple(0.1, function()
			if !IsValid(self) or !IsValid(parent) then return end

			local _, bboxtop1 = parent:GetRotatedAABB(parent:GetCollisionBounds())
			local bboxtop2, _ = self:GetRotatedAABB(self:GetCollisionBounds())
			local height = bboxtop1.z + -bboxtop2.z + parent:GetPos().z

			self:SetPos(Vector(parent:GetPos().x, parent:GetPos().y, height))
		end)

		//Reset our lighting origin so we aren't still inheriting the lighting of the thing we were merged to
		self:Fire("SetLightingOrigin", nil)
		//If anything is advbonemerged to us, correct their lighting origins as well so they inherit their lighting from us
		local tab = constraint.FindConstraints(self,"AdvBoneMerge")
		if tab then
			for _, subtab in pairs (tab) do
				if subtab.Ent1 and subtab.Ent2 and subtab.Ent1 == self then
					AdvBoneSetLightingOrigin(self,subtab.Ent2)
				end
			end
		end

		return self

	end

end




//note 10/15/14: this is now duplicated code in both advbone and animpropoverhaul, lame
if SERVER then

	util.AddNetworkString("AdvBone_ResetBoneChangeTime_SendToCl")

	AdvBone_ResetBoneChangeTime = function(ent)
		//Limit how often the server sends this to clients; i don't know of any obvious cases where this would happen a lot like AdvBone_ResetBoneChangeTimeOnChildren does from manips
		//or stop motion helper, but let's be safe here
		local time = CurTime()
		ent.AdvBone_ResetBoneChangeTime_LastSent = ent.AdvBone_ResetBoneChangeTime_LastSent or 0
		if time > ent.AdvBone_ResetBoneChangeTime_LastSent then
			ent.AdvBone_ResetBoneChangeTime_LastSent = time
			net.Start("AdvBone_ResetBoneChangeTime_SendToCl", true)
				net.WriteEntity(ent)
			net.Broadcast()
		end
	end

else

	net.Receive("AdvBone_ResetBoneChangeTime_SendToCl", function()
		local ent = net.ReadEntity()
		if IsValid(ent) then
			ent.LastBoneChangeTime = CurTime()
		end
	end)

end






























//////////////////////
//FUNCTION OVERRIDES//
//////////////////////

local meta = FindMetaTable("Entity")


//If a trace hits an animated prop that normally has more physics objects (is usually a ragdoll), it can return a physobj id other than 0 (the one it would've hit if it'd been a ragdoll). 
//This results in tools trying to retrieve a physobj that doesn't exist, so redirect them to physobj 0 instead:
local old_GetPhysicsObjectNum = meta.GetPhysicsObjectNum

if old_GetPhysicsObjectNum then

	function meta.GetPhysicsObjectNum(ent, num, ...)

		if isentity(ent) and IsValid(ent) and ent:GetClass() == "prop_animated" then

			return ent:GetPhysicsObject()

		else

			return old_GetPhysicsObjectNum(ent, num, ...)

		end

	end

end


//Custom eye posing functionality for prop_animated - we want to save the eye target as a vector relative to the entity origin, 
//so it moves with us but doesn't look weird by being anchored to the eye attachment or something
local old_SetEyeTarget = meta.SetEyeTarget
if old_SetEyeTarget then

	function meta:SetEyeTarget(pos, ...)

		if isentity(self) and IsValid(self) and self:GetClass() == "prop_animated" and !self.DontLocalizeEyePose then //draw func sets this to true when applying the localized eye pose, so we don't localize it a second time
			
			local localpos = self:WorldToLocal(pos)
			self.EyeTargetLocal = localpos
			
			if SERVER then
				//Send it to clients
				net.Start("AnimProp_EyeTargetLocal_SendToCl")
					net.WriteEntity(self)
					net.WriteVector(localpos)
				net.Broadcast()
			end

		end

		return old_SetEyeTarget(self, pos, ...)
		
	end

end

if CLIENT then

	net.Receive("AnimProp_EyeTargetLocal_SendToCl", function()
		local ent = net.ReadEntity()
		local vec = net.ReadVector()
		if !IsValid(ent) then return end
		ent.EyeTargetLocal = vec
	end)

else

	util.AddNetworkString("AnimProp_EyeTargetLocal_SendToCl")

end