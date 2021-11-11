local namespace = 'CritMeter'
local isUIUnlocked = false
local cpSkillCritMod = 0
local sv -- Saved variables
local isPlayerInCombat = false
local critDamage = GetAdvancedStatValue(ADVANCED_STAT_DISPLAY_TYPE_CRITICAL_DAMAGE)

local defaults = {
    x = 300,
    y = 300,
}

local targetDebuffs = {
    [142610] = 5, -- Flame Weakness, Elemental Catalyst
    [142652] = 5, -- Frost Weakness, Elemental Catalyst
    [142653] = 5, -- Shock Weakness, Elemental Catalyst
    [145975] = 10, -- Minor Brittle
}

local EM = EVENT_MANAGER

-- Check crit dmg debuffs on reticle target
local function GetTargetDebuffs(eventCode)
    if DoesUnitExist('reticleover') and not IsUnitPlayer('reticleover') then
        for i = 1, GetNumBuffs('reticleover') do
            local _, _, _, _, _, _, _, _, _, _, abilityId = GetUnitBuffInfo('reticleover', i)

            if targetDebuffs[abilityId] then critDamage = critDamage + targetDebuffs[abilityId] end
        end
    end
end

-- Whenever registered abilities fade, refresh or are gained this function is called, getting player's current crit dmg as well as crit dmg debuffs on reticle target
local function OnCritDamageUpdated(eventCode, changeType, effectSlot, effectName, unitTag, beginTime, endTime, stackCount, iconName, buffType, effectType, abilityType, statusEffectType, unitName, unitId, abilityId, sourceType)
    _, _, critDamage = GetAdvancedStatValue(ADVANCED_STAT_DISPLAY_TYPE_CRITICAL_DAMAGE)
    critDamage = critDamage + 50 + cpSkillCritMod

    GetTargetDebuffs()

    if critDamage > 125 then critDamage = 125 end

    local colour = critDamage / 125 == 1 and {0.49, 0.72, 0.34} or {0.92, 0.27, 0.38}

    CritMeter_UI_Text:SetText(critDamage)
    CritMeter_UI_Bar:SetWidth(194 * critDamage / 125)
    CritMeter_UI_Bar:SetColor(unpack(colour))
end

local function OnCPChanged(eventCode, result)
    if result == CHAMPION_PURCHASE_SUCCESS then
        cpSkillCritMod = 0
        for disciplineIndex = 4, 8 do
            local championSkillId = GetSlotBoundId(disciplineIndex, HOTBAR_CATEGORY_CHAMPION)

            -- Backstabber CP
            if championSkillId == 31 then cpSkillCritMod = cpSkillCritMod + 15 end
        end

        OnCritDamageUpdated()
    end
end

local function OnCombatStateChanged(eventCode, inCombat)
    if isPlayerInCombat ~= inCombat then
        if inCombat then
            isPlayerInCombat = true
            EM:RegisterForUpdate(namespace, 200, GetTargetDebuffs)
        else
            zo_callLater(function()
                if not IsUnitInCombat('player') then
                    isPlayerInCombat = false
                    EM:UnregisterForUpdate(namespace)
                end
            end, 3000)
        end
    end
end

local function OnPlayerActivated(eventCode, initial)
    OnCPChanged(nil, CHAMPION_PURCHASE_SUCCESS)
    OnCritDamageUpdated()

    -- Player could be in combat after a reloadui
    local inCombat = IsUnitInCombat('player')
    OnCombatStateChanged(nil, inCombat)
end

-- Save ui location after moving
function CritMeterOnMoveStop()
    sv.x, sv.y = CritMeter_UI:GetCenter()
end

