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
    [11]={name="Uses Crowd Control",positive=true},
    [12]={name="Good Sportsmanship",positive=true},
    [13]={name="Shares Resources",positive=true},
    [14]={name="Responsive",positive=true},
    [15]={name="Careful Pulls",positive=true},
    [33]={name="Ninja Looter",positive=false},
    [34]={name="Toxic",positive=false},
    [35]={name="Griefer",positive=false,retired=true},
    [36]={name="Frequently AFK",positive=false},
    [37]={name="Abandons Groups",positive=false},
    [38]={name="Uncooperative",positive=false},
    [39]={name="Ignores Mechanics",positive=false},
    [40]={name="Reckless Pulls",positive=false},
    [41]={name="Unprepared",positive=false},
    [42]={name="Poor Communication",positive=false},
    [43]={name="Ignores Crowd Control",positive=false},
    [44]={name="Disrespects Loot Rules",positive=false,retired=true},
    [45]={name="Resource Hog",positive=false},
    [46]={name="Poor Leadership",positive=false},
    [47]={name="Elitist",positive=false},
    [48]={name="Underperforms",positive=false},
    [49]={name="Impatient",positive=false},
}
-- Each positive tag and its negative opposite can't be chosen together.
-- Retired tags keep their old conflicts for reviews that still carry them.
local opposite = {[1]={[46]=true},[2]={[38]=true},[3]={[47]=true},[4]={[48]=true},
    [5]={[37]=true},[6]={[49]=true},[7]={[33]=true,[44]=true},[8]={[42]=true},
    [9]={[41]=true},[10]={[39]=true},[11]={[43]=true},[12]={[34]=true,[35]=true},
    [13]={[45]=true},[14]={[36]=true},[15]={[40]=true}}
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

-- Count current reviews in local data, once per original author and target.
-- Authored records take precedence over cached copies, including tombstones.
-- Counts are derived on window open; no extra SavedVariables index is stored.
function A:TagUsageCounts()
    local counts,seen={},{}
    local function add(author,guid,review)
        seen[author]=seen[author] or {}
        if seen[author][guid] then return end
        seen[author][guid]=true
        if type(review)~="table" or review.removed or type(review.score)~="number" or review.score<=0 then return end
        for _,id in ipairs(self:ReviewTagIds(review.tags) or {}) do
            counts[id]=(counts[id] or 0)+1
        end
    end
    local db=self.db or {}
    for author,records in pairs(db.authored or {}) do
        for guid,review in pairs(records) do add(author,guid,review) end
    end
    for guid,target in pairs(db.community or {}) do
        for author,review in pairs(target.votes or {}) do add(author,guid,review) end
    end
    return counts
end

-- Choices are shown in rows of opposites: each positive tag beside its
-- negative counterpart. Rows are ordered by how often either tag of the pair
-- is used, then by the positive tag's name. groups.positive[n] and
-- groups.negative[n] form row n; any tag without an active opposite follows
-- the pairs in its own column, ordered the same way.
function A:SortedReviewTagGroups(counts)
    counts=counts or self:TagUsageCounts()
    local function used(id) return id and (counts[id] or 0) or 0 end
    local rows,paired={},{}
    for id,tag in pairs(registry) do
        if tag.positive and not tag.retired then
            local partner
            for other in pairs(opposite[id] or {}) do
                if registry[other] and not registry[other].retired and (not partner or other<partner) then partner=other end
            end
            rows[#rows+1]={positive=id,negative=partner}
            if partner then paired[partner]=true end
        end
    end
    for id,tag in pairs(registry) do
        if not tag.positive and not tag.retired and not paired[id] then rows[#rows+1]={negative=id} end
    end
    local function name(row) return registry[row.positive or row.negative].name end
    table.sort(rows,function(a,b)
        local ca,cb=used(a.positive)+used(a.negative),used(b.positive)+used(b.negative)
        local fa,fb=a.positive and a.negative and 0 or 1,b.positive and b.negative and 0 or 1
        if fa~=fb then return fa<fb end
        if ca~=cb then return ca>cb end
        return name(a)<name(b)
    end)
    local groups={positive={},negative={}}
    for _,row in ipairs(rows) do
        if row.positive then groups.positive[#groups.positive+1]=row.positive end
        if row.negative then groups.negative[#groups.negative+1]=row.negative end
    end
    return groups
end
