local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Uplinked = require(ReplicatedStorage:WaitForChild("Uplinked"))

-- Static actions: Items
local items = Uplinked.Actions.Section("Items")

items:Group("Weapons", {
	{ name = "Rifle", callback = function(group)
		print("Giving Rifle")
	end },
	{ name = "Shotgun", callback = function(group)
		print("Giving Shotgun")
	end },
	{ name = "Pistol", callback = function(group)
		print("Giving Pistol")
	end },
})

items:Group("Armor", {
	{ name = "Shield", callback = function(group)
		print("Giving Shield")
	end },
	{ name = "Helmet", callback = function(group)
		print("Giving Helmet")
	end },
})

-- Dynamic actions: Players
local players = Uplinked.Actions.Section("Players")

Players.PlayerAdded:Connect(function(player)
	players:Group(player.Name, {
		{ name = "Kill", callback = function(group)
			if player.Character and player.Character:FindFirstChild("Humanoid") then
				player.Character.Humanoid.Health = 0
				print("Killed " .. player.Name)
			end
		end },
		{ name = "Heal", callback = function(group)
			if player.Character and player.Character:FindFirstChild("Humanoid") then
				player.Character.Humanoid.Health = player.Character.Humanoid.MaxHealth
				print("Healed " .. player.Name)
			end
		end },
		{ name = "Teleport To", callback = function(group)
			print("Teleport to " .. player.Name)
		end },
	})
end)

Players.PlayerRemoving:Connect(function(player)
	players:RemoveGroup(player.Name)
end)

print("Uplinked: Sample actions registered")
