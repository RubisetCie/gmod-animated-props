AddCSLuaFile()

local PANEL = {}

function PANEL:SetEntity(entity)
	if self.m_Entity == entity then return end

	//This tells the think func to set StoredModel to the new ent's model and run RebuildControls
	self.m_Entity = entity
	self.StoredModel = nil
end

//Function overrides for sliders to unclamp them
local function SliderValueChangedUnclamped(self, val)
	//don't clamp this
	//val = math.Clamp( tonumber( val ) || 0, self:GetMin(), self:GetMax() )

	self.Slider:SetSlideX( self.Scratch:GetFraction( val ) )

	if ( self.TextArea != vgui.GetKeyboardFocus() ) then
		self.TextArea:SetValue( self.Scratch:GetTextValue() )
	end

	self:OnValueChanged( val )
end

local function SliderSetValueUnclamped(self, val)
	//don't clamp this
	//val = math.Clamp( tonumber( val ) || 0, self:GetMin(), self:GetMax() )
	
	if ( self:GetValue() == val ) then return end

	self.Scratch:SetValue( val )

	self:ValueChanged( self:GetValue() )
end

local function SliderValueChangedUnclampedMin(self, val)
	//don't clamp the min value
	val = math.min(tonumber(val) or 0, self:GetMax())

	self.Slider:SetSlideX( self.Scratch:GetFraction( val ) )

	if ( self.TextArea != vgui.GetKeyboardFocus() ) then
		self.TextArea:SetValue( self.Scratch:GetTextValue() )
	end

	self:OnValueChanged( val )
end

local function SliderSetValueUnclampedMin(self, val)
	//don't clamp the min value
	val = math.min(tonumber(val) or 0, self:GetMax())
	
	if ( self:GetValue() == val ) then return end

	self.Scratch:SetValue( val )

	self:ValueChanged( self:GetValue() )
end

local function SliderValueChangedUnclampedMax(self, val)
	//don't clamp the max value
	val = math.max(tonumber(val) or 0, self:GetMin())

	self.Slider:SetSlideX( self.Scratch:GetFraction( val ) )

	if ( self.TextArea != vgui.GetKeyboardFocus() ) then
		self.TextArea:SetValue( self.Scratch:GetTextValue() )
	end

	self:OnValueChanged( val )
end

local function SliderSetValueUnclampedMax(self, val)
	//don't clamp the max value
	val = math.max(tonumber(val) or 0, self:GetMin())
	
	if ( self:GetValue() == val ) then return end

	self.Scratch:SetValue( val )

	self:ValueChanged( self:GetValue() )
end

