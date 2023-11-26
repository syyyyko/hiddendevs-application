-- Obtain all necessary services
local replicatedStorage = game:GetService('ReplicatedStorage')
local userInputService = game:GetService('UserInputService')
local proximityService = game:GetService('ProximityPromptService')
local playerService = game:GetService('Players')
local debrisService = game:GetService('Debris')
local tweenService = game:GetService('TweenService')
local httpService = game:GetService('HttpService')
local starterGui = game:GetService('StarterGui')
local runService = game:GetService('RunService')
--variables required with player data
local player = playerService.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild('Humanoid')
local animator = humanoid:WaitForChild('Animator')
local root = character:WaitForChild('HumanoidRootPart')
--Obtains the Ui of the vehicle to be able to modify the speed in a textlabel.
local playerGui = player.PlayerGui
local vehicleGui = playerGui.vehicleGui
local touchGui = playerGui:FindFirstChild('TouchGui')
-- tables
local cylindricals = {}
local proximityAnims = {}
-- objects
local gasCanAnim
local usingSeat
--booleans
local angularDebounce = false
local endedAnimGasCan = false
--remotes
local addeyEvent = replicatedStorage.src.addeyEvent
local remoteEvent = replicatedStorage.src.carEvent
local vfxFolder = replicatedStorage.src.vfx
local clientEvent = replicatedStorage.src.client
--connetions to optimize lag and avoid a live cycle remaining
local seatConnection
local inputConnection
local heartConnection
local angularConnection
--function to invert a number
function reverseSign(number)
	return -number
end
--create an invisible part where a particleEmitter will be placed, to avoid that if the car is deleted while it has a vfx it will be deleted.
function createPartVFX(children, pos)
	if children.ClassName ~= 'ParticleEmitter' then return end
	local newPart = Instance.new('Part', workspace)
	newPart.Name = 'V_vfx'
	newPart.Anchored = true
	newPart.CanCollide = false
	newPart.CanTouch = false
	newPart.CanQuery = false
	newPart.Size = Vector3.new(.5,.5,.5)
	newPart.Transparency = 1
	newPart.Position = pos
	children.Parent = newPart
	debrisService:AddItem(newPart, (children.Lifetime.Max*2))
