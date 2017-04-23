--[[
@description eGUI Example & Template
@about
 #### eGUI Example
 Basic demo of eGUI boilerplate and layout code
 #### Features
 - layers
 - dropdown lists
 - buttons
 - knobs
 - sliders (horizontal, vertical, horiz_range, vert_range)
 - textboxes
 - frames
 - checkboxes
 - radio buttons
@link Reaper http://reaper.fm
@noindex
@version 1.0
@author RobU
Reaper 5.x
Extensions: None
Licenced under the GPL v3
--]]
--------------------------------------------------------------------------------
-- REQUIRES
--------------------------------------------------------------------------------
package.path = debug.getinfo(1,"S").source:match[[^@?(.*[\/])[^\/]-$]] .."?.lua;".. package.path
local e = require "eGUI"
--------------------------------------------------------------------------------
-- Global window state variables 
--------------------------------------------------------------------------------
gWinX, gWinY, gWinW, gWinH = 25, 25, 410, 470

--------------------------------------------------------------------------------
-- eGUI - LAYOUT START
--------------------------------------------------------------------------------
-- Example Elements
-- Info page text
local infoStr = 
[[eGui - A fork of Eugen27771's Lua GUI template
 * Example usage script
 * Refactoring of original code
 * Added Vertical Range Slider widget
 * Added Textbox widget
 * Added polar coordinate support to Knob widgets
 * Added Min/Max/Step attributes to all widgets
 * Added mousewheel support to range sliders
 * Added Layers
 * Removed dynamic zoom-by-drag
 * Added symetrical fixed-step zoom (eg 80%, 90%, 100%..)
 * Radio Button and Checkbox init and drawing code rewrite
 * Improved general readability (variable naming, etc.)]]
-- local elm 01   = Element:new(tab, x, y, w, h,   r, g, b, a,   label, font, f_sz, f_rgba,   val1, val2, min, max, step)
-- persistent gui elements
local winFrame    = e.Frame:new({0}, 5, 5, gWinW - 10, gWinH - 10, e.col_grey4)
local zoomDrop		= e.Droplist:new({0}, 5, 5, 40, 22, e.col_grey5, "", e.Arial, 16, e.col_grey7, 4, {"70%", "80%", "90%", "100%", "110%", "120%", "140%", "160%", "180%", "200%"})
local winTitle		= e.Textbox:new({0}, 45, 5, gWinW - 50, 22, e.col_grey5, "eGUI Example    ", e.Arial, 16, e.col_grey7)
local winLayer1   = e.Button:new({0}, 5,   gWinH - 25, 100, 20, e.col_grey6, "Layer 1", e.Arial, 16, e.col_grey8)
local winLayer2   = e.Button:new({0}, 105, gWinH - 25, 100, 20, e.col_grey5, "Layer 2", e.Arial, 16, e.col_grey7)
local winLayer3   = e.Button:new({0}, 205, gWinH - 25, 100, 20, e.col_grey5, "Layer 3", e.Arial, 16, e.col_grey7)
local infoLayer   = e.Button:new({0}, 305, gWinH - 25, 100, 20, e.col_grey5, "Info", e.Arial, 16, e.col_grey7)
local optText     = e.Textbox:new({4}, 10, 33, gWinW - 20, gWinH - 66, e.col_grey5, infoStr, e.Arial, 16, e.col_grey7)
-- everything else...
local gridRad     = e.Rad_Button:new({1}, 15, 50, 30, 30, e.col_yellow, "Grid Size", e.Arial, 16, e.col_grey8, 1, {"1/1", "1/2", "1/4", "1/8", "1/16"})
local toggle01    = e.Checkbox:new({1, 3}, 300, 50, 30, 30, e.col_orange, "Toggle", e.Arial, 16, e.col_grey8, {1},{"Pause"})
local knob01      = e.Knob:new({1, 3}, 300, 120, 45, 45, e.col_red, "Knobs Go", e.Arial, 16, e.col_grey8, 4, 0, 0, 11, 1)
local knob02      = e.Knob:new({1, 3}, 300, 200, 45, 45, e.col_red, "To Eleven", e.Arial, 16, e.col_grey8, 7, 0, 0, 11, 1)
local numDrop			= e.Droplist:new({1, 2, 3}, 15, 270, 100, 25, e.col_blue, "Repeat", e.Arial, 16, e.col_grey8, 1, {"One", "Two", "Three"})
local clickBtn    = e.Button:new({1, 2, 3}, 15, 320, 100, 25,  e.col_green, "Click Me", e.Arial, 16, e.col_grey8)
local panicBtn    = e.Button:new({1, 2, 3}, 15, 370, 100, 25,  e.col_red, "PANIC !", e.Arial, 16, e.col_grey8)
local vslider01   = e.Vert_Slider:new({1, 3}, 150, 50, 30, 150, e.col_blue, "Prob %", e.Arial, 16, e.col_grey8, 50, 0, 0, 100, 1)
local vrslider01  = e.V_Rng_Slider:new({1, 3}, 200, 50, 30, 150, e.col_blue, "Accent", e.Arial, 16, e.col_grey8, 0, 27, 0, 127, 1)
local hslider01   = e.Horz_Slider:new({1, 2}, 200, 370, 150, 30, e.col_blue, "Mojo", e.Arial, 16, e.col_grey8, 3, 0, 0, 20, 1)
local hrslider01  = e.H_Rng_Slider:new({1, 2}, 200, 320, 150, 30, e.col_blue, "Mojo Range", e.Arial, 16, e.col_grey8, 100, 127, 0, 127, 1)
local checkbox01  = e.Checkbox:new({2}, 15, 55, 30, 30, e.col_orange, "Checkbox", e.Arial, 16, e.col_grey8, {0,0,1,1,0},{"Sequence", "Transpose", "Randomise", "Shaken", "Stir"})

