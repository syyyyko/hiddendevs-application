--[[
# Here is a script of over 200 lines
# Enter the game and verify that the system is functioning correctly.

I'm tired of my attempts to apply for hiddendevs being declined.
I tried sending visual scripts that work on their own, meaning they are not
connected to other scripts, but they declined them due to a lack of lines. 
So, now I'll be commenting this script, which is a script handler in ServerScriptService 
that makes the entire vehicle system work.
]]
local marketplaceService = game:GetService('MarketplaceService')
local replicatedStorage = game:GetService('ReplicatedStorage')
local serverStorage = game:GetService('ServerStorage')
local httpService = game:GetService('HttpService')
local playerService = game:GetService('Players')
local runService = game:GetService('RunService')
local debris = game:GetService('Debris')
local gameCarsFolder = workspace:WaitForChild('gameCars')


local tireAdd_module = script:FindFirstChild('tireAdd')
if tireAdd_module then
	tireAdd_module = require(tireAdd_module)
end


-- Easy configurations for the commission buyer
local maxRadioVolume = 0.7
local minRadioVolume = 0.05
local radioGamepassId = 184075492
local spawnCarCooldown = 6 -- seconds














-------------------------------------------

--[[
Memory table used to avoid infinite loops, and at some point,
they disconnect with a for loop.
]]
local network = {}
local occupants = {}
local tires = {}
local fuel = {}
local radio = {}
local flipCar = {}
local engines = {}

local carEvent = replicatedStorage.src.carEvent
local addeyEvent = replicatedStorage.src.addeyEvent
local client = replicatedStorage.src.client

local whitelist = {'HumanoidRootPart', 'UpperTorso', 'LowerTorso'}

local carRotation = Vector3.new(0, -90, 90)
local keyRaydistance = 50
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.IgnoreWater = true

local keyCarToolName = 'carKeys'
local carsStorageFolderName = 'car_storage'


--[[
It's a simple function that checks if a part is upside down
]]
local function isUpsideDown(part)
    local UpVector = part.CFrame.UpVector
	local position = part.Position
	local newY = position.Y + 0.4
	return newY > (position + UpVector).Y
end
--[[
This function is responsible for disconnecting all tables when the player disconnects
or exits a car, to avoid memory losses
]]
local function ripNetwork(id, msg)
    if not network[id] then return end

    if occupants[id] then
        if typeof(occupants[id]) == "RBXScriptConnection" then
            occupants[id]:Disconnect()
        end
    end

    if tires[id] then
        for i,v in pairs(tires[id]) do
            if typeof(v) == "RBXScriptConnection" then
				v:Disconnect()
            end
        end
	end

    if fuel[id] then
        fuel[id]:Disconnect()
    end

    if radio[id] then
        radio[id]:Disconnect()
    end

    if flipCar[id] then
        flipCar[id]:Disconnect()
	end

    if network[id]:IsDescendantOf(workspace) then
		-- [stopping]
		network[id].Parent.Parent.plataform.engine:Stop()
		
		-- [car velocity]
		local rig = network[id].Parent.Parent.rig.suspension
		rig.RR.CylindricalConstraint.AngularActuatorType = Enum.ActuatorType.Motor
		rig.RR.CylindricalConstraint.MotorMaxTorque = 4500
		rig.RL.CylindricalConstraint.AngularActuatorType = Enum.ActuatorType.Motor
		rig.RL.CylindricalConstraint.MotorMaxTorque = 4500

        -- [remove net]
        network[id]:SetNetworkOwner(nil)

        -- [engine sound stop]

        network[id] = nil
        --print(msg)
    end
end

