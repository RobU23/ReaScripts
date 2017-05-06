--[[
@description eGUI - A Lua GUI library for REAPER
@about
	#### eGUI - A Lua GUI library for Cockos Reaper
	
	A mod of Eugen27771's original Lua GUI Template for Reaper
	
	Additional code by Lokasenna and Stephane
	
	#### Features
	- Layers
	- Buttons
	- Checklists
	- Dropdown Lists
	- Knobs
	- Frames
	- Horizontal & Vertical Sliders
	- Horizontal & Vertical Range Sliders
	- Radio Buttons
	- Textboxes
	- Resizable
	- Modularised for import to other scripts
	- Licenced under the GPL v3
@link Forum Thread http://reaper.fm
@noindex
@version 2.0
@author RobU
@changelog
	v2.0
	Forked from EUGEN27771's GUI for Lua
	Modularised
	Refactoring of original code
	Added Vertical Range Slider widget
	Added Textbox widget
	Added polar coordinate support to Knob widgets
	Added Min/Max/Step attributes to all widgets
	Added mousewheel support to range sliders
	Added Layers/Tabs
	Removed dynamic zoom-by-drag
	Added symetrical fixed-step zoom (eg 80%, 90%, 100%...)
	Rewrote Radio Button and Checkbox initialisation and drawing code
	Improved general readability (variable naming, etc.)
	Added standard colour tables (e.g - e.col_red, e.col_grey5, etc.)
--]]
--------------------------------------------------------------------------------
-- eGUI Global variables
--------------------------------------------------------------------------------
-- All eGUI code is stored in this table, which is imported by the calling script. 
e = {}
e.gScale = 1; e.gScaleState = false; e.gActiveLayer = 1

-- eGUI colours
e.col_red     = {.78, .21, .23, .50}
e.col_orange  = {.90, .60, .10, .50}
e.col_yellow  = {.80, .80, .10, .50}
e.col_green   = {.27, .61, .36, .50}
e.col_blue    = {.27, .43, .58, .50}
e.col_grey4   = {.40, .40, .40, .40}
e.col_grey5   = {.50, .50, .50, .50}
e.col_grey6   = {.60, .60, .60, .60}
e.col_grey7   = {.70, .70, .70, .70}
e.col_grey8   = {.80, .80, .80, .80}
e.col_grey9   = {.90, .90, .90, .90}
e.col_greym   = {.50, .50, .50, .90}
 
-- common shared Windows and Mac sans-serif fonts
e.Arial     = "Arial"
e.Lucinda   = "Lucinda Sans Unicode"
e.Tahoma    = "Tahoma"
e.Trebuchet = "Trebuchet MS"
e.Verdana   = "Verdana"
e.MSSans    = "MS Sans Serif"
--------------------------------------------------------------------------------
-- eGUI Utility functions
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- wrap(n, max) - returns n wrapped between 0 and max
--------------------------------------------------------------------------------
function e.wrap(n, max)
	n = n % max
	if (n < 1) then
		n = n + max
	end
	return n
end
--------------------------------------------------------------------------------
-- RGB2Packed(r, g, b) - returns a packed rgb value
--------------------------------------------------------------------------------
function e.RGB2Packed(r, g, b)
	local floor = math.floor
		g = (g << 8)
		b = (b << 16)
	return floor(r + g + b)
end
--------------------------------------------------------------------------------
-- Packed2RGB(p) - returns r, g, b from a packed rgb value
--------------------------------------------------------------------------------
function e.Packed2RGB(p)
	local floor = math.floor
	local b, lsb, g, lsg, r = 0, 0, 0, 0, 0
	b = (p >> 16);	lsb = (b << 16);	p = p - lsb
	g = (p >> 8);	  lsg = (g << 8);	  p = p - lsg
	return floor(p), floor(g), floor(b)
end
--------------------------------------------------------------------------------
-- RGB2Dec(r, g, b) - takes 8 bit r, g, b values, returns decimal (0 to 1)
--------------------------------------------------------------------------------
function e.RGB2Dec(r, g, b)
	if r < 0 or r > 255 then r = wrap(r, 255) end
	if g < 0 or g > 255 then g = wrap(g, 255) end
	if b < 0 or b > 255 then b = wrap(b, 255) end
	return r/255, g/255, b/255
end
--------------------------------------------------------------------------------
-- Cart2Polar(x_pos, y_pos, orig_x, orig_y) - returns radius and angle
--------------------------------------------------------------------------------
function e.Cart2Polar(p_x, p_y, orig_x, orig_y)
	local x, y = p_x - orig_x, p_y - orig_y
	local radius = (x^2 + y^2) ^ 0.5
	local angle = math.deg(math.atan(y, x))
	if angle < 0 then angle = angle + 360 end
	return radius, angle
end
--------------------------------------------------------------------------------
-- Polar2Cart(radias, angle, orig_x, orig_y) - returns x_pos and y_pos
--------------------------------------------------------------------------------
function e.Polar2Cart(radius, angle, orig_x, orig_y)
	local angle = angle * math.pi
	local x, y = radius * math.cos(angle), radius * math.sin(angle)
	return x + orig_x, y + orig_y
end
--------------------------------------------------------------------------------
-- Element Class
--------------------------------------------------------------------------------
e.Element = {}
function e.Element:new(tab, x,y,w,h, rgba, label, font, font_sz, font_rgba, val1, val2, min, max, step)
	local elm = {}
	local bf = 0
	if tab[1] == 0 then  -- convert the tabs table to a bitfield
		bf = 0
	else   
		for i = 1, #tab do
			bf = bf + (1 << tab[i])
		end
	end
	elm.tab = bf
	elm.def_xywh = {x,y,w,h, font_sz} -- default coordinates, used for zoom and some Element initialisation
	elm.x, elm.y, elm.w, elm.h = x, y, w, h -- position and size
	elm.r, elm.g, elm.b, elm.a = table.unpack(rgba) -- Element colour
	elm.label, elm.font, elm.font_sz, elm.font_rgba  = label, font, font_sz, font_rgba -- all things fonty
	elm.val1 = val1;	elm.val2 = val2 -- general purpose variables or tables
	elm.min, elm.max, elm.step = min, max, step -- for incrementing or decrementing values
	setmetatable(elm, self)
	self.__index = self
	return elm
end
--------------------------------------------------------------------------------
-- Element Class Methods
--------------------------------------------------------------------------------
function e.Element:update_zoom() -- generic e.Element scaling
	if not e.gScaleState then return end
	self.x = math.ceil(self.def_xywh[1] * e.gScale)	-- update x position
	self.w = math.ceil(self.def_xywh[3] * e.gScale) -- update width
	self.y = math.ceil(self.def_xywh[2] * e.gScale) -- update y position
	self.h = math.ceil(self.def_xywh[4] * e.gScale) -- update height
	if self.font_sz then -- required for the Frame e.Element which has no font defined
		self.font_sz = math.max(10, self.def_xywh[5] * e.gScale) -- update font
		self.font_sz = math.min(28, self.font_sz)
	end       
end
--------------------------------------------------------------------------------
function e.Element:pointIN(p_x, p_y)
	return p_x >= self.x and p_x <= self.x + self.w and p_y >= self.y and p_y <= self.y + self.h
end
--------------------------------------------------------------------------------
function e.Element:mouseIN()
	return gfx.mouse_cap & 1 == 0 and self:pointIN(gfx.mouse_x, gfx.mouse_y)
end
--------------------------------------------------------------------------------
function e.Element:mouseLDown()
	return gfx.mouse_cap & 1 == 1 and self:pointIN(gMouseOX, gMouseOY)
