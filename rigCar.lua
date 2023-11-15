--[[
 This is a script that I use to automatically rig the entire physics system 
 and constraints of my vehicle system.
 
 * If you want to see it in the game, just spawn a car, 
   and you'll see it in action.
]]


--[[

This service is only meant for converting the settings table to JSON, 
in order to save memory and subsequently use it for more integrated systems.
]]
local httpService = game:GetService('HttpService')

local chassis = script.Parent
local plataform = chassis.plataform
local bodyModel = chassis.body
local wheelsModel = chassis.wheels

plataform.Anchored = true

local setts = {
	traction = 'awd',
	motorpower = 5000, --only affect awd traccion
	driftVfxMinSpeed = 40,
	--[[
		tractions:
		'awd': all wheel drive
		'rwd': rear wheel drive
		'fwd': front wheel drive
	--]]
	springs = {
		damping = 5000,
		stiffness = 55000,
		freeLength = 2.1,
		
		limits = {
			enabled = false,
			min = 1.1,
			max = 0
		}
	},
	cylindricals = {
		enabled = true,
		lower = -0.2,
		restitution = 0,
		upper = -6.2,
		
		-- handbrake
		restitutionAngle = 0.1,
		lowerAngle = -100,
		upperAngle = 150,
		
		-- stop car
		maxmotortorque = 4500
	},
	spawnTick = tick()
}

-- Here is where the HTTP service is used to convert a table to JSON.
local VTable = Instance.new('StringValue', chassis)
VTable.Value = httpService:JSONEncode(setts)
VTable.Name = 'VTable'


-- Create Folders
local chassisRig = Instance.new('Folder', chassis)
chassisRig.Name = 'rig'

local suspensionRig = Instance.new('Folder', chassisRig)
suspensionRig.Name = 'suspension'

local bodyWelds = Instance.new('Folder', chassisRig)
bodyWelds.Name = 'welds'

local wheelsRig = Instance.new('Folder', wheelsModel)
wheelsRig.Name = 'rig'

-- Configure body
for i,v in pairs(bodyModel:GetDescendants()) do
	--[[
	All settings are automatically applied to the BaseParts of the model
	to prevent issues, especially if it's a model from the toolbox. By this, 
	I mean ensuring that all parts have the same configuration. Subsequently, 
	welds are created to connect it to the central base of the vehicle.
	]]
	if not v:IsA('BasePart') then continue end

	v.CanCollide = true
	v.CanQuery = true
	v.CanTouch = false
	v.Massless = true

	local w = Instance.new('WeldConstraint', bodyWelds)
	w.Part0 = plataform
	w.Part1 = v

	v.Anchored = false
end

-- set-up wheels
--[[
Some rotations are set to automatically rig the wheels of the car.
]]
local wheelRotation = {
	FL = CFrame.Angles(0,0,0),
	RL = CFrame.Angles(0,0,0),
	FR = CFrame.Angles(0,math.rad(180),0),
	RR = CFrame.Angles(0,math.rad(180),0),
}

local originWheel = wheelsModel.origin


for i,v in pairs(wheelRotation) do
	--[[
	The single 3D wheel model provided by the user is obtained, 
	and then four additional wheels are created. 
	They are configured with their respective positions and rotations. 
	Once the process is complete, the initially used wheel for cloning is deleted, 
	as it is no longer necessary. While it could have been used to create only three wheels, 
	the decision was made to delete it.
	]]
	local newWheel = originWheel:Clone()
	newWheel.Parent = wheelsModel
	newWheel.Name = i
	
	local pivotCFrame = newWheel['3d']:GetPivot()
	newWheel['3d']:PivotTo(pivotCFrame*v)
end

originWheel:Destroy()

