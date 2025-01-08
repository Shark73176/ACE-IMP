AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")

include("shared.lua")

local deg, acos = math.deg, math.acos
local min, Clamp = math.min, math.Clamp
local insert = table.insert
local Rand = math.Rand
local TraceHull = util.TraceHull
local RadarTable = ACF.Weapons.Radars

function ENT:Initialize()

	self.ThinkDelay			= 0.1
	self.StatusUpdateDelay	= 0.5
	self.LastStatusUpdate	= CurTime()
	self.Active				= false

	self.Inputs	= WireLib.CreateInputs( self, {
		"Active (Activates the IRST)",
		"Cone (Sets the view cone angle of the IRST)"
	})

	self.Outputs = WireLib.CreateOutputs( self, {
		"Detected (Returns 1 if the IRST is detecting at least one target)",
		"Angle (Returns an array of angles towards the detected targets) [ARRAY]",
		"EffHeat (Returns an array of the temperature of the detected targets) [ARRAY]",
		"ID (Returns an array of unique IDs for each target that can be used to track a specific contraption) [ARRAY]"
	})

	self.OutputData = {
		Detected		= 0,
		Angle			= {},
		EffHeat			= {},
		ID				= {}
	}

	self:SetActive(false)

	self.Heat               = ACE.AmbientTemp
	self.HeatAboveAmbient   = 10 -- Targets below this temperature above ambient will be ignored

	self.MinViewCone        = 2
	self.MaxViewCone        = 60

	self.NextLegalCheck     = ACF.CurTime + math.random(ACF.Legal.Min, ACF.Legal.Max) -- give any spawning issues time to iron themselves out
	self.Legal              = true
	self.LegalIssues        = ""

	self.TargetDetected		= false

	self.MaxInaccuracy = 40 --The minimum detection accuracy of targets
	self.MaxAccuracyOutsideSweetspot = 10
	self.MinInaccuracy = 2

	--Deg/s of inaccuracy reduced per second as the IRST dials in.
	self.ResolveSpeedBase = 2
	--Targets near the center are resolved fastest and at the highest resolution
	self.SweetspotResolveSpeedMul = 2
	--Hotter targets resolve faster. Every 100C, multiple by this value.
	self.HeatResolveMul = 3
	self.HeatRegionMul = 1 --Every 100C adds another multiple of the regionsize

	--The outer detection area of the IRST
	self.RoughDetectionArea = 10

	--The Inner and more accurate detection area of the IRST
	self.BaseSweetSpotSize = 4

	self.IRResolution = {}
	self:UpdateOverlayText()

end

function MakeACE_IRST(Owner, Pos, Angle, Id)

	if not Owner:CheckLimit("_acf_missileradar") then return false end

	Id = Id or "Small-IRST"

	local radar = RadarTable[Id]
	if not radar then return false end

	local IRST = ents.Create("ace_irst")

	if IsValid(IRST) then

		IRST:SetAngles(Angle)
		IRST:SetPos(Pos)

		IRST.Model				= radar.model
		IRST.Weight				= radar.weight
		IRST.ACFName			= radar.name
		IRST.ICone				= radar.viewcone	--Note: intentional. --Recorded initial cone
		IRST.Cone				= IRST.ICone
		IRST.ACEPoints			= radar.acepoints or 0.9

		IRST.Id					= Id
		IRST.Class				= radar.class

		IRST:Spawn()

		IRST:CPPISetOwner(Owner)

		IRST:SetNWNetwork()
		IRST:SetModelEasy(radar.model)
		IRST:UpdateOverlayText()

		Owner:AddCount( "_acf_missileradar", IRST )
		Owner:AddCleanup( "acfmenu", IRST )

		return IRST
	end

	return false
end
list.Set( "ACFCvars", "ace_irst", {"id"} )
duplicator.RegisterEntityClass("ace_irst", MakeACE_IRST, "Pos", "Angle", "Id" )