end
--------------------------------------------------------------------------------
function e.Element:mouseUp()
	return gfx.mouse_cap & 1 == 0 and self:pointIN(gMouseOX, gMouseOY)
end
--------------------------------------------------------------------------------
function e.Element:mouseLClick()
	return gfx.mouse_cap & 1 == 0 and gLastMouseCap & 1 == 1 and
	self:pointIN(gfx.mouse_x, gfx.mouse_y) and self:pointIN(gMouseOX, gMouseOY)         
end
--------------------------------------------------------------------------------
function e.Element:mouseRClick()
	return gfx.mouse_cap & 2 == 0 and gLastMouseCap & 2 == 2 and
	self:pointIN(gfx.mouse_x, gfx.mouse_y) and self:pointIN(gMouseOX, gMouseOY)         
end
--------------------------------------------------------------------------------
function e.Element:mouseRDown()
	return gfx.mouse_cap & 2 == 2 and self:pointIN(gMouseOX, gMouseOY)
end
--------------------------------------------------------------------------------
function e.Element:mouseMDown()
	return gfx.mouse_cap & 64 == 64 and self:pointIN(gMouseOX, gMouseOY)
end
--------------------------------------------------------------------------------
function e.Element:draw_frame() -- generic e.Element frame drawing
	gfx.rect(self.x, self.y, self.w, self.h, false) -- frame1
	gfx.roundrect(self.x, self.y, self.w - 1, self.h - 1, 3, true) -- frame2         
end
--------------------------------------------------------------------------------
-- Metatable funtion for child classes(args = Child, Parent Class)
--------------------------------------------------------------------------------
function e.extended(Child, Parent)
	setmetatable(Child, {__index = Parent}) 
end
--------------------------------------------------------------------------------
-- Create Element Child Classes
-- Button, Checkbox, Droplist, Frame, Knob, Sliders, Textbox
--------------------------------------------------------------------------------
-- removed local <elm>
e.Button = {};       e.extended(e.Button, e.Element)
e.Checkbox = {};     e.extended(e.Checkbox, e.Element)
e.Droplist = {};     e.extended(e.Droplist, e.Element)
e.Frame = {};        e.extended(e.Frame, e.Element)
e.Knob = {};         e.extended(e.Knob, e.Element)
e.Rad_Button = {};   e.extended(e.Rad_Button, e.Element)
e.H_Rng_Slider = {}; e.extended(e.H_Rng_Slider, e.Element)
e.V_Rng_Slider = {}; e.extended(e.V_Rng_Slider, e.Element)
e.Slider = {};       e.extended(e.Slider, e.Element)
e.Horz_Slider = {};  e.extended(e.Horz_Slider, e.Slider)
e.Vert_Slider = {};  e.extended(e.Vert_Slider, e.Slider)
e.Textbox = {};      e.extended(e.Textbox, e.Element)
--------------------------------------------------------------------------------
-- Button Class Methods
--------------------------------------------------------------------------------
function e.Button:draw_body()
	gfx.rect(self.x, self.y, self.w, self.h, true)
end
--------------------------------------------------------------------------------
function e.Button:draw_label()
	local labelWidth, labelHeight = gfx.measurestr(self.label)
	gfx.x = self.x + (self.w - labelWidth) / 2
	gfx.y = self.y + (self.h - labelHeight) / 2
	gfx.drawstr(self.label)
end
---------------------------------------------------------------------------------
function e.Button:draw()
	if (self.tab & (1 << e.gActiveLayer)) == 0 and self.tab ~= 0 then return end
	self:update_zoom()  
	local a = self.a -- local alpha value for highlight
	-- Get mouse state	
	if self:mouseIN() 		then a = a + 0.1 end  -- if in e.Element, increase opacity
	if self:mouseLDown()	then a = a + 0.2 end  -- if e.Element clicked, increase opacity more
	-- in elm L_up (released and was previously pressed), run onLClick (user defined)
	if self:mouseLClick() and self.onLClick then self.onLClick() end
	-- in elm R_up (released and was previously pressed), run onRClick (user defined)
	if self:mouseRClick() and self.onRClick then self.onRClick() end
	gfx.set(self.r, self.g, self.b, a) -- set e.Element color
	self:draw_body()
	self:draw_frame()
	gfx.set(table.unpack(self.font_rgba)) -- set label color
	gfx.setfont(1, self.font, self.font_sz) -- set label font & size
	self:draw_label()
end
--------------------------------------------------------------------------------
-- Checkbox Class Methods
--------------------------------------------------------------------------------
function e.Checkbox:update_zoom() -- handle window zooming
	if not e.gScaleState then return end
	-- zoom font  
	self.font_sz = math.max(10, self.def_xywh[5] * e.gScale)
	self.font_sz = math.min(28, self.font_sz)
	-- zoom x pos, y pos 
	self.x = math.ceil(self.def_xywh[1] * e.gScale)
	self.y = math.ceil(self.def_xywh[2] * e.gScale)
	-- zoom checkboxes
	self.cbox_w = math.ceil(self.def_xywh[6] * e.gScale)
	self.cbox_h = math.ceil(self.def_xywh[7] * e.gScale)   
	-- zoom width
	local str_w, str_h, max_w = 0, 0, 0
	gfx.setfont(1, self.font, self.font_sz)
	for i = 1, #self.val2 do
		str_w, str_h = gfx.measurestr(self.val2[i])
		if str_w > max_w then max_w = str_w end	
	end
	self.def_xywh[3] = max_w + self.cbox_w + 15
	self.w = math.ceil(self.def_xywh[3])
	-- zoom height	
	self.def_xywh[4] = self.cbox_h * #self.val2
	self.h = math.ceil(self.def_xywh[4]) 
