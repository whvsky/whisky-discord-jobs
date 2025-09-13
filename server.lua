local cache = {}  -- [src] = { discord = "id", principals = { ... }, matchedDept = "group.lspd", matchedGrade = 0 }

local function dbg(msg, ...)
    if Config and Config.Debug then
        print(("[whisky_discord_perms] " .. msg):format(...))
    end
end

-- Badger_Discord_API compatibility shims (handles multiple export names across versions)
local function BD_GetDiscordId(src)
    local ok, res

    -- Try known export names
    ok, res = pcall(function() return exports['Badger_Discord_API']:GetDiscordIdentifier(src) end)
    if ok and res and res ~= "" then return res end

    ok, res = pcall(function() return exports['Badger_Discord_API']:GetDiscordId(src) end)
    if ok and res and res ~= "" then return res end

    ok, res = pcall(function() return exports['Badger_Discord_API']:GetDiscordID(src) end)
    if ok and res and res ~= "" then return res end

    ok, res = pcall(function() return exports['Badger_Discord_API']:GetIdentifier(src) end)
    if ok and res and res ~= "" then return res end

    -- Fallback: parse identifiers (discord:XXXXXXXX)
    for _, id in ipairs(GetPlayerIdentifiers(src)) do
        if string.sub(id, 1, 8) == "discord:" then
            return string.sub(id, 9)
        end
    end
    return nil
end

local function BD_GetDiscordRoles(src)
    local ok, res

    -- Try known role export names
    ok, res = pcall(function() return exports['Badger_Discord_API']:GetDiscordRoles(src) end)
    if ok and type(res) == 'table' then return res end

    ok, res = pcall(function() return exports['Badger_Discord_API']:GetRoles(src) end)
    if ok and type(res) == 'table' then return res end

    ok, res = pcall(function() return exports['Badger_Discord_API']:GetRoleIDs(src) end)
    if ok and type(res) == 'table' then return res end

    ok, res = pcall(function() return exports['Badger_Discord_API']:GetRoleIds(src) end)
    if ok and type(res) == 'table' then return res end

    -- Fallback: empty list
    return {}
end