function ENT:SetNWNetwork()
	self:SetNWString( "WireName", self.ACFName )
end

function ENT:SetModelEasy(mdl)

	self:SetModel( mdl )
	self.Model = mdl

	self:PhysicsInit( SOLID_VPHYSICS )
	self:SetMoveType( MOVETYPE_VPHYSICS )
	self:SetSolid( SOLID_VPHYSICS )

	local phys = self:GetPhysicsObject()
	if IsValid(phys) then
		phys:SetMass(self.Weight)
	end

end

function ENT:TriggerInput( inp, value )
	if inp == "Active" then
		self:SetActive((value ~= 0) and self.Legal)
	elseif inp == "Cone" then
		if value > 0 then
			self.Cone = Clamp(value / 2, self.MinViewCone ,self.MaxViewCone )
		else
			self.Cone = self.ICone
		end

		self:UpdateOverlayText()
	end
end

function ENT:SetActive(active)

	self.Active = active

	if active  then
		self.Heat = ACE.AmbientTemp + 40
	else
		WireLib.TriggerOutput( self, "Detected"	, 0 )
		WireLib.TriggerOutput( self, "Angle", {} )
		WireLib.TriggerOutput( self, "EffHeat", {} )
		WireLib.TriggerOutput( self, "ID", {} )

		self.OutputData.Detected = 0
		self.OutputData.Angle = {}
		self.OutputData.EffHeat = {}
		self.OutputData.ID = {}

		self.Heat = ACE.AmbientTemp
	end

end

local function GetAngleBetweenVectors(v1, v2)
	return deg(acos(v1:Dot(v2)))
end

local LOSTraceData = {
	mask = MASK_SOLID_BRUSHONLY,
	mins = vector_origin,
	maxs = vector_origin,
}

function ENT:CleanupIRTracks()
	local RemovalThreshold = self.MaxInaccuracy
	local IDsToRemove = {}

	-- Collect IDs that need removal
	for ID, Resolution in pairs(self.IRResolution) do
		Resolution = Resolution + self.ResolveSpeedBase * self.ThinkDelay * 4
		if Resolution > RemovalThreshold then
			table.insert(IDsToRemove, ID)
		else
			self.IRResolution[ID] = Resolution
		end
	end

	-- Remove outdated elements after collecting IDs
	for _, ID in ipairs(IDsToRemove) do
		self.IRResolution[ID] = nil
	end

end