end
--------------------------------------------------------------------------------
function e.Checkbox:set_val1()
	local y, h = self.y + 2, self.h -4 -- padding
	local tOptState = self.val1 -- contains the current state of each option
	local tOptions = self.val2 -- the table of options
	local optIdx = math.floor(((gfx.mouse_y - y) / h) * #tOptions) + 1
	if optIdx < 1 then optIdx = 1 elseif optIdx > #tOptions then optIdx = #tOptions end
	if tOptState[optIdx] == 0 then tOptState[optIdx] = 1
	elseif tOptState[optIdx] == 1 then tOptState[optIdx] = 0 end
end
--------------------------------------------------------------------------------
function e.Checkbox:draw_body()
	local x, y = self.x + 2, self.y -- padding
	local padSize = 0.5 * e.gScale -- more padding...
	local tOptState = self.val1 -- current state of each option
	local square = 2 * self.cbox_w / 3
	local centerOffset = ((self.cbox_w - square) / 2)
	-- adjust the options to be centered
	local cx, cy = x + centerOffset, y + centerOffset
	-- necessary to keep the GUI's resizing code from making the square wobble	
	--square = math.floor((square / 4) + 0.5) * 4
	for optIdx = 1, #self.val2 do
		local optY = cy + ((optIdx - 1) * self.cbox_w)
		gfx.roundrect(cx, optY, square, square, true)
		gfx.rect(cx, optY, square, square, false)
		if tOptState[optIdx] == 1 then
			gfx.rect(cx, optY, square + 1, square + 1, true) -- big square
			gfx.rect(cx + (square / 4), optY + (square / 4), square / 2, square / 2, true) -- small square
			gfx.roundrect(cx + (square / 4), optY + (square / 4), square / 2 - 1, square / 2 - 1, true) -- small frame
		end
	end
end
--------------------------------------------------------------------------------
function e.Checkbox:draw_vals()
	local x, y, optY = self.x + 2, self.y + 2 -- padding
	local tOptions = self.val2 -- table of options
	-- to match up with the options
	local square = 2 * self.cbox_w / 3
	local centerOffset = ((self.cbox_w - square) / 2)
	cx, cy = x + self.cbox_w + centerOffset, y + centerOffset 
	for i = 1, #tOptions do
		optY = cy + ((i - 1) * self.cbox_w)
		gfx.x, gfx.y = cx, optY
		gfx.drawstr(tOptions[i])
	end
end
--------------------------------------------------------------------------------
function e.Checkbox:draw_label()
	local x, y  = self.x, self.y + 2 -- padding
	-- to match up with the first option
	local square = 2 * self.cbox_w / 3
	local centerOffset = ((self.cbox_w - square) / 2)
	sy = y + centerOffset
	local labelWidth, labelHeight = gfx.measurestr(self.label)
	gfx.x = x + centerOffset -- labelWidth - 5; 
	gfx.y = self.y + self.h + labelHeight / 2 --gfx.y = sy
	gfx.drawstr(self.label) 
end
--------------------------------------------------------------------------------
function e.Checkbox:draw()
	while not self.setup do -- on first run, set the correct width and height
		local str_w, str_h, max_w = 0, 0, 0	
		self.cbox_w, self.cbox_h = self.w, self.h
		gfx.setfont(1, self.font, self.font_sz)
		for i = 1, #self.val2 do
			str_w, str_h = gfx.measurestr(self.val2[i])			
			if str_w > max_w then max_w = str_w end
		end
		self.def_xywh[3] = self.cbox_w + max_w + 15; self.w = self.def_xywh[3]
		self.def_xywh[4] = self.cbox_h * #self.val2; self.h = self.def_xywh[4]
		self.def_xywh[6] = self.cbox_w; self.def_xywh[7] = self.cbox_h
		self.setup = true
	end  
	if (self.tab & (1 << e.gActiveLayer)) == 0 and self.tab ~= 0 then return end 
	self:update_zoom() -- check and update if window resized
	local a = self.a -- local alpha value for highlighting the e.Element
	if self:mouseIN() then a = a + 0.1 end -- if in e.Element, increase opacity
	if self:mouseLDown() then a = a + 0.2 end -- if e.Element clicked, increase opacity more
	-- in elm L_up(released and was previously pressed)
	if self:mouseLClick() then 
		self:set_val1()
		if self.onLClick then self.onLClick() end -- if mouseL clicked and released, execute onLClick()
	end
	if self:mouseRClick() and self.onRClick then self.onRClick() end -- if mouseR clicked and released, execute onRClick()
	gfx.set(self.r, self.g, self.b, a) -- set the drawing colour for the e.Element
	-- allow for a simple toggle with no frame
	-- if #self.val2 > 1 then self:draw_frame() end -- looks better without the frame...
	self:draw_body()
	gfx.set(table.unpack(self.font_rgba)) -- set label color
	gfx.setfont(1, self.font, self.font_sz) -- set label font
	self:draw_vals()
	if #self.val2 > 1 then self:draw_label() end -- allow for single toggle
end
--------------------------------------------------------------------------------
-- Droplist Class Methods
--------------------------------------------------------------------------------
function e.Droplist:set_norm_val_m_wheel()
	if gfx.mouse_wheel == 0 then return false end  -- return if m_wheel = 0
	if gfx.mouse_wheel < 0 then self.val1 = math.min(self.val1 + 1, #self.val2) end
	if gfx.mouse_wheel > 0 then self.val1 = math.max(self.val1 - 1, 1) end
	return true
end
--------------------------------------------------------------------------------
function e.Droplist:set_val1()
	local x, y, w, h  = self.x, self.y, self.w, self.h
	local val = self.val1
	local menu_tb = self.val2
	local menu_str = ""
	for i = 1, #menu_tb, 1 do
		if i ~= val then menu_str = menu_str .. menu_tb[i] .. "|"
		else menu_str = menu_str .. "!" .. menu_tb[i] .. "|" -- add check
		end
	end
	gfx.x = self.x; gfx.y = self.y + self.h
	local new_val = gfx.showmenu(menu_str) -- show Droplist menu
	if new_val > 0 then self.val1 = new_val end
end
--------------------------------------------------------------------------------
function e.Droplist:draw_body()
	gfx.rect(self.x, self.y, self.w, self.h, true)
end
--------------------------------------------------------------------------------
function e.Droplist:draw_label()
	local labelW, labelH = gfx.measurestr(self.label)
	local pad = 5
	gfx.x = self.x + ((self.w / 2) - (labelW / 2))
	gfx.y = self.y - ((labelH) + (labelH / 3))
	gfx.drawstr(self.label)
end
--------------------------------------------------------------------------------
function e.Droplist:draw_val()
	local x, y, w, h  = self.x, self.y, self.w, self.h
	local val = self.val2[self.val1]
	local val_w, val_h = gfx.measurestr(val)
	gfx.x = x + ((w / 2) - (val_w / 2))
	gfx.y = y + (h - val_h) / 2
	gfx.drawstr(val)
end
--------------------------------------------------------------------------------
function e.Droplist:draw()
	if (self.tab & (1 << e.gActiveLayer)) == 0 and self.tab ~= 0 then return end 
	self:update_zoom() -- check and update if window resized
	local a = self.a -- local alpha value for highlighting the e.Element
	if self:mouseIN() then a = a + 0.1 -- if in e.Element, increase opacity
		if self:set_norm_val_m_wheel() then
			if self.onLClick then self.onLClick() end 
		end 
	end
	if self:mouseLDown() then a = a + 0.2 end -- if e.Element clicked, increase opacity more
	-- in elm L_up(released and was previously pressed)
	if self:mouseLClick() then self:set_val1()
		if self:mouseLClick() and self.onLClick then self.onLClick() end
	end
	-- right click support
	if self:mouseRClick() and self.onRClick then self.onRClick() end
	-- Draw combo body, frame
	gfx.set(self.r, self.g, self.b, a) -- set the drawing colour for the e.Element
	self:draw_body()
	self:draw_frame()
	-- Draw label
	gfx.set(table.unpack(self.font_rgba))   -- set label color
	gfx.setfont(1, self.font, self.font_sz) -- set label font
	self:draw_label() -- draw label
	self:draw_val() -- draw val
end
--------------------------------------------------------------------------------
-- Frame Class Methods
--------------------------------------------------------------------------------
function e.Frame:draw()
	if (self.tab & (1 << e.gActiveLayer)) == 0 and self.tab ~= 0 then return end 
	self:update_zoom() -- check and update if window resized
	local a  = self.a -- local alpha value required for highlighting the e.Element
	if self:mouseIN() then a = a + 0.1 end -- if in e.Element, increase opacity
	gfx.set(self.r, self.g, self.b, a) -- set the drawing colour for the e.Element
	self:draw_frame()
end
--------------------------------------------------------------------------------
-- Knob Class Methods
--------------------------------------------------------------------------------
function e.Knob:pointIN(p_x, p_y)
	local radius, angle = e.Cart2Polar(p_x, p_y, self.ox, self.oy)
	return radius <= self.radius
end
--------------------------------------------------------------------------------
function e.Knob:set_val1()
	local val, K = 0, 5 -- val = temp value; K = coefficient(when Ctrl pressed)
	if Ctrl then 
		val = self.val1 + ((gLastMouseY-gfx.mouse_y) / (self.h * K)) * self.max
	else 
		val = self.val1 + ((gLastMouseY-gfx.mouse_y) / self.h) * self.max
	end
	if val < self.min then val = self.min elseif val > self.max then val = self.max end
	self.val1 = val
end
--------------------------------------------------------------------------------
function e.Knob:set_norm_val_m_wheel()
	if gfx.mouse_wheel == 0 then return end  -- return if m_wheel = 0
	if gfx.mouse_wheel > 0 then self.val1 = math.min(self.val1 + self.step, self.max) end
	if gfx.mouse_wheel < 0 then self.val1 = math.max(self.val1 - self.step, self.min) end
	return true
end
--------------------------------------------------------------------------------
function e.Knob:draw_body()
	local floor = math.floor
	local radius = self.w / 2
	local ox, oy = self.x + self.w / 2, self.y + self.h / 2 -- knob centre origin
	local mx, my = floor(gfx.mouse_x), floor(gfx.mouse_y) -- get the mouse pos - debug only
	local r1, ang = e.Cart2Polar(mx, my, ox, oy) -- debug only
	gfx.circle(ox, oy, radius / 2, true) -- inner  
	gfx.circle(ox, oy, radius, false, true); gfx.circle(ox, oy, radius-0.5, false, true) -- outer
	local pi = math.pi
	local offs = pi + pi / 4 -- quarter of a circle offset to start of range
	local val1 = 1.5 * pi / self.max * self.val1 -- offset 
	local ang1, ang2 = offs - 0.01, offs + val1  
	for i = 1, 10 do -- draw outer circle value range
		gfx.arc(ox, oy, radius - 1, ang1, ang2, true)
		radius = radius - 0.5
	end
end
--------------------------------------------------------------------------------
function e.Knob:draw_label()
	local labelWidth, labelHeight = gfx.measurestr(self.label)
	gfx.x = self.ox - labelWidth / 2; gfx.y = self.oy + self.radius + (labelHeight / 2)
	gfx.drawstr(self.label)
end
--------------------------------------------------------------------------------
function e.Knob:draw_val()
	local str = string.format("%.0f", self.val1)
	local strW, strH = gfx.measurestr(str)
	gfx.x = self.ox - (strW / 2)
	gfx.y = self.oy - (strH / 2) 
	gfx.drawstr(str) -- draw knob Value
end
--------------------------------------------------------------------------------
function e.Knob:draw()
	if (self.tab & (1 << e.gActiveLayer)) == 0 and self.tab ~= 0 then return end 
	self:update_zoom() -- check and update if window resized
	local a = self.a -- local alpha for highlighting the e.Element
	-- set additional knob specific state
	self.radius = self.w / 2
	self.ox, self.oy = self.x + self.w / 2, self.y + self.h / 2
	if self:mouseIN() then a = a + 0.1 -- if in e.Element, increase opacity
		if self:set_norm_val_m_wheel() then 
			if self.onMove then self.onMove() end 
		end  
	end
	if self:mouseLDown() then a = a + 0.2 -- if e.Element clicked, increase opacity more 
		self:set_val1()
		if self.onMove then self.onMove() end 
	end
	if self:mouseRClick() and self.onRClick then self.onRClick() end -- if mouseR clicked and released, execute onRClick()
	gfx.set(self.r, self.g, self.b, a + 0.1) -- set the drawing colour for the e.Element
	self:draw_body()
	gfx.set(table.unpack(self.font_rgba)) -- set label color
	gfx.setfont(1, self.font, self.font_sz) -- set label font
	self:draw_label() -- draw label(if need)
	self:draw_val() -- draw value
end
--------------------------------------------------------------------------------
--  Radio Button Class Methods
--------------------------------------------------------------------------------
function e.Rad_Button:update_zoom() -- handle window zooming
	if not e.gScaleState then return end
	-- zoom font  
	self.font_sz = math.max(10, self.def_xywh[5] * e.gScale)
	self.font_sz = math.min(28, self.font_sz)
	-- zoom x pos, y pos 
	self.x = math.ceil(self.def_xywh[1] * e.gScale)
	self.y = math.ceil(self.def_xywh[2] * e.gScale)
	-- zoom checkboxes
	self.cbox_w = math.ceil(self.def_xywh[6] * e.gScale)
	self.cbox_h = math.ceil(self.def_xywh[7] * e.gScale)   
	-- zoom width
	local str_w, str_h, max_w = 0, 0, 0
	gfx.setfont(1, self.font, self.font_sz)
	for i = 1, #self.val2 do
		str_w, str_h = gfx.measurestr(self.val2[i])
		if str_w > max_w then max_w = str_w end	
	end
	self.def_xywh[3] = max_w + self.cbox_w + 15
	self.w = math.ceil(self.def_xywh[3])
	-- zoom height	
	self.def_xywh[4] = self.cbox_h * #self.val2
	self.h = math.ceil(self.def_xywh[4]) -- * gZoomH) --scale) 