-- Element Tables
local t_Buttons       = {winLayer1, winLayer2, winLayer3, infoLayer, clickBtn, panicBtn}
local t_Checkboxes    = {checkbox01}
local t_Toggles       = {toggle01}
local t_Droplists     = {zoomDrop, numDrop}
local t_Frames        = {winFrame}
local t_Knobs         = {knob01, knob02}
local t_Rad_Buttons   = {gridRad}
local t_HRng_Sliders  = {hrslider01}
local t_VRng_Sliders	=	{vrslider01}
local t_Horz_Sliders  = {hslider01}
local t_Vert_Sliders  = {vslider01}
local t_Textboxes     = {winTitle, optText}

-- eGUI Element Functions Start
clickBtn.onLClick = function()
reaper.ShowConsoleMsg("Nothing to see here, move along")
end 

panicBtn.onLClick = function()
reaper.ShowConsoleMsg("Panic Averted !")
end 

winLayer1.onLClick = function()
  e.gActiveLayer = 1 
  winLayer1.font_rgba = e.col_grey8 -- highlight layer 1
  winLayer1.r, winLayer1.g, winLayer1.b, winLayer1.a = table.unpack(e.col_grey6)
  winLayer2.font_rgba = e.col_grey7
  winLayer2.r, winLayer2.g, winLayer2.b, winLayer2.a = table.unpack(e.col_grey5)
  winLayer3.font_rgba = e.col_grey7
  winLayer3.r, winLayer3.g, winLayer3.b, winLayer3.a = table.unpack(e.col_grey5)
  infoLayer.font_rgba = e.col_grey7
  infoLayer.r, infoLayer.g, infoLayer.b, infoLayer.a = table.unpack(e.col_grey5)
end

winLayer2.onLClick = function()
  e.gActiveLayer = 2
  winLayer1.font_rgba = e.col_grey7
  winLayer1.r, winLayer1.g, winLayer1.b, winLayer1.a = table.unpack(e.col_grey5)
  winLayer2.font_rgba = e.col_grey8 -- highlight layer 2
  winLayer2.r, winLayer2.g, winLayer2.b, winLayer2.a = table.unpack(e.col_grey6)
  winLayer3.font_rgba = e.col_grey7
  winLayer3.r, winLayer3.g, winLayer3.b, winLayer3.a = table.unpack(e.col_grey5)
  infoLayer.font_rgba = e.col_grey7
  infoLayer.r, infoLayer.g, infoLayer.b, infoLayer.a  = table.unpack(e.col_grey5)
end

winLayer3.onLClick = function()
  e.gActiveLayer = 3
  winLayer1.font_rgba = e.col_grey7
  winLayer1.r, winLayer1.g, winLayer1.b, winLayer1.a = table.unpack(e.col_grey5)
  winLayer2.font_rgba = e.col_grey7
  winLayer2.r, winLayer2.g, winLayer2.b, winLayer2.a = table.unpack(e.col_grey5)
  winLayer3.font_rgba = e.col_grey8 -- highlight layer 3
  winLayer3.r, winLayer3.g, winLayer3.b, winLayer3.a = table.unpack(e.col_grey6)
  infoLayer.font_rgba = e.col_grey7
  infoLayer.r, infoLayer.g, infoLayer.b, infoLayer.a = table.unpack(e.col_grey5)
end

infoLayer.onLClick = function()
  e.gActiveLayer = 4
  winLayer1.font_rgba = e.col_grey7
  winLayer1.r, winLayer1.g, winLayer1.b, winLayer1.a = table.unpack(e.col_grey5)
  winLayer2.font_rgba = e.col_grey7
  winLayer2.r, winLayer2.g, winLayer2.b, winLayer2.a = table.unpack(e.col_grey5)
  winLayer3.font_rgba = e.col_grey7
  winLayer3.r, winLayer3.g, winLayer3.b, winLayer3.a = table.unpack(e.col_grey5)
  infoLayer.font_rgba = e.col_grey8 -- highlight layer 4
  infoLayer.r, infoLayer.g, infoLayer.b, infoLayer.a = table.unpack(e.col_grey6)
