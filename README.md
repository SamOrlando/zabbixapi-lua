# zabbixapi-lua
Lua Interface for Zabbix API

Additional Requirements:
- socket.http
- cjson

Features:
- Hook features for calling outside functions on request calls.

Reference:
- zbxapi (table) - Primary table space for api system
- zbxapi.create(url, username, password) [returns table(meta)]
- self:IsAuthenticated()
- self:Disable()
- self:Enable()
- self:ClearAuthToken()
- self:Authorize(user, password)
- self:GetAuthToken()
- self:Request(method, parms, id)
- self:AddRequestHook(id, method, function, args(...))
  *note: "all" is valid method name for any and all request method calls.
- self:RemoveRequestHook(id, method)
- self:RunRequestHook(method, payload, results) [Should not be called by user)

Example:

local mysrv = zbxapi.create("http://10.10.10.10/", "woot", "myneetpassword")
local results = mysrv:Request("host.get", {hostids = {11451}})
