require "/scripts/util.lua"
require "/scripts/vec2.lua"
require "/scripts/versioningutils.lua"
require "/scripts/staticrandom.lua"
require "/scripts/mt/options.lua"
require "/items/buildscripts/abilities.lua"
require "/items/buildscripts/appearance.lua"
require "/items/buildscripts/manufacturers.lua"

function build(directory, config, parameters, level, seed)
  local configParameter = function(keyName, defaultValue)
    if parameters[keyName] ~= nil then
      return parameters[keyName]
    elseif config[keyName] ~= nil then
      return config[keyName]
    else
      return defaultValue
    end
  end

  if level and not configParameter("fixedLevel", false) then
    parameters.level = level
  end

  -- initialize randomization
  if seed then
    parameters.seed = seed
  else
    seed = configParameter("seed")
    if not seed then
      math.randomseed(util.seedTime())
      seed = math.random(1, 4294967295)
      parameters.seed = seed
    end
  end

  -- select the generation profile to use
  local builderConfig = {}
  if config.builderConfig then
    builderConfig = randomFromList(config.builderConfig, seed, "builderConfig")
  end

  -- select, load and merge abilities
  setupAbility(config, parameters, "alt", builderConfig, seed)
  setupAbility(config, parameters, "primary", builderConfig, seed)

  -- name
  if not parameters.shortdescription and builderConfig.nameGenerator then
    parameters.shortdescription = root.generateName(util.absolutePath(directory, builderConfig.nameGenerator), seed)
  else
    parameters.hasPrefix = true --so that we won't try to change the name later
  end

  -- set price
  config.price = (config.price or 0) * root.evalFunction("itemLevelPriceMultiplier", configParameter("level", 1))
  
  -- merge damage properties
  if builderConfig.damageConfig then
    util.mergeTable(config.damageConfig or {}, builderConfig.damageConfig)
  end

  -- preprocess shared primary attack config
  parameters.primaryAbility = parameters.primaryAbility or {}
  parameters.primaryAbility.fireTimeFactor = valueOrRandom(parameters.primaryAbility.fireTimeFactor, seed, "fireTimeFactor")
  parameters.primaryAbility.baseDpsFactor = valueOrRandom(parameters.primaryAbility.baseDpsFactor, seed, "baseDpsFactor")
  parameters.primaryAbility.energyUsageFactor = valueOrRandom(parameters.primaryAbility.energyUsageFactor, seed, "energyUsageFactor")

  config.primaryAbility.fireTime = scaleConfig(parameters.primaryAbility.fireTimeFactor, config.primaryAbility.fireTime)
  config.primaryAbility.baseDps = scaleConfig(parameters.primaryAbility.baseDpsFactor, config.primaryAbility.baseDps)
  config.primaryAbility.energyUsage = scaleConfig(parameters.primaryAbility.energyUsageFactor, config.primaryAbility.energyUsage) or 0
  
  -- preprocess melee primary attack config
  if config.primaryAbility.damageConfig and config.primaryAbility.damageConfig.knockbackRange then
    config.primaryAbility.damageConfig.knockback = scaleConfig(parameters.primaryAbility.fireTimeFactor, config.primaryAbility.damageConfig.knockbackRange)
  end
  
  local weaponType = "all"
  
  if config.manufacturerConfigType then --sets what type of modifications to use from a manufacturer, rather than determining through tags
    weaponType = config.manufacturerConfigType
  elseif config.itemTags then
    for k, v in ipairs(config.itemTags) do
	  if v == "ranged" then
	    weaponType = "ranged"
		break
      elseif v == "melee" then
	    weaponType = "melee"
		break
	  elseif v == "wand" or v == "staff" then
	    weaponType = "magic"
		break
	  end
	end
  end
  
  -- preprocess ranged primary attack config
  if config.primaryAbility.projectileParameters then
    config.primaryAbility.projectileType = randomFromList(config.primaryAbility.projectileType, seed, "projectileType")
    config.primaryAbility.projectileCount = randomIntInRange(config.primaryAbility.projectileCount, seed, "projectileCount") or 1
    config.primaryAbility.fireType = randomFromList(config.primaryAbility.fireType, seed, "fireType") or "auto"
    config.primaryAbility.burstCount = randomIntInRange(config.primaryAbility.burstCount, seed, "burstCount")
    config.primaryAbility.burstTime = randomInRange(config.primaryAbility.burstTime, seed, "burstTime")
    if config.primaryAbility.projectileParameters.knockbackRange then
      config.primaryAbility.projectileParameters.knockback = scaleConfig(parameters.primaryAbility.fireTimeFactor, config.primaryAbility.projectileParameters.knockbackRange)
    end
  end

  -- calculate damage level multiplier
  config.damageLevelMultiplier = root.evalFunction("weaponDamageLevelMultiplier", configParameter("level", 1))

  -- build palette swap directives
  config.paletteSwaps = ""
  if builderConfig.palette then
    --code to ensure compatibility with Weapon Assembly by AlbertoRota
    local selectedSwaps = {}
    if parameters.WA_customPalettes then
      local layers = root.assetJson(util.absolutePath(directory,"/items/active/weapons/colors/WA_layers.weaponcolors"))
      local weaponPalette = string.match(builderConfig.palette, "/([^/]+)%.weaponcolors")
      for layer, targetColors in pairs(parameters.WA_customPalettes) do
        local sourceColors = layers[weaponPalette .. layer]
        for i in ipairs(sourceColors) do selectedSwaps[ sourceColors[i] ] = targetColors[i] end
      end
    else
      local palette = root.assetJson(util.absolutePath(directory, builderConfig.palette))
      selectedSwaps = randomFromList(palette.swaps, seed, "paletteSwaps")
    end
    for k, v in pairs(selectedSwaps) do
      config.paletteSwaps = string.format("%s?replace=%s=%s", config.paletteSwaps, k, v)
    end
  end
  
  -- elemental type
  local elementalTypeList = { "physical" }
  local noElementalTypeUnlessForced = builderConfig.noElementalTypeUnlessForced or false
  if not parameters.elementalType and builderConfig.elementalType then
    elementalTypeList = builderConfig.elementalType
	if noElementalTypeUnlessForced then
	  parameters.elementalType = "physical"
	else
      parameters.elementalType = randomFromList(elementalTypeList, seed, "elementalType")
	end
  end
  local elementalType = configParameter("elementalType", "physical")
  config.elementalType = elementalType
  
  -- manufacturer
  if not parameters.manufacturer and builderConfig.manufacturer then
    parameters.manufacturer = randomFromList(builderConfig.manufacturer, seed, "manufacturer")
  end
  local manufacturer = configParameter("manufacturer", "none")
  local projectileReplacements
  
  manufacturerName, projectileReplacements = setupManufacturer(config, parameters, builderConfig, seed, weaponType, noPrefix, elementalTypeList)
  
  elementalType = config.elementalType
  
  -- elemental config
  if builderConfig.elementalConfig and (elementalType ~= "physical" or builderConfig.treatPhysicalAsElementalType) and (not noElementalTypeUnlessForced or builderConfig.treatPhysicalAsElementalType) then
    util.mergeTable(config, builderConfig.elementalConfig[elementalType])
  end
  if config.altAbility and config.altAbility.elementalConfig and (elementalType ~= "physical" or builderConfig.treatPhysicalAsElementalType) and (not noElementalTypeUnlessForced or builderConfig.treatPhysicalAsElementalType) then
    util.mergeTable(config.altAbility, config.altAbility.elementalConfig[elementalType])
  end

  -- elemental tag
  replacePatternInData(config, nil, "<elementalType>", elementalType)
  replacePatternInData(config, nil, "<elementalName>", elementalType:gsub("^%l", string.upper))

  -- elemental fire sounds
  if config.fireSounds then
    construct(config, "animationCustom", "sounds", "fire")
    local sound = randomFromList(config.fireSounds, seed, "fireSound")
    config.animationCustom.sounds.fire = type(sound) == "table" and sound or { sound }
  end
  
  --resets the projectile type, if it has been given a new one from its element
  --otherwise, it might have a table for its projectile, which will give it a weird, randomized shot type
  if config.primaryAbility.projectileParameters then
    config.primaryAbility.projectileType = randomFromList(config.primaryAbility.projectileType, seed, "projectileType")
  end
  
  -- replaces projectile type if the manufacturer wants a different one
  if config.primaryAbility.projectileType and projectileReplacements then
    for k, v in ipairs(projectileReplacements) do
	  if v.projectile and v.replacement and config.primaryAbility.projectileType == v.projectile then
	    config.primaryAbility.projectileType = v.replacement
	  end
	end
  end
  
  -- merge extra animationCustom
  if builderConfig.animationCustom then
    util.mergeTable(config.animationCustom or {}, builderConfig.animationCustom)
  end

  -- animation parts
  if builderConfig.animationParts then
    config.animationParts = config.animationParts or {}
    if parameters.animationPartVariants == nil then parameters.animationPartVariants = {} end
    for k, v in pairs(builderConfig.animationParts) do
      if type(v) == "table" then
        if v.variants and (not parameters.animationPartVariants[k] or parameters.animationPartVariants[k] > v.variants) then
          parameters.animationPartVariants[k] = randomIntInRange({1, v.variants}, seed, "animationPart"..k)
        end
        config.animationParts[k] = util.absolutePath(directory, string.gsub(v.path, "<variant>", parameters.animationPartVariants[k] or ""))
        if v.paletteSwap then
          config.animationParts[k] = config.animationParts[k] .. config.paletteSwaps
        end
      else
        config.animationParts[k] = v
      end
    end
  end

  -- set gun part offsets
  local partImagePositions = {}
  if builderConfig.gunParts then
    construct(config, "animationCustom", "animatedParts", "parts")
    local imageOffset = {0,0}
    local gunPartOffset = {0,0}
    for _,part in ipairs(builderConfig.gunParts) do
      local imageSize = root.imageSize(config.animationParts[part])
      construct(config.animationCustom.animatedParts.parts, part, "properties")

      imageOffset = vec2.add(imageOffset, {imageSize[1] / 2, 0})
      config.animationCustom.animatedParts.parts[part].properties.offset = {config.baseOffset[1] + imageOffset[1] / 8, config.baseOffset[2]}
      partImagePositions[part] = copy(imageOffset)
      imageOffset = vec2.add(imageOffset, {imageSize[1] / 2, 0})
    end
    config.muzzleOffset = vec2.add(config.baseOffset, vec2.add(config.muzzleOffset or {0,0}, vec2.div(imageOffset, 8)))
  end  

  -- build inventory icon
  if not config.inventoryIcon and config.animationParts then
    config.inventoryIcon = jarray()
    local parts = builderConfig.iconDrawables or {}
    for _,partName in pairs(parts) do
      local drawable = {
        image = config.animationParts[partName] .. config.paletteSwaps,
        position = partImagePositions[partName]
      }
      table.insert(config.inventoryIcon, drawable)
    end
  end
  
  --add color to weapon name
  
  if not parameters.hasColoredName and parameters.shortdescription then
    local colorWeaponNamesFor = options.getOption("colorWeaponNamesFor")
    if colorWeaponNamesFor then
	  local sdesc = parameters.shortdescription or config.shortdescription or ""
	  if colorWeaponNamesFor == "rarity" then
	    parameters.shortdescription = color.getColorByRarity(config.rarity) .. sdesc
      elseif colorWeaponNamesFor == "levelFull" then
	    parameters.shortdescription = color.getColorByLevel(math.floor(parameters.level or 1)) .. sdesc
	  end
      parameters.hasColoredName = true
	end
  end
  
  -- populate tooltip fields
  config.tooltipFields = {}
  local fireTime = parameters.primaryAbility.fireTime or config.primaryAbility.fireTime or 1.0
  local baseDps = parameters.primaryAbility.baseDps or config.primaryAbility.baseDps or 0
  local energyUsage = parameters.primaryAbility.energyUsage or config.primaryAbility.energyUsage or 0
  
  if options.getOption("showWeaponLevel") then
      config.tooltipFields.levelLabel = util.round(configParameter("level", 1), 1)
  else
	  config.tooltipFields.levelLabel = ""
  end

  config.tooltipFields.energyPerShotLabel = config.primaryAbility.energyPerShot or 0
  local bestDrawTime = (config.primaryAbility.powerProjectileTime[1] + config.primaryAbility.powerProjectileTime[2]) / 2
  local bestDrawMultiplier = root.evalFunction(config.primaryAbility.drawPowerMultiplier, bestDrawTime)
  config.tooltipFields.maxDamageLabel = util.round(config.primaryAbility.projectileParameters.power * config.damageLevelMultiplier * bestDrawMultiplier, 1)
  
  --For compatibility with FU
  if options.isFrackinUniverseLoaded() then
    config.tooltipFields.critChanceTitleLabel = "^orange;Crit %^reset;"
    config.tooltipFields.critBonusTitleLabel = "^yellow;Dmg +^reset;"
    config.tooltipFields.critChanceLabel = (configParameter("critChance", 0) + configParameter("level", 1))
    config.tooltipFields.critBonusLabel = (configParameter("critBonus", 0) + configParameter("level", 1))
  end
  --End of FU tooltips
  
  config.tooltipFields.dpsLabel = util.round(baseDps * config.damageLevelMultiplier, 1)
  config.tooltipFields.speedLabel = util.round(1 / fireTime, 1)
  config.tooltipFields.damagePerShotLabel = util.round(baseDps * fireTime * config.damageLevelMultiplier, 1)
  config.tooltipFields.energyPerShotLabel = util.round(energyUsage * fireTime, 1)
  
  config.tooltipFields.manufacturerNameLabel = manufacturerName
  config.tooltipFields.energyPerSecondLabel = util.round(energyUsage, 1)
  if energyUsage and energyUsage > 0 and baseDps then
    config.tooltipFields.damagePerEnergyLabel = util.round((baseDps * config.damageLevelMultiplier) / energyUsage, 2)
  else
    config.tooltipFields.damagePerEnergyLabel = "---"
  end
  
  if elementalType ~= "physical" then
    config.tooltipFields.damageKindImage = "/interface/elements/"..elementalType..".png"
  end
  if config.primaryAbility then
    config.tooltipFields.primaryAbilityTitleLabel = "Primary:"
    config.tooltipFields.primaryAbilityLabel = config.primaryAbility.name or "unknown"
  end
  if config.altAbility then
    config.tooltipFields.altAbilityTitleLabel = "Special:"
    config.tooltipFields.altAbilityLabel = config.altAbility.name or "unknown"
  end
  
  return config, parameters
end

function scaleConfig(ratio, value)
  if type(value) == "table" then
    return util.lerp(ratio, value[1], value[2])
  else
    return value
  end
end
