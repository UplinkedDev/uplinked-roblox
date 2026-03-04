local CollectionService = game:GetService("CollectionService")

local UplinkedInspect = {}

local SERVER_ROOT_SERVICES = {
	"Workspace",
	"Players",
	"ReplicatedStorage",
	"ServerStorage",
	"ServerScriptService",
	"Lighting",
	"SoundService",
	"StarterGui",
	"StarterPack",
	"StarterPlayer",
	"Teams",
}

local CLIENT_ROOT_SERVICES = {
	"Workspace",
	"Players",
	"ReplicatedStorage",
	"Lighting",
	"SoundService",
	"StarterGui",
	"StarterPack",
	"StarterPlayer",
}

-- Resolve a slash-delimited path to an Instance
-- Supports [n] index notation for duplicate-named siblings
function UplinkedInspect.ResolvePath(path)
	local current = game
	for segment in string.gmatch(path, "[^/]+") do
		local name, indexStr = string.match(segment, "^(.+)%[(%d+)%]$")
		if name then
			local targetIndex = tonumber(indexStr)
			local count = 0
			local found = nil
			for _, child in ipairs(current:GetChildren()) do
				if child.Name == name then
					count = count + 1
					if count == targetIndex then
						found = child
						break
					end
				end
			end
			current = found
		else
			current = current:FindFirstChild(segment)
		end
		if not current then
			return nil
		end
	end
	return current
end

-- Build slash-delimited path string for an instance
-- Appends [n] index when siblings share the same name
function UplinkedInspect.GetPath(instance)
	local parts = {}
	local current = instance
	while current and current ~= game do
		local segment = current.Name
		if current.Parent then
			local count = 0
			local index = 0
			for _, sibling in ipairs(current.Parent:GetChildren()) do
				if sibling.Name == current.Name then
					count = count + 1
					if sibling == current then
						index = count
					end
				end
			end
			if count > 1 then
				segment = segment .. "[" .. index .. "]"
			end
		end
		table.insert(parts, 1, segment)
		current = current.Parent
	end
	return table.concat(parts, "/")
end

-- Serialize direct children of an instance
function UplinkedInspect.GetChildren(instance, source)
	-- Root level: return curated service list
	if instance == game then
		local serviceNames = source == "Client" and CLIENT_ROOT_SERVICES or SERVER_ROOT_SERVICES
		local children = {}
		for _, name in ipairs(serviceNames) do
			local ok, service = pcall(function()
				return game:GetService(name)
			end)
			if ok and service then
				table.insert(children, {
					Name = name,
					ClassName = service.ClassName,
					Path = name,
					HasChildren = #service:GetChildren() > 0,
				})
			end
		end
		return children
	end

	local children = {}
	for _, child in ipairs(instance:GetChildren()) do
		table.insert(children, {
			Name = child.Name,
			ClassName = child.ClassName,
			Path = UplinkedInspect.GetPath(child),
			HasChildren = #child:GetChildren() > 0,
		})
	end
	table.sort(children, function(a, b) return a.Name < b.Name end)
	return children
end

