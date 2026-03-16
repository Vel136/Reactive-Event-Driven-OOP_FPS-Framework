
local ProceduralAnimationConfig = {}

ProceduralAnimationConfig.Recoil = {
	Default = {
		Camera = {
			SpringDamping = 0.5,
			SpringSpeed = 25,
			Pitch = {10, 20},
			Yaw = {-5, 5},
			Roll = {-3, 3}
		},
		Weapon = {
			KickIntensity = 0.1,
			RecoverySpeed = 14,
			KickSnapSpeed = 25.0,
			Rotation = {
				X = {Min = math.rad(0.3), Max = math.rad(4)},
				Y = {Min = math.rad(-0.05), Max = math.rad(0.15)},
				Z = {Min = math.rad(-0.1), Max = math.rad(0.2)},
			},
			Position = {
				X = {Min = -0.05, Max = 0.05},
				Y = {Min = -0.03, Max = 0.03},
				Z = {Min = 0.1, Max = 0.2},
			},
			MaxRotation = {
				X = math.rad(6),
				Y = math.rad(8),
				Z = math.rad(7),
			},
			MaxPosition = {
				X = 0.5,
				Y = 0.5,
				Z = 1.0,
			},
		}
	},

	Aiming = {
		Camera = {
			SpringDamping = 0.65,
			SpringSpeed = 30,
			Pitch = {4, 9},
			Yaw = {-2, 2},
			Roll = {-1, 1}
		},
		Weapon = {
			KickIntensity = 0.04,
			RecoverySpeed = 18,
			KickSnapSpeed = 28.0,
			Rotation = {
				X = {Min = math.rad(0.15), Max = math.rad(1.8)},
				Y = {Min = math.rad(-0.03), Max = math.rad(0.08)},
				Z = {Min = math.rad(-0.05), Max = math.rad(0.1)},
			},
			Position = {
				X = {Min = -0.02, Max = 0.02},
				Y = {Min = -0.015, Max = 0.015},
				Z = {Min = 0.05, Max = 0.1},
			},
			MaxRotation = {
				X = math.rad(3),
				Y = math.rad(4),
				Z = math.rad(3.5),
			},
			MaxPosition = {
				X = 0.25,
				Y = 0.25,
				Z = 0.5,
			},
		}
	},

	-- Heavy weapon preset (higher recoil)
	Heavy = {
		Camera = {
			SpringDamping = 0.4,
			SpringSpeed = 20,
			Pitch = {15, 30},
			Yaw = {-8, 8},
			Roll = {-5, 5}
		},
		Weapon = {
			KickIntensity = 0.15,
			RecoverySpeed = 12,
			KickSnapSpeed = 30.0,
			Rotation = {
				X = {Min = math.rad(0.5), Max = math.rad(6)},
				Y = {Min = math.rad(-0.1), Max = math.rad(0.2)},
				Z = {Min = math.rad(-0.2), Max = math.rad(0.3)},
			},
			Position = {
				X = {Min = -0.08, Max = 0.08},
				Y = {Min = -0.05, Max = 0.05},
				Z = {Min = 0.15, Max = 0.3},
			},
			MaxRotation = {
				X = math.rad(8),
				Y = math.rad(10),
				Z = math.rad(9),
			},
			MaxPosition = {
				X = 0.7,
				Y = 0.7,
				Z = 1.5,
			},
		}
	},

	-- Light weapon preset (minimal recoil)
	Light = {
		Camera = {
			SpringDamping = 0.6,
			SpringSpeed = 28,
			Pitch = {5, 12},
			Yaw = {-3, 3},
			Roll = {-2, 2}
		},
		Weapon = {
			KickIntensity = 0.06,
			RecoverySpeed = 16,
			KickSnapSpeed = 22.0,
			Rotation = {
				X = {Min = math.rad(0.2), Max = math.rad(2)},
				Y = {Min = math.rad(-0.03), Max = math.rad(0.08)},
				Z = {Min = math.rad(-0.08), Max = math.rad(0.12)},
			},
			Position = {
				X = {Min = -0.03, Max = 0.03},
				Y = {Min = -0.02, Max = 0.02},
				Z = {Min = 0.05, Max = 0.12},
			},
			MaxRotation = {
				X = math.rad(4),
				Y = math.rad(5),
				Z = math.rad(4.5),
			},
			MaxPosition = {
				X = 0.35,
				Y = 0.35,
				Z = 0.7,
			},
		}
	}
}

