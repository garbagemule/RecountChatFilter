-------------------------------------------------------------------------------
--
--  Utility functions
--
-------------------------------------------------------------------------------

local function startsWith(text, prefix)
  return text:sub(1, #prefix) == prefix
end

local function last(list)
  -- Stop when there is no next link
  if not list.next then
    return list
  end
  -- Otherwise, keep recursing
  return last(list.next)
end

local function append(list, value)
  -- Create a new link
  local link = { next = nil, value = value }

  -- Empty list, just return the link
  if not list then
    return link
  end
  -- Otherwise, append to the list and return the list
  last(list).next = link
  return list
end

local function length(list)
  -- Stop when we reach the end
  if not list then
    return 0
  end
  -- Otherwise, +1 and keep recursing
  return 1 + length(list.next)
end

-------------------------------------------------------------------------------
--
--  Local variables
--
-------------------------------------------------------------------------------

-- Mapping of sender -> current tracker object.
-- Tracker objects contain the following information:
--     id      - tracker ID
--     timeout - when this tracking object is terminated
--     addon   - name of addon (Skada or Recount)
--     sender  - player name
--     first   - the first message (or "report headline")
--     lines   - linked list of the data lines
local trackers = {}

-- Mapping of tracker ID -> tracking objects.
-- The tracker ID comes from the tracking objects themselves. This ID is
-- contained in the chat link messages for easy lookup.
local reports = {}

-- Counter for the next tracker ID.
local nextTrackerId = 1

-- Total elapsed time, used by the timeout handler.
local elapsed = 0

-------------------------------------------------------------------------------
--
--  Chat filtering and tracker/report functions
--
-------------------------------------------------------------------------------

--
-- The timeout handler is responsible for moving the tracker objects from the
-- trackers map into the reports map. The reason this is important is that we
-- want to separate "finished" reports from "accumulating" reports, such that
-- the heavy-lifting can be moved from the chat handler to the click handler,
-- which is activated much less frequently.
--
local function timeoutHandler(self, delta)
  elapsed = elapsed + delta
  for sender, tracker in pairs(trackers) do
    if elapsed >= tracker.timeout then
      -- Move the tracker to the reports map
      reports[tracker.id] = tracker
      trackers[sender] = nil
    end
  end
end
local timeoutFrame = CreateFrame("Frame", "RecountChatFilter Timeout Frame")
timeoutFrame:SetScript("OnUpdate", timeoutHandler)

--
-- Create a new tracker object with the given information, store it in the
-- trackers map, and return it.
--
local function createTrackerObject(sender, message, addon)
  -- Create the object
  local tracker = {
    id = nextTrackerId,
    timeout = elapsed + 1,
    addon = addon,
    sender = sender,
    first = message,
    lines = nil
  }

  -- Store it in the trackers map
  trackers[sender] = tracker

  -- Remember to increment the next tracker ID
  nextTrackerId = nextTrackerId + 1
  return tracker
end

--
-- Create a special chat link for the given tracker.
--
-- Chat links take the form of |H<type>:<data>|h<text>|h, where <type> is the
-- linkstring, or the type of link, <data> is any auxiliary information that
-- may exist in the string, and <text> is what will be displayed in the chat
-- frame.
--
-- Our special chat link's <type> is recountlink, and the <data> part consists
-- of the sender and tracker ID, separated by a colon. Finally, the <text> is
-- the first message in the tracker, i.e. the "headline".
--
-- Note that the pipes (|) must be escaped, hence \124.
--
local function createChatLink(tracker)
  local tmp = "|Hrecountlink:%s:%u|h[%s]|h"
  local template = "\124Hrecountlink:%s:%u\124h[%s]\124h"

  local sender = tracker.sender
  local id     = tracker.id
  local text   = tracker.first

  return string.format(template, sender, id, text)
end

--
-- Get the addon name from a given message, or nil. We're only interested
-- in Skada and Recount at this time.
--
local function getAddon(message)
  return string.match(message, "^(Recount) - .*$") or
         string.match(message, "^(Skada): .*$")
end

--
-- Message processor for the first "headline" message.
--
local function processFirstMessage(sender, message)
  -- Grab the addon part of the message, if any
  local addon = getAddon(message)

  -- If so, create a new tracker object and return a chat link
  if addon then
    local tracker = createTrackerObject(sender, message, addon)
    return createChatLink(tracker)
  end
  -- Otherwise, do nothing
  return message
end

--
-- Message processor for data lines following the first message.
--
local function processNextMessage(sender, message)
  -- Grab the tracker
  local tracker = trackers[sender]

  -- We expect the next line to be the next numbered message
  local expected = length(tracker.lines) + 1
  local match = string.match(message, "%s*(" .. expected .. "%.%s+%a+%s+.*)")

  -- If not, just ignore and wait for the timeout to stop tracking the sender
  if not match then
    return false, message
  end
  -- Otherwise, append the message to the lines list and filter out
  tracker.lines = append(tracker.lines, message)
  return true, message
end

--
-- The chat filter for processing messages.
--
local function filter(frame, event, message, sender, ...)
  -- If we aren't tracking this sender, process this as the first message
  if not trackers[sender] then
    return false, processFirstMessage(sender, message), sender, ...
  end
  -- Otherwise, process it as the next message
  return processNextMessage(sender, message), message, sender, ...
end

-- Party/guild/raid
ChatFrame_AddMessageEventFilter("CHAT_MSG_PARTY",        filter)
ChatFrame_AddMessageEventFilter("CHAT_MSG_PARTY_LEADER", filter)
ChatFrame_AddMessageEventFilter("CHAT_MSG_GUILD",        filter)
ChatFrame_AddMessageEventFilter("CHAT_MSG_OFFICER",      filter)
ChatFrame_AddMessageEventFilter("CHAT_MSG_RAID",         filter)
ChatFrame_AddMessageEventFilter("CHAT_MSG_RAID_LEADER",  filter)
ChatFrame_AddMessageEventFilter("CHAT_MSG_RAID_WARNING", filter)

-- Local channels
ChatFrame_AddMessageEventFilter("CHAT_MSG_SAY",          filter)
ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER",      filter)
ChatFrame_AddMessageEventFilter("CHAT_MSG_YELL",         filter)

-------------------------------------------------------------------------------
--
--  Chat links
--
-------------------------------------------------------------------------------

--
-- Add the headline and the data lines from the report to the tooltip.
--
local function populateTooltip(tooltip, report)
  -- Add the headline, and a bit of padding
  tooltip:AddLine(report.first, 1, 1, 1, true)
  tooltip:AddLine(" ")

  -- Process each individual line, and switch colors
  local color = true
  local line = report.lines
  while line do
    -- Split it before the first digit, into left and right
    local left = string.match(line.value, "(%s*[1-9][0-9]?%.%s+[^%d]+).*")
    local right = string.sub(line.value, #left)

    -- Add the line
    if color then
      tooltip:AddDoubleLine(left, right)
    else
      tooltip:AddDoubleLine(left, right, 1, 1, 1, 1, 1, 1)
    end

    -- Swap color, advance to next line
    color = not color
    line = line.next
  end
end

--
-- Extract information from the chat link to look up the corresponding report
-- from the trackers/reports map.
--
local function reportFromLink(link)
  -- Try to grab it from the tracker ID first
  local id = link:match("recountlink:%a+:(%d+).*")
  local report = reports[tonumber(id)]
  if report then
    return report
  end
  -- Otherwise, grab it from the sender name
  local sender = link:match("recountlink:(%a+):.*")
  return trackers[sender]
end

-- Create a local reference to the SetHyperLink function
local SetHyperlink = ItemRefTooltip.SetHyperlink

-- Then override it to intercept our Recount links
function ItemRefTooltip:SetHyperlink(link)
  -- If the link doesn't start with "recountlink", pass it on
  if not startsWith(link, "recountlink") then
    SetHyperlink(self, link)
    return
  end

  -- Grab the report
  local report = reportFromLink(link)

  -- Clear the tooltip, then populate it and show it
  local tooltip = RecountChatFilterTooltip
  tooltip:Hide()
  tooltip:SetOwner(WorldFrame, "ANCHOR_PRESERVE")
  populateTooltip(tooltip, report)
  tooltip:Show();
end
