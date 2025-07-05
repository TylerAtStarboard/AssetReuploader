local CoreGui = game:GetService("CoreGui")
local Selection = game:GetService("Selection")
local RunService = game:GetService("RunService")
local MaterialService = game:GetService("MaterialService")
local StudioService = game:GetService("StudioService")
local GroupService = game:GetService("GroupService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ChangeHistory = game:GetService("ChangeHistoryService")
local ServerStorage = game:GetService("ServerStorage")
local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local AssetService = game:GetService("AssetService")

local Resources = script.Parent.Resources
local Components = script.Parent.Components
local Packages = script.Parent.Packages
local Modules = script.Parent.Modules

local Promise = require(Modules.Promise)
local Maid = require(Modules.Maid)
local LoadingSprites = require(Modules.Sprites)

local Fusion = require(Packages.Fusion)

local StudioComponents = Components.StudioComponents
local Slider = require(StudioComponents.Slider)
local Label = require(StudioComponents.Label)
local Background = require(StudioComponents.Background)
local Button = require(StudioComponents.Button)
local ProgressBar = require(StudioComponents.ProgressBar)
local Checkbox = require(StudioComponents.Checkbox)
local BoxBorder = require(StudioComponents.BoxBorder)
local TextInput = require(StudioComponents.TextInput)
local ScrollFrame = require(StudioComponents.ScrollFrame)
local VerticalExpandingList = require(StudioComponents.VerticalExpandingList)
local Dropdown = require(StudioComponents.Dropdown)
local ColorPicker = require(StudioComponents.ColorPicker)
local IconButton = require(StudioComponents.IconButton)
local Loading = require(StudioComponents.Loading)
local VerticalCollapsibleSection = require(StudioComponents.VerticalCollapsibleSection)

pcall(function()
	CoreGui.AssetReuploaderUI:Destroy()
end)
local CoreUI = Resources.AssetReuploaderUI:Clone()
CoreUI.Parent = CoreGui 
local ViewportFrame = CoreUI.ViewportFrame

local CurrentCameraValue = Fusion.Value(workspace.CurrentCamera)
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	CurrentCameraValue:set(workspace.CurrentCamera)
end)
Fusion.Hydrate(ViewportFrame)
{
	CurrentCamera = CurrentCameraValue
}

local toolbar = plugin:CreateToolbar("Asset Reuploader")

local button = toolbar:CreateButton("Asset Reuploader", "Reupload Assets", "")
button.ClickableWhenViewportHidden = true


local bg


--[[ Plugin Save/Load]]

local SettingCache = {}

local function GetSetting(i)
	if SettingCache[i] then
		return SettingCache[i]
	else
		return plugin:GetSetting(i)
	end
end
local function SetSetting(i,v)
	plugin:SetSetting(i,v)
	SettingCache[i] = v
end


local SavedPlayerAPIKey = GetSetting("PlayerAPIKey")
local SavedGroupAPIKey = GetSetting("GroupAPIKey")

local SavedGroupOwner = GetSetting("GroupOwner")

local SavedUploadAssetType = GetSetting("UploadAssetType")
--



local UserId = StudioService:GetUserId()
local Username = Players:GetNameFromUserIdAsync(UserId)
local Groups = GroupService:GetGroupsAsync(UserId)

