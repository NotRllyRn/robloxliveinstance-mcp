local PropertyCatalog = {}

PropertyCatalog.DEFAULT_PROPERTIES = {
	"Name",
	"ClassName",
	"Parent",
	"Archivable",
}

PropertyCatalog.CLASS_PROPERTIES = {
	BasePart = { "Position", "CFrame", "Size", "Color", "Material", "Anchored", "CanCollide", "Transparency" },
	Model = { "PrimaryPart", "WorldPivot" },
	BaseScript = { "Enabled", "RunContext" },
	ModuleScript = {},
	GuiObject = { "Visible", "Position", "Size", "ZIndex", "BackgroundTransparency" },
	TextLabel = { "Text", "TextColor3", "TextSize" },
	TextButton = { "Text", "TextColor3", "TextSize" },
	ImageLabel = { "Image", "ImageColor3", "ImageTransparency" },
	ImageButton = { "Image", "ImageColor3", "ImageTransparency" },
	Camera = { "CameraType", "CameraSubject", "FieldOfView", "ViewportSize", "CFrame", "Focus" },
	Humanoid = {
		"Health",
		"MaxHealth",
		"WalkSpeed",
		"JumpPower",
		"JumpHeight",
		"MoveDirection",
		"FloorMaterial",
		"SeatPart",
	},
	Player = { "Team", "Neutral", "UserId", "Character" },
	ScreenGui = { "Enabled", "DisplayOrder", "IgnoreGuiInset", "ResetOnSpawn" },
}

function PropertyCatalog.defaultsFor(instance)
	local names = table.clone(PropertyCatalog.DEFAULT_PROPERTIES)
	for className, properties in pairs(PropertyCatalog.CLASS_PROPERTIES) do
		if instance:IsA(className) then
			for _, propertyName in ipairs(properties) do
				table.insert(names, propertyName)
			end
		end
	end
	return names
end

return PropertyCatalog