-- Get saved variables, reposition ui, and register events
local function OnAddonLoaded(eventCode, addonName)
    if addonName == namespace then
        EM:UnregisterForEvent(namespace, eventCode)

        sv = ZO_SavedVars:NewAccountWide('CritMeterSV', 1, nil, defaults)

        CritMeter_UI:ClearAnchors()
        CritMeter_UI:SetAnchor(CENTER, GuiRoot, TOPLEFT, sv.x, sv.y)

        local fragment = ZO_SimpleSceneFragment:New(CritMeter_UI)
        HUD_SCENE:AddFragment(fragment)
        HUD_UI_SCENE:AddFragment(fragment)

        -- In order: Minor Force, Major Force, Minor Enervation, Senche's Bite, Sul-Xan Soulbound, Harpooner's Wading Kilt
        for index, abilityId in ipairs({61746, 61747, 79907, 127192, 154737, 155150}) do
            local namespace = namespace .. abilityId
            EM:RegisterForEvent(namespace, EVENT_EFFECT_CHANGED, OnCritDamageUpdated)
            EM:AddFilterForEvent(namespace, EVENT_EFFECT_CHANGED, REGISTER_FILTER_ABILITY_ID, abilityId, REGISTER_FILTER_UNIT_TAG, 'player')
        end

        -- Hidden (Archer's Mind)
        EM:RegisterForEvent(namespace .. 'Crouch', EVENT_COMBAT_EVENT, OnCritDamageUpdated)
        EM:AddFilterForEvent(namespace .. 'Crouch', EVENT_COMBAT_EVENT, REGISTER_FILTER_ABILITY_ID, 20309, REGISTER_FILTER_TARGET_COMBAT_UNIT_TYPE, COMBAT_UNIT_TYPE_PLAYER)

        -- Minor Brittle and Elemental Catalyst
        EM:RegisterForEvent(namespace .. 'Reticle', EVENT_RETICLE_TARGET_CHANGED, GetTargetDebuffs)

        -- True-Sworn Fury
        EM:RegisterForEvent(namespace .. 'Health', EVENT_POWER_UPDATE, OnCritDamageUpdated)
        EM:AddFilterForEvent(namespace .. 'Health', EVENT_POWER_UPDATE, REGISTER_FILTER_POWER_TYPE, POWERTPYE_HEALTH)

        EM:RegisterForEvent(namespace .. 'Gear', EVENT_INVENTORY_SINGLE_SLOT_UPDATE, OnCritDamageUpdated)
        EM:AddFilterForEvent(namespace .. 'Gear', EVENT_INVENTORY_SINGLE_SLOT_UPDATE, REGISTER_FILTER_BAG_ID, BAG_WORN, REGISTER_FILTER_INVENTORY_UPDATE_REASON, INVENTORY_UPDATE_REASON_DEFAULT)

        -- Nightblade's Hemorrhage and Templar's Piercing Spear passives require skill slotted
        EM:RegisterForEvent(namespace .. 'Skill', EVENT_ACTION_SLOT_UPDATED, OnCritDamageUpdated)
        EM:RegisterForEvent(namespace .. 'AllSkills', EVENT_ACTION_SLOTS_ALL_HOTBARS_UPDATED, OnCritDamageUpdated)
        EM:RegisterForEvent(namespace .. 'Hotbar', EVENT_ACTION_SLOTS_ACTIVE_HOTBAR_UPDATED, OnCritDamageUpdated)

        EM:RegisterForEvent(namespace .. 'CPChanged', EVENT_CHAMPION_PURCHASE_RESULT, OnCPChanged)

        EM:RegisterForEvent(namespace .. 'CombatState', EVENT_PLAYER_COMBAT_STATE, OnCombatStateChanged)

        EM:RegisterForEvent(namespace .. 'PlayerActivated', EVENT_PLAYER_ACTIVATED, OnPlayerActivated)
    end
end

EM:RegisterForEvent(namespace, EVENT_ADD_ON_LOADED, OnAddonLoaded)

-- Chat command to (un-)lock ui
SLASH_COMMANDS['/critmeter'] = function()
    isUIUnlocked = not isUIUnlocked

    CritMeter_UI:SetMouseEnabled(isUIUnlocked)
    CritMeter_UI:SetMovable(isUIUnlocked)
end