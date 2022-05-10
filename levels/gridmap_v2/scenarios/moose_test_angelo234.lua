local M = {}

local helper = require('scenario/scenariohelper')

local spawn_pos = vec3(344, 219.67, 100.25)

local zones_speeds_history = {}

-- 1 = zone 1 enter, 2 = zone 1 exit
-- 3 = zone 2 enter, 4 = zone 2 exit
-- 5 = zone 3 enter, 6 = zone 3 exit
local current_zones_speeds = {}

local cones_init_pos = {}

local state = "ready"
local next_trigger = 1

M.last_user_inputs = {
  steering = 0,
  throttle = 0,
  brake = 0,
  parkingbrake = 0,
  clutch = 0
}

local update_ui_timer = 0
local update_ui_delay = 0.25 -- update UI every 0.25 seconds

-- http://lua-users.org/wiki/SimpleRound
function round(num, numDecimalPlaces)
  local mult = 10^(numDecimalPlaces or 0)
  return math.floor(num * mult + 0.5) / mult
end

local function resetSpeeds()
  current_zones_speeds = {}
end

local function failRun(msg)
  if state ~= "failed" then
    local str_msg = msg or ""
  
    helper.flashUiMessage("Run Disqualified! " .. str_msg, 5)     
    state = "failed"
  end
end

local function removeOtherObjects()
  local handling_moose_test = scenetree.zone_handling:findObject("handling_moose_test")
  
  for k, v in pairs(handling_moose_test:getObjects()) do
    local obj = handling_moose_test:findObjectById(v)
    
    if obj.shapeName == "/levels/gridmap_v2/art/shapes/grid/s_gm_flip_dome_4x4.dae" then
      obj:setField('position', '', '0 -999 0')
    end
  end
  
  be:reloadCollision()
end

local function setupCones()
  local veh = be:getPlayerVehicle(0)
  
  local markers = getObjectsByClass("BeamNGPointOfInterest")
  
  -- Sort unsorted markers
  local sorted_markers = {}
  
  for k,v in pairs(markers) do
    if v.name:find("marker") then
      local str_idx = v.name:gsub('%marker', '')
      local idx = tonumber(str_idx)
      
      if idx then
        sorted_markers[idx] = v 
      end
    end
  end
  
  -- Section 1
  -- width (m) = 1.1 * vehicle_width + 0.25
  -- left = pos y axis
  local half_width_1 = 1.1 * veh:getSpawnWorldOOBB():getHalfExtents().x + 0.125
  
  local section1_markers = {"marker1", "marker2", "marker3"}
  local section1_cones = {"cone1l", "cone1r", "cone2l", "cone2r", "cone3l", "cone3r"}
  
  local i = 1
  
  for k, v in pairs(section1_markers) do
    local marker = scenetree.findObject(v)
    local marker_pos = marker:getPosition()
    
    local cone_l = scenetree.findObject(section1_cones[i])
    local cone_r = scenetree.findObject(section1_cones[i + 1])
    
    cone_l:setPosition(marker_pos + vec3(0, half_width_1, 0))
    cone_r:setPosition(marker_pos - vec3(0, half_width_1, 0))
    
    i = i + 2
  end
  
  -- Section 2
  -- width (m) = vehicle_width + 1.0
  local half_width_2 = veh:getSpawnWorldOOBB():getHalfExtents().x + 0.5
  
  local section2_markers = {"marker4", "marker5", "marker6"}
  local section2_cones = {"cone4l", "cone4r", "cone5l", "cone5r", "cone6l", "cone6r"}
  
  local cone3l_pos = scenetree.findObject("cone3l"):getPosition() 
  local marker_y = cone3l_pos.y + 1 + half_width_2

  i = 1
  
  for k, v in pairs(section2_markers) do
    local marker = scenetree.findObject(v)
    local marker_pos = marker:getPosition()
    
    marker:setPosition(vec3(marker_pos.x, marker_y, marker_pos.z))
    marker_pos = marker:getPosition()
    
    local cone_l = scenetree.findObject(section2_cones[i])
    local cone_r = scenetree.findObject(section2_cones[i + 1])
    
    cone_l:setPosition(marker_pos + vec3(0, half_width_2, 0))
    cone_r:setPosition(marker_pos - vec3(0, half_width_2, 0))
    
    i = i + 2
  end
  
  -- Section 3
  -- width (m) = 3
  local half_width_3 = 1.5
  
  local section3_markers = {"marker7", "marker8", "marker9"}
  local section3_cones = {"cone7l", "cone7r", "cone8l", "cone8r", "cone9l", "cone9r"}
  
  i = 1
  
  for k, v in pairs(section3_markers) do
    local marker = scenetree.findObject(v)
    local marker_pos = marker:getPosition()
    
    local cone_l = scenetree.findObject(section3_cones[i])
    local cone_r = scenetree.findObject(section3_cones[i + 1])
    
    cone_l:setPosition(marker_pos + vec3(0, half_width_3, 0))
    cone_r:setPosition(marker_pos - vec3(0, half_width_3, 0))
    
    i = i + 2
  end
  
  -- Store init position of cones for determining if they move later
  for k,v in pairs(map.objects) do
    cones_init_pos[k] = vec3(v.pos)
  end
  
  -- Track cones for movement
  be:queueAllObjectLua("mapmgr.enableTracking()")
