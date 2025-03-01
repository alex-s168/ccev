local ccev = nil
local ccev_io = nil

ccev_io = {
    http = function(params)
        http.request(params)

        local out = ccev.onceSignal()

        ccev.thenSync(ccev.onceEvent({"http_success","http_failure"}, params.url),
        function(ev)
            local val = {}
            if ev[1] == "http_success" then
                val.success = true
                val.response = ev[3]
            else
                val.success = false
                val.error = ev[3]
                val.response = ev[4]
            end
            out:tryNotify(val)
        end)

        return out
    end,
}

return function(ccevIn)
    ccev = ccevIn
    return ccev_io
end
