if not game:IsLoaded() then
    game.Loaded:Wait()
end

local players = game:GetService("Players")
local teleport_service = game:GetService("TeleportService")
local http_service = game:GetService("HttpService")

local user_file = "meetv_userid.txt"
local server_file = "meetv_servers.txt"
local place_id = game.PlaceId
local job_id = game.JobId

local session_uids = {}

local function get_lines(file)
    if not isfile(file) then return {} end
    local lines = {}
    for line in readfile(file):gmatch("[^\r\n]+") do
        table.insert(lines, line)
    end
    return lines
end

local function save_users()
    local ids = {}
    for _, p in ipairs(players:GetPlayers()) do
        local uid = tostring(p.UserId)
        if not session_uids[uid] then
            table.insert(ids, uid)
            session_uids[uid] = true
        end
    end
    
    if #ids > 0 then
        local content = table.concat(ids, "\n") .. "\n"
        if isfile(user_file) then
            appendfile(user_file, content)
        else
            writefile(user_file, content)
        end
    end
end

local function get_new_servers()
    local found = {}
    local cursor = ""
    
    for i = 1, 10 do
        local url = "https://games.roblox.com/v1/games/" .. place_id .. "/servers/Public?sortOrder=Asc&limit=100"
        if cursor ~= "" then url = url .. "&cursor=" .. cursor end
        
        local res = request({Url = url, Method = "GET"})
        if res.Success then
            local decoded = http_service:JSONDecode(res.Body)
            for _, s in ipairs(decoded.data) do
                if s.playing < s.maxPlayers and s.id ~= job_id then
                    table.insert(found, s.id)
                end
            end
            cursor = decoded.nextPageCursor
            if not cursor then break end
        else
            break
        end
    end
    return found
end

local function handle_hop()
    local cache = {}
    local order = {}
    local raw = get_lines(server_file)
    
    for _, line in ipairs(raw) do
        local id, status = line:match("^(%S+)%s*(.*)$")
        if id then
            table.insert(order, id)
            cache[id] = status
        end
    end
    
    local needs_refresh = (#order == 0)
    if not needs_refresh then
        local all_done = true
        for _, id in ipairs(order) do
            if cache[id] ~= "DONE" then
                all_done = false
                break
            end
        end
        needs_refresh = all_done
    end

    if needs_refresh then
        local fetched = get_new_servers()
        order = {}
        cache = {}
        for _, id in ipairs(fetched) do
            table.insert(order, id)
            cache[id] = "PENDING"
        end
    end
    
    cache[job_id] = "DONE"
    
    local updated = ""
    for _, id in ipairs(order) do
        updated = updated .. id .. " " .. (cache[id] or "PENDING") .. "\n"
    end
    writefile(server_file, updated)
    
    for _, id in ipairs(order) do
        if cache[id] ~= "DONE" and id ~= job_id then
            return id
        end
    end
    return nil
end

task.spawn(function()
    while true do
        save_users()
        task.wait(1)
        
        local target = handle_hop()
        if target then
            if syn and syn.queue_on_teleport then
            end
            
            local success, err = pcall(function()
                teleport_service:TeleportToPlaceInstance(place_id, target, players.LocalPlayer)
            end)
            
            if not success then
                task.wait(5)
            end
        else
            delfile(server_file)
            task.wait(10)
        end
        task.wait(2)
    end
end)
