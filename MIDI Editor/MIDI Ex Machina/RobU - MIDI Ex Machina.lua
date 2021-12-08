--[[
@description MIDI Ex Machina - Note Randomiser, Sequencer, and Euclidean Generator
@about
	#### MIDI Ex Machina
	A scale-oriented, probability based composition tool
 
	#### Features
	note randomiser
	- selectable root note, octave, scale
	- note probability sliders
	- randomise all or selected notes
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
@version 1.3.5
@author RobU
@changelog
	v1.3.5
	Fixed crash when item not selected in arrange view
	Provided more meaningful warning messages (for not item, or no midi editor)
@provides
	[main=midi_editor] .
	[nomain] eGUI.lua
	[nomain] euclid.lua
	[nomain] persistence.lua

Reaper 5.x
Extensions: SWS
Licenced under the GPL v3
--]]
--------------------------------------------------------------------------------
-- REQUIRES
--------------------------------------------------------------------------------
package.path = debug.getinfo(1,"S").source:match[[^@?(.*[\/])[^\/]-$]] .."?.lua;".. package.path
local e = require 'eGUI'
local b = require 'euclid'
local p = require 'persistence' -- currently unused, i.e. no preset save, load, nada...
-- ToDo preset save, load, etc...

--------------------------------------------------------------------------------
-- GLOBAL VARIABLES START
--------------------------------------------------------------------------------
m = {} -- all ex machina data
-- user changeable defaults are marked with "(option)"
m.debug = false
m.OS = reaper.GetOS()
-- window
m.win_title = "RobU : MIDI Ex Machina - v1.3.5"; m.win_dockstate = 0
m.win_x = 10; m.win_y = 10; m.win_w = 900; m.win_h = 280 -- window dimensions
m.win_bg = {0, 0, 0} -- background colour
m.def_zoom = 4 -- 100% (option)
m.font_sz = 16
-- zoom values are 1=70, 2=80, 3=90, 4=100, 5=110%, 6=120, 7=140, 8=160, 9=180, 10=200
m.zoomF = false

if string.match(m.OS, "Win") then
	-- nada
elseif string.match(m.OS, "OSX") then
	m.font_sz = m.font_sz - 2
else
	-- nada		
end

-- default octave & key
-- due to some quirk, oct 4 is really oct 3...
m.oct = 4; m.key = 1; m.root = 0 -- (options, except m.root)

-- midi editor, take, grid
m.activeEditor, m.activeTake = nil, nil
m.ppqn = 960; -- default ppqn, no idea how to check if this has been changed.. 
m.reaGrid = 0

-- note randomiser
m.rndAllNotesF = false -- all notes or only selected notes (option)
m.rndOctX2F = false -- enable double scale randomisation (option)
m.rndFirstNoteF = true; -- first note is always root (option)
m.rndPermuteF = false; m.pHash = 0 -- midi item state changes
m.rndOctProb = 1 -- (option - min 0, max 10)

-- sequence generator
m.seqF = true -- generate sequence (option)
m.seqFirstNoteF = true -- first note always (option)
m.seqAccentF = true -- generate accents (option)
m.seqLegatoF = false -- use legato (option)
m.seqRndNotesF = true -- randomise notes (option) 
m.seqRepeatF = false -- repeat sequence by grid length (option - not implemented yet)
m.legato = -10 -- default legatolessness value
m.accentLow = 100; m.accentHigh = 127; m.accentProb = 3 -- default values (options)
-- accentLow/High - min 0, max 127; accentProb - min 0, max 10
m.legatoProb = 3 -- default value (option - min 0, max 10)
m.seqGrid16 = {8, 4, 0, 2} -- sane default sequencer note length slider values
m.seqGrid8  = {0, 8, 2, 2} -- sane default sequencer note length slider values
m.seqGrid4  = {0, 2, 8, 1} -- sane default sequencer note length slider values
m.seqShift = 0; m.seqShiftMin = -16; m.seqShiftMax = 16 -- shift notes left-right from sequencer
m.repeatStart, m.repeatEnd, m.repeatLength, m.repeatTimes = 0, 0, 0, 0 -- repeat values (currently unused)

-- euclidean generator
m.eucF = true	-- generate euclid (option)
m.eucAccentF = false	-- generate accents (option)
m.eucRndNotesF = false	-- randomise notes (option)
m.eucPulses = 3; m.eucSteps = 8; m.eucRot = 0 -- default values (options)

-- note buffers and current buffer index
m.notebuf = {}; m.notebuf.i = 0; m.notebuf.max = 0

m.dupes = {} -- for duplicate note detection while randomising
m.euclid = {} -- for pattern generation

m.notes = {'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B', 'C'}
m.scales = {
	{0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, name = "Chromatic"},
	{0, 2, 3, 5, 7, 8, 10, 12, name = "Aeolian / Minor"},
	{0, 2, 3, 5, 7, 9, 10, 12, name = "Dorian"},	
	{0, 2, 4, 5, 7, 9, 11, 12, name = "Ionian / Major"},
	{0, 1, 3, 5, 6, 8, 10, 12, name = "Locrian"},
	{0, 2, 4, 6, 7, 9, 11, 12, name = "Lydian"},	
	{0, 2, 4, 5, 7, 9, 10, 12, name = "Mixolydian"},	
	{0, 1, 3, 5, 7, 8, 10, 12, name = "Phrygian"},
	{0, 3, 5, 6, 7, 10, 12, name = "Blues"},
	{0, 1, 4, 5, 7, 8, 11, 12, name = "Dbl. Harmonic"},
	{0, 1, 3, 6, 8, 10, 11, 12, name = "Enigmatic"},
	{0, 1, 4, 5, 7, 8, 11, 12, name = "Flamenco"},
	{0, 2, 4, 5, 7, 8, 11, 12, name = "Harmonic Maj"},
	{0, 2, 3, 5, 7, 8, 11, 12, name = "Harmonic min"},
	{0, 2, 3, 5, 7, 9, 11, 12, name = "Melodic min"},	
	{0, 2, 4, 7, 9, 12, name = "Pentatonic Maj"},
	{0, 3, 5, 7, 10, 12, name = "Pentatonic min"},
	{0, 1, 4, 5, 6, 8, 11, 12, name = "Persian"},
	{name = "Permute"}
}  
-- a list of scales available to the note randomiser, more can be added manually if required
-- each value is the interval step from the root note of the scale (0) including the octave (12)

-- textual list of the available scale names for the GUI list selector
m.scalelist = {}
m.curScaleName = "Chromatic" -- (option - !must be a valid scale name!)

-- various probability tables
m.preNoteProbTable = {};  m.noteProbTable = {}
m.preSeqProbTable = {};   m.seqProbTable  = {}
m.accProbTable = {};      m.octProbTable  = {}
m.legProbTable = {}

pExtSaveStateF = false -- when true, update the pExtState for saving
pExtLoadStateF = true -- when true, load the pExtState
pExtState = {} -- Reaper project ext state table
pExtStateStr = "" -- pickled string. a nom a nom a nom...
--------------------------------------------------------------------------------
-- GLOBAL VARIABLES END
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Utility Functions Start
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local function Wrap (n, max)
-- Wrap(n, max) -return n wrapped between 'n' and 'max'	
	n = n % max
	if (n < 1) then n = n + max end
	return n
end

local function RGB2Dec(r, g, b)
-- RGB2Dec(r, g, b) - takes 8 bit r, g, b values, returns decimal (0 to 1)	
	if r < 0 or r > 255 then r = wrap(r, 255) end
	if g < 0 or g > 255 then g = wrap(g, 255) end
	if b < 0 or b > 255 then b = wrap(b, 255) end
	return r/255, g/255, b/255
end

local function RGB2Packed(r, g, b)
-- RGB2Packed(r, g, b) - returns a packed rgb value	
	local floor = math.floor
		g = (g << 8)
		b = (b << 16)
	return floor(r + g + b)
end

local function ConMsg(str)
-- ConMsg(str) - outputs 'str' to the Reaper console
	reaper.ShowConsoleMsg(str .."\n")
end

--------------------------------------------------------------------------------
-- Pickle table serialization - Steve Dekorte, http://www.dekorte.com, Apr 2000
--------------------------------------------------------------------------------
function pickle(t)
	return Pickle:clone():pickle_(t)
end
--------------------------------------------------------------------------------
Pickle = {
	clone = function (t) local nt = {}
	for i, v in pairs(t) do 
		nt[i] = v 
	end
	return nt 
end 
}
--------------------------------------------------------------------------------
function Pickle:pickle_(root)
	if type(root) ~= "table" then 
		error("can only pickle tables, not " .. type(root) .. "s")
	end
	self._tableToRef = {}
	self._refToTable = {}
	local savecount = 0
	self:ref_(root)
	local s = ""
	while #self._refToTable > savecount do
		savecount = savecount + 1
		local t = self._refToTable[savecount]
		s = s .. "{\n"
		for i, v in pairs(t) do
			s = string.format("%s[%s]=%s,\n", s, self:value_(i), self:value_(v))
		end
	s = s .. "},\n"
	end
	return string.format("{%s}", s)