local CanUploadToGroup = Fusion.Value(#Groups > 0)

table.sort(Groups,function(a,b)
	local scoreA = a.Rank
	local scoreB = b.Rank
	if a.IsPrimary then
		scoreA += 256
	end
	if b.IsPrimary then
		scoreB += 256
	end
	return scoreA > scoreB
end)



local ReplacingImages = {
	ShirtTemplate = Fusion.Value(true),
	PantsTemplate = Fusion.Value(true),
	Texture = Fusion.Value(true),
	Image = Fusion.Value(true),
	TextureID = Fusion.Value(true),
	TextureId = Fusion.Value(true),
	ColorMap = Fusion.Value(true)
}
local ReplacingMeshes = {
	MeshId = Fusion.Value(true)
}

local ReplacingOrderImages = {"ShirtTemplate","PantsTemplate","Texture","Image","TextureID","TextureId","ColorMap"}
local ReplacingOrderMeshes = {"MeshId"}

local UploadAssetType = Fusion.Value(SavedUploadAssetType or "Images")

local GroupOwner = Fusion.Value(SavedGroupOwner and CanUploadToGroup or false)

local SelectedGroup = Fusion.Value(Groups[1])

local ID = Fusion.Computed(function()
	if GroupOwner:get() and SelectedGroup:get() then
		return SelectedGroup:get().Id
	else
		return UserId
	end
end)

local API_Key = Fusion.Value("")

local OnlyUnderSelection = Fusion.Value(true)
local SelectAssetsAfterSearch = Fusion.Value(true)

local Searching = Fusion.Value(false)




local SearchMaid = Maid.new()
local SearchPromise
local FoundInstances = Fusion.Value({})
local NumSkippedInstances = Fusion.Value(0)
local RanSearch = Fusion.Value(false)
local SelectingGroup = Fusion.Value(false)

local NotSelectingGroup = Fusion.Computed(function() return not SelectingGroup:get() end)
local NumSelected = Fusion.Value(#Selection:Get())

Selection.SelectionChanged:Connect(function()
	NumSelected:set(#Selection:get())
end)

local CanSearch = Fusion.Computed(function()
	if OnlyUnderSelection:get() then
		if NumSelected:get() > 1 then 
			return false
		end
	end
	return true
end)
local ValidIDAndAPIKey = Fusion.Computed(function()
	return tonumber(ID:get()) ~= nil and (API_Key:get():match("%S") or UploadAssetType:get() ~= "Images")
end)

local ProgressString = Fusion.Value("")

local function RunSearch()
	if SearchPromise then
		SearchMaid:Cleanup()
	end	

	SearchMaid:Add(function()
		if SearchPromise then
			SearchPromise:cancel()
			Searching:set(nil)
		end
	end)

	SearchPromise = Promise.new(function(resolve,reject)
		local startAt = if OnlyUnderSelection:get() then Selection:Get()[1] else game 
		local currentFound = 0
		
		local open = {startAt}
		
		local list = {}
		local NumSkipped = 0
		local assetTypeAnimation = UploadAssetType:get() == "Animations"
		
		local replacing = if UploadAssetType:get() == "Meshes" then ReplacingMeshes else ReplacingImages
		
		local function run(checkingInstance)
			local foundID
			local foundProperty
			
			if assetTypeAnimation then
				if checkingInstance:IsA("Animation") then
					foundProperty = "AnimationId"
					foundID = checkingInstance.AnimationId
				end
			else
				for property,fusionVal in replacing do 
					if not fusionVal:get() then
						continue
					end

					local flagged = {}

					if checkingInstance:FindFirstChild(property) then
						for i,child in checkingInstance:GetChildren() do 
							if child.Name == property then
								child.Name = "Temp"
								table.insert(flagged,child)
							end
						end
					end

					local success,id = pcall(function()
						return checkingInstance[property]
					end)

					for i,child in flagged do 
						child.Name = property
					end

					if success then
						foundID = id
						foundProperty = property 
						break
					end
				end
			end
			
			if foundID then
				if foundID:match("%S") then
					
					local ValidID = false
					
					local idNumber = foundID:match("%d+")
					if idNumber then
						idNumber = tonumber(idNumber)
						
						local success,productInfo = pcall(function()
							return MarketplaceService:GetProductInfo(idNumber)
						end)
						if success and productInfo then
							local creatorID = productInfo.Creator.CreatorTargetId
							local creatorType = productInfo.Creator.CreatorType
							
							local ownerID = tonumber(ID:get())
							
							local creatorTypeMatches = (GroupOwner:get() and creatorType == "Group") or (not GroupOwner:get() and creatorType == "User")
							local creatorMatches = creatorTypeMatches and creatorID == ownerID
									
							currentFound += 1 
							ProgressString:set(`Searching... ({currentFound} instances found)`)
							
							if creatorMatches or not ownerID then
								ValidID = false
								NumSkipped += 1
							else
								ValidID = true
							end
						end
					end
					
					
					if ValidID then
						table.insert(list,{
							instance = checkingInstance,
							property = foundProperty,
							id = foundID
						})
					end
				end
			end
		end

		local t0 = os.clock()

		local runDuration = 200e-3 -- before yielding
		local runUntil = os.clock() + runDuration

		while next(open) do
			local popped = table.remove(open)
			if popped then
				run(popped)
				for i,child in popped:GetChildren() do 
					table.insert(open,child)
				end
			else
				break
			end
			if os.clock() > runUntil then
				task.wait()
				runUntil = os.clock() + runDuration
			end
		end		
		resolve(list,NumSkipped)
	end)
	Searching:set(SearchPromise)
	SearchPromise:andThen(function(list,numSkipped)
		FoundInstances:set(list)
		NumSkippedInstances:set(numSkipped)
		RanSearch:set(true)
		Searching:set(nil)
		
		if SelectAssetsAfterSearch:get() then
			local sel = {}
			for i,v in list do 
				table.insert(sel,v.instance)
			end
			Selection:Set(sel)
		end
	end)
end


local ServerPromise
local ServerRunning = Fusion.Value(false)

local NotRunning = Fusion.Computed(function()
	return not ServerRunning:get() and not Searching:get()
end)

local function RunServer(params)
	if ServerRunning:get() then
		return
	end

	ProgressString:set("Connecting...")
	
	RanSearch:set(false)

	local ServerPromise = Promise.new(function(resolve, reject)
		local assetIDs = params.assetIDs
		local CreatorID = params.CreatorID
		local APIKey = params.APIKey
		local UploadUnderGroup = (GroupOwner:get() ~= false)
		
	-- 1) Tell the Node server to start the upload job
		local success, response = pcall(function()
			return HttpService:PostAsync(
				"http://localhost:3000/upload",
				HttpService:JSONEncode({
					assetIDs = assetIDs,
					creatorID = CreatorID,
					isGroup   = UploadUnderGroup,
					apiKey    = APIKey,
					uploadType = UploadAssetType:get(), -- Either "Animations", "Meshes", or "Images"
					cookie = nil -- Can provide your own if rbx-cookie doesnt work I guess?
				}),
				Enum.HttpContentType.ApplicationJson,
				false
			)
		end)

		if not success then
			reject("Failed to start server job: " .. tostring(response))
			return
		end

		local data
		success, data = pcall(function()
			return HttpService:JSONDecode(response)
		end)
		if not success or not data then
			reject("Invalid JSON response from local Node server.")
			return
		end

		if data.error then
			reject(data.error)
			return
		end

		local jobId = data.jobId
		if not jobId then
			reject("No jobId returned from server.")
			return
		end

		-- 2) Poll for progress every second until 'finished == true'
		local finished = false
		local resultsCount = 0
		local chunkSize = 50
		local finalMessage
		local totalAssets
		local moderatedCount = 0
		local failProgressAmt = 0
		
		while not finished do
			local getProgressSuccess, progressResult = pcall(function()
				return HttpService:GetAsync("http://localhost:3000/progress?jobId=" .. jobId)
			end)

			if getProgressSuccess then
				local progressData
				local decodeSuccess
				decodeSuccess, progressData = pcall(function()
					return HttpService:JSONDecode(progressResult)
				end)

				if decodeSuccess and progressData then
					if progressData.message then
						ProgressString:set(progressData.message)
					end
					totalAssets = progressData.total

					if progressData.finished then
						finished = true
						finalMessage = progressData.message
						resultsCount = progressData.resultsCount or 0
						moderatedCount = progressData.moderatedCount or 0
						chunkSize = progressData.chunkSize or 50
					end
				end
			else
				warn("Failed to fetch progress:", progressResult)
				failProgressAmt += 1
				if failProgressAmt == 5 then
					reject("Failed to fetch progress. Some error occured")
				end
			end

			if not finished then
				task.wait(1) -- Wait a bit before polling again
			end
		end

		-- 3) Check finalMessage for "Error:"
		if finalMessage and finalMessage:sub(1,6) == "Error:" then
			-- The Node script signaled an error
			reject(finalMessage)
			return
		end

		-- 4) Now we fetch two lists: 
		--    A) Approved results from /chunks
		--    B) Moderated results from /moderated

		local finalResults = {}
		if resultsCount > 0 then
			local offset = 0
			while offset < resultsCount do
				local count = chunkSize
				local chunkUrl = ("http://localhost:3000/chunks?jobId=%s&offset=%d&count=%d")
					:format(jobId, offset, count)

				local chunkSuccess, chunkResponseStr = pcall(function()
					return HttpService:GetAsync(chunkUrl)
				end)
				if not chunkSuccess then
					reject("Failed to fetch chunk at offset " .. offset .. ": " .. tostring(chunkResponseStr))
					return
				end

				local chunkData
				local decodeSuccess, chunkDecoded = pcall(function()
					return HttpService:JSONDecode(chunkResponseStr)
				end)
				if not decodeSuccess or not chunkDecoded then
					reject("Failed to decode chunk data at offset " .. offset)
					return
				end
				chunkData = chunkDecoded

				if chunkData.error then
					reject("Chunk endpoint error: " .. tostring(chunkData.error))
					return
				end

				for _, item in chunkData.data do
					table.insert(finalResults, item)
				end

				if not chunkData.hasMore then
					break
				end

				offset += count 
			end
		end

		-- Also fetch 'moderated' assets
		local finalModerated = {}
		if moderatedCount > 0 then
			local offset = 0
			while offset < moderatedCount do
				local count = chunkSize
				local modUrl = ("http://localhost:3000/moderated?jobId=%s&offset=%d&count=%d")
					:format(jobId, offset, count)

				local modSuccess, modResponseStr = pcall(function()
					return HttpService:GetAsync(modUrl)
				end)
				if not modSuccess then
					reject("Failed to fetch moderated chunk offset " .. offset .. ": " .. tostring(modResponseStr))
					return
				end

				local modData
				local decodeSuccess, modDecoded = pcall(function()
					return HttpService:JSONDecode(modResponseStr)
				end)
				if not decodeSuccess or not modDecoded then
					reject("Failed to decode moderated data offset " .. offset)
					return
				end
				modData = modDecoded

				if modData.error then
					reject("Moderated endpoint error: " .. tostring(modData.error))
					return
				end

				for _, item in modData.data do
					table.insert(finalModerated, item)
				end

				if not modData.hasMore then
					break
				end

				offset += count
			end
		end

		print("All chunks retrieved. Approved results: " .. #finalResults 
			.. ", moderated: " .. #finalModerated)

		-- 5) Resolve with both lists
		resolve({
			approved = finalResults,
			moderated = finalModerated
		})
	end)

	ServerPromise:andThen(function(resultTables)
		print("RunServer completed successfully!")
		task.wait(0.5)
		if resultTables then
			-- "resultTables" has { approved = [...], moderated = [...] }

			-- A) Replace IDs in the game with the approved ones
			local approvedMap = {}
			for _, entry in resultTables.approved do
				approvedMap[entry.oldId] = entry.newId
			end

			local replaceCount = 0
			local foundInstances = FoundInstances:get()
			for _,instEntry in foundInstances do 
				local id = instEntry.id
				local instance = instEntry.instance
				local property = instEntry.property

				local newId = approvedMap[id]
				if newId then
					instance:SetAttribute("OldId", id)
					
					if instance:IsA("MeshPart") and UploadAssetType:get() == "Meshes" then
						--[[ Cant write MeshId for meshparts, ugh ]]
						
						local tags = instance:GetTags()
						local attributes = instance:GetAttributes()
						local clone = game:GetService("AssetService"):CreateMeshPartAsync(newId,
							{
								CollisionFidelity = instance.CollisionFidelity,
								RenderFidelity = instance.RenderFidelity
							}
						)
						clone.TextureID = instance.TextureID
						instance:ApplyMesh(clone)
					else
						instance[property] = newId
					end
					
					print(`Replaced {property} of {instance} from {id} to {newId}`)
					replaceCount += 1
				end
			end

			ProgressString:set(`Replaced {replaceCount} asset IDs`)
			
			if #resultTables.moderated > 0 then
				-- B) Let us deal with moderated assets:
				
				local folder = Instance.new("Folder",workspace)
				folder.Name = "ImageReuploader_ModeratedAssets"
				
				for _, modItem in resultTables.moderated do
					local decal = Instance.new("Decal",folder)
					decal.Texture = modItem.oldId
					decal.Name = modItem.oldId
				end
				
				Selection:Set{folder}
			end
		end
	end):catch(function(err)
		if err:match("ConnectFail") then
			ProgressString:set("Couldn't connect")
		else
			ProgressString:set("Encountered an error. See output for details")
		end
		warn("AssetUploader encountered an error:", err)
	end):finally(function()
		task.wait(5)
		ProgressString:set("")
		ServerRunning:set(false)
		FoundInstances:set({})
	end)

	ServerRunning:set(ServerPromise)
