local M = {}

local im = extensions.ui_imgui
local helper = require('scenario/scenariohelper')

local initial_window_size = im.ImVec2(300, 200)

local spawn_pos = vec3(344, 219.67, 100.25)

local runs_json_file_dir = "settings/moose_test_angelo234/runs.json"

M.last_user_inputs = {
  steering = 0,
  throttle = 0,
  brake = 0,
  parkingbrake = 0,
  clutch = 0
}

M.last_sensors_data = {
  gx2 = 0,
  gy2 = 0,
  gz2 = 0
}

-- 1 = zone 1 enter, 2 = zone 1 middle, 3 = zone 1 exit
-- 4 = zone 2 enter, 5 = zone 2 middle, 6 = zone 2 exit
-- 7 = zone 3 enter, 8 = zone 3 middle, 9 = zone 3 exit
local zones_speeds = {}

local acc_data =
{
  max_forward_acc = 0,
  max_lateral_acc = 0,
  sum_forward_acc = 0,
  sum_lateral_acc = 0,
  num_samples = 0,
  avg_forward_acc = 0,
  avg_lateral_acc = 0
}

local cones_init_pos = {}
local reset_cone_timer = -1

local state = "ready"
local next_trigger = 1

local update_ui_timer = 0
local update_ui_delay = 0.25 -- update UI every 0.25 seconds

local window_open = im.BoolPtr(true) -- this just holds window open state
local show_window = false

local runs_data = {}

local last_run_index = -1

local function onScenarioUIReady(state)
  show_window = true
end

local function readRunsJSONFile()
  runs_data = jsonReadFile(runs_json_file_dir) or {}
end

local function addRunToJSONFile(new_run)
  if tableSize(runs_data) == 0 then
    table.insert(runs_data, new_run)
    last_run_index = 1
  else
    local added = false

    -- Place new entry in correct order by speed
    for k,v in ipairs(runs_data) do
      if new_run.speeds[1] > v.speeds[1] then
        table.insert(runs_data, k, new_run)
        last_run_index = k

        added = true
        break
      end
    end

    if not added then
      table.insert(runs_data, new_run)
      last_run_index = #runs_data
    end
  end

  jsonWriteFile(runs_json_file_dir, runs_data)
end

local function removeRunFromJSONFile(id)
  table.remove(runs_data, id)
  jsonWriteFile(runs_json_file_dir, runs_data)

  if id < last_run_index then
    last_run_index = last_run_index - 1
  elseif id == last_run_index then
    last_run_index = -1
  end
end

local function removeAllRunsFromJSONFile()
  runs_data = {}
  jsonWriteFile(runs_json_file_dir, runs_data)

  last_run_index = -1
end

local function onExtensionLoaded()
  readRunsJSONFile()
end

-- http://lua-users.org/wiki/SimpleRound
function round(num, numDecimalPlaces)
  local mult = 10^(numDecimalPlaces or 0)
  return math.floor(num * mult + 0.5) / mult
end

local function resetData()
  zones_speeds = {}
  acc_data = {
    max_forward_acc = 0,
    max_lateral_acc = 0,
    sum_forward_acc = 0,
    sum_lateral_acc = 0,
    num_samples = 0,
    avg_forward_acc = 0,
    avg_lateral_acc = 0
  }
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

  -- Section 1
  -- width (m) = 1.1 * vehicle_width + 0.25
  -- left = pos y axis
  local half_width_1 = 1.1 * veh:getSpawnWorldOOBB():getHalfExtents().x + 0.125

  local section1_triggers = {"zone_trigger1", "zone_trigger2", "zone_trigger3"}
  local section1_cones = {"cone1l", "cone1r", "cone2l", "cone2r", "cone3l", "cone3r"}

  local i = 1

  for k, v in pairs(section1_triggers) do
    local trigger = scenetree.findObject(v)
    local trigger_pos = trigger:getPosition()

    local cone_l = scenetree.findObject(section1_cones[i])
    local cone_r = scenetree.findObject(section1_cones[i + 1])

    cone_l:setPosition(trigger_pos + vec3(0, half_width_1, 0))
    cone_r:setPosition(trigger_pos - vec3(0, half_width_1, 0))

    i = i + 2
  end

  -- Section 2
  -- width (m) = vehicle_width + 1.0
  local half_width_2 = veh:getSpawnWorldOOBB():getHalfExtents().x + 0.5

  local section2_triggers = {"zone_trigger4", "zone_trigger5", "zone_trigger6"}
  local section2_cones = {"cone4l", "cone4r", "cone5l", "cone5r", "cone6l", "cone6r"}

  local cone3l_pos = scenetree.findObject("cone3l"):getPosition()
  local trigger_y = cone3l_pos.y + 1 + half_width_2

  i = 1

  for k, v in pairs(section2_triggers) do
    local trigger = scenetree.findObject(v)
    local trigger_pos = trigger:getPosition()

    trigger:setPosition(vec3(trigger_pos.x, trigger_y, trigger_pos.z))
    trigger_pos = trigger:getPosition()

    local cone_l = scenetree.findObject(section2_cones[i])
    local cone_r = scenetree.findObject(section2_cones[i + 1])

    cone_l:setPosition(trigger_pos + vec3(0, half_width_2, 0))
    cone_r:setPosition(trigger_pos - vec3(0, half_width_2, 0))

    i = i + 2
  end

  -- Section 3
  -- width (m) = 3
  local half_width_3 = 1.5

  local section3_triggers = {"zone_trigger7", "zone_trigger8", "zone_trigger9"}
  local section3_cones = {"cone7l", "cone7r", "cone8l", "cone8r", "cone9l", "cone9r"}

  i = 1

  for k, v in pairs(section3_triggers) do
    local trigger = scenetree.findObject(v)
    local trigger_pos = trigger:getPosition()

    local cone_l = scenetree.findObject(section3_cones[i])
    local cone_r = scenetree.findObject(section3_cones[i + 1])

    cone_l:setPosition(trigger_pos + vec3(0, half_width_3, 0))
    cone_r:setPosition(trigger_pos - vec3(0, half_width_3, 0))

    i = i + 2
  end

  reset_cone_timer = 0
