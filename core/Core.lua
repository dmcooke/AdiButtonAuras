--[[
AdiButtonAuras - Display auras on action buttons.
Copyright 2013-2023 Adirelle (adirelle@gmail.com)
All rights reserved.

This file is part of AdiButtonAuras.

AdiButtonAuras is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

AdiButtonAuras is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with AdiButtonAuras. If not, see <http://www.gnu.org/licenses/>.
--]]

local addonName, addon = ...

local _G = _G
local CloseAllWindows = _G.CloseAllWindows
local CreateFrame = _G.CreateFrame
local error = _G.error
local format = _G.format
local GetAddOnInfo = _G.GetAddOnInfo
local GetCVarBool = _G.GetCVarBool
local geterrorhandler = _G.geterrorhandler
local GetModifiedClick = _G.GetModifiedClick
local gsub = _G.gsub
local hooksecurefunc = _G.hooksecurefunc
local ipairs = _G.ipairs
local IsAddOnLoaded = _G.IsAddOnLoaded
local IsInGroup = _G.IsInGroup
local IsInRaid = _G.IsInRaid
local LoadAddOn = _G.LoadAddOn
local next = _G.next
local NUM_ACTIONBAR_BUTTONS = _G.NUM_ACTIONBAR_BUTTONS
local NUM_PET_ACTION_SLOTS = _G.NUM_PET_ACTION_SLOTS
local NUM_STANCE_SLOTS = _G.NUM_STANCE_SLOTS
local pairs = _G.pairs
local print = _G.print
local select = _G.select
local strmatch = _G.strmatch
local tinsert = _G.tinsert
local tonumber = _G.tonumber
local tostring = _G.tostring
local tremove = _G.tremove
local type = _G.type
local UnitExists = _G.UnitExists
local UnitGUID = _G.UnitGUID
local UnitIsUnit = _G.UnitIsUnit
local wipe = _G.wipe
local xpcall = _G.xpcall
local assert = _G.assert
local UnitClass = _G.UnitClass

local L = addon.L

-- API
local api = {}
addon.api = api
_G.AdiButtonAuras = api

------------------------------------------------------------------------------
-- Default config
------------------------------------------------------------------------------

addon.DEFAULT_SETTINGS = {
	profile = {
		enabled = { ['*'] = true },
		rules = { ['*'] = true },
		missing = { ['*'] = "none" },
		missingThreshold = { ['*'] = 0 },
		flashPromotion = { ['*'] = false },
		colors = {
			good            = { 0.0, 1.0, 0.0, 0.7 },
			bad             = { 1.0, 0.0, 0.0, 0.7 },
			Curse           = { 0.6, 0.0, 1.0, 1.0 },
			Disease         = { 0.6, 0.4, 0.0, 1.0 },
			Magic           = { 0.2, 0.6, 1.0, 1.0 },
			Poison          = { 0.0, 0.6, 0.0, 1.0 },
			Enrage          = { 0.9, 0.6, 0.1, 1.0 },
			countdownLow    = { 1.0, 0.0, 0.0 },
			countdownMedium = { 1.0, 1.0, 0.0 },
			countdownHigh   = { 1.0, 1.0, 1.0 },
			countAtMax      = { 1.0, 0.0, 0.0 },
		},
		maxCountdown = 600,
		minMinutes = 600,
		minMinuteSecs = 60,
		maxTenth = 3,
		noFlashOnCooldown = false,
		noFlashOutOfCombat = false,
		hints = "show",
		fontSize = 13,
		textPosition = "BOTTOM",
		textXOffset = 2,
		textYOffset = 2,
		highlightTexture = "default",
		debuggingTooltip = false,
	},
	global = {
		userRules = {
			['**'] = {
				enabled = true,
				scope = "ALL",
				title = "",
				code = "",
			}
		},
	},
}

------------------------------------------------------------------------------
-- Keep track of used libraries and their version
------------------------------------------------------------------------------

