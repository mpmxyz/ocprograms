-----------------------------------------------------
--name       : lib/crunch/15_variable_compression.lua
--description: crunch module, converts variables and values to variables with shorter names
--author     : mpmxyz
--github page: https://github.com/mpmxyz/ocprograms
--forum page : none
-----------------------------------------------------
return {
  run = function(context, options)
    --This code only works if you know how the code is structured.
    if options.tree then
      context.verbose("Compressing variables...")
      
      local editableList = {}
      do
        --fill list
        local n = 0
        for k, token in pairs(context.variableRegistry) do
          n = n + 1
          editableList[n] = token
        end
        for k, token in pairs(context.valueRegistry) do
          n = n + 1
          editableList[n] = token
        end
      end
      local function sortingComparator(a, b)
        if a.nused == b.nused then
          --prioritize optimization of local variables (compared to global variables and values)
          -->removes overhead due to declarations at the beginning of the file
          return (a.isLocal and not b.isLocal)
        end
        --more uses first
        return a.nused > b.nused
      end
      local function sortList()
        table.sort(editableList, sortingComparator)
      end
      
      local blacklisted_globals = {}
      local function tryCompression()
        local ranking    = 1
        local nameIndex  = 1
        local usedNames  = {}
        local dictionary = {}
        local needsRestart = false
        local totalLocalizationGain = -5 --local
        while true do
          --get next token
          local token = editableList[ranking]
          if token == nil then
            break
          end
          --find a new valid name
          local newName
          repeat
            newName = context.numberToName(nameIndex)
            nameIndex = nameIndex + 1
            --skip invalid names
          until not context.blacklisted_names[newName] and not blacklisted_globals[newName]
          usedNames[newName] = true
          ---calculating gain and loss of replacement
          --but that is not necessary for local variables
          local useReplacement = true
          if not token.isLocal then
            --The original size is important as a reference...
            local newSize = #newName
            local originalSize = 0
            for i, part in ipairs(token) do
              originalSize = originalSize + #part
            end
            local gainPerUsage = originalSize - newSize
            --,newName=oldValue
            local overhead = 1 + newSize + 1 + originalSize
            if token.replacementModifierClones then
              for modifier, clone in pairs(token.replacementModifierClones) do
                if gainPerUsage <= modifier then
                  --not enough gain; remove clones with this modifier
                  clone:unlock()
                else
                  --add overhead
                  overhead = overhead + modifier * clone.nused
                end
              end
              --check if list is still sorted correctly
              local nextToken = editableList[ranking + 1]
              if nextToken then
                if sortingComparator(nextToken, token) then
                  --sorting required
                  sortList()
                  return true
                end
              end
            end
            local gain = gainPerUsage * token.nused - overhead
            if gain <= 0 then
              useReplacement = false
              ---replacement does not help; it's better to leave everything untouched
              --remove object from the list of modifiable objects
              table.remove(editableList, ranking)
              --revert all effects to the next objects
              ranking = ranking - 1
              nameIndex = nameIndex - 1
              usedNames[newName] = false
              --avoid naming something like this global variable
              if type(token.id) == "string" then
                blacklisted_globals[token.id] = true
                if usedNames[token.id] then
                  --name is already used somewhere else: start again
                  return true
                end
              end
              --else: just continue; this event doesn't affect other parts of the program.
            else
              totalLocalizationGain = totalLocalizationGain + gain
            end
          end
          if useReplacement then
            --all good; saving newName for later usage
            dictionary[token] = newName
          end
          --repeat...
          ranking = ranking + 1
        end
        --check if the global/value -> local optimization helped
        local header = {}
        if totalLocalizationGain <= 0 then
          --nope: remove non local values from the list
          local iInput, iOutput = 1, 1
          while true do
            local input = editableList[iInput]
            if input == nil then
              --removed some entries? -> force restart to rename local variables
              if (iInput ~= iOutput) then
                return true
              end
              break
            end
            editableList[iInput] = nil
            if input.isLocal then
              --keep locals
              editableList[iOutput] = input
              iOutput = iOutput + 1
            end
            iInput = iInput + 1
          end
        else
          --add localization header
          table.insert(header, "local ")
        end
        --do translation
        local headerNames  = {}
        local headerValues = {}
        for _, token in ipairs(editableList) do
          local newName = dictionary[token]
          if not token.isLocal then
            table.insert(headerNames, newName)
            table.insert(headerValues, table.concat(token))
          end
          if token.id then
            --It already is a variable; just replace the name.
            token[1] = newName
          else
            --It is a value; replace it by a variable
            token.typ = "var"
            token[1] = {
              typ = "name",
              newName,
            }
            for i = 2, #token do
              token[i] = nil
            end
          end
        end
        for i, name in ipairs(headerNames) do
          if i > 1 then
            table.insert(header, ",")
          end
          table.insert(header, name)
        end
        if totalLocalizationGain > 0 then
          table.insert(header, "=")
        end
        for i, value in ipairs(headerValues) do
          if i > 1 then
            table.insert(header, ",")
          end
          table.insert(header, value)
        end
        context.header = header
      end
      
      sortList()
      while tryCompression() do
        --
      end
      
      --  TODO: local limit
    end
  end,
}