end

local function onRaceStart()
  removeOtherObjects()
  setupCones()
  resetSpeeds()
  
  next_trigger = 1
  state = "ready"
end

local function getUserInputs()
  local playerVehicle = be:getPlayerVehicle(0)
  if not playerVehicle then return end
    
  for k, v in pairs(M.last_user_inputs) do    
    playerVehicle:queueLuaCommand("obj:queueGameEngineLua('if not scenario_moose_test_angelo234 then return end scenario_moose_test_angelo234.last_user_inputs." .. k .. " = ' .. input.state." .. k .. ".val)")
  end
end

local function failPlayerOnInputs()
  for k, v in pairs(M.last_user_inputs) do    
    if k ~= "steering" and v > 0 and state == "running" then
      failRun("User input except steering not allowed!")
    end
  end 
end

local function renderUIText(dt)
  if update_ui_timer >= update_ui_delay then
    local speed = 0
    
    if zones_speeds_history[#zones_speeds_history] then 
      speed = zones_speeds_history[#zones_speeds_history][2]
    end
    
    guihooks.message("Last Exit Speed: " .. string.format("%.1f", round(speed * 3.6, 1)) .. " km/h", 2 * update_ui_delay, "num_deliveries")
  
    update_ui_timer = 0
  end
  
  update_ui_timer = update_ui_timer + dt
end

local function onPreRender(dt, dtSim)
  getUserInputs() 
  failPlayerOnInputs()
  
  -- Display UI text
  renderUIText(dt)
end

local function onRaceTick(raceTickTime, scenarioTimer)
  local playerVeh = be:getPlayerVehicle(0)
  
  for k,v in pairs(map.objects) do
    if v.id ~= playerVeh:getID() then
      local dist_moved = (v.pos - cones_init_pos[k]):length()
      
      if dist_moved > 0.1 then  
        -- Cone hit!!!
        failRun("You hit a cone!")
        break
      end
    end
  end
end

local function resetScene()
  local playerVeh = be:getPlayerVehicle(0)
  
  -- Move all cones back to original positions
  local allVehicles = scenetree.findClassObjects('BeamNGVehicle')
  for k, vehicleName in ipairs(allVehicles) do
    local vehicle = scenetree.findObject(vehicleName)
    if vehicle and vehicle:getID() ~= playerVeh:getID() then
      vehicle:resetBrokenFlexMesh()
      vehicle:reset()
    end
  end
  
  -- Set vehicle position back to original position
  -- but with current velocity
  playerVeh:setPosition(spawn_pos)
  
  resetSpeeds()
  
  next_trigger = 1
  state = "ready"
end

local function setSpeedAndVerify(i)
  local speed = be:getPlayerVehicle(0):getVelocity():length()
  
  print("Trigger:" .. i)
  print(next_trigger)
  
  if next_trigger == i then
    current_zones_speeds[i] = speed
  
    next_trigger = i + 1
  
  elseif current_zones_speeds[i] == nil then
    failRun()
  end
end

local function successfulRun()
  zones_speeds_history[#zones_speeds_history + 1] = current_zones_speeds
  
  helper.flashUiMessage("Successful Run!", 3)
  
  state = "finished"
end

local function onBeamNGTrigger(data)
  local veh = be:getPlayerVehicle(0)
  
  -- Only care about player on triggers
  if not veh or data.subjectName ~= "thePlayer" then return end
  
  if data.triggerName == "zone_1_enter_trigger" then
    state = "running"
    setSpeedAndVerify(1)

  elseif data.triggerName == "zone_1_exit_trigger" then
    setSpeedAndVerify(2)
  
  elseif data.triggerName == "zone_2_enter_trigger" then
    setSpeedAndVerify(3)
  
  elseif data.triggerName == "zone_2_exit_trigger" then
    setSpeedAndVerify(4)
  
  elseif data.triggerName == "zone_3_enter_trigger" then
    setSpeedAndVerify(5)
  
  elseif data.triggerName == "zone_3_exit_trigger" then
    if data.event == "enter" then
      setSpeedAndVerify(6)
      
    elseif data.event == "exit" then
      if state == "running" then
        successfulRun()
      end
    end
  
  elseif data.triggerName == "finish_trigger" then
    resetScene()
  end
end

M.onRaceStart = onRaceStart
M.onPreRender = onPreRender
M.onRaceTick = onRaceTick
M.onBeamNGTrigger = onBeamNGTrigger

return M