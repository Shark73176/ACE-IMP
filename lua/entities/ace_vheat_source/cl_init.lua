include("shared.lua")

local ACF_ToolInfoWhileSeated = CreateClientConVar("ACF_ToolInfoWhileSeated", 0, true, false)

function ENT:Initialize()
    self.BaseClass.Initialize(self)
end

function ENT:Draw()
    local lply = LocalPlayer()
    local hideBubble = not ACF_ToolInfoWhileSeated:GetBool() and IsValid(lply) and lply:InVehicle()

    self.BaseClass.DoNormalDraw(self, false, hideBubble)
    Wire_Render(self)
end

function ACEVHeatSourceGUICreate(Table)
    acfmenupanel:CPanelText("Name", Table.name, "DermaDefaultBold")
    acfmenupanel:CPanelText("GunDesc", Table.desc)
    acfmenupanel.CustomDisplay:PerformLayout()
end
