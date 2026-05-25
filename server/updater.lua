local function debugPrint(...)
    if Config.Debug then
        print("[timeclock Debug]", ...)
    end
end

local scriptName = "TIMECLOCK"
local scriptUrl = "timeclock"

AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        print("^2["..scriptName .."]^0 Server-side script loaded, developed by EddiesLife247 Scripts. Support at: https://discord.eddieslife247.co.uk/")

        -- Check for updates asynchronously
        PerformHttpRequest("https://eddieslife247.co.uk/".. scriptUrl .."/version.txt", function(statusCode, response, headers)
            if statusCode == 200 and response then
                local currentVersion = GetResourceMetadata(GetCurrentResourceName(), "version", 0)
                local remoteVersion = response:match("%S+") -- Extract the version string

                if remoteVersion and currentVersion ~= remoteVersion then
                    print("^3["..scriptName .."]^0 A New Update is available on the keymaster site! Version: " .. remoteVersion)
                else
                    print("^2["..scriptName .."]^0 You are using the latest version.")
                end
            else
                print("^1["..scriptName .."]^0 Failed to check for updates. Status Code: " .. tostring(statusCode))
            end
        end, "GET", "", {['Content-Type'] = 'text/plain'})
    end
end)
