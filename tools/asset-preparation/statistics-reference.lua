local jobs = require('jobs')

local function box(b)
  if not b then return nil end
  return {{b.left_top.x, b.left_top.y}, {b.right_bottom.x, b.right_bottom.y}, b.orientation or 0}
end

local function placements(p)
  local result = {}
  for _, item in pairs(p.items_to_place_this or {}) do
    result[#result + 1] = {name = item.name, count = item.count}
  end
  return result
end

-- Independent game-side rectangle calculation, using boxes measured from live entities/ghosts.
local function footprint(entities, tiles, prototypes_map)
  local min_x, min_y, max_x, max_y
  local function include(x1, y1, x2, y2)
    min_x = math.min(min_x or x1, x1); min_y = math.min(min_y or y1, y1)
    max_x = math.max(max_x or x2, x2); max_y = math.max(max_y or y2, y2)
  end
  local function include_box(b, position, off_grid, rotation, shape)
    if not b then return end
    local cx, cy = (b[1][1] + b[2][1]) / 2, (b[1][2] + b[2][2]) / 2
    local turn = (rotation or 0) * math.pi * 2
    local center_x = position.x + cx * math.cos(turn) - cy * math.sin(turn)
    local center_y = position.y + cx * math.sin(turn) + cy * math.cos(turn)
    local angle = ((b[3] or 0) + (rotation or 0)) * math.pi * 2
    local hx, hy = (b[2][1] - b[1][1]) / 2, (b[2][2] - b[1][2]) / 2
    local rx = math.abs(math.cos(angle)) * hx + math.abs(math.sin(angle)) * hy
    local ry = math.abs(math.sin(angle)) * hx + math.abs(math.cos(angle)) * hy
    local x1, y1, x2, y2 = center_x - rx, center_y - ry, center_x + rx, center_y + ry
    if not off_grid then
      local phase_x, phase_y = (shape.tileWidth % 2) / 2, (shape.tileHeight % 2) / 2
      x1 = math.floor(x1 - position.x + phase_x + 1e-9) - phase_x + position.x
      y1 = math.floor(y1 - position.y + phase_y + 1e-9) - phase_y + position.y
      x2 = math.ceil(x2 - position.x + phase_x - 1e-9) - phase_x + position.x
      y2 = math.ceil(y2 - position.y + phase_y - 1e-9) - phase_y + position.y
    end
    include(x1, y1, x2, y2)
  end
  for _, entity in pairs(entities) do
    local proto = prototypes_map[entity.name]
    if not proto then return {error = 'Unknown prototype ' .. entity.name} end
    local direction = tostring(entity.direction or 0)
    local shape = proto.directions[proto.offGrid and '0' or direction]
    if not shape then return {error = 'Unmeasured geometry ' .. entity.name .. ':' .. direction} end
    local rotation = proto.orientationAffectsCollision and (entity.orientation or (entity.direction or 0) / 16) or 0
    include_box(shape.collisionBox, entity.position, proto.offGrid, rotation, shape)
    include_box(shape.secondaryCollisionBox, entity.position, proto.offGrid, rotation, shape)
  end
  for _, tile in pairs(tiles) do include(tile.position.x, tile.position.y, tile.position.x + 1, tile.position.y + 1) end
  if not min_x then return {width = 0, height = 0} end
  return {width = max_x - min_x, height = max_y - min_y, minX = min_x, minY = min_y, maxX = max_x, maxY = max_y}
end

script.on_init(function()
  local report = {schema = 1, gameVersion = helpers.game_version, mods = {}, qualities = {}, entities = {}, tiles = {}, items = {}, cases = {}, geometryErrors = {}}
  for name, version in pairs(script.active_mods) do if name ~= 'fb-statistics-reference' then report.mods[name] = version end end
  for name in pairs(prototypes.quality) do report.qualities[name] = true end
  local surface = game.create_surface('statistics-reference', {width = 64, height = 64, generate_with_lab_tiles = true, autoplace_controls = {}})
  surface.request_to_generate_chunks({0, 0}, 1)
  surface.force_generate_chunk_requests()
  local platform = game.forces.player.create_space_platform{name = 'Statistics reference', planet = 'nauvis', starter_pack = 'space-platform-starter-pack'}
  local hub = platform.apply_starter_pack(true)
  for name, p in pairs(prototypes.item) do
    report.items[name] = {type = p.type, equipment = p.place_as_equipment_result and p.place_as_equipment_result.name or nil}
  end
  for name, p in pairs(prototypes.tile) do
    if p.items_to_place_this then report.tiles[name] = {placement = placements(p)} end
  end
  for name, p in pairs(prototypes.entity) do
    if p.items_to_place_this then
      local item = {type = p.type, placement = placements(p), tileWidth = p.tile_width, tileHeight = p.tile_height,
        collisionBox = box(p.collision_box), selectionBox = box(p.selection_box), offGrid = p.has_flag('placeable-off-grid'), notBlueprintable = p.has_flag('not-blueprintable'), supportsDirection = p.supports_direction, directions = {}}
      for direction = 0, 15 do
        local ok, created = pcall(function()
          if name == 'space-platform-hub' then return hub end
          return surface.create_entity{name = name, position = {0, 0}, direction = direction, orientation = direction / 16, force = 'player', create_build_effect_smoke = false}
        end)
        local geometry_source = 'entity'
        if not ok or not created then
          ok, created = pcall(function()
            return surface.create_entity{name = 'entity-ghost', inner_name = name, position = {0, 0}, direction = direction, orientation = direction / 16, force = 'player', expires = false}
          end)
          geometry_source = 'ghost'
        end
        if ok and created then
          local position = created.position
          local function relative(b)
            if not b then return nil end
            return {{b.left_top.x - position.x, b.left_top.y - position.y}, {b.right_bottom.x - position.x, b.right_bottom.y - position.y}, b.orientation or 0}
          end
          item.directions[tostring(direction)] = {direction = created.direction, orientation = created.orientation, source = geometry_source, tileWidth = created.tile_width, tileHeight = created.tile_height,
            collisionBox = relative(created.bounding_box), secondaryCollisionBox = relative(created.secondary_bounding_box), selectionBox = relative(created.selection_box)}
          if created ~= hub then created.destroy() end
        elseif direction % 4 == 0 then
          report.geometryErrors[#report.geometryErrors + 1] = {name = name, direction = direction, error = tostring(created)}
        end
      end
      item.orientationAffectsCollision = item.offGrid and item.directions['2'] and math.abs((item.directions['2'].collisionBox[3] or 0) - (item.directions['0'].collisionBox[3] or 0)) > 0.001 or false
      report.entities[name] = item
    end
  end
  for _, job in ipairs(jobs) do
    local inv = game.create_inventory(1)
    local stack = inv[1]
    local result = {id = job.id}
    local ok, err = pcall(function()
      result.importResult = stack.import_stack(job.blueprint)
      result.entities = stack.get_blueprint_entities() or {}
      result.tiles = stack.get_blueprint_tiles() or {}
      result.costToBuild = stack.cost_to_build
      result.footprint = footprint(result.entities, result.tiles, report.entities)
      result.sourceFootprint = footprint(job.data.entities or {}, job.data.tiles or {}, report.entities)
    end)
    if not ok then result.error = tostring(err) end
    report.cases[#report.cases + 1] = result
    inv.destroy()
  end
  helpers.write_file('statistics-reference.json', helpers.table_to_json(report))
  log('FB_STATISTICS_REFERENCE_READY')
end)
