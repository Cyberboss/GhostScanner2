--[[ Copyright (c) 2019 Optera
 * update 2.0, 2.1 by Tiavor
 * update 2.2 by KeinNIemand
 * Part of Ghost Scanner
 *
 * See LICENSE.md in the project directory for license information.
--]]

-- local logger = require("__OpteraLib__.script.logger")
-- logger.settings.read_all_properties = false
-- logger.settings.max_depth = 6

-- logger.settings.class_dictionary.LuaEntity = {
--   backer_name = true,
--   name = true,
--   type = true,
--   unit_number = true,
--   force = true,
--   logistic_network = true,
--   logistic_cell = true,
--   item_requests = true,
--   ghost_prototype = true,
--  }
-- logger.settings.class_dictionary.LuaEntityPrototype = {
--   type = true,
--   name = true,
--   valid = true,
--   items_to_place_this = true,
--   next_upgrade = true,
--  }

local coreUtil = require("__core__/lualib/util")

-- constant prototypes names
local Scanner_Name = "ghost-scanner"

-- MOD SETTINGS --
local sapt = settings.global["ghost-scanner-scan-areas-per-tick"].value
local UpdateInterval = settings.global["ghost-scanner-update-interval"].value
--How long to wait between scanning sapt number of areas
local ScanAreaDelay = settings.global["ghost-scanner-area-scan-delay"].value
local MaxResults = settings.global["ghost-scanner-max-results"].value
if MaxResults == 0 then MaxResults = nil end
local ShowHidden = settings.global["ghost-scanner-show-hidden"].value
local InvertSign = settings.global["ghost-scanner-negative-output"].value
local RoundToStack = settings.global["ghost-scanner-round2stack"].value
--local ShowCellCount = settings.global["ghost-scanner-cell-count"].value

script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
  if event.setting == "ghost-scanner-update-interval" then
    UpdateInterval = settings.global["ghost-scanner-update-interval"].value
    UpdateEventHandlers()
  end
  if event.setting == "ghost-scanner-scan-areas-per-tick" then
    sapt = settings.global["ghost-scanner-scan-areas-per-tick"].value
    UpdateEventHandlers()
  end
  if event.setting == "ghost-scanner-max-results" then
    MaxResults = settings.global["ghost-scanner-max-results"].value
    if MaxResults == 0 then MaxResults = nil end
  end
  if event.setting == "ghost-scanner-show-hidden" then
    ShowHidden = settings.global["ghost-scanner-show-hidden"].value
    global.Lookup_items_to_place_this = {}
  end
  if event.setting == "ghost-scanner-negative-output" then
    InvertSign = settings.global["ghost-scanner-negative-output"].value
  end
  if event.setting == "ghost-scanner-round2stack" then
    RoundToStack = settings.global["ghost-scanner-round2stack"].value
  end
  --if event.setting == "ghost-scanner-cell-count" then
  --  ShowCellCount = settings.global["ghost-scanner-cell-count"].value
  --end
end)

--log("UpdateInterval = "..tostring(UpdateInterval))
-- EVENTS --

