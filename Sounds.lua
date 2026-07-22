local ADDON, ns = ...
local SG = ns

----------------------------------------------------------------------
-- Sounds: a master toggle + per-event toggles, played on the SFX channel so they respect the
-- player's own sound settings. Each event uses a built-in default until you assign your own:
--   /tim sound <id>              audition a SoundKit id
--   /tim sound file <id>         audition a FileDataID (voice lines are usually these)
--   /tim sound set <event> <id> [file]   assign what you just auditioned
-- Deliberately sparse - one cue per run start/stop and per sell, never per loot.
----------------------------------------------------------------------

local EVENTS = {
  { key = "runStart", label = "Run start" },
  { key = "runStop",  label = "Run stop"  },
  { key = "sell",     label = "Sell"      },
}
SG.SoundEvents = EVENTS

-- Built-in defaults -> id, isFile. The namesake: run start plays the goblin voice line
-- "Time is money, friend!" (a FileDataID, so it goes through PlaySoundFile). SoundKit lookups
-- are feature-detected, so a nil simply means "no sound" rather than an error.
local function DefaultSound(key)
  if key == "runStart" then return 550805, true end      -- goblin: "Time is money, friend!"
  if key == "runStop"  then return 550803, true end
  if key == "sell"     then return 550772, true end
  return nil, false
end

-- Settings live under settings.sounds; created/repaired on demand so no migration is needed.
local function Cfg()
  local s = TimeIsMoneyDB and TimeIsMoneyDB.settings
  if not s then return nil end
  s.sounds = s.sounds or {}
  local snd = s.sounds
  if snd.master == nil then snd.master = true end
  snd.events = snd.events or {}
  for _, e in ipairs(EVENTS) do
    local ev = snd.events[e.key]
    if not ev then ev = {}; snd.events[e.key] = ev end
    if ev.on == nil then ev.on = true end
  end
  return snd
end
SG.SoundCfg = Cfg

-- Play the cue for an event, honoring the master + per-event toggles.
function SG.PlayEventSound(key)
  local snd = Cfg(); if not snd or not snd.master then return end
  local ev = snd.events[key]; if not ev or ev.on == false then return end
  if ev.id and ev.id > 0 then
    if ev.file then pcall(PlaySoundFile, ev.id, "SFX") else pcall(PlaySound, ev.id, "SFX") end
    return
  end
  local id, isFile = DefaultSound(key)
  if id then
    if isFile then pcall(PlaySoundFile, id, "SFX") else pcall(PlaySound, id, "SFX") end
  end
end

local function EventLabel(key)
  for _, e in ipairs(EVENTS) do if e.key == key then return e.label end end
  return key
end

local function Status()
  local snd = Cfg(); if not snd then return end
  SG.Print(("Sounds: %s"):format(snd.master and "|cff8fd694on|r" or "|cff808080off|r"))
  for _, e in ipairs(EVENTS) do
    local ev = snd.events[e.key]
    local what = (ev.id and ev.id > 0) and ((ev.file and "file " or "kit ") .. ev.id) or "built-in default"
    SG.Print(("  %s: %s  (%s)"):format(e.label, ev.on and "on" or "|cff808080off|r", what))
  end
end

-- Audition a RANGE of FileDataIDs, one every couple of seconds, printing each id as it plays.
-- Voice lines for one NPC sit in a contiguous block, so this is how you find a specific line.
local scanTimer, scanStop = nil, false
local SCAN_CAP = 40
local function ScanRange(from, to)
  to = math.min(to, from + SCAN_CAP - 1)
  scanStop = false
  local id = from
  local function step()
    if scanStop then SG.Print("Sound scan stopped."); return end
    if id > to then SG.Print("Sound scan finished."); return end
    SG.Print(("  playing |cffffd200%d|r  |cff808080(/tim sound stop to halt · /tim sound set runstart %d file to keep)|r"):format(id, id))
    pcall(PlaySoundFile, id, "SFX")
    id = id + 1
    scanTimer = C_Timer.NewTimer(2.0, step)
  end
  SG.Print(("Scanning sounds |cffffd200%d|r to |cffffd200%d|r, one every 2s..."):format(from, to))
  step()