function ENT:ScanForContraptions()
	self.TargetDetected = false

	local Temperatures  = {}
	local AngTable      = {}
	local IDs			= {}
	local Distances		= {}

	local SelfContraption = self:GetContraption()
	local SelfForward = self:GetForward()
	local SelfPos = self:GetPos()
	local MinTrackingHeat = ACE.AmbientTemp + self.HeatAboveAmbient

	for Contraption in pairs(CFW.Contraptions) do

		if Contraption == SelfContraption then continue end

		local _, HottestEntityTemp = Contraption:GetACEHottestEntity()
		HottestEntityTemp = HottestEntityTemp or 0
		local Base = Contraption:GetACEBaseplate()

		if not IsValid(Base) then continue end

		local BasePhys = Base:GetPhysicsObject()
		local BaseTemp = 0

		if IsValid(BasePhys) and BasePhys:IsMoveable() then
			BaseTemp = ACE_InfraredHeatFromProp(Base, self.HeatAboveAmbient)
		end

		local Pos
		if not Contraption.aceEntities or (HottestEntityTemp and BaseTemp > HottestEntityTemp) then
			Pos = Base:GetPos()
		else
			Pos = Contraption:GetACEHeatPosition()
		end
		local PosDiff = Pos - SelfPos
		local Distance = PosDiff:Length()

		local Heat = BaseTemp + math.max(ACE.AmbientTemp,HottestEntityTemp)

		--0x heat @ 2400m
		--0.25x heat @ 1800m
		--0.5x heat @ 1200m
		--0.75x heat @ 600m
		--1.0x heat @ 0m
		local HeatMulFromDist = 1 - min(Distance / 94488, 1) -- 39.37 * 2400 = 94488
		Heat = Heat * HeatMulFromDist

		LOSTraceData.start = SelfPos
		LOSTraceData.endpos = Pos
		local LOSTrace = TraceHull(LOSTraceData)

		local AngleFromTarget = GetAngleBetweenVectors(PosDiff:GetNormalized(), SelfForward)

		if AngleFromTarget < self.Cone and Heat > MinTrackingHeat and not LOSTrace.Hit then

			local RegionMul = Heat / 100 * self.HeatRegionMul
			local ResolveMul = Heat / 100 * self.HeatResolveMul

			local OuterDetectRegion = self.RoughDetectionArea * RegionMul
			local InnerDetectRegion = self.BaseSweetSpotSize * RegionMul

			local ClampMin = self.MaxAccuracyOutsideSweetspot

			if AngleFromTarget < InnerDetectRegion then
				debugoverlay.Line(SelfPos, Pos, 0.2, Color(255, 0, 0))
				ResolveMul = ResolveMul * self.SweetspotResolveSpeedMul
				ClampMin = self.MinInaccuracy
			elseif AngleFromTarget < OuterDetectRegion then
				debugoverlay.Line(SelfPos, Pos, 0.2, Color(255, 153, 0))
			else --Target too far from sensor to be detected
				continue
			end

			self.TargetDetected = true

			local Index = ACE_GetContraptionIndex(Contraption)

			self.IRResolution[Index] = Clamp((self.IRResolution[Index] or self.MaxInaccuracy) - self.ResolveSpeedBase * self.ThinkDelay * ResolveMul * 2.5,ClampMin,self.MaxInaccuracy)

			--print(self.IRResolution[Index])

			local AngleError = Angle(Rand(-1, 1), Rand(-1, 1)) * self.IRResolution[Index]
			local FinalAngle = -self:WorldToLocalAngles(PosDiff:Angle()) + AngleError

			local debugDir = self:LocalToWorldAngles(-FinalAngle):Forward()

			debugoverlay.Line(SelfPos, SelfPos + debugDir * Distance, 0.2, Color(0, 255, 0))

			FinalAngle.r = 0

			local InsertionIndex = ACE_GetBinaryInsertIndex(Distances, Distance)

			insert(Distances, InsertionIndex, Distance)
			insert(AngTable, InsertionIndex, FinalAngle)
			insert(Temperatures, InsertionIndex, Heat)
			insert(IDs, InsertionIndex, Index)
		end
	end

	for _, Ply in ipairs(player.GetAll()) do

		if not IsValid(Ply) then continue end

		local Pos = Ply:EyePos()

		local PosDiff = Pos - SelfPos
		local Distance = PosDiff:Length()

		local Heat = 38 --A bit hotter than a person but it helps the optics

		LOSTraceData.start = SelfPos
		LOSTraceData.endpos = Pos
		local LOSTrace = TraceHull(LOSTraceData)

		local AngleFromTarget = GetAngleBetweenVectors(PosDiff:GetNormalized(), SelfForward)

		if AngleFromTarget < self.Cone and not LOSTrace.Hit then

			local RegionMul = Heat / 100 * self.HeatRegionMul
			local ResolveMul = Heat / 100 * self.HeatResolveMul

			local OuterDetectRegion = self.RoughDetectionArea * RegionMul
			local InnerDetectRegion = self.BaseSweetSpotSize * RegionMul

			local ClampMin = self.MaxAccuracyOutsideSweetspot

			if AngleFromTarget < InnerDetectRegion then
				debugoverlay.Line(SelfPos, Pos, 0.2, Color(255, 0, 0))
				ResolveMul = ResolveMul * self.SweetspotResolveSpeedMul
				ClampMin = self.MinInaccuracy
			elseif AngleFromTarget < OuterDetectRegion then
				debugoverlay.Line(SelfPos, Pos, 0.2, Color(255, 153, 0))
			else --Target too far from sensor to be detected
				continue
			end

			self.TargetDetected = true
			local Index = Ply:Nick()
			self.IRResolution[Index] = Clamp((self.IRResolution[Index] or self.MaxInaccuracy) - self.ResolveSpeedBase * self.ThinkDelay * ResolveMul * 5,ClampMin,self.MaxInaccuracy)

			--print(self.IRResolution[Index])

			local AngleError = Angle(Rand(-1, 1), Rand(-1, 1)) * self.IRResolution[Index]
			local FinalAngle = -self:WorldToLocalAngles(PosDiff:Angle()) + AngleError

			local debugDir = self:LocalToWorldAngles(-FinalAngle):Forward()

			debugoverlay.Line(SelfPos, SelfPos + debugDir * Distance, 0.2, Color(0, 255, 0))

			FinalAngle.r = 0

			local InsertionIndex = ACE_GetBinaryInsertIndex(Distances, Distance)

			insert(Distances, InsertionIndex, Distance)
			insert(AngTable, InsertionIndex, FinalAngle)
			insert(Temperatures, InsertionIndex, Heat)
			insert(IDs, InsertionIndex, -1)
		end
	end


	self:CleanupIRTracks()

	local OutputData = self.OutputData

	if self.TargetDetected then
		WireLib.TriggerOutput( self, "Detected", 1 )
		WireLib.TriggerOutput( self, "Angle", AngTable )
		WireLib.TriggerOutput( self, "EffHeat", Temperatures )
		WireLib.TriggerOutput( self, "ID", IDs )


		OutputData.Detected = 1
		OutputData.Angle = AngTable
		OutputData.EffHeat = Temperatures
		OutputData.ID = IDs
	else
		WireLib.TriggerOutput( self, "Detected", 0 )
		WireLib.TriggerOutput( self, "Angle", {} )
		WireLib.TriggerOutput( self, "EffHeat", {} )
		WireLib.TriggerOutput( self, "ID", {} )

		OutputData.Detected = 0
		OutputData.Angle = {}
		OutputData.EffHeat = {}
		OutputData.ID = {}
	end