end


if GroupOwner:get() then
	if SavedGroupAPIKey then
		API_Key:set(SavedGroupAPIKey)
	end
else
	if SavedPlayerAPIKey then
		API_Key:set(SavedPlayerAPIKey)
	end
end


Fusion.Observer(UploadAssetType):onChange(function()
	SetSetting("UploadAssetType",UploadAssetType:get())
end)
Fusion.Observer(GroupOwner):onChange(function()
	local newAPIKey = ""
	local newID = ""
	
	local isGroupOwner = GroupOwner:get()
	
	FoundInstances:set({})
	RanSearch:set(false)

	if isGroupOwner then
		local groupAPI = GetSetting("GroupAPIKey")
		if groupAPI then
			newAPIKey = groupAPI
		end
	else
		local playerAPI = GetSetting("PlayerAPIKey")
		if playerAPI then
			newAPIKey = playerAPI
		end
	end
	
	API_Key:set(newAPIKey)
	ApiKeyBox.Text = newAPIKey
	SetSetting("GroupOwner",GroupOwner:get())
end)
Fusion.Observer(API_Key):onChange(function()
	local apiKey = API_Key:get()
	if GroupOwner:get() then
		SetSetting("GroupAPIKey",apiKey)
	else
		SetSetting("PlayerAPIKey",apiKey)
	end
end)

