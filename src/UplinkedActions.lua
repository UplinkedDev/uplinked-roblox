local UplinkedActions = {}

-- Internal state
local sections = {}
local schemaVersion = 0

-- Section handle
local SectionHandle = {}
SectionHandle.__index = SectionHandle

function SectionHandle:Group(groupName, actionDefs)
	local sectionData = sections[self._name]
	if not sectionData then return end

	local actions = {}
	for _, def in ipairs(actionDefs) do
		actions[def.name] = def.callback
	end

	sectionData.groups[groupName] = { actions = actions }
	schemaVersion = schemaVersion + 1
end

function SectionHandle:RemoveGroup(groupName)
	local sectionData = sections[self._name]
	if not sectionData then return end

	sectionData.groups[groupName] = nil
	schemaVersion = schemaVersion + 1
end

function UplinkedActions.Section(name)
	if not sections[name] then
		sections[name] = { groups = {} }
		schemaVersion = schemaVersion + 1
	end

	local handle = setmetatable({ _name = name }, SectionHandle)
	return handle
end

function UplinkedActions.GetSchema()
	if next(sections) == nil then
		return nil
	end

	local result = {}
	for sectionName, sectionData in pairs(sections) do
		local groupsList = {}
		for groupName, groupData in pairs(sectionData.groups) do
			local actionNames = {}
			for actionName, _ in pairs(groupData.actions) do
				table.insert(actionNames, actionName)
			end
			table.sort(actionNames)
			table.insert(groupsList, {
				Name = groupName,
				Actions = actionNames,
			})
		end
		table.sort(groupsList, function(a, b) return a.Name < b.Name end)
		table.insert(result, {
			Name = sectionName,
			Groups = groupsList,
		})
	end
	table.sort(result, function(a, b) return a.Name < b.Name end)

	return result
end

function UplinkedActions.GetSchemaVersion()
	return schemaVersion
end

function UplinkedActions.Dispatch(section, group, action, player)
	local sectionData = sections[section]
	if not sectionData then
		warn("Uplinked: no section '" .. section .. "' for action dispatch")
		return false
	end

	local groupData = sectionData.groups[group]
	if not groupData then
		warn("Uplinked: no group '" .. group .. "' in section '" .. section .. "'")
		return false
	end

	local callback = groupData.actions[action]
	if not callback then
		warn("Uplinked: no action '" .. action .. "' in group '" .. group .. "'")
		return false
	end

	local success, err = pcall(callback, group, player)
	if not success then
		warn("Uplinked: action callback error: " .. tostring(err))
	end
	return success
end

return UplinkedActions
