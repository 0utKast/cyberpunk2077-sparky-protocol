-- Protocolo CHISPA v2.0 — Puente IPC por archivos seguros en CET (Windows)

local LiveIPC = {}

local function utf8FromCodepoint(cp)
    if cp < 128 then
        return string.char(cp)
    elseif cp < 2048 then
        return string.char(
            192 + math.floor(cp / 64),
            128 + (cp % 64)
        )
    elseif cp < 65536 then
        return string.char(
            224 + math.floor(cp / 4096),
            128 + (math.floor(cp / 64) % 64),
            128 + (cp % 64)
        )
    end
    return "?"
end

local function skipWs(str, pos)
    local _, nextPos = str:find("^[ \t\r\n]*", pos)
    return (nextPos or pos - 1) + 1
end

local parseValue

local function parseString(str, pos)
    pos = pos + 1 -- saltar '"'
    local out = {}
    local len = #str
    while pos <= len do
        local ch = str:sub(pos, pos)
        if ch == '"' then
            return table.concat(out), pos + 1
        elseif ch == "\\" then
            local nxt = str:sub(pos + 1, pos + 1)
            if nxt == '"' or nxt == "\\" or nxt == "/" then
                table.insert(out, nxt)
                pos = pos + 2
            elseif nxt == "n" then
                table.insert(out, "\n")
                pos = pos + 2
            elseif nxt == "r" then
                table.insert(out, "\r")
                pos = pos + 2
            elseif nxt == "t" then
                table.insert(out, "\t")
                pos = pos + 2
            elseif nxt == "u" then
                local hex = str:sub(pos + 2, pos + 5)
                local cp = tonumber(hex, 16)
                if cp then
                    table.insert(out, utf8FromCodepoint(cp))
                    pos = pos + 6
                else
                    pos = pos + 2
                end
            else
                table.insert(out, nxt)
                pos = pos + 2
            end
        else
            table.insert(out, ch)
            pos = pos + 1
        end
    end
    return nil, pos
end

local function parseObject(str, pos)
    pos = skipWs(str, pos + 1) -- saltar '{'
    local obj = {}
    if str:sub(pos, pos) == "}" then
        return obj, pos + 1
    end
    local len = #str
    while pos <= len do
        pos = skipWs(str, pos)
        if str:sub(pos, pos) ~= '"' then
            return nil, pos
        end
        local key
        key, pos = parseString(str, pos)
        if not key then
            return nil, pos
        end
        pos = skipWs(str, pos)
        if str:sub(pos, pos) ~= ":" then
            return nil, pos
        end
        pos = skipWs(str, pos + 1)
        local val
        val, pos = parseValue(str, pos)
        obj[key] = val
        pos = skipWs(str, pos)
        local sep = str:sub(pos, pos)
        if sep == "}" then
            return obj, pos + 1
        elseif sep == "," then
            pos = pos + 1
        else
            return nil, pos
        end
    end
    return nil, pos
end

parseValue = function(str, pos)
    pos = skipWs(str, pos)
    local ch = str:sub(pos, pos)
    if ch == '"' then
        return parseString(str, pos)
    elseif ch == "{" then
        return parseObject(str, pos)
    elseif str:sub(pos, pos + 3) == "true" then
        return true, pos + 4
    elseif str:sub(pos, pos + 4) == "false" then
        return false, pos + 5
    elseif str:sub(pos, pos + 3) == "null" then
        return nil, pos + 4
    else
        local numStr = str:match("^-?%d+%.?%d*[eE]?[+-]?%d*", pos)
        if numStr and #numStr > 0 then
            return tonumber(numStr), pos + #numStr
        end
    end
    return nil, pos + 1
end

function LiveIPC.decodeJsonObject(raw)
    if type(raw) ~= "string" or #raw == 0 then
        return nil
    end
    local ok, obj = pcall(function()
        local pos = skipWs(raw, 1)
        if raw:sub(pos, pos) ~= "{" then
            return nil
        end
        local parsed = parseObject(raw, pos)
        return parsed
    end)
    if ok and type(obj) == "table" then
        return obj
    end
    return nil
end

function LiveIPC.escapeJson(s)
    if type(s) ~= "string" then
        s = tostring(s or "")
    end
    s = s:gsub("\\", "\\\\")
    s = s:gsub('"', '\\"')
    s = s:gsub("\r", "")
    s = s:gsub("\n", " ")
    s = s:gsub("\t", " ")
    return s
end

function LiveIPC.writeAtomic(relPath, content)
    local tmpPath = relPath .. ".tmp"
    local ok = pcall(function()
        local f = io.open(tmpPath, "wb")
        if not f then
            return
        end
        f:write(content)
        f:close()
        -- En Windows os.rename falla si relPath ya existe; eliminar destino antes.
        os.remove(relPath)
        os.rename(tmpPath, relPath)
    end)
    return ok
end

local lastInboxRaw = nil
local lastInboxObj = nil
local lastHbRaw = nil
local lastHbObj = nil
local lastStateCore = nil
local lastStateWriteClock = -999.0

function LiveIPC.readRawFile(relPath)
    local raw = nil
    pcall(function()
        local f = io.open(relPath, "rb")
        if f then
            raw = f:read("*a")
            f:close()
        end
    end)
    return raw
end

function LiveIPC.readJsonFile(relPath)
    local raw = LiveIPC.readRawFile(relPath)
    if not raw then
        return nil
    end
    return LiveIPC.decodeJsonObject(raw)
end

function LiveIPC.writeState(stateJson, forceNow)
    if type(stateJson) ~= "string" or #stateJson < 2 then
        return false
    end
    local isMenu = stateJson:find('"in_menu":true', 1, true) ~= nil
    local nowClk = os.clock()
    if not forceNow and stateJson == lastStateCore then
        if isMenu or (nowClk - lastStateWriteClock) < 1.1 then
            return false
        end
    end
    local stamped = stateJson
    if stateJson:sub(-1) == "}" then
        stamped = stateJson:sub(1, -2) .. string.format(',"cet_time":%.3f}', nowClk)
    end
    local ok = LiveIPC.writeAtomic("ipc/state.json", stamped)
    if ok then
        lastStateCore = stateJson
        lastStateWriteClock = nowClk
    end
    return ok
end

function LiveIPC.sendRequest(cetSessionId, reqId, action, text)
    local payload = string.format(
        '{"cet_session":"%s","req_id":%d,"action":"%s","text":"%s","ts":%.3f}',
        LiveIPC.escapeJson(cetSessionId),
        tonumber(reqId) or 0,
        LiveIPC.escapeJson(action),
        LiveIPC.escapeJson(text),
        os.time()
    )
    return LiveIPC.writeAtomic("ipc/player_req.json", payload)
end

function LiveIPC.readInbox()
    local raw = LiveIPC.readRawFile("ipc/inbox.json")
    if not raw then
        return nil
    end
    if raw == lastInboxRaw then
        return lastInboxObj
    end
    lastInboxRaw = raw
    lastInboxObj = LiveIPC.decodeJsonObject(raw)
    return lastInboxObj
end

function LiveIPC.readHeartbeat()
    local raw = LiveIPC.readRawFile("ipc/heartbeat.json")
    if not raw then
        return nil
    end
    if raw == lastHbRaw then
        return lastHbObj
    end
    lastHbRaw = raw
    lastHbObj = LiveIPC.decodeJsonObject(raw)
    return lastHbObj
end

return LiveIPC