end

local function onRaceStart()
  core_input_actionFilter.setGroup('camera_blacklist', {"toggleCamera", "dropCameraAtPlayer", "dropPlayerAtCamera"})
  core_input_actionFilter.addAction(0, 'camera_blacklist', false)

  -- Deactivate when watching replay
  if core_replay.state.state == "playing" then return end

  removeOtherObjects()
  setupCones()
  resetData()

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

local function getVehicleSensorsData()
  local playerVehicle = be:getPlayerVehicle(0)
  if not playerVehicle then return end

  for k, v in pairs(M.last_sensors_data) do
    playerVehicle:queueLuaCommand("obj:queueGameEngineLua('if not scenario_moose_test_angelo234 then return end scenario_moose_test_angelo234.last_sensors_data." .. k .. " = ' .. sensors." .. k .. ")")
  end

  acc_data.max_forward_acc = math.max(M.last_sensors_data.gy2, acc_data.max_forward_acc)
  acc_data.max_lateral_acc = math.max(math.abs(M.last_sensors_data.gx2), acc_data.max_lateral_acc)

  --
  acc_data.sum_forward_acc = acc_data.sum_forward_acc + M.last_sensors_data.gy2
  acc_data.sum_lateral_acc = acc_data.sum_lateral_acc + math.abs(M.last_sensors_data.gx2)
  acc_data.num_samples = acc_data.num_samples + 1

  acc_data.avg_forward_acc = acc_data.sum_forward_acc / acc_data.num_samples
  acc_data.avg_lateral_acc = acc_data.sum_lateral_acc / acc_data.num_samples
end

local function failPlayerOnInputs()
  for k, v in pairs(M.last_user_inputs) do
    if k ~= "steering" and v > 0 and state == "running" then
      failRun("User input except steering not allowed!")
    end
  end
end

local im_char_size = 6.25
local x_button_size = 15

local function renderIMGUI()
  if not show_window then return end

  im.SetNextWindowSize(initial_window_size, im.Cond_FirstUseEver)

  if im.Begin('Moose Test Leaderboard', window_open, im.WindowFlags_MenuBar) then
    if im.BeginMenuBar() then
      if im.BeginMenu("File") then
        --im.PushStyleColor2(im.Col_Text, im.ImVec4(1, 0, 0, 1))
        --im.PopStyleColor()

        if im.MenuItem1("Remove All Runs") then
          removeAllRunsFromJSONFile()
        end
        im.EndMenu()
      end

      im.EndMenuBar()
    end

    for k,v in ipairs(runs_data) do
      if v.speeds and v.acc_data and v.config_name then
        local str_entrance_speed = string.format("%.1f", round(v.speeds[1] * 3.6, 1))
        local str_middle_speed = string.format("%.1f", round(v.speeds[5] * 3.6, 1))
        local str_exit_speed = string.format("%.1f", round(v.speeds[9] * 3.6, 1))

        local str_max_fwd_acc = string.format("%.2f", round(-v.acc_data.max_forward_acc / 9.80665, 2))
        local str_max_lat_acc = string.format("%.2f", round(v.acc_data.max_lateral_acc / 9.80665, 2))
        local str_avg_fwd_acc = string.format("%.2f", round(-v.acc_data.avg_forward_acc / 9.80665, 2))
        local str_avg_lat_acc = string.format("%.2f", round(v.acc_data.avg_lateral_acc / 9.80665, 2))

        local avail = im.GetContentRegionAvail().x - x_button_size

        local full_text = tostring(k) .. ". " .. str_entrance_speed .. " km/h, " .. v.config_name
        local text_displayed = string.sub(full_text, 1, math.floor(avail / im_char_size))

        if last_run_index == k then
          im.PushFont3("cairo_bold")
          im.Text(text_displayed)
          im.PopFont()
        else
          im.Text(text_displayed)
        end

        local tooltip_text =
          v.config_name .. "\n"
          .. "Entrance/Middle/Exit Speed: " .. str_entrance_speed .. "/" .. str_middle_speed .. "/" .. str_exit_speed .. " km/h\n"
          .. "Max Forward/Lateral Acceleration: " .. str_max_fwd_acc .. "/" .. str_max_lat_acc .. " g's\n"
          .. "Avg Forward/Lateral Acceleration: " .. str_avg_fwd_acc .. "/" .. str_avg_lat_acc .. " g's"


        im.tooltip(tooltip_text)

        im.SameLine(avail)

        --im.PushStyleColor2(im.Col_Text, im.ImVec4(1, 0, 0, 1))
        if im.Button("X##" .. tostring(k)) then
          removeRunFromJSONFile(k)
        end
      end
      --im.PopStyleColor()
    end
  end
  im.End()
