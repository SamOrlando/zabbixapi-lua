-- Zabbix API
-- Author: Sam Orlando
-- 20160330
-- TODO: Recovery if timeout/disconnect/retry?


local http = require("socket.http")
http.TIMEOUT = 5 --- set timeout if no response to 5 seconds.
local ltn12 = require("ltn12")
local json = require("cjson")

zbxapi = {
	meta = {
		methods = {};
		__index = function(self, key) return rawget(getmetatable(self), "methods")[key] end;
		__tostring = function(self) return string.format("Zabbix API %s - Enabled: %s - Authenticated: %s", self.url, tostring(self.enabled), tostring(self:IsAuthenticated())) end;
	}
}
local method = zbxapi.meta.methods


zbxapi.create = function(url, user, password)
	local tbl = {
		url = url or "http://192.168.1.1/zabbix/";
		user = user or "Admin";
		password = password or "zabbix";
		enabled = true;
		isAPI = true;
		hooks = {
			all = {};
			};
		}
	return setmetatable(tbl, zbxapi.meta)
end

function method:IsAuthenticated()
	if self.auth_token then return true else return false end
end

function method:Disable()
	self.auth_token = nil
	self.enabled = false
end

function method:Enable()
	self.enabled = true
end

function method:ClearAuthToken()
	self.auth_token = nil
end

function method:Authorize(user, password)
	self.user = user or self.user
	self.password = password or self.password
	
	if self:GetAuthToken() then self.enabled = true
	else self.enabled = false end
	return self.enabled
end

function method:GetAuthToken()
	local ptbl = { -- payload table
		jsonrpc = "2.0";
		method = "user.login";
		params = {
			user = self.user;
			password = self.password;
		};
		id = "user.login-" .. tostring(math.random(1,1000)) .. tostring(os.time());
	}
	
	local payload = json.encode(ptbl)
	local response_body = {}
	
	local res, code, response_headers, status = http.request {
		url = self.url .. "api_jsonrpc.php";
		method = "POST";
		headers = {
			["Content-Type"] = "application/json-rpc";
			["Content-Length"] = payload:len();
		};
    		source = ltn12.source.string(payload);
    		sink = ltn12.sink.table(response_body);
	}
	
	-- fix me for timeout and retry option
	if code == "timeout" or code == 404 then
		self:Disable()
		return false
	end
	
	local results = json.decode(response_body[1])
	if results.error then 
		self:Disable()
		return false
	end

	if results.result then
		self.enabled = true
		self.auth_token = results.result
		return true
	end
	
	return false
end

function method:Request(method, params, id)
	if not self.enabled then return {
		error = {
			message = "Zabbix server is disabled via lua api.";
			data = "Disabled server in lua api, must Enable() or do Authorize().";
			code = "-666";
		};
	} end
	
	if not self.auth_token and not self:GetAuthToken() then return {
		error = {
			message = "Unable to authenticate.";
			data = "Unable to verify username and password or server was unreachable.";
			code = "-666";
		};
	} end
	
	local ptbl = { -- payload table
		jsonrpc = "2.0";
		method = method;
		params = params;
		id = id or method .. "-" .. tostring(math.random(1,1000)) .. tostring(os.time());
		auth = self.auth_token;
	}
	
	local payload = json.encode(ptbl)
	local response_body = {}
	
	local res, code, response_headers, status = http.request {
		url = self.url .. "api_jsonrpc.php";
		method = "POST";
		headers = {
			["Content-Type"] = "application/json-rpc";
			["Content-Length"] = payload:len();
		};
    		source = ltn12.source.string(payload);
    		sink = ltn12.sink.table(response_body);
	}

	-- fixme and perhaps share error handling with common routine between auth and request.
	if code == "timeout" or code == 404 then
		self.enabled = false
		return {
			error = {
			message = "Unable to reach service or timeout.";
			data = "Was not able to reach the server, url location or request timeout reached.";
			code = code;
			};
		}
	end
	
	if code == 500 then return {
		error = {
			message = "HTTP 500 - Internal Server Error";
			data = "Server returned an abnormal internal error.";
			code = code;
		};
	} end
	
	local result = json.decode(table.concat(response_body) or {})
	self:RunRequestHook(method, ptbl, result)
	return result

end

function method:AddRequestHook(id, method, func, ...)
	self.hooks[method] = self.hooks[method] or {}
	self.hooks[method][id] = {
		func = func;
		args = {...};
		}
end

function method:RemoveRequestHook(id, method)
	self.hooks[method] = self.hooks[method] or {}
	self.hooks[method][id] = nil
end

function method:RunRequestHook(method, ptbl, result)
	local b,r = false, true
	for k,v in pairs(self.hooks[method] or {}) do
		b, r = pcall(v.func, method, ptbl, result, unpack(v.args))
		if not b then print("Hook ERROR: " .. method .. ":" .. k .. " - " .. tostring(r)) end
	end
	for k,v in pairs(self.hooks.all) do
		b, r= pcall(v.func, method, ptbl, result, unpack(v.args))
		if not b then print("Hook ERROR: all:" .. k .. " - " .. tostring(r)) end
	end
end