end
--------------------------------------------------------------------------------
function Pickle:value_(v)
	local vtype = type(v)
	if     vtype == "string" then return string.format("%q", v)
	elseif vtype == "number" then return v
	elseif vtype == "boolean" then return tostring(v)
	elseif vtype == "table" then return "{"..self:ref_(v).."}"
	else error("pickle a " .. type(v) .. " is not supported")
	end 
end
--------------------------------------------------------------------------------
function Pickle:ref_(t)
	local ref = self._tableToRef[t]
	if not ref then 
		if t == self then error("can't pickle the pickle class") end
		table.insert(self._refToTable, t)
		ref = #self._refToTable
		self._tableToRef[t] = ref
	end
	return ref
end
--------------------------------------------------------------------------------
-- unpickle
--------------------------------------------------------------------------------
function unpickle(s)
	if type(s) ~= "string" then
		error("can't unpickle a " .. type(s) .. ", only strings")
	end
	local gentables = load("return " .. s)
	local tables = gentables()
	for tnum = 1, #tables do
		local t = tables[tnum]
		local tcopy = {}
		for i, v in pairs(t) do tcopy[i] = v end
		for i, v in pairs(tcopy) do
			local ni, nv
			if type(i) == "table" then ni = tables[i[1]] else ni = i end
			if type(v) == "table" then nv = tables[v[1]] else nv = v end
			t[i] = nil
			t[ni] = nv
		end
	end
	return tables[1]
end
--------------------------------------------------------------------------------
-- Utility Functions End
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Ex Machina Functions Start
--------------------------------------------------------------------------------
function ClearTable(t)
-- ClearTable(t) - set all items in 2D table 't' to nil	
	local debug = false
	if debug or m.debug then ConMsg("ClearTable()") end
	for k, v in pairs(t) do
		t[k] = nil
	end
end

function CopyTable(t1, t2)
-- CopyTable(t1, t2) - copies note data from t1 to t2
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
-- Note Buffers
--------------------------------------------------------------------------------
local function NewNoteBuf()
-- NewNoteBuf() - add a new note buffer to the table, returns handle
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

local function GetNoteBuf()
-- GetNoteBuf() - returns handle to the current note buffer
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

local function UndoNoteBuf()
-- UndoNoteBuf() - points to previous note buffer
	local debug = false
	if debug or m.debug then ConMsg("UndoNoteBuf()") end
	if m.notebuf.i > 1 then
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

local function PurgeNoteBuf(idx)
-- PurgeNoteBuf() - purge all note buffers from current+1 to end
	local debug = false
	if debug or m.debug then
		ConMsg("PurgeNoteBuf()")
		ConMsg("current idx = " .. tostring(m.notebuf.i))
		ConMsg("max idx     = " .. tostring(m.notebuf.max))
	end
	while m.notebuf.max > m.notebuf.i do
		m.notebuf[m.notebuf.max] = nil
		if debug or m.debug then ConMsg("purging buffer " .. tostring(m.notebuf.max))
		end
		m.notebuf.max = m.notebuf.max - 1
	end  
end

--------------------------------------------------------------------------------
-- GetItemLength(t) - get length of take 't', set various global vars
-- currently it only returns the item length (used in Sequencer and Euclid)
--------------------------------------------------------------------------------
function GetItemLength()
	local debug = false
	if debug or m.debug then ConMsg("GetItemLength()") end

		--mItem = reaper.GetSelectedMediaItem(0, 0)
			mItemLen = reaper.GetMediaItemInfo_Value(m.mItem, "D_LENGTH")
			mBPM, mBPI = reaper.GetProjectTimeSignature2(0)
			msPerMin = 60000
			msPerQN = msPerMin / mBPM
			numQNPerItem = (mItemLen * 1000) / msPerQN
			numBarsPerItem = numQNPerItem / 4
			ItemPPQN = numQNPerItem * m.ppqn
			if debug or m.debug then
				ConMsg("ItemLen (ms)    = " .. mItemLen)
				ConMsg("mBPM            = " .. mBPM)
				ConMsg("MS Per QN       = " .. msPerQN)
				ConMsg("Num of QN       = " .. numQNPerItem)
				ConMsg("Num of Bar      = " .. numBarsPerItem)
				ConMsg("Item size ppqn  = " .. ItemPPQN .. "\n")
			end
			mItemTake = reaper.GetTake(m.mItem, 0) -- should fix looped items
			ItemPPQN = reaper.BR_GetMidiSourceLenPPQ(mItemTake) -- thanks Thrash!
			return ItemPPQN

end

function GetReaperGrid(gridRad)
-- GetReaperGrid() - get the current grid size, set global var m.reaGrid
	local debug = false
	if debug or m.debug then ConMsg("GetReaperGrid()") end
	if m.activeTake then
		m.reaGrid, __, __ = reaper.MIDI_GetGrid(m.activeTake) -- returns quarter notes
		if gridRad then -- if a grid object was passed, update it
			if m.reaGrid == 0.25 then gridRad.val1 = 1 -- 1/16
			elseif m.reaGrid == 0.5 then gridRad.val1 = 2 -- 1/8
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
-- GetNotesFromTake() - fill a note buffer from the active take
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
		PrintNotes(GetNoteBuf())
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
	if debug or m.debug then ConMsg("SetScale()") end
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
	if debug or m.debug then ConMsg("scaleName = " .. tostring(scaleName)) end
end
--------------------------------------------------------------------------------
-- SetSeqGridSizes()  
--------------------------------------------------------------------------------
function SetSeqGridSizes(sliderTable)
	local debug = false
	if debug or m.debug then ConMsg("SetSeqGridSizes()") end
	for k, v in pairs(sliderTable) do
		if sliderTable[k].label == "1/16" then m.preSeqProbTable[k] = 0.25
		elseif sliderTable[k].label == "1/8" then m.preSeqProbTable[k] = 0.5
		elseif sliderTable[k].label == "1/4" then m.preSeqProbTable[k] = 1.0
		elseif sliderTable[k].label == "Rest" then m.preSeqProbTable[k] = -1.0
		end
	end
