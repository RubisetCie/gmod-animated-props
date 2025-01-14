//For the most part, the overhauled animated prop addon doesn't need a tool any more because of the new context menu-based controls, but there are still a few cases where it's needed:
//1: A few models like TF2 buildables don't work with properties when they're prop_physics, making it impossible to use the "convert to animated prop" option on them unless you do some
//trickery to spawn them as a prop_effect instead or something (which most players won't know to do)
//2: Effect animprops still use the model's hitboxes for clientside traces instead of the effect box (as far as I can tell, we can't change this), so using properties on them is a pain 
//because you have to find an angle where both the effect box and the hitboxes line up. Using a tool instead bypasses this issue.
//3: After the update, a lot of players won't be used to the new controls and will still want to use a tool instead because it's what they're familiar with (but they can learn)

//Honestly, I'd like to get rid of this stool entirely because of how extraneous it feels (we're clogging up the tool list with an unnecessary tool just to cover 3 edge cases??), and if
//there were better fixes for problems 1 and 2 (get buildable prop_physics to work with properties again for problem #1, and use some imaginary ent:SetHitboxOverride(mins,maxs) function to 
//make clientside traces hit the effect box for problem #2) then it wouldn't even be here.

//Update 12-28-20: while it's here we might as well use it as a model picker for the puppeteer lol

//Update 3-10-24: this one's called "animprops" while the old one is called "animprop" so that they don't conflict when both addons are installed

TOOL.Category = "Construction"
TOOL.Name = "#tool.animprops.name"
TOOL.Command = nil
TOOL.ConfigName = "" 

TOOL.ClientConVar["model"] = "models/gman_high.mdl"
TOOL.ClientConVar["skin"] = "0"
TOOL.ClientConVar["notifications"] = "1"
TOOL.ClientConVar["frozen"] = "1"

TOOL.Information = {
	{name = "left0", stage = 0, icon = "gui/lmb.png"},
	{name = "right0", stage = 0, icon = "gui/rmb.png"},
	{name = "info1", stage = 1, icon = "gui/info.png"},
	{name = "right1", stage = 1, icon = "gui/rmb.png"},
	{name = "reload1", stage = 1, icon = "gui/r.png"},
}

if CLIENT then
	language.Add("tool.animprops.name", "Animated Props")
	language.Add("tool.animprops.desc", "Spawn and edit animated props")
	language.Add("tool.animprops.help", "You can also use the context menu to spawn and edit animated props. Hold C to open the context menu, then right click any entity and select \"Convert to Animated Prop\", or right click an animated prop and select \"Edit Animated Prop\".")

	language.Add("tool.animprops.left0", "Spawn an animated prop")
	language.Add("tool.animprops.right0", "Copy a model, or click an animated prop to open a control window in the context menu")
	language.Add("tool.animprops.info1", "Tool is selecting a puppeteer model, reload or holster to cancel")
	language.Add("tool.animprops.right1", "Copy a model to use for the puppeteer")
	language.Add("tool.animprops.reload1", "Cancel puppeteer selection")
end

function TOOL:LeftClick(trace)

	if self:GetStage() != 0 then return false end

	//Super simple method of creating a new animprop: just spawn a dummy entity and convert it using the global function we already have, 
	//instead of copying over all the stuff from that function like DTvar defaults

	if CLIENT then return true end

	local ply = self:GetOwner()
	//local dummy = DoPlayerEntitySpawn(ply, "prop_dynamic", self:GetClientInfo("model"), self:GetClientNumber("skin"))
	local dummy = ents.Create("prop_dynamic")
	dummy:SetPos(trace.HitPos)
	dummy:SetAngles(Angle(0, ply:EyeAngles().y - 180, 0))
	dummy:SetModel(self:GetClientInfo("model"))
	dummy:SetSkin(self:GetClientNumber("skin"))
	dummy:Spawn()
	dummy:Activate()
	if !IsValid(dummy) then return false end

	local animprop = ConvertEntityToAnimprop(dummy, ply, false, false, self:GetClientNumber("frozen") == 1)
	if IsValid(dummy) then dummy:Remove() end
	if !IsValid(animprop) then return false end

	return true

end

function TOOL:RightClick(trace)

	local ent = trace.Entity
	if !IsValid(ent) then return false end

	if IsValid(ent.AttachedEntity) then ent = ent.AttachedEntity end
	local model = ent:GetModel() or ""
	
	if self:GetStage() == 0 then

		//If no nwentity set, then copy model, and open control window for animprops

		if CLIENT then return true end
		if !util.IsValidModel(model) then model = "models/error.mdl" end

		if ent:GetClass() == "prop_animated" then
			net.Start("AnimProp_OpenEditMenu_SendToCl")
				net.WriteEntity(ent)
			net.Send(self:GetOwner())
			self:Notification("Opened context menu window for animated prop: " .. string.GetFileFromFilename(model))
		else
			self:Notification("Copied model: " .. string.GetFileFromFilename(model))
		end
		self:GetOwner():ConCommand("animprops_model " .. model)
		self:GetOwner():ConCommand("animprops_skin " .. (ent:GetSkin() or 0))

	else

		//If nwentity set, then set the model we clicked on as its puppeteer, and then clear the nwentity

		local nwent = self:GetWeapon():GetNWEntity("Animprops_CurEntity")

		if !util.IsValidModel(model) or model == nwent:GetModel() then return false end
		if CLIENT then return true end

		nwent:SetPuppeteerModel(model)
		self:GetWeapon():SetNWEntity("Animprops_CurEntity", NULL)
		self:Notification("Copied puppeteer model: " .. string.GetFileFromFilename(model))

	end

	return true

end

function TOOL:Reload()

	//Clear the nwentity on reload
	if self:GetStage() == 1 then
		if SERVER then
			self:GetWeapon():SetNWEntity("Animprops_CurEntity", NULL)
		end
		return true
	end

end

function TOOL:GetStage()

	local ent = self:GetWeapon():GetNWEntity("Animprops_CurEntity")

	if IsValid(ent) then
		return 1
	else
		return 0
	end

end

if SERVER then

	function TOOL:Notification(msg)

		if self:GetClientNumber("notifications") != 1 then return end

		self:GetOwner():SendLua("GAMEMODE:AddNotify('" .. msg .. "', NOTIFY_GENERIC, 4)")
		self:GetOwner():SendLua("surface.PlaySound('ambient/water/drip" .. math.random(1, 4) .. ".wav')")

	end

	function TOOL:Holster()

		//Clear the nwentity on holster
		local ent = self:GetWeapon():GetNWEntity("Animprops_CurEntity")
		if IsValid(ent) then
			self:GetWeapon():SetNWEntity("Animprops_CurEntity", NULL)
		end

	end

	function TOOL:Think()

		//Filter out bad nwentities
		local ent = self:GetWeapon():GetNWEntity("Animprops_CurEntity")
		if IsValid(ent) and ent:GetClass() != "prop_animated" then
			self:GetWeapon():SetNWEntity("Animprops_CurEntity", NULL)
		end

	end

end

function TOOL.BuildCPanel(panel)

	panel:Help( "#tool.animprops.help" )

	panel:TextEntry( "Model", "animprops_model" )

	panel:NumSlider( "Skin", "animprops_skin", 0, 10, 0 )

	panel:CheckBox( "Start Frozen", "animprops_frozen" )
	panel:CheckBox( "Show Notifications", "animprops_notifications" )

	panel:CheckBox( "Draw Physics Boxes", "cl_animprop_drawphysboxes" )

end