-- Normalize role IDs to strings so comparisons always match config keys
local function normalizeRoles(roles)
    local out = {}
    for _, rid in ipairs(roles or {}) do
        out[#out+1] = tostring(rid)
    end
    return out
end

local function getDiscordId(src)
    if GetResourceState('Badger_Discord_API') == 'started' then
        local id = BD_GetDiscordId(src)
        if id and id ~= "" then return id end
    end
    -- Fallback handled inside BD_GetDiscordId already.
    return BD_GetDiscordId(src)
end

local function getRoleIds(src)
    if GetResourceState('Badger_Discord_API') ~= 'started' then
        return {}
    end
    local roles = BD_GetDiscordRoles(src) or {}
    roles = normalizeRoles(roles)
    return roles
end

local function removePrincipals(discordId, principals)
    if not discordId or not principals then return end
    for _, ace in ipairs(principals) do
        ExecuteCommand(("remove_principal identifier.discord:%s %s"):format(discordId, ace))
        dbg("Removed principal %s for discord:%s", ace, discordId)
    end
end

local function grantPrincipals(discordId, principals)
    if not discordId then return end
    for _, ace in ipairs(principals) do
        ExecuteCommand(("add_principal identifier.discord:%s %s"):format(discordId, ace))
        dbg("Granted principal %s to discord:%s", ace, discordId)
    end
end

local function setContains(tbl, val)
    for _, v in ipairs(tbl or {}) do
        if v == val then return true end
    end
    return false
end

local function collapseToPrincipals(roleIds)
    local principals = {}
    local seen = {}
    if Config and Config.BaseAce and Config.BaseAce ~= "" then
        principals[#principals+1] = Config.BaseAce
        seen[Config.BaseAce] = true
    end

    -- Auto-grant department ACE if any of its roles matched
    if Config and Config.AutoGrantDepartmentAce and Config.DepartmentMap then
        for deptGroup, info in pairs(Config.DepartmentMap) do
            for rid, _ in pairs(info.roleGrades or {}) do
                for _, have in ipairs(roleIds) do
                    if rid == have and not seen[deptGroup] then
                        principals[#principals+1] = deptGroup
                        seen[deptGroup] = true
                        break
                    end
                end
            end
        end
    end

    return principals
end

-- Decide department and grade based on roleGrades / groupGrades
local function chooseDepartmentAndGrade(principals, roleIds)
    local candidates = {}
    if not Config or not Config.DepartmentMap then return nil, nil end

    -- role-based matches
    for deptGroup, info in pairs(Config.DepartmentMap) do
        for rid, grade in pairs(info.roleGrades or {}) do
            for _, have in ipairs(roleIds) do
                if rid == have then
                    local base = info.defaultGrade or 0
                    local g = tonumber(grade) or 0
                    candidates[deptGroup] = math.max(candidates[deptGroup] or base, g)
                end
            end
        end
    end
    -- group-based matches (ACE aliases)
    for deptGroup, info in pairs(Config.DepartmentMap) do
        for gname, grade in pairs(info.groupGrades or {}) do
            for _, ace in ipairs(principals or {}) do
                if gname == ace then
                    local base = info.defaultGrade or 0
                    local g = tonumber(grade) or 0
                    candidates[deptGroup] = math.max(candidates[deptGroup] or base, g)
                end
            end
        end
    end
    -- If no matches at all, allow defaultGrade when the dept ACE itself is present
    for deptGroup, info in pairs(Config.DepartmentMap) do
        if (candidates[deptGroup] == nil) and setContains(principals, deptGroup) then
            candidates[deptGroup] = tonumber(info.defaultGrade or 0) or 0
        end
    end

    -- choose highest priority dept that exists in candidates
    if Config and Config.DepartmentPriority then
        for _, dept in ipairs(Config.DepartmentPriority) do
            if candidates[dept] ~= nil then
                return dept, candidates[dept]
            end
        end
    end
    return nil, nil
end

local function trySetJob(src, deptGroup, grade)
    if not deptGroup or not Config or not Config.EnableJobLink then return end
    local info = Config.DepartmentMap and Config.DepartmentMap[deptGroup]
    if not info then return end

    local job   = info.job or 'unemployed'
    local jgrad = tonumber(grade ~= nil and grade or info.defaultGrade or 0) or 0

    -- Try Qbox/qb-core APIs safely
    local function setWithQBCore()
        if GetResourceState('qb-core') ~= 'started' then return false end
        local QBCore = exports['qb-core']:GetCoreObject()
        if not QBCore or not QBCore.Functions then return false end
        local Player = QBCore.Functions.GetPlayer(src)
        if not Player or not Player.Functions then return false end
        if Config.OnlySetIfUnemployed then
            local pdata = Player.PlayerData or {}
            local curJob = pdata.job and pdata.job.name
            if curJob and curJob ~= 'unemployed' then
                dbg("QB: skipping job set for %s; already %s", tostring(src), tostring(curJob))
                return true
            end
        end
        Player.Functions.SetJob(job, jgrad)
        dbg("QB: set job for %s => %s grade %s", tostring(src), job, tostring(jgrad))
        return true
    end

    local function setWithQbx()
        if GetResourceState('qbx_core') ~= 'started' then return false end
        -- Many Qbox forks still expose qb-core API; try export alias just in case
        local ok = false
        if GetResourceState('qb-core') == 'started' then
            ok = setWithQBCore()
            if ok then return true end
        end
        -- Fallback generic event for forks
        TriggerEvent('QBCore:Server:SetJob', src, job, jgrad)
        dbg("QBX: attempted event-based set job for %s => %s grade %s", tostring(src), job, tostring(jgrad))
        return true
    end

    if setWithQbx() then return end
    if setWithQBCore() then return end

    dbg("No job framework detected for %s; skipped job set.", tostring(src))
end

local function refreshPlayer(src)
    if not src or not GetPlayerName(src) then
        return false, "invalid source"
    end

    local discordId = getDiscordId(src)
    if not discordId then
        if Config and Config.AllowNoDiscord then
            dbg("No Discord ID for %s; skipping principals", tostring(src))
            cache[src] = { discord = nil, principals = {}, ts = os.time() }
            return true, "no_discord"
        else
            return false, "no_discord"
        end
    end

    local prev = cache[src]
    if prev and prev.discord ~= discordId then
        removePrincipals(prev.discord, prev.principals)
        cache[src] = nil
    end

    local roles = getRoleIds(src)
    dbg("Roles for %s (discord:%s): %s", GetPlayerName(src), discordId, json.encode(roles))

    local principals = collapseToPrincipals(roles)

    if Config and Config.ResetBeforeGrant and prev and prev.principals then
        removePrincipals(discordId, prev.principals)
    end
    grantPrincipals(discordId, principals)

    local dept, grade = chooseDepartmentAndGrade(principals, roles)
    if dept then
        dbg("Matched department %s (grade %s) for %s", dept, tostring(grade), GetPlayerName(src))
        if Config and Config.AutoGrantDepartmentAce and not setContains(principals, dept) then
            ExecuteCommand(("add_principal identifier.discord:%s %s"):format(discordId, dept))
            principals[#principals+1] = dept
        end
        trySetJob(src, dept, grade)
    end

    cache[src] = {
        discord = discordId,
        principals = principals,
        matchedDept = dept,
        matchedGrade = grade,
        ts = os.time()
    }
    TriggerEvent('whisky_discord_perms:updated', src, cache[src])
    return true, "ok"
end

-- Clean up
AddEventHandler('playerDropped', function()
    local src = source
    local entry = cache[src]
    if entry and entry.discord and entry.principals then
        removePrincipals(entry.discord, entry.principals)
    end
    cache[src] = nil
end)

-- Refresh on join
AddEventHandler('playerJoining', function()
    local src = source
    CreateThread(function()
        Wait(500)
        local ok, why = refreshPlayer(src)
        if not ok then
            dbg("Refresh failed on join for %s: %s", tostring(src), tostring(why))
        end
    end)
end)

-- Commands
RegisterCommand('permrefresh', function(src, args)
    if src ~= 0 and not IsPlayerAceAllowed(src, 'command.permrefresh') then
        TriggerClientEvent('chat:addMessage', src, { args = { '^1permrefresh', 'No permission.' } })
        return
    end
    local target = args[1]
    if not target then
        print("Usage: /permrefresh <id | all>")
        return
    end
    if target == 'all' then
        for _, id in ipairs(GetPlayers()) do
            refreshPlayer(tonumber(id))
        end
        print("Refreshed principals for all players.")
    else
        local id = tonumber(target)
        if id and GetPlayerName(id) then
            local ok, why = refreshPlayer(id)
            print(("Refreshed %s => %s"):format(GetPlayerName(id), tostring(why)))
        else
            print("Invalid player id.")
        end
    end
end, true)

RegisterCommand('permdebug', function(src, args)
    local id = tonumber(args[1] or -1)
    if not id or not GetPlayerName(id) then
        print("Usage: /permdebug <serverId>")
        return
    end
    local entry = cache[id]
    if not entry then
        print(("No cache entry for %s"):format(id))
        return
    end
    print(("[permdebug] %s discord:%s principals:%s dept:%s grade:%s ts:%s"):format(
        GetPlayerName(id),
        tostring(entry.discord),
        json.encode(entry.principals or {}),
        tostring(entry.matchedDept),
        tostring(entry.matchedGrade),
        os.date("%Y-%m-%d %H:%M:%S", entry.ts or os.time())
    ))
end, true)

-- Dump raw roles (diagnostic)
RegisterCommand('permdumproles', function(src, args)
    local id = tonumber(args[1] or -1)
    if not id or not GetPlayerName(id) then
        print("Usage: /permdumproles <serverId>")
        return
    end
    local roles = getRoleIds(id) or {}
    print(("[permdumproles] %s roles: %s"):format(GetPlayerName(id), json.encode(roles)))
end, true)

-- Expose a manual API other scripts can call
RegisterNetEvent('whisky_discord_perms:refreshPlayer', function(targetId)
    local src = source
    if src ~= 0 and not IsPlayerAceAllowed(src, 'command.permrefresh') then
        return
    end
    if targetId and GetPlayerName(targetId) then
        refreshPlayer(targetId)
    end
end)