local libraries = {}
local function GetLib(major, silent)
	local lib, minor = LibStub(major, silent)
	libraries[major] = minor
	return lib, minor
end
addon.libraries, addon.GetLib = libraries, GetLib

------------------------------------------------------------------------------
-- Stuff to embed
------------------------------------------------------------------------------

if AdiDebug then
	AdiDebug:Embed(addon, addonName)
	addon.GetName = function() return addonName end
else
	addon.Debug = function() end
end

local mixins = {}
-- Event dispatching using CallbackHandler-1.0
local events = GetLib('CallbackHandler-1.0'):New(mixins, 'RegisterEvent', 'UnregisterEvent', 'UnregisterAllEvents')
local frame = CreateFrame("Frame")
frame:SetScript('OnEvent', function(_, ...) return events:Fire(...) end)
function events:OnUsed(_, event) return frame:RegisterEvent(event) end
function events:OnUnused(_, event) return frame:UnregisterEvent(event) end

-- Messaging using CallbackHandler-1.0
local bus = GetLib('CallbackHandler-1.0'):New(mixins, 'RegisterMessage', 'UnregisterMessage', 'UnregisterAllMessages')
addon.SendMessage = bus.Fire

local messages = {}
function bus:OnUsed(_, message)
	addon.Debug('Messages', 'OnUsed', message)
	if messages[message] and messages[message].OnUsed then
		messages[message].OnUsed(message)
	end
end
function bus:OnUnused(_, message)
	addon.Debug('Messages', 'OnUnused', message)
	if messages[message] and messages[message].OnUnused then
		messages[message].OnUnused(message)
	end
end
function mixins:DeclareMessage(message, OnUsed, OnUnused)
	messages[message] = { OnUsed = OnUsed, OnUnused = OnUnused }
end
function mixins:IsDeclaredMessage(str)
	return str and messages[str] and true
end

for name, func in pairs(mixins) do
	addon[name] = func
	api[name] = func
end

------------------------------------------------------------------------------
-- LibSharedMedia-3.0 stuff
------------------------------------------------------------------------------

local LSM = GetLib('LibSharedMedia-3.0')
local HIGHLIGHT_MEDIATYPE = LSM.MediaType.BUTTON_HIGHLIGHT
addon.HIGHLIGHT_MEDIATYPE = HIGHLIGHT_MEDIATYPE

-- Initialize the default font
do
	local default = LSM:GetDefault(LSM.MediaType.FONT)

	local wantedFile = _G.NumberFontNormalSmall:GetFont()
	for name, file in pairs(LSM:HashTable(LSM.MediaType.FONT)) do
		if file == wantedFile then
			default = name
			break
		end
	end

	addon.DEFAULT_SETTINGS.profile.fontName = default
end

------------------------------------------------------------------------------
-- Event names
------------------------------------------------------------------------------

local CONFIG_CHANGED = addonName..'_Config_Changed'
local THEME_CHANGED = addonName..'_Theme_Changed'
local RULES_UPDATED = addonName..'_Rules_Updated'

addon.RULES_UPDATED = RULES_UPDATED
addon.CONFIG_CHANGED = CONFIG_CHANGED
addon.THEME_CHANGED = THEME_CHANGED

------------------------------------------------------------------------------
-- Initialization
------------------------------------------------------------------------------

local function UpdateHandler(event, button)
	local overlay = addon:GetOverlay(button)
	if overlay and overlay:IsVisible() then
		overlay:ApplySkin()
		return overlay:UpdateAction(event)
	end
end

local function UpdateHandlerForButton(button)
	return UpdateHandler('ActionButton_Update', button)
end

local hookedFrames = {}
local function RegisterDominos()
	for _, button in next, _G.Dominos.ActionButtons do
		if not hookedFrames[button] then
			hookedFrames[button] = true
			hooksecurefunc(button, 'Update', UpdateHandlerForButton)
		end
	end
end

