-- Bind the companion-owned communication API after the data API is available.
local _, A = ...
local communication = _G.RateMeCommunicationStore
if type(communication) ~= "table" or type(communication.Bind) ~= "function" then
    error("Rate Me! requires the RateMeCommunication companion addon.")
end
communication:Bind(A)