-- configure wheels
-- The physical parts and their constraints are organized into respective folders for each wheel to maintain a better visual order.
for i,model in pairs(wheelsModel:GetChildren()) do
	if model.Name == wheelsRig.Name then continue end

	-- wheel folders
	local folder = Instance.new('Folder', wheelsRig)
	folder.Name = model.Name
	local welds = Instance.new('Folder', folder)
	welds.Name = 'welds'
	local nccs = Instance.new('Folder', folder)
	nccs.Name = 'nccs'

	local physicalWheel = model.physicalWheel

	-- 3d configure
	--[[
	The physics of the 3D wheel models, such as meshes, 
	are disabled since they are purely visual and might have poorly constructed hitboxes.
	]]
	for i,child in pairs(model['3d']:GetDescendants()) do
		if not child:IsA('BasePart') then continue end

		child.CanCollide = false
		child.CanQuery = false
		child.CanTouch = false
		child.Massless = true

		local w = Instance.new('WeldConstraint', welds)
		w.Part0 = physicalWheel
		w.Part1 = child
		w.Name = child.Name

		child.Anchored = false
	end

	-- nccs
	--[[
	NoCollisionConstraint is created to ensure that the meshes and the 
	physical (invisible) wheels do not interfere with the physics of the car.
	]]
	for i,child in pairs(bodyModel:GetDescendants()) do
		if not child:IsA('BasePart') then continue end

		local n = Instance.new('NoCollisionConstraint', nccs)
		n.Part0 = physicalWheel
		n.Part1 = child
		n.Name = child.Name
	end

	-- suspension
	local rig = Instance.new('Folder', suspensionRig)
	rig.Name = model.Name
	
	--model:MoveTo(plataform[model.Name].WorldPosition - Vector3.new(0,model.physicalWheel.Size.Y,0))
	physicalWheel.Anchored = true

	local attachment = Instance.new('Attachment', physicalWheel)
	attachment.Orientation = Vector3.new(90, -180, 0)

	--- cylindrical
	--[[
	All constraints are configured with the settings specified in the table.
	]]
	local cylindrical = Instance.new('CylindricalConstraint',rig)
	local cTab = setts.cylindricals

	cylindrical.Attachment0 = plataform[model.Name]
	cylindrical.Attachment1 = attachment

	cylindrical.InclinationAngle = 90
	cylindrical.LowerLimit = cTab.lower
	cylindrical.Restitution = cTab.restitution
	cylindrical.UpperLimit = cTab.upper
	cylindrical.LowerAngle = cTab.lowerAngle
	cylindrical.UpperAngle = cTab.upperAngle
	cylindrical.AngularRestitution = cTab.restitutionAngle
	
	if not model.Name:find('F') then
		cylindrical.AngularActuatorType = Enum.ActuatorType.Motor
		cylindrical.MotorMaxTorque = cTab.maxmotortorque
	end

	if cTab.enabled then
		cylindrical.LimitsEnabled = true
	end

	--- spring
	--Similarly, the springs are configured with the settings specified in the table.
	local spring = Instance.new('SpringConstraint',rig)
	local sTab = setts.springs

	spring.Attachment0 = plataform[model.Name]
	spring.Attachment1 = attachment

	spring.FreeLength = sTab.freeLength
	spring.Stiffness = sTab.stiffness
	spring.Damping = sTab.damping
	
	spring.MaxLength = sTab.limits.max
	spring.MinLength = sTab.limits.min

	if sTab.limits.enabled then
		spring.LimitsEnabled = true
	end
	physicalWheel.Anchored = false
	physicalWheel.CanCollide = true
end

-- seats
-- All seats are anchored to the central base of the vehicle.
for i,seat in pairs(chassis.seats:GetChildren()) do
	if seat:IsA('Seat') or seat:IsA('VehicleSeat') then
		seat.Anchored = false
		seat.CanCollide = false
		seat.CanTouch = false
		seat.CanQuery = false
		seat.Massless = true

		local w = Instance.new('WeldConstraint', bodyWelds)
		w.Part0 = plataform
		w.Part1 = seat
		w.Name = seat.Name
	end
end

-- ui
--[[
This is essentially to adjust the position of a UI above the car,
such as a timer counting down to disappear when there are no people seated.
]]
local sizeOfChassis = chassis:GetExtentsSize()
plataform.deSpawnGui.StudsOffset = Vector3.new(0, sizeOfChassis.Y/2+3, 0)

plataform.Anchored = false
script:Destroy()
--[[
Finally, the script is deleted as it serves a single purpose, 
which is to rig the car, and it is not needed thereafter.
]]