playerService.PlayerAdded:Connect(function(player)
    local localId = player.UserId
	player.CharacterAdded:Connect(function(char)
		--[[
		This is created to prevent tools from bugging when the player dies.
		 It waits until the player is correctly loaded and 
		 clones the tools from a folder
		]]
		repeat task.wait() until char:IsDescendantOf(workspace)
		
		for i,v in pairs(serverStorage.vehicleSystemTools:GetChildren()) do
			if v:IsA('Tool') then
				local new = v:Clone()
				new.Parent = player.Backpack
			end
		end

        local huma = char:WaitForChild('Humanoid')
		local lastSeat
		
		
		-- Sets up various IKControl for the steering system in the car
		local rightIK = Instance.new('IKControl', huma)
		rightIK.Name = 'rIK'

		local leftIK = Instance.new('IKControl', huma)
		leftIK.Name = 'lIK'
		-- Checks if it's r6 or r15
		if char:FindFirstChild('Torso') and not char:FindFirstChild('UpperTorso') then
			-- r6
			rightIK.ChainRoot = char:WaitForChild('Right Arm')

			leftIK.ChainRoot = char:WaitForChild('Left Arm')
		else
			-- r15
			rightIK.EndEffector = char:WaitForChild('RightHand')
			rightIK.ChainRoot = char:WaitForChild('RightUpperArm')

			leftIK.EndEffector = char:WaitForChild('LeftHand')
			leftIK.ChainRoot = char:WaitForChild('LeftUpperArm')
		end
		

		-- Detects when the player is seated
		huma.Seated:Connect(function(bool, seatIn)
			-- Checks if the player has a vehicle network afterward
			-- If it has one, it calls the main function to disconnect everything
            if not seatIn then
                ripNetwork(localId, '[Seat signal] Rip')
                lastSeat = nil

                return
            end
			-- Checks if it's a VehicleSeat to avoid connecting a regular seat
			-- to the player's network
            if not seatIn:IsA('VehicleSeat') then return end
			ripNetwork(localId, '[Seat signal] Bug-net rip')
			-- Just in case, calls the function to disconnect any type
			-- of connections that may still exist
			
			-- Sets up a function that detects when the occupant of a seat is removed or not
			occupants[localId] = seatIn:GetPropertyChangedSignal('Occupant'):Connect(function()
				if not seatIn.Occupant or seatIn.Occupant ~= huma then
					
					-- If removed, removes the network of that occupant
					ripNetwork(localId, '[Occupant Exit] Rip')
                end
            end)
			
			-- Creates a new network for the player
			network[localId] = seatIn
			-- Grants the Roblox network to the player
			seatIn:SetNetworkOwner(player)
			-- Calls the player's UI to refresh some icons
			addeyEvent:FireClient(player, 'refreshLockIcon', not network[localId].Parent.Parent.Configuration.locked.Value)
			local plataform = network[localId].Parent.Parent.plataform
			
			local rig = network[localId].Parent.Parent.rig.suspension
			rig.RR.CylindricalConstraint.AngularActuatorType = Enum.ActuatorType.None
			rig.RR.CylindricalConstraint.MotorMaxTorque = 0
			rig.RL.CylindricalConstraint.AngularActuatorType = Enum.ActuatorType.None
			rig.RL.CylindricalConstraint.MotorMaxTorque = 0
			
   			 --[[
		     	A function that is fuel, meaning it checks if the car's configuration
		     	has the fuel system, if it does,
		     	creates a heartbeat connected to the fuel memory, and basic calculations are performed
		    ]]
            task.spawn(function() -- full depletion
                if network[localId].Parent.Parent.Configuration:FindFirstChild('fuel') then
                    local last = tick()
                    local fuelInt = network[localId].Parent.Parent.Configuration.fuel
                    fuel[localId] = runService.Heartbeat:Connect(function()
                        if not network[localId] then return end
                        if (tick() - last) < fuelInt.rate.Value then return end
    
                        fuelInt.Value -= fuelInt.amount.Value
                        last = tick()
                    end)
                end
			end)
			
			-- Checks if the system has the addition that tires can break
			if tireAdd_module ~= nil then
				tires[localId] = tireAdd_module.breakTire(network[localId])
			end

			-- Refreshes the radio icon
			radio[localId] = plataform.radio.Changed:Connect(function()
                addeyEvent:FireClient(player, 'refreshRadioIcon', not plataform.radio.IsPlaying)
			end)

            -- flip car & engine
			local flipTick = tick()
			plataform.engine:Play()
			
			-- [Handler of the function that checks if a part is upside down]
			local passengersGui = player.PlayerGui.vehicleGui.pc.passengers.list
            task.spawn(function()
				flipCar[localId] = runService.Heartbeat:Connect(function()
					if network[localId] then
						-- In addition to checking if the car is upside down
						-- the loop is used to play the engine sound
						local maxSpeed = seatIn.MaxSpeed
						local velocity = seatIn.AssemblyLinearVelocity.Magnitude
						plataform.engine.PlaybackSpeed = (velocity / maxSpeed) + 0.1
						if plataform:FindFirstChildWhichIsA('BodyGyro') then return end
						if tick() - flipTick < 1.5 then return end
						
						-- [Verification]
						if isUpsideDown(plataform) then
							local b = Instance.new('BodyGyro', plataform)
							debris:AddItem(b, 1)
						end

						flipTick = tick()
					end
                end)
            end)

			-- Finally, any remaining information in the client systems is sent

            addeyEvent:FireClient(player, 'refreshRadioIcon', not plataform.radio.IsPlaying)
			
			-- Sends all remaining information to the car controller
			carEvent:FireAllClients({
                localId,
                network[localId],
                plataform
            }, 'engine')

            --print('[Seat] New-net')
        end)
    end)
end)
 
-- Detects when the player leaves and sends to check if there is a network [memory]
playerService.PlayerRemoving:Connect(function(player)
    local id = player.UserId
	if network[id] then
		-- This is a bug that occurred in case the car had fallen into the void
		if not network[id]:IsDescendantOf(workspace) then network[id] = nil return end
        network[id]:SetNetworkOwner(nil)
        network[id] = nil
    end
end)