do -- create & remove
  function OnEntityCreated(event)
    local entity = event.created_entity or event.entity
    if entity and entity.valid then
      if entity.name == Scanner_Name then
        global.GhostScanners = global.GhostScanners or {}

        -- entity.operable = false
        -- entity.rotatable = false

        local ghostScanner = {}
        ghostScanner.ID = entity.unit_number
        ghostScanner.entity = entity
        global.GhostScanners[#global.GhostScanners+1] = ghostScanner
        --log("adding scanner "..tostring(ghostScanner.ID))

        UpdateEventHandlers()
      end

    end

  end

  function RemoveSensor(id)
    --log("removing scanner "..tostring(id))
    for i=#global.GhostScanners, 1, -1 do
      if id == global.GhostScanners[i].ID then
        table.remove(global.GhostScanners,i)
      end
    end
    CleanUp(id)
    UpdateEventHandlers()
  end

  function CleanUp(id)
    --log("cleaning up "..tostring(id))
    global.ScanSignals[id] = nil
    global.signal_indexes[id] = nil
    global.ScanAreas[id] = nil
    global.found_entities[id]=nil
  end

  function OnEntityRemoved(event)
  -- script.on_event({defines.events.on_pre_player_mined_item, defines.events.on_robot_pre_mined, defines.events.on_entity_died}, function(event)
    if event.entity.name == Scanner_Name then
      RemoveSensor(event.entity.unit_number)
    end
  end
end
do -- tick handlers
  function UpdateEventHandlers()
    -- unsubscribe tick handlers
    script.on_event(defines.events.on_tick, nil)

    local entity_count = #global.GhostScanners
    if entity_count > 0 then
      --log("found some GhostScanners "..tostring(global.GhostScanners))
      script.on_event(defines.events.on_tick, OnTick)
      script.on_nth_tick(math.floor(UpdateInterval+1), OnNthTick)
      script.on_event({defines.events.on_pre_player_mined_item, defines.events.on_robot_pre_mined, defines.events.on_entity_died}, OnEntityRemoved)
    else  -- all sensors removed
      script.on_event({defines.events.on_pre_player_mined_item, defines.events.on_robot_pre_mined, defines.events.on_entity_died}, nil)
    end
  end


  function OnTick(event)

    if not (event.tick % ScanAreaDelay == 0) then return end
    --log("number of ScanAreas "..tostring(#global.ScanAreas))
    --log("updateindex: "..tostring(global.UpdateIndex))
    --log("number of Scanners "..tostring(#global.GhostScanners))
    if not global.UpdateTimeout then
      if global.UpdateIndex > #global.GhostScanners then
        --log("updateindex (over max): "..tostring(global.UpdateIndex))
        global.UpdateIndex = 1
        global.UpdateTimeout = true
      else
        --log("updateindex: "..tostring(global.UpdateIndex))
        UpdateSensor(global.GhostScanners[global.UpdateIndex])
        global.UpdateIndex = global.UpdateIndex + 1
      end
    end
    UpdateArea()
  end

  -- runs when #global.GhostScanners <= UpdateInterval/2
  function OnNthTick(NthTickEvent)
    global.UpdateTimeout=false
  end

end

function dump(o)
  if type(o) == 'table' then
     local s = '{ '
     for k,v in pairs(o) do
        if type(k) ~= 'number' then k = '"'..k..'"' end
        s = s .. '['..k..'] = ' .. dump(v) .. ','
     end
     return s .. '} '
  else
     return tostring(o)
  end
end



-- update Sensor --
do
  local signals

  function UpdateArea()

    if global.ScanAreas == nil then
      --log("no scanAreas in list")
      return
    end
    
    --log("start update area")
    -- read and delete (sapt) number of entries from global.scanAreas
    local num = 1
    --log("ScanAreas: "..dump(global.ScanAreas))
    --log("GhostScanners: "..dump(global.GhostScanners))
    for id, cells in next, global.ScanAreas do
      --log("ID: "..tostring(id))
      local tempAreas = {}
      --log("scanner ID is "..tostring(i))
      if cells ~= nil and cells.cells ~= nil and #cells.cells > 0 then
        --log("number of cells "..tostring(#cells.cells))
        local force=cells.force
        for _,cell in pairs(cells.cells) do
          --log("cell is "..dump(cell))
          if num <= sapt then
            if cell ~= nil then
              if global.ScanSignals[id] == nil then
                --log("attempting to get new signals")
                global.signal_indexes[id]=nil
                global.ScanSignals[id]=get_ghosts_as_signals(id,cell,force,{})
                --log("signals from "..tostring(id).." : "..dump(global.ScanSignals[id]))
              else
                global.ScanSignals[id]=get_ghosts_as_signals(id,cell,force,global.ScanSignals[id])
                --log("signals from "..tostring(id).." : "..dump(global.ScanSignals[id]))
              end
            end
          else
            table.insert(tempAreas,cell)
          end
          num = num + 1
        end
        
        -- --set signals
        for j=#global.GhostScanners, 1, -1 do
          --log("checking index "..tostring(j).." id "..tostring(id).." vs Scanner "..tostring(global.GhostScanners[j].ID).." from max "..tostring(#global.GhostScanners))
          if id == global.GhostScanners[j].ID then
            if not global.ScanSignals[id] then
              global.GhostScanners[j].entity.get_control_behavior().parameters = nil
              --log("no signals found for scanner "..tostring(id))
              break
            end
            --log("adding signals to ghostscanner id "..tostring(id).." at index "..tostring(j).." signals: "..dump(signals))
            global.GhostScanners[j].entity.get_control_behavior().parameters = global.ScanSignals[id] --tablecopy(global.ScanSignals[id])
            break
          else
            if j==1 then
              CleanUp(id)
            end
          end
        end
        if #tempAreas > 0 then
          global.ScanAreas[id].cells=tablecopy(tempAreas)
          tempAreas={}
          --log("cells larger than limit, inserting tempArea to ScanArea")
          break
        else          
          --log("removing "..tostring(id).." from ScanArea")
          global.ScanAreas[id]=nil
          global.found_entities[id]=nil
        end
      end
    end
    --if num == 1 then
    --  global.found_entities[id]={}
    --end
  end

  local function get_items_to_place(prototype)
    local overide_items_to_place = function(name)
      local prefix = "waterGhost-"
      if (coreUtil.string_starts_with(name,prefix)) then
        --get the original entity name from the dummy entity name
        local originalEntityName = string.sub(name, string.len(prefix) + 1)
        return originalEntityName
      else
        return name
      end 
    end

    local itemsToPlace = prototype.items_to_place_this;
    for index, value in pairs(itemsToPlace) do
      itemsToPlace[index].name = overide_items_to_place(value.name)
    end


    if ShowHidden then
      global.Lookup_items_to_place_this[prototype.name] = itemsToPlace
    else
      -- filter items flagged as hidden
      local items_to_place_filtered = {}
      for _, v in pairs (itemsToPlace) do
        local item = v.name and game.item_prototypes[v.name]
        if item and item.has_flag("hidden") == false then
          items_to_place_filtered[#items_to_place_filtered+1] = v
        end
      end
      global.Lookup_items_to_place_this[prototype.name] = items_to_place_filtered
    end
    return global.Lookup_items_to_place_this[prototype.name]
  end

  local function add_signal(id, name, count)
    local signal_index = global.signal_indexes[id][name]
    local s
    if signal_index and signals[signal_index] then
      s = signals[signal_index]
    else
      signal_index = #signals+1
      global.signal_indexes[id][name] = signal_index
      s = { signal = { type = "item", name = name }, count = 0, index = (signal_index) }
      signals[signal_index] = s
    end

    if InvertSign then
      s.count = s.count - count
    else
      s.count = s.count + count
    end
  end

  local function is_in_bbox(pos, area)
    if pos.x >= area.left_top.x and pos.x <= area.right_bottom.x
    and pos.y >= area.left_top.y and pos.y <= area.right_bottom.y then
      return true
    end
    return false
  end

  --- returns ghost requested items as signals or nil
  function get_ghosts_as_signals(id,cell,force,prev_entry)
    local result_limit = MaxResults
    --log("in get_ghosts:")
    --log("entities: "..dump(global.found_entities))
     -- store found unit_numbers to prevent duplicate entries
    if global.found_entities == nil then
      global.found_entities={}
    end
    if global.found_entities[id] == nil then
      global.found_entities[id]={}
    end 
    --log("entities: "..dump(global.found_entities))
    --log("entities at id "..tostring(id)..": "..dump(global.found_entities[id]))
    signals = prev_entry
    if global.signal_indexes == nil then
      global.signal_indexes = {}
    end
    if signals == nil then
      signals = {}
      global.signal_indexes[id] = {}
    end
    --log("signal_indexes "..dump(global.signal_indexes))
    if global.signal_indexes[id] == nil then
      global.signal_indexes[id] = {}
    end
    --log("signal_indexes "..dump(global.signal_indexes))
    --log("signal_indexes at id: "..dump(global.signal_indexes[id]))
    --log("starting get_ghosts_as_signals")
    if cell == nil or not cell.valid then
      return {}
    end
    local pos = cell.owner.position
    local r = cell.construction_radius
    --log("construction radius "..tostring(r))
    if r > 0 then
      --log("found cell at "..dump(pos).." with radius "..tostring(r))
      local bounds = {
        left_top={ x=pos.x-r, y=pos.y-r, },
        right_bottom={ x=pos.x+r, y=pos.y+r }
      }
      local inner_bounds = { -- hack to skip checking if position is inside bounds for tiles
        left_top={ x=pos.x-r+0.001, y=pos.y-r+0.001, },
        right_bottom={ x=pos.x+r-0.001, y=pos.y+r-0.001 }
      }
      search_area = {
        bounds=bounds,
        inner_bounds=inner_bounds,
        force=force,
        surface=cell.owner.surface
      }
    end

    -- cliffs
    do
      local entities = search_area.surface.find_entities_filtered{area=search_area.inner_bounds, limit=result_limit, type="cliff"}
      local count_unique_entities = 0
      for _, e in pairs(entities) do
        local uid = e.unit_number or e.position
        if not global.found_entities[id][uid] and e.to_be_deconstructed() and e.prototype.cliff_explosive_prototype then
          global.found_entities[id][uid] = true
          add_signal(id,e.prototype.cliff_explosive_prototype, 1)
          count_unique_entities = count_unique_entities + 1
        end
        if MaxResults then
          result_limit = result_limit - count_unique_entities
          count_unique_entities = 0
        end
      end
    end
    -- upgrade requests (requires 0.17.69)
    if MaxResults == nil or result_limit > 0 then
      local entities = search_area.surface.find_entities_filtered{area=search_area.bounds, limit=result_limit, to_be_upgraded=true, force=search_area.force}
      local count_unique_entities = 0
      --log("found update requests: "..dump(entities))
      for _, e in pairs(entities) do
        local uid = e.unit_number
        local upgrade_prototype = e.get_upgrade_target()
        if not global.found_entities[id][uid] and upgrade_prototype then
          if is_in_bbox(e.position, search_area.bounds) then
            global.found_entities[id][uid] = true
            for _, item_stack in pairs(
              global.Lookup_items_to_place_this[upgrade_prototype.name] or
              get_items_to_place(upgrade_prototype)
            ) do
              add_signal(id,item_stack.name, item_stack.count)
              count_unique_entities = count_unique_entities + item_stack.count
            end
          end
        end
      end
      -- --log("found "..tostring(count_unique_entities).."/"..tostring(result_limit).." upgrade requests." )
      if MaxResults then
        result_limit = result_limit - count_unique_entities
      end
    end

    -- entity-ghost knows items_to_place_this and item_requests (modules)
    --log("limit: "..tostring(result_limit).." maxresults: "..tostring(MaxResults))
    if MaxResults == nil or result_limit > 0 then
      --log("data: bounds: "..dump(search_area.bounds).." force: "..tostring(search_area.forc))
      local entities = search_area.surface.find_entities_filtered{area=search_area.bounds, type="entity-ghost"} --, limit=result_limit, force=search_area.force
      local count_unique_entities = 0
      --log("found entity-ghosts "..dump(entities))
      for _, e in pairs(entities) do
        local uid = e.unit_number
        if not global.found_entities[id][uid] then
          if is_in_bbox(e.position, search_area.bounds) then
            global.found_entities[id][uid] = true
            for _, item_stack in pairs(
              global.Lookup_items_to_place_this[e.ghost_name] or
              get_items_to_place(e.ghost_prototype)
            ) do
              add_signal(id,item_stack.name, item_stack.count)
              count_unique_entities = count_unique_entities + item_stack.count
            end

            for request_item, count in pairs(e.item_requests) do
              add_signal(id,request_item, count)
              count_unique_entities = count_unique_entities + count
            end
          end
        end
      end
      -- --log("found "..tostring(count_unique_entities).."/"..tostring(result_limit).." ghosts." )
      if MaxResults then
        result_limit = result_limit - count_unique_entities
      end
    end

    --log("limit after entity ghosts: "..tostring(result_limit).." maxresults: "..tostring(MaxResults))
    -- item-request-proxy holds item_requests (modules) for built entities
    if MaxResults == nil or result_limit > 0 then
      local entities = search_area.surface.find_entities_filtered{area=search_area.inner_bounds, limit=result_limit, type="item-request-proxy", force=search_area.force}
      local count_unique_entities = 0
      --log("found item request proxy: "..dump(entities))
      for _, e in pairs(entities) do
        local uid = script.register_on_entity_destroyed(e) -- abuse on_entity_destroyed to generate ids directly for proxies
        if not global.found_entities[id][uid] then
          global.found_entities[id][uid] = true
          for request_item, count in pairs(e.item_requests) do
            add_signal(id,request_item, count)
            count_unique_entities = count_unique_entities + count
          end
        end
      end
        -- --log("found "..tostring(count_unique_entities).."/"..tostring(result_limit).." request proxies." )
      if MaxResults then
        result_limit = result_limit - count_unique_entities
      end
    end

    --log("limit after item requests: "..tostring(result_limit).." maxresults: "..tostring(MaxResults))
    -- tile-ghost knows only items_to_place_this
    if MaxResults == nil or result_limit > 0 then
      local entities = search_area.surface.find_entities_filtered{area=search_area.inner_bounds, limit=result_limit, type="tile-ghost", force=search_area.force}
      local count_unique_entities = 0
      --log("found tile ghosts: "..dump(entities))
      for _, e in pairs(entities) do
        local uid = e.unit_number
        if not global.found_entities[id][uid] then
          global.found_entities[id][uid] = true
          for _, item_stack in pairs(
            global.Lookup_items_to_place_this[e.ghost_name] or
            get_items_to_place(e.ghost_prototype)
          ) do
            add_signal(id,item_stack.name, item_stack.count)
            count_unique_entities = count_unique_entities + item_stack.count
          end
        end
      end
        -- --log("found "..tostring(count_unique_entities).."/"..tostring(result_limit).." tile-ghosts." )
      if MaxResults then
        result_limit = result_limit - count_unique_entities
      end
    end

    --log("limit after tile ghosts: "..tostring(result_limit).." maxresults: "..tostring(MaxResults))
    -- round signals to next stack size
    -- signal = { type = "item", name = name }, count = 0, index = (signal_index)
    if RoundToStack then
      local round = math.ceil
      if InvertSign then round = math.floor end

      for _, signal in pairs(signals) do
        local prototype = game.item_prototypes[signal.signal.name]
        if prototype then
          local stack_size = prototype.stack_size
          signal.count = round(signal.count / stack_size) * stack_size
        end
      end
    end

    
    --log("returning signals "..tostring(signals))
    return signals
  end

  
  function UpdateSensor(ghostScanner)
    if ghostScanner == nil then
      --log("ghost scanner entry is nil")
      RemoveSensor(ghostScanner.ID)
      return
    end

    --log("updateSensor ... "..tostring(ghostScanner.ID))

    -- handle invalidated sensors
    if not ghostScanner.entity.valid then
      RemoveSensor(ghostScanner.ID)
      --log("invalid scanner")
      return
    end

    -- skip scanner if disabled
    if not ghostScanner.entity.get_control_behavior().enabled then
      ghostScanner.entity.get_control_behavior().parameters = nil
      CleanUp(ghostScanner.ID)
      --log("scanner disabled")
      return
    end

    if global.ScanAreas[ghostScanner.ID] == nil then
      -- storing logistic network becomes problematic when roboports run out of energy
      local logisticNetwork = ghostScanner.entity.surface.find_logistic_network_by_position(ghostScanner.entity.position, ghostScanner.entity.force )
      if not logisticNetwork then
        ghostScanner.entity.get_control_behavior().parameters = nil
        CleanUp(ghostScanner.ID)
        --log("no logistic network found on ID "..tostring(ghostScanner.ID))
        return
      end

      --log("adding "..tostring(#logisticNetwork.cells).." cells from network to ScanArea "..tostring(ghostScanner.ID))
      -- resetting found data and adding areas to scan queue
      global.ScanSignals[ghostScanner.ID]=nil
      global.signal_indexes[ghostScanner.ID]=nil
      global.found_entities[ghostScanner.ID]=nil
      global.ScanAreas[ghostScanner.ID]={cells=tablecopy(logisticNetwork.cells),force=logisticNetwork.force}
      --log("adding cells to ScanAreas id "..tostring(ghostScanner.ID))
    end
  end
end


function tablecopy(t)
  local u = { }
  for k, v in pairs(t) do u[k] = v end
  return setmetatable(u, getmetatable(t))
end

-- INIT --
do
  local function init_mod()
    if #global.GhostScanners == 0 and not global.InitMod then
      global.GhostScanners = global.GhostScanners or {}
      for _,surface in pairs(game.surfaces) do
        local entities = surface.find_entities_filtered{name="ghost-scanner"}
        for _, entity in pairs(entities) do
          local ghostScanner = {}
          ghostScanner.ID = entity.unit_number
          ghostScanner.entity = entity
          global.GhostScanners[#global.GhostScanners+1] = ghostScanner
        end
      end
      log("initialized mod for the first time, scanned for old ghost scanners")
      global.InitMod = true
    end
  end
  local function init_events()
    script.on_event({
      defines.events.on_built_entity,
      defines.events.on_robot_built_entity,
      defines.events.script_raised_built,
      defines.events.script_raised_revive,
    }, OnEntityCreated)
    if global.GhostScanners then
      UpdateEventHandlers()
    end
  end

  script.on_load(function()
    init_events()
  end)

  script.on_init(function()
    global.InitMod = global.InitMod or false
    global.ScanSignals = {}
    global.UpdateTimeout = global.UpdateTimeout or false
    global.GhostScanners = global.GhostScanners or {}
    global.ScanAreas = {}
    global.UpdateIndex = global.UpdateIndex or 1
    global.signal_indexes = global.signal_indexes or {}
    global.found_entities = global.found_entities or {}
    --global.UpdateIndex2 = global.UpdateIndex2 or 1
    global.Lookup_items_to_place_this = {}
    init_mod()
    init_events()
  end)

  script.on_configuration_changed(function(data)
    global.InitMod = global.InitMod or false
    global.ScanSignals = global.ScanSignals or {}
    global.UpdateTimeout = global.UpdateTimeout or false
    global.GhostScanners = global.GhostScanners or {}
    global.ScanAreas = {}
    global.UpdateIndex = global.UpdateIndex or 1
    global.signal_indexes = global.signal_indexes or {}
    global.found_entities = global.found_entities or {}
    --global.UpdateIndex2 = global.UpdateIndex2 or 1
    global.Lookup_items_to_place_this = {}
    init_events()
  end)

end