end

-- /tim sound ...
function SG.SoundCommand(arg)
  local snd = Cfg(); if not snd then return end
  arg = (arg or ""):lower()
  local a1, a2, a3 = arg:match("^(%S*)%s*(%S*)%s*(%S*)$")

  if a1 == "" then
    SG.Print("|cff8fd694Sounds|r  /tim sound <id> (audition kit) · file <id> (audition file) · set <event> <id> [file] · on|off · <event> on|off")
    SG.Print("  events: runstart, runstop, sell   |cff808080(hunt an id, then assign it - e.g. /tim sound set runstart 12345 file)|r")
    Status()
    return
  end

  if a1 == "scan" then                    -- /tim sound scan <from> [to]
    local from, to = tonumber(a2), tonumber(a3)
    if not from then SG.Print("Usage: /tim sound scan <fromID> [toID]   (max 40 at a time)"); return end
    ScanRange(from, to or (from + 19))
    return
  end
  if a1 == "stop" then
    scanStop = true
    if scanTimer then scanTimer:Cancel(); scanTimer = nil end
    SG.Print("Sound scan stopped.")
    return
  end

  if a1 == "on" or a1 == "off" then
    snd.master = (a1 == "on")
    SG.Print("Sounds " .. (snd.master and "|cff8fd694on|r" or "|cff808080off|r"))
    if SG.RefreshConfig then SG.RefreshConfig() end
    return
  end

  -- audition a FileDataID:  /tim sound file <id>
  if a1 == "file" then
    local id = tonumber(a2)
    if not id then SG.Print("Usage: /tim sound file <FileDataID>"); return end
    local ok = pcall(PlaySoundFile, id, "SFX")
    SG.Print(("Auditioned file |cffffd200%d|r%s"):format(id, ok and "" or " |cffff7070(failed)|r"))
    return
  end

  -- assign:  /tim sound set <event> <id> [file]
  if a1 == "set" then
    local key = (a2 == "runstart" and "runStart") or (a2 == "runstop" and "runStop") or (a2 == "sell" and "sell")
    local id  = tonumber(a3)
    if not key or not id then SG.Print("Usage: /tim sound set <runstart|runstop|sell> <id> [file]"); return end
    local isFile = arg:find("file%s*$") ~= nil
    snd.events[key].id, snd.events[key].file = id, isFile or false
    SG.Print(("%s sound = %s |cffffd200%d|r"):format(EventLabel(key), isFile and "file" or "kit", id))
    SG.PlayEventSound(key)
    return
  end

  -- per-event toggle:  /tim sound runstart off
  local key = (a1 == "runstart" and "runStart") or (a1 == "runstop" and "runStop") or (a1 == "sell" and "sell")
  if key and (a2 == "on" or a2 == "off") then
    snd.events[key].on = (a2 == "on")
    SG.Print(("%s sound %s"):format(EventLabel(key), a2 == "on" and "|cff8fd694on|r" or "|cff808080off|r"))
    if SG.RefreshConfig then SG.RefreshConfig() end
    return
  end
  if key and a2 == "" then                       -- /tim sound sell  -> just play it
    SG.PlayEventSound(key); return
  end

  -- audition a SoundKit id:  /tim sound <id>
  local id = tonumber(a1)
  if id then
    local ok = pcall(PlaySound, id, "SFX")
    SG.Print(("Auditioned kit |cffffd200%d|r%s  |cff808080(assign: /tim sound set <event> %d)|r"):format(id, ok and "" or " |cffff7070(failed)|r", id))
    return
  end

  SG.Print("Usage: /tim sound <id> | file <id> | set <event> <id> [file] | on | off | <event> on|off")
end
