--[[
@description MIDI Ex Machina - Note Randomizer and Sequencer
@about
	#### MIDI Ex Machina
	A scale-oriented, probability based composition tool
 
	#### Features
	note randomizer
	- selectable root note, octave, scale
	- note probability sliders
	- randomize all or selected notes
	- octave doubler, with probability slider 
	- force first note to root note option 
	- permute selected notes
 
	monophonic random sequence generator
	- note length probability sliders
	- grid size control
	- velocity accent level, and probabilty slider
	- legato probability slider
	- various generation options
 
	euclidean sequence generator
	- grid size control
	- set pulses, steps, and rotation
	- velocity accent level and probability slider
	- various generation options
@donation https://www.paypal.me/RobUrquhart
@link Reaper http://reaper.fm
@link Forum Thread http://reaper.fm
@version 1.2.1
@author RobU
@changelog
	v1.2.1
	added monophonic sequence generator
	added euclidean sequence generator (bjorklund)
	added permute option in note randomizer
	added octave multiplier in note randomizer
@provides
	[main=midi_editor] .
	[nomain] eGUI.lua
	[nomain] euclid.lua
	[nomain] persistence.lua

Reaper 5.x
Extensions: None
Licenced under the GPL v3
--]]
--------------------------------------------------------------------------------
-- REQUIRES
--------------------------------------------------------------------------------
package.path = debug.getinfo(1,"S").source:match[[^@?(.*[\/])[^\/]-$]] .."?.lua;".. package.path
e = require 'eGUI'
b = require 'euclid'
p = require 'persistence' -- currently unused, i.e. no save, load, nada...
-- ToDo save, load, etc...

--------------------------------------------------------------------------------
-- GLOBAL VARIABLES START
--------------------------------------------------------------------------------
m = {} -- all ex machina data
-- user changable options marked with "(option)"
m.debug = false
m.msgTimer = 30
-- window
m.win_title = "RobU : MIDI Ex Machina - v1.2.1"; m.win_dockstate = 0
m.win_x = 10; m.win_y = 10; m.win_w = 900; m.win_h = 300 -- window dimensions
m.win_bg = {0, 0, 0} -- background colour
m.def_zoom = 4 -- 100% (option)
-- zoom values are 1=70, 2=80, 3=90, 4=100, 5=110%, 6=120, 7=140, 8=160, 9=180, 10=200

-- default octave, key, and root (root = octave + key)
-- due to some quirk, oct 4 is really oct 3...
m.oct = 4; m.key = 1; m.root = 0 -- (options, except m.root)

-- midi editor, take, grid
m.activeEditor, m.activeTake = nil, nil
m.ppqn = 960; -- default ppqn, no idea how to check if this has been changed.. 
m.reaGrid = 0

-- note randomizer flags - user set start up options
m.rndAllNotesF = false -- all notes or only selected notes (option)
m.rndOctX2F = false -- enable double scale randomisation (option)
m.rndFirstNoteF = false; -- first note is always root (option)
m.rndPermuteF = false; m.pHash = 0 -- midi item changes

-- sequencer flags - user set start up options
m.seqF = true -- generate sequence (option)
m.seqFirstNoteF = true -- first note always (option)
m.seqAccentF = true -- generate accents (option)
m.seqLegatoF = false -- use legato (option)
m.seqRndNotesF = true -- randomise notes (option) 
m.seqRepeatF = false -- repeat sequence by grid length (option - not implemented yet)
m.legato = -10 -- default legatolessness value
m.repeatStart, m.repeatEnd, m.repeatLength, m.repeatTimes = 0, 0, 0, 0 -- repeat values

-- euclid flags - user set start up options
m.eucF = true	-- generate euclid (option)
m.eucAccentF = false	-- generate accents (option)
m.eucRndNotesF = false	-- randomize notes (option)

-- note buffers and current buffer index
m.notebuf = {}; m.notebuf.i = 0; m.notebuf.max = 0

m.dupes = {} -- for duplicate note detection while randomizing
m.euclid = {} -- for pattern generation

m.notes = {'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B', 'C'}
m.scales = {
	{0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, name = "Chromatic"},
	{0, 2, 4, 5, 7, 9, 11, 12, name = "Ionian / Major"},
	{0, 2, 3, 5, 6, 9, 10, 12, name = "Dorian"},
	{0, 1, 3, 5, 7, 8, 10, 12, name = "Phrygian"},
	{0, 2, 4, 6, 7, 9, 11, 12, name = "Lyndian"},
	{0, 2, 4, 5, 7, 9, 10, 12, name = "Mixolydian"},
	{0, 2, 3, 5, 7, 8, 10, 12, name = "Aeolian / Minor"},
	{0, 1, 3, 5, 6, 8, 10, 12, name = "Locrian"},
	{0, 3, 5, 6, 7, 10, 12,name = "Blues"},
	{0, 2, 4, 7, 9, 12,name = "Pentatonic Major"},
	{0, 3, 5, 7, 10, 12,name = "Pentatonic Minor"},
	{name = "Permute"}
}  
-- a list of scales available to the mangling engine, more can be added manually if required
-- each value is the interval step from the root note of the scale (0) including the octave (12)

-- textual list of the available scale names for the GUI list selector
m.scalelist = {}
m.curScaleName = "Chromatic" -- (option) !must be a valid scale name!

-- various probability tables
m.preNoteProbTable = {};  m.noteProbTable = {}
m.preSeqProbTable = {};   m.seqProbTable  = {}
m.accProbTable = {};      m.octProbTable  = {}
m.legProbTable = {}

dstr, lstr = "", "" -- debug strings for GfxCon function
--------------------------------------------------------------------------------
-- GLOBAL VARIABLES END
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Utility Functions Start
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Wrap(n, max) -return n wrapped between 'n' and 'max'
--------------------------------------------------------------------------------
local function Wrap (n, max)
	n = n % max
	if (n < 1) then
		n = n + max
	end
	return n
end
--------------------------------------------------------------------------------
-- RGB2Dec(r, g, b) - takes 8 bit r, g, b values, returns decimal (0 to 1)
--------------------------------------------------------------------------------
function RGB2Dec(r, g, b)
	if r < 0 or r > 255 then r = wrap(r, 255) end
	if g < 0 or g > 255 then g = wrap(g, 255) end
	if b < 0 or b > 255 then b = wrap(b, 255) end
	return r/255, g/255, b/255
end
--------------------------------------------------------------------------------
-- RGB2Packed(r, g, b) - returns a packed rgb value
--------------------------------------------------------------------------------
local function RGB2Packed(r, g, b)
	local floor = math.floor
		g = (g << 8)
		b = (b << 16)
	return floor(r + g + b)
end
--------------------------------------------------------------------------------
-- ConMsg(str) - outputs 'str' to the Reaper console
--------------------------------------------------------------------------------
local function ConMsg(str)
	reaper.ShowConsoleMsg(str .."\n")
end
--------------------------------------------------------------------------------
-- GfxConMsg() - prints str & mouse pos at xpos, ypos
--------------------------------------------------------------------------------
local function GfxCon(xpos, ypos, str)
	local floor = math.floor
	local fstr = ""
	local padx, pady = 20, 20
	local mx, my = 0, 0
	gfx.set(RGB2Dec(200, 200, 200))
	gfx.setfont(1, "Arial", 14)	-- 9 is the debug font
	--mx = floor(gfx.mouse_x); my = floor(gfx.mouse_y) -- get the mouse pos
	--fstr = fstr .. "\nm_x = " .. tostring(x) .. " m_y = " .. tostring(y)
	fstr = fstr .. "\n" .. str
	local strw, strh = gfx.measurestr(fstr)	-- measure it...
	gfx.x = xpos + m.win_w - strw	- padx -- set the print position, with padding
	gfx.y = ypos + pady	-- set the print position, with padding
	gfx.drawstr(fstr)
end
--------------------------------------------------------------------------------
-- Utility Functions End
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Ex Machina Functions Start
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- ClearTable(t) - set all items in 2D table 't' to nil
--------------------------------------------------------------------------------
function ClearTable(t)
	local debug = false
	if debug or m.debug then ConMsg("ClearTable()") end
	for k, v in pairs(t) do
		t[k] = nil
	end