local LoadingIcon = nil

local function CreateFusionUi(widget)

	local scrollingFrame = Resources.ScrollingFrame:Clone()
	
	Fusion.Hydrate(scrollingFrame)
	{
		Position = Fusion.Computed(function()
			if SelectingGroup:get() then
				return UDim2.new(0,0,0,20)
			else
				return UDim2.new(0,0,0,0)
			end
		end),
		Size = Fusion.Computed(function()
			if SelectingGroup:get() then
				return UDim2.new(1,0,1,-50)
			else
				return UDim2.new(1,0,1,0)
			end
		end)
	}
	scrollingFrame.Parent = widget 


	bg = VerticalExpandingList 
	{
		Parent = scrollingFrame,
		Position = UDim2.fromScale(0,0),
		Size = UDim2.fromScale(1,1),
		ZIndex = 0,
		Visible = NotSelectingGroup
	}
	bg.UIStroke:Destroy()

	local GroupSelectionBackground = Background 
	{
		Parent = scrollingFrame,
		Position = UDim2.fromScale(0,0),
		Size = UDim2.fromScale(1,1),
		ZIndex = 0,
		BackgroundTransparency = 0,
		Visible = SelectingGroup
	}
	

	local UploadUnderLabel = Label{
		Parent = widget,
		Text = "Upload Under",
		Position = UDim2.new(0,5,0,0),
		TextXAlignment = "Left",
		Visible = SelectingGroup
	}
	
	Resources.UIListLayout:Clone().Parent = GroupSelectionBackground



	for i = 1,#Groups do 
		local groupEntry = Groups[i]
		local template = Resources.GroupEntry:Clone()
		
		template.TextLabel.TextColor3 = if settings().Studio.Theme.Name == "Dark" then Color3.new(1,1,1) else Color3.new(0,0,0)
		template.TextLabel.Text = groupEntry.Name
		template.Icon.Image = groupEntry.EmblemUrl
		
		template.MouseEnter:Connect(function()
			template.TextLabel.TextTransparency = 0
			template.Icon.ImageTransparency = 0
		end)
		template.MouseLeave:Connect(function()
			template.TextLabel.TextTransparency = 0.5
			template.Icon.ImageTransparency = 0.5
		end)
		template.MouseButton1Click:Connect(function()
			SelectedGroup:set(groupEntry)
			SelectingGroup:set(nil)
		end)
		template.Parent = GroupSelectionBackground
	end
	

	local UIList = Resources.UIListLayout:Clone()
	UIList.Parent = bg
	local Padding = Resources.UIPadding:Clone()
	Padding.Parent = bg

	local UploadSettings = VerticalCollapsibleSection{
		Parent = bg,
		Text = "Upload Settings",
	}
	local UploadSettingsList = VerticalExpandingList{
		Parent = UploadSettings,
		Padding = UDim.new(0,7),
		BackgroundTransparency = 1,
		[Fusion.Children] = {
			Fusion.New "UIPadding"
			{
				PaddingLeft = UDim.new(0,10),
				PaddingTop = UDim.new(0,2)
			}
		}
	}
	
	local OwnerBox = Checkbox{
		Parent = UploadSettingsList,
		Value = GroupOwner,
		Text = "Upload To Group",
		Enabled = NotRunning,
		Visible = CanUploadToGroup
	}
	
	local GroupDisplay = Resources.GroupDisplay:Clone()
	GroupDisplay.Parent = UploadSettingsList
	Fusion.Hydrate(GroupDisplay)
	{
		Visible = Fusion.Computed(function()
			return GroupOwner:get()
		end) 
	}
	local GroupDisplayLabel = GroupDisplay.TextLabel
	local GroupDisplayIcon = GroupDisplay.Icon
	Fusion.Hydrate(GroupDisplayLabel){
		Text = Fusion.Computed(function()
			local selectedGroup = SelectedGroup:get()
			
			--changechange
			if selectedGroup then
				return selectedGroup.Name
			else
				return ""
			end
		end),
		TextTransparency = Fusion.Computed(function()
			if NotRunning:get() then
				return 0
			else
				return 0.5
			end
		end)
	}
	Fusion.Hydrate(GroupDisplayIcon){
		Image = Fusion.Computed(function()
			local selectedGroup = SelectedGroup:get()

			--changechange
			if selectedGroup then
				return selectedGroup.EmblemUrl
			else
				return ""
			end
		end),
		ImageTransparency = Fusion.Computed(function()
			if NotRunning:get() then
				return 0
			else
				return 0.5
			end
		end)
	}
	
	local SelectGroup = Button{
		Parent = UploadSettingsList,
		Text = "Select Group",
		Size = UDim2.fromOffset(75,20),
		Activated = function()
			SelectingGroup:set(true)
		end,
		Visible = Fusion.Computed(function()
			return NotRunning:get() and GroupOwner:get()
		end)
	}



	local ApiKeyLabel = Label{
		Parent = UploadSettingsList,
		Text = Fusion.Computed(function()
			if GroupOwner:get() and SelectedGroup:get() then
				return "API Key for "..SelectedGroup:get().Name
			else
				return "API Key for "..Username
			end
		end),
		Size = UDim2.fromOffset(200,20),
		TextXAlignment = "Left",
		Enabled = NotRunning,
		Visible = Fusion.Computed(function()
			return UploadAssetType:get() == "Images"
		end)
	} 


	ApiKeyBox = TextInput{
		Parent = UploadSettingsList,
		Size = UDim2.fromOffset(200,20),
		PlaceholderText = "OpenCloud API Key",
		Text = API_Key,
		Enabled = NotRunning,
		[Fusion.Children] = {
			Fusion.New "UIPadding"
			{
				PaddingLeft = UDim.new(0,10)
			}
		},
		Visible = Fusion.Computed(function()
			return UploadAssetType:get() == "Images"
		end)
	}
	ApiKeyBox.FocusLost:Connect(function()
		if not ApiKeyBox.Text:match("%S") then
			ApiKeyBox.Text = ""
			API_Key:set("")
		else
			API_Key:set(ApiKeyBox.Text)
		end
	end)
	

	
	local SearchSettings = VerticalCollapsibleSection{
		Parent = bg,
		Text = "Search Settings",
	}
	
	local SearchSettingsList = VerticalExpandingList{
		Parent = SearchSettings,
		Padding = UDim.new(0,7),
		BackgroundTransparency = 1,
		[Fusion.Children] = {
			Fusion.New "UIPadding"
			{
				PaddingLeft = UDim.new(0,10),
				PaddingTop = UDim.new(0,2)
			}
		}
	}
	
	
	local UnderSelectionBox = Checkbox{
		Parent = SearchSettingsList,
		Text = "Under Selection",
		Value = OnlyUnderSelection,
		Enabled = NotRunning
	}
	local SelectAssets = Checkbox{
		Parent = SearchSettingsList,
		Text = "Select Assets",
		Value = SelectAssetsAfterSearch,
		Enabled = NotRunning
	}
	

	local AssetType = Dropdown{
		Parent = UploadSettingsList,
		Value = UploadAssetType,
		Size = UDim2.fromOffset(100,25),
		Options = {"Images","Meshes","Animations"},		
		Enabled = NotRunning,
	}


	local SearchContent = VerticalCollapsibleSection{
		Parent = bg,
		Text = "Search Content",
		Visible = Fusion.Computed(function()
			return UploadAssetType:get() == "Images" or UploadAssetType:get() == "Meshes"
		end)
	}
	local SearchContentList = VerticalExpandingList{
		Parent = SearchContent,
		Padding = UDim.new(0,7),
		BackgroundTransparency = 1,
		[Fusion.Children] = {
			Fusion.New "UIPadding"
			{
				PaddingLeft = UDim.new(0,10),
				PaddingTop = UDim.new(0,2)
			}
		}
	}
	
	
	for i,name in ReplacingOrderImages do 
		local fusionVal = ReplacingImages[name]
		local checkBox = Checkbox{
			Parent = SearchContentList,
			Text = name,
			Value = fusionVal,
			Enabled = NotRunning,
			Visible = Fusion.Computed(function()
				return UploadAssetType:get() == "Images"
			end)
		}
	end
	for i,name in ReplacingOrderMeshes do 
		local fusionVal = ReplacingMeshes[name]
		local checkBox = Checkbox{
			Parent = SearchContentList,
			Text = name,
			Value = fusionVal,
			Enabled = NotRunning,
			Visible = Fusion.Computed(function()
				return UploadAssetType:get() == "Meshes"
			end)
		}
	end
	

	local SearchButton = Button{
		Parent = bg,
		Text = "Search",
		Size = UDim2.fromOffset(75,20),
		Activated = function()
			RunSearch()
		end,
		Visible = NotRunning,
		Enabled = Fusion.Computed(function()
			return ValidIDAndAPIKey:get() and CanSearch:get()
		end)
	}
	
	local SearchInfo = Label{
		Parent = bg,
		Text = Fusion.Computed(function()
			local list = FoundInstances:get()
			if not RanSearch:get() then
				return ""
			end
			return string.format("%.0f instance(s) found",#list)
		end),
		Size = UDim2.fromOffset(200,10),
		TextXAlignment = "Left",
		Visible = Fusion.Computed(function()
			if not NotRunning:get() then
				return false
			end
			if not RanSearch:get() then
				return false
			end
			return true
		end)
	} 
	local SearchInfoSkipped = Label{
		Parent = bg,
		Text = Fusion.Computed(function()
			local numSkipped = NumSkippedInstances:get()
			if numSkipped == 0 then
				return ""
			end
			local creatorType = if GroupOwner:get() then "Group" else "User"
			return `{numSkipped} instances were skipped(Already owned by this {creatorType})`
		end),
		Size = UDim2.fromOffset(200,10),
		TextColor3 = Color3.new(0.890196, 0.745098, 0.458824),
		TextXAlignment = "Left",
		Visible = Fusion.Computed(function()
			if not NotRunning:get() then
				return false
			end
			if not RanSearch:get() then
				return false
			end
			if NumSkippedInstances:get() == 0 then
				return false
			end
			return true
		end)
	} 
	local RunButton = Button{
		Parent = bg,
		Text = "Run",
		Size = UDim2.fromOffset(75,20),
		Activated = function()
			local foundInstances = FoundInstances:get()
			if #foundInstances > 0 then
				
				local assetIDs = {}
				for i,entry in foundInstances do 
					local id = entry.id
					
					if not table.find(assetIDs,id) then
						table.insert(assetIDs,id)
					end
				end
				RunServer{
					assetIDs = assetIDs,
					CreatorID = tonumber(ID:get()),
					APIKey = API_Key:get()
				}
			end
		end,
		Enabled = Fusion.Computed(function()
			if #FoundInstances:get() == 0 then
				return false
			end
			if not ValidIDAndAPIKey:get() then
				return
			end
			return true
		end),
		Visible = Fusion.Computed(function()
			if not NotRunning:get() then
				return false
			end
			if not RanSearch:get() then
				return
			end
			return true
		end)
	}
	
	local Loading = Resources.Loading:Clone()
	Loading.Parent = bg 
	Fusion.Hydrate(Loading)
	{
		Visible = Fusion.Computed(function() return not NotRunning:get() end)
	}
	
	LoadingIcon = Loading.ImageLabel
	
	Fusion.Hydrate(Loading.Progress)
	{
		Text = ProgressString
	}
end





local ToolMaid = Maid.new()

local widget


local function ToolEnabled(enabled)
	if not enabled then
		ToolMaid:Cleanup()
		return	
	else
		
		local LoadingFrame = 1
		local LastFrame = os.clock()
		ToolMaid:Add(RunService.Heartbeat:Connect(function()
			
			if LoadingIcon then
		
				if os.clock() - LastFrame >= 0.15 then
					
					LoadingFrame = (LoadingFrame % 6) + 1
					
					LoadingIcon.ImageRectOffset = LoadingSprites[LoadingFrame].ImageRectOffset
										
					LastFrame = os.clock()
				
				end
			end
		end))
	end
end

local function CreateWidget()
	if (widget) then
		widget.Enabled = not widget.Enabled
		return
	end

	-- Create new "DockWidgetPluginGuiInfo" object
	local widgetInfo = DockWidgetPluginGuiInfo.new(
		Enum.InitialDockState.Float,  -- Widget will be initialized in floating panel
		true,   -- Widget will be initially enabled
		true,  -- Don't override the previous enabled state
		351,    -- Default width of the floating window
		600,    -- Default height of the floating window
		351,    -- Minimum width of the floating window
		600     -- Minimum height of the floating window,
	)

	-- Create new widget GUI
	widget = plugin:CreateDockWidgetPluginGui("Asset Reuploader", widgetInfo)
	widget.Title = "Asset Reuploader"  -- Optional widget title
	widget.Name = "Asset Reuploader"  -- Optional widget title
	widget:GetPropertyChangedSignal("Enabled"):Connect(function()
		ToolEnabled(widget.Enabled)
	end)
	CreateFusionUi(widget)	
	ToolEnabled(true)
end

local function clicked()
	CreateWidget()
end

button.Click:Connect(clicked)

plugin.Unloading:Connect(function()
	ToolMaid:Cleanup()
end)