end
--detects when the player sits down, since this script handles all the driving, instead of putting a localscript from each car, a handler from starterplayercharacter is used.
humanoid.Seated:Connect(function(bool, seatPart)
	--disable proximityprompt since he will be sitting in a car and will not be able to interact
    proximityService.Enabled = not bool

	if not seatPart then
        --This if detects when the player gets off, disconnects all functions, returns the ui to its original parent, activates the backpack ui, destroys the false ui, sets the car speed to 0 to prevent the car from slowing down, iterates over a connection table to see if it has an active one and deactivates it if it does, puts the root out of the car and finally activates the jump.
		if seatConnection then seatConnection:Disconnect() end
		if inputConnection then inputConnection:Disconnect() end
		if heartConnection then heartConnection:Disconnect() end
		if touchGui then
			touchGui.Parent = playerGui
		end
		starterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, true)
		if playerGui:FindFirstChild('usingGUI') then
			playerGui.usingGUI:Destroy()
		end
		if not usingSeat then return end
		if not usingSeat:IsDescendantOf(workspace) then
			return
		end
		for i, cylindrical in pairs(cylindricals) do
			cylindrical.MotorMaxTorque = 2500
		end
		if angularConnection ~= nil then
			if typeof(angularConnection) == 'RBXScriptConnection' then
				angularConnection:Disconnect()
			end
		end
		root.CFrame = usingSeat.side.WorldCFrame
		usingSeat:FindFirstAncestorWhichIsA('Model').plataform.radio.effect.Enabled = true
		usingSeat = nil
		task.wait(0.3)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
		return
	end
	if seatPart then
		if seatPart.Parent.Name == 'seats' and seatPart.Parent:IsA('Folder') and seatPart.Parent:FindFirstChildWhichIsA('VehicleSeat') then

			if seatPart:FindFirstAncestorWhichIsA('Model') then
                --Detects if it is a system carriage using a find to find a folder with a required name
				if seatPart:FindFirstAncestorWhichIsA('Model'):FindFirstChild('rig') then

					usingSeat = seatPart
					local plataform = seatPart:FindFirstAncestorWhichIsA('Model').plataform
					plataform.radio.effect.Enabled = false
				end
			end
        --detects if it is an ascent of a system vehicle
        if not seatPart:IsA('VehicleSeat') then
            --creates a connection to detect when the player presses space, since the jump is disabled, i.e. he can't exit the ascent, so I take him out manually
			inputConnection = userInputService.InputBegan:Connect(function(key, gp)
					if gp then return end
					if key.KeyCode == Enum.KeyCode.Space then
						humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
						humanoid.Sit = false
					end
				end)
				return
			end
            --disable backpack
			starterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
			if vehicleGui:FindFirstChild('usingGUI') then vehicleGui.usingGUI:Destroy() end
            --states some important variables
			local chassis = seatPart.Parent.Parent
			local wheels = chassis.wheels
			local plataform = chassis.plataform
			local steer = chassis.steer
			local fuelValue = chassis.Configuration.fuel		
			local ui
			local isDevice = ''
            --check if the player is on mobile or computer to know which ui to clone
			if userInputService.TouchEnabled then
				ui = vehicleGui:Clone()
				playerGui.TouchGui.Parent = player
				ui.mobile.Visible = true
				isDevice = 'mobile'
			else
				ui = vehicleGui:Clone()
				ui.pc.chassis.carName.Text = chassis.Name
				ui.pc.Visible = true
				isDevice = 'pc'
			end
			ui.Name = 'usingGUI'
			ui.Parent = playerGui
			ui.Enabled = true
			ui.LocalScript.Enabled = true
			ui = ui[isDevice]
            --the folder where all the car physics are concentrated is obtained.
			local rig = {suspension = chassis.rig.suspension}
			cylindricals = {RR = rig.suspension.RR.CylindricalConstraint,RL = rig.suspension.RL.CylindricalConstraint}
            --get the default values with which the vehicle is mounted, which is a string value made with json
			local VTable = httpService:JSONDecode(chassis.VTable.Value)
            --check what type of traction it is to know which tires to make them roll
			if VTable.traction == 'awd' then
				cylindricals.FL = rig.suspension.FL.CylindricalConstraint
				cylindricals.FR = rig.suspension.FR.CylindricalConstraint
			elseif VTable.traction == 'fwd' then
				cylindricals = {FL = rig.suspension.FL.CylindricalConstraint,FR = rig.suspension.FR.CylindricalConstraint}
			end
            
			local attachments = {FR = plataform.FR,FL = plataform.FL}
            --these parameters are declared as they are used in a loop that creates raycast to know what material is being drifted.
			local rayParams = RaycastParams.new()
			rayParams.FilterDescendantsInstances = {chassis, character}
			rayParams.IgnoreWater = false
			rayParams.FilterType = Enum.RaycastFilterType.Exclude
            --simple calculations
			local seatTorque = seatPart.Torque
			local maxAngularAcceleration = seatPart.MaxSpeed / (wheels.RR.physicalWheel.Size.Y / 2)
			local exAngular = 0
            --it puts the table of cylindricals that was declared when the if was put of which traction it is, and it puts them in motor
			for i,cylindrical in pairs(cylindricals) do
				cylindrical.AngularActuatorType = Enum.ActuatorType.Motor
			end

			seatConnection = seatPart.Changed:Connect(function(property)

				if property == 'SteerFloat' then
                    --Creates the effect of bending the rims sideways with a tweenservice
					local orientation = Vector3.new(0, -seatPart.SteerFloat * seatPart.TurnSpeed, 90)
					for i, attachment in pairs(attachments) do
						tweenService:Create(attachment, TweenInfo.new(0.3), {Orientation = orientation}):Play()
					end
					chassis.steer.HingeConstraint.TargetAngle = (-seatPart.SteerFloat * seatPart.TurnSpeed)
				elseif property == 'ThrottleFloat' then
                    --checks whether you are moving forward or backward to turn on or turn off the red tail lights.
					if seatPart.ThrottleFloat == -1 then
						remoteEvent:FireServer('lights', 'brakes', true)
					else
						remoteEvent:FireServer('lights', 'brakes', false)
					end
                    --obtains parameters from the vehicleseat, performs multiplications to obtain the desired speed
					local torque = math.abs(seatPart.ThrottleFloat * seatTorque)
					local angularVelocity = math.sign(seatPart.ThrottleFloat) * maxAngularAcceleration
					if torque == 0 then
						torque = 2500
					end
					for i, cylindrical in pairs(cylindricals) do
                        --iterate on the cylindricals with motor and adjust what was calculated.
						cylindrical.MotorMaxTorque = torque
						cylindrical.AngularVelocity = angularVelocity
					end
				end
			end)
            --Keys for more things on the chassis
			inputConnection = userInputService.InputBegan:Connect(function(key, gp)
				if gp then return end
				if key.KeyCode == Enum.KeyCode.L then
                    --the headlights turn on with a remotevent
					remoteEvent:FireServer('lights', 'highlight')
				elseif key.KeyCode == Enum.KeyCode.H then
                    --the position of the initial horn is obtained, it is turned on, once the player stops pressing it stops beeping and the original sound position is passed by argument.
					local pos = plataform.horn.TimePosition
					remoteEvent:FireServer('horn', true)
					repeat task.wait() until not userInputService:IsKeyDown(Enum.KeyCode.H)
					remoteEvent:FireServer('horn', false, pos)
				elseif key.KeyCode == Enum.KeyCode.Space then
                    --In case the first space detection fails here's another one
					humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
					humanoid.Sit = false
				elseif key.KeyCode == Enum.KeyCode.F then
                    --police sirens
					chassis.body.lightbar.turn:FireServer()
				elseif key.KeyCode == Enum.KeyCode.P then
                    --Drift system with handbrake
					ui.chassis.handBrake.Visible = true
                    --First iterate on the cylindricals with motor to stop them.
					for i, cylindrical in pairs(cylindricals) do
						cylindrical.AngularLimitsEnabled = true
					end
                    --then iterate and call the previously declared function that creates a detection of the material where the wheel is located to create a separate part of the vehicle that has the default vfx for the material (only 1 is created first to avoid input lag since a hearbeart must be created).
					for i,cylindrical in pairs(cylindricals) do
						local physical = wheels[i].physicalWheel
						if physical:FindFirstChildWhichIsA('ParticleEmitter') then
							createPartVFX(physical:FindFirstChildWhichIsA('ParticleEmitter'), physical.Position)
						end
					end
					local connect

					connect = runService.Heartbeat:Connect(function()
                        --finally a detection cycle is created while the car is still at a higher speed than the one set to activate the drift vfx.
						local velocity = seatPart.AssemblyLinearVelocity.Magnitude
						if velocity >= VTable.driftVfxMinSpeed then
							for i,cylindrical in pairs(cylindricals) do
                                --creates raycast to detect what material is under the wheel
								local rayDirection = -plataform.CFrame.UpVector * 150
								local rayOrigin = plataform[i].WorldPosition
								local raycast = workspace:Raycast(rayOrigin, rayDirection, rayParams)
								local physical = wheels[i].physicalWheel
								if raycast then
                                    --gets the name of the material
									local materialName = raycast.Material.Name
                                    --look for the name of the material in a folder with all the vfx according to its name, if it does not find it use a default one.
									if not vfxFolder:FindFirstChild(materialName) then
										materialName = 'Normal'
									end
                                    --check if you already have a vfx to avoid creating a lot of them
									if physical:FindFirstChildWhichIsA('ParticleEmitter') then
										if physical:FindFirstChildWhichIsA('ParticleEmitter').Name ~= materialName then
                                            --check if it is not the same one, if it is not the same one create it
											createPartVFX(physical:FindFirstChildWhichIsA('ParticleEmitter'), physical.Position)
										end
									end
									if physical:FindFirstChildWhichIsA('ParticleEmitter') and physical:FindFirstChildWhichIsA('ParticleEmitter').Name == materialName then
										continue 
									end
									local newEmitter = vfxFolder[materialName]:Clone()
									newEmitter.Parent = physical
									newEmitter.Enabled = true
								end
							end
						else
                            --Sometimes it gave a speed error, so I solved it with an else
							for i,cylindrical in pairs(cylindricals) do
								local physical = wheels[i].physicalWheel
								if physical:FindFirstChildWhichIsA('ParticleEmitter') then
									createPartVFX(physical:FindFirstChildWhichIsA('ParticleEmitter'), physical.Position)
								end
							end
						end
					end)
                    --detects when you stop pressing to erase the connection and avoid infinite cycling
					repeat task.wait() until not userInputService:IsKeyDown(Enum.KeyCode.P)
					if connect then connect:Disconnect() end -- disconnect it
					for i,cylindrical in pairs(cylindricals) do
						local physical = wheels[i].physicalWheel
						if physical:FindFirstChildWhichIsA('ParticleEmitter') then
							createPartVFX(physical:FindFirstChildWhichIsA('ParticleEmitter'), physical.Position)
						end
					end
					if not usingSeat then return end -- the player may have exited the car while pressing p, so a conditional is used to see if a car follows in the variable
					ui.chassis.handBrake.Visible = false
                    --finally makes the wheels able to turn again
					for i, cylindrical in pairs(cylindricals) do
						cylindrical.AngularLimitsEnabled = false
					end

				end
			end)
            --This loop changes the text of a textlabel at the speed of the carriage using simple calculations 
			heartConnection = runService.Heartbeat:Connect(function()
				ui.chassis.velocity.Text = math.floor(seatPart.AssemblyLinearVelocity.Magnitude)
                --it also verifies in real time how much gasoline is left in the car from a value of this and changes the size since it is represented with a frame from top to botto
				local calcule = fuelValue.Value/100
				local newSize = UDim2.fromScale(1,calcule)
				ui.chassis.buttons.Frame.icon.Frame.Size = newSize
			end)
		end
	end
end)
