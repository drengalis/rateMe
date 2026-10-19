-- PERMANENT WIRE/DATABASE IDS. NEVER RENUMBER, REASSIGN OR REUSE AN ID.
-- Retire a tag by keeping its entry and setting retired=true. Never delete it.
-- Labels may be clarified without changing the meaning of the assigned ID.
-- Gaps are reserved for future additions. These IDs are independent of ordering.
local _, Store = ...
local A = Store.API
local registry = {
    [1]={name="Leader",positive=true},
    [2]={name="Team Player",positive=true},
    [3]={name="Helpful",positive=true},
    [4]={name="Skilled",positive=true},
    [5]={name="Reliable",positive=true},
    [6]={name="Patient",positive=true},
    [7]={name="Fair Looter",positive=true},
    [8]={name="Good Communicator",positive=true},
    [9]={name="Well Prepared",positive=true},
    [10]={name="Knows Mechanics",positive=true},
    [11]={name="Protects Teammates",positive=true},
    [12]={name="Good Sportsmanship",positive=true},
    [33]={name="Ninja Looter",positive=false},
    [34]={name="Toxic",positive=false},
    [35]={name="Griefer",positive=false},
    [36]={name="Frequently AFK",positive=false},
    [37]={name="Abandons Groups",positive=false},
    [38]={name="Uncooperative",positive=false},
    [39]={name="Ignores Mechanics",positive=false},
    [40]={name="Reckless Pulls",positive=false},
    [41]={name="Unprepared",positive=false},
    [42]={name="Poor Communication",positive=false},
    [43]={name="Breaks Crowd Control",positive=false},
    [44]={name="Disrespects Loot Rules",positive=false},
}
local opposite = {[2]={[38]=true},[7]={[33]=true,[44]=true},[8]={[42]=true},
    [9]={[41]=true},[10]={[39]=true},[12]={[34]=true,[35]=true}}
-- One safe ASCII byte per ID. Preserve this alphabet and ID-to-byte mapping.
local alphabet="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
A.TAG_REGISTRY = registry
A.MAX_REVIEW_TAGS = 3

function A:ReviewTagIds(value)
    local ids = {}
    if value == nil then return ids end
    if type(value) == "string" then
        if #value > 3 then return nil end
        for n=1,#value do
            local at=alphabet:find(value:sub(n,n),1,true)
            if not at then return nil end
            ids[#ids+1]=at-1
        end
    elseif type(value) == "table" then
        local count=0
        for k in pairs(value) do
            if type(k)~="number" or k<1 or k>3 or k~=math.floor(k) then return nil end
            count=count+1
        end
        if count~=#value or count>3 then return nil end
        for _,id in ipairs(value) do ids[#ids+1]=id end
    else return nil end
    local seen={}
    for _,id in ipairs(ids) do
        if type(id)~="number" or not registry[id] or seen[id] then return nil end
        for prior in pairs(seen) do
            if (opposite[id] and opposite[id][prior]) or (opposite[prior] and opposite[prior][id]) then return nil end
        end
        seen[id]=true
    end
    table.sort(ids)
    return ids
end

function A:EncodeReviewTags(value)
    local ids=self:ReviewTagIds(value)
    if not ids then return nil end
    local chars={}
    for _,id in ipairs(ids) do chars[#chars+1]=alphabet:sub(id+1,id+1) end
    return table.concat(chars)
end

function A:ReviewTagText(id)
    local tag=registry[id]
    if not tag then return "" end
    return (tag.positive and "|cff59ff73+" or "|cffff5959-")..tag.name.."|r"
end

function A:ReviewTagsText(value)
    local parts={}
    for _,id in ipairs(self:ReviewTagIds(value) or {}) do parts[#parts+1]=self:ReviewTagText(id) end
    return #parts>0 and table.concat(parts,"  ") or "No tags"
end