end

function ENT:UpdateStatus()
	self.Status = self.Active and "On" or "Off"
end

function ENT:Think()

	local curTime = CurTime()

	-- Legal check system
	if ACF.CurTime > self.NextLegalCheck then

		self.Legal, self.LegalIssues = ACF_CheckLegal(self, self.Model, math.Round(self.Weight,2), nil, true, true)
		self.NextLegalCheck = ACF.Legal.NextCheck(self.legal)

		if not self.Legal then
			self.Active = false
			self:SetActive(false)
		end

	end

	if self.Active and self.Legal then
		self:ScanForContraptions()
	end

	if (self.LastStatusUpdate + self.StatusUpdateDelay) < curTime then
		self:UpdateStatus()
		self.LastStatusUpdate = curTime
	end

	self:UpdateOverlayText()

	self:NextThink(curTime + self.ThinkDelay)
	return true
end

function ENT:UpdateOverlayText()
	local cone		= self.Cone
	local status	= self.Status or "Off"
	local detected  = status ~= "Off" and self.TargetDetected or false

	local txt = "Status: " .. status

	txt = txt .. "\n\nView Cone: " .. math.Round(cone * 2, 2) .. " deg"

	if detected then
		txt = txt .. "\n\nTarget Detected!"
	end

	if not self.Legal then
		txt = txt .. "\n\nNot legal, disabled for " .. math.ceil(self.NextLegalCheck - ACF.CurTime) .. "s\nIssues: " .. self.LegalIssues
	end

	self:SetOverlayText(txt)
end