end

local function resetConeTimer(dt)
  if reset_cone_timer >= 1 then
    -- Store init position of cones for determining if they move later
    for k,v in pairs(map.objects) do
      cones_init_pos[k] = vec3(v.pos)
    end

    -- Track cones for movement
    be:queueAllObjectLua("mapmgr.enableTracking()")

    reset_cone_timer = -1
  end

  if reset_cone_timer >= 0 then
    reset_cone_timer = reset_cone_timer + dt
  end
end

local function onUpdate(dt)
  -- Display UI text
  renderIMGUI()

  -- Deactivate when watching replay
  if core_replay.state.state == "playing" then return end

  resetConeTimer(dt)

  getUserInputs()

  if state == "running" then -- user has entered cones
    getVehicleSensorsData()

    failPlayerOnInputs()
  end
end

local function onRaceTick(raceTickTime, scenarioTimer)
  -- Deactivate when watching replay
  if core_replay.state.state == "playing" then return end

  local playerVeh = be:getPlayerVehicle(0)

  if tableSize(cones_init_pos) > 0 and reset_cone_timer == -1 then
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
end

local function resetScene()
  local playerVeh = be:getPlayerVehicle(0)

  reset_cone_timer = 0

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
  playerVeh:setPositionNoPhysicsReset(spawn_pos)

  resetData()

  next_trigger = 1
  state = "ready"
end

local function setSpeedAndVerify(i)
  local speed = be:getPlayerVehicle(0):getVelocity():length()

  if next_trigger == i then
    zones_speeds[i] = speed

    next_trigger = i + 1

  elseif zones_speeds[i] == nil then
    failRun()
  end
end

local function successfulRun()
  local config_data = core_vehicles.getCurrentVehicleDetails().configs
  local veh_config = config_data.Name
  local veh_name = nil

  if config_data.aggregates.Brand then
    local veh_brand = tableKeys(config_data.aggregates.Brand)[1]
    veh_name = veh_brand .. " " .. veh_config
  else
    veh_name = veh_config
  end

  -- Save speed to file
  addRunToJSONFile({
      config_name = veh_name,
      speeds = zones_speeds,
      acc_data = acc_data
  })

  helper.flashUiMessage("Successful Run!", 3)

  state = "finished"
end

local function onBeamNGTrigger(data)
  -- Deactivate when watching replay
  if core_replay.state.state == "playing" then return end

  local veh = be:getPlayerVehicle(0)

  -- Only care about player on triggers
  if not veh or data.subjectName ~= "thePlayer" then return end

  if data.triggerName == "zone_trigger1" then
    if data.event == "enter" then
      state = "running"

      setSpeedAndVerify(1)
    end

  elseif data.triggerName == "zone_trigger9" then
    if data.event == "enter" then
      setSpeedAndVerify(9)

    elseif data.event == "exit" then
      if state == "running" then
        successfulRun()
      end
    end

  elseif data.triggerName == "finish_trigger" then
    if data.event == "enter" then
      resetScene()
    end

  elseif data.triggerName:find("zone_trigger") then
    if data.event == "enter" then
      local str_id = data.triggerName:match("%d+")
      local id = tonumber(str_id)

      setSpeedAndVerify(id)
    end
  end

end

M.onScenarioUIReady = onScenarioUIReady
M.onExtensionLoaded = onExtensionLoaded
M.onRaceStart = onRaceStart
M.onUpdate = onUpdate
M.onRaceTick = onRaceTick
M.onBeamNGTrigger = onBeamNGTrigger

return M