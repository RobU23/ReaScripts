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
@version 1.3.2
@author RobU
@changelog
	v1.3.2
	fixed bug all note sliders at zero causes crash
	added sequencer note shifter (left / right by grid size)
	v1.3
	added monophonic sequence generator
	added euclidean sequence generator (bjorklund algorithm)
	added all/selected notes option
	added force first note to root option
	added randomise octave option
	added permute scale in note randomiser
	added force first note in sequence generator
	added velocity/accent randomisation to sequence/euclidean generators
	added legato randomisation to sequence generator
	added rotation slider to euclidean generator
	added active-take detection
	added undo/redo
	added script state save/restore to Reaper project file
	added right-click reset for sliders (right-click the textbox)
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
-- window
m.win_title = "RobU : MIDI Ex Machina - v1.37"; m.win_dockstate = 0
m.win_x = 10; m.win_y = 10; m.win_w = 900; m.win_h = 280 -- window dimensions
m.win_bg = {0, 0, 0} -- background colour
m.def_zoom = 4 -- 100% (option)
-- zoom values are 1=70, 2=80, 3=90, 4=100, 5=110%, 6=120, 7=140, 8=160, 9=180, 10=200
m.zoomF = false
m.defFont = e.Lucinda; m.defFontSz = 15

-- default octave & key
-- due to some quirk, oct 4 is really oct 3...
m.oct = 4; m.key = 1; m.root = 0 -- (options, except m.root)

-- midi editor, take, grid
m.activeEditor, m.activeTake, m.mediaItem = nil, nil, nil
m.currTake, m.lastTake = "", ""
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
m.seqRepeatF = false -- repeat sequence by grid length
m.seqShiftF = false -- shift sequence by grid length
m.legato = 10 -- default legatolessness value
m.legQ = 240 -- default is 1/16 - is set when changing the grid
m.accentLow = 100; m.accentHigh = 127; m.accentProb = 5 -- default values (options)
-- accentLow/High - min 0, max 127; accentProb - min 0, max 10
m.legatoProb = 5 -- default value (option - min 0, max 10)
m.seqGrid16 = {8, 8, 0, 4} -- sane default sequencer note length slider values
m.seqGrid8  = {0, 8, 2, 2} -- sane default sequencer note length slider values
m.seqGrid4  = {0, 2, 8, 1} -- sane default sequencer note length slider values
m.seqShift = 0; m.seqShiftMin = -16; m.seqShiftMax = 16 -- shift notes left-right from sequencer
m.shiftGlueF = false
m.loopStartG, m.loopLenG, m.loopNum, m.loopMaxRep = 0, 0, 0, 0 -- repeat values for GUI
m.t_loopStart, m.t_loopNum, m.t_loopLen = {}, {}, {} -- repeat value tables
m.loopGlueF = false

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
	{0, 2, 4, 5, 7, 9, 11, 12, name = "Ionian / Major"},
	{0, 2, 3, 5, 6, 9, 10, 12, name = "Dorian"},
	{0, 1, 3, 5, 7, 8, 10, 12, name = "Phrygian"},
	{0, 2, 4, 6, 7, 9, 11, 12, name = "Lyndian"},
	{0, 2, 4, 5, 7, 9, 10, 12, name = "Mixolydian"},
	{0, 2, 3, 5, 7, 8, 10, 12, name = "Aeolian / Minor"},
	{0, 1, 3, 5, 6, 8, 10, 12, name = "Locrian"},
	{0, 3, 5, 6, 7, 10, 12,name = "Blues"},
	{0, 2, 4, 7, 9, 12,name = "Pentatonic Maj"},
	{0, 3, 5, 7, 10, 12,name = "Pentatonic Min"},
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

pExtState = {} -- Reaper project ext state table
pExtStateStr = "" -- pickled string. a nom a nom a nom...
--------------------------------------------------------------------------------
-- GLOBAL VARIABLES END
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Utility Functions Start
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Bitfields - set, clear, flip, or check bits - returns a bitfield, or bool (check)
--------------------------------------------------------------------------------
local function BitSet(bitField, bitIdx)
	return bitField | (1 << bitIdx)
end
--------------------------------------------------------------------------------
local function BitClear(bitField, bitIdx)
	return bitField & ~(1 << bitIdx)
end
--------------------------------------------------------------------------------
local function BitFlip(bitField, bitIdx)
	return bitField ~ (1 << bitIdx)
end
--------------------------------------------------------------------------------
local function BitCheck(bitField, bitIdx)
  return (bitField & (1 << bitIdx) ~= 0) and true or false
end
--------------------------------------------------------------------------------
-- GetSign(n) -return -1 or 1
--------------------------------------------------------------------------------
function GetSign(n)
  return n > 0 and 1 or n < 0 and -1 or 1
end
--------------------------------------------------------------------------------
-- Wrap(n, max) -return n wrapped between 'n' and 'max'
--------------------------------------------------------------------------------
local function Wrap (n, max)
	n = n % max
	if (n < 1) then n = n + max end
	return n
end
--------------------------------------------------------------------------------
-- RGB2Dec(r, g, b) - takes 8 bit r, g, b values, returns decimal (0 to 1)
--------------------------------------------------------------------------------
local function RGB2Dec(r, g, b)
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
	local debug = false
	if debug or m.debug then ConMsg("CopyTable()") end
	
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
		str = str .. "buffer index = " .. tostring(m.notebuf.i)
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
			str = str .. "buffer index = " .. tostring(m.notebuf.i)
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
		m.notebuf.i = m.notebuf.i -1
		if debug or m.debug then
			str = "removed buffer " .. tostring(m.notebuf.i + 1) .. "\n"
			str = str .. "buffer index = " .. tostring(m.notebuf.i)
			ConMsg(str)
		end
	else
		if debug or m.debug then
			str = "nothing to undo...\n"
			str = str .. "buffer index = " .. tostring(m.notebuf.i)
			ConMsg(str)
		end
	end
end
--------------------------------------------------------------------------------
-- PurgeNoteBuf() - purge all note buffers from current+1 to end
--------------------------------------------------------------------------------
local function PurgeNoteBuf()
	local debug = false
	if debug or m.debug then
		ConMsg("PurgeNoteBuf()")
		ConMsg("current idx = " .. tostring(m.notebuf.i))
		ConMsg("max idx     = " .. tostring(m.notebuf.max))
	end
	
	while m.notebuf.max > m.notebuf.i do
		m.notebuf[m.notebuf.max] = nil
		if debug or m.debug then ConMsg("purging buffer " .. tostring(m.notebuf.max)) end
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
	
	mItem = reaper.GetSelectedMediaItem(0, 0)
	if mItem then
		if debug or m.debug then ConMsg("mItem = " .. tostring(mItem)) end
		mItemLen = reaper.GetMediaItemInfo_Value(mItem, "D_LENGTH")
		mBPM, mBPI = reaper.GetProjectTimeSignature2(0)
		msPerMin = 60000
		msPerQN = msPerMin / mBPM
		numQNPerItem = (mItemLen * 1000) / msPerQN
		numBarsPerItem = numQNPerItem / 4
		ItemPPQN = numQNPerItem * m.ppqn
		if debug or m.debug then
			--ConMsg("ItemLen (ms)    = " .. mItemLen)
			--ConMsg("mBPM            = " .. mBPM)
			--ConMsg("MS Per QN       = " .. msPerQN)
			--ConMsg("Num of QNs      = " .. numQNPerItem)
			--ConMsg("Num of Measures = " .. numBarsPerItem)
			ConMsg("Itemlen (ppqn)  = " .. ItemPPQN)
		end
		return math.floor(ItemPPQN)
	end
end
--------------------------------------------------------------------------------
-- GetReaperGrid() - get the current grid size, set global var m.reaGrid
--------------------------------------------------------------------------------
function GetReaperGrid(gridRad)
	local debug = false
	if debug or m.debug then ConMsg("GetReaperGrid()") end
	
	if m.activeTake then
		m.reaGrid, __, __ = reaper.MIDI_GetGrid(m.activeTake) -- returns quarter notes
		if debug or m.debug then ConMsg("m.reaGrid = " .. tostring(m.reaGrid)) end
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
-- Quantise(ppqn) note length quantisation
--------------------------------------------------------------------------------
function Quantise(ppqn)
	local div = math.floor(ppqn / m.legQ + 0.5)
	if div < 1 then div = 1 end
	local leg = ppqn % m.legQ
	return div * m.legQ, leg
