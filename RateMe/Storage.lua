-- Compatibility bridge: persistent data classes are implemented by RateMeData.
local _, A = ...
local store = _G.RateMeDataStore
if type(store) ~= "table" or type(store.Bind) ~= "function" then
    error("Rate Me! requires the RateMeData companion addon.")
end
store:Bind(A)