function PANEL:RebuildControls(tab, d, d2, d3)

	self:Clear()
	local ent = self.m_Entity
	if !IsValid(ent) then self:EntityLost() return end
	self:GetParent():SetTitle("Animated Prop [" .. tostring(ent:EntIndex()) .. "]: " .. tostring(ent:GetModel()))

	local ent2 = ent:GetPuppeteer()
	if !IsValid(ent2) then ent2 = nil end
	local animent = ent2 or ent //animation settings use the puppeteer if one exists, or ent otherwise

	//Make sure mouse input is enabled - this can get set to false if the window is created while the context menu is closed
	self:SetMouseInputEnabled(true)

	local tabs = self:Add("DPropertySheet")
	self.TabPanel = tabs
	tabs:Dock(FILL)

	//Give our help strings a slightly darker color than normal so they're easier to read against the gray background
	local color_helpdark = table.Copy(self:GetSkin().Colours.Tree.Hover)
	color_helpdark.r = math.max(0, color_helpdark.r - 40)
	color_helpdark.g = math.max(0, color_helpdark.g - 40)
	color_helpdark.b = math.max(0, color_helpdark.b - 40)

	//Animations

	local animtabs = vgui.Create("DPropertySheet", tabs)
	animtabs:SetPadding(1)
	self.TabAnimations = animtabs

	self.AnimChannels = {}

	local padding = 14 //space between the edges of lists and their contents
	local betweenitems = 8 //space between items in lists
	local betweencategories = 28 //space between categories in lists

	local padding_help = 22 //bigger padding for help text
	local betweenitems_help = 5 //smaller betweenitems for help text
	local betweenitems_help2 = 3 //even smaller betweenitems for second help text paragraphs

	for i = 1, 4 do

		local name = ""
		local tooltip = ""
		if i == 1 then 
			name = "Base Animation"
			tooltip = "The main animation played by the prop"
		else
			name = "Layer " .. tostring(i - 1)
			tooltip = "An additional animation applied over the base animation"
		end
		//Tab icon shows whether a channel is in use
		local icon = "icon16/lightbulb_off.png"
		if animent["GetChannel" .. i .. "Sequence"](animent) >= 0 then
			icon = "icon16/lightbulb.png"
		end

		local back = vgui.Create("DPanel", animtabs)
		local sheet = animtabs:AddSheet(name, back, icon, false, false, tooltip)
		self.AnimChannels[i] = back

		//For this second set of tabs, we want to use a lighter color scheme that matches DPanel. In the default skin, DButton's scheme works well for this.
		function sheet.Tab:Paint(w, h)
			local skin = self:GetSkin()
			self:SetDisabled(!self:IsActive()) //use grayed-out skin for inactive tabs
			skin:PaintButton(self, w, h) //use the skin's PaintButton method so that we can inherit custom PaintButton methods from derma addons
			self:SetDisabled(false)
		end
		function sheet.Tab:UpdateColours(skin)
			if ( self:IsDown() || self.m_bSelected ) then return self:SetTextStyleColor( skin.Colours.Button.Down ) end
			if ( self.Hovered ) then return self:SetTextStyleColor( skin.Colours.Button.Hover ) end
			if ( !self:IsActive() ) then return self:SetTextStyleColor( skin.Colours.Button.Disabled ) end

			return self:SetTextStyleColor(skin.Colours.Button.Normal)
		end

		local lpnl = vgui.Create("Panel", back)
		lpnl:Dock(LEFT)
		lpnl:DockMargin(4,4,0,4)

		local list = vgui.Create("DListView", lpnl)
		back.AnimationList = list
		list:AddColumn("name")
		list:Dock(FILL)
		list:SetMultiSelect(false)
		list:SetHideHeaders(true)
		//This list will be populated in the Think hook
		self:BuildAnimationList(i)

		local entry = vgui.Create("DTextEntry", lpnl)
		back.AnimationTextEntry = entry
		entry:SetHeight(20)
		entry:Dock(BOTTOM)
		entry:DockMargin(0,-1,0,0)
		local sequencename = string.lower( animent:GetSequenceName( animent["GetChannel" .. i .. "Sequence"](animent) ) or "" )
		if animent["GetChannel" .. i .. "Sequence"](animent) < 0 then sequencename = "" end
		entry:SetText(sequencename)

		entry.OnEnter = function()
			local sequence = animent:LookupSequence(entry:GetText())
			animent:DoInput("channel_sequence", i, sequence)
			//Update tab icon
			if sequence >= 0 then
				sheet.Tab.Image:SetImage("icon16/lightbulb.png")
			else
				sheet.Tab.Image:SetImage("icon16/lightbulb_off.png")
			end
		end
		entry.OnFocusChanged = function(_, b) 
			if !b then entry:OnEnter() end
		end

		local search = vgui.Create("DTextEntry", lpnl)
		back.AnimationSearch = entry
		search:SetHeight(20)
		search:Dock(TOP)
		search:DockMargin(0,0,0,-1)
		search:SetPlaceholderText("#spawnmenu.search")
		search:SetTooltip("#spawnmenu.enter_search")

		search.OnEnter = function()
			list:Clear()
			if list.VBar then
				list.VBar:SetScroll(0)
			end
			self:BuildAnimationList(i, search:GetText())
		end

		local searchbutton = search:Add("DImageButton")
		back.AnimationSearchButton = searchbutton
		searchbutton:SetImage("icon16/magnifier.png")
		searchbutton:Dock(RIGHT)
		searchbutton:DockMargin(4,2,4,2)
		searchbutton:SetSize(16,16)
		searchbutton:SetTooltip("#spawnmenu.press_search")

		searchbutton.DoClick = function()
			search.OnEnter()
		end

		lpnl:InvalidateLayout()
		lpnl:SizeToChildren(true,true)

		local container = vgui.Create("DCategoryList", back)
		container.Paint = function(self, w, h)
			//derma.SkinHook("Paint", "CategoryList", self, w, h)
			//draw.RoundedBox(4, 0, 0, w, h, Color(0,0,0,70))
			return false
		end
		container:Dock(FILL)
		container:DockMargin(2,0,0,0)

		//category for speed slider
		//no collapsible category for this one, it's a basic option that should always be visible
		local rpnl = vgui.Create("DSizeToContents", container)
		rpnl:DockMargin(0,3-1,3-1,3) //1 less upper and right because otherwise it'll be too thick compared to the ones in all the other tabs, 0 left because of divider
		//rpnl:DockMargin(2,4,4,4) //old rpnl margins. experiment with these!
		rpnl:Dock(FILL)
		container:AddItem(rpnl)
		rpnl.Paint = function(self, w, h) draw.RoundedBox(4, 0, 0, w, h, Color(0,0,0,70)) end
		rpnl:DockPadding(0,0,0,padding) //DSizeToContents is finicky and ignores the bottom dock margin of the lowermost item

			local slider = vgui.Create("DNumSlider", rpnl)
			back.PlaybackRateSlider = slider
			slider:SetText("Speed")
			slider:SetMinMax(-2, 2)
			slider:SetDefaultValue(1.00)
			slider:SetDark(true)
			slider:SetHeight(18)
			slider:Dock(TOP)
			slider:DockMargin(padding,padding-5,0,3)  //less up and extra down on sliders because we want to base the "top" off the text, not the knob, but also want 16px between sliders' text

			slider.ValueChanged = SliderValueChangedUnclamped
			slider.SetValue = SliderSetValueUnclamped

			slider:SetValue(animent["GetChannel" .. i .. "Speed"](animent) or 1.00)
			function slider.OnValueChanged(_, val)
				animent:DoInput("channel_speed", i, val)
			end

			local help = vgui.Create("DLabel", rpnl)
			help:SetDark(true)
			help:SetWrap(true)
			help:SetTextInset(0, 0)
			help:SetText("How fast the animation plays. Negative numbers will make it play backwards.")
			help:SetContentAlignment(5)
			help:SetAutoStretchVertical(true)
			help:DockMargin(padding_help,betweenitems_help,padding_help,0)
			help:Dock(TOP)
			help:SetTextColor(color_helpdark)

		//category for key
		local cat = vgui.Create("DCollapsibleCategory", container)
		cat:SetLabel("Key Settings")
		cat:DockMargin(0,1,3-1,3) //1 less right because otherwise it'll be too thick compared to the ones in all the other tabs, 0 left because of divider
		cat:Dock(FILL)
		container:AddItem(cat)

		//expand if any contained options are non-default
		cat:SetExpanded(
			((animent["GetChannel" .. i .. "NumpadMode"](animent) or 0) != 0)
			or ((animent["GetChannel" .. i .. "Numpad"](animent) or 0) != 0)
			or (animent["GetChannel" .. i .. "NumpadToggle"](animent) != true)
			or (animent["GetChannel" .. i .. "NumpadStartOn"](animent) != true)
			//considered also adding a check here to make sure the layer isn't disabled, but i don't think that's possible without a numpad key set
		)

		local rpnl = vgui.Create("DSizeToContents", cat)
		rpnl:Dock(FILL)
		cat:SetContents(rpnl)
		rpnl.Paint = function(self, w, h) draw.RoundedBox(4, 0, -5, w, h+5, Color(0,0,0,70)) end //draw the top of the box higher up (it'll be hidden behind the header) so the upper corners are hidden and it blends smoothly into the header
		rpnl:DockPadding(0,0,0,padding) //DSizeToContents is finicky and ignores the bottom dock margin of the lowermost item
		rpnl:DockMargin(0,-1,0,0) //fix the 1px of blank white space between the header and the contents

			local drop = vgui.Create("Panel", rpnl)

			drop.Label = vgui.Create("DLabel", drop)
			drop.Label:SetDark(true)
			drop.Label:SetText("Key Function")
			drop.Label:Dock(LEFT)

			drop.Combo = vgui.Create("DComboBox", drop)
			drop.Combo:SetHeight(25)
			drop.Combo:Dock(FILL)

			local numpadmode0 = "Disable/enable animation"
			local numpadmode1 = "Pause/unpause animation"
			local numpadmode2 = "Restart animation"
			local val = animent["GetChannel" .. i .. "NumpadMode"](animent) or 0
			if val == 0 then
				drop.Combo:SetValue(numpadmode0)
			elseif val == 1 then
				drop.Combo:SetValue(numpadmode1)
			elseif val == 2 then
				drop.Combo:SetValue(numpadmode2)
			end
			drop.Combo:AddChoice(numpadmode0, 0)
			drop.Combo:AddChoice(numpadmode1, 1)
			drop.Combo:AddChoice(numpadmode2, 2)
			function drop.Combo.OnSelect(_, index, value, data)
				animent:DoInput("channel_numpad_mode", i, data)

				//"toggle" option is grayed out for numpad mode 2 (restart animation); make sure it's always true to prevent unintended behavior 
				//("restart animation" with toggle off makes the anim restart on both key in and key out, instead of just key in)
				if data > 1 then
					back.NumpadToggleCheckbox:SetValue(true)
				end
				//"start on" option is grayed out for numpad mode 1 (pause/unpause) and numpad mode 2 (restart animation); make sure it's true to prevent unintended behavior
				if data > 0 then
					back.NumpadStartOnCheckbox:SetValue(true)
				end
			end

			drop:SetHeight(25)
			drop:Dock(TOP)
			drop:DockMargin(padding,padding-9,padding,0) //-9 to base the "top" off the text, not the box
			function drop.PerformLayout(_, w, h)
				drop.Label:SetWide(w / 2.4)
			end

			local pnl = vgui.Create("Panel", rpnl)

			local numpadpnl = vgui.Create("DPanel", pnl)
			numpadpnl:SetPaintBackground(false)

			numpadpnl.numpad = vgui.Create("DBinder", numpadpnl)
			back.Numpad = numpadpnl.numpad
			numpadpnl.label = vgui.Create("DLabel", numpadpnl)
			numpadpnl.label:SetText("Animation Key")
			numpadpnl.label:SetDark(true)

			function numpadpnl:PerformLayout()
				self:SetWide(100)
				self:SetTall(70)

				self.numpad:InvalidateLayout(true)
				self.numpad:SetSize(100, 50)

				self.label:SizeToContents()

				self.numpad:Center()
				self.numpad:AlignTop(20)

				self.label:CenterHorizontal()
				self.label:AlignTop(0)

				local wide = self.label:GetWide()
				if wide > 100 then self:SetWide(wide) end
			end
			numpadpnl:Dock(LEFT)

			numpadpnl.numpad:SetSelectedNumber(animent["GetChannel" .. i .. "Numpad"](animent) or 0)
			function numpadpnl.numpad.SetValue(_, val)
				numpadpnl.numpad:SetSelectedNumber(val)
				animent:DoInput("channel_numpad_num", i, val)
			end

			pnl:Dock(TOP)
			pnl:DockMargin(padding,betweenitems-3,0,padding) //numpad label is 3px too tall, compensate for it here
			pnl:SetHeight(70)
			//function pnl.Paint(_, w, h) draw.RoundedBox(4, 0, 0, w, h, Color(255,0,0,70)) end //for testing the full size of this panel

			local anotherpnl = vgui.Create("Panel", pnl)
			anotherpnl:Dock(LEFT)
			anotherpnl:SetWidth(90)

			local check = vgui.Create("DCheckBoxLabel", anotherpnl)
			back.NumpadToggleCheckbox = check
			check:SetText("Toggle")
			check:SetDark(true)
			check:SetHeight(15)
			check:Dock(TOP)
			check:DockMargin(8,28,0,0)

			check:SetValue(animent["GetChannel" .. i .. "NumpadToggle"](animent))
			check.OnChange = function(_, val)
				animent:DoInput("channel_numpad_toggle", i, val)
			end
			check.Think = function()
				if !IsValid(animent) then return end

				if animent["GetChannel" .. i .. "NumpadMode"](animent) > 1 then
					check:SetDisabled(true)
					//check:SetTooltip("Option not available for restart mode") //never mind, tooltips don't work on disabled checkboxes
				else
					check:SetDisabled(false)
					//check:SetTooltip("") //TODO: use this if we're creating tooltips for everything
				end
			end

			local check = vgui.Create("DCheckBoxLabel", anotherpnl)
			back.NumpadStartOnCheckbox = check
			check:SetText("Start on")
			check:SetDark(true)
			check:SetHeight(15)
			check:Dock(BOTTOM)
			check:DockMargin(8,0,0,8)

			check:SetValue(animent["GetChannel" .. i .. "NumpadStartOn"](animent))
			check.OnChange = function(_, val)
				animent:DoInput("channel_numpad_starton", i, val)
			end
			check.Think = function()
				if !IsValid(animent) then return end

				if animent["GetChannel" .. i .. "NumpadMode"](animent) > 0 then
					check:SetDisabled(true)
					//check:SetTooltip("Option only available for enable/disable mode - use pause button below") //never mind, tooltips don't work on disabled checkboxes
				else
					check:SetDisabled(false)
					//check:SetTooltip("") //TODO: use this if we're creating tooltips for everything
				end
			end

			local pnldisabled = vgui.Create("Panel", pnl)
			//pnldisabled:Dock(RIGHT)
			//pnldisabled:DockMargin(0,3,padding,0) //+3 to top to align the top of this panel with the top of the numpad label text
			pnldisabled:Dock(FILL)
			pnldisabled:DockMargin(-12,3,padding,0) //+3 to top to align the top of this panel with the top of the numpad label text, -12 to left to get it 8px away from checkbox text
			//pnldisabled:SetWidth(115)

			local text = vgui.Create("DLabel", pnldisabled)
			text:SetFont("DermaDefaultBold")
			text:SetColor(Color(255,0,0,255))
			text:SetText("DISABLED")
			text:SizeToContents()
			text:CenterHorizontal()
			text:AlignTop(9)

			local text2 = vgui.Create("DLabel", pnldisabled)
			text2:SetColor(Color(255,0,0,255))
			text2:SetText("(press animation")
			text2:SizeToContents()
			text2:CenterHorizontal()
			text2:AlignTop(17 + text:GetTall())

			local text3 = vgui.Create("DLabel", pnldisabled)
			text3:SetColor(Color(255,0,0,255))
			text3:SetText("key to enable)")
			text3:SizeToContents()
			text3:CenterHorizontal()
			text3:AlignTop(17 + text:GetTall() + text2:GetTall())

			function pnldisabled.Paint(_, w, h)
				draw.RoundedBox(4, 0, 0, w, h, Color(255,0,0,70))
				//text:SizeToContents()
				text:CenterHorizontal()
				//text2:SizeToContents()
				text2:CenterHorizontal()
				//text3:SizeToContents()
				text3:CenterHorizontal()
			end

			function pnldisabled.Think()
				if !IsValid(animent) then return end

				local numpadisdisabling = animent["GetChannel" .. i .. "NumpadState"](animent)
				local starton = animent["GetChannel" .. i .. "NumpadStartOn"](animent)
				if !starton then
					numpadisdisabling = !numpadisdisabling
				end
				if animent["GetChannel" .. i .. "NumpadMode"](animent) > 0 then numpadisdisabling = false end
				//make this value available to the seek bar so we don't have to do this a second time
				pnldisabled.NumpadIsDisabling = numpadisdisabling

				if numpadisdisabling then
					pnldisabled:SetAlpha(255)

					local newtext = nil
					if animent["GetChannel" .. i .. "NumpadToggle"](animent) then
						newtext = "(press animation"
					else
						if starton then
							newtext = "(release animation"
						else
							newtext = "(hold animation"
						end
					end
					if newtext != text2:GetText() then
						text2:SetText(newtext)
						text2:SizeToContents()
					end
				else
					pnldisabled:SetAlpha(0)
				end
			end

		//category for repeats
		local cat = vgui.Create("DCollapsibleCategory", container)
		cat:SetLabel("Repeat Settings")
		cat:DockMargin(0,1,3-1,3) //1 less right because otherwise it'll be too thick compared to the ones in all the other tabs, 0 left because of divider
		cat:Dock(FILL)
		container:AddItem(cat)

		//expand if any contained options are non-default
		cat:SetExpanded(
			((animent["GetChannel" .. i .. "LoopMode"](animent) or 1) != 1)
			or ((animent["GetChannel" .. i .. "LoopDelay"](animent) or 0) != 0)
		)

		local rpnl = vgui.Create("DSizeToContents", cat)
		rpnl:Dock(FILL)
		cat:SetContents(rpnl)
		rpnl.Paint = function(self, w, h) draw.RoundedBox(4, 0, -5, w, h+5, Color(0,0,0,70)) end //draw the top of the box higher up (it'll be hidden behind the header) so the upper corners are hidden and it blends smoothly into the header
		rpnl:DockPadding(0,0,0,padding) //DSizeToContents is finicky and ignores the bottom dock margin of the lowermost item
		rpnl:DockMargin(0,-1,0,0) //fix the 1px of blank white space between the header and the contents

			local drop = vgui.Create("Panel", rpnl)

			drop.Label = vgui.Create("DLabel", drop)
			drop.Label:SetDark(true)
			drop.Label:SetText("Repeat Type")
			drop.Label:Dock(LEFT)

			drop.Combo = vgui.Create("DComboBox", drop)
			drop.Combo:SetHeight(25)
			drop.Combo:Dock(FILL)

			local loopmode0 = "Don't repeat"
			local loopmode1 = "Repeat X seconds after ending"
			local loopmode2 = "Repeat every X seconds"
			local val = animent["GetChannel" .. i .. "LoopMode"](animent) or 1
			if val == 0 then
				drop.Combo:SetValue(loopmode0)
			elseif val == 1 then
				drop.Combo:SetValue(loopmode1)
			elseif val == 2 then
				drop.Combo:SetValue(loopmode2)
			end
			drop.Combo:AddChoice(loopmode0, 0)
			drop.Combo:AddChoice(loopmode1, 1)
			drop.Combo:AddChoice(loopmode2, 2)
			function drop.Combo.OnSelect(_, index, value, data)
				animent:DoInput("channel_loop_mode", i, data)
			end

			drop:SetHeight(25)
			drop:Dock(TOP)
			drop:DockMargin(padding,padding-9,padding,0) //-9 to base the "top" off the text, not the box
			function drop.PerformLayout(_, w, h)
				drop.Label:SetWide(w / 2.4)
			end

			local slider = vgui.Create("DNumSlider", rpnl)
			back.LoopDelaySlider = slider
			slider:SetText("Seconds between repeats")
			slider:SetMinMax(0, 5)
			slider:SetDefaultValue(0.00)
			slider:SetDark(true)
			slider:SetHeight(18)
			slider:Dock(TOP)
			slider:DockMargin(padding,betweenitems-5,0,3) //less up and extra down on sliders because we want to base the "top" off the text, not the knob, but also want 16px between sliders' text

			function slider:Think()
				if !IsValid(animent) then return end

				//Disable the slider if set to "do not repeat"
				if animent["GetChannel" .. i .. "LoopMode"](animent) == 0 then
					slider:SetMouseInputEnabled(false)
					slider:SetAlpha(75)
				else
					slider:SetMouseInputEnabled(true)
					slider:SetAlpha(255)
				end
			end

			slider.ValueChanged = SliderValueChangedUnclampedMax
			slider.SetValue = SliderSetValueUnclampedMax

			slider:SetValue(animent["GetChannel" .. i .. "LoopDelay"](animent) or 0.00)
			function slider.OnValueChanged(_, val)
				animent:DoInput("channel_loop_delay", i, val)
			end

		//category for start/end points
		local cat = vgui.Create("DCollapsibleCategory", container)
		cat:SetLabel("End Points")
		cat:DockMargin(0,1,3-1,3) //1 less right because otherwise it'll be too thick compared to the ones in all the other tabs, 0 left because of divider
		cat:Dock(FILL)
		container:AddItem(cat)

		//expand if any contained options are non-default
		cat:SetExpanded(
			((animent["GetChannel" .. i .. "StartPoint"](animent) or 0) != 0)
			or ((animent["GetChannel" .. i .. "EndPoint"](animent) or 1) != 1)
		)
		back.EndPointsCategory = cat //make this specific category accessible by seekbar code

		local rpnl = vgui.Create("DSizeToContents", cat)
		rpnl:Dock(FILL)
		cat:SetContents(rpnl)
		rpnl.Paint = function(self, w, h) draw.RoundedBox(4, 0, -5, w, h+5, Color(0,0,0,70)) end //draw the top of the box higher up (it'll be hidden behind the header) so the upper corners are hidden and it blends smoothly into the header
		rpnl:DockPadding(0,0,0,padding) //DSizeToContents is finicky and ignores the bottom dock margin of the lowermost item
		rpnl:DockMargin(0,-1,0,0) //fix the 1px of blank white space between the header and the contents

			local slider = vgui.Create("DNumSlider", rpnl)
			slider:SetText("Start Point")
			slider:SetMinMax(0, 1)
			slider:SetDefaultValue(0.00)
			slider:SetDark(true)
			slider:SetHeight(18)
			slider:Dock(TOP)
			slider:DockMargin(padding,padding-5,0,3) //less up and extra down on sliders because we want to base the "top" off the text, not the knob, but also want 16px between sliders' text

			slider.SetValue = function(self, val)
				//clamp this value at the value of the opposite slider
				local otherval = 1
				if back.EndPointSlider then otherval = back.EndPointSlider:GetValue() end
				val = math.Clamp( tonumber(val) or 0, 0, otherval )

				if ( self:GetValue() == val ) then return end

				self.Scratch:SetValue( val )

				self:ValueChanged( self:GetValue() )
			end
			slider.SliderValueChanged = function(self, val)
				//clamp this value at the value of the opposite slider
				local otherval = 1
				if back.EndPointSlider then otherval = back.EndPointSlider:GetValue() end
				val = math.Clamp( tonumber(val) or 0, 0, otherval )

				self.Slider:SetSlideX( self.Scratch:GetFraction( val ) )

				if ( self.TextArea != vgui.GetKeyboardFocus() ) then
					self.TextArea:SetValue( self.Scratch:GetTextValue() )
				end

				self:OnValueChanged( val )
			end

			slider:SetValue(animent["GetChannel" .. i .. "StartPoint"](animent) or 0.00)
			function slider.OnValueChanged(_, val)
				local track = self.AnimChannels[i].Track
				if track then
					if val <= 0 then
						track.CustomStartPoint = nil
					else
						track.CustomStartPoint = val
					end
				end
				animent:DoInput("channel_startendpoint", i, false, val)
			end
			back.StartPointSlider = slider

			local slider = vgui.Create("DNumSlider", rpnl)
			slider:SetText("End Point")
			slider:SetMinMax(0, 1)
			slider:SetDefaultValue(1.00)
			slider:SetDark(true)
			slider:SetHeight(18)
			slider:Dock(TOP)
			slider:DockMargin(padding,betweenitems-5,0,3) //less up and extra down on sliders because we want to base the "top" off the text, not the knob, but also want 16px between sliders' text

			slider.SetValue = function(self, val)
				//clamp this value at the value of the opposite slider
				local otherval = 0
				if back.StartPointSlider then otherval = back.StartPointSlider:GetValue() end
				val = math.Clamp( tonumber(val) or 0, otherval, 1 )

				if ( self:GetValue() == val ) then return end

				self.Scratch:SetValue( val )

				self:ValueChanged( self:GetValue() )
			end
			slider.SliderValueChanged = function(self, val)
				//clamp this value at the value of the opposite slider
				local otherval = 0
				if back.StartPointSlider then otherval = back.StartPointSlider:GetValue() end
				val = math.Clamp( tonumber(val) or 0, otherval, 1 )

				self.Slider:SetSlideX( self.Scratch:GetFraction( val ) )

				if ( self.TextArea != vgui.GetKeyboardFocus() ) then
					self.TextArea:SetValue( self.Scratch:GetTextValue() )
				end

				self:OnValueChanged( val )
			end

			slider:SetValue(animent["GetChannel" .. i .. "EndPoint"](animent) or 1.00)
			function slider.OnValueChanged(_, val)
				local track = self.AnimChannels[i].Track
				if track then
					if val >= 1 then
						track.CustomEndPoint = nil
					else
						track.CustomEndPoint = val
					end
				end
				animent:DoInput("channel_startendpoint", i, true, val)
			end
			back.EndPointSlider = slider

			local help = vgui.Create("DLabel", rpnl)
			help:SetDark(true)
			help:SetWrap(true)
			help:SetTextInset(0, 0)
			help:SetText("Starts or ends the animation partway through, so that only part of it plays. Can also be set by right-clicking the seek bar.")
			help:SetContentAlignment(5)
			help:SetAutoStretchVertical(true)
			help:DockMargin(padding_help,betweenitems_help,padding_help,0)
			help:Dock(TOP)
			help:SetTextColor(color_helpdark)

		//For layers, add extra controls for layer settings
		if i > 1 then

			//category for layers

			local cat = vgui.Create("DCollapsibleCategory", container)
			cat:SetLabel("Layer Settings")
			cat:DockMargin(0,1,3-1,3-1) //1 less down and right because otherwise it'll be too thick compared to the ones in all the other tabs, 0 left because of divider
			cat:Dock(FILL)
			container:AddItem(cat)

			//expand if any contained options are non-default
			cat:SetExpanded(
				((animent["GetChannel" .. i .. "LayerSettings"](animent) or Vector(0,0,1)) != Vector(0,0,1))
			)
			back.LayerOptionsCategory = cat //make this specific category accessible by seekbar code

			local rpnl = vgui.Create("DSizeToContents", cat)
			rpnl:Dock(FILL)
			cat:SetContents(rpnl)
			rpnl.Paint = function(self, w, h) draw.RoundedBox(4, 0, -5, w, h+5, Color(0,0,0,70)) end //draw the top of the box higher up (it'll be hidden behind the header) so the upper corners are hidden and it blends smoothly into the header
			rpnl:DockPadding(0,0,0,padding) //DSizeToContents is finicky and ignores the bottom dock margin of the lowermost item
			rpnl:DockMargin(0,-1,0,0) //fix the 1px of blank white space between the header and the contents

				//Squish LayerBlendIn, LayerBlendOut, and LayerWeight into a vector together to save on nwvar floats
				local layersettings = animent["GetChannel" .. i .. "LayerSettings"](animent) or Vector(0,0,1)

				local slider = vgui.Create("DNumSlider", rpnl)
				slider:SetText("Layer Weight")
				slider:SetMinMax(0, 1)
				slider:SetDefaultValue(1.00)
				slider:SetDark(true)
				slider:SetHeight(18)
				slider:Dock(TOP)
				slider:DockMargin(padding,padding-5,0,3)  //less up and extra down on sliders because we want to base the "top" off the text, not the knob, but also want 16px between sliders' text
				//slider:DockMargin(padding,padding,0,3)  //works better with full betweencategories, actually

				function slider:Think()
					if !IsValid(animent) then return end

					local layersettings = animent["GetChannel" .. i .. "LayerSettings"](animent)

					//Disable the slider if blend in/out is above 0
					if layersettings.x > 0 or layersettings.y > 0 then
						slider:SetMouseInputEnabled(false)
						slider:SetAlpha(75)
						if slider.help then slider.help:SetAlpha(75) end
					else
						slider:SetMouseInputEnabled(true)
						slider:SetAlpha(255)
						if slider.help then slider.help:SetAlpha(255) end
					end
				end

				//weight values not between 0-1 don't do anything different, so don't unclamp

				slider:SetValue(layersettings.z)
				function slider.OnValueChanged(_, val)
					animent:DoInput("channel_layersetting", i, 2, val)
				end

				local help = vgui.Create("DLabel", rpnl)
				help:SetDark(true)
				help:SetWrap(true)
				help:SetTextInset(0, 0)
				help:SetText("How strongly to apply this layer over the base animation.")
				help:SetContentAlignment(5)
				help:SetAutoStretchVertical(true)
				help:DockMargin(padding_help,betweenitems_help,padding_help,betweenitems)
				help:Dock(TOP)
				help:SetTextColor(color_helpdark)
				slider.help = help //let the think func of the above slider find this

				local slider = vgui.Create("DNumSlider", rpnl)
				slider:SetText("Layer Blend In")
				slider:SetMinMax(0, 1)
				slider:SetDefaultValue(0.00)
				slider:SetDark(true)
				slider:SetHeight(18)
				slider:Dock(TOP)
				slider:DockMargin(padding,betweenitems-5,0,3)  //less up and extra down on sliders because we want to base the "top" off the text, not the knob, but also want 16px between sliders' text

				slider.SetValue = function(self, val)
					//clamp this value at the value of the opposite slider
					local otherval = 1
					if back.BlendOutSlider then otherval = back.BlendOutSlider:GetValue() end
					val = math.Clamp( tonumber(val) or 0, 0, otherval )

					if ( self:GetValue() == val ) then return end

					self.Scratch:SetValue( val )

					self:ValueChanged( self:GetValue() )
				end
				slider.SliderValueChanged = function(self, val)
					//clamp this value at the value of the opposite slider
					local otherval = 1
					if back.BlendOutSlider then otherval = back.BlendOutSlider:GetValue() end
					val = math.Clamp( tonumber(val) or 0, 0, otherval )

					self.Slider:SetSlideX( self.Scratch:GetFraction( val ) )

					if ( self.TextArea != vgui.GetKeyboardFocus() ) then
						self.TextArea:SetValue( self.Scratch:GetTextValue() )
					end

					self:OnValueChanged( val )
				end

				slider:SetValue(layersettings.x)
				function slider.OnValueChanged(_, val)
					local track = self.AnimChannels[i].Track
					if track then
						if val <= 0 then
							track.BlendInPoint = nil
						else
							track.BlendInPoint = val
						end
					end
					animent:DoInput("channel_layersetting", i, 0, val)
				end
				back.BlendInSlider = slider

				//note: for consistency with the end point slider, this slider uses 1 - actual value, so 1 = blending of 0, 0.9 = blending of 0.1, etc.
				local slider = vgui.Create("DNumSlider", rpnl)
				slider:SetText("Layer Blend Out")
				slider:SetMinMax(0, 1)
				slider:SetDefaultValue(1.00)
				slider:SetDark(true)
				slider:SetHeight(18)
				slider:Dock(TOP)
				slider:DockMargin(padding,betweenitems-5,0,3)  //less up and extra down on sliders because we want to base the "top" off the text, not the knob, but also want 16px between sliders' text

				slider.SetValue = function(self, val)
					//clamp this value at the value of the opposite slider
					local otherval = 0
					if back.BlendInSlider then otherval = back.BlendInSlider:GetValue() end
					val = math.Clamp( tonumber(val) or 0, otherval, 1 )

					if ( self:GetValue() == val ) then return end

					self.Scratch:SetValue( val )

					self:ValueChanged( self:GetValue() )
				end
				slider.SliderValueChanged = function(self, val)
					//clamp this value at the value of the opposite slider
					local otherval = 0
					if back.BlendInSlider then otherval = back.BlendInSlider:GetValue() end
					val = math.Clamp( tonumber(val) or 0, otherval, 1 )

					self.Slider:SetSlideX( self.Scratch:GetFraction( val ) )

					if ( self.TextArea != vgui.GetKeyboardFocus() ) then
						self.TextArea:SetValue( self.Scratch:GetTextValue() )
					end

					self:OnValueChanged( val )
				end

				slider:SetValue(1 - layersettings.y)
				function slider.OnValueChanged(_, val)
					local track = self.AnimChannels[i].Track
					if track then
						if val >= 1 then
							track.BlendOutPoint = nil
						else
							track.BlendOutPoint = val
						end
					end
					animent:DoInput("channel_layersetting", i, 1, 1 - val)
				end
				back.BlendOutSlider = slider

				local help = vgui.Create("DLabel", rpnl)
				help:SetDark(true)
				help:SetWrap(true)
				help:SetTextInset(0, 0)
				help:SetText("How much to ease the animation in and out.")
				help:SetContentAlignment(5)
				help:SetAutoStretchVertical(true)
				help:DockMargin(padding_help,betweenitems_help,padding_help,0)
				help:Dock(TOP)
				help:SetTextColor(color_helpdark)

				local help = vgui.Create("DLabel", rpnl)
				help:SetDark(true)
				help:SetWrap(true)
				help:SetTextInset(0, 0)
				help:SetText("NOTE: This overrides layer weight, and won't take custom start/end points into account!")
				help:SetContentAlignment(5)
				help:SetAutoStretchVertical(true)
				help:DockMargin(padding_help,betweenitems_help2,padding_help,0)
				help:Dock(TOP)
				help:SetTextColor(color_helpdark)

		else

			//this is dumb, reduce lower margin of previous category because it's the lowest one now
			cat:DockMargin(0,1,3-1,3-1) //1 less down and right because otherwise it'll be too thick compared to the ones in all the other tabs, 0 left because of divider

		end

		//dummy category to fix bug where lowest category has broken right-side padding
		local rpnl = vgui.Create("DSizeToContents", container)
		//rpnl:DockMargin(3,1,3,3)
		rpnl:Dock(FILL)
		container:AddItem(rpnl)
		//rpnl.Paint = function(self, w, h) draw.RoundedBox(4, 0, 0, w, h, Color(0,0,0,70)) end
		//rpnl:DockPadding(0,0,0,padding) //DSizeToContents is finicky and ignores the bottom dock margin of the lowermost item

		local divider = vgui.Create("DHorizontalDivider", back)
		divider:Dock(FILL)
		divider:SetLeft(lpnl)
		divider:SetRight(container)
		divider:SetDividerWidth(8)
		divider:SetLeftMin(125)
		divider:SetRightMin(250)
		divider:SetLeftWidth(d or GetConVar("cl_animprop_editor_d"):GetInt())
		back.Divider = divider
		local old_OnMouseReleased = divider.OnMouseReleased
		divider.OnMouseReleased = function(self2, mcode)
			old_OnMouseReleased(self2, mcode)

			//Resize all the other tabs' dividers to the same width
			local width = self2:GetLeftWidth()
			for i2 = 1, 4 do
				if i != i2 then
					self.AnimChannels[i2].Divider:SetLeftWidth(width)
				end
			end
		end

		local trackpnl = vgui.Create("Panel", back)
		trackpnl:Dock(BOTTOM)
		trackpnl:DockMargin(4,0,0,4)

		local track = vgui.Create("DSlider", trackpnl)
		back.TrackSlider = track
		track:Dock(FILL)
		track:DockMargin(-4,0,-3,0) //get us some consistent 4px margins around everything, use the track borders from disabling or custom start/end points to make this more obvious (TODO: this makes the knob look sort of bad, though, maybe rethink this?)
		track:SetNotches(50)
		track:SetTrapInside(true)
		track:SetLockY(0.5)
		Derma_Hook(track, "Paint", "Paint", "NumSlider")
		track:SetTooltip("Right click to set a custom start or end point for the animation")	//TODO: if the knob passes over the cursor, it'll remove the tooltip, making it hard
		back.Track = track									//for players to read. can't think of an easy way to fix this.

		local pause = vgui.Create("DImageButton", trackpnl)
		pause:SetImage("icon16/control_pause_blue.png")
		pause:SetStretchToFit(false)
		pause:SetDrawBackground(true)
		pause:SetIsToggle(true)
		pause:SetToggle(false)
		pause:Dock(LEFT)
		pause:SetWide(32)

		function track.Think()
			if !IsValid(animent) then return end

			if track:GetDragging() and !pnldisabled.NumpadIsDisabling then
				track:SetSlideX( math.Clamp(track:GetSlideX(), track.CustomStartPoint or 0, track.CustomEndPoint or 1) ) //don't let the player drag it into grayed-out areas
				animent:DoInput("channel_frame", i, track:GetSlideX() or 0)
				//pause:SetToggle(true)
			else
				local seq = animent["GetChannel" .. i .. "Sequence"](animent)
				if !(seq <= 0)								//not an invalid animation
				and animent:SequenceDuration(seq) > 0					//not a single-frame animation
				and (!pnldisabled or !pnldisabled.NumpadIsDisabling) then		//not disabled by numpad
					local cycle = nil
					if i == 1 then
						cycle = animent:GetCycle()
					else
						local id = animent["GetChannel" .. i .. "LayerID"](animent)
						if id != -1 and animent:IsValidLayer(id) then
							cycle = animent:GetLayerCycle(id)
						else
							cycle = track.CustomStartPoint or 0
						end
					end
					track:SetSlideX(cycle)
				else
					track:SetSlideX(track.CustomStartPoint or 0)
				end
			end
		end

		function pause.Think()
			if !IsValid(animent) then return end
			//NOTE: This can be changed without clicking on the button by using the numpad key to pause/unpause
			pause:SetToggle(animent["GetChannel" .. i .. "Pause"](animent) or false)
		end
		function pause.OnToggled(val)
			animent:DoInput("channel_pause", i, pause:GetToggle() or false)
		end

		//Right clicking on the seek bar opens a dropdown menu that can be used to set a custom start or end point
		local function TrackDropdownMenu()
			//Get the click pos and save it for later
			local x, _ = track:CursorPos()
			//Use some code grabbed from the slider move function to translate it to a value from 0 to 1
			local w, _ = track:GetSize()
			local iw, _ = track.Knob:GetSize()
			if ( track.m_bTrappedInside ) then
				w = w - iw
				x = x - iw * 0.5
			end
			x = math.Clamp( x, 0, w ) / w
			local duration = animent:SequenceDuration(animent["GetChannel" .. i .. "Sequence"](animent))
			local menu = DermaMenu()

			//Add custom start point
			if !(track.CustomEndPoint and track.CustomEndPoint <= x) and x > 0 and x < 1 then
				local option = menu:AddOption("Set start point at " .. tostring(math.Round(x * 100, 2)) .. "% (" .. tostring(math.Round(x * duration, 2)) .. " secs)", function()
					track.CustomStartPoint = x
					animent:DoInput("channel_startendpoint", i, false, x)
					self.AnimChannels[i].StartPointSlider:SetValue(x)
					self.AnimChannels[i].EndPointsCategory:DoExpansion(true)
				end)
				option:SetImage("icon16/control_start_blue.png")
			end

			//Add custom end point
			if !(track.CustomStartPoint and track.CustomStartPoint >= x) and x > 0 and x < 1 then
				local option = menu:AddOption("Set end point at " .. tostring(math.Round(x * 100, 2)) .. "% (" .. tostring(math.Round(x * duration, 2)) .. " secs)", function()
					track.CustomEndPoint = x
					animent:DoInput("channel_startendpoint", i, true, x)
					self.AnimChannels[i].EndPointSlider:SetValue(x)
					self.AnimChannels[i].EndPointsCategory:DoExpansion(true)
				end)
				option:SetImage("icon16/control_end_blue.png")
			end

			if i > 1 then
				//Add blend in point
				if !(track.BlendOutPoint and track.BlendOutPoint <= x) and x > 0 and x < 1 then
					local option = menu:AddOption("Set blend in at " .. tostring(math.Round(x * 100, 2)) .. "% (" .. tostring(math.Round(x * duration, 2)) .. " secs)", function()
						track.BlendInPoint = x
						animent:DoInput("channel_layersetting", i, 0, x)
						self.AnimChannels[i].BlendInSlider:SetValue(x)
						self.AnimChannels[i].LayerOptionsCategory:DoExpansion(true)
					end)
					option:SetImage("icon16/control_fastforward_blue.png")
				end

				//Add blend out point
				if !(track.BlendInPoint and track.BlendInPoint >= x) and x > 0 and x < 1 then
					local option = menu:AddOption("Set blend out at " .. tostring(math.Round(x * 100, 2)) .. "% (" .. tostring(math.Round(x * duration, 2)) .. " secs)", function()
						track.BlendOutPoint = x
						animent:DoInput("channel_layersetting", i, 1, 1 - x)
						self.AnimChannels[i].BlendOutSlider:SetValue(x)
						self.AnimChannels[i].LayerOptionsCategory:DoExpansion(true)
					end)
					option:SetImage("icon16/control_rewind_blue.png")
				end
			end

			if track.CustomStartPoint or track.CustomEndPoint or track.BlendInPoint or track.BlendOutPoint then
				menu:AddSpacer()
			end

			//Remove custom start point
			if track.CustomStartPoint then
				local option = menu:AddOption("Remove start point at " .. tostring(math.Round(track.CustomStartPoint * 100, 2)) .. "% (" .. tostring(math.Round(track.CustomStartPoint * duration,2)) .. " secs)", function()
					track.CustomStartPoint = nil
					animent:DoInput("channel_startendpoint", i, false, 0)
					self.AnimChannels[i].StartPointSlider:SetValue(0)
				end)
				option:SetImage("icon16/control_start.png")
			end

			//Remove custom end point
			if track.CustomEndPoint then
				local option = menu:AddOption("Remove end point at " .. tostring(math.Round(track.CustomEndPoint * 100, 2)) .. "% (" .. tostring(math.Round(track.CustomEndPoint * duration,2)) .. " secs)", function()
					track.CustomEndPoint = nil
					animent:DoInput("channel_startendpoint", i, true, 1)
					self.AnimChannels[i].EndPointSlider:SetValue(1)
				end)
				option:SetImage("icon16/control_end.png")
			end

			//Remove blend in point
			if track.BlendInPoint then
				local option = menu:AddOption("Remove blend in at " .. tostring(math.Round(track.BlendInPoint * 100, 2)) .. "% (" .. tostring(math.Round(track.BlendInPoint * duration,2)) .. " secs)", function()
					track.BlendInPoint = nil
					animent:DoInput("channel_layersetting", i, 0, 0)
					self.AnimChannels[i].BlendInSlider:SetValue(0)
				end)
				option:SetImage("icon16/control_fastforward.png")
			end

			//Remove blend out point
			if track.BlendOutPoint then
				local option = menu:AddOption("Remove blend out at " .. tostring(math.Round(track.BlendOutPoint * 100, 2)) .. "% (" .. tostring(math.Round(track.BlendOutPoint * duration,2)) .. " secs)", function()
					track.BlendOutPoint = nil
					animent:DoInput("channel_layersetting", i, 1, 0)
					self.AnimChannels[i].BlendOutSlider:SetValue(1)
				end)
				option:SetImage("icon16/control_rewind.png")
			end

			menu:Open()
		end
		track.OnMousePressed_Default = track.OnMousePressed or track.OnMousePressed_Default
		function track.OnMousePressed(track, mcode)
			if mcode == MOUSE_RIGHT then
				TrackDropdownMenu()
			else
				track:OnMousePressed_Default(mcode)
			end
		end
		//Make sure it also works if we right click on the knob
		track.Knob.OnMousePressed_Default = track.Knob.OnMousePressed or track.Knob.OnMousePressed_Default
		function track.Knob.OnMousePressed(panel, mcode)
			if mcode == MOUSE_RIGHT then
				TrackDropdownMenu()
			else
				track.Knob.OnMousePressed_Default(panel, mcode)
			end
		end

		//Grab the values from the entity if it already has a custom start and/or end point set
		track.CustomStartPoint = math.Clamp(animent["GetChannel" .. i .. "StartPoint"](animent), 0, 1)
		if track.CustomStartPoint and track.CustomStartPoint <= 0 then track.CustomStartPoint = nil end
		track.CustomEndPoint = math.Clamp(animent["GetChannel" .. i .. "EndPoint"](animent), 0, 1)
		if track.CustomEndPoint and track.CustomEndPoint >= 1 then track.CustomEndPoint = nil end
		if i > 1 then
			local vec = animent["GetChannel" .. i .. "LayerSettings"](animent)
			track.BlendInPoint = math.Clamp(vec.x, 0, vec.x)
			if track.BlendInPoint and track.BlendInPoint <= 0 then track.BlendInPoint = nil end
			track.BlendOutPoint = 1 - math.Clamp(vec.y, 0, vec.y)
			if track.BlendOutPoint and track.BlendOutPoint >= 1 then track.BlendOutPoint = nil end
		end

		local col_solid = table.Copy(color_helpdark)
		col_solid.a = 50
		local col_gradient = table.Copy(color_helpdark)
		col_gradient.a = 140

		track.Paint_Default = track.Paint or track.Paint_Default
		function track.Paint(track, w, h)
			track.Paint_Default(track, w, h)

			local iw, _ = track.Knob:GetSize()
			local sliderstart = 0 + (iw * 0.5)
			local sliderend = w - (iw * 0.5)
			local sliderwidth = sliderend - sliderstart

			//Show the custom start and end point by graying out the parts of the timeline we're skipping over
			if track.CustomStartPoint then
				local startpoint = sliderwidth * track.CustomStartPoint
				draw.RoundedBox(math.Clamp(4,0,math.floor(startpoint/2)), sliderstart, 0, startpoint, h, Color(0,0,0,70))
			end
			if track.CustomEndPoint then
				local endpoint = sliderwidth * track.CustomEndPoint + (iw * 0.5)
				local sliderend = sliderend - endpoint
				draw.RoundedBox(math.Clamp(4,0,math.floor(sliderend/2)), endpoint, 0, sliderend, h, Color(0,0,0,70))
			end

			//Show layer blend in/out with blue gradients to make them distinct from the start/end point
			if track.BlendInPoint then
				local startpoint = sliderwidth * track.BlendInPoint
				draw.RoundedBox(math.Clamp(4,0,math.floor(startpoint/2)), sliderstart, 0, startpoint, h, col_solid)
				draw.TexturedQuad({
				texture = surface.GetTextureID( "vgui/gradient-l" ),
				color = col_gradient,
				x = sliderstart,
				y = 0,
				w = startpoint,
				h = h})
			end
			if track.BlendOutPoint then
				local endpoint = sliderwidth * track.BlendOutPoint + (iw * 0.5)
				local sliderend = sliderend - endpoint
				draw.RoundedBox(math.Clamp(4,0,math.floor(sliderend/2)), endpoint, 0, sliderend, h, col_solid)
				draw.TexturedQuad({
				texture = surface.GetTextureID( "vgui/gradient-r" ),
				color = col_gradient,
				x = endpoint,
				y = 0,
				w = sliderend,
				h = h})
			end

			//Make the timeline red if the animation layer is disabled and players can't use it
			if pnldisabled and pnldisabled.NumpadIsDisabling then
				draw.RoundedBox(4, sliderstart, 0, sliderwidth, h, Color(255,0,0,70))
			end
		end

		pause.Paint_Default = pause.Paint or pause.Paint_Default
		function pause.Paint(paint, w, h)
			pause.Paint_Default(pause, w, h)

			//Make the button red if the animation layer is disabled and players can't use it
			if pnldisabled and pnldisabled.NumpadIsDisabling then
				draw.RoundedBox(4, 0, 0, w, h, Color(255,0,0,70))
			end
		end


		back:InvalidateLayout()
		back:SizeToChildren(false, true)
		back:DockPadding(0,0,0,0)

	end

	tabs:AddSheet("Animations", self.TabAnimations, "icon16/film.png")

	//Pose Parameters

	local container = vgui.Create("DPanel", tabs)
	container.Paint = function(self, w, h)
		derma.SkinHook("Paint", "CategoryList", self, w, h)
		draw.RoundedBox(4, 0, 0, w, h, Color(0,0,0,70))

		return false
	end
	container:DockPadding(1,1,1,1)
	self.PoseParameters = container

	local catlist = vgui.Create("DCategoryList", container)
	catlist:Dock(FILL)
	catlist.Paint = function() end
	catlist:DockMargin(0,0,0,0)

	self.PoseParamSliders = {}
	local movementposeparams = false
	for i = 0, animent:GetNumPoseParameters() - 1 do
		local name = animent:GetPoseParameterName(i)
		local min, max = animent:GetPoseParameterRange(i)

		local slider = vgui.Create("DNumSlider", catlist)
		self.PoseParamSliders[i] = slider
		slider:SetText(name)
		slider:SetMinMax(min, max)
		slider:SetDark(true)
		slider:SetHeight(18)
		local padding = padding - 2 //extra pixels on surrounding box bloat up the padding, decrease it to match the others
		if i == 0 then
			slider:DockMargin(padding,padding-6,-13,3) //less up and extra down on sliders because we want to base the "top" off the text, not the knob, but also want 16px between sliders' text
		else						   //also note the -13 on right to get the same amount of space on both sides of the slider - this doesn't scale with padding, TODO: fix that?
			slider:DockMargin(padding,betweenitems-5,-13,3) //less up and extra down on sliders because we want to base the "top" off the text, not the knob, but also want 16px between sliders' text
		end
		catlist:AddItem(slider)

		if name == "move_x" or name == "move_y" or name == "move_yaw" or name == "move_scale" then
			function slider:Think()
				if !IsValid(animent) then return end

				//Disable the slider for this poseparam if it's currently being controlled by the entity
				if animent:GetControlMovementPoseParams() then
					slider:SetMouseInputEnabled(false)
					slider:SetAlpha(75)
				else
					slider:SetMouseInputEnabled(true)
					slider:SetAlpha(255)
				end
			end
			movementposeparams = true
		end

		slider:SetValue( math.Remap(animent:GetPoseParameter(name), 0, 1, min, max) )
		function slider.OnValueChanged(_, val)
			animent:DoInput("poseparam_set", i, val)
		end

		//if name == "move_x" or name == "move_scale" then
		//	slider:SetDefaultValue(1.00)
		//else
			//TODO: is this wrong? can poseparams default to something other than 0?
			slider:SetDefaultValue(0.00)
		//end

	end
	if table.Count(self.PoseParamSliders) == 0 then
		local text = vgui.Create("DLabel", catlist)
		text:SetDark(true)
		text:SetWrap(true)
		text:SetTextInset(0, 0)
		text:SetText("(No pose parameters for this model)")
		text:SetContentAlignment(5)
		text:SetAutoStretchVertical(true)
		local padding = padding - 2 //extra pixels on surrounding box bloat up the padding, decrease it to match the others
		text:DockMargin(padding,padding-3,padding,0) //-3 height on text because it has a little extra bloat on top
		text:Dock(TOP)
		catlist:AddItem(text)
	end

	local optionspnl = vgui.Create("DScrollPanel", container)
	optionspnl:SetWidth(220)
	optionspnl:Dock(RIGHT)
	optionspnl.Paint = function(self, w, h) draw.RoundedBox(4, 0, 0, w, h, Color(0,0,0,70)) end
	optionspnl:DockMargin(4,4,4,4)

		local text = vgui.Create("DLabel", optionspnl)
		text:SetDark(true)
		text:SetWrap(true)
		text:SetTextInset(0, 0)
		text:SetText("Pose parameters change certain animations' settings, such as the direction a character is looking or moving. Different models have different pose parameters available.")
		text:SetContentAlignment(5)
		text:SetAutoStretchVertical(true)
		//text:DockMargin(32,0,32,8)
		text:DockMargin(padding,padding-3,padding,0) //-3 height on text because it has a little extra bloat on top
		text:Dock(TOP)

		if movementposeparams then

			local check = vgui.Create( "DCheckBoxLabel", optionspnl)
			check:SetText("Drive movement pose parameters")
			check:SetDark(true)
			check:SetHeight(15)
			check:Dock(TOP)
			check:DockMargin(padding,betweenitems,0,0)
			check:SetValue(animent:GetControlMovementPoseParams())
			check.OnChange = function(_, val)
				animent:DoInput("poseparam_drive", val)
			end

			local help = vgui.Create("DLabel", optionspnl)
			help:SetDark(true)
			help:SetWrap(true)
			help:SetTextInset(0, 0)
			help:SetText("If checked, all movement pose parameters are controlled by the motion of the prop.")
			help:SetContentAlignment(5)
			help:SetAutoStretchVertical(true)
			help:DockMargin(padding_help,betweenitems_help,padding_help,0)
			help:Dock(TOP)
			help:SetTextColor(color_helpdark)

			local help = vgui.Create("DLabel", optionspnl)
			help:SetDark(true)
			help:SetWrap(true)
			help:SetTextInset(0, 0)
			help:SetText("Note: For this feature to work, the move animation must be the base animation, not a layer.")
			help:SetContentAlignment(5)
			help:SetAutoStretchVertical(true)
			help:DockMargin(padding_help,betweenitems_help2,padding_help,0)
			help:Dock(TOP)
			help:SetTextColor(color_helpdark)

		end

		//filler to add padding to end of list
		local pnl = vgui.Create("Panel", optionspnl)
		pnl:Dock(TOP)
		pnl:SetHeight(padding)

	local divider = vgui.Create("DHorizontalDivider", container)
	divider:Dock(FILL)
	divider:SetLeft(catlist)
	divider:SetRight(optionspnl)
	divider:SetDividerWidth(8)
	divider:SetLeftMin(187.5) //why does this work
	divider:SetRightMin(187.5)
	divider:SetLeftWidth(d2 or GetConVar("cl_animprop_editor_d2"):GetInt())
	container.Divider = divider

	local sheet = tabs:AddSheet("Pose Parameters", container, "icon16/chart_bar.png")
	//When the tab is clicked, re-retrieve the pose parameter values from the entity. If we created the panel right when the entity was first spawned, 
	//then the pose parameters will not have been set yet, meaning the sliders didn't get the right values from animent:GetPoseParameter() when we first made them.
	sheet.Tab.DoClick = function()
		for i, slider in pairs (self.PoseParamSliders) do
			local name = animent:GetPoseParameterName(i)
			local min, max = animent:GetPoseParameterRange(i)
			slider:SetValue( math.Remap(animent:GetPoseParameter(name), 0, 1, min, max) )
		end
		sheet.Tab:GetPropertySheet():SetActiveTab(sheet.Tab)
	end

	//Remapping

	local back = vgui.Create("DPanel", tabs) 
	back.Paint = function(self, w, h)
		derma.SkinHook("Paint", "CategoryList", self, w, h)
		draw.RoundedBox(4, 0, 0, w, h, Color(0,0,0,70))

		return false
	end
	self.Remapping = back

	local pnl = vgui.Create("DSizeToContents", back)
	//pnl:DockMargin(3,3,3,3)
	pnl:DockMargin(5,5,5,4) //why do all these dock margins in this tab need to be 5s instead of 4s to get margins the same size as all the 4s in the other tabs? i don't understand.
	pnl:Dock(TOP)
	//back:AddItem(pnl)
	pnl.Paint = function(self, w, h) draw.RoundedBox(4, 0, 0, w, h, Color(0,0,0,70)) end

		//filler to ensure pnl is stretched to full width
		local filler = vgui.Create("Panel", pnl)
		filler:Dock(TOP)
		filler:SetHeight(0)

		local text = vgui.Create("DLabel", pnl)
		text:SetDark(true)
		text:SetWrap(true)
		text:SetTextInset(0, 0)
		text:SetText('Remapping lets this prop play another model\'s animations instead of its own. This works by spawning a second "puppeteer" model that animates normally, while the prop copies all of its bone movements.')
		text:SetContentAlignment(5)
		text:SetAutoStretchVertical(true)
		text:DockMargin(padding,padding-3,padding,0) //-3 height on text because it has a little extra bloat on top
		text:Dock(TOP)

		local entrypnl = vgui.Create("Panel", pnl)
		entrypnl:SetHeight(20)
		entrypnl:Dock(TOP)
		entrypnl:DockMargin(padding,betweenitems,padding,0)

		local label = vgui.Create("DLabel", entrypnl)
		label:SetDark(true)
		label:SetText("Puppeteer Model")
		label:Dock(LEFT)

		local entry = vgui.Create("DTextEntry", entrypnl)
		entry:SetHeight(20)
		entry:Dock(FILL)
		//entry:SetPlaceholderText("Enter a model path")
		if IsValid(ent2) then
			entry:SetText(ent2:GetModel())
		end

		entry.OnEnter = function()
			//util.IsValidModel() returns false here for models that aren't precached yet (i.e. copy-pasting a model path from spawnmenu without spawning the model first) 
			//so we can't check validity here. We used to blank out this textentry whenever the player entered an invalid model path, but that's not worth the trouble.
			ent:DoInput("remap_model", entry:GetText())
		end
		entry.OnFocusChanged = function(_, b) 
			if !b then entry:OnEnter() end
		end

		local button = vgui.Create("DButton", entrypnl)
		button:SetText("Copy model with tool")
		button:SizeToContents()
		button:SetWidth(button:GetWide() + 14) //+ 4)
		button:SetHeight(20)
		button:Dock(RIGHT)
		button:DockMargin(padding,0,0,0)

		button.DoClick = function()
			ent:DoInput("remap_getwithtool")
		end

		function entrypnl.PerformLayout(_, w, h)
			local w2, h2 = label:GetTextSize()
			label:SetWide(w2 + padding*2)
		end

	pnl:DockPadding(0,0,0,padding) //DSizeToContents is finicky and ignores the bottom dock margin of the lowermost item

	if IsValid(ent2) then

		local function SendRemapInfoToServer()
			local entbone = back.BoneList.selectedbone

			local newtargetbone = back.TargetBoneList.selectedtargetbone
			local newang = Angle( back.slider_ang_p:GetValue(), back.slider_ang_y:GetValue(), back.slider_ang_r:GetValue() )

			//First, apply the new RemapInfo clientside
			if !back.BoneList.UpdatingRemapOptions then
				if newtargetbone != -1 then
					ent.RemapInfo[entbone]["parent"] = ent2:GetBoneName(newtargetbone)
				else
					ent.RemapInfo[entbone]["parent"] = ""
				end

				ent.RemapInfo[entbone]["ang"] = newang

				//Wake up BuildBonePositions and get it to use the new info
				ent.RemapInfo_RemapAngOffsets = nil
				ent.LastBoneChangeTime = CurTime()

				//Then, send all of the information to the server so the duplicator can pick it up
				net.Start("AnimProp_RemapInfoFromEditor_SendToSv")
					net.WriteEntity(ent)
					net.WriteInt(entbone, 9)

					net.WriteInt(newtargetbone, 9)
					net.WriteAngle(newang)

					net.WriteBool(engine.IsRecordingDemo())
				net.SendToServer()
			end
		end

		local lpnl = vgui.Create("Panel", back)
		lpnl:Dock(LEFT)
		lpnl:DockMargin(5,0,2,5)

		local list = vgui.Create("DListView", lpnl)
		back.BoneList = list
		list:AddColumn("Bone (" .. string.GetFileFromFilename(ent:GetModel()) .. ")")
		list:Dock(FILL)
		list:SetMultiSelect(false)

		ent:SetupBones()
		ent:InvalidateBoneCache()

		list.Bones = {}
		list.selectedbone = 0
		for id = 0, ent:GetBoneCount() do
			if ent:GetBoneName(id) != "__INVALIDBONE__" then
				local line = list:AddLine(ent:GetBoneName(id))
				list.Bones[id] = line

				local selectedtargetbone = -1
				if ent.RemapInfo and ent.RemapInfo[id] then
					local targetbonestr = ent.RemapInfo[id]["parent"]
					if targetbonestr != "" then selectedtargetbone = ent2:LookupBone(targetbonestr) end
				end
				if selectedtargetbone != -1 then line.HasTargetBone = true end

				line.OnSelect = function()
					list.selectedbone = id
					list.UpdateRemapOptions(id)
				end

				//Select bone 0 by default
				if id == 0 then
					line:SetSelected(true) //TODO: what if bone 0 is invalid somehow?
				end

				line.Paint = function(self, w, h)
					derma.SkinHook("Paint", "ListViewLine", self, w, h)
					if line.HasTargetBone then
						if self.Icon then
							self.Icon:SetImage("icon16/tick.png")
						end
						surface.SetDrawColor(0,255,0,35)
					else
						if self.Icon then
							self.Icon:SetImage("icon16/cross.png")
						end
						surface.SetDrawColor(255,0,0,35)
					end
						surface.DrawRect(0, 0, w, h)
				end

				local img = vgui.Create("DImage", line)
				line.Icon = img
				img:SetImage("icon16/cross.png")
				img:SizeToContents()
				img:Dock(RIGHT)
				img:DockMargin(0,0,list.VBar:GetWide(),0) //not worth the trouble making this adjust for whether the vbar is visible or not

				local img = vgui.Create("DImage", line)
				line.Icon2 = img
				img:SetImage("icon16/link.png")
				img:SizeToContents()
				img:Dock(RIGHT)
			end
		end

		list.UpdatingRemapOptions = false
		list.UpdateRemapOptions = function(boneid)
			//Don't let the options accidentally update anything while we're changing their values like this
			list.UpdatingRemapOptions = true

			local ang = ent.RemapInfo[boneid]["ang"]

			//if the keyboard focus is on a slider's text field when we update the slider's value, then the text value won't update correctly,
			//so make sure to take the focus off of the text fields first
			back.slider_ang_p.TextArea:KillFocus()
			back.slider_ang_y.TextArea:KillFocus()
			back.slider_ang_r.TextArea:KillFocus()

			back.slider_ang_p:SetValue(ang.p)
			back.slider_ang_y:SetValue(ang.y)
			back.slider_ang_r:SetValue(ang.r)

			//taking the focus off of the text areas isn't enough, we also need to update their text manually because vgui.GetKeyboardFocus()
			//erroneously tells them that they've still got focus and shouldn't be updating themselves
			back.slider_ang_p.TextArea:SetText( back.slider_ang_p.Scratch:GetTextValue() )
			back.slider_ang_y.TextArea:SetText( back.slider_ang_y.Scratch:GetTextValue() )
			back.slider_ang_r.TextArea:SetText( back.slider_ang_r.Scratch:GetTextValue() )

			local bonename = ent.RemapInfo[boneid]["parent"]
			if ent2:LookupBone(bonename) then
				back.TargetBoneList:SetValue(bonename)
				back.TargetBoneList.selectedtargetbone = ent2:LookupBone(bonename)
			else
				back.TargetBoneList:SetValue("(none)")
				back.TargetBoneList.selectedtargetbone = -1
			end

			list.UpdatingRemapOptions = false
		end

		lpnl:InvalidateLayout()
		lpnl:SizeToChildren(true,true)

		--[[local rpnl = vgui.Create("DScrollPanel", back)
		rpnl:Dock(TOP)
		rpnl:DockMargin(2,0,5,2)
		rpnl.Paint = function(self, w, h) draw.RoundedBox( 4, 0, 0, w, h, Color(0,0,0,70) ) end]]

		local container = vgui.Create("DCategoryList", back)
		container.Paint = function(self, w, h)
			//derma.SkinHook("Paint", "CategoryList", self, w, h)
			//draw.RoundedBox(4, 0, 0, w, h, Color(0,0,0,70))
			return false
		end
		container:Dock(FILL)
		container:DockMargin(0,0,0,0)

		//category for bone options
		local rpnl = vgui.Create("DSizeToContents", container)
		rpnl:DockMargin(0,-2,3,3) //0 left because of divider, -2 upper to fix spacing issue
		rpnl:Dock(FILL)
		container:AddItem(rpnl)
		rpnl.Paint = function(self, w, h) draw.RoundedBox(4, 0, 0, w, h, Color(0,0,0,70)) end
		rpnl:DockPadding(0,0,0,padding) //DSizeToContents is finicky and ignores the bottom dock margin of the lowermost item

			local text = vgui.Create("DLabel", rpnl)
			text:SetDark(true)
			text:SetWrap(true)
			text:SetTextInset(0, 0)
			//text:SetText("To set up remapping, use the angle options above to make the prop's default pose match the puppeteer's default pose as closely as possible, and then make sure the bones you want to animate have target bones set (green checkmarks).")
			text:SetText("To set up remapping, both models' default poses need to match as closely as possible. To adjust the pose, select a bone in the list to the left, and then use the angle options below to rotate it.")
			text:SetContentAlignment(5)
			text:SetAutoStretchVertical(true)
			text:DockMargin(padding,padding-3,padding,0) //-3 height on text because it has a little extra bloat on top
			text:Dock(TOP)

		--[[local rpnl = vgui.Create("DSizeToContents", container)
		rpnl:DockMargin(0,1,3,3) //0 left because of divider
		rpnl:Dock(FILL)
		container:AddItem(rpnl)
		rpnl.Paint = function(self, w, h) draw.RoundedBox(4, 0, 0, w, h, Color(0,0,0,70)) end
		rpnl:DockPadding(0,0,0,padding) //DSizeToContents is finicky and ignores the bottom dock margin of the lowermost item]]

			local drop = vgui.Create("Panel", rpnl)
			drop.Label = vgui.Create("DLabel", drop)
			drop.Label:SetDark(true)
			drop.Label:SetText("Target Bone")
			drop.Label:Dock(LEFT)

			drop.Combo = vgui.Create("DComboBox", drop)
			back.TargetBoneList = drop.Combo
			
			drop.Combo:SetHeight(25)
			drop.Combo:Dock(FILL)

			ent2:SetupBones()
			ent2:InvalidateBoneCache()

			drop.Combo:AddChoice("(none)", -1)
			for id = 0, ent2:GetBoneCount() do
				if ent2:GetBoneName(id) != "__INVALIDBONE__" then
					drop.Combo:AddChoice(ent2:GetBoneName(id), id)
				end
			end

			drop.Combo.OnSelect = function(_,_,value,data)
				drop.Combo.selectedtargetbone = data
				SendRemapInfoToServer()

				//Update visuals of list entry for this bone
				if back.BoneList.Bones[back.BoneList.selectedbone] then
					back.BoneList.Bones[back.BoneList.selectedbone].HasTargetBone = data != -1
				end
			end

			//Modified OpenMenu fuction to display menu items in bone ID (data value) order
			drop.Combo.OpenMenu = function(self, pControlOpener)
				if ( pControlOpener && pControlOpener == self.TextEntry ) then
					return
				end

				-- Don't do anything if there aren't any options..
				if ( #self.Choices == 0 ) then return end

				-- If the menu still exists and hasn't been deleted
				-- then just close it and don't open a new one.
				if ( IsValid( self.Menu ) ) then
					self.Menu:Remove()
					self.Menu = nil
				end

				self.Menu = DermaMenu( false, self )

				for k, v in SortedPairs( self.Choices ) do
					local option = self.Menu:AddOption( v, function() self:ChooseOption( v, k ) end )
					if back.TargetBoneList.selectedtargetbone == (k - 2) then option:SetChecked(true) end  //check the currently selected target bone
				end

				local x, y = self:LocalToScreen( 0, self:GetTall() )

				self.Menu:SetMinimumWidth( self:GetWide() )
				self.Menu:Open( x, y, false, self )
			end

			drop:SetHeight(25)
			drop:Dock(TOP)
			//drop:DockMargin(padding,padding-9,padding,0) //-9 to base the "top" off the text, not the box
			//drop:DockMargin(padding,padding,padding,0) //full upper padding to give some space between this and the text
			drop:DockMargin(padding,betweenitems,padding,0)
			function drop.PerformLayout(_, w, h)
				drop.Label:SetWide(w / 2.4)
			end

			local help = vgui.Create("DLabel", rpnl)
			help:SetDark(true)
			help:SetWrap(true)
			help:SetTextInset(0, 0)
			help:SetText("Bone on the puppeteer for this bone to follow.")
			help:SetContentAlignment(5)
			help:SetAutoStretchVertical(true)
			help:DockMargin(padding_help,betweenitems_help,padding_help,0)
			help:Dock(TOP)
			help:SetTextColor(color_helpdark)

			local slider = vgui.Create("DNumSlider", rpnl)
			slider:SetText("Angle Pitch")
			slider:SetMinMax(-180, 180)
			slider:SetDefaultValue(0.00)
			slider:SetDark(true)
			slider:SetHeight(18)//(9)
			slider:Dock(TOP)
			slider:DockMargin(padding,betweenitems,0,0)
			slider.OnValueChanged = function() SendRemapInfoToServer() end
			back.slider_ang_p = slider

			local slider = vgui.Create("DNumSlider", rpnl)
			slider:SetText("Angle Yaw")
			slider:SetMinMax(-180, 180)
			slider:SetDefaultValue(0.00)
			slider:SetDark(true)
			slider:SetHeight(18)//(9)
			slider:Dock(TOP)
			slider:DockMargin(padding,betweenitems-5,0,0)
			slider.OnValueChanged = function() SendRemapInfoToServer() end
			back.slider_ang_y = slider

			local slider = vgui.Create("DNumSlider", rpnl)
			slider:SetText("Angle Roll")
			slider:SetMinMax(-180, 180)
			slider:SetDefaultValue(0.00)
			slider:SetDark(true)
			slider:SetHeight(18)//(9)
			slider:Dock(TOP)
			slider:DockMargin(padding,betweenitems-5,0,3)
			slider.OnValueChanged = function() SendRemapInfoToServer() end
			back.slider_ang_r = slider

			local help = vgui.Create("DLabel", rpnl)
			help:SetDark(true)
			help:SetWrap(true)
			help:SetTextInset(0, 0)
			help:SetText("Adjusts the angle of this bone before remapping.")
			help:SetContentAlignment(5)
			help:SetAutoStretchVertical(true)
			help:DockMargin(padding_help,betweenitems_help,padding_help,0)
			help:Dock(TOP)
			help:SetTextColor(color_helpdark)

		--[[local rpnl2 = vgui.Create("DScrollPanel", back)
		rpnl2:Dock(TOP)
		rpnl2:DockMargin(2,2,5,5)
		rpnl2.Paint = function(self, w, h) draw.RoundedBox( 4, 0, 0, w, h, Color(0,0,0,70) ) end]]

		//category for puppeteer options
		local rpnl = vgui.Create("DSizeToContents", container)
		rpnl:DockMargin(0,1,3,3) //0 left because of divider
		rpnl:Dock(FILL)
		container:AddItem(rpnl)
		rpnl.Paint = function(self, w, h) draw.RoundedBox(4, 0, 0, w, h, Color(0,0,0,70)) end
		rpnl:DockPadding(0,0,0,padding) //DSizeToContents is finicky and ignores the bottom dock margin of the lowermost item

			local slider = vgui.Create("DNumSlider", rpnl)
			slider:SetText("Puppeteer Move X")
			slider:SetMinMax(-128, 128)
			slider:SetDefaultValue(0.00)
			slider:SetDark(true)
			slider:SetHeight(18)//(9)
			slider:Dock(TOP)
			slider:DockMargin(padding,padding,0,0)

			slider.ValueChanged = SliderValueChangedUnclamped
			slider.SetValue = SliderSetValueUnclamped
			back.slider_pos_x = slider

			local slider = vgui.Create("DNumSlider", rpnl)
			slider:SetText("Puppeteer Move Y")
			slider:SetMinMax(-128, 128)
			slider:SetDefaultValue(0.00)
			slider:SetDark(true)
			slider:SetHeight(18)//(9)
			slider:Dock(TOP)
			slider:DockMargin(padding,betweenitems-5,0,0)

			slider.ValueChanged = SliderValueChangedUnclamped
			slider.SetValue = SliderSetValueUnclamped
			back.slider_pos_y = slider

			local slider = vgui.Create("DNumSlider", rpnl)
			slider:SetText("Puppeteer Move Z")
			slider:SetMinMax(-128, 128)
			slider:SetDefaultValue(0.00)
			slider:SetDark(true)
			slider:SetHeight(18)//(9)
			slider:Dock(TOP)
			slider:DockMargin(padding,betweenitems-5,0,0)

			slider.ValueChanged = SliderValueChangedUnclamped
			slider.SetValue = SliderSetValueUnclamped
			back.slider_pos_z = slider

			local vec = ent2:GetPuppeteerPos()
			back.slider_pos_x:SetValue(vec.x)
			back.slider_pos_y:SetValue(vec.y)
			back.slider_pos_z:SetValue(vec.z)
			local movesliderfunc = function()
				ent2:DoInput("remap_pos", Vector(back.slider_pos_x:GetValue(), back.slider_pos_y:GetValue(), back.slider_pos_z:GetValue()))
			end
			back.slider_pos_x.OnValueChanged = movesliderfunc
			back.slider_pos_y.OnValueChanged = movesliderfunc
			back.slider_pos_z.OnValueChanged = movesliderfunc

			--[[local slider = vgui.Create("DNumSlider", rpnl)
			slider:SetText("Puppeteer Transparency")
			slider:SetMinMax(0, 255)
			slider:SetDefaultValue(255)
			slider:SetDecimals(0)
			slider:SetDark(true)
			slider:SetHeight(18)
			slider:Dock(TOP)
			slider:DockMargin(padding,betweenitems-5,0,3)

			slider:SetValue(ent2:GetPuppeteerAlpha())
			function slider.OnValueChanged(_, val)
				ent2:DoInput("remap_alpha", val)
			end]]

			local check = vgui.Create( "DCheckBoxLabel", rpnl)
			check:SetText("Show puppeteer")
			check:SetDark(true)
			check:SetHeight(15)
			check:Dock(TOP)
			check:DockMargin(padding,betweenitems,0,0)

			check:SetValue(ent2:GetPuppeteerAlpha())
			check.OnChange = function(_, val)
				ent2:DoInput("remap_alpha", val)
			end

			//not necessary? will players understand that these options are all visual and don't actually matter if there's a checkbox that hides the puppeteer entirely?
			local help = vgui.Create("DLabel", rpnl)
			help:SetDark(true)
			help:SetWrap(true)
			help:SetTextInset(0, 0)
			help:SetText("These options are purely visual and won't affect remapping.") //bad wording
			help:SetContentAlignment(5)
			help:SetAutoStretchVertical(true)
			//help:DockMargin(32,0,32,8)
			help:DockMargin(padding_help,betweenitems_help,padding_help,0)
			help:Dock(TOP)
			help:SetTextColor(color_helpdark)

		//dummy category to fix bug where lowest category has broken lower padding
		local rpnl = vgui.Create("DSizeToContents", container)
		//rpnl:DockMargin(3,1,3,3)
		rpnl:Dock(FILL)
		container:AddItem(rpnl)
		//rpnl.Paint = function(self, w, h) draw.RoundedBox(4, 0, 0, w, h, Color(0,0,0,70)) end
		//rpnl:DockPadding(0,0,0,padding) //DSizeToContents is finicky and ignores the bottom dock margin of the lowermost item

		--[[local vdivider = vgui.Create("DVerticalDivider", back)
		vdivider:Dock(FILL)
		vdivider:DockMargin(0,0,0,1)
		vdivider:SetTop(rpnl)
		vdivider:SetBottom(rpnl2)
		vdivider:SetDividerHeight(8)
		vdivider:SetTopMin(50)
		vdivider:SetBottomMin(50)
		vdivider.Think = function()
			if vdivider.DoHeightThink then
				local tab = nil
				if self.TabPanel and self.TabPanel.GetActiveTab then
					tab = self.TabPanel:GetActiveTab():GetText()
				end
				if tab == "Remapping" then
					//If the panel starts with this tab open, vdivider won't resize properly unless we do it on a timer.
					//If it starts with another tab open, vdivider won't resize at all, so we have to wait until the tab is open.
					timer.Simple(0.2, function() //minimum time for this to work
						if !vdivider or !vdivider.SetTopHeight then return end
						if g_ContextMenu:IsVisible() then
							vdivider:SetTopHeight(d4 or GetConVar("cl_animprop_editor_d4"):GetInt())
						else
							//If the menu isn't visible (player changed tab then immediately let go of C) then SetTopHeight will fail, so give up and do the check again once reopened
							vdivider.DoHeightThink = true
						end
					end)
					vdivider.DoHeightThink = nil
				end
			end
		end
		vdivider.DoHeightThink = true
		back.VDivider = vdivider]]

		local divider = vgui.Create("DHorizontalDivider", back)
		divider:Dock(FILL)
		divider:SetLeft(lpnl)
		divider:SetRight(container)//(vdivider)
		divider:SetDividerWidth(8)
		divider:SetLeftMin(125)
		divider:SetRightMin(250)
		divider:SetLeftWidth(d3 or GetConVar("cl_animprop_editor_d3"):GetInt())
		back.Divider = divider

		back:InvalidateLayout()
		back:SizeToChildren(false, true)
		back:DockPadding(0,0,0,0)

		back.BoneList.UpdateRemapOptions(0)

	end

	tabs:AddSheet("Remapping", back, "icon16/group.png")

	//Misc. Settings

	local container = vgui.Create("DCategoryList", tabs)
	container.Paint = function(self, w, h)
		derma.SkinHook("Paint", "CategoryList", self, w, h)
		draw.RoundedBox(4, 0, 0, w, h, Color(0,0,0,70))

		return false
	end

	--[[local pnl = vgui.Create("DSizeToContents", container)
	pnl:DockMargin(3,3,3,3)
	pnl:Dock(FILL)
	container:AddItem(pnl)
	pnl.Paint = function(self, w, h) draw.RoundedBox(4, 0, 0, w, h, Color(0,0,0,70)) end
	pnl:DockPadding(0,0,0,padding) //DSizeToContents is finicky and ignores the bottom dock margin of the lowermost item]]

	//category for scale & collisions
	local cat = vgui.Create("DCollapsibleCategory", container)
	cat:SetLabel("Scale & Collisions")
	//cat:DockMargin(0,1,3-1,3) //1 less right because otherwise it'll be too thick compared to the ones in all the other tabs, 0 left because of divider
	cat:DockMargin(3,3,3,3)
	cat:Dock(FILL)
	container:AddItem(cat)
	cat:SetExpanded(true)

	local pnl = vgui.Create("DSizeToContents", cat)
	pnl:Dock(FILL)
	cat:SetContents(pnl)
	pnl.Paint = function(self, w, h) draw.RoundedBox(4, 0, -5, w, h+5, Color(0,0,0,70)) end //draw the top of the box higher up (it'll be hidden behind the header) so the upper corners are hidden and it blends smoothly into the header
	pnl:DockPadding(0,0,0,padding) //DSizeToContents is finicky and ignores the bottom dock margin of the lowermost item
	pnl:DockMargin(0,-1,0,0) //fix the 1px of blank white space between the header and the contents

		local slider = vgui.Create("DNumSlider", pnl)
		slider:SetText("Model Scale")
		slider:SetMinMax(0.06, 16)
		slider:SetDefaultValue(1.00)
		slider:SetDark(true)
		slider:SetHeight(18)
		slider:Dock(TOP)
		//slider:DockMargin(padding,betweencategories-5,0,3) //less up and extra down on sliders because we want to base the "top" off the text, not the knob, but also want 16px between sliders' text
		//slider:DockMargin(padding,betweencategories,0,3)  //works better with full betweencategories, actually
		slider:DockMargin(padding,betweenitems,0,3)

		slider.ValueChanged = SliderValueChangedUnclamped
		slider.SetValue = SliderSetValueUnclamped

		slider:SetValue(ent:GetModelScale())
		function slider.OnValueChanged(_, val)
			ent:DoInput("phys_scale", val)
		end

		local help = vgui.Create("DLabel", pnl)
		help:SetDark(true)
		help:SetWrap(true)
		help:SetTextInset(0, 0)
		help:SetText("Changes the size of the prop.")
		help:SetContentAlignment(5)
		help:SetAutoStretchVertical(true)
		help:DockMargin(padding_help,betweenitems_help,padding_help,0)
		help:Dock(TOP)
		help:SetTextColor(color_helpdark)

		local drop = vgui.Create("Panel", pnl)

		drop.Label = vgui.Create("DLabel", drop)
		drop.Label:SetDark(true)
		drop.Label:SetText("Collision Type")
		drop.Label:Dock(LEFT)

		drop.Combo = vgui.Create("DComboBox", drop)
		drop.Combo:SetHeight(25)
		drop.Combo:Dock(FILL)

		local physmode0 = "Physics Prop (prop models only)"
		local physmode1 = "Physics Box"
		local physmode2 = "Effect"
		function drop.Combo.Think()
			if !IsValid(ent) then return end

			//Automatically update the dropdown if the entity changes its own physics mode (prop and box physics will swirch to effect physics if they can't make a good physobj)
			local val = ent:GetPhysicsMode() or 1
			if val == 0 then
				drop.Combo:SetValue(physmode0)
			elseif val == 1 then
				drop.Combo:SetValue(physmode1)
			elseif val == 2 then
				drop.Combo:SetValue(physmode2)
			end

			//Don't show the physics box options unless we're set to that mode
			if val == 1 then
				self.PhysboxCheck:SetHeight(15)
				//self.PhysboxCheck:DockMargin(16,14,0,0)
				self.PhysboxCheck:DockMargin(padding,betweenitems,0,0)
				self.PhysboxCheckHelp:SetAutoStretchVertical(true)
				//self.PhysboxCheckHelp:DockMargin(22,4,22,14)
				self.PhysboxCheckHelp:DockMargin(padding_help,betweenitems_help,padding_help,0)
			else
				self.PhysboxCheck:SetHeight(0)
				self.PhysboxCheck:DockMargin(0,0,0,0)
				self.PhysboxCheckHelp:SetAutoStretchVertical(false)
				self.PhysboxCheckHelp:SetHeight(0)
				self.PhysboxCheckHelp:DockMargin(0,0,0,0)
			end
		end
		local mdl = ent:GetModel()
		if util.IsValidProp(mdl) and !util.IsValidRagdoll(mdl) then
			drop.Combo:AddChoice(physmode0, 0)  //only show this option for prop models
		end
		drop.Combo:AddChoice(physmode1, 1)
		drop.Combo:AddChoice(physmode2, 2)
		function drop.Combo.OnSelect(_, index, value, data)
			ent:DoInput("phys_mode", data)
		end

		drop:SetHeight(25)
		drop:Dock(TOP)
		drop:DockMargin(padding,betweenitems,padding,0)
		function drop.PerformLayout(_, w, h)
			drop.Label:SetWide(w / 2.4)
		end

		local check = vgui.Create( "DCheckBoxLabel", pnl)
		self.PhysboxCheck = check
		check:SetText("Physics box doesn't go below model origin")
		check:SetDark(true)
		check:SetHeight(15)
		check:Dock(TOP)
		check:DockMargin(padding,betweenitems,0,0)

		check:SetValue(ent:GetNoPhysicsBelowOrigin())
		check.OnChange = function(_, val)
			ent:DoInput("phys_beloworigin", val)
		end

		local help = vgui.Create("DLabel", pnl)
		self.PhysboxCheckHelp = help
		help:SetDark(true)
		help:SetWrap(true)
		help:SetTextInset(0, 0)
		help:SetText("If checked, the bottom of the physics box is cut off at the origin point of the model. For most characters, this is located right at their feet, letting them sit flat on the ground.")
		//help:SetContentAlignment(5)
		help:SetAutoStretchVertical(true)
		//help:DockMargin(32,0,32,8)
		help:DockMargin(padding_help,betweenitems_help,padding_help,0)
		help:Dock(TOP)
		help:SetTextColor(color_helpdark)

		local text = vgui.Create("DLabel", pnl)
		text:SetDark(true)
		text:SetWrap(true)
		text:SetTextInset(0, 0)
		text:SetText("Warning: Modifying the prop's scale or collisions will break any constraints attached to it!")
		text:SetContentAlignment(5)
		text:SetAutoStretchVertical(true)
		text:DockMargin(padding,betweenitems,padding,0)
		text:Dock(TOP)

	//new category for ragdollize, but only if the option is available
	if util.IsValidRagdoll(ent:GetModel()) then

		--[[local pnl = vgui.Create("DSizeToContents", container)
		pnl:DockMargin(3,1,3,3)
		pnl:Dock(FILL)
		container:AddItem(pnl)
		pnl.Paint = function(self, w, h) draw.RoundedBox(4, 0, 0, w, h, Color(0,0,0,70)) end
		pnl:DockPadding(0,0,0,padding) //DSizeToContents is finicky and ignores the bottom dock margin of the lowermost item]]

		local cat = vgui.Create("DCollapsibleCategory", container)
		cat:SetLabel("Ragdollize")
		//cat:DockMargin(0,1,3-1,3) //1 less right because otherwise it'll be too thick compared to the ones in all the other tabs, 0 left because of divider
		cat:DockMargin(3,1,3,3)
		cat:Dock(FILL)
		container:AddItem(cat)
		cat:SetExpanded(true)

		local pnl = vgui.Create("DSizeToContents", cat)
		pnl:Dock(FILL)
		cat:SetContents(pnl)
		pnl.Paint = function(self, w, h) draw.RoundedBox(4, 0, -5, w, h+5, Color(0,0,0,70)) end //draw the top of the box higher up (it'll be hidden behind the header) so the upper corners are hidden and it blends smoothly into the header
		pnl:DockPadding(0,0,0,padding) //DSizeToContents is finicky and ignores the bottom dock margin of the lowermost item
		pnl:DockMargin(0,-1,0,0) //fix the 1px of blank white space between the header and the contents

			//filler to ensure pnl is stretched to full width
			local filler = vgui.Create("Panel", pnl)
			filler:Dock(TOP)
			filler:SetHeight(0)

			local button = vgui.Create("DButton", pnl)
			button:SetText("Ragdollize!")
			button:SizeToContents()
			//button:SetWidth(button:GetWide() + 14) //+ 4)
			button:SetHeight(30)
			button:Dock(TOP)
			//button:DockMargin(0,0,0,0)
			button:DockMargin(padding,padding,padding,0)

			button.DoClick = function()
				surface.PlaySound("ui/buttonclickrelease.wav") //("common/wpn_select.wav")
				ent:Ragdollize()
			end

			local help = vgui.Create("DLabel", pnl)
			help:SetDark(true)
			help:SetWrap(true)
			help:SetTextInset(0, 0)
			//help:SetText("Spawns a ragdoll in the same pose as the animated prop (and then moves the prop above it).") //awkward wording. do we need to explain this?
			help:SetText("Spawns a ragdoll in the same pose as the animated prop.")
			help:SetContentAlignment(5)
			help:SetAutoStretchVertical(true)
			help:DockMargin(padding_help,betweenitems_help,padding_help,0)
			help:Dock(TOP)
			help:SetTextColor(color_helpdark)

			local help = vgui.Create("DLabel", pnl)
			help:SetDark(true)
			help:SetWrap(true)
			help:SetTextInset(0, 0)
			help:SetText("The ragdoll will try to match the animation as closely as possible, but in some cases, like ragdolls with unposable shoulders, bones are stuck between two physics objects and can't be posed.")
			help:SetContentAlignment(5)
			help:SetAutoStretchVertical(true)
			help:DockMargin(padding_help,betweenitems_help2,padding_help,0)
			help:Dock(TOP)
			help:SetTextColor(color_helpdark)

			local check = vgui.Create( "DCheckBoxLabel", pnl)
			check:SetText("Pose ragdoll's non-physics bones (fingers, etc.)")
			check:SetDark(true)
			check:SetHeight(15)
			check:Dock(TOP)
			check:DockMargin(padding,betweenitems,0,0)

			check:SetValue(ent.RagdollizeDoManips)
			check.OnChange = function(_, val)
				ent.RagdollizeDoManips = val
			end

			local check = vgui.Create( "DCheckBoxLabel", pnl)
			check:SetText("Resize ragdoll's physics bones with Ragdoll Resizer (if applicable)")
			check:SetDark(true)
			check:SetHeight(15)
			check:Dock(TOP)
			check:DockMargin(padding,betweenitems,0,0)

			check:SetValue(ent.RagdollizeUseRagdollResizer)
			check.OnChange = function(_, val)
				ent.RagdollizeUseRagdollResizer = val
			end
			check:SetDisabled(!tobool(duplicator.FindEntityClass("prop_resizedragdoll_physparent")))

			local check = vgui.Create( "DCheckBoxLabel", pnl)
			check:SetText("Ragdollize on damage")
			check:SetDark(true)
			check:SetHeight(15)
			check:Dock(TOP)
			check:DockMargin(padding,betweenitems*2,0,0) //double top margin to separate it from the more general ragdollize options

			check:SetValue(ent:GetRagdollizeOnDamage())
			check.OnChange = function(_, val)
				ent:DoInput("misc_ragdollizeondmg", val)
			end

			local help = vgui.Create("DLabel", pnl)
			help:SetDark(true)
			help:SetWrap(true)
			help:SetTextInset(0, 0)
			help:SetText("If checked, taking damage will kill the prop and turn it into a ragdoll. Unfreeze the prop for best results!")
			help:SetContentAlignment(5)
			help:SetAutoStretchVertical(true)
			help:DockMargin(padding_help,betweenitems_help2,padding_help,0)
			help:Dock(TOP)
			help:SetTextColor(color_helpdark)

	end

	//new category for animevent checkbox, which isn't related to scale & collisions or ragdollize
	--[[local pnl = vgui.Create("DSizeToContents", container)
	pnl:DockMargin(3,1,3,3)
	pnl:Dock(FILL)
	container:AddItem(pnl)
	pnl.Paint = function(self, w, h) draw.RoundedBox(4, 0, 0, w, h, Color(0,0,0,70)) end
	pnl:DockPadding(0,0,0,padding) //DSizeToContents is finicky and ignores the bottom dock margin of the lowermost item]]

	local cat = vgui.Create("DCollapsibleCategory", container)
	cat:SetLabel("Other")
	//cat:DockMargin(0,1,3-1,3) //1 less right because otherwise it'll be too thick compared to the ones in all the other tabs, 0 left because of divider
	cat:DockMargin(3,1,3,3)
	cat:Dock(FILL)
	container:AddItem(cat)
	cat:SetExpanded(true)

	local pnl = vgui.Create("DSizeToContents", cat)
	pnl:Dock(FILL)
	cat:SetContents(pnl)
	pnl.Paint = function(self, w, h) draw.RoundedBox(4, 0, -5, w, h+5, Color(0,0,0,70)) end //draw the top of the box higher up (it'll be hidden behind the header) so the upper corners are hidden and it blends smoothly into the header
	pnl:DockPadding(0,0,0,padding) //DSizeToContents is finicky and ignores the bottom dock margin of the lowermost item
	pnl:DockMargin(0,-1,0,0) //fix the 1px of blank white space between the header and the contents

		local check = vgui.Create( "DCheckBoxLabel", pnl)
		check:SetText("Allow animation events to play sounds & particle effects")
		check:SetDark(true)
		check:SetHeight(15)
		check:Dock(TOP)
		check:DockMargin(padding,padding,0,0)

		check:SetValue(animent:GetEnableAnimEventEffects())
		check.OnChange = function(_, val)
			animent:DoInput("misc_animeventfx", val)
		end

	//dummy category to add extra padding to bottom of list if there's a scrollbar
	local pnl = vgui.Create("DSizeToContents", container)
	//rpnl:DockMargin(3,1,3,3)
	pnl:Dock(FILL)
	container:AddItem(pnl)
	//rpnl.Paint = function(self, w, h) draw.RoundedBox(4, 0, 0, w, h, Color(0,0,0,70)) end
	//rpnl:DockPadding(0,0,0,padding) //DSizeToContents is finicky and ignores the bottom dock margin of the lowermost item

	tabs:AddSheet("Misc. Settings", container, "icon16/cog.png")

	//Restore the tab we had selected before, if applicable
	if tab then
		for _, info in pairs (tabs:GetItems()) do
			if info.Name == tab then
				tabs:SetActiveTab(info.Tab)
			end
		end
	end

end

function PANEL:BuildAnimationList(i, filter)

	local ent = self.m_Entity
	if !IsValid(ent) then self:OnEntityLost() return end

	local ent2 = ent:GetPuppeteer()
	if !IsValid(ent2) then ent2 = nil end
	local animent = ent2 or ent //animation settings use the puppeteer if one exists, or ent otherwise

	if filter then 
		if filter == "" then
			filter = nil
		else
			filter = filter:lower()
		end
	end

	//The control window can freeze if it has to add a ton of animation list entries all at once, so create a table of sequences here 
	//and slowly go through it a few at a time in the Think hook.
	local sequencelist = animent:GetSequenceList()
	for k, v in pairs (sequencelist) do
		//convert all of the names to lowercase, otherwise all of the uppercase ones will be sorted above the rest
		sequencelist[k] = string.lower(v)
	end
	//Sort them in alphabetical order
	self["SequenceList" .. i] = {}
	for k, v in SortedPairsByValue(sequencelist) do
		if !filter or v:find(filter) then
			table.insert(self["SequenceList" .. i], v)
		end
			
	end
	self["SequenceListKey" .. i] = 1

end

local entriesperframe = 15

function PANEL:Think()

	local ent = self.m_Entity
	if !IsValid(ent) then self:OnEntityLost() return end
	if ent.AnimpropControlWindow != self and IsValid(ent.AnimpropControlWindow) then self:OnEntityLost() return end //make sure we don't open duplicate control windows
	ent.AnimpropControlWindow = self

	local shouldrebuild = false

	//If the model has been changed for some reason (i.e. model manipulator) then all of the sequences, poseparams, etc. will be different, so we need to reset the controls
	if ent:GetModel() != self.StoredModel then
		self.StoredModel = ent:GetModel()
		shouldrebuild = true
	end

	//If the puppeteer has changed (or been created or removed), then a lot of controls will need to be redirected from the old entity, so reset the controls
	local puppeteer = nil
	if ent.GetPuppeteer then //make sure the nwvar method exists
		puppeteer = ent:GetPuppeteer()
		if !IsValid(puppeteer) then puppeteer = nil end
		if puppeteer != self.StoredPuppeteer then
			self.StoredPuppeteer = puppeteer
			shouldrebuild = true
		end
	end

	if shouldrebuild then
		local d = nil
		if self.AnimChannels and self.AnimChannels[1].Divider then
			d = self.AnimChannels[1].Divider:GetLeftWidth()
		end
		local d2 = nil
		if self.PoseParameters and self.PoseParameters.Divider then
			d2 = self.PoseParameters.Divider:GetLeftWidth()
		end
		local d3 = nil
		if self.Remapping and self.Remapping.Divider then
			d3 = self.Remapping.Divider:GetLeftWidth()
		end
		local tab = nil
		if self.TabPanel and self.TabPanel.GetActiveTab then
			tab = self.TabPanel:GetActiveTab():GetText()
		end

		local animent = puppeteer or ent //animation settings use the puppeteer if one exists, or ent otherwise
		//If the nwvar methods don't exist yet, or we're remapping but don't have RemapInfo yet, then we can't create the controls yet, so make the Think function try again the next time it runs.
		if !animent.GetChannel1Sequence or !ent.GetChannel1Sequence or (IsValid(puppeteer) and !ent.RemapInfo) then
			self.StoredModel = nil
			return
		end

		self:RebuildControls(tab, d, d2, d3)

		//Fix: if animations isn't the active tab when we refresh, then the divider width for anim 1 doesn't set properly for some reason, and we have to do it again on a timer to fix it
		if tab != "Animations" and d then
			timer.Simple(0.25, function() //has to be at least this long and not shorter, not sure why
				if !self or !self.AnimChannels or !self.AnimChannels[1] or !self.AnimChannels[1].Divider then return end
				self.AnimChannels[1].Divider:SetLeftWidth(d)
			end)
		end
	end

	//Go through the sequence lists and create a few animation entries at a time each frame
	for i = 1, 4 do
		if self["SequenceList" .. i] and self["SequenceListKey" .. i] then
			for k = self["SequenceListKey" .. i], self["SequenceListKey" .. i] + entriesperframe do
				local v = self["SequenceList" .. i][k]
				if v then
					local line = self.AnimChannels[i].AnimationList:AddLine(v)
					//if this animation is selected, highlight and scroll down to it
					local entry = self.AnimChannels[i].AnimationTextEntry
					if entry:GetText() == v then
						line:SetSelected(true)
						//If we do this now, line:GetPos() returns 0,0 because the line hasn't been moved into position yet, so wait a frame
						timer.Simple(0, function()
							if self.AnimChannels[i].AnimationList.VBar then
								local x, y = line:GetPos()
								if y > self.AnimChannels[i].AnimationList:GetTall() - line:GetTall() then //only scroll down if we have to
									self.AnimChannels[i].AnimationList.VBar:SetScroll(y)
								end
							end
						end)
					end
					line.OnSelect = function()
						entry:SetText(v)
						entry:OnEnter()
					end
				else
					//We've gone through the whole table, so we're done here, get rid of it
					self["SequenceList" .. i] = nil
					self["SequenceListKey" .. i] = nil
					break
				end
			end
			if self["SequenceListKey" .. i] then self["SequenceListKey" .. i] = self["SequenceListKey" .. i] + entriesperframe + 1 end
		end
	end

end

function PANEL:EntityLost()

	self:Clear()
	self:OnEntityLost()

end

function PANEL:OnEntityLost()
	-- For override
end

//function PANEL:OnRemove()
//end

vgui.Register("AnimpropEditor", PANEL, "Panel")