end
--------------------------------------------------------------------------------
-- GetNotesFromTake() - fill a note buffer from the active take, returns a table
--------------------------------------------------------------------------------
function GetNotesFromTake()
	local debug = false
	if debug or m.debug then ConMsg("GetNotesFromTake()") end
	
	local i, t
	if m.activeTake then
		local _retval, num_notes, num_cc, num_sysex = reaper.MIDI_CountEvts(m.activeTake)
		if num_notes > 0 then
			t = GetNoteBuf(); if t == nil then t = NewNoteBuf() end
			local div, leg, noteLen
			ClearTable(t)
			for i = 1, num_notes do
				_retval, selected, muted, startppq, endppq, channel, pitch, velocity = reaper.MIDI_GetNote(m.activeTake, i-1)
				t[i] = {}
				t[i][1] = selected
				t[i][2] = muted
				t[i][3] = startppq
				--t[i][3] = Quantise(startppq)
					noteLen = endppq - startppq
					div = math.floor(noteLen / m.legQ + 0.5)
					if div < 1 then div = 1 end
					leg = noteLen % m.legQ
					noteLen = div * m.legQ
				t[i][4] = startppq + noteLen
				--t[i][4], leg = Quantise(endppq)
				t[i][5] = noteLen			
				t[i][6] = channel
				t[i][7] = pitch
				t[i][8] = velocity
				t[i][9] = leg == 0 and true or false
			end -- for i				
		end -- num_notes
		if debug or m.debug then PrintNotes(t) end
		return t
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
		probTable[j] = false
		j = j + 1
	end
	-- legato
	for i = 1, (probSlider.val1) do
		probTable[j] = true
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
	if debug or m.debug then ConMsg("SetScale() - scaleName = " .. tostring(scaleName)) end
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
function RandomiseNotesPoly()
	local debug = false
	if debug or m.debug then ConMsg("RandomiseNotesPoly()") end
	
	m.dupes.i = 1
	local  i = 1
	local t1, t2 = GetNoteBuf(), NewNoteBuf()
	CopyTable(t1, t2)
	
	if debug and m.debug then PrintNotes(t1) end	
	
	while t2[i] do
		if t2[i][1] == true or m.rndAllNotesF then -- if selected, or all notes flag is true
			if i == 1 and m.rndFirstNoteF then -- if selected, the first not is always root of scale
				t2[i][7] = m.root
			else
				t2[i][7] = GetUniqueNote(t1, i, m.noteProbTable, m.octProbTable)
			end
		end
		i = i + 1
	end -- while t1[i]
	
	PurgeNoteBuf()
	if debug and m.debug then PrintNotes(t2) end
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
	
	local t = NewNoteBuf()
	GetReaperGrid() -- populates m.reaGrid
	local itemPos = 0
	local gridSize = m.reaGrid * m.ppqn
	local itemLength = GetItemLength()
	local noteStart, noteEnd, noteLen, noteVel, notLeg = 0, 0, 0, 0, 0
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
				noteLeg = legProbTable[math.random(1, #legProbTable)]
			else
				noteLeg = false
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
			t[noteCount][9] = noteLeg             -- legato
			
		end -- newNote
		
	end -- itemPos < itemLength
	if debug and m.debug then PrintNotes(t) end
	PurgeNoteBuf()
	--if not m.seqRndNotesF then InsertNotes() end
	InsertNotes()
end
--------------------------------------------------------------------------------
-- GenBjorklund(pulses, steps, rotation, accProbTable, accSlider)
--------------------------------------------------------------------------------
function GenBjorklund(pulses, steps, rotation, accProbTable, accSlider)
	local debug = false
	if debug or m.debug then ConMsg("GenBjorklund()") end
	
	local floor = math.floor
	local t = NewNoteBuf()
	GetReaperGrid() -- populates m.reaGrid
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
			t[noteCount][9] = false               -- handle legatolessness
		else
			itemPos = itemPos + gridSize
			restCount = restCount + 1
		end
		
		idx = idx + 1
		idx = Wrap(idx, step)
	end
	
	PurgeNoteBuf()
	--if not m.eucRndNotesF then InsertNotes() end
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
	local gridSize = GetReaperGrid()
	local i = 1
	local div, rem, noteLen
	CopyTable(t1, t2)
	if debug and m.debug then PrintNotes(t2) end
	
	for k, v in pairs(t2) do
		if v[1] then -- selected
			if accF then -- handle accent flag (8 = velocity)
				v[8] = accProbTable[math.random(1, #accProbTable)]
			end -- end accF
			if legF ~= 1 then -- no legato when called by euclid
				if legF then -- handle legato flag 
					v[9] = legProbTable[math.random(1, #legProbTable)]
				end -- legF     
			end -- legF ~= 1
		end -- selected 
	end -- for k, v t2
	
	if debug and m.debug then PrintNotes(t2) end
	PurgeNoteBuf()
	InsertNotes()
end

--------------------------------------------------------------------------------
-- SeqShifter() - shift notes left / right
--------------------------------------------------------------------------------
function SeqShifter(t1)
	local debug = false
	if debug or m.debug then ConMsg("SeqShifter()") end
	
	local gridSize = math.floor(m.reaGrid * m.ppqn)
	local itemLenP = GetItemLength()	
	local noteShift = math.floor(m.seqShift * gridSize)
	local t2 = nil
	
	-- note shifter
	if m.shiftGlueF then
		if debug or m.debug then ConMsg("Shifter glued ...") end	
		t2 = NewNoteBuf() -- new note buffer for glueing
		m.shiftGlueF = false
	else
		if debug or m.debug then ConMsg("Shifter not glued ...") end		
		t2 = {} -- temp table for note shifter (no undo)
	end

	CopyTable(t1, t2)		
	for k, v in pairs(t2) do
		v[3] = v[3] + noteShift
		v[4] = v[4] + noteShift
		if v[3] < 0 then
			v[3] = itemLenP + v[3]
			v[4] = itemLenP + v[4]
			if v[4] > itemLenP then v[4] = itemLenP end
		elseif v[3] >= itemLenP then
			v[3] = v[3] - itemLenP
			v[4] = v[4] - itemLenP
		end
	end -- for k, v t2
	
	return t2
end
--------------------------------------------------------------------------------
-- SeqRepeater() - repeat a range of notes x times
--------------------------------------------------------------------------------
function SeqRepeater(t1)
	local debug = false
	if debug or m.debug then ConMsg("SeqRepeater()") end
	
	local gridSize = math.floor(m.reaGrid * m.ppqn)
	local itemLenP = GetItemLength()	
	local t2 = nil

	-- note repeater
	if m.loopGlueF then
		if debug or m.debug then ConMsg("Repeater glued...") end
		t2 = NewNoteBuf() -- new buffer for repeating
		m.loopGlueF = false
	else
		if debug or m.debug then ConMsg("Repeater not glued...") end
		t2 = {} -- temp table for repeating
	end
	
	local loopStartP = (m.loopStartG -1) * gridSize
	local loopLenP = m.loopLenG * gridSize
	local loopEndP = loopStartP + loopLenP
	local loopNum = m.loopNum
	local i = 1
	local writeOffP = 0
	if loopStartP > 0 then writeOffP = -loopStartP else writeOffP = 0 end

	-- pre-repeat
	if debug or m.debug then ConMsg("pre repeat ...") end
	for k, v in pairs(t1) do 
		if v[3] >= 0 and v[3] < loopStartP then
			t2[i] = {}
			t2[i][1] = v[1] -- selected
			t2[i][2] = v[2] -- muted
			t2[i][3] = v[3] -- startppqn					
			t2[i][4] = v[4] -- endppqn
			--if not t2[i][9] then t2[i][4] = t2[i][4] - m.legato end -- handle legatolessness
			t2[i][5] = v[5] -- length
			t2[i][6] = v[6] -- channel
			t2[i][7] = v[7] -- pitch
			t2[i][8] = v[8] -- vel
			t2[i][9] = v[9] -- legato
			reaper.MIDI_InsertNote(m.activeTake, t2[i][1], t2[i][2], t2[i][3], t2[i][4], t2[i][6], t2[i][7], t2[i][8], false)
			i = i + 1
		end
	end -- k, v in pairs(t1) - pre-repeat
	writeOffP = writeOffP + loopStartP
	
	-- repeat
	if debug or m.debug then ConMsg("repeat ...") end
	while loopNum > 0 do
		for k, v in pairs(t1) do
			if v[3] >= loopStartP and v[3] < loopEndP then
				t2[i] = {}
				t2[i][1] = v[1] -- selected 
				t2[i][2] = v[2] -- muted
				t2[i][3] = v[3] + writeOffP -- startppqn
				if v[4] > loopEndP then t2[i][4] = loopEndP + writeOffP else t2[i][4] = v[4] + writeOffP end -- endppqn
				--if not t2[i][9] then t2[i][4] = t2[i][4] - m.legato end -- handle legatolessness
				t2[i][5] = v[5] -- length
				t2[i][6] = v[6] -- channel
				t2[i][7] = v[7] -- pitch
				t2[i][8] = v[8] -- vel
				t2[i][9] = v[9] -- legato
				reaper.MIDI_InsertNote(m.activeTake, t2[i][1], t2[i][2], t2[i][3], t2[i][4], t2[i][6], t2[i][7], t2[i][8], false)
				i = i + 1
			end -- if v[3]
			
		end -- for k, v t1 - repeat
		loopNum = loopNum - 1
		writeOffP = writeOffP + loopLenP
	end -- while loopNum > 0

	-- post-repeat
	if debug or m.debug then ConMsg("post repeat ...") end
	local written = loopStartP + (loopLenP * m.loopNum)	
	local remLenP = itemLenP - written	
	local readStartP = loopStartP + loopLenP
	local readEndP = readStartP + remLenP
	local writeOffP = written - readStartP
	
	for k, v in pairs(t1) do
		if v[3] >= readStartP and v[3] < readEndP then
			t2[i] = {}
			t2[i][1] = v[1] -- selected 
			t2[i][2] = v[2] -- muted
			t2[i][3] = v[3] + writeOffP -- startppqn
			if v[4] > itemLenP then t2[i][4] = itemLenP else t2[i][4] = v[4] + writeOffP end -- endppqn
			--if not t2[i][9] then t2[i][4] = t2[i][4] - m.legato end -- handle legatolessness
			t2[i][5] = v[5] -- channel
			t2[i][6] = v[6] -- channel
			t2[i][7] = v[7] -- pitch
			t2[i][8] = v[8] -- vel
			t2[i][9] = v[9] -- legato
			reaper.MIDI_InsertNote(m.activeTake, t2[i][1], t2[i][2], t2[i][3], t2[i][4], t2[i][6], t2[i][7], t2[i][8], false)
			i = i + 1
		end			
	end -- k, v in pairs(t1) - post-repeat
	
	return t2
		
end
--------------------------------------------------------------------------------
-- InsertNotes() - insert current note buffer in the active take
--------------------------------------------------------------------------------
function InsertNotes()
	local debug = false
	if debug or m.debug then ConMsg("InsertNotes()") end
	
	local t1, t2, t3 = GetNoteBuf(), nil, nil

	-- note shifter
	if m.seqShiftF then
		t2 = SeqShifter(t1)
	else
		t2 = {}; CopyTable(t1, t2)
	end

	-- note repeater
	if m.seqRepeatF then 
		t3 = SeqRepeater(t2)
	else
		t3 = {}; CopyTable(t2, t3)
	end

	DeleteNotes()
	for k, v in pairs(t3) do
		v[4] = Quantise(v[4])
		if not v[9] then v[4] = v[4] - m.legato end -- handle legatolessness
		reaper.MIDI_InsertNote(m.activeTake, v[1], v[2], v[3], v[4], v[6], v[7], v[8], false)	
	end -- for k, v t3
		
	reaper.MIDI_Sort(m.activeTake)
	reaper.MIDIEditor_OnCommand(m.activeEditor, 40435) -- all notes off
	
end
--------------------------------------------------------------------------------
-- PrintNotes - arg note_buffer t; print note_buffer to reaper console
--------------------------------------------------------------------------------
function PrintNotes(t) -- debug code
	local debug = false
	if debug or m.debug then ConMsg("PrintNotes()") end
	
	if not t then return end
	local i = 1
	local str = "sel \t mut \t s_ppq \t e_ppq \t leng \t chan \t pitch \t vel \t leg \n"
	
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
	
	if not t then return end
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
local zoomDrop = e.Droplist:new({0}, 5, 5, 40, 22, e.col_green, "", m.defFont, m.defFontSz, e.col_grey8, 4, {"70%", "80%", "90%", "100%", "110%", "120%", "140%", "160%", "180%", "200%"})
local winText  = e.Textbox:new({0}, 45, 5, m.win_w - 50, 22, e.col_green, "MIDI Ex Machina    ", m.defFont, m.defFontSz, e.col_grey8)
local layerBtn01 = e.Button:new({0}, 5, m.win_h - 25, 100, 20, e.col_green, "Randomiser", m.defFont, m.defFontSz, e.col_grey8)
local layerBtn02 = e.Button:new({0}, 105, m.win_h - 25, 100, 20, e.col_grey5, "Sequencer", m.defFont, m.defFontSz, e.col_grey7)
local layerBtn03 = e.Button:new({0}, 205, m.win_h - 25, 100, 20, e.col_grey5, "Euclidiser", m.defFont, m.defFontSz, e.col_grey7)
local layerBtn04 = e.Button:new({0}, 305, m.win_h - 25, 100, 20, e.col_grey5, "Options", m.defFont, m.defFontSz, e.col_grey7)
local undoBtn = e.Button:new({0}, m.win_w-85, m.win_h -25, 40, 20, e.col_grey5, "Undo", m.defFont, m.defFontSz, e.col_grey7)
local redoBtn = e.Button:new({0}, m.win_w-45, m.win_h -25, 40, 20, e.col_grey5, "Redo", m.defFont, m.defFontSz, e.col_grey7)
-- Persistent window element table
local t_winElements = {winFrame, zoomDrop, winText, undoBtn, redoBtn}
local t_winLayers = {layerBtn01, layerBtn02, layerBtn03, layerBtn04}
--------------------------------------------------------------------------------
-- Common Elements
--------------------------------------------------------------------------------
-- key, octave, & scale droplists
dx, dy, dw, dh = 25, 70, 100, 20
local keyDrop = e.Droplist:new({1, 2, 3}, dx, dy,		 dw, dh, e.col_blue, "Root Note", m.defFont, m.defFontSz, e.col_grey8, m.key, m.notes)
local octDrop = e.Droplist:new({1, 2, 3}, dx, dy + 45, dw, dh, e.col_blue, "Octave ", m.defFont, m.defFontSz, e.col_grey8, m.oct,{0, 1, 2, 3, 4, 5, 6, 7})
local scaleDrop = e.Droplist:new({1, 2, 3}, dx, dy + 90, dw, dh, e.col_blue, "Scale", m.defFont, m.defFontSz, e.col_grey8, 1, m.scalelist)
local t_Droplists = {keyDrop, octDrop, scaleDrop} 

--------------------------------------------------------------------------------
-- Randomiser Layer
--------------------------------------------------------------------------------
-- note randomise button
local randomBtn = e.Button:new({1}, 25, 205, 100, 25, e.col_green, "Generate", m.defFont, m.defFontSz, e.col_grey8)
-- note weight sliders
local nx, ny, nw, nh, np = 160, 50, 30, 150, 40
local noteSldr01 = e.Vert_Slider:new({1}, nx,        ny, nw, nh, e.col_blue, "", m.defFont, m.defFontSz, e.col_grey8, 1, 0, 0, 12, 1)
local noteSldr02 = e.Vert_Slider:new({1}, nx+(np*1), ny, nw, nh, e.col_blue, "", m.defFont, m.defFontSz, e.col_grey8, 1, 0, 0, 12, 1)
local noteSldr03 = e.Vert_Slider:new({1}, nx+(np*2), ny, nw, nh, e.col_blue, "", m.defFont, m.defFontSz, e.col_grey8, 1, 0, 0, 12, 1)
local noteSldr04 = e.Vert_Slider:new({1}, nx+(np*3), ny, nw, nh, e.col_blue, "", m.defFont, m.defFontSz, e.col_grey8, 1, 0, 0, 12, 1)
local noteSldr05 = e.Vert_Slider:new({1}, nx+(np*4), ny, nw, nh, e.col_blue, "", m.defFont, m.defFontSz, e.col_grey8, 1, 0, 0, 12, 1)
local noteSldr06 = e.Vert_Slider:new({1}, nx+(np*5), ny, nw, nh, e.col_blue, "", m.defFont, m.defFontSz, e.col_grey8, 1, 0, 0, 12, 1)
local noteSldr07 = e.Vert_Slider:new({1}, nx+(np*6), ny, nw, nh, e.col_blue, "", m.defFont, m.defFontSz, e.col_grey8, 1, 0, 0, 12, 1)
local noteSldr08 = e.Vert_Slider:new({1}, nx+(np*7), ny, nw, nh, e.col_blue, "", m.defFont, m.defFontSz, e.col_grey8, 1, 0, 0, 12, 1)
local noteSldr09 = e.Vert_Slider:new({1}, nx+(np*8), ny, nw, nh, e.col_blue, "", m.defFont, m.defFontSz, e.col_grey8, 1, 0, 0, 12, 1)
local noteSldr10 = e.Vert_Slider:new({1}, nx+(np*9), ny, nw, nh, e.col_blue, "", m.defFont, m.defFontSz, e.col_grey8, 1, 0, 0, 12, 1)
local noteSldr11 = e.Vert_Slider:new({1}, nx+(np*10), ny, nw, nh, e.col_blue, "", m.defFont, m.defFontSz, e.col_grey8, 1, 0, 0, 12, 1)
local noteSldr12 = e.Vert_Slider:new({1}, nx+(np*11), ny, nw, nh, e.col_blue, "", m.defFont, m.defFontSz, e.col_grey8, 1, 0, 0, 12, 1)
local noteSldr13 = e.Vert_Slider:new({1}, nx+(np*12), ny, nw, nh, e.col_blue, "", m.defFont, m.defFontSz, e.col_grey8, 1, 0, 0, 12, 1)
-- Note probability slider table
local t_noteSliders = {noteSldr01, noteSldr02, noteSldr03, noteSldr04, noteSldr05, noteSldr06, noteSldr07,
	noteSldr08, noteSldr09, noteSldr10, noteSldr11, noteSldr12, noteSldr13}
-- Note probability slider label (Textbox) - right-click to reset all
local probSldrText = e.Textbox:new({1}, nx, 210, 510, 20, e.col_grey5, "Note Weight Sliders", m.defFont, m.defFontSz, e.col_grey7)
-- Note octave doubler probability slider
local octProbSldr = e.Vert_Slider:new({1}, nx+(np*13) + 10,  ny, nw, nh, e.col_blue, "%", m.defFont, m.defFontSz, e.col_grey8, m.rndOctProb, 0, 0, 10, 1)
local octProbText = e.Textbox:new({1}, nx+(np*13) + 10, 210, (nw), 20, e.col_grey5, "Oct", m.defFont, m.defFontSz, e.col_grey7) 
-- Note randomiser options
local noteOptionsCb = e.Checkbox:new({1}, nx+(np*15)-10, ny+30, 30, 30, e.col_orange, "", m.defFont, m.defFontSz, e.col_grey8, {0,0,0},   {"All / Sel Notes", "1st Note = Root", "Octave X2"})
local noteOptionText = e.Textbox:new({1}, nx+(np*14)+20, 210, (nw*4), 20, e.col_grey5, "Options", m.defFont, m.defFontSz, e.col_grey7)

--------------------------------------------------------------------------------
-- Sequencer Layer
--------------------------------------------------------------------------------
-- sequence generate button
local sequenceBtn = e.Button:new({2}, 25, 205, 100, 25, e.col_yellow, "Generate", m.defFont, m.defFontSz, e.col_grey8)
local sx, sy, sw, sh, sp = 140, 50, 30, 150, 40
-- sequencer grid size radio selector
local seqGridRad = e.Rad_Button:new({2,3}, sx, sy + 40, 30, 30, e.col_yellow, "", m.defFont, m.defFontSz, e.col_grey8, 1, {"1/16", "1/8", "1/4"})
local seqGridText = e.Textbox:new({2,3}, sx+5, 210, (sw*2)+5, 20, e.col_grey5, "Grid Size", m.defFont, m.defFontSz, e.col_grey7)
-- sequence grid probability sliders
local seqSldr16   = e.Vert_Slider:new({2}, sx+(sp*2)+20,  sy, sw, sh, e.col_blue, "1/16",  m.defFont, m.defFontSz, e.col_grey8, 0, 0, 0, m.defFontSz, 1)
local seqSldr8    = e.Vert_Slider:new({2}, sx+(sp*3)+20,  sy, sw, sh, e.col_blue, "1/8",   m.defFont, m.defFontSz, e.col_grey8, 0, 0, 0, m.defFontSz, 1)
local seqSldr4    = e.Vert_Slider:new({2}, sx+(sp*4)+20,  sy, sw, sh, e.col_blue, "1/4",   m.defFont, m.defFontSz, e.col_grey8, 0, 0, 0, m.defFontSz, 1)
local seqSldrRest = e.Vert_Slider:new({2}, sx+(sp*5)+20,  sy, sw, sh, e.col_blue, "Rest",  m.defFont, m.defFontSz, e.col_grey8, 0, 0, 0, m.defFontSz, 1)
-- sequence grid probability slider table
local t_seqSliders = {seqSldr16, seqSldr8, seqSldr4, seqSldrRest}
-- sequence grid probability sliders label - right click to reset all (per grid size selection)
local seqSldrText = e.Textbox:new({2}, sx+(sp * 2)+20, 210, (sw * 5), 20, e.col_grey5, "Size Weight Sliders", m.defFont, m.defFontSz, e.col_grey7)

-- velocity accent slider (shared with Euclid layer)
local seqAccRSldr  = e.V_Rng_Slider:new({2,3},  sx+(sp*7), sy, sw, sh, e.col_blue, "", m.defFont, m.defFontSz, e.col_grey8, m.accentLow, m.accentHigh, 0, 127, 1)
local seqAccProbSldr = e.Vert_Slider:new({2,3}, sx+(sp*8), sy, sw, sh, e.col_blue, "%", m.defFont, m.defFontSz, e.col_grey8, m.accentProb, 0, 0, 10, 1)
local seqAccSldrText = e.Textbox:new({2,3},     sx+(sp*7), 210, (sw * 2) + 10, 20, e.col_grey5, "Vel  |  Acc", m.defFont, m.defFontSz, e.col_grey7)

-- legato slider
local seqLegProbSldr = e.Vert_Slider:new({2}, sx+(sp * 9), sy, sw, sh, e.col_blue, "%", m.defFont, m.defFontSz, e.col_grey8, m.legatoProb, 0, 0, 10, 1)
local seqLegSldrText = e.Textbox:new({2},     sx+(sp * 9), 210, sw, 20, e.col_grey5, "Leg", m.defFont, m.defFontSz, e.col_grey7)

-- repeat dropboxes
local seqLoopStartDrop = e.Droplist:new({2}, sx+(sp*10)+25, sy+15,  sw*2, 20, e.col_blue,  "Start",  m.defFont, m.defFontSz, e.col_grey8, m.loopStartG, m.t_loopStart)
local seqLoopLenDrop   = e.Droplist:new({2}, sx+(sp*10)+25, sy+65,  sw*2, 20, e.col_blue,  "Length", m.defFont, m.defFontSz, e.col_grey8, m.loopLenG, m.t_loopLen)
local seqLoopNumDrop   = e.Droplist:new({2}, sx+(sp*10)+25, sy+115, sw*2, 20, e.col_blue,  "Amount", m.defFont, m.defFontSz, e.col_grey8, m.loopNum, m.t_loopNum)
local seqLoopText      = e.Textbox:new({2},  sx+(sp*10)+25, 210,    sw*2, 20, e.col_grey5, "Repeat", m.defFont, m.defFontSz, e.col_grey7)

-- sequence shift buttons
local seqShiftLBtn = e.Button:new({2},  sx+(sp*12)+30, sy+sh-25, sw-5,    25, e.col_blue, "<<", m.defFont, m.defFontSz, e.col_grey8)
local seqShiftVal  = e.Textbox:new({2}, sx+(sp*13)+15, sy+sh-25, sw,      25, e.col_grey5, tostring(m.seqShift), m.defFont, m.defFontSz, e.col_grey7)
local seqShiftRBtn = e.Button:new({2},  sx+(sp*14)+5,  sy+sh-25, sw-5,    25, e.col_blue, ">>", m.defFont, m.defFontSz, e.col_grey8)
local seqShiftText = e.Textbox:new({2}, sx+(sp*12)+30, 210,      sw*3-10, 20, e.col_grey5, "Shift Notes", m.defFont, m.defFontSz, e.col_grey7)

-- Sequencer options
local seqOptionsCb = e.Checkbox:new({2}, sx+(np * 15) + 10, sy + 5, 30, 30, e.col_orange, "", m.defFont, m.defFontSz, e.col_grey8, {0,0,0,0,0}, {"Generate", "Force 1st Note", "Accent", "Legato", "Rnd Notes", "Repeat"})

--------------------------------------------------------------------------------
-- Euclid Layer
--------------------------------------------------------------------------------
-- euclid generate button
local euclidBtn = e.Button:new({3}, 25, 205, 100, 25, e.col_orange, "Generate", m.defFont, m.defFontSz, e.col_grey8)
-- euclidean sliders
local ex, ey, ew, eh, ep = 160, 50, 30, 150, 40
local euclidPulsesSldr = e.Vert_Slider:new({3}, ex+(ep*2), ey, ew, eh, e.col_blue, "Puls", m.defFont, m.defFontSz, e.col_grey8, m.eucPulses, 0, 1, 24, 1)
local euclidStepsSldr = e.Vert_Slider:new({3}, ex+(ep*3), ey, ew, eh, e.col_blue, "Step", m.defFont, m.defFontSz, e.col_grey8, m.eucSteps, 0, 1, 24, 1)
local euclidRotationSldr = e.Vert_Slider:new({3}, ex+(ep*4), ey, ew, eh, e.col_blue, "Rot",  m.defFont, m.defFontSz, e.col_grey8, m.eucRot, 0, 0, 24, 1)
local t_euclidSliders = {euclidPulsesSldr, euclidStepsSldr, euclidRotationSldr}
-- euclid slider label - right click to reset all
local txtEuclidLabel = e.Textbox:new({3}, ex + (ep * 2), 210, (ew * 3) + 20, 20, e.col_grey5, "Euclid Sliders", m.defFont, m.defFontSz, e.col_grey7)
-- Sequencer options
local eucOptionsCb = e.Checkbox:new({3},  ex + (ep * 15)- 10, ey + 40, 30, 30, e.col_orange, "", m.defFont, m.defFontSz, e.col_grey8, {0,0,0}, {"Generate", "Accent", "Rnd Notes"})

--------------------------------------------------------------------------------
-- Options Layer
--------------------------------------------------------------------------------
local optText = e.Textbox:new({4}, m.win_x + 10, m.win_y + 30, m.win_w - 40, m.win_h - 80, e.col_grey5, "Nothing to see here, yet...", m.defFont, m.defFontSz, e.col_grey8)

--------------------------------------------------------------------------------
-- Messages Layer
--------------------------------------------------------------------------------
local msgText = e.Textbox:new({9}, m.win_x + 10, m.win_y + 30, m.win_w - 40, m.win_h - 80, e.col_greym, "", m.defFont, 22, e.col_grey9)

--------------------------------------------------------------------------------
-- Shared Element Tables
--------------------------------------------------------------------------------
local t_Buttons = {randomBtn, sequenceBtn, seqShiftLBtn, seqShiftRBtn, euclidBtn}
local t_Checkboxes = {noteOptionsCb, seqOptionsCb, eucOptionsCb}
local t_Droplists2 = {seqLoopLenDrop, seqLoopNumDrop, seqLoopStartDrop}
local t_RadButtons = {seqGridRad}
local t_RSliders = {octProbSldr, seqAccRSldr, seqAccProbSldr, seqLegProbSldr}
local t_Textboxes = {probSldrText, octProbText, seqGridText, seqSldrText, seqShiftVal, seqLoopText, seqShiftText, seqAccSldrText, seqLegSldrText, txtEuclidLabel, optText, msgText}
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
	pExtState.zoomDrop = zoomDrop.val1
	
	if debug or m.debug then ConMsg("zoom = " .. tostring(e.gScale)) end
	
	-- set soom 
	if pExtState.win_x ~= m.win_x then
		__, m.win_x, m.win_y, __, __ = gfx.dock(-1,0,0,0,0)
	pExtState.win_x = m.win_x
	pExtState.win_y = m.win_y
	end
		
	m.zoomF = true
end
-- Layer 1 button
layerBtn01.onLClick = function() -- randomiser
	local debug = false
	if debug or m.debug then ConMsg("\nlayerBtn01.onLClick() (note randomiser)") end
	-- set active layer
	e.gActiveLayer = 1
	-- set zoom and window text elements to highlight colour
	zoomDrop:getSetColour(e.col_green)
	winText:getSetColour(e.col_green)
	-- reset all layer buttons to default colour
	for k, v in pairs(t_winLayers) do
		v:getSetColour(e.col_grey5)
		v:getSetLabelColour(e.gol_grey7)
	end
	-- set current layer to highlight colour
	layerBtn01:getSetColour(e.col_green)	
	layerBtn01:getSetLabelColour(e.col_grey8)
	-- set zoom state flag
	e.gScaleState = true
	-- set project ext state
	pExtState.activeLayer = e.gActiveLayer
		
end
-- Layer 2 button
layerBtn02.onLClick = function() -- sequencer
	local debug = false
	if debug or m.debug then ConMsg("\nlayerBtn02.onLClick() (sequencer)") end
	-- set active layer
	e.gActiveLayer = 2
	-- set zoom and window text elements to highlight colour
	zoomDrop:getSetColour(e.col_yellow)
	winText:getSetColour(e.col_yellow)
	-- reset all layer buttons to default colour
	for k, v in pairs(t_winLayers) do
		v:getSetColour(e.col_grey5)
		v:getSetLabelColour(e.gol_grey7)
	end
	-- set current layer to highlight colour
	layerBtn02:getSetColour(e.col_yellow)	
	layerBtn02:getSetLabelColour(e.col_grey8)
	-- set zoom state flag
	e.gScaleState = true
	-- set project ext state
	pExtState.activeLayer = e.gActiveLayer	
end
-- Layer 3 button
layerBtn03.onLClick = function() -- euclidean
	local debug = false
	if debug or m.debug then ConMsg("\nlayerBtn03.onLClick() (euclid)") end
	-- set active layer
	e.gActiveLayer = 3
	-- set zoom and window text elements to highlight colour
	zoomDrop:getSetColour(e.col_orange)
	winText:getSetColour(e.col_orange)
	-- reset all layer buttons to default colour
	for k, v in pairs(t_winLayers) do
		v:getSetColour(e.col_grey5)
		v:getSetLabelColour(e.gol_grey7)
	end
	-- set current layer to highlight colour
	layerBtn03:getSetColour(e.col_orange)	
	layerBtn03:getSetLabelColour(e.col_grey8)
	-- set zoom state flag	
	e.gScaleState = true
	-- set project ext state
	pExtState.activeLayer = e.gActiveLayer	
end
-- Layer 4 button
layerBtn04.onLClick = function() -- options
	local debug = false
	if debug or m.debug then ConMsg("\nlayerBtn04.onLClick() (options)") end
	-- set active layer
	e.gActiveLayer = 4
	-- set zoom and window text elements to highlight colour
	zoomDrop:getSetColour(e.col_grey5)
	winText:getSetColour(e.col_grey5)
	-- reset all layer buttons to default colour
	for k, v in pairs(t_winLayers) do
		v:getSetColour(e.col_grey5)
		v:getSetLabelColour(e.gol_grey7)
	end
	-- set current layer to highlight colour
	layerBtn04:getSetColour(e.col_grey6)	
	layerBtn04:getSetLabelColour(e.col_grey8)
	-- set zoom state flag
	e.gScaleState = true
	-- set project ext state
	pExtState.activeLayer = e.gActiveLayer	
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
		if debug or m.debug then ConMsg("nothing to redo...") end  
	end
end
-- Set default window options
function SetDefaultWindowOpts()
	local debug = false
	if debug or m.debug then ConMsg("SetDefaultWinOpts()") end
	
	if pExtState.zoomDrop then
		zoomDrop.val1 = pExtState.zoomDrop
	end
	
	if pExtState.win_x then -- set the windown position
		m.win_x = pExtState.win_x
		m.win_y = pExtState.win_y
	end
	
	zoomDrop.onLClick()
end
-- Set default layer
function SetDefaultLayer()
	local debug = false
	if debug or m.debug then ConMsg("SetDefaultLayer()") end
	
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
-- Set randomiser default options
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
-- Randomiser options toggle logic
noteOptionsCb.onLClick = function()
	local debug = false
	if debug or m.debug then ConMsg("noteOptionsCb.onLClick()") end
	
	m.rndAllNotesF =  noteOptionsCb.val1[1] == 1 and true or false -- All / Sel Notes
	m.rndFirstNoteF = noteOptionsCb.val1[2] == 1 and true or false -- 1st Note Root
	m.rndOctX2F =     noteOptionsCb.val1[3] == 1 and true or false -- Octave X2
	
	pExtState.noteOptionsCb = {m.rndAllNotesF, m.rndFirstNoteF, m.rndOctX2F}

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

-- Set randomiser note slider defaults
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
-- Reset randomiser note sliders
probSldrText.onRClick = function()
	local debug = false
	if debug or m.debug then ConMsg("\nprobSldrText.onRClick()") end
	
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
	end -- result
end

-- Reset octave slider
octProbText.onRClick = function()
	local debug = false
	if debug or m.debug then ConMsg("\noctProbText.onRClick()") end
	
	gfx.x = gfx.mouse_x; gfx.y = gfx.mouse_y
	local result = gfx.showmenu("Reset Octave Slider")
	
	if result == 1 then 
		octProbSldr.val1 = m.rndOctProb
		if pExtState.rndOctProb then -- write the new proj ext state
				pExtState.rndOctProb = nil
		end -- pExtState.noteSliders
	end -- result
end

--------------------------------------------------------------------------------
-- Sequencer
--------------------------------------------------------------------------------
-- Set sequencer options defaults
function SetDefaultSeqOptions()
	local debug = false
	if debug or m.debug then ConMsg("SetDefaultSeqOptions()") end
	
	-- if sequencer options were saved to project state, load them
	if pExtState.seqOptionsCb then 
		m.seqF          = pExtState.seqOptionsCb[1] ==  true and true or false
		m.seqFirstNoteF = pExtState.seqOptionsCb[2] ==  true and true or false
		m.seqAccentF    = pExtState.seqOptionsCb[3] ==  true and true or false
		m.seqLegatoF    = pExtState.seqOptionsCb[4] ==  true and true or false
		m.seqRndNotesF  = pExtState.seqOptionsCb[5] ==  true and true or false
		m.seqRepeatF    = pExtState.seqOptionsCb[6] ==  true and true or false
	end
	
	-- set sequencer options using defaults, or loaded project state
	seqOptionsCb.val1[1] = (true and m.seqF) and 1 or 0 -- generate
	seqOptionsCb.val1[2] = (true and m.seqFirstNoteF) and 1 or 0 -- 1st Note Always
	seqOptionsCb.val1[3] = (true and m.seqAccentF) and 1 or 0 -- accent
	seqOptionsCb.val1[4] = (true and m.seqLegatoF) and 1 or 0 -- legato
	seqOptionsCb.val1[5] = (true and m.seqRndNotesF) and 1 or 0 -- random notes
	seqOptionsCb.val1[6] = (true and m.seqRepeatF) and 1 or 0 -- repeat
	
	-- store the project state
	pExtState.seqOptionsCb = {m.seqF, m.seqFirstNoteF, m.seqAccentF, m.seqLegatoF, m.seqRndNotesF, m.seqRepeatF}
end
-- Sequencer options toggle logic 
seqOptionsCb.onLClick = function()
	local debug = false
	if debug or m.debug then ConMsg("seqOptionsCb.onLClick()") end
	
	m.seqF          = seqOptionsCb.val1[1] == 1 and true or false -- Generate
	m.seqFirstNoteF = seqOptionsCb.val1[2] == 1 and true or false -- 1st Note Always
	m.seqAccentF    = seqOptionsCb.val1[3] == 1 and true or false -- Accent
	m.seqLegatoF    = seqOptionsCb.val1[4] == 1 and true or false -- Legato
	m.seqRndNotesF  = seqOptionsCb.val1[5] == 1 and true or false -- Randomise Notes
	m.seqRepeatF    = seqOptionsCb.val1[6] == 1 and true or false -- Repeat
	
	if pExtState.seqOptionsCb then
		if pExtState.seqOptionsCb[6] ~= m.seqRepeatF then InsertNotes() end
	else
		if m.seqRepeatF then InsertNotes() end
	end
	
	pExtState.seqOptionsCb = {m.seqF, m.seqFirstNoteF, m.seqAccentF, m.seqLegatoF, m.seqRndNotesF, m.seqRepeatF}

	if debug or m.debug then PrintTable(seqOptionsCb.val1) end
end

-- Set sequencer grid slider defaults
function SetDefaultSeqGridSliders()
	local debug = false
	if debug or m.debug then ConMsg("SetDefaultSeqGridSliders()") end

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
	end -- result
end

-- Set sequencer accent & legato slider defaults
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
end -- function
-- Reset sequencer velocity slider
seqAccSldrText.onRClick = function()
	local debug = false
	if debug or m.debug then ConMsg("\nseqAccSldrText.onRClick()") end
	
	gfx.x = gfx.mouse_x; gfx.y = gfx.mouse_y
	local result = gfx.showmenu("Reset Accent Sliders")
	
	if result == 1 then 
		seqAccRSldr.val1 = m.accentLow
		if pExtState.seqAccRSldrLo then pExtState.seqAccRSldrLo = nil end		
		seqAccRSldr.val2 = m.accentHigh
		if pExtState.seqAccRSldrHi then pExtState.seqAccRSldrHi = nil end
		seqAccProbSldr.val1 = m.accentProb
		if pExtState.seqAccProb then pExtState.seqAccProb = nil end
	end -- result
end
-- Reset sequencer legato sliders
seqLegSldrText.onRClick = function()
	local debug = false
	if debug or m.debug then ConMsg("\nseqLegSldrText.onLClick()") end
	
	gfx.x = gfx.mouse_x; gfx.y = gfx.mouse_y
	local result = gfx.showmenu("Reset Legato Slider")
	
	if result == 1 then 
		seqLegProbSldr.val1 = m.legatoProb
		if pExtState.seqLegProb then pExtState.seqLegProb = nil end
	end -- result
end

-- Set sequence shifter defaults
function SetDefaultSeqShift()
	local debug = false
	if debug or m.debug then ConMsg("SetDefaultSeqShift()") end
	
	m.seqShift = 0
	m.seqShiftMin = 0
	m.seqShiftMax = 0
	seqShiftVal.label = tostring(m.seqShift)
end
-- Reset sequence shifter
function ResetSeqShifter()
	local debug = false
	if debug or m.debug then ConMsg("ResetSeqShifter()") end
	
	m.seqShiftF = false	
	m.seqShift = 0; m.seqShiftMin = 0; m.seqShiftMax = 0
	seqShiftVal.label = tostring(m.seqShift)
end
-- Glue sequence shifter
function GlueSeqShifter()
	local debug = false
	if debug or m.debug then ConMsg("GlueSeqShifter()") end
	m.shiftGlueF = true
	m.seqRepeatF = seqOptionsCb.val1[6] == 1 and true or false -- Turn off repeat if on...
	InsertNotes()
	m.seqShift = 0; m.seqShiftMin = 0; m.seqShiftMax = 0 -- reset shift on new sequence
	seqShiftVal.label = tostring(m.seqShift)
	m.seqShiftF = false
    m.seqRepeatF = seqOptionsCb.val1[6] == 1 and true or false -- Turn on repeat
	InsertNotes()
end
-- Right-click handler
seqShiftText.onRClick = function()
	local debug = false
	if debug or m.debug then ConMsg("\nseqShiftText.onRClick") end
	
	gfx.x = gfx.mouse_x; gfx.y = gfx.mouse_y
	local result = gfx.showmenu("Reset Note Shift|Glue Shift")

	if result == 1 then
		ResetSeqShifter()
		InsertNotes()
	elseif result == 2 then
		GlueSeqShifter()
	end -- result
end	
-- Sequence shifter left
seqShiftLBtn.onLClick = function()
	local debug = false
	if debug or m.debug then ConMsg("\nseqShiftLBtn()") end
	
	local gridSize = m.reaGrid * m.ppqn
	local itemLength = GetItemLength()
	m.seqShiftMin = -(math.floor(itemLength / gridSize)-1)
	
	if m.seqShift <= m.seqShiftMin then
		m.seqShift = 0
		m.seqShiftF = false
	else
		m.seqShift = m.seqShift - 1
		m.seqShiftF = true
	end
	
	seqShiftVal.label = tostring(m.seqShift)
	InsertNotes()
end
-- Sequence shifter right
seqShiftRBtn.onLClick = function()
	local debug = false
	if debug or m.debug then ConMsg("\nseqShiftRBtn()") end
	
	local gridSize = m.reaGrid * m.ppqn
	local itemLength = GetItemLength()
	m.seqShiftMax = math.floor(itemLength / gridSize) - 1

	if m.seqShift >= m.seqShiftMax then 
		m.seqShift = 0
		m.seqShiftF = false
	else
		m.seqShift = m.seqShift + 1
		m.seqShiftF = true
	end	

	seqShiftVal.label = tostring(m.seqShift)
	InsertNotes()
end

-- Set default sequencer repeater state
function SetDefaultSeqRepeat()
	local debug = false
	if debug or m.debug then ConMsg("SetDefaultSeqRepeat()") end
	
	GetReaperGrid() -- sets m.reaGrid (.25 / 0.5 / 0.1)
	local gridSize = m.reaGrid * m.ppqn
	local itemLength = GetItemLength()
	
	-- start
		m.loopStartG = 1
		seqLoopStartDrop.val1 = m.loopStartG
	
	-- length
		m.loopLenG = 1
		seqLoopLenDrop.val1 = m.loopLenG	
	
	-- amount
		m.loopNum = 1
		seqLoopNumDrop.val1 = m.loopNum

	m.loopMaxRep = math.floor(itemLength / gridSize)
	
	for i = 1, m.loopMaxRep do
		seqLoopStartDrop.val2[i] = i
		seqLoopNumDrop.val2[i] = i
		seqLoopLenDrop.val2[i] = i
	end
end
-- Reset sequencer repeater
function ResetSeqRepeater()
	local debug = false
	if debug or m.debug then ConMsg("ResetSeqRepeater()") end
	-- reset the GUI and repeat flag
	m.seqRepeatF = false 
	seqOptionsCb.val1[6] = (true and m.seqRepeatF) and 1 or 0
	-- reset the drop down lists
	seqLoopStartDrop.val1 = 1; m.loopStartG = 1
	seqLoopLenDrop.val1 = 1; m.loopLenG = 1
	seqLoopNumDrop.val1 = 1; m.loopNum = 1
	-- save state
	pExtState.seqOptionsCb[6] = m.seqRepeatF
end
-- Glue sequencer repeater
function GlueSeqRepeater()
	local debug = false
	if debug or m.debug then ConMsg("GlueSeqRepeater()") end
	m.loopGlueF = true		
	InsertNotes()
	
	-- reset the shifter (implicit when glueing the loop)
	ResetSeqShifter()
	
	-- reset the GUI and repeat flag
	ResetSeqRepeater()
	
	-- reset the drop down lists and pExtState
	seqLoopStartDrop.val1 = 1; m.loopStartG = 1
	seqLoopLenDrop.val1 = 1; m.loopLenG = 1
	seqLoopNumDrop.val1 = 1; m.loopNum = 1
end
-- Right-click handler
seqLoopText.onRClick = function()
	local debug = false
	if debug or m.debug then ConMsg("\nseqLoopText.onRClick") end
	
	gfx.x = gfx.mouse_x; gfx.y = gfx.mouse_y
	local result = gfx.showmenu("Reset Repeat|Glue Repeat")

	if result == 1 then 
		ResetSeqRepeater()
		InsertNotes()
	elseif result == 2 then
		GlueSeqRepeater()
	end -- result
	
end -- onRClick
-- Sequencer repeater functions
seqLoopStartDrop.onLClick = function()
	local debug = false
	if debug or m.debug then ConMsg("\nseqLoopStartDrop.onLClick()") end
	
	GetReaperGrid() -- sets m.reaGrid (.25 / 0.5 / 0.1)
	local gridSizeP = m.reaGrid * m.ppqn
		if debug or m.debug then ConMsg("gridSizeP  = " .. tostring(gridSizeP)) end	
	local itemLenP = GetItemLength()
		if debug or m.debug then ConMsg("itemLenP   = " .. tostring(itemLenP)) end		
	local itemLenG = math.floor(itemLenP / gridSizeP)
		if debug or m.debug then ConMsg("itemLenG   = " .. tostring(itemLenG)) end	
	local remLenG = itemLenG - (seqLoopStartDrop.val1 -1)
		if debug or m.debug then ConMsg("remLenG    = " .. tostring(remLenG)) end	 	
	
	-- set the start point lookup table
	for i = 1, itemLenG do
		seqLoopStartDrop.val2[i] = i
		m.t_loopStart[i] = i
	end
	m.loopStartG = seqLoopStartDrop.val1
	
	-- check the loop length doesn't exceed the remaining item length
	if seqLoopLenDrop.val1 > remLenG then seqLoopLenDrop.val1 = remLenG end
	seqLoopLenDrop.val2 = {}
	for i = 1, remLenG do
		seqLoopLenDrop.val2[i] = i
	end			
	m.loopLenG = seqLoopLenDrop.val1
	
	-- check the loop amount doesn't exceed the remaining item length
	while seqLoopNumDrop.val1 * m.loopLenG > remLenG do
		seqLoopNumDrop.val1 = seqLoopNumDrop.val1 - 1
	end
	seqLoopNumDrop.val2 = {}
	local maxLoops = math.floor(remLenG / m.loopLenG)
	for i = 1, maxLoops do
		seqLoopNumDrop.val2[i] = i
	end	
	m.loopNum = seqLoopNumDrop.val1
	
	if m.seqRepeatF then InsertNotes() end

	if debug or m.debug then ConMsg("m.loopStartG = " .. tostring(m.loopStartG)) end
	if debug or m.debug then ConMsg("m.loopLenG   = " .. tostring(m.loopLenG)) end
	if debug or m.debug then ConMsg("m.loopNum    = " .. tostring(m.loopNum)) end	

end
-- Sequencer repeat length
seqLoopLenDrop.onLClick = function()
	local debug = false
	if debug or m.debug then ConMsg("\nseqLoopLenDrop.onLClick()") end
	
	GetReaperGrid() -- sets m.reaGrid (.25 / 0.5 / 0.1)
	local gridSizeP = m.reaGrid * m.ppqn
		if debug or m.debug then ConMsg("gridSizeP  = " .. tostring(gridSizeP)) end	
	local itemLenP = GetItemLength()
		if debug or m.debug then ConMsg("itemLenP   = " .. tostring(itemLenP)) end		
	local itemLenG = math.floor(itemLenP / gridSizeP)
		if debug or m.debug then ConMsg("itemLenG   = " .. tostring(itemLenG)) end	
	local remLenG = itemLenG - (seqLoopStartDrop.val1 -1)
		if debug or m.debug then ConMsg("remLenG    = " .. tostring(remLenG)) end	 	
	
	-- check the loop length doesn't exceed the remaining item length
	if seqLoopLenDrop.val1 > remLenG then seqLoopLenDrop.val1 = remLenG end
	seqLoopLenDrop.val2 = {}
	for i = 1, remLenG do
		seqLoopLenDrop.val2[i] = i
	end			
	m.loopLenG = seqLoopLenDrop.val1
	
	-- check the loop amount doesn't exceed the remaining item length
	while seqLoopNumDrop.val1 * m.loopLenG > remLenG do
		seqLoopNumDrop.val1 = seqLoopNumDrop.val1 - 1
	end
	seqLoopNumDrop.val2 = {}
	local maxLoops = math.floor(remLenG / m.loopLenG)
	for i = 1, maxLoops do
		seqLoopNumDrop.val2[i] = i
	end	
	m.loopNum = seqLoopNumDrop.val1
	
	if m.seqRepeatF then InsertNotes() end

	if debug or m.debug then ConMsg("m.loopStartG = " .. tostring(m.t_loopStart[m.loopStartG])) end
	if debug or m.debug then ConMsg("m.loopLenG   = " .. tostring(m.loopLenG)) end
	if debug or m.debug then ConMsg("m.loopNum    = " .. tostring(m.loopNum)) end	
end
-- Sequencer repeat amount
seqLoopNumDrop.onLClick = function()
	local debug = false
	if debug or m.debug then ConMsg("\nseqLoopNumDrop.onLClick()") end
	
	GetReaperGrid() -- sets m.reaGrid (.25 / 0.5 / 0.1)
	local gridSizeP = m.reaGrid * m.ppqn
		if debug or m.debug then ConMsg("gridSizeP  = " .. tostring(gridSizeP)) end	
	local itemLenP = GetItemLength()
		if debug or m.debug then ConMsg("itemLenP   = " .. tostring(itemLenP)) end		
	local itemLenG = math.floor(itemLenP / gridSizeP)
		if debug or m.debug then ConMsg("itemLenG   = " .. tostring(itemLenG)) end	
	local remLenG = itemLenG - (seqLoopStartDrop.val1 -1)
		if debug or m.debug then ConMsg("remLenG    = " .. tostring(remLenG)) end	 	
	
	-- check the loop amount doesn't exceed the remaining item length
	while seqLoopNumDrop.val1 * m.loopLenG > remLenG do
		seqLoopNumDrop.val1 = seqLoopNumDrop.val1 - 1
	end
	seqLoopNumDrop.val2 = {}
	local maxLoops = math.floor(remLenG / m.loopLenG)
	for i = 1, maxLoops do
		seqLoopNumDrop.val2[i] = i
	end	
	m.loopNum = seqLoopNumDrop.val1
	
	if m.seqRepeatF then InsertNotes() end

	if debug or m.debug then ConMsg("m.loopStartG = " .. tostring(m.t_loopStart[m.loopStartG])) end
	if debug or m.debug then ConMsg("m.loopLenG   = " .. tostring(m.loopLenG)) end
	if debug or m.debug then ConMsg("m.loopNum    = " .. tostring(m.loopNum)) end	
end

--------------------------------------------------------------------------------
-- Euclidiser
--------------------------------------------------------------------------------
-- Set euclid default options
function SetDefaultEucOptions()
	local debug = false
	if debug or m.debug then ConMsg("SetDefaultEucOptions()") end
	
	-- if euclidean options were saved to project state, load them
	if pExtState.eucOptionsCb then 
		m.eucF         = pExtState.eucOptionsCb[1] ==  true and true or false
		m.eucAccentF   = pExtState.eucOptionsCb[2] ==  true and true or false
		m.eucRndNotesF = pExtState.eucOptionsCb[3] ==  true and true or false
	end
	
	-- set euclidean options using defaults, or loaded project state
	eucOptionsCb.val1[1] = (true and m.eucF) and 1 or 0 -- generate
	eucOptionsCb.val1[2] = (true and m.eucAccentF) and 1 or 0 -- accents
	eucOptionsCb.val1[3] = (true and m.eucRndNotesF) and 1 or 0 -- randomise notes
end

-- Euclidiser options logic
eucOptionsCb.onLClick = function()
	local debug = false
	if debug or m.debug then ConMsg("eucOptionsCb.onLClick()") end
	
	m.eucF         = eucOptionsCb.val1[1] == 1 and true or false -- Generate
	m.eucAccentF   = eucOptionsCb.val1[2] == 1 and true or false -- Accent
	m.eucRndNotesF = eucOptionsCb.val1[3] == 1 and true or false -- Randomise notes
	
	pExtState.eucOptionsCb = {m.eucF, m.eucAccentF, m.eucRndNotesF}

	if debug or m.debug then PrintTable(eucOptionsCb.val1) end
end

-- Set euclid slider defaults
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
-- Reset euclid sliders
txtEuclidLabel.onRClick = function()
	local debug = false
	if debug or m.debug then ConMsg("\ntxtEuclidLabel.onLClick()") end
	
	gfx.x = gfx.mouse_x; gfx.y = gfx.mouse_y
	local result = gfx.showmenu("Reset Euclid Sliders")
	
	if result == 1 then 
		euclidPulsesSldr.val1 = m.eucPulses
		euclidStepsSldr.val1 = m.eucSteps
		euclidRotationSldr.val1 = m.eucRot
		pExtState.eucSliders = nil
	end -- result
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

-- Main action elements
-- Randomiser
randomBtn.onLClick = function()
	local debug = false
	if debug or m.debug then ConMsg("\nrandomBtn.onLClick()") end
	if not m.activeTake then return end

	-- turn off and reset shifter and repeater
	ResetSeqShifter()
	ResetSeqRepeater()
	--InsertNotes()
	-- generate the probability tables
	GenProbTable(m.preNoteProbTable, t_noteSliders, m.noteProbTable)
	if #m.noteProbTable == 0 then return end
	GenOctaveTable(m.octProbTable, octProbSldr)
	GetNotesFromTake() -- grab the current take data
	RandomiseNotesPoly()
	
	-- set project ext state	
	pExtState.noteSliders = {}
	for k, v in pairs(t_noteSliders) do
		pExtState.noteSliders[k] = v.val1
	end
	pExtState.rndOctProb = octProbSldr.val1
end 
-- Sequencer
sequenceBtn.onLClick = function()
	local debug = false
	if debug or m.debug then ConMsg("\nsequenceBtn.onLClick()") end
	if not m.activeTake then return end
	
	-- turn off and reset shift
	local t_shift = table.pack(m.seqShift, m.seqShiftMin, m.seqShiftMax) -- required?
	ResetSeqShifter()
	
	-- backup repeat
		local t_repeat = table.pack(m.loopStartG, m.loopLenG, m.loopNum, m.seqRepeatF)	
	
	if m.seqF then
		if m.seqRepeatF then -- temporarily turn off repeat, if it was on
			m.seqRepeatF = false -- remember it was on...
			m.seqRepeatState = true
			seqOptionsCb.val1[6] = (true and m.seqRepeatF) and 1 or 0
			seqLoopStartDrop.val1 = 1; m.loopStartG = 1
			seqLoopLenDrop.val1   = 1; m.loopLenG   = 1
			seqLoopNumDrop.val1   = 1; m.loopNum    = 1
			InsertNotes()
		end	
		SetSeqGridSizes(t_seqSliders)
		GenProbTable(m.preSeqProbTable, t_seqSliders, m.seqProbTable)
		GenAccentTable(m.accProbTable, seqAccRSldr, seqAccProbSldr)
		GenLegatoTable(m.legProbTable, seqLegProbSldr)
		GetNotesFromTake()
		GenSequence(m.seqProbTable, m.accProbTable, seqAccRSldr, m.legProbTable)
		if m.seqRndNotesF then randomBtn.onLClick() end
		-- restore and turn on repeat, if it was previously on...
		if m.seqRepeatState then
			m.loopStartG, m.loopLenG, m.loopNum, m.seqRepeatF = table.unpack(t_repeat)
			seqLoopNumDrop.val1   = m.loopNum	
			seqOptionsCb.val1[6] = (true and m.seqRepeatF) and 1 or 0
			seqLoopStartDrop.val1 = m.loopStartG
			seqLoopLenDrop.val1   = m.loopLenG
			seqLoopNumDrop.val1   = m.loopNum
			InsertNotes()
			m.seqRepeatState = false
		end
		-- if m.seqRepeatF then InsertNotes() end		
		
	else -- not m.seqF
		GenAccentTable(m.accProbTable, seqAccRSldr, seqAccProbSldr)
		GenLegatoTable(m.legProbTable, seqLegProbSldr)
		GetNotesFromTake() 
		GenNoteAttributes(m.seqAccentF, m.accProbTable, seqAccRSldr, m.seqLegatoF, m.legProbTable)
		
		if m.seqRndNotesF then randomBtn.onLClick() end		
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
	pExtState.seqOptionsCb = {m.seqF, m.seqFirstNoteF, m.seqAccentF, m.seqLegatoF, m.seqRndNotesF, m.seqRepeatF}
	pExtState.seqAccRSldrLo = seqAccRSldr.val1
	pExtState.seqAccRSldrHi = seqAccRSldr.val2
	pExtState.seqAccProb = seqAccProbSldr.val1
	pExtState.seqLegProb = seqLegProbSldr.val1
end
-- Sequencer grid toggle logic
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

	-- turn off and reset shifter and repeater
	ResetSeqShifter()
	ResetSeqRepeater()
	InsertNotes()
	end -- m.activeTake
end
-- Euclidiser
euclidBtn.onLClick = function()
	local debug = false
	if debug or m.debug then ConMsg("\neuclidBtn.onLClick()") end
	
	-- turn off and reset shifter and repeater
	ResetSeqShifter()
	ResetSeqRepeater()
	InsertNotes()
	if m.activeTake then
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
	end -- m.activeTake
end

--------------------------------------------------------------------------------
-- Draw GUI
--------------------------------------------------------------------------------
function DrawGUI()
	for key, winElms in pairs(t_winElements) do winElms:draw() end
	for key, winLays in pairs(t_winLayers) do winLays:draw() end
	--for key, frame in pairs(t_Frames) do frame:draw() end 
	for key, check in pairs(t_Checkboxes) do check:draw() end
	for key, radio in pairs(t_RadButtons) do radio:draw() end	
	for key, btn in pairs(t_Buttons) do btn:draw() end
	for key, dlist in pairs(t_Droplists) do dlist:draw() end
	for key, dlist2 in pairs(t_Droplists2) do dlist2:draw() end 
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
		if debug or m.debug then ConMsg("activeEditor = " .. tostring(m.activeEditor)) end
		m.activeTake = reaper.MIDIEditor_GetTake(m.activeEditor)
		if m.activeTake then
			m.lastTake = nil
			if debug or m.debug then ConMsg("activeTake = " .. tostring(m.activeTake)) end
			__ = NewNoteBuf()
			-- get the take's parent media item
			m.mediaItem = reaper.GetMediaItemTake_Item(m.activeTake)
			reaper.SetMediaItemSelected(m.mediaItem, true)
			reaper.UpdateArrange()
			-- get some item info
			GetItemLength()
			GetNotesFromTake() -- grab the original note data (if any...)
		end
		if not m.activeTake then ConMsg("InitMidiExMachina() - No Active Take") end
	end -- m.activeEditor
	
	-- Load ProjectExtState
	__, pExtStateStr = reaper.GetProjExtState(0, "MEM", "pExtState")
	if pExtStateStr ~= "" then 
		pExtState = unpickle(pExtStateStr)
	end -- pExtStateStr
		
	-- set GUI defaults or restore from project state
	SetDefaultWindowOpts();	SetDefaultLayer() 
	SetDefaultScaleOpts()
	SetDefaultRndOptions(); SetDefaultRndSliders()
	SetDefaultSeqOptions(); SetDefaultSeqShift(); SetDefaultSeqRepeat()
	SetDefaultSeqGridSliders(); SetDefaultAccLegSliders()
	SetDefaultEucOptions(); SetDefaultEucSliders()

	-- some pExtState stuff required early...
	if not pExtState.seqOptionsCb then pExtState.seqOptionsCb = {} end
	if debug or m.debug then ConMsg("End InitMidiExMachina()") end
end
--------------------------------------------------------------------------------
-- InitGFX
--------------------------------------------------------------------------------
function InitGFX()
	local debug = false
	if debug or m.debug then ConMsg("\nInitGFX()") end
	
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
	local debug = false
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
	
	-- if resized, set scale flag and reset gfx
	if m.zoomF == true then
		if debug or m.debug then ConMsg("m.zoomF == true") end
		e.gScaleState = true
		gfx.quit()
		InitGFX()
		m.zoomF = false
	end	
	
	DrawGUI()
	e.gScaleState = false	-- prevent zoom code from running every loop
	
	-- Save or reset last mouse state since GUI was refreshed
	gLastMouseCap = gfx.mouse_cap
	gLastMouseX, gLastMouseY = gfx.mouse_x, gfx.mouse_y
	gfx.mouse_wheel = 0 -- reset gfx.mouse_wheel
	
	-- Get passthrough key for play/stop (spacebar)
	char = gfx.getchar()
	if char == 32 then reaper.Main_OnCommand(40044, 0) end
	
	-- Defer 'MainLoop' if not explicitly quiting (esc)
	if char ~= -1 and char ~= 27 then 
		reaper.defer(MainLoop) 
	else
		if debug or m.debug then ConMsg("quitting.....") end

		InsertNotes() -- capture any shifted or repeated notes
		
		-- Check and save window position
		__, pExtState.win_x, pExtState.win_y, __, __ = gfx.dock(-1,0,0,0,0)
		
		-- Pickle 
		pExtStateStr = pickle(pExtState)
		reaper.SetProjExtState(0, "MEM", "pExtState", pExtStateStr )

	end
	
	-- Update Reaper GFX
	gfx.update()
	
	-- check for midi editor, take, and media item
	m.activeEditor = reaper.MIDIEditor_GetActive()
	if m.activeEditor then
		m.activeTake = reaper.MIDIEditor_GetTake(m.activeEditor)
		if m.activeTake then
			if m.activeTake ~= m.lastTake then
				if debug or m.debug then ConMsg("\nswitched MIDI item...") end
				-- reset shift and repeat
				ResetSeqShifter()
				ResetSeqRepeater()
				-- purge undo/redo buffers and grab new note data
				m.notebuf.i = 1
				PurgeNoteBuf()
				t = GetNoteBuf()
				ClearTable(t)
				m.lastTake = m.activeTake
				GetNotesFromTake()
			end
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
end

--------------------------------------------------------------------------------
-- RUN
--------------------------------------------------------------------------------
InitMidiExMachina()
InitGFX()
MainLoop()
--------------------------------------------------------------------------------