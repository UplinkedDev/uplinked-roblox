local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Uplinked = require(ReplicatedStorage:WaitForChild("Uplinked"))

Uplinked.Server.Start({
	-- BackendUrl = "http://localhost:5041", -- Optional, defaults to https://uplinked.dev/api
	Password = "changeme", -- Required password for web clients to connect
})
