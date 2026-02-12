local HttpService = game:GetService("HttpService")
local LogService = game:GetService("LogService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local UplinkedServer = {}

-- Deferred: loaded in Start() to avoid blocking early log capture
local UplinkedActions
local UplinkedInspect

local REMOTE_EVENT_NAME = "UplinkedEvent"
local MAX_CLIENT_LOG_LENGTH = 1000
local MAX_CLIENT_LOGS_PER_INTERVAL = 50
local LOG_RATE_INTERVAL = 2

local VALID_LOG_LEVELS = { Info = true, Warn = true, Error = true }

local MESSAGE_TYPE_TO_LEVEL = {
	[Enum.MessageType.MessageWarning] = "Warn",
	[Enum.MessageType.MessageError] = "Error",
}

-- Module state (set by Start)
local config = nil
local remoteEvent = nil
local activeSessions = {}
local playerLogRates = {} -- player -> { count: number, resetTime: number }
local playerDeviceInfo = {} -- player -> { Locale, Resolution, GraphicsQuality, SafeArea, Inputs }
local globalLogBuffer = {} -- all server logs since game start
local MAX_GLOBAL_LOG_BUFFER = 5000

-- Backfill logs that happened before this module was required
for _, entry in ipairs(LogService:GetLogHistory()) do
	local level = MESSAGE_TYPE_TO_LEVEL[entry.messageType] or "Info"
	table.insert(globalLogBuffer, {
		Message = entry.message,
		Level = level,
		Timestamp = entry.timestamp,
		Source = "Server",
	})
end

-- Capture all future logs
LogService.MessageOut:Connect(function(message, messageType)
	local level = MESSAGE_TYPE_TO_LEVEL[messageType] or "Info"
	local log = {
		Message = message,
		Level = level,
		Timestamp = os.time(),
		Source = "Server",
	}
	table.insert(globalLogBuffer, log)
	if #globalLogBuffer > MAX_GLOBAL_LOG_BUFFER then
		table.remove(globalLogBuffer, 1)
	end
	for _, session in pairs(activeSessions) do
		table.insert(session.LogBuffer, log)
	end
end)

local function getServerType()
	if game.PrivateServerId ~= "" then
		if game.PrivateServerOwnerId == 0 then
			return "Reserved"
		end
		return "VIP"
	end
	return "Public"
end

local function getServerInfo()
	local playerList = {}
	for _, player in Players:GetPlayers() do
		local info = {
			Name = player.Name,
			DisplayName = player.DisplayName,
			UserId = player.UserId,
		}
		local deviceInfo = playerDeviceInfo[player]
		if deviceInfo then
			info.Locale = deviceInfo.Locale
			info.Resolution = deviceInfo.Resolution
			info.GraphicsQuality = deviceInfo.GraphicsQuality
			info.SafeArea = deviceInfo.SafeArea
			info.Inputs = deviceInfo.Inputs
		end
		table.insert(playerList, info)
	end
	return {
		UniverseId = game.GameId,
		PlaceId = game.PlaceId,
		JobId = game.JobId,
		PlaceVersion = game.PlaceVersion,
		ServerType = getServerType(),
		Platform = RunService:IsStudio() and "Studio" or "Production",
		Players = playerList,
	}
end

local function checkLogRate(player)
	local now = os.clock()
	local tracker = playerLogRates[player]
	if not tracker or now >= tracker.resetTime then
		playerLogRates[player] = { count = 1, resetTime = now + LOG_RATE_INTERVAL }
		return true
	end
	tracker.count = tracker.count + 1
	return tracker.count <= MAX_CLIENT_LOGS_PER_INTERVAL
end

local function bufferClientLog(message, level, player)
	local log = {
		Message = message,
		Level = level,
		Timestamp = os.time(),
		Source = "Client",
	}

	local session = activeSessions[player]
	if session then
		table.insert(session.LogBuffer, log)
	end
end

local function endSession(player)
	local session = activeSessions[player]
	if not session then return end

	activeSessions[player] = nil
	playerLogRates[player] = nil
	playerDeviceInfo[player] = nil
	local ok, err = pcall(function()
		HttpService:PostAsync(
			config.BackendUrl .. "/api/end-session",
			HttpService:JSONEncode({ SessionCode = session.Code, Password = session.Password }),
			Enum.HttpContentType.ApplicationJson
		)
	end)
	if not ok then
		warn("Uplinked: failed to end session: " .. tostring(err))
	end
end

function UplinkedServer.Start(options)
	assert(options, "UplinkedServer.Start requires a config table")

	UplinkedActions = require(script.Parent.UplinkedActions)
	UplinkedInspect = require(script.Parent.UplinkedInspect)

	config = {
		BackendUrl = options.BackendUrl or "https://uplinked.dev/api",
		Password = options.Password or nil,
		FlushInterval = options.FlushInterval or 2,
		PollInterval = options.PollInterval or 1,
	}

	remoteEvent = Instance.new("RemoteEvent")
	remoteEvent.Name = REMOTE_EVENT_NAME
	remoteEvent.Parent = ReplicatedStorage

	remoteEvent.OnServerEvent:Connect(function(player, payload)
		if type(payload) ~= "table" or type(payload.Type) ~= "string" then
			return
		end

		if payload.Type == "Log" then
			if type(payload.Data) ~= "table" then return end
			if type(payload.Data.Message) ~= "string" then return end

			if not checkLogRate(player) then return end

			local message = payload.Data.Message
			if #message > MAX_CLIENT_LOG_LENGTH then
				message = string.sub(message, 1, MAX_CLIENT_LOG_LENGTH)
			end
			local level = VALID_LOG_LEVELS[payload.Data.Level] and payload.Data.Level or "Info"

			local msg = string.format("[%s] %s", player.Name, message)
			bufferClientLog(msg, level, player)
		elseif payload.Type == "InspectResult" then
			local data = payload.Data
			if type(data) ~= "table" then return end
			if type(data.RequestId) ~= "string" then return end
			if type(data.Type) ~= "string" then return end
			if type(data.Path) ~= "string" then return end

			local session = activeSessions[player]
			if session then
				local ok, err = pcall(function()
					HttpService:PostAsync(
						config.BackendUrl .. "/api/inspect-result",
						HttpService:JSONEncode({
							SessionCode = session.Code,
							Password = session.Password,
							Result = data,
						}),
						Enum.HttpContentType.ApplicationJson
					)
				end)
				if not ok then
					warn("Uplinked: failed to send inspect result: " .. tostring(err))
				end
			end
		elseif payload.Type == "PlayerInfo" then
			local data = payload.Data
			if type(data) ~= "table" then return end
			playerDeviceInfo[player] = {
				Locale = type(data.Locale) == "string" and data.Locale or nil,
				Resolution = type(data.Resolution) == "string" and data.Resolution or nil,
				GraphicsQuality = type(data.GraphicsQuality) == "string" and data.GraphicsQuality or nil,
				SafeArea = type(data.SafeArea) == "string" and data.SafeArea or nil,
				Inputs = type(data.Inputs) == "table" and data.Inputs or nil,
			}
		elseif payload.Type == "EndSession" then
			if activeSessions[player] then
				endSession(player)
				remoteEvent:FireClient(player, { Type = "SessionEnded" })
			end
		elseif payload.Type == "RequestSession" then
			if activeSessions[player] then
				remoteEvent:FireClient(player, {
					Type = "SessionCode",
					Code = activeSessions[player].Code,
				})
				return
			end

			local success, response = pcall(function()
				return HttpService:PostAsync(
					config.BackendUrl .. "/api/session",
					HttpService:JSONEncode({ Password = config.Password }),
					Enum.HttpContentType.ApplicationJson
				)
			end)

			if success then
				local data = HttpService:JSONDecode(response)

				-- Replay global log buffer into the new session
				local replayedLogs = {}
				for _, log in ipairs(globalLogBuffer) do
					table.insert(replayedLogs, log)
				end

				activeSessions[player] = {
					Code = data.sessionCode,
					Password = config.Password,
					LogBuffer = replayedLogs,
					LastSchemaVersion = 0,
				}
				remoteEvent:FireClient(player, {
					Type = "SessionCode",
					Code = data.sessionCode,
				})
				print("Uplinked: session created for " .. player.Name)
			else
				warn("Uplinked: failed to create session for " .. player.Name .. ": " .. tostring(response))
				remoteEvent:FireClient(player, {
					Type = "SessionError",
					Message = "Failed to create session",
				})
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		endSession(player)
	end)

	game:BindToClose(function()
		for player in pairs(activeSessions) do
			endSession(player)
		end
	end)

	-- Flush logs for all active sessions
	task.spawn(function()
		while true do
			task.wait(config.FlushInterval)

			local currentSchemaVersion = UplinkedActions.GetSchemaVersion()
			local serverInfo = getServerInfo()

			for player, session in pairs(activeSessions) do
				local schemaChanged = currentSchemaVersion ~= session.LastSchemaVersion

				if #session.LogBuffer == 0 and not schemaChanged then
					continue
				end

				local logsToSend = session.LogBuffer
				session.LogBuffer = {}

				local payload = {
					SessionCode = session.Code,
					Password = session.Password,
					Logs = logsToSend,
					ServerInfo = serverInfo,
				}

				if schemaChanged then
					payload.ActionSchema = UplinkedActions.GetSchema()
				end

				local success, err = pcall(function()
					HttpService:PostAsync(
						config.BackendUrl .. "/api/ingest",
						HttpService:JSONEncode(payload),
						Enum.HttpContentType.ApplicationJson
					)
				end)

				if not success then
					warn("Uplinked: failed to ingest logs: " .. tostring(err))
				end

				if success and schemaChanged then
					session.LastSchemaVersion = currentSchemaVersion
				end
			end
		end
	end)

	-- Poll for pending actions and inspect requests
	task.spawn(function()
		while true do
			task.wait(config.PollInterval)

			for player, session in pairs(activeSessions) do
				local success, response = pcall(function()
					return HttpService:PostAsync(
						config.BackendUrl .. "/api/poll",
						HttpService:JSONEncode({ SessionCode = session.Code, Password = session.Password }),
						Enum.HttpContentType.ApplicationJson
					)
				end)

				if success then
					local pollData = HttpService:JSONDecode(response)

					local actions = pollData.actions or {}
					for _, actionReq in ipairs(actions) do
						task.spawn(function()
							UplinkedActions.Dispatch(actionReq.section, actionReq.group, actionReq.action, player)
						end)
					end

					local inspectRequests = pollData.inspectRequests or {}
					for _, inspectReq in ipairs(inspectRequests) do
						task.spawn(function()
							local source = inspectReq.source or "Server"

							if source == "Client" then
								remoteEvent:FireClient(player, {
									Type = "InspectRequest",
									Data = inspectReq,
								})
							else
								local result = UplinkedInspect.HandleRequest(inspectReq)
								local ok, err = pcall(function()
									HttpService:PostAsync(
										config.BackendUrl .. "/api/inspect-result",
										HttpService:JSONEncode({
											SessionCode = session.Code,
											Password = session.Password,
											Result = result,
										}),
										Enum.HttpContentType.ApplicationJson
									)
								end)
								if not ok then
									warn("Uplinked: failed to send inspect result: " .. tostring(err))
								end
							end
						end)
					end
				else
					warn("Uplinked: poll failed: " .. tostring(response))
				end
			end
		end
	end)

	print("Uplinked: Server started")
end

return UplinkedServer