end
--------------------------------------------------------------------------------
-- CopyTable(t1, t2) - copies note data from t1 to t2
--------------------------------------------------------------------------------
function CopyTable(t1, t2)
	ClearTable(t2)
	local i = 1
	while t1[i] do
		local j = 1
		t2[i] = {}		
		while (t1[i][j] ~= nil)   do
			t2[i][j] = t1[i][j]
			j = j + 1
		end	--while (t1[i][j]
		i = i + 1
	end -- while t1[i]
end
--------------------------------------------------------------------------------
-- NewNoteBuf() - add a new note buffer to the table, returns handle
--------------------------------------------------------------------------------
local function NewNoteBuf()
	local debug = false
	if debug or m.debug then ConMsg("NewNoteBuf()") end
	m.notebuf.i = m.notebuf.i + 1
	m.notebuf.max = m.notebuf.max + 1
	m.notebuf[m.notebuf.i] = {}
	if debug or m.debug then
		str = "created buffer\n"
		str = str .. "buffer index = " .. tostring(m.notebuf.i) .. "\n"
		ConMsg(str)
	end
	return m.notebuf[m.notebuf.i]
end
--------------------------------------------------------------------------------
-- GetNoteBuf() - returns handle to the current note buffer
--------------------------------------------------------------------------------
local function GetNoteBuf()
	local debug = false
	if debug or m.debug then ConMsg("GetNoteBuf()") end
	if m.notebuf.i >= 1 then
		if debug or m.debug then
			str = "retrieved buffer\n"
			str = str .. "buffer index = " .. tostring(m.notebuf.i) .. "\n"
			ConMsg(str)
		end
		return m.notebuf[m.notebuf.i]
	end
end	
--------------------------------------------------------------------------------
-- UndoNoteBuf() - points to previous note buffer
--------------------------------------------------------------------------------
local function UndoNoteBuf()
	local debug = false
	if debug or m.debug then ConMsg("UndoNoteBuf()") end
	if m.notebuf.i > 1 then
		--table.remove(m.notebuf[m.notebuf.i])
		--m.notebuf[m.notebuf.i] = nil
		m.notebuf.i = m.notebuf.i -1
		if debug or m.debug then
			str = "removed buffer " .. tostring(m.notebuf.i + 1) .. "\n"
			str = str .. "buffer index = " .. tostring(m.notebuf.i) .. "\n"
			ConMsg(str)
		end
	else
		if debug or m.debug then
			str = "nothing to undo...\n"
			str = str .. "buffer index = " .. tostring(m.notebuf.i) .. "\n"
			ConMsg(str)
		end
	end
end
--------------------------------------------------------------------------------
-- PurgeNoteBuf() - purge all note buffers from current+1 to end
--------------------------------------------------------------------------------
local function PurgeNoteBuf()
	local debug = false
	if debug or m.debug then ConMsg("PurgeNoteBuf()") end
	if debug or m.debug then ConMsg("current idx = " .. tostring(m.notebuf.i)) end
	if debug or m.debug then ConMsg("max idx     = " .. tostring(m.notebuf.max)) end
	while m.notebuf.max > m.notebuf.i do
		m.notebuf[m.notebuf.max] = nil
		if debug or m.debug then ConMsg("purging buffer " .. tostring(m.notebuf.max))
		end
		m.notebuf.max = m.notebuf.max - 1
	end  
end
--------------------------------------------------------------------------------
-- GetItemLength(t) - get length of take 't', set various global vars
-- currently it only returns the item length (used in Sequencer and Bjorklund)
--------------------------------------------------------------------------------
function GetItemLength()
	local debug = false
	mItem = reaper.GetSelectedMediaItem(0, 0)
	mItemLen = reaper.GetMediaItemInfo_Value(mItem, "D_LENGTH")
	mBPM, mBPI = reaper.GetProjectTimeSignature2(0)
	msPerMin = 60000
	msPerQN = msPerMin / mBPM
	numQNPerItem = (mItemLen * 1000) / msPerQN
	numBarsPerItem = numQNPerItem / 4
	ItemPPQN = numQNPerItem * m.ppqn
	if debug then
		ConMsg("ItemLen (ms)    = " .. mItemLen)
		ConMsg("mBPM            = " .. mBPM)
		ConMsg("MS Per QN       = " .. msPerQN)
		ConMsg("Num of QN       = " .. numQNPerItem)
		ConMsg("Num of Bar      = " .. numBarsPerItem)
		ConMsg("Item size ppqn  = " .. ItemPPQN .. "\n")
	end
	if debug or m.debug then ConMsg("GetItemLength() = " .. tostring(ItemPPQN)) end
	return ItemPPQN
end
--------------------------------------------------------------------------------
-- GetReaperGrid() - get the current grid size, set global var m.reaGrid
--------------------------------------------------------------------------------
function GetReaperGrid(gridRad)
	local debug = false
	if debug or m.debug then ConMsg("GetReaperGrid()") end
	if m.activeTake then
		m.reaGrid, __, __ = reaper.MIDI_GetGrid(m.activeTake) -- returns quarter notes
		if gridRad then -- else, if a grid object was passed, update it
		--if m.reaGrid <= 0.17 then gridRad.val1 = 1 -- 1/16t
			if m.reaGrid == 0.25 then gridRad.val1 = 1 -- 1/16
		--elseif m.reaGrid == 0.25 then gridRad.val1 = 2 -- 1/16
		--elseif m.reaGrid == 0.33 then gridRad.val1 = 3 -- 1/8t
			elseif m.reaGrid == 0.5 then gridRad.val1 = 2 -- 1/8
		--elseif m.reaGrid == 0.67 then gridRad.val1 = 5 -- 1/4t
			elseif m.reaGrid == 1 then gridRad.val1 = 3 -- 1/4
			end -- m.reaGrid
		end
	else 
		if debug or m.debug then ConMsg("No Active Take\n") end
	end -- m.activeTake
end
--------------------------------------------------------------------------------
-- GetPermuteScaleFromTake(t) - fill a scale buffer 't' from the active take
--------------------------------------------------------------------------------
function GetPermuteScaleFromTake(t)
	local debug = false
	if debug or m.debug then ConMsg("GetPermuteScaleFromTake()") end
	local i, j = 1, 0
	if m.activeTake then
		local __, num_notes, num_cc, num_sysex = reaper.MIDI_CountEvts(m.activeTake)
		if num_notes > 0 then
			ClearTable(t)
			for i = 1, num_notes do
				__, selected, __, __, __, __, pitch, __ = reaper.MIDI_GetNote(m.activeTake, i-1)
				if selected == true then
					j = j + 1   
					t[j] = pitch - m.root
				end
			end -- for i		    
		end --if num_notes
	else
		if debug or m.debug then ConMsg("No Active Take")	end
	end -- m.activeTake	
end
--------------------------------------------------------------------------------
-- GetNotesFromTake(t) - fill a note buffer from the active take
--------------------------------------------------------------------------------
function GetNotesFromTake()
	local debug = false
	if debug or m.debug then ConMsg("GetNotesFromTake()") end
	local i, t
	if m.activeTake then
		local _retval, num_notes, num_cc, num_sysex = reaper.MIDI_CountEvts(m.activeTake)
		if num_notes > 0 then 
			t = GetNoteBuf(); if t == nil then t = NewNoteBuf() end
			ClearTable(t)
			for i = 1, num_notes do
				_retval, selected, muted, startppq, endppq, channel, pitch, velocity = reaper.MIDI_GetNote(m.activeTake, i-1)
				t[i] = {}
				t[i][1] = selected
				t[i][2] = muted
				t[i][3] = startppq
				t[i][4] = endppq
				t[i][5] = endppq-startppq
				t[i][6] = channel
				t[i][7] = pitch
				t[i][8] = velocity
			end -- for i				
		end -- num_notes
	else -- no active take
		if debug or m.debug then ConMsg("No Active Take") end
	end -- m.activeTake
end
--------------------------------------------------------------------------------
-- DeleteNotes() - delete all notes from the active take
--------------------------------------------------------------------------------
function DeleteNotes()
	local debug = false
	if debug or m.debug then ConMsg("DeleteNotes()") end
	local i, num_notes = 0, 0
	if m.activeTake then
		__, num_notes, __, __ = reaper.MIDI_CountEvts(m.activeTake)
		for i = 0, num_notes do
			reaper.MIDI_DeleteNote(m.activeTake, 0)
		end --for
	else
		if debug or m.debug then ConMsg("No Active Take") end
	end --m.activeTake	
end
--------------------------------------------------------------------------------
-- SetRootNote(octave, key) - returns new root midi note
--------------------------------------------------------------------------------
function SetRootNote(octave, key)
	local debug = false
	local o  = octave * 12
	local k = key - 1
	if debug or m.debug then ConMsg("SetRootNote() - Note = " .. tostring(o + k)) end
	return o + k
end
--------------------------------------------------------------------------------
-- GenProbTable(preProbTable, slidersTable, probTable)
-- creates an event probability table using values from sliders
--------------------------------------------------------------------------------
function GenProbTable(preProbTable, sliderTable, probTable)
	local debug = false
	if debug or m.debug then ConMsg("GenProbTable()") end
	local i, j, k, l = 1, 1, 1, 1
	local floor = math.floor
	ClearTable(probTable)
	for i, v in ipairs(preProbTable) do
		if sliderTable[j].val1 > 0 then
			for l = 1, (sliderTable[j].val1) do
			probTable[k] = preProbTable[i]
			k = k + 1
			end -- for l
		end -- if sliderTable[j]
		j = j + 1
	end
end
--------------------------------------------------------------------------------
-- GenAccentTable(probTable, velSlider, probSlider)
-- creates an event probability table using values from sliders
--------------------------------------------------------------------------------
function GenAccentTable(probTable, velSlider, probSlider)
	local debug = false
	if debug or m.debug then ConMsg("GenAccentTable()") end
	local i, j = 1, 1
	ClearTable(probTable)
	-- insert normal velocity
	for i = 1, (probSlider.max - probSlider.val1) do
		probTable[j] = math.floor(velSlider.val1)
		j = j + 1
	end
	-- insert the accented velocity
	for i = 1, (probSlider.val1) do
		probTable[j] = math.floor(velSlider.val2)
		j = j + 1
	end
end
--------------------------------------------------------------------------------
-- GenLegatoTable(probTable, velSlider, probSlider)
-- creates an event probability table using values from sliders
--------------------------------------------------------------------------------
function GenLegatoTable(probTable, probSlider)
	local debug = false
	if debug or m.debug then ConMsg("GenLegatoTable()") end
	local i, j = 1, 1
	ClearTable(probTable)
	-- no legato
	for i = 1, (probSlider.max - probSlider.val1) do
		probTable[j] = m.legato
		j = j + 1
	end
	-- legato
	for i = 1, (probSlider.val1) do
		probTable[j] = 0
		j = j + 1
	end
end
--------------------------------------------------------------------------------
-- GenOctaveTable(probTable, velSlider, probSlider)
-- creates an event probability table using values from sliders
--------------------------------------------------------------------------------
function GenOctaveTable(probTable, probSlider)
	local debug = false
	if debug or m.debug then ConMsg("GenOctaveTable()") end
	local i, j = 1, 1
	ClearTable(probTable)
	-- single octave
	for i = 1, (probSlider.max - probSlider.val1) do
		probTable[j] = 0
		j = j + 1
	end
	-- double octave
	for i = 1, (probSlider.val1) do
		probTable[j] = 12
		j = j + 1
	end
end
--------------------------------------------------------------------------------
-- SetScale() 
-- copies a scale from allScales to scale, key = scaleName
--------------------------------------------------------------------------------
function SetScale(scaleName, allScales, scale)
	local debug = false
	if debug or m.debug then ConMsg("SetScale() = " .. scaleName) end
	ClearTable(scale)
	for i = 1, #allScales, 1 do
		if scaleName == allScales[i].name then
			if scaleName == "Permute" then 
				m.rndPermuteF = true 
				GetPermuteScaleFromTake(scale)
			else
				m.rndPermuteF = false
			end
			for k, v in pairs(allScales[i]) do
				scale[k] = v
			end
			break
		end
	end
end
--------------------------------------------------------------------------------
-- SetSeqGridSizes()  
--------------------------------------------------------------------------------
function SetSeqGridSizes(sliderTable)
	local debug = false
	if debug or m.debug then ConMsg("SetSeqGridSizes()") end
	for k, v in pairs(sliderTable) do
		--if sliderTable[k].label == "1/16t" then m.preSeqProbTable[k] = 0.167 
		if sliderTable[k].label == "1/16" then m.preSeqProbTable[k] = 0.25
		--elseif sliderTable[k].label == "1/8t" then m.preSeqProbTable[k] = 0.333
		elseif sliderTable[k].label == "1/8" then m.preSeqProbTable[k] = 0.5
		--elseif sliderTable[k].label == "1/4t" then m.preSeqProbTable[k] = 0.667
		elseif sliderTable[k].label == "1/4" then m.preSeqProbTable[k] = 1.0
		elseif sliderTable[k].label == "Rest" then m.preSeqProbTable[k] = -1.0
		end
	end
end
--------------------------------------------------------------------------------
-- UpdateSliderLabels() args t_noteSliders, m.preNoteProbTable
-- sets the sliders to the appropriate scale notes, including blanks
--------------------------------------------------------------------------------
function UpdateSliderLabels(sliderTable, preProbTable) -- needs an offset for the root note
	local debug = false
	if debug or m.debug then ConMsg("UpdateSliderLabels()") end
	for k, v in pairs(sliderTable) do
		if preProbTable[k] then -- if there's a Scale note
			sliderTable[k].label = m.notes[Wrap((preProbTable[k] + 1) + m.root, 12)] -- set the slider to the note name
			if sliderTable[k].val1 == 0 then sliderTable[k].val1 = 1 end
		else
			sliderTable[k].label = ""
			sliderTable[k].val1 = 0
		end
	end
end
--------------------------------------------------------------------------------
-- GetUniqueNote()
--------------------------------------------------------------------------------
function GetUniqueNote(tNotes, noteIdx, noteProbTable, octProbTable)
	local debug = false
	if debug and m.debug then ConMsg("GetUniqueNote()") end
	newNote = m.root + noteProbTable[math.random(1,#noteProbTable)]	
	if m.rndOctX2F and not m.rndPermuteF then
		newNote = newNote + octProbTable[math.random(1, #octProbTable)]
	end
	if #m.dupes == 0 then -- dupe table is empty
		m.dupes.i = 1;  m.dupes[m.dupes.i] = {} -- add note to the dupe table
		m.dupes[m.dupes.i].srtpos	= tNotes[noteIdx][3]
		m.dupes[m.dupes.i].endpos	= tNotes[noteIdx][4]
		m.dupes[m.dupes.i].midi		= newNote
		return newNote
	elseif tNotes[noteIdx][3] >= m.dupes[m.dupes.i].srtpos
		and tNotes[noteIdx][3] < m.dupes[m.dupes.i].endpos then -- note overlaps with previous note
		m.dupes.i = m.dupes.i + 1; m.dupes[m.dupes.i] = {} -- add note to dupe table
		m.dupes[m.dupes.i].srtpos = tNotes[noteIdx][3]
		m.dupes[m.dupes.i].endpos = tNotes[noteIdx][4]
		unique = false
		while not unique do		
			newNote = m.root + noteProbTable[math.random(1,#noteProbTable)]
			if m.rndOctX2F and not m.rndPermuteF then
				newNote = newNote + octProbTable[math.random(1, #octProbTable)]
			end
			unique = true
				for i = 1, m.dupes.i - 1 do -- check all previous overlapping notes
					if m.dupes[i].midi == newNote then unique = false end -- clash, try again
				end -- m.dupes.i
		end -- not unique
			m.dupes[m.dupes.i].midi = newNote -- update dupe table
			return newNote
	else -- note does not overlap with previous note
		m.dupes = {}; m.dupes.i = 1;  m.dupes[m.dupes.i] = {} -- reset dupe table
		m.dupes[m.dupes.i].srtpos	= tNotes[noteIdx][3]
		m.dupes[m.dupes.i].endpos	= tNotes[noteIdx][4]
		m.dupes[m.dupes.i].midi		= newNote
		return newNote			
	end -- if #m.dupes
end
--------------------------------------------------------------------------------
-- RandomizeNotesMono(notebufs t1,t2, noteProbTable)
-- transforms t1 to t2 via noteProbTable
--------------------------------------------------------------------------------
function RandomizeNotesMono(noteProbTable)
	local debug = false
	if debug or m.debug then ConMsg("RandomizeNotesMono()") end
	i = 1
	local t1, t2 = GetNoteBuf(), NewNoteBuf()
	selected, muted, startppq, endppq, pitch, velocity = "true", "false", 0, 0, 0, 127
	while t1[i] do
		t2[i] = {}	
		t2[i][1] = t1[i][1] --selected
		t2[i][2] = t1[i][2] --muted
		t2[i][3] = t1[i][3] --startppq
		t2[i][4] = t1[i][4] --endppq
		t2[i][5] = t1[i][5] --length
		t2[i][6] = t1[i][6] --channel
		if t1[i][1] == true then
			t2[i][7] = m.root + noteProbTable[math.random(1,#noteProbTable)] --pitch  
		else
			t2[i][7] = t1[i][7]
		end
		t2[i][8] = t1[i][8] --velocity/accent
		i = i + 1
	end -- while t1[i]
	--if debug then PrintNotes(t2) end
	SetNotes()
	if m.rndPermuteF and m.activeTake then 
		__, pHash = reaper.MIDI_GetHash(m.activeTake, false, 0)
		m.pHash = pHash
	end
end
--------------------------------------------------------------------------------
-- RandomizeNotesPoly(notebufs t1,t2, noteProbTable)
--------------------------------------------------------------------------------
function RandomizeNotesPoly(noteProbTable)
	local debug = false
	if debug or m.debug then ConMsg("RandomizeNotesPoly()") end
	m.dupes.i = 1
	local  i = 1
	local t1, t2 = GetNoteBuf(), NewNoteBuf()
	CopyTable(t1, t2)
	while t2[i] do
		if t2[i][1] == true or m.rndAllNotesF then -- if selected, or all notes flag is true
			if i == 1 and m.rndFirstNoteF then
				t2[i][7] = m.root
			else
				t2[i][7] = GetUniqueNote(t1, i, noteProbTable, m.octProbTable)
			end
		end
		i = i + 1
	end -- while t1[i]
	PurgeNoteBuf()
	InsertNotes()
	if m.rndPermuteF and m.activeTake then 
		__, pHash = reaper.MIDI_GetHash(m.activeTake, false, 0)
		m.pHash = pHash
	end
end
--------------------------------------------------------------------------------
-- GenSequence(seqProbTable, accProbTable, accSlider, legProbTable)
--------------------------------------------------------------------------------
function GenSequence(seqProbTable, accProbTable, accSlider, legProbTable)
	local debug = false
	if debug or m.debug then ConMsg("GenSequence()") end
	local t, t2 = NewNoteBuf(), GetNoteBuf()
	CopyTable(t2, t)
	GetReaperGrid() -- populates m.reaGrid
	--t = GetNoteBuf(); if t == nil then t = NewNoteBuf() end --pre-undo
	ClearTable(t)
	local itemPos = 0
	local gridSize = m.reaGrid * m.ppqn
	local itemLength = GetItemLength()
	local noteStart, noteEnd, noteLen, noteVel = 0, 0, 0, 0
	local newNote = 0
	local noteCount = 0; restCount = 0
	while itemPos < itemLength do
	
		if m.seqFirstNoteF and noteCount == 0 then  -- handle first note flag
			newNote = seqProbTable[math.random(1, #seqProbTable)]
			while newNote == -1 do
				newNote = seqProbTable[math.random(1, #seqProbTable)]
			end
		else  
			newNote = seqProbTable[math.random(1, #seqProbTable)]
		end -- m.seqFirstNoteF
			
		if newNote == -1 then
			itemPos = itemPos + gridSize
			restCount = restCount + 1
		else
			noteStart = itemPos
			noteLen = newNote * m.ppqn
			noteEnd = noteStart + noteLen
			itemPos = itemPos + noteLen
			if m.seqLegatoF then  -- handle legato flag
				noteEnd = noteEnd + legProbTable[math.random(1, #legProbTable)]
			else
				noteEnd = noteEnd + m.legato
			end 
			if m.seqAccentF then  -- handle accent flag
				noteVel = accProbTable[math.random(1, #accProbTable)]
			else
				noteVel = math.floor(accSlider.val1)
			end -- m.seqAccentF
			noteCount = noteCount + 1
			t[noteCount] = {}
			t[noteCount][1] = true                -- selected
			t[noteCount][2] = false               -- muted
			t[noteCount][3] = noteStart           -- startppqn
			t[noteCount][4] = noteEnd             -- endppqn
			t[noteCount][5] = noteLen             -- note length
			t[noteCount][6] = 0                   -- channel
			t[noteCount][7] = m.root              -- note number
			t[noteCount][8] = noteVel             -- velocity
		end -- newNote
	end -- itemPos < itemLength
	if debug and m.debug then PrintNotes(t) end
	PurgeNoteBuf()  
	InsertNotes()
end
--------------------------------------------------------------------------------
-- GenBjorklund(pulses, steps, rotation, accProbTable, accSlider)
--------------------------------------------------------------------------------
function GenBjorklund(pulses, steps, rotation, accProbTable, accSlider)
	local debug = false
	if debug or m.debug then ConMsg("GenBjorklund()") end
	local t, t2 = NewNoteBuf(), GetNoteBuf()
	CopyTable(t2, t)
	GetReaperGrid() -- populates m.reaGrid
	--t = GetNoteBuf(); if t == nil then t = NewNoteBuf() end -- pre-undo
	ClearTable(t)
	local itemPos = 0
	local gridSize = m.reaGrid * m.ppqn
	local itemLength = GetItemLength()
	local noteStart, noteEnd, noteLen, noteVel = 0, 0, 0, 0
	local newNote = 0
	local noteCount = 0; restCount = 0
	local pattern = b.generate(pulses.val1, steps.val1)
	local rot = rotation.val1
	local idx = (-rot) + 1; idx = Wrap(idx, steps.val1)
	while itemPos < itemLength do
		if pattern[idx] then
			noteStart = itemPos
			noteLen = gridSize
			noteEnd = noteStart + noteLen
			itemPos = itemPos + noteLen
			if m.eucAccentF then  -- handle accent flag
				noteVel = accProbTable[math.random(1, #accProbTable)]
			else
				noteVel = math.floor(accSlider.val1)
			end -- m.seqAccentF      
			--noteVel = accProbTable[math.random(1, #accProbTable)]
			noteCount = noteCount + 1
			t[noteCount] = {}
			t[noteCount][1] = true                -- selected
			t[noteCount][2] = false               -- muted
			t[noteCount][3] = noteStart           -- startppqn
			t[noteCount][4] = noteEnd + m.legato  -- endppqn
			t[noteCount][5] = noteLen             -- note length
			t[noteCount][6] = 0                   -- channel
			t[noteCount][7] = m.root              -- note number
			t[noteCount][8] = noteVel             -- velocity
		else
			itemPos = itemPos + gridSize
			restCount = restCount + 1
		end
		idx = idx + 1
		idx = Wrap(idx, steps.val1)
	end
	PurgeNoteBuf()
	InsertNotes()
end
--------------------------------------------------------------------------------
-- GenNoteAttributes(acc, leg) -- accent, legato only
--------------------------------------------------------------------------------
function GenNoteAttributes(accF, accProbTable, accSlider, legF, legProbTable)
	local debug = false
	if debug or m.debug then ConMsg("GenNoteAttributes()") end
	if not accF and not legF then return end
	local t1, t2 = GetNoteBuf(), NewNoteBuf()
	local i = 1
	local noteStart, noteEnd, noteLen = 0, 0, 0
	CopyTable(t1, t2)
	if debug and m.debug then PrintNotes(t2) end
	while t2[i] do
		if t2[i][1] then
			if accF then -- handle accent flag (8 = velocity)
				t2[i][8] = accProbTable[math.random(1, #accProbTable)]
			end -- end accent
			if legF ~= 1 then -- no legato when called by euclid
				if legF then -- handle legato flag (3 = noteStart, 4 = noteEnd, 5 = noteLen)
					noteLen = t2[i][5]
					if noteLen >= 960 + m.legato and noteLen <= 960 - m.legato then noteLen = 960 -- 1/4
				--elseif noteLen >= 642 + m.legato and noteLen <= 644 - m.legato then noteLen = 643.2 -- 1/4t
					elseif noteLen >= 480 + m.legato and noteLen <= 480 - m.legato then noteLen = 480 -- 1/8
				--elseif noteLen >= 315 + m.legato and noteLen <= 317 - m.legato then noteLen = 316.8 -- 1/8t
					elseif noteLen >= 240 + m.legato and noteLen <= 240 - m.legato then noteLen = 240 -- 1/16
				--elseif noteLen >= 162 + m.legato and noteLen <= 164 - m.legato then noteLen = 163.2 -- 1/16t
					end
					t2[i][4] = t2[i][3] + noteLen + legProbTable[math.random(1, #legProbTable)]
				end -- legato     
			end -- t2[i]
		end --selected
		i = i + 1    
	end -- while t1[i]
	if debug and m.debug then PrintNotes(t2) end
	PurgeNoteBuf()
	SetNotes()
end
--------------------------------------------------------------------------------
-- SetNotes - arg notebuf t1; set notes in the active take
--------------------------------------------------------------------------------
function SetNotes()
	local debug = false
	if debug or m.debug then ConMsg("SetNotes()") end
	--get repeat info 
	--get item length
	local i = 1
	if m.activeTake then
		local t1 = GetNoteBuf()
		while t1[i] do
			reaper.MIDI_SetNote(m.activeTake, i-1, t1[i][1], t1[i][2], t1[i][3], t1[i][4], t1[i][6], t1[i][7], t1[i][8], __)
			--1=selected, 2=muted, 3=startppq, 4=endppq, 5=len, 6=chan, 7=pitch, 8=vel, noSort)		
			i = i + 1
		end -- while t1[i]
		reaper.MIDI_Sort(m.activeTake)
		reaper.MIDIEditor_OnCommand(m.activeEditor, 40435) -- all notes off
	else
		if debug or m.debug then ConMsg("No Active Take") end
	end -- m.activeTake
end
--------------------------------------------------------------------------------
-- InsertNotes(note_buffer) - insert notes in the active take
--------------------------------------------------------------------------------
function InsertNotes()
	local debug = false
	if debug or m.debug then ConMsg("InsertNotes()") end
	--get repeat info 
	--get item length
	DeleteNotes()
	local i = 1
	if m.activeTake then
		local t1 = GetNoteBuf()
		while t1[i] do
			reaper.MIDI_InsertNote(m.activeTake, t1[i][1], t1[i][2], t1[i][3], t1[i][4], t1[i][6], t1[i][7], t1[i][8], false)
			--1=selected, 2=muted, 3=startppq, 4=endppq, 5=len, 6=chan, 7=pitch, 8=vel, noSort)		
			i = i + 1
		end -- while t1[i]
		reaper.MIDI_Sort(m.activeTake)
		reaper.MIDIEditor_OnCommand(m.activeEditor, 40435) -- all notes off
	else
		ConMsg("Error in InsertNotes() - No Active Take")
	end -- m.activeTake
end
--------------------------------------------------------------------------------
-- PrintNotes - arg note_buffer t; print note_buffer to reaper console
--------------------------------------------------------------------------------
function PrintNotes(t)
	local debug = false
	if debug or m.debug then ConMsg("PrintNotes()") end
	local i = 1
	local str = "sel \t mut \t s_ppq \t e_ppq \t leng \t chan \t pitch \t vel \n"
	while t[i] do
		j = 1
		while (t[i][j] ~= nil)   do	
			str = str .. tostring(t[i][j]) .. "\t"
			j = j + 1
		end	
		str = str .. "\n"
		i = i + 1
	end -- while t[i]
	str = str .. "\n"
	if debug or m.debug then ConMsg(str) end
end
--------------------------------------------------------------------------------
-- PrintTable - print table to reaper console
--------------------------------------------------------------------------------
function PrintTable(t)
	local debug = false
	if debug or m.debug then ConMsg("PrintTable()") end
	local str = ""
	for k, v in pairs(t) do
			str = str .. tostring(v) .. "\t"
	end	
	str = str .. "\n"
	if debug or m.debug then ConMsg(str) end
end
--------------------------------------------------------------------------------
-- ShowMessage(textbox, message number) - display or hide a message for user
--------------------------------------------------------------------------------
function ShowMessage(tb, msgNum)
	local debug = false
	if debug and m.debug then ConMsg("ShowMessage() ") end
	if msgNum == 0 then
		tb.tab = (1 << 9)  
		tb.label = ""
	elseif msgNum == 1 then 
		tb.tab = 0
		tb.label = "No Active Take"  
	end
end

--[[
--------------------------------------------------------------------------------
-- Experimental Swing Code
--------------------------------------------------------------------------------
--[[ Swing Explanation
MIDI 'swing'  -- every 2nd grid position can be 'swung' by 1/2 of 1 grid position either left or right (total == 1 grid pos)
PPQN (pulses per quarter note) default in REAPER is 960; function(p)
GRID is in decimal quarter notes; e.g. 0.25 = 1/16th (1/4 of 1/4); function(g)
SWINGPC is a % from -100% to 100%.  If using values from 0-1, the conversion is ((s - 0.5) * 200); function(s)
swingTicks is the amount of ppqn to shift the note (positive or negative)
--]]
--[[ Swing How-to
to find every 2nd note position; start at grid position 2 (== grid_size), then add double the grid size each time, until the the end of the note array.
the note will lie somewhere between -50 and 50 % of the grid size e.g.
	if note_start > curr_grid_pos - max_swing_val and note_start < curr_grid_pos + max_swing_val then
		note_start = curr_grid_pos + swing
	end
--]]
--------------------------------------------------------------------------------
local function SwingNotes(noteTable, p, g, st)
	local gridSize = p * g  -- grid size in ticks
	local gridPos  = gridSize -- 1st swing grid position
	local gridStep = gridSize * 2 -- offset to next swing grid position
	local maxSwing = gridSize / 2 -- max swing is +/-50% of the grid size
	local itemLen  = gridSize * 16 -- get this from reaper api
	local noteLen	 = 0
	sth="gd : "..gridSize.."\tcgp : "..gridPos.."\tgs : " .. gridStep.."\tmsv : "..maxSwing.."\tst : "..st.."\til : "..itemLen
	for k, v in pairs(noteTable) do
		for gridPos = gridSize, (itemLen-gridSize), gridStep do --
			if v[1] >= (gridPos - maxSwing) and v[1] <= (gridPos + maxSwing) then
				noteLen = v[2] - v[1]
				--print("start = " .. v[1] .. "\tend = " .. v[2] .. "\tlen = " .. (v[2] - v[1]) .. "\t- pre-swing")
				v[1] = gridPos + st  --noteStart
				v[2] = v[1] + noteLen  --noteEnd but check for end of item...
				--print("start = " .. v[1] .. "\tend = " .. v[2] .. "\tlen = " .. (v[2] - v[1]) .. "\t- post-swing")
			end
		end
	end
end
--------------------------------------------------------------------------------
local function PrintNotes2(noteTable)
	local str = ""  
	for k, v in pairs(noteTable) do
		if type(v) == "table" then 
			PrintNotes(v)
		else 
			str = str .. tostring(v).."\t" 
		end
	end
	--print(str)
end
--------------------------------------------------------------------------------
local function GetGridSize (p, g) -- (ppqn, g)
	return p * g
end
--------------------------------------------------------------------------------
-- GetSwingTicks(p, g, s) args; int ppqn, float grid, int swing%; returns; int swing ticks(ppqn)
--------------------------------------------------------------------------------
local function GetSwingTicks(p, g, s)
	return math.floor(p * g * s * 0.005)
end
--------------------------------------------------------------------------------
local notez = { 
	{0,     240, 240}, 
	{240,   480, 240}, 
	{480,   720, 240},
	{720,   960, 240},
	{960,  1200, 240},
	{1200, 1440, 240},
	{1440, 1680, 240},
	{1920, 2160, 240},
	{2160, 2400, 240}
}
local ppqn = 960 -- default REAPER value; how to check ?
local grid = 0.25 -- 1/16th note (4 / 16) set by user (droplist, or from REAPER ME)
local swingpc = -23 -- set by user (slider)
local swingTicks = GetSwingTicks(ppqn, grid, swingpc)

--------------------------------------------------------------------------------
-- Experimental Swing Code End
--------------------------------------------------------------------------------
--]]
--------------------------------------------------------------------------------
-- FUNCTIONS END
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- GUI Layout START
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Create GUI Elements
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Main Window
--------------------------------------------------------------------------------
-- Persistent window elements
local winFrame = e.Frame:new({0}, 5, 5, m.win_w - 10, m.win_h - 10, e.col_grey4)
local zoomDrop = e.Droplist:new({0}, 5, 5, 40, 22, e.col_green, "", e.Arial, 16, e.col_grey8, 4, {"70%", "80%", "90%", "100%", "110%", "120%", "140%", "160%", "180%", "200%"})
local winText = e.Textbox:new({0}, 45, 5, m.win_w - 50, 22, e.col_green, "MIDI Ex Machina    ", e.Arial, 16, e.col_grey8)
local layerBtn01 = e.Button:new({0}, 5, m.win_h - 25, 100, 20, e.col_green, "Notes", e.Arial, 16, e.col_grey8)
local layerBtn02 = e.Button:new({0}, 105, m.win_h - 25, 100, 20, e.col_grey5, "Sequencer", e.Arial, 16, e.col_grey7)
local layerBtn03 = e.Button:new({0}, 205, m.win_h - 25, 100, 20, e.col_grey5, "Euclid", e.Arial, 16, e.col_grey7)
local layerBtn04 = e.Button:new({0}, 305, m.win_h - 25, 100, 20, e.col_grey5, "Options", e.Arial, 16, e.col_grey7)
local undoBtn = e.Button:new({0}, m.win_w-90, m.win_h -25, 40, 20, e.col_grey5, "Undo", e.Arial, 16, e.col_grey7)
local redoBtn = e.Button:new({0}, m.win_w-50, m.win_h -25, 40, 20, e.col_grey5, "Redo", e.Arial, 16, e.col_grey7)
-- Persistent window element table
t_winElements = {winFrame, zoomDrop, winText, layerBtn01, layerBtn02, layerBtn03, layerBtn04, undoBtn, redoBtn}

--------------------------------------------------------------------------------
-- Common Elements
--------------------------------------------------------------------------------
-- key, octave, & scale droplists
dx, dy, dw, dh = 25, 70, 110, 20
local keyDrop = e.Droplist:new({1, 2, 3}, dx, dy,		 dw, dh, e.col_blue, "Root Note", e.Arial, 16, e.col_grey8, m.key, m.notes)
local octDrop = e.Droplist:new({1, 2, 3}, dx, dy + 45, dw, dh, e.col_blue, "Octave ", e.Arial, 16, e.col_grey8, m.oct,{0, 1, 2, 3, 4, 5, 6, 7})
local scaleDrop = e.Droplist:new({1, 2, 3}, dx, dy + 90, dw, dh, e.col_blue, "Scale", e.Arial, 16, e.col_grey8, 1, m.scalelist)
local t_Droplists = {keyDrop, octDrop, scaleDrop} 

--------------------------------------------------------------------------------
-- Notes Layer
--------------------------------------------------------------------------------
-- note randomize button
local randomBtn = e.Button:new({1}, 25, 205, 110, 25, e.col_green, "Randomize", e.Arial, 16, e.col_grey8)
-- note weight sliders
local nx, ny, nw, nh, np = 160, 50, 30, 150, 40 -- Tie this anchor to the Notes Section Frame, and rename vars
local noteSldr01 = e.Vert_Slider:new({1}, nx,        ny, nw, nh, e.col_blue, "", e.Arial, 16, e.col_grey8, 1, 0, 0, 12, 1)
local noteSldr02 = e.Vert_Slider:new({1}, nx+(np*1), ny, nw, nh, e.col_blue, "", e.Arial, 16, e.col_grey8, 1, 0, 0, 12, 1)
local noteSldr03 = e.Vert_Slider:new({1}, nx+(np*2), ny, nw, nh, e.col_blue, "", e.Arial, 16, e.col_grey8, 1, 0, 0, 12, 1)
local noteSldr04 = e.Vert_Slider:new({1}, nx+(np*3), ny, nw, nh, e.col_blue, "", e.Arial, 16, e.col_grey8, 1, 0, 0, 12, 1)
local noteSldr05 = e.Vert_Slider:new({1}, nx+(np*4), ny, nw, nh, e.col_blue, "", e.Arial, 16, e.col_grey8, 1, 0, 0, 12, 1)
local noteSldr06 = e.Vert_Slider:new({1}, nx+(np*5), ny, nw, nh, e.col_blue, "", e.Arial, 16, e.col_grey8, 1, 0, 0, 12, 1)
local noteSldr07 = e.Vert_Slider:new({1}, nx+(np*6), ny, nw, nh, e.col_blue, "", e.Arial, 16, e.col_grey8, 1, 0, 0, 12, 1)
local noteSldr08 = e.Vert_Slider:new({1}, nx+(np*7), ny, nw, nh, e.col_blue, "", e.Arial, 16, e.col_grey8, 1, 0, 0, 12, 1)
local noteSldr09 = e.Vert_Slider:new({1}, nx+(np*8), ny, nw, nh, e.col_blue, "", e.Arial, 16, e.col_grey8, 1, 0, 0, 12, 1)
local noteSldr10 = e.Vert_Slider:new({1}, nx+(np*9), ny, nw, nh, e.col_blue, "", e.Arial, 16, e.col_grey8, 1, 0, 0, 12, 1)
local noteSldr11 = e.Vert_Slider:new({1}, nx+(np*10), ny, nw, nh, e.col_blue, "", e.Arial, 16, e.col_grey8, 1, 0, 0, 12, 1)
local noteSldr12 = e.Vert_Slider:new({1}, nx+(np*11), ny, nw, nh, e.col_blue, "", e.Arial, 16, e.col_grey8, 1, 0, 0, 12, 1)
local noteSldr13 = e.Vert_Slider:new({1}, nx+(np*12), ny, nw, nh, e.col_blue, "", e.Arial, 16, e.col_grey8, 1, 0, 0, 12, 1)
-- Note weight slider table
local t_noteSliders = {noteSldr01, noteSldr02, noteSldr03, noteSldr04, noteSldr05, noteSldr06, noteSldr07,
	noteSldr08, noteSldr09, noteSldr10, noteSldr11, noteSldr12, noteSldr13}
-- Note weight slider label (Textbox)
local probSldrText = e.Textbox:new({1}, nx, 210, 510, 20, e.col_grey5, "Note Weight Sliders", e.Arial, 16, e.col_grey7)
-- Note octave doubler probability slider
local octProbSldr = e.Vert_Slider:new({1}, nx+(np*13) + 10,  ny, nw, nh, e.col_blue, "%", e.Arial, 16, e.col_grey8, 1, 0, 0, 10, 1)
local octProbText = e.Textbox:new({1}, nx+(np*13) + 10, 210, (nw), 20, e.col_grey5, "Oct", e.Arial, 16, e.col_grey7) 
-- Note randomiser options
local noteOptionsCb = e.Checkbox:new({1}, nx+(np*14)+10, ny+30, 30, 30, e.col_orange, "", e.Arial, 16, e.col_grey8, {0,0,0},   {"All / Sel Notes", "1st Note = Root", "Octave X2"})
local noteOptionText = e.Textbox:new({1}, nx+(np*14)+20, 210, (nw*4), 20, e.col_grey5, "Options", e.Arial, 16, e.col_grey7)
--------------------------------------------------------------------------------
-- Sequencer Layer
--------------------------------------------------------------------------------
-- sequence generate button
local sequenceBtn = e.Button:new({2}, 25, 205, 110, 25, e.col_yellow, "Generate", e.Arial, 16, e.col_grey8)
local sx, sy, sw, sh, sp = 160, 50, 30, 150, 40
-- sequencer grid size radio selector
local seqGridRad = e.Rad_Button:new({2,3}, sx, sy + 40, 30, 30, e.col_yellow, "", e.Arial, 16, e.col_grey8, 1, {"1/16", "1/8", "1/4"})
local seqGridText = e.Textbox:new({2,3}, sx, 210, (sw*2)+20, 20, e.col_grey5, "Grid Size", e.Arial, 16, e.col_grey7)
-- sequence grid probability sliders
--local seqSldr16t  = e.Vert_Slider:new({2}, sx+(sp*3),  sy, sw, sh, e.col_blue, "1/16t", e.Arial, 16, e.col_grey8, 0, 0, 0, 16, 1)
local seqSldr16   = e.Vert_Slider:new({2}, sx+(sp*3),  sy, sw, sh, e.col_blue, "1/16",  e.Arial, 16, e.col_grey8, 0, 0, 0, 16, 1)
--local seqSldr8t   = e.Vert_Slider:new({2}, sx+(sp*5),  sy, sw, sh, e.col_blue, "1/8t",  e.Arial, 16, e.col_grey8, 0, 0, 0, 16, 1)
local seqSldr8    = e.Vert_Slider:new({2}, sx+(sp*4),  sy, sw, sh, e.col_blue, "1/8",   e.Arial, 16, e.col_grey8, 0, 0, 0, 16, 1)
--local seqSldr4t   = e.Vert_Slider:new({2}, sx+(sp*7),  sy, sw, sh, e.col_blue, "1/4t",  e.Arial, 16, e.col_grey8, 0, 0, 0, 16, 1)
local seqSldr4    = e.Vert_Slider:new({2}, sx+(sp*5),  sy, sw, sh, e.col_blue, "1/4",   e.Arial, 16, e.col_grey8, 0, 0, 0, 16, 1)
local seqSldrRest = e.Vert_Slider:new({2}, sx+(sp*6),  sy, sw, sh, e.col_blue, "Rest",  e.Arial, 16, e.col_grey8, 0, 0, 0, 16, 1)
-- sequence grid probability slider table
local t_seqSliders = {seqSldr16, seqSldr8, seqSldr4, seqSldrRest}
-- sequence grid probability sliders label 
local seqSldrText = e.Textbox:new({2}, sx + (sp * 3) - 10, 210, (sw * 4) + 50, 20, e.col_grey5, "Sequence Weight Sliders", e.Arial, 16, e.col_grey7)

-- velocity accent slider (shared with Euclid layer)
local seqAccRSldr  = e.V_Rng_Slider:new({2,3}, sx + (sp * 10), sy, sw, sh, e.col_blue, "", e.Arial, 16, e.col_grey8, 100, 127, 0, 127, 1)
local seqAccProbSldr = e.Vert_Slider:new({2,3}, sx + (sp * 11),  sy, sw, sh, e.col_blue, "%", e.Arial, 16, e.col_grey8, 3, 0, 0, 10, 1)
local seqAccSldrText = e.Textbox:new({2,3}, sx + (sp * 10), 210, (sw * 2) + 10, 20, e.col_grey5, "Vel  |  Acc", e.Arial, 16, e.col_grey7)

-- legato slider
local seqLegProbSldr = e.Vert_Slider:new({2}, sx + (sp * 12), sy, sw, sh, e.col_blue, "%", e.Arial, 16, e.col_grey8, 3, 0, 0, 10, 1)
local seqLegSldrText = e.Textbox:new({2}, sx+(sp * 12), 210, sw, 20, e.col_grey5, "Leg", e.Arial, 16, e.col_grey7)
-- Sequencer options
local seqOptionsCb = e.Checkbox:new({2}, sx+(np * 14) + 10, sy + 5, 30, 30, e.col_orange, "", e.Arial, 16, e.col_grey8, {0,0,0,0,0,0}, {"Generate", "1st Note Always", "Accent", "Legato", "Rnd Notes", "Repeat"})
-- ToDo Repeat

--------------------------------------------------------------------------------
-- Euclid Layer
--------------------------------------------------------------------------------
-- euclid generate button
local euclidBtn = e.Button:new({3}, 25, 205, 110, 25, e.col_orange, "Generate", Arial, 16, e.col_grey8)
-- euclidean sliders
local ex, ey, ew, eh, ep = 160, 50, 30, 150, 40
--local vslider01 = e.Vert_Slider:new({1}, x, y, w, h, col, "label", Font, 16, e.col_grey8, v1,v2, min, max, step)
local euclidPulsesSldr = e.Vert_Slider:new({3}, ex+(ep*3), ey, ew, eh, e.col_blue, "Puls", Arial, 16, e.col_grey8, 3, 0, 0, 24, 1)
local euclidStepsSldr = e.Vert_Slider:new({3}, ex+(ep*4), ey, ew, eh, e.col_blue, "Step", Arial, 16, e.col_grey8, 8, 0, 0, 24, 1)
local euclidRotationSldr = e.Vert_Slider:new({3}, ex+(ep*5), ey, ew, eh, e.col_blue, "Rot",  Arial, 16, e.col_grey8, 0, 0, 0, 24, 1)
local t_euclidSliders = {euclidPulsesSldr, euclidStepsSldr, euclidRotationSldr}
-- euclid slider label 
local txtEuclidLabel = e.Textbox:new({3}, ex + (ep * 3), 210, (ew * 3) + 20, 20, e.col_grey5, "Euclid Sliders", Arial, 16, e.col_grey7)
-- Sequencer options
local eucOptionsCb = e.Checkbox:new({3},  ex + (ep * 14) + 10, ey + 40, 30, 30, e.col_orange, "", e.Arial, 16, e.col_grey8, {0,0,0}, {"Generate", "Accent", "Rnd Notes"})

--------------------------------------------------------------------------------
-- Options Layer
--------------------------------------------------------------------------------
local optText = e.Textbox:new({4}, m.win_x + 10, m.win_y + 30, m.win_w - 40, m.win_h - 80, e.col_grey5, "Nothing to see here, yet...", e.Arial, 16, e.col_grey8)

--------------------------------------------------------------------------------
-- Messages Layer
--------------------------------------------------------------------------------
local msgText = e.Textbox:new({9}, m.win_x + 10, m.win_y + 30, m.win_w - 40, m.win_h - 80, e.col_greym, "", e.Arial, 22, e.col_grey9)
--------------------------------------------------------------------------------
-- Shared Element Tables
--------------------------------------------------------------------------------
local t_Buttons = {randomBtn, sequenceBtn, euclidBtn}
local t_Checkboxes = {noteOptionsCb, seqOptionsCb, eucOptionsCb}
local t_RadButtons = {seqGridRad}
local t_RSliders = {octProbSldr, seqAccRSldr, seqAccProbSldr, seqLegProbSldr}
local t_Textboxes = {probSldrText, octProbText, seqGridText, seqSldrText, seqAccSldrText, seqLegSldrText, txtEuclidLabel, optText, msgText}
--------------------------------------------------------------------------------
-- errors and messages, all screens
	-- textbox
	-- botton

--------------------------------------------------------------------------------
-- GUI Element Functions START
-------------------------------------------------------------------------------- 
--------------------------------------------------------------------------------
-- Button Functions
--------------------------------------------------------------------------------
-- Layer 1
layerBtn01.onLClick = function() -- randomizer
	local debug = false
	if debug or m.debug then ConMsg("\nlayerBtn01.onLClick() (note randomizer)") end
	e.gActiveLayer = 1 
	zoomDrop.r, zoomDrop.g, zoomDrop.b, zoomDrop.a = table.unpack(e.col_green)
	winText.r, winText.g, winText.b, winText.a = table.unpack(e.col_green)
	layerBtn01.font_rgba = e.col_grey8 -- highlight layer 1
	layerBtn01.r, layerBtn01.g, layerBtn01.b, layerBtn01.a = table.unpack(e.col_green)
	layerBtn02.font_rgba = e.col_grey7
	layerBtn02.r, layerBtn02.g, layerBtn02.b, layerBtn02.a = table.unpack(e.col_grey5)
	layerBtn03.font_rgba = e.col_grey7
	layerBtn03.r, layerBtn03.g, layerBtn03.b, layerBtn03.a = table.unpack(e.col_grey5)
	layerBtn04.font_rgba = e.col_grey7
	layerBtn04.r, layerBtn04.g, layerBtn04.b, layerBtn04.a = table.unpack(e.col_grey5)
end
-- Layer 2
layerBtn02.onLClick = function() -- sequencer
	local debug = false
	if debug or m.debug then ConMsg("\nlayerBtn02.onLClick() (sequencer)") end
	e.gActiveLayer = 2
	zoomDrop.r, zoomDrop.g, zoomDrop.b, zoomDrop.a = table.unpack(e.col_yellow)
	winText.r, winText.g, winText.b, winText.a = table.unpack(e.col_yellow)
	layerBtn01.font_rgba = e.col_grey7
	layerBtn01.r, layerBtn01.g, layerBtn01.b, layerBtn01.a = table.unpack(e.col_grey5)
	layerBtn02.font_rgba = e.col_grey8 -- highlight layer 2
	layerBtn02.r, layerBtn02.g, layerBtn02.b, layerBtn02.a = table.unpack(e.col_yellow)
	layerBtn03.font_rgba = e.col_grey7
	layerBtn03.r, layerBtn03.g, layerBtn03.b, layerBtn03.a = table.unpack(e.col_grey5)
	layerBtn04.font_rgba = e.col_grey7
	layerBtn04.r, layerBtn04.g, layerBtn04.b, layerBtn04.a  = table.unpack(e.col_grey5)
end
-- Layer 3
layerBtn03.onLClick = function() -- euclidean sequencer
	local debug = false
	if debug or m.debug then ConMsg("\nlayerBtn03.onLClick() (euclid)") end
	e.gActiveLayer = 3
	zoomDrop.r, zoomDrop.g, zoomDrop.b, zoomDrop.a = table.unpack(e.col_orange)
	winText.r, winText.g, winText.b, winText.a = table.unpack(e.col_orange)
	layerBtn01.font_rgba = e.col_grey7
	layerBtn01.r, layerBtn01.g, layerBtn01.b, layerBtn01.a = table.unpack(e.col_grey5)
	layerBtn02.font_rgba = e.col_grey7
	layerBtn02.r, layerBtn02.g, layerBtn02.b, layerBtn02.a = table.unpack(e.col_grey5)
	layerBtn03.font_rgba = e.col_grey8 -- highlight layer 3
	layerBtn03.r, layerBtn03.g, layerBtn03.b, layerBtn03.a = table.unpack(e.col_orange)
	layerBtn04.font_rgba = e.col_grey7
	layerBtn04.r, layerBtn04.g, layerBtn04.b, layerBtn04.a = table.unpack(e.col_grey5)
end
-- Layer 4
layerBtn04.onLClick = function() -- options
	local debug = false
	if debug or m.debug then ConMsg("\nlayerBtn04.onLClick() (options)") end
	e.gActiveLayer = 4
	zoomDrop.r, zoomDrop.g, zoomDrop.b, zoomDrop.a = table.unpack(e.col_grey5)
	winText.r, winText.g, winText.b, winText.a = table.unpack(e.col_grey5)
	layerBtn01.font_rgba = e.col_grey7
	layerBtn01.r, layerBtn01.g, layerBtn01.b, layerBtn01.a = table.unpack(e.col_grey5)
	layerBtn02.font_rgba = e.col_grey7
	layerBtn02.r, layerBtn02.g, layerBtn02.b, layerBtn02.a = table.unpack(e.col_grey5)
	layerBtn03.font_rgba = e.col_grey7
	layerBtn03.r, layerBtn03.g, layerBtn03.b, layerBtn03.a = table.unpack(e.col_grey5)
	layerBtn04.font_rgba = e.col_grey8 -- highlight layer 4
	layerBtn04.r, layerBtn04.g, layerBtn04.b, layerBtn04.a = table.unpack(e.col_grey6)
end
-- Undo
undoBtn.onLClick = function() -- undo
	local debug = false
	if debug or m.debug then ConMsg("\nundoBtn.onLClick()") end
	UndoNoteBuf()
	InsertNotes()
	PrintNotes(m.notebuf[m.notebuf.i])
end
-- Redo
redoBtn.onLClick = function() -- redo
	local debug = false
	if debug or m.debug then ConMsg("\nredoBtn.onLClick()") end
	--m.notebuf = {}; m.notebuf.i = 0
	if m.notebuf[m.notebuf.i + 1] ~= nil then
		PrintNotes(m.notebuf[m.notebuf.i + 1])
		m.notebuf.i = m.notebuf.i + 1
		InsertNotes()
		PrintNotes(m.notebuf[m.notebuf.i])
	else
	if debug or m.debug then ConMsg("\nnothing to redo...") end  
	end
end
-- Randomize
randomBtn.onLClick = function()
	local debug = false
	if debug or m.debug then ConMsg("\nrandomBtn.onLClick()") end
	if m.activeTake then
		GenProbTable(m.preNoteProbTable, t_noteSliders, m.noteProbTable)
		GenOctaveTable(m.octProbTable, octProbSldr)
		GetNotesFromTake() 
		RandomizeNotesPoly(m.noteProbTable)
	end --m.activeTake
end 
-- Sequence
sequenceBtn.onLClick = function()
	local debug = false
	if debug or m.debug then ConMsg("\nsequenceBtn.onLClick()") end
	if m.activeTake then 
		if m.seqF then
			if debug or m.debug then ConMsg("m.seqF = " .. tostring(m.seqF)) end
			SetSeqGridSizes(t_seqSliders)
			GenProbTable(m.preSeqProbTable, t_seqSliders, m.seqProbTable)
			GenAccentTable(m.accProbTable, seqAccRSldr, seqAccProbSldr)
			GenLegatoTable(m.legProbTable, seqLegProbSldr)
			GetNotesFromTake()
			GenSequence(m.seqProbTable, m.accProbTable, seqAccRSldr, m.legProbTable)
			if m.seqRndNotesF then 
				randomBtn.onLClick() -- call RandomizeNotes
			end
		else -- not m.seqF
			if debug or m.debug then ConMsg("m.seqF = " .. tostring(m.seqF)) end
			GenAccentTable(m.accProbTable, seqAccRSldr, seqAccProbSldr)
			GenLegatoTable(m.legProbTable, seqLegProbSldr)
			GetNotesFromTake() 
			GenNoteAttributes(m.seqAccentF, m.accProbTable, seqAccRSldr, m.seqLegatoF, m.legProbTable)  
			if m.seqRndNotesF then
			if debug or m.debug then ConMsg("m.seqRndNotesF = " .. tostring(m.seqRndNotesF)) end
				randomBtn.onLClick() -- call RandomizeNotes
			end
		end  -- m.seqF
	end  --m.activeTake
end

-- Euclid
euclidBtn.onLClick = function()
	local debug = false
	if debug or m.debug then ConMsg("\neuclidBtn.onLClick()") end
	if m.activeTake then
		if m.eucF then
			if debug or m.debug then ConMsg("m.eucF = " .. tostring(m.eucF)) end
			GenAccentTable(m.accProbTable, seqAccRSldr, seqAccProbSldr)
			GetNotesFromTake()
			GenBjorklund(euclidPulsesSldr, euclidStepsSldr, euclidRotationSldr, m.accProbTable, seqAccRSldr)
			if m.eucRndNotesF then 
				randomBtn.onLClick() -- call RandomizeNotes
			end
		else -- not m.eucF
			if debug or m.debug then ConMsg("m.eucF = " .. tostring(m.eucF)) end
			GenAccentTable(m.accProbTable, seqAccRSldr, seqAccProbSldr)
			GetNotesFromTake()
			GenNoteAttributes(m.eucAccentF, m.accProbTable, seqAccRSldr, false, m.legProbTable)
			if m.eucRndNotesF then 
				if debug or m.debug then ConMsg("m.eucRndNotesF = " .. tostring(m.eucRndNotesF)) end
				randomBtn.onLClick() -- call RandomizeNotes
			end    
		end -- m.eucF
	end -- m.activeTake
end
--------------------------------------------------------------------------------
-- Checkbox and Toggle functions
--------------------------------------------------------------------------------
-- Note randomizer options toggle logic
noteOptionsCb.onLClick = function()
	local debug = false
	if debug or m.debug then ConMsg("\nnoteOptionsCb.onLClick()") end
	m.rndAllNotesF = 		 noteOptionsCb.val1[1] == 1 and true or false -- All / Sel Notes
	m.rndFirstNoteF = noteOptionsCb.val1[2] == 1 and true or false -- 1st Note Root
	m.rndOctX2F = 				 noteOptionsCb.val1[3] == 1 and true or false -- Octave X2
	if debug or m.debug then PrintTable(noteOptionsCb.val1) end
end

-- Sequencer options toggle logic 
seqOptionsCb.onLClick = function()
	local debug = false
	if debug or m.debug then ConMsg("\nseqOptionsCb.onLClick()") end
	m.seqF = 					seqOptionsCb.val1[1] == 1 and true or false -- Generate
	m.seqFirstNoteF = seqOptionsCb.val1[2] == 1 and true or false -- 1st Note Always
	m.seqAccentF = 		seqOptionsCb.val1[3] == 1 and true or false -- Accent
	m.seqLegatoF = 		seqOptionsCb.val1[4] == 1 and true or false -- Legato
	m.seqRndNotesF = 	seqOptionsCb.val1[5] == 1 and true or false -- Randomize Notes
	m.seqRepeatF = 		seqOptionsCb.val1[6] == 1 and true or false -- Repeat
	if debug or m.debug then PrintTable(seqOptionsCb.val1) end
end

-- Euclid options
eucOptionsCb.onLClick = function()
	local debug = false
	if debug or m.debug then ConMsg("\neucOptionsCb.onLClick()") end
	m.eucF = 				 eucOptionsCb.val1[1] == 1 and true or false -- Generate
	m.eucAccentF = 	 eucOptionsCb.val1[2] == 1 and true or false -- Accent
	m.eucRndNotesF = eucOptionsCb.val1[3] == 1 and true or false -- Randomize notes
	if debug or m.debug then PrintTable(eucOptionsCb.val1) end
end

--------------------------------------------------------------------------------
-- Droplist Functions
--------------------------------------------------------------------------------
-- Window zoom
zoomDrop.onLClick = function() -- window scaling
	local debug = false
	if debug or m.debug then ConMsg("\nzoomDrop.onLClick()") end
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
	if debug or m.debug then ConMsg("zoom = " .. tostring(e.gScale)) end
	-- Save state, close and reopen GFX window
	__, m.win_x, m.win_y, __, __ = gfx.dock(-1,0,0,0,0)
	e.gScaleState = true
	gfx.quit()
	InitGFX()
end
-- Root Key
keyDrop.onLClick = function()
	local debug = false
	if debug or m.debug then ConMsg("\nkeyDrop.onLClick()") end
	m.key = keyDrop.val1
	m.root = SetRootNote(m.oct, m.key)	
	UpdateSliderLabels(t_noteSliders, m.preNoteProbTable)
end
-- Octave
octDrop.onLClick = function()
	local debug = false
	if debug or m.debug then ConMsg("\noctDrop.onLClick()") end
	m.oct = octDrop.val1
	m.root = SetRootNote(m.oct, m.key)	
end
-- Scale
scaleDrop.onLClick = function()
	local debug = false
	if debug or m.debug then ConMsg("\nscaleDrop.onLClick()") end
	SetScale(scaleDrop.val2[scaleDrop.val1], m.scales, m.preNoteProbTable)
	UpdateSliderLabels(t_noteSliders, m.preNoteProbTable)
end	

--------------------------------------------------------------------------------
-- Radio Button Functions
--------------------------------------------------------------------------------
seqGridRad.onLClick = function() -- change grid size
	local debug = false
	if debug or m.debug then ConMsg("\nseqGridRad.onLClick()") end
	if m.activeTake then
		if seqGridRad.val1 == 1 then -- 1/16 grid
			reaper.MIDIEditor_OnCommand(m.activeEditor, 40192) -- set grid 1/16 
			seqSldr16.val1 = 8; seqSldr8.val1 = 8; seqSldr4.val1 = 0; seqSldrRest.val1 = 4        
		elseif seqGridRad.val1 == 2 then -- 1/8 grid
			seqSldr16.val1 = 0; seqSldr8.val1 = 8; seqSldr4.val1 = 2; seqSldrRest.val1 = 2      
			reaper.MIDIEditor_OnCommand(m.activeEditor, 40197) -- set grid 1/8  
		elseif seqGridRad.val1 == 3 then -- 1/4 grid
			reaper.MIDIEditor_OnCommand(m.activeEditor, 40201) -- set grid 1/4 
			seqSldr16.val1 = 0; seqSldr8.val1 = 2; seqSldr4.val1 = 8; seqSldrRest.val1 = 1        
		end -- seGridRad
	end -- m.activeTake
end
--------------------------------------------------------------------------------
-- Slider Functions
--------------------------------------------------------------------------------
-- Euclid pulses slider 
euclidPulsesSldr.onMove = function()
	local debug = false
	if debug or m.debug then ConMsg("euclidPlusesSldr.onMove()") end
	if euclidPulsesSldr.val1 > euclidStepsSldr.val1 then -- pulses > steps
		euclidStepsSldr.val1 = euclidPulsesSldr.val1
		euclidRotationSldr.max = euclidStepsSldr.val1
	end
end
-- Euclid steps slider
euclidStepsSldr.onMove = function()
	local debug = false
	if debug or m.debug then ConMsg("euclidStepsSldr.onMove()") end
	if euclidStepsSldr.val1 < euclidPulsesSldr.val1 then -- steps < pulses
		euclidPulsesSldr.val1 = euclidStepsSldr.val1
	end
	if euclidStepsSldr.val1 < euclidRotationSldr.val1 then -- steps < rotation
		euclidRotationSldr.val1 = euclidStepsSldr.val1
		euclidRotationSldr.max = euclidRotationSldr.val1
	end
	if euclidStepsSldr.val1 > euclidRotationSldr.max then -- steps > max rotation
		euclidRotationSldr.max = euclidStepsSldr.val1
	end
end
-- Euclid rotation slider
euclidRotationSldr.onMove = function()
	local debug = false
	if debug or m.debug then ConMsg("euclidRotationSldr.onMove()") end
	euclidRotationSldr.max = euclidStepsSldr.val1
	if euclidRotationSldr.val1 > euclidStepsSldr.val1 then
		euclidRotationSldr.val1 = euclidStepsSldr.val1
		euclidRotationSldr.max = euclidRotationSldr.val1
	end
end

--------------------------------------------------------------------------------
-- GUI Element Functions END
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- GUI Layout END
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- GUI - Main DRAW function
--------------------------------------------------------------------------------
function DrawGUI()
	for key, winElms in pairs(t_winElements) do winElms:draw() end
	--for key, frame in pairs(t_Frames) do frame:draw() end 
	for key, check in pairs(t_Checkboxes) do check:draw() end
	for key, radio in pairs(t_RadButtons) do radio:draw() end	
	for key, btn in pairs(t_Buttons) do btn:draw() end
	for key, dlist in pairs(t_Droplists) do dlist:draw() end 
	--for key, knb in pairs(t_Knobs) do knb:draw() end
	for key, rsliders in pairs(t_RSliders) do rsliders:draw() end
	for key, nsldrs in pairs(t_noteSliders) do nsldrs:draw() end
	for key, ssldrs in pairs(t_seqSliders) do ssldrs:draw() end
	for key, esldrs in pairs(t_euclidSliders) do esldrs:draw() end
	for key, textb in pairs(t_Textboxes) do textb:draw() end
end
--------------------------------------------------------------------------------
-- INIT
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Init Functions (GUI)
--------------------------------------------------------------------------------
function setDefaultScale()
	local debug = false
	if debug or m.debug then ConMsg("SetDefaultScale() = " .. m.curScaleName) end
	local scaleIdx = 0
	for k, v in pairs(m.scales) do
		if v.name == m.curScaleName then scaleDrop.val1 = k	end
	end
end
--[[
ToDo - make these right click functions (layers, sliders, radio/checkbox)
-- reset zoom
zoomDrop.onRClick = function()
	local result = reaper.ShowMessageBox("Reset Zoom?", "Zoom Reset", 4)
	if result == 6 then zoomDrop.val1 = m.def_zoom end
	zoomDrop.onLClick()
end
-- octave, key, and root (root = octave + key)
function setDefaultOctave()
	octDrop.val1 - m.oct
end
function setDefaultKey()
-- 1 = low c in an octave, 2 = c#, 3 = d... 13 = high c
	keyDrop.val1 = m.key
end
--]]
function setDefaultNoteOptions()
	local debug = false
	if debug or m.debug then ConMsg("setDefaultNoteOptions()") end
	noteOptionsCb.val1[1] = (true and m.rndAllNotesF) and 1 or 0 -- all notes
	noteOptionsCb.val1[2] = (true and m.rndFirstNoteF) and 1 or 0 -- first note root
	noteOptionsCb.val1[2] = (true and m.rndOctX2F) and 1 or 0 -- octave doubler
end
function setDefaultSeqOptions()
	local debug = false
	if debug or m.debug then ConMsg("setDefaultSeqOptions()") end
	seqOptionsCb.val1[1] = (true and m.seqF) and 1 or 0 -- generate
	seqOptionsCb.val1[2] = (true and m.seqFirstNoteF) and 1 or 0 -- 1st Note Always
	seqOptionsCb.val1[3] = (true and m.seqAccentF) and 1 or 0 -- accent
	seqOptionsCb.val1[4] = (true and m.seqLegatoF) and 1 or 0 -- legato
	seqOptionsCb.val1[5] = (true and m.seqRndNotesF) and 1 or 0 -- random notes
	seqOptionsCb.val1[6] = (true and m.seqRepeatF) and 1 or 0 -- repeat
end
function setDefaultEucOptions()
	local debug = false
	if debug or m.debug then ConMsg("setDefaultEucOptions()") end
	eucOptionsCb.val1[1] = (true and m.eucF) and 1 or 0 -- generate
	eucOptionsCb.val1[2] = (true and m.eucAccentF) and 1 or 0 -- accents
	eucOptionsCb.val1[3] = (true and m.eucRndNotesF) and 1 or 0 -- randomize notes
end
--------------------------------------------------------------------------------
-- InitMidiExMachina
--------------------------------------------------------------------------------
function InitMidiExMachina()
	math.randomseed(os.time())
	for i = 1, 15 do math.random() end -- lua quirk, first random call always returns the same value...
	reaper.ClearConsole()
	local debug = false  
	if debug or m.debug then ConMsg("InitMidiExMachina()") end 
	
	-- grab the midi editor, and active take
	m.activeEditor = reaper.MIDIEditor_GetActive()
	if m.activeEditor then
		m.activeTake = reaper.MIDIEditor_GetTake(m.activeEditor)
		__ = NewNoteBuf()
		if not m.activeTake then ConMsg("InitMidiExMachina() - No Active Take") end
	else
		ConMsg("InitMidiMachina() - No Active MIDI Editor")
	end -- m.activeEditor
	
	m.root = SetRootNote(m.oct, m.key) -- root note should match the gui..
	for k, v in pairs(m.scales) do  -- create a scale list for the gui
		m.scalelist[k] = m.scales[k]["name"]
	end
	
	setDefaultScale()
	ClearTable(m.preNoteProbTable); ClearTable(m.preSeqProbTable)
	SetScale(m.curScaleName, m.scales, m.preNoteProbTable)	--set chosen scale
	SetSeqGridSizes(t_seqSliders)
	UpdateSliderLabels(t_noteSliders, m.preNoteProbTable)
	GenProbTable(m.preNoteProbTable, t_noteSliders, m.noteProbTable)
	
	--set default checkbox options
	setDefaultNoteOptions()
	setDefaultSeqOptions()
	setDefaultEucOptions()
	--set sane default sequencer grid slider values
	seqGridRad.onLClick()	
	
	
	GetReaperGrid(seqGridRad)
	
	GetItemLength()
	GetNotesFromTake() -- grab the original note data (if any...)
	if debug or m.debug then ConMsg("End InitMidiExMachina()\n") end
end
--------------------------------------------------------------------------------
-- InitGFX
--------------------------------------------------------------------------------
function InitGFX()
	local debug = false
	if debug or m.debug then ConMsg("InitGFX()") end
	-- Init window ------
	gfx.clear = RGB2Packed(table.unpack(m.win_bg))     
	gfx.init(m.win_title, m.win_w * e.gScale, m.win_h * e.gScale, m.win_dockstate, m.win_x, m.win_y)
	-- Last mouse position and state
	gLastMouseCap, gLastMouseX, gLastMouseY = 0, 0, 0
	gMouseOX, gMouseOY = -1, -1
end
--------------------------------------------------------------------------------
-- Mainloop
--------------------------------------------------------------------------------
function MainLoop()
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
	
	-- Defer 'MainLoop' if not explicitly quiting (esc)
	if char ~= -1 and char ~= 27 then reaper.defer(MainLoop) end
	
	-- Update Reaper GFX
	gfx.update()
	
	-- editor status checks
	m.activeEditor = reaper.MIDIEditor_GetActive()
	if m.activeEditor then
		m.activeTake = reaper.MIDIEditor_GetTake(m.activeEditor)
		if m.activeTake then
			ShowMessage(msgText, 0) -- clear any previous messages
			-- check for changes in the active take if the "Permute" scale is selected
			if scaleDrop.val2[scaleDrop.val1] == "Permute" then 
				__, pHash = reaper.MIDI_GetHash(m.activeTake, false, 0)
				if m.pHash ~= pHash then
					SetScale("Permute", m.scales, m.preNoteProbTable)
					UpdateSliderLabels(t_noteSliders, m.preNoteProbTable)
					m.pHash = pHash
				end
				-- don't allow any note options that might upset permute...
				noteOptionsCb.val1[1] = 0; m.rndAllNotesF = false -- maybe allow this...?
				noteOptionsCb.val1[2] = 0; m.rndFirstNoteF = false
				noteOptionsCb.val1[3] = 0; m.rndOctX2F = false 
			end -- scaleDrop   
			-- check for grid changes
			local grid = m.reaGrid
			m.reaGrid, __, __ = reaper.MIDI_GetGrid(m.activeTake)
			if grid ~= m.reaGrid then 
				GetReaperGrid(seqGridRad)
				seqGridRad.onLClick() -- set sane default values for sequencer based on grid
			end -- grid
		else -- handle m.activeTake error
			ShowMessage(msgText, 1) 
			m.activeTake = nil
		end
	else -- handle m.activeEditor error
		-- pop up error message - switch layer on textbox element
		ShowMessage(msgText, 1)
		m.activeEditor = nil
		m.activeTake = nil
	end
	
	e.gScaleState = true
end
--------------------------------------------------------------------------------
-- RUN
--------------------------------------------------------------------------------
InitGFX()
InitMidiExMachina()
MainLoop()
--------------------------------------------------------------------------------