-- Read common properties based on ClassName (no GetProperties API in Luau)
function UplinkedInspect.GetProperties(instance)
	local props = {}

	-- Universal
	props["Name"] = instance.Name
	props["ClassName"] = instance.ClassName
	props["Parent"] = instance.Parent and instance.Parent.Name or "nil"

	-- BasePart
	if instance:IsA("BasePart") then
		props["Position"] = tostring(instance.Position)
		props["Size"] = tostring(instance.Size)
		props["CFrame"] = tostring(instance.CFrame)
		props["Anchored"] = tostring(instance.Anchored)
		props["CanCollide"] = tostring(instance.CanCollide)
		props["Transparency"] = tostring(instance.Transparency)
		props["Color"] = tostring(instance.Color)
		props["Material"] = tostring(instance.Material)
		props["BrickColor"] = tostring(instance.BrickColor)
		props["Massless"] = tostring(instance.Massless)
	end

	-- Model
	if instance:IsA("Model") then
		if instance.PrimaryPart then
			props["PrimaryPart"] = instance.PrimaryPart.Name
		end
		props["WorldPivot"] = tostring(instance:GetPivot())
	end

	-- Humanoid
	if instance:IsA("Humanoid") then
		props["Health"] = tostring(instance.Health)
		props["MaxHealth"] = tostring(instance.MaxHealth)
		props["WalkSpeed"] = tostring(instance.WalkSpeed)
		props["JumpPower"] = tostring(instance.JumpPower)
		props["HipHeight"] = tostring(instance.HipHeight)
	end

	-- GuiObject
	if instance:IsA("GuiObject") then
		props["Position"] = tostring(instance.Position)
		props["Size"] = tostring(instance.Size)
		props["Visible"] = tostring(instance.Visible)
		props["BackgroundColor3"] = tostring(instance.BackgroundColor3)
		props["BackgroundTransparency"] = tostring(instance.BackgroundTransparency)
		props["ZIndex"] = tostring(instance.ZIndex)
	end

	-- Text objects
	if instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox") then
		props["Text"] = instance.Text
		props["TextColor3"] = tostring(instance.TextColor3)
		props["TextSize"] = tostring(instance.TextSize)
		props["Font"] = tostring(instance.Font)
	end

	-- Light
	if instance:IsA("Light") then
		props["Brightness"] = tostring(instance.Brightness)
		props["Color"] = tostring(instance.Color)
		props["Enabled"] = tostring(instance.Enabled)
		props["Range"] = tostring(instance.Range)
	end

	-- Script
	if instance:IsA("LuaSourceContainer") then
		props["Disabled"] = tostring(instance.Disabled)
	end

	-- ValueBase (IntValue, StringValue, etc.)
	if instance:IsA("ValueBase") then
		local ok, val = pcall(function() return instance.Value end)
		if ok then
			props["Value"] = tostring(val)
		end
	end

	return props
end

-- Get attributes as a flat dictionary
function UplinkedInspect.GetAttributes(instance)
	local attrs = instance:GetAttributes()
	local result = {}
	for key, value in pairs(attrs) do
		result[key] = tostring(value)
	end
	return result
end

-- Get tags as an array of strings
function UplinkedInspect.GetTags(instance)
	return CollectionService:GetTags(instance)
end

-- Parse a string value into the appropriate Lua/Roblox type
-- Uses the current value to infer the target type
function UplinkedInspect.ParseValue(str, currentValue)
	local valueType = typeof(currentValue)

	if valueType == "number" then
		return tonumber(str)
	elseif valueType == "boolean" then
		local lower = string.lower(str)
		if lower == "true" then return true end
		if lower == "false" then return false end
		return nil
	elseif valueType == "string" then
		return str
	elseif valueType == "Vector3" then
		local x, y, z = string.match(str, "([%d%.%-]+)%s*,%s*([%d%.%-]+)%s*,%s*([%d%.%-]+)")
		if x then return Vector3.new(tonumber(x), tonumber(y), tonumber(z)) end
		return nil
	elseif valueType == "Color3" then
		local r, g, b = string.match(str, "([%d%.%-]+)%s*,%s*([%d%.%-]+)%s*,%s*([%d%.%-]+)")
		if r then return Color3.new(tonumber(r), tonumber(g), tonumber(b)) end
		return nil
	elseif valueType == "BrickColor" then
		return BrickColor.new(str)
	elseif valueType == "EnumItem" then
		-- Try to resolve e.g. "Enum.Material.Plastic" or just "Plastic"
		local enumType = tostring(currentValue.EnumType)
		local ok, result = pcall(function()
			return (Enum :: any)[enumType][str]
		end)
		if ok then return result end
		-- Try full path like "Enum.Material.Plastic"
		local _, _, enumVal = string.find(str, "Enum%.%w+%.(%w+)")
		if enumVal then
			local ok2, result2 = pcall(function()
				return (Enum :: any)[enumType][enumVal]
			end)
			if ok2 then return result2 end
		end
		return nil
	elseif valueType == "UDim2" then
		-- Accept both "{sx, ox}, {sy, oy}" (tostring format) and "sx, ox, sy, oy"
		local sx, ox, sy, oy = string.match(str, "{%s*([%d%.%-]+)%s*,%s*([%d%.%-]+)%s*}%s*,%s*{%s*([%d%.%-]+)%s*,%s*([%d%.%-]+)%s*}")
		if not sx then
			sx, ox, sy, oy = string.match(str, "([%d%.%-]+)%s*,%s*([%d%.%-]+)%s*,%s*([%d%.%-]+)%s*,%s*([%d%.%-]+)")
		end
		if sx then return UDim2.new(tonumber(sx), tonumber(ox), tonumber(sy), tonumber(oy)) end
		return nil
	elseif valueType == "UDim" then
		-- Accept both "{s, o}" (tostring format) and "s, o"
		local s, o = string.match(str, "{%s*([%d%.%-]+)%s*,%s*([%d%.%-]+)%s*}")
		if not s then
			s, o = string.match(str, "([%d%.%-]+)%s*,%s*([%d%.%-]+)")
		end
		if s then return UDim.new(tonumber(s), tonumber(o)) end
		return nil
	elseif valueType == "Vector2" then
		local x, y = string.match(str, "([%d%.%-]+)%s*,%s*([%d%.%-]+)")
		if x then return Vector2.new(tonumber(x), tonumber(y)) end
		return nil
	end

	-- Fallback: return the string as-is
	return str