ProceduralAnimationConfig.WalkBob = {
	Default = {
		MovementIntensity = 0.025,
		HorizontalFrequency = 8,
		VerticalFrequency = 16,
		DepthFrequency = 8,
		RotationIntensity = 3,
	},

	Sprint = {
		MovementIntensity = 0.07,
		HorizontalFrequency = 8,
		VerticalFrequency = 16,
		DepthFrequency = 16,
		DepthIntensity = 1.4,
		RotationIntensity = 3,
	},

	Aiming = {
		MovementIntensity = 0.005,
		HorizontalFrequency = 8 / 1.5,
		VerticalFrequency = 16 / 1.5,
		DepthFrequency = 8 / 1.5,
		RotationIntensity = 1,
	},

	Crouch = {
		MovementIntensity = 0.015,
		HorizontalFrequency = 6,
		VerticalFrequency = 12,
		DepthFrequency = 6,
		RotationIntensity = 2,
	},

	Tactical = {
		MovementIntensity = 0.01,
		HorizontalFrequency = 5,
		VerticalFrequency = 10,
		DepthFrequency = 5,
		RotationIntensity = 1.5,
	}
}

ProceduralAnimationConfig.Sway = {
	Default = {
		AimTime = 0.35,
		SwaySpeed = 0.3,
		BreathRate = 0.3,
		SwayIntensity = 1.0,
		MaxSwayAngle = 2.5,
	},

	Focused = {
		AimTime = 0.25,
		SwaySpeed = 0.2,
		BreathRate = 0.2,
		SwayIntensity = 0.5,
		MaxSwayAngle = 1.5,
	},

	Relaxed = {
		AimTime = 0.5,
		SwaySpeed = 0.4,
		BreathRate = 0.4,
		SwayIntensity = 1.5,
		MaxSwayAngle = 3.5,
	},

	Heavy = {
		AimTime = 0.45,
		SwaySpeed = 0.35,
		BreathRate = 0.35,
		SwayIntensity = 1.8,
		MaxSwayAngle = 4.0,
	}
}

ProceduralAnimationConfig.CameraShake = {
	-- Standard firing shake
	Fire = {
		Magnitude = 0.15,
		Roughness = 3,
		FadeIn = 0,
		FadeOut = 0.4,
		PositionInfluence = Vector3.new(0.1, 0.1, 0.1),
		RotationInfluence = Vector3.new(1.5, 0.5, 0.2),
	},

	-- Heavy weapon firing
	FireHeavy = {
		Magnitude = 0.25,
		Roughness = 4,
		FadeIn = 0,
		FadeOut = 0.5,
		PositionInfluence = Vector3.new(0.15, 0.15, 0.15),
		RotationInfluence = Vector3.new(2.0, 0.8, 0.4),
	},

	-- Light weapon firing
	FireLight = {
		Magnitude = 0.08,
		Roughness = 2.5,
		FadeIn = 0,
		FadeOut = 0.3,
		PositionInfluence = Vector3.new(0.05, 0.05, 0.05),
		RotationInfluence = Vector3.new(1.0, 0.3, 0.1),
	},

	-- Explosion impact
	Explosion = {
		Magnitude = 0.5,
		Roughness = 5,
		FadeIn = 0,
		FadeOut = 1.0,
		PositionInfluence = Vector3.new(0.3, 0.3, 0.3),
		RotationInfluence = Vector3.new(3.0, 1.5, 1.0),
	},

	-- Landing from height
	Landing = {
		Magnitude = 0.2,
		Roughness = 2,
		FadeIn = 0,
		FadeOut = 0.3,
		PositionInfluence = Vector3.new(0.0, 0.2, 0.0),
		RotationInfluence = Vector3.new(0.5, 0.0, 0.5),
	}
}

ProceduralAnimationConfig.AnimationSpeed = {
	-- Camera transitions
	Camera = {
		AimTransition = 0.2,
		DefaultFOV = 90,
		AimFOV = 55,
		EasingStyle = Enum.EasingStyle.Quad,
	},

	-- Weapon state transitions
	Weapon = {
		EquipTime = 0.5,
		UnequipTime = 0.3,
		SwapTime = 0.6,
		InspectTime = 2.0,
	}
}

return ProceduralAnimationConfig