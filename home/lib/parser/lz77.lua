-----------------------------------------------------
--name       : lib/parser/lz77.lua
--description: LZ77 variant made to store compressed lua sources in long strings
--author     : mpmxyz
--github page: https://github.com/mpmxyz/ocprograms
--forum page : none
-----------------------------------------------------

--[[
  abaca
  window size = 3
  SA[0] = {0}
  SA[1] = {0,1}
  SA[2] = {0,1,2}
  SA[4] = {0,1,3,2}
  SA[5] = {0,3,2,4}
  LCP[0] = {nil}
  LCP[1] = {nil, 0}
  LCP[2] = {nil, 0, 0}
  LCP[3] = {nil, 0, 1, 0}
  LCP[4] = {nil, 0, 0, 0}
]]


local lz77 = {}




function lz77.compress(input, biggestReference, output, sleepBetweenCharacters)
  local function getByte(number)
    return number + (number >= 13 and 1 or 0) + (number >= 92 and 1 or 0)
  end
  local MAX_NUMBER = 253
  --go through character by character:
  -- find longest match
  -- if match is long enough to reduce size: create reference, add literal prefix if necessary
  -- else: add this character to the literal prefix
  local literalFrom = 1
  local inputBuffer = (type(input) == "string") and input:gsub("\r\n?","\n") or ""
  output = output or ""
  local i = 1
  
  local function tryload()
    if type(input) == "function" then
      while i - 2 + biggestReference > #inputBuffer do
        local nextChunk = input()
        if nextChunk and #nextChunk > 0 then
          nextChunk = nextChunk:gsub("\r\n?","\n")
          local firstNeededIndex = math.max(1, math.min(i - MAX_NUMBER, literalFrom))
          inputBuffer = inputBuffer:sub(firstNeededIndex, -1) .. nextChunk
          i           = i           - (firstNeededIndex - 1)
          literalFrom = literalFrom - (firstNeededIndex - 1)
        else
          input = nil
          break
        end
      end
    end
  end
  local function appendOutput(text)
    if type(output) == "function" then
      output(text)
    else
      output = output .. text
    end
  end
  local function appendLiterals(to)
    local literalLength =  to - literalFrom + 1
    --split if it is too long
    while literalLength > 0 do
      local partLength = math.min(literalLength, MAX_NUMBER - biggestReference + 2)
      appendOutput(string.char(getByte(biggestReference + partLength - 2)) .. inputBuffer:sub(literalFrom, literalFrom + partLength - 1))
      literalLength = literalLength - partLength
      literalFrom   = literalFrom   + partLength
    end
  end
  
  local amountDone = 0
  
  tryload()
  while i <= #inputBuffer do
    local byte = inputBuffer:byte(i)
    ----find longest match----
    local activeMatches = {}
    local longestFrom, longestLength = nil, 0
    local checkedMin = math.max(1, i - MAX_NUMBER)
    local checkedMax = math.min(#inputBuffer, i - 2 + biggestReference)
    for j = checkedMin, checkedMax do
      local checkedByte = inputBuffer:byte(j)
      if j < i then
        --starting new matching attempt
        activeMatches[#activeMatches + 1] = j
      elseif activeMatches[1] == nil then
        break
      end
      local k = 1
      while true do
        local startingIndex = activeMatches[k]
        if startingIndex == nil then
          break
        end
        --at j == startingIndex -> j <=> i
        local referenceByte = inputBuffer:byte(i + (j - startingIndex))
        if checkedByte == referenceByte then
          local length = (j - startingIndex + 1)
          if length > longestLength then
            longestLength = length
            longestFrom   = startingIndex
          end
          k = k + 1
        else
          activeMatches[k] = activeMatches[#activeMatches]
          activeMatches[#activeMatches] = nil
        end
      end
    end
    if longestLength > 2 or byte == 93 then
      if literalFrom < i then
        --add literals
        appendLiterals(i - 1)
      end
      if longestLength > 2 then
        --limitting longestLength to allowed maximum
        longestLength = math.min(longestLength, biggestReference)
        appendOutput(string.char(getByte(longestLength-2)) .. string.char(getByte(longestFrom - (i - 1) + MAX_NUMBER)))
        literalFrom = i + longestLength
      elseif byte == 93 then
        --byte == 93 / char == "]"
        appendOutput("\0")
        literalFrom = i + 1
      end
      i = literalFrom
    else
      i = i + 1
    end
    tryload()
    --force sleeping to avoid too long without yield errors
    amountDone = amountDone + 1
    if sleepBetweenCharacters and os.sleep then
      if amountDone % sleepBetweenCharacters == 0 then
        os.sleep(0.05)
      end
    end
  end
  --add missing literals
  appendLiterals(#inputBuffer)
  --return final value
  if type(output) == "string" then
    return output
  end
end

function lz77.uncompress(input, biggestReference)
  local function getNumber(byte)
    return byte - (byte > 13 and 1 or 0) - (byte > 93 and 1 or 0)
  end
  local MAX_NUMBER = 253
  
  local i, output = 1, ""
  while i <= #input do
    local length, offset = input:byte(i, i + 1)
    length = getNumber(length) + 2
    offset = getNumber(offset)
    if length > biggestReference then
      --long part for literals
      --watch out for length == 93  "]" might cause syntax errors in long strings
      --(handled in compression)
      length = length - biggestReference
      output = output .. input:sub(i + 1, i + length)
      i = i + length
    elseif length > 2 then
      --length == 1 and length == 2 do not exist
      local from = #output + (offset - MAX_NUMBER)
      while length > 0 do
        local part = output:sub(from, from + length - 1)
        output = output .. part
        from   = from   + #part
        length = length - #part
      end
      i = i + 1
    else
      --special code for closing bracket (avoids syntax errors in long strings)
      --will only be written during compression when necessary (->it can cause 1 byte overhead per occurence)
      output = output .. "]"
    end
    i = i + 1
  end
  return output
end


function lz77.getSXF(input, output, biggestReference)
  return (([[
local j,%output%,s,l,p,f=1,""while j<=#i do
l,s=%input%:byte(j,j+1)s=s or 0l=l+(l>13 and 1 or 2)-(l>93 and 1 or 0)s=s-(s>13 and 1 or 0)-(s>93 and 1 or 0)if l>%biggestReference%then
l=l-%biggestReference%%output%=%output%..%input%:sub(j+1,j+l)j=j+l
elseif l>2 then
f=#%output%+(s-253)while l>0 do
p=%output%:sub(f,f+l-1)%output%=%output%..p
f=f+#p
l=l-#p
end
j=j+1
else
%output%=%output%.."]"end
j=j+1
end]]):gsub("%%(%w+)%%",{input = input, output = output, biggestReference = biggestReference}))
end

return lz77