end

-- Set a property on an instance
function UplinkedInspect.SetProperty(instance, propertyName, valueStr)
	local ok, currentValue = pcall(function()
		return (instance :: any)[propertyName]
	end)
	if not ok then
		return false, "Cannot read property: " .. propertyName
	end

	local parsed = UplinkedInspect.ParseValue(valueStr, currentValue)
	if parsed == nil and valueStr ~= "nil" then
		return false, "Cannot parse value for " .. propertyName .. " (type: " .. typeof(currentValue) .. ")"
	end

	local setOk, setErr = pcall(function()
		(instance :: any)[propertyName] = parsed
	end)
	if not setOk then
		return false, "Failed to set " .. propertyName .. ": " .. tostring(setErr)
	end
	return true, nil
end

-- Set an attribute on an instance
function UplinkedInspect.SetAttribute(instance, attrName, valueStr)
	local currentValue = instance:GetAttribute(attrName)

	if currentValue ~= nil then
		local parsed = UplinkedInspect.ParseValue(valueStr, currentValue)
		if parsed == nil and valueStr ~= "nil" then
			return false, "Cannot parse value for attribute: " .. attrName
		end
		instance:SetAttribute(attrName, parsed)
	else
		-- New attribute or nil current — try number, then boolean, then string
		local num = tonumber(valueStr)
		if num then
			instance:SetAttribute(attrName, num)
		elseif string.lower(valueStr) == "true" then
			instance:SetAttribute(attrName, true)
		elseif string.lower(valueStr) == "false" then
			instance:SetAttribute(attrName, false)
		else
			instance:SetAttribute(attrName, valueStr)
		end
	end

	return true, nil
end

-- Highlight management
local activeHighlight = nil -- { path = string, instances = { Instance } }

local function clearHighlight()
	if activeHighlight then
		for _, inst in ipairs(activeHighlight.instances) do
			inst:Destroy()
		end
		activeHighlight = nil
	end
end