end
--------------------------------------------------------------------------------
function e.Rad_Button:set_norm_val_m_wheel()
	if gfx.mouse_wheel == 0 then return false end  -- return if m_wheel = 0
	if gfx.mouse_wheel < 0 then self.val1 = math.min(self.val1 + 1, #self.val2) end
	if gfx.mouse_wheel > 0 then self.val1 = math.max(self.val1 - 1, 1) end
	return true
end
--------------------------------------------------------------------------------
function e.Rad_Button:set_val1()
	local y, h = self.y + 2, self.h - 4 -- padding
	local tOptions = self.val2
	local val = math.floor(((gfx.mouse_y - y) / h) * #tOptions) + 1
	if val < 1 then val = 1 elseif val > #tOptions then val = #tOptions end
	self.val1 = val
end
--------------------------------------------------------------------------------
function e.Rad_Button:draw_body()
	local x, y = self.x + 2, self.y -- padding
	local padSize = .25 * e.gScale -- more padding...
	local r = self.cbox_w / 3
	local centerOffset = ((self.cbox_w - (2 * r)) / 2)
	-- adjust the options to be centered
	cx, cy = x + centerOffset, y + centerOffset
	for i = 1, #self.val2 do
		local optY = cy + ((i - 1) * self.cbox_w)
		gfx.circle(cx + r, optY + r, r, false)
		gfx.circle(cx + r, optY + r, r - padSize, false, true)
		if i == self.val1 then
			gfx.circle(cx + r, optY + r, r, true) -- big circle	
			gfx.circle(cx + r, optY + r, r * 0.5, true) -- small circle
			gfx.circle(cx + r, optY + r, r * 0.5, false) -- small frame
		end
	end
end
--------------------------------------------------------------------------------
function e.Rad_Button:draw_vals()
	local x, y, optY = self.x + 2, self.y + 2 -- padding
	local tOptions = self.val2 -- table of options
	-- to match up with the options
	local r = self.cbox_w / 3
	local centerOffset = ((self.optSpacing - (2 * r)) / 2)
	cx, cy = x + self.cbox_w + centerOffset, y + centerOffset
	for i = 1, #tOptions do
		optY = cy + ((i - 1) * self.cbox_w)
		gfx.x, gfx.y = cx, optY
		gfx.drawstr(tOptions[i])
	end
end
--------------------------------------------------------------------------------
function e.Rad_Button:draw_label()
	local x, y = self.x, self.y + 2 -- padding
	local optSpacing = self.optSpacing
	-- to match up with the first option
	local r = self.cbox_w / 3
	local centerOffset = ((self.cbox_w - (2 * r)) / 2)
	y = y + centerOffset
	local labelWidth, labelHeight = gfx.measurestr(self.label)
	gfx.x = x + centerOffset-- labelWidth - 5
	gfx.y = self.y + self.h + labelHeight / 2 
	gfx.drawstr(self.label) 
end
--------------------------------------------------------------------------------
function e.Rad_Button:draw()
	while not self.setup do -- on first run, set the correct width and height
		local str_w, str_h, max_w = 0, 0, 0	
		self.cbox_w, self.cbox_h = self.w, self.h
		gfx.setfont(1, self.font, self.font_sz)
		for i = 1, #self.val2 do
			str_w, str_h = gfx.measurestr(self.val2[i])			
			if str_w > max_w then max_w = str_w end
		end
		self.def_xywh[3] = self.cbox_w + max_w + 15; self.w = self.def_xywh[3]
		self.def_xywh[4] = self.cbox_h * #self.val2; self.h = self.def_xywh[4]
		self.def_xywh[6] = self.cbox_w; self.def_xywh[7] = self.cbox_h
		self.setup = true
	end
	if (self.tab & (1 << e.gActiveLayer)) == 0 and self.tab ~= 0 then return end 
	self:update_zoom() -- check and update if window resized
	local a = self.a -- local alpha value required for highlighting the e.Element
	self.optSpacing = (self.h / (#self.val2 or 1)) -- e.Element height / number of options
	if self:mouseIN() then a = a + 0.1 -- if in e.Element, increase opacity 
		if self:set_norm_val_m_wheel() then 
			if self.onLClick then self.onLClick() end 
		end 
	end
	-- in elm L_up(released and was previously pressed)
	if self:mouseLDown() then a = a + 0.2 end -- if e.Element clicked, increase opacity more
	-- in elm L_up(released and was previously pressed)
	if self:mouseLClick() then 
		self:set_val1()
		if self.onLClick then self.onLClick() end -- if mouseL clicked and released, execute onLClick()
	end
	if self:mouseRClick() and self.onRClick then self.onRClick() end -- if mouseR clicked and released, execute onRClick()
	gfx.set(self.r, self.g, self.b, a) -- set the drawing colour for the e.Element
	-- self:draw_frame()	-- looks better without the frame
	self:draw_body()
	gfx.set(table.unpack(self.font_rgba)) -- set label color
	gfx.setfont(1, self.font, self.font_sz) -- set label font 
	self:draw_vals()
	self:draw_label()
end
--------------------------------------------------------------------------------
-- Slider Class Methods
--------------------------------------------------------------------------------
function e.Slider:set_norm_val_m_wheel()
	if gfx.mouse_wheel == 0 then return false end  -- return if m_wheel = 0
	local K = 1 -- K = coefficient
	if Ctrl then K = 5 end	
	if gfx.mouse_wheel > 0 then self.val1 = math.min(self.val1 + self.step * K, self.max) end
	if gfx.mouse_wheel < 0 then self.val1 = math.max(self.val1 - self.step * K, self.min) end
	return true
end
--------------------------------------------------------------------------------
function e.Horz_Slider:set_val1()
	local val, K = 0, 5 -- val = temp value; K = coefficient (when Ctrl pressed)
	if Ctrl then
		val = self.val1 + ((gfx.mouse_x - gLastMouseX) / (self.w * K) * self.max)
	else 
		val =(gfx.mouse_x - self.x) / self.w * self.max
	end
	if val < self.min then val = self.min elseif val > self.max then val = self.max end
	self.val1 = val
end
--------------------------------------------------------------------------------
function e.Horz_Slider:draw_body()
	local rng_width = self.w / self.max * self.val1
	gfx.rect(self.x, self.y, rng_width, self.h, true)
end
--------------------------------------------------------------------------------
function e.Horz_Slider:draw_label()
	local labelWidth, labelHeight = gfx.measurestr(self.label)
	gfx.x = self.x + 5; gfx.y = self.y + (self.h - labelHeight) / 2;
	gfx.drawstr(self.label)
end
--------------------------------------------------------------------------------
function e.Horz_Slider:draw_val()
	local val = string.format("%.0f", self.val1)
	local val_w, val_h = gfx.measurestr(val)
	gfx.x = self.x + self.w - val_w - 5; gfx.y = self.y + (self.h - val_h) / 2;
	gfx.drawstr(val)
end
--------------------------------------------------------------------------------
function e.Vert_Slider:set_val1()
	local val, K = 0, 5 -- val=temp value; K=coefficient (when Ctrl pressed)
	if Ctrl then 
		val = self.val1 + ((gLastMouseY - gfx.mouse_y) / (self.h * K)) * self.max
	else
		val = (self.h - (gfx.mouse_y - self.y)) / self.h * self.max
	end
	if val < self.min then val = self.min elseif val > self.max then val = self.max end
	self.val1 = val
end
--------------------------------------------------------------------------------
function e.Vert_Slider:draw_body()
	local rng_height = self.h / self.max * self.val1
	gfx.rect(self.x, self.y + self.h - rng_height, self.w, rng_height, true)
end
--------------------------------------------------------------------------------
function e.Vert_Slider:draw_label()
	local labelWidth, labelHeight = gfx.measurestr(self.label)
	gfx.x = self.x + (self.w - labelWidth) / 2
	--gfx.y = self.y + self.h + (labelHeight / 2) -- bottom of slider
	gfx.y = self.y + self.h - labelHeight - 5; -- inside slider
	gfx.drawstr(self.label)
end
--------------------------------------------------------------------------------
function e.Vert_Slider:draw_val()
	local val = string.format("%.0f", self.val1)
	local val_w, val_h = gfx.measurestr(val)
	gfx.x = self.x + (self.w - val_w) / 2
	gfx.y = self.y + 5
	gfx.drawstr(val)
end
--------------------------------------------------------------------------------
function e.Slider:draw()
	if (self.tab & (1 << e.gActiveLayer)) == 0 and self.tab ~= 0 then return end 
	self:update_zoom() -- check and update if window resized
	local a  = self.a -- local alpha value required for highlighting the e.Element
	if self:mouseIN() then a = a + 0.1 -- if in e.Element, increase opacity
		if self:set_norm_val_m_wheel() then 
			if self.onMove then self.onMove() end 
		end  
	end
	if self:mouseLDown() then 
		a = a + 0.2 -- if e.Element clicked, increase opacity more
		self:set_val1()
		if self.onMove then self.onMove() end 
	end
	if self:mouseRClick() and self.onRClick then self.onRClick() end
	gfx.set(self.r, self.g, self.b, a) -- set the drawing colour for the e.Element
	self:draw_body()
	self:draw_frame()
	gfx.set(table.unpack(self.font_rgba))   -- set label color
	gfx.setfont(1, self.font, self.font_sz) -- set label font
	self:draw_label()
	self:draw_val()
end
--------------------------------------------------------------------------------
-- Horizontal Range Slider Class Methods
--------------------------------------------------------------------------------
function e.H_Rng_Slider:pointIN_LHnd(p_x, p_y)
	local range_lx = self.rng_x + self.rng_w / self.max * self.val1 -- x pos of left edge of range (abs)
	return p_x >= range_lx - self.hnd_w and p_x <= range_lx and p_y >= self.y and p_y <= self.y + self.h
end
--------------------------------------------------------------------------------
function e.H_Rng_Slider:pointIN_RHnd(p_x, p_y)
	local range_rx = self.rng_x + self.rng_w / self.max * self.val2 -- x pos of right edge of range (abs)
	return p_x >= range_rx and p_x <= self.hnd_w + range_rx and p_y >= self.y and p_y <= self.y + self.h
end
--------------------------------------------------------------------------------
function e.H_Rng_Slider:pointIN_Rng(p_x, p_y)
	local range_lx = self.rng_x + self.rng_w / self.max * self.val1 -- x pos of left edge of range (abs)
	local range_rx = self.rng_x + self.rng_w / self.max * self.val2 -- x pos of right edge of range (abs)
	return p_x >= range_lx and p_x <= range_rx and p_y >= self.y and p_y <= self.y + self.h
end
--------------------------------------------------------------------------------
function e.H_Rng_Slider:mouseIN_LHnd()
	return gfx.mouse_cap & 1 == 0 and self:pointIN_LHnd(gfx.mouse_x, gfx.mouse_y)
end
--------------------------------------------------------------------------------
function e.H_Rng_Slider:mouseIN_RHnd()
	return gfx.mouse_cap & 1 == 0 and self:pointIN_RHnd(gfx.mouse_x, gfx.mouse_y)
end
--------------------------------------------------------------------------------
function e.H_Rng_Slider:mouseIN_Rng()
	return gfx.mouse_cap & 1 == 0 and self:pointIN_Rng(gfx.mouse_x, gfx.mouse_y)
end
--------------------------------------------------------------------------------
function e.H_Rng_Slider:mouseLDown_LHnd()
	return gfx.mouse_cap & 1 == 1 and gLastMouseCap & 1 == 0 and self:pointIN_LHnd(gMouseOX, gMouseOY)
end
--------------------------------------------------------------------------------
function e.H_Rng_Slider:mouseLDown_RHnd()
	return gfx.mouse_cap & 1 == 1 and gLastMouseCap & 1 == 0 and self:pointIN_RHnd(gMouseOX, gMouseOY)
end
--------------------------------------------------------------------------------
function e.H_Rng_Slider:mouseLDown_rng()
	return gfx.mouse_cap & 1 == 1 and gLastMouseCap & 1 == 0 and self:pointIN_Rng(gMouseOX, gMouseOY)
end
--------------------------------------------------------------------------------
function e.H_Rng_Slider:set_val1()
	local K = 1 -- K = coefficient
	if Ctrl then K = 5 end
	local val = self.val1 + ((gfx.mouse_x - gLastMouseX) / (self.rng_w * K) * self.max)
	if val < self.min then val = self.min elseif val > self.val2 then val = self.val2 end
	self.val1 = val
end
--------------------------------------------------------------------------------
function e.H_Rng_Slider:set_val2()
	local K = 1 -- K = coefficient
	if Ctrl then K = 5 end
	local val = self.val2 + ((gfx.mouse_x - gLastMouseX) / (self.rng_w * K) * self.max)
	if val < self.val1 then val = self.val1 elseif val > self.max then val = self.max end
	self.val2 = val
end
--------------------------------------------------------------------------------
function e.H_Rng_Slider:set_val_both()
	local diff = self.val2 - self.val1 -- range size
	local K = 1 -- K = coefficient
	if Ctrl then K = 5 end
	local val  = self.val1  + (gfx.mouse_x - gLastMouseX) / (self.w * K) * self.max
	if val < self.min then val = self.min elseif val > self.max - diff then val = self.max - diff end
	self.val1 = val
	self.val2 = val + diff
end
--------------------------------------------------------------------------------
function e.H_Rng_Slider:set_vals_m_wheel()
	if gfx.mouse_wheel == 0 then return false end  -- return if m_wheel = 0
	local diff = self.val2 - self.val1 -- range size
	local K = 1 -- K = coefficient
	if Ctrl then K = 5 end
	if gfx.mouse_wheel > 0 then 
		self.val1 = math.min(self.val1 + self.step * K, self.max - diff)
		self.val2 = math.min(self.val2 + self.step * K, self.max)
		end
	if gfx.mouse_wheel < 0 then 
		self.val1 = math.max(self.val1 - self.step * K, self.min)
		self.val2 = math.max(self.val2 - self.step * K, self.min + diff)
		end
	return true
end
--------------------------------------------------------------------------------
function e.H_Rng_Slider:draw_body()
	local range_lx = self.rng_w / self.max * self.val1 -- x pos of left edge of range (abs)
	local range_rx = self.rng_w / self.max * self.val2 -- x pos of right edge of range (abs)
	gfx.rect(self.rng_x + range_lx, self.y, range_rx - range_lx, self.h, true)
end
--------------------------------------------------------------------------------
function e.H_Rng_Slider:draw_hnds()
	local range_lx = self.rng_w / self.max * self.val1 -- x pos of left edge of range (abs)  
	local range_rx = self.rng_w / self.max * self.val2 -- x pos of right edge of range (abs)  
	gfx.set(self.r, self.g, self.b, 0.9) -- handle body color
	gfx.rect(self.rng_x + range_lx - self.hnd_w, self.y, self.hnd_w, self.h, true) -- left
	gfx.rect(self.rng_x + range_rx, self.y, self.hnd_w, self.h, true) -- right  
	gfx.set(0, 0, 0, 1) -- handle frame color
	gfx.rect(self.rng_x + range_lx - self.hnd_w - 1, self.y - 1, self.hnd_w + 2, self.h + 2, false) -- left
	gfx.rect(self.rng_x + range_rx - 1, self.y - 1, self.hnd_w + 2, self.h + 2, false) -- right
end
--------------------------------------------------------------------------------
function e.H_Rng_Slider:draw_val()
	local val1 = string.format("%.0f", self.val1)
	local val2 = string.format("%.0f", self.val2)
	local val1_w, val1_h  = gfx.measurestr(val1)
	local val2_w, val2_h = gfx.measurestr(val2) 
	gfx.x = self.x + 5
	gfx.y = self.y + (self.h - val1_h) / 2
	gfx.drawstr(val1)  
	gfx.x = self.x + self.w - val2_w - 5
	gfx.y = self.y + (self.h - val2_h) / 2
	gfx.drawstr(val2)
end
--------------------------------------------------------------------------------
function e.H_Rng_Slider:draw_label()
	local labelWidth, labelHeight = gfx.measurestr(self.label)
	gfx.x = self.x + (self.w - labelWidth) / 2
	gfx.y = self.y + (self.h - labelHeight) / 2
	gfx.drawstr(self.label)
end
--------------------------------------------------------------------------------
function e.H_Rng_Slider:draw()
	if (self.tab & (1 << e.gActiveLayer)) == 0 and self.tab ~= 0 then return end 
	self:update_zoom() -- check and update if window resized
	local a  = self.a -- local alpha for highlighting the e.Element
	-- set additional range slider specific state
	self.hnd_w  = math.floor(self.w / 20)  -- handle width (pixels)
	self.rng_x = self.x + self.hnd_w       -- range start x_pos, w/o handle (screen)
	self.rng_w = self.w - (self.hnd_w * 2) -- range length, w/o handles (pixels)
	self.rng_e = self.rng_x + self.rng_w   -- range end_pos inc' 1 handle (screen)
	if self:mouseIN() then
		if self:set_vals_m_wheel() then 
			if self.onMove then self.onMove() end 
		end  
	end  
	if gfx.mouse_cap & 1 == 0 then self.LHnd_state, self.RHnd_state, self.rng_state = false, false, false end -- Reset Ls / Rs / range state
	if self:mouseIN_LHnd() or self:mouseIN_RHnd() then a = a + 0.1 end -- if in e.Element handles, increase opacity
	if self:mouseIN_Rng() then a = a + 0.2 end -- if in range, increase opacity 
	if self:mouseLDown_LHnd()  then self.LHnd_state = true end -- MouseLButton on left handle down
	if self:mouseLDown_RHnd()  then self.RHnd_state = true end -- MouseLButton on right handle down
	if self:mouseLDown_rng() then self.rng_state = true end -- MouseLButton in range down
	if self.LHnd_state == true then a = a + 0.2; self:set_val1() end -- if e.Element left handle clicked, increase opacity more
	if self.RHnd_state == true then a = a + 0.2; self:set_val2() end -- if e.Element right handle clicked, increase opacity more
	if self.rng_state  == true then a = a + 0.2; self:set_val_both() end -- if e.Element range clicked, increase opacity more
	if (self.LHnd_state or self.RHnd_state or self.rng_state) and self.onMove then self.onMove() end
	if self:mouseRClick() and self.onRClick then self.onRClick() end -- if mouseR clicked and released, execute onRClick()
	gfx.set(self.r, self.g, self.b, a)  -- set e.Element color
	self:draw_body()
	self:draw_frame()
	self:draw_hnds()
	gfx.set(table.unpack(self.font_rgba)) -- set label color
	gfx.setfont(1, self.font, self.font_sz) -- set label font
	self:draw_label()
	self:draw_val()
end
--------------------------------------------------------------------------------
-- Vertical Range Slider Class Methods
--------------------------------------------------------------------------------
function e.V_Rng_Slider:pointIN_THnd(p_x, p_y)
	local range_ty = self.rng_e - (self.rng_h / self.max * self.val2) -- y pos of upper edge of range (abs)
	return p_x >= self.x and p_x <= self.x + self.w and p_y >= range_ty - self.hnd_h and p_y <= range_ty
end
--------------------------------------------------------------------------------
function e.V_Rng_Slider:pointIN_BHnd(p_x, p_y)
	local range_by = self.rng_e - (self.rng_h / self.max * self.val1) -- y pos of lower edge of range (abs)
	return p_x >= self.x and p_x <= self.x + self.w and p_y >= range_by and p_y <= range_by + self.hnd_h
end
--------------------------------------------------------------------------------
function e.V_Rng_Slider:pointIN_Rng(p_x, p_y)
	local range_ty = self.rng_e - (self.rng_h / self.max * self.val2) -- y pos of upper edge of range (abs)  
	local range_by = self.rng_e - (self.rng_h / self.max * self.val1) -- y pos of lower edge of range (abs)
	return p_x >= self.x and p_x <= self.x + self.w and p_y >= range_ty and p_y <= range_by
end
--------------------------------------------------------------------------------
function e.V_Rng_Slider:mouseIN_THnd()
	return gfx.mouse_cap & 1 == 0 and self:pointIN_THnd(gfx.mouse_x, gfx.mouse_y)
end
--------------------------------------------------------------------------------
function e.V_Rng_Slider:mouseIN_BHnd()
	return gfx.mouse_cap & 1 == 0 and self:pointIN_BHnd(gfx.mouse_x, gfx.mouse_y)
end
--------------------------------------------------------------------------------
function e.V_Rng_Slider:mouseIN_Rng()
	return gfx.mouse_cap & 1 == 0 and self:pointIN_Rng(gfx.mouse_x, gfx.mouse_y)
end
--------------------------------------------------------------------------------
function e.V_Rng_Slider:mouseLDown_THnd()
	return gfx.mouse_cap & 1 == 1 and gLastMouseCap & 1 == 0 and self:pointIN_THnd(gMouseOX, gMouseOY)
end
--------------------------------------------------------------------------------
function e.V_Rng_Slider:mouseLDown_BHnd()
	return gfx.mouse_cap & 1 == 1 and gLastMouseCap & 1 == 0 and self:pointIN_BHnd(gMouseOX, gMouseOY)
end
--------------------------------------------------------------------------------
function e.V_Rng_Slider:mouseLDown_rng()
	return gfx.mouse_cap & 1 == 1 and gLastMouseCap & 1 == 0 and self:pointIN_Rng(gMouseOX, gMouseOY)
end
--------------------------------------------------------------------------------
function e.V_Rng_Slider:set_val1()
	local K = 1 -- K = coefficient
	if Ctrl then K = 5 end
	local val = self.val1 + ((gLastMouseY - gfx.mouse_y) / (self.rng_h * K) * self.max)
	if val < self.min then val = self.min elseif val > self.val2 then val = self.val2 end
	self.val1 = val
end
--------------------------------------------------------------------------------
function e.V_Rng_Slider:set_val2()
	local K = 1 -- K = coefficient
	if Ctrl then K = 5 end
	local val = self.val2 + ((gLastMouseY - gfx.mouse_y) / (self.rng_h * K) * self.max)
	if val < self.val1 then val = self.val1 elseif val > self.max then val = self.max end
	self.val2 = val
end
--------------------------------------------------------------------------------
function e.V_Rng_Slider:set_val_both()
	local diff = self.val2 - self.val1 -- range size
	local K = 1 -- K = coefficient
	if Ctrl then K = 5 end
	local val = self.val1 + (gLastMouseY - gfx.mouse_y) / (self.h * K) * self.max
	if val < self.min then val = self.min elseif val > self.max - diff then val = self.max - diff end
	self.val1 = val
	self.val2 = val + diff
end
--------------------------------------------------------------------------------
function e.V_Rng_Slider:set_vals_m_wheel()
	if gfx.mouse_wheel == 0 then return false end  -- return if m_wheel = 0
	local diff = self.val2 - self.val1 -- range size
	local K = 1 -- K = coefficient
	if Ctrl then K = 5 end
	if gfx.mouse_wheel > 0 then 
		self.val1 = math.min(self.val1 + self.step * K, self.max - diff)
		self.val2 = math.min(self.val2 + self.step * K, self.max)
		end
	if gfx.mouse_wheel < 0 then 
		self.val1 = math.max(self.val1 - self.step * K, self.min)
		self.val2 = math.max(self.val2 - self.step * K, self.min + diff)
		end
	return true
end
--------------------------------------------------------------------------------
function e.V_Rng_Slider:draw_body()
	local range_ty = self.rng_e - (self.rng_h / self.max * self.val2) -- y pos of upper edge of range (abs)  
	local range_by = self.rng_e - (self.rng_h / self.max * self.val1) -- y pos of lower edge of range (abs)
	gfx.rect(self.x, range_ty, self.w, range_by - range_ty, true)
end
--------------------------------------------------------------------------------
function e.V_Rng_Slider:draw_hnds()
	local range_ty = self.rng_e - (self.rng_h / self.max * self.val2) -- y pos of upper edge of range (abs)  
	local range_by = self.rng_e - (self.rng_h / self.max * self.val1) -- y pos of lower range (abs)
	gfx.set(self.r, self.g, self.b, 0.9) -- handle body color
	gfx.rect(self.x, range_ty - self.hnd_h, self.w, self.hnd_h, true) -- upper
	gfx.rect(self.x, range_by, self.w, self.hnd_h, true) -- lower 
	gfx.set(0, 0, 0, 1) -- handle frame colour
	gfx.rect(self.x - 1, range_ty - self.hnd_h - 1, self.w + 2, self.hnd_h + 2, false) -- upper
	gfx.rect(self.x - 1, range_by - 1 , self.w + 2, self.hnd_h + 2, false) -- lower
end
--------------------------------------------------------------------------------
function e.V_Rng_Slider:draw_val()
	local val1 = string.format("%.0f", self.val1)
	local val2 = string.format("%.0f", self.val2)
	local val1_w, val1_h  = gfx.measurestr(val1)
	local val2_w, val2_h = gfx.measurestr(val2)   
	gfx.x = self.x + (self.w - val2_w) / 2  
	gfx.y = self.y + 5
	gfx.drawstr(val2)  
	gfx.x = self.x + (self.w - val1_w) / 2
	gfx.y = self.y + self.h - val1_h - 5
	gfx.drawstr(val1)
end
--------------------------------------------------------------------------------
function e.V_Rng_Slider:draw_label()
	local labelWidth, labelHeight = gfx.measurestr(self.label)
	gfx.x = self.x + (self.w - labelWidth) / 2
	gfx.y = self.y + self.h + (labelHeight) / 3 * 2
	gfx.drawstr(self.label)
end
--------------------------------------------------------------------------------
function e.V_Rng_Slider:draw()
	if (self.tab & (1 << e.gActiveLayer)) == 0 and self.tab ~= 0 then return end 
	self:update_zoom() -- check and update if window resized
	local a  = self.a -- local alpha value for highlighting the e.Element
	-- set additional range slider specific state
	self.hnd_h = math.floor(self.h / 20)    -- handle height (pixels)
	self.rng_y = self.y + self.hnd_h        -- range start y_pos, w/o handle (screen)
	self.rng_h = self.h - (self.hnd_h * 2)  -- range length, w/o handles (pixels)
	self.rng_e = self.rng_y + self.rng_h    -- range end_pos w/o handle (screen)
	if self:mouseIN() then
		if self:set_vals_m_wheel() then 
			if self.onMove then self.onMove() end 
		end  
	end
	if gfx.mouse_cap & 1 == 0 then self.BHnd_state, self.THnd_state, self.rng_state = false, false, false end -- Reset Bs / Ts / Range states
	if self:mouseIN_THnd() or self:mouseIN_BHnd() then a = a + 0.1 end -- if in e.Element handles, increase opacity
	if self:mouseIN_Rng() then a = a + 0.2 end -- if in range, increase opacity 
	if self:mouseLDown_THnd() then self.THnd_state  = true end -- MouseLButton on upper handle down
	if self:mouseLDown_BHnd() then self.BHnd_state = true end -- MouseLButton on lower handle down
	if self:mouseLDown_rng() then self.rng_state = true end -- MouseLButton in range down
	if self.THnd_state == true then a = a + 0.2; self:set_val2() end -- if e.Element top handle clicked, increase opacity more
	if self.BHnd_state == true then a = a + 0.2; self:set_val1() end -- if e.Element top handle clicked, increase opacity more
	if self.rng_state  == true then a = a + 0.2; self:set_val_both() end -- if e.Element range clicked, increase opacity more
	if (self.THnd_state or self.BHnd_state or self.rng_state) and self.onMove then self.onMove() end
	if self:mouseRClick() and self.onRClick then self.onRClick() end -- if mouseR clicked and released, execute onRClick()
	gfx.set(self.r, self.g, self.b, a)  -- set color
	self:draw_body()
	self:draw_frame()
	self:draw_hnds()
	gfx.set(table.unpack(self.font_rgba)) -- set label color
	gfx.setfont(1, self.font, self.font_sz) -- set label font
	self:draw_label()
	self:draw_val()
end
--------------------------------------------------------------------------------
--  Textbox Class Methods
--------------------------------------------------------------------------------
function e.Textbox:draw_body()
	gfx.rect(self.x, self.y, self.w, self.h, true)
end
--------------------------------------------------------------------------------
function e.Textbox:draw_label()
	local labelWidth, labelHeight = gfx.measurestr(self.label)
	gfx.x = self.x + (self.w - labelWidth) / 2
	gfx.y = self.y + (self.h - labelHeight) / 2
	gfx.drawstr(self.label)
end
--------------------------------------------------------------------------------
function e.Textbox:draw()
	if (self.tab & (1 << e.gActiveLayer)) == 0 and self.tab ~= 0 then return end
	self:update_zoom() -- check and update if window resized
	-- in elm R_up (released and was previously pressed), run onRClick (user defined)
	if self:mouseRClick() and self.onRClick then self.onRClick() end
	gfx.set(self.r, self.g, self.b, self.a) -- set the drawing colour for the e.Element
	self:draw_body()
	self:draw_frame()
	gfx.set(table.unpack(self.font_rgba)) -- set label color
	gfx.setfont(1, self.font, self.font_sz) -- set label font
	self:draw_label()
end
--------------------------------------------------------------------------------
return e -- pass eGUI to calling script

--[[
Example e.Element declarations
local elem        = e.element:new(      {tabs}  x, y, w,   h,   colour,       "Label", Font,    Sz, font col,    val1,   val2,      min, max, step)
local frame01     = e.Frame:new(        {0},    x, y, w,   h,   e.col_grey4)
local textbox01		= e.Textbox:new(      {1},    x, y, w,   h,   e.col_grey5,  "Label", e.Arial, 16, e.col_grey7)
local button01    = e.Button:new(       {1},    x, y, w,   h,   e.col_grey6,  "Label", e.Arial, 16, e.col_grey8)
local toggle01    = e.Checkbox:new(     {1, 3}, x, y, w,   h,   e.col_orange, "",      e.Arial, 16, e.col_grey8, {1},       {"Option"})
local checkbox01  = e.Checkbox:new(     {1},    x, y, cbw, cbh, e.col_orange, "Label", e.Arial, 16, e.col_grey8, {0,0,1},   {"Opt1", "Opt2", "Opt3"})
local radbutton01 = e.Rad_Button:new(   {1},    x, y, rbw, rbh, e.col_yellow, "Label", e.Arial, 16, e.col_grey8, 1,         {"Opt1", "Opt2", "Opt3", "Opt4"})
local droplist01  = e.Droplist:new(     {1},    x, y, w,   h,   e.col_grey5,  "Label", e.Arial, 16, e.col_grey7, 1,         {"One", "Two", "Three", "Four"})
local knob01      = e.Knob:new(         {1, 3}, x, y, w,   h,   e.col_red,    "Label", e.Arial, 16, e.col_grey8, curr_val,  0,      min, max, step)
local hslider01   = e.Horz_Slider:new(  {1, 2}, x, y, w,   h,   e.col_blue,   "Label", e.Arial, 16, e.col_grey8, curr_val,  0,      min, max, step)
local vslider01   = e.Vert_Slider:new(  {1, 3}, x, y, w,   h,   e.col_blue,   "Label", e.Arial, 16, e.col_grey8, curr_val,  0,      min, max, step)
local hrslider01  = e.H_Rng_Slider:new( {1, 2}, x, y, w,   h,   e.col_blue,   "Label", e.Arial, 16, e.col_grey8, lo_val,    hi_val, min, max, step)
local vrslider01  = e.V_Rng_Slider:new( {1, 3}, x, y, w,   h,   e.col_blue,   "Label", e.Arial, 16, e.col_grey8, lo_val,    hi_val, min, max, step)

Elements can be displayed on multiple layers, defined in the 'tabs' table.  0 means all layers.

Checkbox and Radiobutton elements use 'w' and 'h' to define the width and height of each checkbox or radiobutton. 
The overall element height is derived from the total number of options multiplied by 'h', plus padding
The overall element width is derived from 'w' plus the length of the longest label string, plus padding
--]]

--[[
Example e.Element functions
button01.onLClick = function()
	reaper.ShowConsoleMsg("Button Example")
end 

droplist01.onLClick = function()
			if droplist01.val1 ==  1 then e.gScale = 0.7
	elseif droplist01.val1 ==  2 then e.gScale = 0.8
	elseif droplist01.val1 ==  3 then e.gScale = 0.9
	elseif droplist01.val1 ==  4 then e.gScale = 1  
	end
	-- Save state, close and reopen GFX window
	__,gWinX,gWinY,__,__ = gfx.dock(-1,0,0,0,0)
	gScaleState = true
	gfx.quit()
	InitGFX()
end
--]]