end
--------------------------------------------------------------------------------
-- UpdateSliderLabels() args t_noteSliders, m.preNoteProbTable
-- sets the sliders to the appropriate scale notes, including blanks
--------------------------------------------------------------------------------
function UpdateSliderLabels(sliderTable, preProbTable)
	local debug = false
	if debug or m.debug then ConMsg("UpdateSliderLabels()") end
	for k, v in pairs(sliderTable) do
		if preProbTable[k] then -- if there's a Scale note
			-- set the slider to the note name
			sliderTable[k].label = m.notes[Wrap((preProbTable[k] + 1) + m.root, 12)]
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
	newNote = m.root + noteProbTable[math.random(1, #noteProbTable)]	
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
-- RandomiseNotesPoly(noteProbTable)
--------------------------------------------------------------------------------
function RandomiseNotesPoly(noteProbTable)
	local debug = false
	if debug or m.debug then ConMsg("RandomiseNotesPoly()") end
	m.dupes.i = 1
	local  i = 1
	local t1, t2 = GetNoteBuf(), NewNoteBuf()
	CopyTable(t1, t2)
	while t2[i] do
		if t2[i][1] == true or m.rndAllNotesF then -- if selected, or all notes flag is true
			if i == 1 and m.rndFirstNoteF then -- if selected, the first not is always root of scale
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
			-- check if noteLen exceeds the item length
			if noteStart + noteLen > itemLength then noteLen = itemLength - noteStart end
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
	local floor = math.floor
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
	local pulse = floor(pulses.val1 + 0.5)
	local step = floor(steps.val1 + 0.5)
	local pattern = b.generate(pulse, step)
	local rot = floor(rotation.val1 + 0.5)
	local idx = (-rot) + 1; idx = Wrap(idx, step)
	while itemPos < itemLength do
		if pattern[idx] then
			noteStart = itemPos
			noteLen = gridSize
			noteEnd = noteStart + noteLen
			itemPos = itemPos + noteLen
			if m.eucAccentF then  -- handle accent flag
				noteVel = accProbTable[math.random(1, #accProbTable)]
			else
				noteVel = floor(accSlider.val1)
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
		idx = Wrap(idx, step)
	end
	PurgeNoteBuf()
	InsertNotes()
end
--------------------------------------------------------------------------------
-- GenNoteAttributes(accF, accProb, accVal, legF, legVal) -- accent, legato only
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
					elseif noteLen >= 480 + m.legato and noteLen <= 480 - m.legato then noteLen = 480 -- 1/8
					elseif noteLen >= 240 + m.legato and noteLen <= 240 - m.legato then noteLen = 240 -- 1/16
					end
					t2[i][4] = t2[i][3] + noteLen + legProbTable[math.random(1, #legProbTable)]
				end -- legato     
			end -- t2[i]
		end --selected
		i = i + 1    
	end -- while t1[i]
	if debug and m.debug then PrintNotes(t2) end
	PurgeNoteBuf()
	InsertNotes()
end

--------------------------------------------------------------------------------
-- InsertNotes(note_buffer) - insert notes in the active take
--------------------------------------------------------------------------------
function InsertNotes()
	local debug = false
	if debug or m.debug then ConMsg("\nInsertNotes()") end
	DeleteNotes()
	local i = 1
	if m.activeTake and m.mItem then
		local noteLength = 0
		local gridSize = m.reaGrid * m.ppqn
		local itemLength = GetItemLength()	
		local noteShift = m.seqShift * gridSize
		local t1 = GetNoteBuf()	
		local t2 = {} -- for note shifting
		CopyTable(t1, t2)
		if debug then ConMsg("itemPPQN = "..itemLength) end
		if debug then ConMsg("noteshift = "..noteShift) end
		
		for k, v in pairs(t2) do -- do note shifting
			noteLength = v[4] - v[3]
			v[3] = v[3] + noteShift
			v[4] = v[4] + noteShift	
			
			if v[3] >= itemLength then -- positive shift
				v[3] = v[3] - itemLength
				v[4] = v[4] - itemLength
			
			elseif v[3] < 0 then -- negative shift
				v[3] = v[3] + itemLength
				v[4] = v[4] + itemLength

			end
			
			if v[4] > itemLength then v[4] = itemLength - 1 end	
			
			if debug then ConMsg("v3 = "..v[3].."    ".."v4 = "..v[4].."    ".."notelen = "..noteLength) end			
		end

		
		while t2[i] do
			reaper.MIDI_InsertNote(m.activeTake, t2[i][1], t2[i][2], t2[i][3], t2[i][4], t2[i][6], t2[i][7], t2[i][8], false)
			--1=selected, 2=muted, 3=startppq, 4=endppq, 5=len, 6=chan, 7=pitch, 8=vel, noSort)		
			i = i + 1
		end -- while t2[i]
		reaper.MIDI_Sort(m.activeTake)
		reaper.MIDIEditor_OnCommand(m.activeEditor, 40435) -- all notes off
	else
		if debug or m.debug then ConMsg("No Active Take") end
	end -- m.activeTake
end

--------------------------------------------------------------------------------
-- PrintNotes - arg note_buffer t; print note_buffer to reaper console
--------------------------------------------------------------------------------
function PrintNotes(t) -- debug code
	local debug = false
	if debug or m.debug then ConMsg("PrintNotes()") end
	if not t then return end	
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
function PrintTable(t) -- debug code
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
		tb.label = "MIDI Editor Closed" 
	elseif msgNum == 2 then
		tb.tab = 0
		tb.label = "Please select a MIDI Item in the Arrange Window"
	end
	e.gScaleState = true
end
--------------------------------------------------------------------------------
-- FUNCTIONS END
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- GUI START
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- GUI Elements
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Main Window
--------------------------------------------------------------------------------
-- Persistent window elements
local winFrame = e.Frame:new({0}, 5, 5, m.win_w - 10, m.win_h - 10, e.col_grey4)
local zoomDrop = e.Droplist:new({0}, 5, 5, 40, 22, e.col_green, "", e.Arial, m.font_sz, e.col_grey8, 4, {"70%", "80%", "90%", "100%", "110%", "120%", "140%", "160%", "180%", "200%"})
local winText  = e.Textbox:new({0}, 45, 5, m.win_w - 50, 22, e.col_green, "MIDI Ex Machina    ", e.Arial, m.font_sz, e.col_grey8)
local layerBtn01 = e.Button:new({0}, 5, m.win_h - 25, 100, 20, e.col_green, "Randomiser", e.Arial, m.font_sz, e.col_grey8)
local layerBtn02 = e.Button:new({0}, 105, m.win_h - 25, 100, 20, e.col_grey5, "Sequencer", e.Arial, m.font_sz, e.col_grey7)
local layerBtn03 = e.Button:new({0}, 205, m.win_h - 25, 100, 20, e.col_grey5, "Euclidiser", e.Arial, m.font_sz, e.col_grey7)
local layerBtn04 = e.Button:new({0}, 305, m.win_h - 25, 100, 20, e.col_grey5, "Options", e.Arial, m.font_sz, e.col_grey7)
local undoBtn = e.Button:new({0}, m.win_w-85, m.win_h -25, 40, 20, e.col_grey5, "Undo", e.Arial, m.font_sz, e.col_grey7)
local redoBtn = e.Button:new({0}, m.win_w-45, m.win_h -25, 40, 20, e.col_grey5, "Redo", e.Arial, m.font_sz, e.col_grey7)
-- Persistent window element table
t_winElements = {winFrame, zoomDrop, winText, layerBtn01, layerBtn02, layerBtn03, layerBtn04, undoBtn, redoBtn}

--------------------------------------------------------------------------------
-- Common Elements
--------------------------------------------------------------------------------
-- key, octave, & scale droplists
dx, dy, dw, dh = 25, 70, 110, 20
local keyDrop = e.Droplist:new({1, 2, 3}, dx, dy,		 dw, dh, e.col_blue, "Root Note", e.Arial, m.font_sz, e.col_grey8, m.key, m.notes)
local octDrop = e.Droplist:new({1, 2, 3}, dx, dy + 45, dw, dh, e.col_blue, "Octave ", e.Arial, m.font_sz, e.col_grey8, m.oct,{0, 1, 2, 3, 4, 5, 6, 7})
local scaleDrop = e.Droplist:new({1, 2, 3}, dx, dy + 90, dw, dh, e.col_blue, "Scale", e.Arial, m.font_sz, e.col_grey8, 1, m.scalelist)
local t_Droplists = {keyDrop, octDrop, scaleDrop} 

--------------------------------------------------------------------------------
-- Randomiser Layer
--------------------------------------------------------------------------------
-- note randomise button
local randomBtn = e.Button:new({1}, 25, 205, 110, 25, e.col_green, "Generate", e.Arial, m.font_sz, e.col_grey8)
-- note weight sliders
local nx, ny, nw, nh, np = 160, 50, 30, 150, 40
local noteSldr01 = e.Vert_Slider:new({1}, nx,        ny, nw, nh, e.col_blue, "", e.Arial, m.font_sz, e.col_grey8, 1, 0, 0, 12, 1)
local noteSldr02 = e.Vert_Slider:new({1}, nx+(np*1), ny, nw, nh, e.col_blue, "", e.Arial, m.font_sz, e.col_grey8, 1, 0, 0, 12, 1)
local noteSldr03 = e.Vert_Slider:new({1}, nx+(np*2), ny, nw, nh, e.col_blue, "", e.Arial, m.font_sz, e.col_grey8, 1, 0, 0, 12, 1)
local noteSldr04 = e.Vert_Slider:new({1}, nx+(np*3), ny, nw, nh, e.col_blue, "", e.Arial, m.font_sz, e.col_grey8, 1, 0, 0, 12, 1)
local noteSldr05 = e.Vert_Slider:new({1}, nx+(np*4), ny, nw, nh, e.col_blue, "", e.Arial, m.font_sz, e.col_grey8, 1, 0, 0, 12, 1)
local noteSldr06 = e.Vert_Slider:new({1}, nx+(np*5), ny, nw, nh, e.col_blue, "", e.Arial, m.font_sz, e.col_grey8, 1, 0, 0, 12, 1)
local noteSldr07 = e.Vert_Slider:new({1}, nx+(np*6), ny, nw, nh, e.col_blue, "", e.Arial, m.font_sz, e.col_grey8, 1, 0, 0, 12, 1)
local noteSldr08 = e.Vert_Slider:new({1}, nx+(np*7), ny, nw, nh, e.col_blue, "", e.Arial, m.font_sz, e.col_grey8, 1, 0, 0, 12, 1)
local noteSldr09 = e.Vert_Slider:new({1}, nx+(np*8), ny, nw, nh, e.col_blue, "", e.Arial, m.font_sz, e.col_grey8, 1, 0, 0, 12, 1)
local noteSldr10 = e.Vert_Slider:new({1}, nx+(np*9), ny, nw, nh, e.col_blue, "", e.Arial, m.font_sz, e.col_grey8, 1, 0, 0, 12, 1)
local noteSldr11 = e.Vert_Slider:new({1}, nx+(np*10), ny, nw, nh, e.col_blue, "", e.Arial, m.font_sz, e.col_grey8, 1, 0, 0, 12, 1)
local noteSldr12 = e.Vert_Slider:new({1}, nx+(np*11), ny, nw, nh, e.col_blue, "", e.Arial, m.font_sz, e.col_grey8, 1, 0, 0, 12, 1)
local noteSldr13 = e.Vert_Slider:new({1}, nx+(np*12), ny, nw, nh, e.col_blue, "", e.Arial, m.font_sz, e.col_grey8, 1, 0, 0, 12, 1)
-- Note probability slider table
local t_noteSliders = {noteSldr01, noteSldr02, noteSldr03, noteSldr04, noteSldr05, noteSldr06, noteSldr07,
	noteSldr08, noteSldr09, noteSldr10, noteSldr11, noteSldr12, noteSldr13}
-- Note probability slider label (Textbox) - right-click to reset all
local probSldrText = e.Textbox:new({1}, nx, 210, 510, 20, e.col_grey5, "Note Weight Sliders", e.Arial, m.font_sz, e.col_grey7)
-- Note octave doubler probability slider
local octProbSldr = e.Vert_Slider:new({1}, nx+(np*13) + 10,  ny, nw, nh, e.col_blue, "%", e.Arial, m.font_sz, e.col_grey8, m.rndOctProb, 0, 0, 10, 1)
local octProbText = e.Textbox:new({1}, nx+(np*13) + 10, 210, (nw), 20, e.col_grey5, "Oct", e.Arial, m.font_sz, e.col_grey7) 
-- Note randomiser options
local noteOptionsCb = e.Checkbox:new({1}, nx+(np*14)+10, ny+30, 30, 30, e.col_orange, "", e.Arial, m.font_sz, e.col_grey8, {0,0,0},   {"All / Sel Notes", "1st Note = Root", "Octave X2"})
local noteOptionText = e.Textbox:new({1}, nx+(np*14)+20, 210, (nw*4), 20, e.col_grey5, "Options", e.Arial, m.font_sz, e.col_grey7)

--------------------------------------------------------------------------------
-- Sequencer Layer
--------------------------------------------------------------------------------
-- sequence generate button
local sequenceBtn = e.Button:new({2}, 25, 205, 110, 25, e.col_yellow, "Generate", e.Arial, m.font_sz, e.col_grey8)
local sx, sy, sw, sh, sp = 160, 50, 30, 150, 40
-- sequencer grid size radio selector
local seqGridRad = e.Rad_Button:new({2,3}, sx, sy + 40, 30, 30, e.col_yellow, "", e.Arial, m.font_sz, e.col_grey8, 1, {"1/16", "1/8", "1/4"})
local seqGridText = e.Textbox:new({2,3}, sx, 210, (sw*2)+20, 20, e.col_grey5, "Grid Size", e.Arial, m.font_sz, e.col_grey7)
-- sequence grid probability sliders
local seqSldr16   = e.Vert_Slider:new({2}, sx+(sp*3),  sy, sw, sh, e.col_blue, "1/16",  e.Arial, m.font_sz, e.col_grey8, 0, 0, 0, 16, 1)
local seqSldr8    = e.Vert_Slider:new({2}, sx+(sp*4),  sy, sw, sh, e.col_blue, "1/8",   e.Arial, m.font_sz, e.col_grey8, 0, 0, 0, 16, 1)
local seqSldr4    = e.Vert_Slider:new({2}, sx+(sp*5),  sy, sw, sh, e.col_blue, "1/4",   e.Arial, m.font_sz, e.col_grey8, 0, 0, 0, 16, 1)
local seqSldrRest = e.Vert_Slider:new({2}, sx+(sp*6),  sy, sw, sh, e.col_blue, "Rest",  e.Arial, m.font_sz, e.col_grey8, 0, 0, 0, 16, 1)
-- sequence grid probability slider table
local t_seqSliders = {seqSldr16, seqSldr8, seqSldr4, seqSldrRest}
-- sequence grid probability sliders label - right click to reset all (per grid size selection)
local seqSldrText = e.Textbox:new({2}, sx + (sp * 3), 210, (sw * 5), 20, e.col_grey5, "Size Weight Sliders", e.Arial, m.font_sz, e.col_grey7)

-- velocity accent slider (shared with Euclid layer)
local seqAccRSldr  = e.V_Rng_Slider:new({2,3},  sx + (sp * 8) - (sw / 2), sy, sw, sh, e.col_blue, "", e.Arial, m.font_sz, e.col_grey8, m.accentLow, m.accentHigh, 0, 127, 1)
local seqAccProbSldr = e.Vert_Slider:new({2,3}, sx + (sp * 9) - (sw / 2), sy, sw, sh, e.col_blue, "%", e.Arial, m.font_sz, e.col_grey8, m.accentProb, 0, 0, 10, 1)
local seqAccSldrText = e.Textbox:new({2,3},     sx + (sp * 8) - (sw / 2), 210, (sw * 2) + 10, 20, e.col_grey5, "Vel  |  Acc", e.Arial, m.font_sz, e.col_grey7)

-- legato slider
local seqLegProbSldr = e.Vert_Slider:new({2}, sx + (sp * 10) - (sw / 2), sy, sw, sh, e.col_blue, "%", e.Arial, m.font_sz, e.col_grey8, m.legatoProb, 0, 0, 10, 1)
local seqLegSldrText = e.Textbox:new({2},     sx + (sp * 10) - (sw / 2), 210, sw, 20, e.col_grey5, "Leg", e.Arial, m.font_sz, e.col_grey7)

-- sequence shift buttons
local seqShiftLBtn = e.Button:new({2},  sx + (sp * 11) + 10, sy + sh - 25, sw, 25, e.col_blue, "<<", e.Arial, m.font_sz, e.col_grey8)
local seqShiftRBtn = e.Button:new({2},  sx + (sp * 13) - 10, sy + sh - 25, sw, 25, e.col_blue, ">>", e.Arial, m.font_sz, e.col_grey8)
local seqShiftVal  = e.Textbox:new({2}, sx + (sp * 12),      sy + sh - 25, sw, 25, e.col_grey5, tostring(m.seqShift), e.Arial, m.font_sz, e.col_grey7)
local seqShiftText = e.Textbox:new({2}, sx + (sp * 11) + 10, 210, sw * 3, 20, e.col_grey5, "Shift Notes", e.Arial, m.font_sz, e.col_grey7)

-- Sequencer options
local seqOptionsCb = e.Checkbox:new({2}, sx+(np * 14) + 10, sy + 5, 30, 30, e.col_orange, "", e.Arial, m.font_sz, e.col_grey8, {0,0,0,0,0}, {"Generate", "1st Note Always", "Accent", "Legato", "Rnd Notes"})

--------------------------------------------------------------------------------
-- Euclid Layer
--------------------------------------------------------------------------------
-- euclid generate button
local euclidBtn = e.Button:new({3}, 25, 205, 110, 25, e.col_orange, "Generate", Arial, m.font_sz, e.col_grey8)
-- euclidean sliders
local ex, ey, ew, eh, ep = 160, 50, 30, 150, 40
local euclidPulsesSldr = e.Vert_Slider:new({3}, ex+(ep*3), ey, ew, eh, e.col_blue, "Puls", Arial, m.font_sz, e.col_grey8, m.eucPulses, 0, 1, 24, 1)
local euclidStepsSldr = e.Vert_Slider:new({3}, ex+(ep*4), ey, ew, eh, e.col_blue, "Step", Arial, m.font_sz, e.col_grey8, m.eucSteps, 0, 1, 24, 1)
local euclidRotationSldr = e.Vert_Slider:new({3}, ex+(ep*5), ey, ew, eh, e.col_blue, "Rot",  Arial, m.font_sz, e.col_grey8, m.eucRot, 0, 0, 24, 1)
local t_euclidSliders = {euclidPulsesSldr, euclidStepsSldr, euclidRotationSldr}
-- euclid slider label - right click to reset all
local txtEuclidLabel = e.Textbox:new({3}, ex + (ep * 3), 210, (ew * 3) + 20, 20, e.col_grey5, "Euclid Sliders", Arial, m.font_sz, e.col_grey7)
-- Sequencer options
local eucOptionsCb = e.Checkbox:new({3},  ex + (ep * 14) + 10, ey + 40, 30, 30, e.col_orange, "", e.Arial, m.font_sz, e.col_grey8, {0,0,0}, {"Generate", "Accent", "Rnd Notes"})

--------------------------------------------------------------------------------
-- Options Layer
--------------------------------------------------------------------------------
local optText = e.Textbox:new({4}, m.win_x + 10, m.win_y + 30, m.win_w - 40, m.win_h - 80, e.col_grey5, "Nothing to see here, yet...", e.Arial, m.font_sz, e.col_grey8)

--------------------------------------------------------------------------------
-- Messages Layer
--------------------------------------------------------------------------------
local msgText = e.Textbox:new({9}, m.win_x + 10, m.win_y + 30, m.win_w - 40, m.win_h - 80, e.col_greym, "", e.Arial, 22, e.col_grey9)

--------------------------------------------------------------------------------
-- Shared Element Tables
--------------------------------------------------------------------------------
local t_Buttons = {randomBtn, sequenceBtn, seqShiftLBtn, seqShiftRBtn, euclidBtn}
local t_Checkboxes = {noteOptionsCb, seqOptionsCb, eucOptionsCb}
local t_RadButtons = {seqGridRad}
local t_RSliders = {octProbSldr, seqAccRSldr, seqAccProbSldr, seqLegProbSldr}
local t_Textboxes = {probSldrText, octProbText, seqGridText, seqSldrText, seqShiftVal, seqShiftText, seqAccSldrText, seqLegSldrText, txtEuclidLabel, optText, msgText}
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- GUI Functions START
-------------------------------------------------------------------------------- 
--------------------------------------------------------------------------------
-- Main window
--------------------------------------------------------------------------------
-- Window zoom droplist
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
	if not pExtState.win_x then
		__, m.win_x, m.win_y, __, __ = gfx.dock(-1,0,0,0,0)
	else
		-- set project ext state
		pExtState.zoomDrop = zoomDrop.val1
		pExtSaveStateF = true		
	end
	m.zoomF = true
end
-- Layer 1 button
layerBtn01.onLClick = function() -- randomiser
	local debug = false
	if debug or m.debug then ConMsg("\nlayerBtn01.onLClick() (note randomiser)") end
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
	e.gScaleState = true
	-- set project ext state
	pExtState.activeLayer = e.gActiveLayer
	pExtSaveStateF = true			
end
-- Layer 2 button
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
	e.gScaleState = true
		-- set project ext state
	pExtState.activeLayer = e.gActiveLayer
	pExtSaveStateF = true		
end
-- Layer 3 button
layerBtn03.onLClick = function() -- euclidean
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
	e.gScaleState = true
		-- set project ext state
	pExtState.activeLayer = e.gActiveLayer
	pExtSaveStateF = true		
end
-- Layer 4 button
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
	e.gScaleState = true
		-- set project ext state
	pExtState.activeLayer = e.gActiveLayer
	pExtSaveStateF = true		
end
-- Undo button
undoBtn.onLClick = function() -- undo
	local debug = false
	if debug or m.debug then ConMsg("\nundoBtn.onLClick()") end
	UndoNoteBuf()
	InsertNotes()
	PrintNotes(m.notebuf[m.notebuf.i])
end
-- Redo button
redoBtn.onLClick = function() -- redo
	local debug = false
	if debug or m.debug then ConMsg("\nredoBtn.onLClick()") end
	if m.notebuf[m.notebuf.i + 1] ~= nil then
		--PrintNotes(m.notebuf[m.notebuf.i + 1])
		m.notebuf.i = m.notebuf.i + 1
		InsertNotes()
		--PrintNotes(m.notebuf[m.notebuf.i])
	else
		if debug or m.debug then ConMsg("\nnothing to redo...") end  
	end
end
-- Set default window options
function SetDefaultWindowOpts()
	local debug = false
	if debug or m.debug then ConMsg("SetDefaultWinOpts()") end
	if pExtState.zoomDrop then
		zoomDrop.val1 = pExtState.zoomDrop
	end
	if pExtState.win_x or pExtState.win_y then
		m.win_x = pExtState.win_x
		m.win_y = pExtState.win_y
	end
	zoomDrop.onLClick()
end
-- Set default layer
function SetDefaultLayer()
	if pExtState.activeLayer then 
		    if pExtState.activeLayer == 1 then layerBtn01.onLClick()
		elseif pExtState.activeLayer == 2 then layerBtn02.onLClick()
		elseif pExtState.activeLayer == 3 then layerBtn03.onLClick()
		elseif pExtState.activeLayer == 4 then layerBtn04.onLClick()
		end
	end
end

--------------------------------------------------------------------------------
-- Note Randomiser
--------------------------------------------------------------------------------
-- Randomiser button
randomBtn.onLClick = function()
	local debug = false
	if debug or m.debug then ConMsg("\nrandomBtn.onLClick()") end
	if m.activeTake and m.mItem then
		m.seqShift = 0; m.seqShiftMin = 0; m.seqShiftMax = 0 -- reset shift
		seqShiftVal.label = tostring(m.seqShift)
		GenProbTable(m.preNoteProbTable, t_noteSliders, m.noteProbTable)
		if #m.noteProbTable == 0 then return end
		GenOctaveTable(m.octProbTable, octProbSldr)
		GetNotesFromTake() 
		RandomiseNotesPoly(m.noteProbTable)
		-- set project ext state	
		pExtState.noteSliders = {}
		for k, v in pairs(t_noteSliders) do
			pExtState.noteSliders[k] = v.val1
		end
		pExtState.rndOctProb = octProbSldr.val1
		pExtSaveStateF = true
	end --m.activeTake
end 
-- Randomiser options toggle logic
noteOptionsCb.onLClick = function()
	local debug = false
	if debug or m.debug then ConMsg("\nnoteOptionsCb.onLClick()") end
	m.rndAllNotesF =  noteOptionsCb.val1[1] == 1 and true or false -- All / Sel Notes
	m.rndFirstNoteF = noteOptionsCb.val1[2] == 1 and true or false -- 1st Note Root
	m.rndOctX2F =     noteOptionsCb.val1[3] == 1 and true or false -- Octave X2
	pExtState.noteOptionsCb = {m.rndAllNotesF, m.rndFirstNoteF, m.rndOctX2F}
	pExtSaveStateF = true
	if debug or m.debug then PrintTable(noteOptionsCb.val1) end
end
-- Root Key droplist
keyDrop.onLClick = function()
	local debug = false
	if debug or m.debug then ConMsg("\nkeyDrop.onLClick()") end
	m.key = keyDrop.val1
	m.root = SetRootNote(m.oct, m.key)	
	UpdateSliderLabels(t_noteSliders, m.preNoteProbTable)
	-- set project ext state
	pExtState.key = m.key
	pExtState.root = m.root
	pExtSaveStateF = true
end
-- Octave droplist
octDrop.onLClick = function()
	local debug = false
	if debug or m.debug then ConMsg("\noctDrop.onLClick()") end
	m.oct = octDrop.val1
	m.root = SetRootNote(m.oct, m.key)
	-- set project ext state	
	pExtState.oct = m.oct
	pExtState.root = m.root
	pExtSaveStateF = true
end
-- Scale droplist
scaleDrop.onLClick = function()
	local debug = false
	if debug or m.debug then ConMsg("\nscaleDrop.onLClick()") end
	SetScale(scaleDrop.val2[scaleDrop.val1], m.scales, m.preNoteProbTable)
	if m.rndPermuteF then 
		noteOptionsCb.val1[1] = 0
		m.rndAllNotesF  = false
	end
	UpdateSliderLabels(t_noteSliders, m.preNoteProbTable)
	-- set project ext state	
	pExtState.curScaleName = scaleDrop.val2[scaleDrop.val1]
	pExtSaveStateF = true
end	

-- Set default scale options
function SetDefaultScaleOpts()
	local debug = false
	if debug or m.debug then ConMsg("SetDefaultScaleOpts()") end
	-- if key saved in project state, load it
	if pExtState.key then 
		m.key = math.floor(tonumber(pExtState.key))
		keyDrop.val1 = m.key
	end
	-- if octave saved in project state, load it
	if pExtState.oct then 
		m.oct = math.floor(tonumber(pExtState.oct))
		octDrop.val1 = m.oct
	end
	-- set the midi note number for scale root
	m.root = SetRootNote(m.oct, m.key) 
	-- create a scale name lookup table for the gui (scaleDrop)
	for k, v in pairs(m.scales) do
		m.scalelist[k] = m.scales[k]["name"]
	end
	-- if scale name saved in project state, load it
	if pExtState.curScaleName then
		m.curScaleName = pExtState.curScaleName
	end
	-- update the scale dropbox val1 to match the scale table index
	for k, v in pairs(m.scales) do 
		if v.name == m.curScaleName then scaleDrop.val1 = k	end
	end	

	SetScale(m.curScaleName, m.scales, m.preNoteProbTable)	--set chosen scale
	UpdateSliderLabels(t_noteSliders, m.preNoteProbTable) -- set sliders labels to current scale notes
end
-- Set default randomiser options
function SetDefaultRndOptions()
	local debug = false
	if debug or m.debug then ConMsg("SetDefaultRndOptions()") end
	-- if randomiser options were saved to project state, load them
	if pExtState.noteOptionsCb then
		m.rndAllNotesF =  pExtState.noteOptionsCb[1] == true and true or false 
		m.rndFirstNoteF = pExtState.noteOptionsCb[2] == true and true or false
		m.rndOctX2F =     pExtState.noteOptionsCb[3] == true and true or false
		end
	-- set randomiser options using defaults, or loaded project state
	noteOptionsCb.val1[1] = (true and m.rndAllNotesF) and 1 or 0 -- all notes
	noteOptionsCb.val1[2] = (true and m.rndFirstNoteF) and 1 or 0 -- first note root
	noteOptionsCb.val1[3] = (true and m.rndOctX2F) and 1 or 0 -- octave doubler
end
-- Set default randomiser sliders
function SetDefaultRndSliders()
	local debug = false
	if debug or m.debug then ConMsg("SetDefaultRndSliders()") end
	-- if randomiser sliders were saved to project state, load them
	if pExtState.noteSliders then
		for k, v in pairs(t_noteSliders) do
			v.val1 = pExtState.noteSliders[k]
		end
	else
		for k, v in pairs(t_noteSliders) do
			v.val1 = 1
		end
	end -- load note sliders pExtState
	if pExtState.rndOctProb then -- octave probability slider
		octProbSldr.val1 = pExtState.rndOctProb
	else
		octProbSldr.val1 = m.rndOctProb
	end
end

-- Reset note probability sliders
probSldrText.onRClick = function()
	gfx.x = gfx.mouse_x; gfx.y = gfx.mouse_y
	local result = gfx.showmenu("Reset Note Sliders")
	if result == 1 then 
		for k, v in pairs(t_noteSliders) do -- reset the sliders
			if v.label ~= "" then v.val1 = 1 end
		end -- in pairs(t_noteSliders)
		if pExtState.noteSliders then -- write the new proj ext state
			for k, v in pairs(t_noteSliders) do
				if v.label ~= "" then pExtState.noteSliders[k] = v.val1 end
			end -- in pairs(t_noteSliders)
		end -- pExtState.noteSliders
		pExtSaveStateF = true	-- set the ext state save flag
	end -- result
end
-- Reset octave probability slider
octProbText.onRClick = function()
	gfx.x = gfx.mouse_x; gfx.y = gfx.mouse_y
	local result = gfx.showmenu("Reset Octave Slider")
	if result == 1 then 
		octProbSldr.val1 = m.rndOctProb
		if pExtState.rndOctProb then -- write the new proj ext state
				pExtState.rndOctProb = nil
		end -- pExtState.noteSliders
	pExtSaveStateF = true	-- set the ext state save flag
	end -- result
end

--------------------------------------------------------------------------------
-- Sequencer
--------------------------------------------------------------------------------
-- Sequencer button
sequenceBtn.onLClick = function()
	local debug = false
	if debug or m.debug then ConMsg("\nsequenceBtn.onLClick()") end
	if m.activeTake and m.mItem then 
			m.seqShift = 0; m.seqShiftMin = 0; m.seqShiftMax = 0 -- reset shift on new sequence
			seqShiftVal.label = tostring(m.seqShift)	
		if m.seqF then
			SetSeqGridSizes(t_seqSliders)
			GenProbTable(m.preSeqProbTable, t_seqSliders, m.seqProbTable)
			GenAccentTable(m.accProbTable, seqAccRSldr, seqAccProbSldr)
			GenLegatoTable(m.legProbTable, seqLegProbSldr)
			GetNotesFromTake()
			GenSequence(m.seqProbTable, m.accProbTable, seqAccRSldr, m.legProbTable)
			if m.seqRndNotesF then 
				randomBtn.onLClick() -- call RandomiseNotes
			end
		else -- not m.seqF
			GenAccentTable(m.accProbTable, seqAccRSldr, seqAccProbSldr)
			GenLegatoTable(m.legProbTable, seqLegProbSldr)
			GetNotesFromTake() 
			GenNoteAttributes(m.seqAccentF, m.accProbTable, seqAccRSldr, m.seqLegatoF, m.legProbTable)  
			if m.seqRndNotesF then
				randomBtn.onLClick() -- call RandomiseNotes
			end
		end  -- m.seqF
		-- set project ext state
		if seqGridRad.val1 == 1 then -- 1/16 grid
			pExtState.seqGrid16 = {}
			for k, v in pairs (t_seqSliders) do
				pExtState.seqGrid16[k] = v.val1
			end
		end
		if seqGridRad.val1 == 2 then -- 1/8 grid
			pExtState.seqGrid8 = {}
			for k, v in pairs (t_seqSliders) do
				pExtState.seqGrid8[k] = v.val1
			end
		end		
		if seqGridRad.val1 == 3 then -- 1/4 grid
			pExtState.seqGrid4 = {}
			for k, v in pairs (t_seqSliders) do
				pExtState.seqGrid4[k] = v.val1
			end
		end	
		
		pExtState.seqAccRSldrLo = seqAccRSldr.val1
		pExtState.seqAccRSldrHi = seqAccRSldr.val2
		pExtState.seqAccProb = seqAccProbSldr.val1
		pExtState.seqLegProb = seqLegProbSldr.val1
		
		pExtSaveStateF = true
	end  --m.activeTake
end
-- Sequencer options toggle logic 
seqOptionsCb.onLClick = function()
	local debug = false
	if debug or m.debug then ConMsg("\nseqOptionsCb.onLClick()") end
	m.seqF = 					seqOptionsCb.val1[1] == 1 and true or false -- Generate
	m.seqFirstNoteF = seqOptionsCb.val1[2] == 1 and true or false -- 1st Note Always
	m.seqAccentF = 		seqOptionsCb.val1[3] == 1 and true or false -- Accent
	m.seqLegatoF = 		seqOptionsCb.val1[4] == 1 and true or false -- Legato
	m.seqRndNotesF = 	seqOptionsCb.val1[5] == 1 and true or false -- Randomise Notes
	m.seqRepeatF = 		seqOptionsCb.val1[6] == 1 and true or false -- Repeat
	pExtState.seqOptionsCb = {m.seqF, m.seqFirstNoteF, m.seqAccentF, m.seqLegatoF, m.seqRndNotesF, m.seqRepeatF}
	pExtSaveStateF = true
	if debug or m.debug then PrintTable(seqOptionsCb.val1) end
end
-- Sequencer grid radio button
seqGridRad.onLClick = function() -- change grid size
	local debug = false
	if debug or m.debug then ConMsg("\nseqGridRad.onLClick()") end
	if m.activeTake then
	
		if seqGridRad.val1 == 1 then -- 1/16 grid
			reaper.MIDIEditor_OnCommand(m.activeEditor, 40192) -- set grid
			if pExtState.seqGrid16 then
				for k, v in pairs(t_seqSliders) do
					v.val1 = pExtState.seqGrid16[k]
				end -- in pairs(t_seqSliders)
			else -- not pExtState.seqGrid16
				for k, v in pairs(t_seqSliders) do
					v.val1 = m.seqGrid16[k]
				end -- in pairs(t_seqSliders)
			end -- if pExtState.seqGrid16

		elseif seqGridRad.val1 == 2 then -- 1/8 grid
			reaper.MIDIEditor_OnCommand(m.activeEditor, 40197) -- set grid
			if pExtState.seqGrid8 then
				for k, v in pairs(t_seqSliders) do
					v.val1 = pExtState.seqGrid8[k]
				end -- in pairs(t_seqSliders)
			else -- not pExtState.seqGrid8
				for k, v in pairs(t_seqSliders) do
					v.val1 = m.seqGrid8[k]
				end -- in pairs(t_seqSliders)
			end -- if pExtState.seqGrid8

		elseif seqGridRad.val1 == 3 then -- 1/4 grid
			reaper.MIDIEditor_OnCommand(m.activeEditor, 40201) -- set grid
			if pExtState.seqGrid4 then -- 1/4 grid
				for k, v in pairs(t_seqSliders) do
					v.val1 = pExtState.seqGrid4[k]
				end -- in pairs(t_seqSliders)
			else -- not pExtState.seqGrid4
				for k, v in pairs(t_seqSliders) do
					v.val1 = m.seqGrid4[k]
				end -- in pairs(t_seqSliders)
			end -- pExtState.seqGrid4
		end -- seGridRad

		-- reset the shift state
		m.seqShift = 0; m.seqShiftMin = 0; m.seqShiftMax = 0
		seqShiftVal.label = tostring(m.seqShift)
		GetNotesFromTake() -- force an undo point on grid change
		--InsertNotes()

		pExtSaveStateF = true
		
	end -- m.activeTake
end
-- Sequencer shift left
seqShiftLBtn.onLClick = function()
	if not m.mItem then return end
	local gridSize = m.reaGrid * m.ppqn
	local itemLength = GetItemLength()
	m.seqShiftMin = -(math.floor(itemLength / gridSize)-1)
	if m.seqShift <= m.seqShiftMin then
		m.seqShift = 0
	else
		m.seqShift = m.seqShift - 1
	end
	seqShiftVal.label = tostring(m.seqShift)
	InsertNotes()
end
-- Sequencer shift right
seqShiftRBtn.onLClick = function()
	if not m.mItem then return end
	local gridSize = m.reaGrid * m.ppqn
	local itemLength = GetItemLength()
	m.seqShiftMax = math.floor(itemLength / gridSize) - 1
	if m.seqShift >= m.seqShiftMax then 
		m.seqShift = 0
	else
		m.seqShift = m.seqShift + 1
	end	
	seqShiftVal.label = tostring(m.seqShift)
	InsertNotes()
end

-- Set sequencer default options
function SetDefaultSeqOptions()
	local debug = false
	if debug or m.debug then ConMsg("SetDefaultSeqOptions()") end
	
	-- if sequencer options were saved to project state, load them
	if pExtState.seqOptionsCb then 
		m.seqF = 					pExtState.seqOptionsCb[1] ==  true and true or false
		m.seqFirstNoteF = pExtState.seqOptionsCb[2] ==  true and true or false
		m.seqAccentF = 		pExtState.seqOptionsCb[3] ==  true and true or false
		m.seqLegatoF = 		pExtState.seqOptionsCb[4] ==  true and true or false
		m.seqRndNotesF = 	pExtState.seqOptionsCb[5] ==  true and true or false
		m.seqRepeatF = 		pExtState.seqOptionsCb[6] ==  true and true or false
	end
	
	-- set sequencer options using defaults, or loaded project state
	seqOptionsCb.val1[1] = (true and m.seqF) and 1 or 0 -- generate
	seqOptionsCb.val1[2] = (true and m.seqFirstNoteF) and 1 or 0 -- 1st Note Always
	seqOptionsCb.val1[3] = (true and m.seqAccentF) and 1 or 0 -- accent
	seqOptionsCb.val1[4] = (true and m.seqLegatoF) and 1 or 0 -- legato
	seqOptionsCb.val1[5] = (true and m.seqRndNotesF) and 1 or 0 -- random notes
	seqOptionsCb.val1[6] = (true and m.seqRepeatF) and 1 or 0 -- repeat
end
-- Set default accent & legato sliders
function SetDefaultAccLegSliders()
	local debug = false
	if debug or m.debug then ConMsg("SetDefaultAccLegSliders()") end
	-- if seq accent & legato sliders were saved to project state, load them
	if pExtState.seqAccRSldrLo then 
		seqAccRSldr.val1 = pExtState.seqAccRSldrLo
	else
		seqAccRSldr.val1 = m.accentLow
	end
	if pExtState.seqAccRSldrHi then 
		seqAccRSldr.val2 = pExtState.seqAccRSldrHi
	else
		seqAccRSldr.val2 = m.accentHigh
	end
	if pExtState.seqAccProb then 
		seqAccProbSldr.val1 = pExtState.seqAccProb
	else
		seqAccProbSldr.val1	= m.accentProb
	end
	if pExtState.seqLegProb then 
		seqLegProbSldr.val1 = pExtState.seqLegProb
	else
		seqLegProbSldr.val1 = m.legatoProb
	end
end
-- Set default grid sliders
function SetDefaultSeqGridSliders()
	local debug = false
	if debug or m.debug then ConMsg("\nSetDefaultSeqGridSliders()") end

	GetReaperGrid(seqGridRad)
	SetSeqGridSizes(t_seqSliders)	

	if seqGridRad.val1 == 1 then
		if pExtState.seqGrid16 then -- 1/16 grid
			for k, v in pairs(t_seqSliders) do
				v.val1 = pExtState.seqGrid16[k]
			end
		else -- not pExtState.seqGrid16
			for k, v in pairs(t_seqSliders) do
				v.val1 = m.seqGrid16[k]
			end
		end -- pExtState.seqGrid16

	elseif seqGridRad.val1 == 2 then	
		if pExtState.seqGrid8 then -- 1/8 grid
			for k, v in pairs(t_seqSliders) do
				v.val1 = pExtState.seqGrid8[k]
			end
		else -- not pExtState.seqGrid8
			for k, v in pairs(t_seqSliders) do
				v.val1 = m.seqGrid8[k]
			end
		end -- pExtState.seqGrid8

	elseif seqGridRad.val1 == 3 then		
		if pExtState.seqGrid4 then -- 1/4 grid
			for k, v in pairs(t_seqSliders) do
				v.val1 = pExtState.seqGrid4[k]
			end
		else -- not pExtState.seqGrid4
			for k, v in pairs(t_seqSliders) do
				v.val1 = m.seqGrid4[k]
			end
		end 
	end -- pExtState.seqGrid4
	
		if debug or m.debug then 
			for k, v in pairs(t_seqSliders) do
				ConMsg("t_seqSliders.val1 (4) = " .. tostring(v.val1))
			end
		end
		
end
-- Set default sequencer shift state
function SetDefaultSeqShift()
	local debug = false
	if debug or m.debug then ConMsg("SetDefaultSeqShift()") end
		m.seqShift = 0
		m.seqShiftMin = 0
		m.seqShiftMax = 0
		seqShiftVal.label = tostring(m.seqShift)
end

-- Reset sequencer grid sliders
seqSldrText.onRClick = function()
	local debug = false
	if debug or m.debug then ConMsg("\nseqSldrText.onLClick()") end
	gfx.x = gfx.mouse_x; gfx.y = gfx.mouse_y
	local result = gfx.showmenu("Reset Sequence Sliders")
	if result == 1 then
		if seqGridRad.val1 == 1 then -- 1/16ths
			for k, v in pairs(t_seqSliders) do -- reset the sliders
				v.val1 = m.seqGrid16[k]
			end -- in pairs(t_seqSliders)
			pExtState.seqGrid16 = nil
			
		elseif seqGridRad.val1 == 2 then -- 1/8ths
			for k, v in pairs(t_seqSliders) do -- reset the sliders
				v.val1 = m.seqGrid8[k]
			end -- in pairs(t_seqSliders)
			pExtState.seqGrid8 = nil
			
		elseif seqGridRad.val1 == 3 then -- 1/4ths
			for k, v in pairs(t_seqSliders) do -- reset the sliders
				v.val1 = m.seqGrid4[k]
			end -- in pairs(t_seqSliders)
			pExtState.seqGrid4 = nil
			
		end -- seqGridRad
		pExtSaveStateF = true	-- set the ext state save flag
	end -- result
end
-- Reset sequencer velocity slider
seqAccSldrText.onRClick = function()
	local debug = false
	if debug or m.debug then ConMsg("\nseqAccSldrText.onLClick()") end
	gfx.x = gfx.mouse_x; gfx.y = gfx.mouse_y
	local result = gfx.showmenu("Reset Accent Sliders")
	if result == 1 then 
		seqAccRSldr.val1 = m.accentLow
		if pExtState.seqAccRSldrLo then pExtState.seqAccRSldrLo = nil end		
		seqAccRSldr.val2 = m.accentHigh
		if pExtState.seqAccRSldrHi then pExtState.seqAccRSldrHi = nil end
		seqAccProbSldr.val1 = m.accentProb
		if pExtState.seqAccProb then pExtState.seqAccProb = nil end
	pExtSaveStateF = true	-- set the ext state save flag
	end -- result
end
-- Reset sequencer legato slider
seqLegSldrText.onRClick = function()
	local debug = false
	if debug or m.debug then ConMsg("\nseqLegSldrText.onLClick()") end
	gfx.x = gfx.mouse_x; gfx.y = gfx.mouse_y
	local result = gfx.showmenu("Reset Legato Slider")
	if result == 1 then 
		seqLegProbSldr.val1 = m.legatoProb
		if pExtState.seqLegProb then pExtState.seqLegProb = nil end
		pExtSaveStateF = true
	end -- result
end
-- Reset sequencer shift
seqShiftText.onRClick = function()
	local debug = false
	if debug or m.debug then ConMsg("\nseqShiftText.onRClick") end
	gfx.x = gfx.mouse_x; gfx.y = gfx.mouse_y
	local result = gfx.showmenu("Reset Note Shift")
	if result == 1 then
		m.seqShift = 0; m.seqShiftMin = 0; m.seqShiftMax = 0
		seqShiftVal.label = tostring(m.seqShift)
		InsertNotes()
	end -- result
end	


--------------------------------------------------------------------------------
-- Euclidiser
--------------------------------------------------------------------------------
-- Euclidiser button
euclidBtn.onLClick = function()
	local debug = false
	if debug or m.debug then ConMsg("\neuclidBtn.onLClick()") end
	if m.activeTake and m.mItem then
		if m.eucF then
			if debug or m.debug then ConMsg("m.eucF = " .. tostring(m.eucF)) end
			GenAccentTable(m.accProbTable, seqAccRSldr, seqAccProbSldr)
			GetNotesFromTake()
			GenBjorklund(euclidPulsesSldr, euclidStepsSldr, euclidRotationSldr, m.accProbTable, seqAccRSldr)
			if m.eucRndNotesF then 
				randomBtn.onLClick() -- call RandomiseNotes
			end
		else -- not m.eucF
			if debug or m.debug then ConMsg("m.eucF = " .. tostring(m.eucF)) end
			GenAccentTable(m.accProbTable, seqAccRSldr, seqAccProbSldr)
			GetNotesFromTake()
			GenNoteAttributes(m.eucAccentF, m.accProbTable, seqAccRSldr, false, m.legProbTable)
			if m.eucRndNotesF then 
				if debug or m.debug then ConMsg("m.eucRndNotesF = " .. tostring(m.eucRndNotesF)) end
				randomBtn.onLClick() -- call RandomiseNotes
			end    
		end -- m.eucF
		-- set project ext state		
		pExtState.eucSliders = {}
		for k, v in pairs(t_euclidSliders) do
			pExtState.eucSliders[k] = v.val1
		end
		pExtSaveStateF = true
	end -- m.activeTake
end
-- Euclidiser options
eucOptionsCb.onLClick = function()
	local debug = false
	if debug or m.debug then ConMsg("\neucOptionsCb.onLClick()") end
	m.eucF = 				 eucOptionsCb.val1[1] == 1 and true or false -- Generate
	m.eucAccentF = 	 eucOptionsCb.val1[2] == 1 and true or false -- Accent
	m.eucRndNotesF = eucOptionsCb.val1[3] == 1 and true or false -- Randomise notes
	pExtState.eucOptionsCb = {m.eucF, m.eucAccentF, m.eucRndNotesF}
	pExtSaveStateF = true
	if debug or m.debug then PrintTable(eucOptionsCb.val1) end
end
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

-- Set default euclid options
function SetDefaultEucOptions()
	local debug = false
	if debug or m.debug then ConMsg("SetDefaultEucOptions()") end
	-- if euclidean options were saved to project state, load them
	if pExtState.eucOptionsCb then 
		m.eucF = 					pExtState.eucOptionsCb[1] ==  true and true or false
		m.eucAccentF = 		pExtState.eucOptionsCb[2] ==  true and true or false
		m.eucRndNotesF = 	pExtState.eucOptionsCb[3] ==  true and true or false
	end
	-- set euclidean options using defaults, or loaded project state
	eucOptionsCb.val1[1] = (true and m.eucF) and 1 or 0 -- generate
	eucOptionsCb.val1[2] = (true and m.eucAccentF) and 1 or 0 -- accents
	eucOptionsCb.val1[3] = (true and m.eucRndNotesF) and 1 or 0 -- randomise notes
end
-- Set default euclid sliders
function SetDefaultEucSliders()
	local debug = false
	if debug or m.debug then ConMsg("SetDefaultEucSliders()") end
	-- if euclidean sliders were saved to project state, load them
	if pExtState.eucSliders then
		for k, v in pairs(t_euclidSliders) do
			v.val1 = pExtState.eucSliders[k]
		end
	else
		euclidPulsesSldr.val1 = m.eucPulses
		euclidStepsSldr.val1 = m.eucSteps
		euclidRotationSldr.val1 = m.eucRot
	end -- load pExtState
end

-- Reset euclidean sliders
txtEuclidLabel.onRClick = function()
	local debug = false
	if debug or m.debug then ConMsg("\ntxtEuclidLabel.onLClick()") end
	gfx.x = gfx.mouse_x; gfx.y = gfx.mouse_y
	local result = gfx.showmenu("Reset Euclid Sliders")
	if result == 1 then 
		euclidPulsesSldr.val1 = m.eucPulses
		euclidStepsSldr.val1 = m.eucSteps
		euclidRotationSldr.val1 = m.eucRot
		pExtSaveStateF = true
		pExtState.eucSliders = nil
	end -- result
end

--------------------------------------------------------------------------------
-- Draw GUI
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
-- GUI Functions END
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- GUI END
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- INIT
--------------------------------------------------------------------------------
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
	
	-- Load ProjectExtState
		if pExtLoadStateF then
			__, pExtStateStr = reaper.GetProjExtState(0, "MEM", "pExtState")
			if pExtStateStr ~= "" then
				pExtState = unpickle(pExtStateStr)
			end -- pExtStateStr
		end -- pExtLoadStateF
		
	-- set GUI defaults or restore from project state
	SetDefaultWindowOpts();	SetDefaultLayer() 
	SetDefaultScaleOpts()
	SetDefaultRndOptions(); SetDefaultRndSliders()
	SetDefaultSeqOptions(); SetDefaultSeqShift()
	SetDefaultSeqGridSliders(); SetDefaultAccLegSliders()
	SetDefaultEucOptions(); SetDefaultEucSliders()
	m.mItem = reaper.GetSelectedMediaItem(0, 0)
	--GetItemLength()
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
	if gfx.mouse_cap & 1 == 1   and gLastMouseCap & 1  == 0 or    -- L mouse
		 gfx.mouse_cap & 2 == 2   and gLastMouseCap & 2  == 0 or    -- R mouse
		 gfx.mouse_cap & 64 == 64 and gLastMouseCap & 64 == 0 then  -- M mouse
		 gMouseOX, gMouseOY = gfx.mouse_x, gfx.mouse_y 
	end
	-- Set modifier keys
	Ctrl  = gfx.mouse_cap & 4  == 4
	Shift = gfx.mouse_cap & 8  == 8
	Alt   = gfx.mouse_cap & 16 == 16
	
	-- Check and save window position
	__, pExtState.win_x, pExtState.win_y, __, __ = gfx.dock(-1,0,0,0,0)
	if m.win_x ~= pExtState.win_x or m.win_y ~= pExtState.win_y then	
		m.win_x = pExtState.win_x
		m.win_y = pExtState.win_y
		pExtSaveStateF = true
	end	
	-- if resized, set scale flag and reset gfx
	if m.zoomF == true then
		e.gScaleState = true
		gfx.quit()
		InitGFX()
		m.zoomF = false
	end	
	
	DrawGUI()
	e.gScaleState = false	-- prevent zoom code from running every loop
	
	-- Save last mouse state since GUI was refreshed
	gLastMouseCap = gfx.mouse_cap
	gLastMouseX, gLastMouseY = gfx.mouse_x, gfx.mouse_y
	gfx.mouse_wheel = 0 -- reset gfx.mouse_wheel
	
	-- Get passthrough key for play/stop (spacebar)
	char = gfx.getchar()
	if char == 32 then reaper.Main_OnCommand(40044, 0) end
	
	-- Defer 'MainLoop' if not explicitly quiting (esc)
	if char ~= -1 and char ~= 27 then 
		reaper.defer(MainLoop) 
	elseif pExtSaveStateF then -- quiting, save script state
		pExtStateStr = pickle(pExtState)
		reaper.SetProjExtState(0, "MEM", "pExtState", pExtStateStr )
		--pExtSaveStateF = false
	end
	
	-- Update Reaper GFX
	gfx.update()
	
	-- check for selected item, midi editor and take
	m.lmItem = m.mItem
	m.lactiveTake = m.activeTake
	m.mItem = reaper.GetSelectedMediaItem(0, 0)
	if m.mItem then
		if m.mItem ~= m.lmItem then 
			m.seqShift = 0; m.seqShiftMin = 0; m.seqShiftMax = 0
			seqShiftVal.label = tostring(m.seqShift)
			m.notebuf.i = 0 -- brutal hack
			PurgeNoteBuf(); NewNoteBuf()
			m.activeEditor, m.activeTake = nil, nil
		end

		m.activeEditor = reaper.MIDIEditor_GetActive()
		if m.activeEditor then
			m.activeTake = reaper.MIDIEditor_GetTake(m.activeEditor)
			
			if m.activeTake ~= m.lactiveTake then GetNotesFromTake() end
			if m.lmItem == nil and m.mItem then GetNotesFromTake() end						
			if m.activeTake then
				ShowMessage(msgText, 0) -- clear old messages
				-- check for changes in the active take if the "Permute" scale is selected		
				if scaleDrop.val2[scaleDrop.val1] == "Permute" then 
					__, pHash = reaper.MIDI_GetHash(m.activeTake, false, 0)
					if m.pHash ~= pHash then
						SetScale("Permute", m.scales, m.preNoteProbTable)
						UpdateSliderLabels(t_noteSliders, m.preNoteProbTable)
						m.pHash = pHash
					end -- m.pHash
					-- don't allow any note options that might upset permute...
					noteOptionsCb.val1[2] = 0; m.rndFirstNoteF = false
					noteOptionsCb.val1[3] = 0; m.rndOctX2F     = false 
				end -- scaleDrop   
				-- check for grid changes
				local grid = m.reaGrid
				m.reaGrid, __, __ = reaper.MIDI_GetGrid(m.activeTake)
				if grid ~= m.reaGrid then 
					GetReaperGrid(seqGridRad)
					seqGridRad.onLClick() -- update the sequence grid sizes
				end -- grid
			else -- handle m.activeTake error
				ShowMessage(msgText, 1) 
				m.activeTake = nil
			end -- m.activeTake
		else -- handle m.activeEditor error
			-- pop up error message - switch layer on textbox element
			ShowMessage(msgText, 1)
			m.activeEditor = nil
			m.activeTake = nil
		end -- m.activeEditor
	else
		ShowMessage(msgText, 2)
		m.mItem = nil
	end
end

--------------------------------------------------------------------------------
-- RUN
--------------------------------------------------------------------------------
InitMidiExMachina()
InitGFX()
MainLoop()
--------------------------------------------------------------------------------