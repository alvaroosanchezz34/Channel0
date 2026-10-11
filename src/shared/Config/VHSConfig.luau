--!strict
--[[
	Permanent analog filter. Values are the DEFAULT profile; accessibility profiles scale them.
	The filter is on by default and cannot be fully disabled during gameplay, only reduced.
]]

local VHSConfig = {}

VHSConfig.Profiles = {
	Default = {
		BaseNoiseIntensity = 0.13, -- grain opacity
		ScanlineOpacity = 0.16,
		ScanlinePeriod = 3, -- pixels per line at 1x scale
		ChromaticIntensity = 0.45, -- edge fringe strength 0..1
		VignetteIntensity = 0.42,
		LuminanceFlicker = 0.018,
		StaticFrequency = 14, -- grain re-rolls per second
		DistortionIntensity = 0.35, -- tracking tears / head-switch band
		TrackingBandChance = 0.06, -- per second while idle
		Saturation = -0.22,
		Contrast = 0.12,
		Tint = { 1.0, 0.97, 0.9 },
		Blur = 0,
		Bloom = 0.32,
		AllowCameraJolt = true,
	},
	Reduced = {
		BaseNoiseIntensity = 0.08,
		ScanlineOpacity = 0.11,
		ScanlinePeriod = 3,
		ChromaticIntensity = 0.25,
		VignetteIntensity = 0.32,
		LuminanceFlicker = 0.006,
		StaticFrequency = 8,
		DistortionIntensity = 0.12,
		TrackingBandChance = 0.015,
		Saturation = -0.18,
		Contrast = 0.1,
		Tint = { 1.0, 0.97, 0.9 },
		Blur = 0,
		Bloom = 0.28,
		AllowCameraJolt = false,
	},
	MinimalNoise = {
		BaseNoiseIntensity = 0.035,
		ScanlineOpacity = 0.09,
		ScanlinePeriod = 3,
		ChromaticIntensity = 0.15,
		VignetteIntensity = 0.3,
		LuminanceFlicker = 0,
		StaticFrequency = 6,
		DistortionIntensity = 0.05,
		TrackingBandChance = 0,
		Saturation = -0.15,
		Contrast = 0.08,
		Tint = { 1.0, 0.97, 0.9 },
		Blur = 0,
		Bloom = 0.25,
		AllowCameraJolt = false,
	},
}

-- Ceiling for event pulses so no event can make the game unplayable.
VHSConfig.MaxAnomalyMultiplier = 3.2
-- Maximum per-second change in overall screen brightness from flicker/dropouts (photosensitivity guard).
VHSConfig.MaxDropoutsPerWindow = 2
VHSConfig.DropoutWindowSeconds = 3
VHSConfig.DropoutMaxDarkness = 0.75 -- never full black, never white
VHSConfig.GrainTextureSize = 96
VHSConfig.GrainTileScale = 2.2 -- texture pixels shown per screen pixel ~ 1/scale
-- Optional uploaded grain texture (rbxassetid://...). Empty = generate at runtime.
VHSConfig.GrainTextureId = ""

return VHSConfig