end

zoomDrop.onLClick = function()
	-- Window scaling 
	    if zoomDrop.val1 ==  1 then e.gScale = 0.7
  elseif zoomDrop.val1 ==  2 then e.gScale = 0.8
  elseif zoomDrop.val1 ==  3 then e.gScale = 0.9
  elseif zoomDrop.val1 ==  4 then e.gScale = 1  
  elseif zoomDrop.val1 ==  5 then e.gScale = 1.1
  elseif zoomDrop.val1 ==  6 then e.gScale = 1.2
  elseif zoomDrop.val1 ==  7 then e.gScale = 1.4
  elseif zoomDrop.val1 ==  8 then e.gScale = 1.6
  elseif zoomDrop.val1 ==  9 then e.gScale = 1.8
  elseif zoomDrop.val1 == 10 then e.gScale = 2.0
  end
	-- Save state, close and reopen GFX window
	__,gWinX,gWinY,__,__ = gfx.dock(-1,0,0,0,0)
	e.gScaleState = true
  gfx.quit()
  InitGFX()
end

-- eGUI Element Functions END
--------------------------------------------------------------------------------
-- eGUI LAYOUT END
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- eGUI - Main DRAW function
--------------------------------------------------------------------------------
function DrawGUI()
  for k, button		in pairs(t_Buttons)			  do button:draw()		end
	for k, check 	  in pairs(t_Checkboxes)		do check:draw()			end  
  for k, toggle   in pairs(t_Toggles)       do toggle:draw()  	end  
  for k, drop		  in pairs(t_Droplists)		  do drop:draw()			end   
  for k, frame		in pairs(t_Frames)			  do frame:draw()			end 
  for k, knob			in pairs(t_Knobs)				  do knob:draw()	  	end   
  for k, radio	  in pairs(t_Rad_Buttons)	  do radio:draw()	  	end	
  for k, hrslider	in pairs(t_HRng_Sliders) 	do hrslider:draw()	end
 	for k, vrslider in pairs(t_VRng_Sliders) 	do vrslider:draw()	end
  for k, hslider  in pairs(t_Horz_Sliders)  do hslider:draw()		end
  for k, vslider  in pairs(t_Vert_Sliders)  do vslider:draw()		end
	for k, textbox  in pairs(t_Textboxes)     do textbox:draw()		end
end

--------------------------------------------------------------------------------
-- InitGFX
--------------------------------------------------------------------------------
function InitGFX()
  -- Window set up
  gWinBgd = 0, 0, 0
	gWinTitle = "eGUI Example"
  gWinDockState = 0
  -- Init window
  gfx.clear = gWinBgd         
  gfx.init(gWinTitle, gWinW * e.gScale, gWinH * e.gScale, gWinDockState, gWinX, gWinY )
  -- Last mouse position and state
  gLastMouseCap, gLastMouseX, gLastMouseY = 0, 0, 0
  gMouseOX, gMouseOY = -1, -1
end
--------------------------------------------------------------------------------
-- Mainloop
--------------------------------------------------------------------------------
function mainloop()
	-- Update mouse state and position
  if gfx.mouse_cap & 1 == 1   and gLastMouseCap & 1 == 0  or		-- L mouse
		 gfx.mouse_cap & 2 == 2   and gLastMouseCap & 2 == 0  or		-- R mouse
		 gfx.mouse_cap & 64 == 64 and gLastMouseCap & 64 == 0 then	-- M mouse
		 gMouseOX, gMouseOY = gfx.mouse_x, gfx.mouse_y 
  end
	-- Set modifier keys
	Ctrl  = gfx.mouse_cap & 4 == 4
  Shift = gfx.mouse_cap & 8 == 8
  Alt   = gfx.mouse_cap & 16 == 16
	-- Update and draw eGUI
	DrawGUI()
	-- Save last mouse state
	gLastMouseCap = gfx.mouse_cap
  gLastMouseX, gLastMouseY = gfx.mouse_x, gfx.mouse_y
  gfx.mouse_wheel = 0 -- reset gfx.mouse_wheel
  -- Set passthrough keys for play/stop
  char = gfx.getchar()
  if char == 32 then reaper.Main_OnCommand(40044, 0) end
  -- Defer 'mainloop' if not explicitly quiting (esc)
  if char ~= -1 and char ~= 27 then reaper.defer(mainloop) end
  -- Update Reaper GFX
	gfx.update()
	e.gScaleState = true
end
--------------------------------------------------------------------------------
-- RUN
--------------------------------------------------------------------------------
InitGFX()
mainloop()