function UplinkedInspect.SetHighlight(instance, path)
	clearHighlight()

	if instance:IsA("BasePart") or instance:IsA("Model") then
		local highlight = Instance.new("Highlight")
		highlight.Name = "UplinkedHighlight"
		highlight.FillColor = Color3.fromRGB(34, 197, 94)
		highlight.FillTransparency = 0.7
		highlight.OutlineColor = Color3.fromRGB(134, 239, 172)
		highlight.OutlineTransparency = 0
		highlight.Parent = instance
		activeHighlight = { path = path, instances = { highlight } }
	elseif instance:IsA("GuiObject") then
		local stroke = Instance.new("UIStroke")
		stroke.Name = "UplinkedHighlight"
		stroke.Color = Color3.fromRGB(34, 197, 94)
		stroke.Thickness = 2
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = instance
		activeHighlight = { path = path, instances = { stroke } }
	elseif instance:IsA("ScreenGui") or instance:IsA("SurfaceGui") or instance:IsA("BillboardGui") then
		local frame = Instance.new("Frame")
		frame.Name = "UplinkedHighlight"
		frame.Size = UDim2.new(1, 0, 1, 0)
		frame.BackgroundColor3 = Color3.fromRGB(34, 197, 94)
		frame.BackgroundTransparency = 0.85
		frame.BorderSizePixel = 0
		frame.ZIndex = 2147483647
		frame.Parent = instance

		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(34, 197, 94)
		stroke.Thickness = 2
		stroke.Parent = frame

		activeHighlight = { path = path, instances = { frame } }
	end
end

-- Validate that a path starts with an allowed root service
local function isAllowedRoot(path, source)
	if path == "" or path == "game" then return true end
	local rootSegment = string.match(path, "^([^/]+)")
	if not rootSegment then return true end
	-- Strip index notation like "Workspace[2]"
	rootSegment = string.match(rootSegment, "^(.+)%[%d+%]$") or rootSegment
	local allowedServices = source == "Client" and CLIENT_ROOT_SERVICES or SERVER_ROOT_SERVICES
	for _, name in ipairs(allowedServices) do
		if name == rootSegment then return true end
	end
	return false
end

-- Process a single inspect request and return the result table
function UplinkedInspect.HandleRequest(request)
	local path = request.path or request.Path or ""
	local reqType = request.type or request.Type
	local requestId = request.requestId or request.RequestId
	local source = request.source or request.Source or "Server"

	local result = {
		RequestId = requestId,
		Path = path,
		Source = source,
	}

	-- Validate path root against allowed services
	if not isAllowedRoot(path, source) then
		result.Type = reqType == "GetChildren" and "Children" or "Properties"
		result.Error = "Access denied: path not in allowed services"
		return result
	end

	-- Resolve instance
	local instance
	if path == "" or path == "game" then
		instance = game
	else
		instance = UplinkedInspect.ResolvePath(path)
	end

	if not instance then
		result.Type = reqType == "GetChildren" and "Children" or "Properties"
		result.Error = "Instance not found at path: " .. tostring(path)
		return result
	end

	if reqType == "GetChildren" then
		result.Type = "Children"
		result.Children = UplinkedInspect.GetChildren(instance, source)
	elseif reqType == "GetProperties" then
		result.Type = "Properties"
		result.Properties = UplinkedInspect.GetProperties(instance)
		local attrs = UplinkedInspect.GetAttributes(instance)
		if next(attrs) then
			result.Attributes = attrs
		end
		local tags = UplinkedInspect.GetTags(instance)
		if #tags > 0 then
			result.Tags = tags
		end
	elseif reqType == "SetProperty" then
		result.Type = "SetPropertyResult"
		local propertyName = request.propertyName or request.PropertyName
		local propertyValue = request.propertyValue or request.PropertyValue
		if not propertyName then
			result.Error = "Missing propertyName"
		else
			local success, err = UplinkedInspect.SetProperty(instance, propertyName, propertyValue or "")
			if not success then
				result.Error = err
			end
		end
	elseif reqType == "SetAttribute" then
		result.Type = "SetAttributeResult"
		local propertyName = request.propertyName or request.PropertyName
		local propertyValue = request.propertyValue or request.PropertyValue
		if not propertyName then
			result.Error = "Missing propertyName"
		else
			local success, err = UplinkedInspect.SetAttribute(instance, propertyName, propertyValue or "")
			if not success then
				result.Error = err
			end
		end
	elseif reqType == "Highlight" then
		result.Type = "Highlight"
		UplinkedInspect.SetHighlight(instance, path)
	end

	return result
end

return UplinkedInspect