local labs = {}
function api:RegisterLAB(libName)
	assert(type(libName) == "string", format("Bad argument to 'RegisterLAB', expected string, got '%s'", type(libName)))

	if not libName:match("LibActionButton%-1%.0") then
		error(format("Bad argument to 'RegisterLAB', expected 'LibActionButton-1.0*', got '%s'", libName), 2)
	end

	if not labs[libName] then
		local lib = GetLib(libName, true)
		if lib then
			lib.RegisterCallback(addon, 'OnButtonCreated', UpdateHandler)
			lib.RegisterCallback(addon, 'OnButtonUpdate', UpdateHandler)
			for button in pairs(lib:GetAllButtons()) do
				local _ = addon:GetOverlay(button)
			end
			labs[libName] = true
		end
	end
end

function addon:ADDON_LOADED(event, name)
	if name ~= addonName then
		return
	end
	self:UnregisterEvent(event)
	self[event] = nil

	self:Initialize()

	if IsAddOnLoaded('Dominos') then
		_G.Dominos.RegisterCallback(addon, 'LAYOUT_LOADED', RegisterDominos)
	end

	if IsAddOnLoaded('Bartender4') then
		self:ScanButtons("BT4Button", 120)
		self:ScanButtons("BT4PetButton", NUM_PET_ACTION_SLOTS)
		self:ScanButtons("BT4StanceButton", NUM_STANCE_SLOTS)
	end

	-- LibActionButton support
	api:RegisterLAB('LibActionButton-1.0')
	api:RegisterLAB('LibActionButton-1.0-ElvUI')
	api:RegisterLAB('LibActionButton-1.0-nMainbar')
end

addon:RegisterEvent('ADDON_LOADED')

function addon:Initialize()
	self.db = GetLib('AceDB-3.0'):New(addonName.."DB", self.DEFAULT_SETTINGS, true)

	-- migrate SV from old inverted to new missing
	local profile = self.db.profile
	if profile.inverted then
		for key in pairs(profile.inverted) do
			if profile.flashPromotion[key] then
				profile.missing[key] = "flash"
				profile.flashPromotion[key] = nil
			else
				profile.missing[key] = "highlight"
			end
		end
		profile.inverted = nil
	end

	self.db.RegisterCallback(self, "OnProfileChanged")
	self.db.RegisterCallback(self, "OnProfileCopied", "OnProfileChanged")
	self.db.RegisterCallback(self, "OnProfileReset", "OnProfileChanged")

	GetLib('LibDualSpec-1.0'):EnhanceDatabase(self.db, addonName)

	self:ScanButtons("ActionButton", NUM_ACTIONBAR_BUTTONS)
	self:ScanButtons("BonusActionButton", NUM_ACTIONBAR_BUTTONS)
	self:ScanButtons("MultiBarRightButton", NUM_ACTIONBAR_BUTTONS)
	self:ScanButtons("MultiBarLeftButton", NUM_ACTIONBAR_BUTTONS)
	self:ScanButtons("MultiBarBottomRightButton", NUM_ACTIONBAR_BUTTONS)
	self:ScanButtons("MultiBarBottomLeftButton", NUM_ACTIONBAR_BUTTONS)
	self:ScanButtons("StanceButton", NUM_STANCE_SLOTS)
	self:ScanButtons("PetActionButton", NUM_PET_ACTION_SLOTS)

	for _, actionBarButton in next, _G.ActionBarButtonEventsFrame.frames do
		hookedFrames[actionBarButton] = true
		hooksecurefunc(actionBarButton, 'Update', UpdateHandlerForButton)
	end

	hooksecurefunc(_G.PetActionBar, "Update", function()
		for _, button in next, _G.PetActionBar.actionButtons do
			UpdateHandler("PetActionBar_Update", button)
		end
	end)

	hooksecurefunc(_G.StanceBar, "UpdateState", function()
		for _, button in next, _G.StanceBar.actionButtons do
			UpdateHandler("StanceBar_UpdateState", button)
		end
	end)

	self:RegisterEvent('UPDATE_MACROS')

	self:UpdateDynamicUnitConditionals()

	local LibSpellbook = GetLib('LibSpellbook-1.0')
	LibSpellbook.RegisterCallback(addon, 'LibSpellbook_Spells_Changed')
	if LibSpellbook:HasSpells() then
		addon:LibSpellbook_Spells_Changed('OnLoad')
	end

	LSM.RegisterCallback(self, "LibSharedMedia_SetGlobal", "OnMediaUpdate")
	LSM.RegisterCallback(self, "LibSharedMedia_Registered", "OnMediaUpdate")

	self:SendMessage(CONFIG_CHANGED)
	self:SendMessage(THEME_CHANGED)
end

function addon:OnProfileChanged()
	self:SendMessage(CONFIG_CHANGED)
end

function addon:OnMediaUpdate(event, mediatype)
	if mediatype == LSM.MediaType.FONT or mediatype == HIGHLIGHT_MEDIATYPE then
		self:SendMessage(THEME_CHANGED)
	end
end

------------------------------------------------------------------------------
-- Rule loading and updating
------------------------------------------------------------------------------

local builders
local initializers = {}

local rules, descriptions = {}, {}
addon.rules = rules
addon.descriptions = descriptions

local function errorhandler(msg)
	addon:Debug('|cffff0000'..tostring(msg)..'|r')
	return geterrorhandler()(msg)
end

local function GetBuilders(event)
	if not builders then
		addon:Debug('Initializing rules', event)
		if #initializers == 0 then
			error("No rules registered !", 2)
		end
		local t = {}
		for i, initializer in ipairs(initializers) do
			local ok, result = xpcall(initializer, errorhandler)
			if ok and result then
				tinsert(t, result)
			end
		end
		builders = addon.AsList(t, "function")
		addon:Debug(#builders, 'builders found')
	end
	return builders
end

function addon:LibSpellbook_Spells_Changed(event)
	self:Debug(event)
	wipe(rules)
	wipe(descriptions)
	for _, builder in ipairs(GetBuilders(event)) do
		xpcall(builder, errorhandler)
	end
	self:SendMessage(RULES_UPDATED)
end

function addon.api:RegisterRules(initializer)
	tinsert(initializers, addon.Restricted(initializer))
	if builders then
		addon:Debug('Rebuilding rules')
		builders = nil
		return addon:LibSpellbook_Spells_Changed('RegisterRules')
	end
end

function addon:GetActionConfiguration(actionType, actionId)
	if actionType == "empty" or actionType == "unsupported" or actionType == "hidden" then
		return nil, false, nil
	end
	assert(actionType == "item" or actionType == "spell", format("Invalid action type: %q", tostring(actionType)))
	local key = actionType..':'..actionId
	local rule = rules[key]
	if rule then
		return rule, self.db.profile.enabled[key], key
	else
		return nil, false, key
	end
end

function addon.isClass(class)
	return class == 'ALL' or class == select(2, UnitClass("player"))
	--@debug@
	--	or true
	--@end-debug@
end

------------------------------------------------------------------------------
-- Handle configuration
------------------------------------------------------------------------------

-- The loading handler
function addon:OpenConfiguration(args)
	local loaded, why

	-- Replace the handler to avoid infinite recursive loops
	addon.OpenConfiguration = function()
		if not loaded then
			print(format('|cffff0000[%s] %s: %s|r', addonName, L["Could not load configuration panel"], _G["ADDON_"..why]))
		end
	end

	-- Load the configuration addon
	loaded, why = LoadAddOn(addonName..'_Config')
	if loaded then
		CloseAllWindows()
		CloseAllWindows()
		_G.Settings.OpenToCategory(addonName)
	end

	-- Forward the arguments
	return addon:OpenConfiguration(args)
end

-- The slash command
_G.SLASH_ADIBUTTONAURAS1 = "/adibuttonauras"
_G.SLASH_ADIBUTTONAURAS2 = "/aba"
_G.SlashCmdList["ADIBUTTONAURAS"] = function(args) return addon:OpenConfiguration(args) end

-- Used to register the actual configuration GUI, with access to internals
function addon.api:CreateConfig(func)
	return func(addonName, addon)
end

------------------------------------------------------------------------------
-- Group roster update
------------------------------------------------------------------------------

local GROUP_CHANGED = addonName..'_Group_Changed'
local groupPrefix, groupSize = "", 0
local groupUnits = {}
addon.GROUP_CHANGED, addon.groupUnits = GROUP_CHANGED, groupUnits

function addon:GROUP_ROSTER_UPDATE(event)
	local prefix, start, size = "", 1, 0
	if IsInRaid() then
		prefix, size = "raid", 40
	elseif IsInGroup() then
		prefix, start, size = "party", 0, 4
	else
		start = 0
	end
	if prefix ~= groupPrefix then
		wipe(groupUnits)
	end
	local changed = false
	for i = start, size do
		local unit, petUnit
		if i == 0 then
			unit, petUnit = "player", "pet"
		else
			unit, petUnit = prefix..i, prefix..'pet'..i
		end
		local guid, petGUID = UnitGUID(unit), UnitGUID(petUnit)
		if groupUnits[unit] ~= guid or groupUnits[petUnit] ~= petGUID then
			groupUnits[unit], groupUnits[petUnit] = guid, petGUID
			changed = true
		end
	end
	if changed then
		addon.Debug('Group', addon.getkeys(groupUnits))
		return self:SendMessage(GROUP_CHANGED)
	end
end

function addon:UNIT_PET(event, unit)
	local petUnit
	if unit == "player" then
		petUnit = "pet"
	elseif groupUnits[unit] then
		petUnit = gsub(unit.."pet", "(%d+)pet", "pet%1")
	else
		return
	end
	local guid = UnitGUID(petUnit)
	if groupUnits[petUnit] ~= guid then
		groupUnits[petUnit] = guid
		return self:SendMessage(GROUP_CHANGED)
	end
end

addon:DeclareMessage(
	GROUP_CHANGED,
	function()
		addon:RegisterEvent('GROUP_ROSTER_UPDATE')
		addon:RegisterEvent('UNIT_PET')
		addon:GROUP_ROSTER_UPDATE('OnUse')
	end,
	function()
		addon:UnregisterEvent('GROUP_ROSTER_UPDATE')
		addon:UnregisterEvent('UNIT_PET')
	end
)

------------------------------------------------------------------------------
-- Mouseover watching
------------------------------------------------------------------------------

local MOUSEOVER_CHANGED = addonName..'_Mouseover_Changed'
local MOUSEOVER_TICK = addonName..'_Mouseover_Tick'
local unitList = { "player", "pet", "target", "focus" }

addon.MOUSEOVER_CHANGED, addon.MOUSEOVER_TICK, addon.unitList = MOUSEOVER_CHANGED, MOUSEOVER_TICK, unitList

for i = 1,4 do tinsert(unitList, "party"..i) end
for i = 1,40 do tinsert(unitList, "raid"..i) end

local mouseoverUnit, mouseoverGUID = 'mouseover'

local function ResolveMouseover()
	if UnitExists('mouseover') then
		for i, unit in pairs(unitList) do
			if UnitIsUnit(unit, "mouseover") then
				return unit
			end
		end
		return 'mouseover'
	end
end

local mouseoverFrame = CreateFrame("Frame")
mouseoverFrame:Hide()

function mouseoverFrame:Update(event)
	local unit = ResolveMouseover()
	mouseoverGUID = UnitGUID('mouseover')
	if mouseoverUnit ~= unit then
		mouseoverUnit = unit
		self:SetShown(unit == 'mouseover')
		addon.Debug('Mouseover', event, 'Changed:', unit)
		return addon:SendMessage(MOUSEOVER_CHANGED, 'mouseover', unit)
	elseif unit == 'mouseover' then
		addon.Debug('Mouseover', event, 'Tick')
		return addon:SendMessage(MOUSEOVER_TICK)
	end
end

local timer = 0
function mouseoverFrame:OnUpdate(elapsed)
	timer = timer - elapsed
	if timer <= 0 or UnitGUID('mouseover') ~= mouseoverGUID then
		timer = 0.5
		return self:Update('OnUpdate')
	end
end

mouseoverFrame:SetScript('OnEvent', mouseoverFrame.Update)
mouseoverFrame:SetScript('OnUpdate', mouseoverFrame.OnUpdate)

function addon:GetMouseoverUnit()
	return mouseoverUnit
end

do
	local mouseoverUsed = 0
	local function OnUsed(msg)
		if mouseoverUsed == 0 then
			mouseoverFrame:RegisterEvent('UPDATE_MOUSEOVER_UNIT')
			addon.Debug('Mouseover', 'Started listening to UPDATE_MOUSEOVER_UNIT')
			mouseoverFrame:Update('OnUsed')
		end
		mouseoverUsed = mouseoverUsed + 1
	end
	local function OnUnused(msg)
		mouseoverUsed = mouseoverUsed - 1
		if mouseoverUsed == 0 then
			mouseoverFrame:UnregisterEvent('UPDATE_MOUSEOVER_UNIT')
			mouseoverFrame:Hide()
			addon.Debug('Mouseover', 'Stopped listening to UPDATE_MOUSEOVER_UNIT')
		end
	end
	addon:DeclareMessage(MOUSEOVER_CHANGED, OnUsed, OnUnused)
	addon:DeclareMessage(MOUSEOVER_TICK, OnUsed, OnUnused)
end

------------------------------------------------------------------------------
-- "ally" and "enemy" pseudo-units
------------------------------------------------------------------------------

local DYNAMIC_UNIT_CONDITONALS_CHANGED = addonName..'_DynamicUnitConditionals_Changed'
local dynamicUnitConditionals = {}

addon.DYNAMIC_UNIT_CONDITONALS_CHANGED = DYNAMIC_UNIT_CONDITONALS_CHANGED
addon.dynamicUnitConditionals = dynamicUnitConditionals

function addon:UpdateDynamicUnitConditionals()
	local selfCast, focusCast = GetModifiedClick("SELFCAST"), GetModifiedClick("FOCUSCAST")
	local enemy = "[harm]"
	local ally
	if GetCVarBool("autoSelfCast") then
		ally = "[help,nodead][@player]"
	else
		ally = "[help]"
	end
	if focusCast ~= "NONE" then
		enemy = "[@focus,mod:"..focusCast.."]"..enemy
		ally = "[@focus,mod:"..focusCast.."]"..ally
	end
	if selfCast ~= "NONE" then
		ally = "[@player,mod:"..selfCast.."]"..ally
	end
	if dynamicUnitConditionals.enemy ~= enemy or dynamicUnitConditionals.ally ~= ally then
		dynamicUnitConditionals.enemy, dynamicUnitConditionals.ally = enemy, ally
		addon:SendMessage(DYNAMIC_UNIT_CONDITONALS_CHANGED)
	end
end

function addon:CVAR_UPDATE(_, name)
	if name == "autoSelfCast" then
		return self:UpdateDynamicUnitConditionals()
	end
end

addon:DeclareMessage(
	DYNAMIC_UNIT_CONDITONALS_CHANGED,
	function()
		addon:RegisterEvent('CVAR_UPDATE')
		addon:RegisterEvent('VARIABLES_LOADED', 'UpdateDynamicUnitConditionals')
		addon:RegisterEvent('UPDATE_BINDINGS', 'UpdateDynamicUnitConditionals')
		addon:UpdateDynamicUnitConditionals()
	end,
	function()
		addon:UnregisterEvent('CVAR_UPDATE')
		addon:UnregisterEvent('VARIABLES_LOADED')
		addon:UnregisterEvent('UPDATE_BINDINGS')
	end
)
