--- Type definitions and helper methods for the notifications model
--- (i.e., its abstract state).
---
--- Note that this model exists separately from the view for several reasons:
--- (1) to make debugging and testing easier;
--- (2) to accumulate repeated, asynchronous in-place-updating notifications,
---     and avoid building strings for no reason; and
--- (3) to enable fine-grained cacheing of rendered elements.
local M = {}

--- A collection of NotificationItems.
---@class NotificationGroup
---@field key           NotificationKey     used to distinguish this group from others
---@field config        NotificationConfig  configuration for this group
---@field items         NotificationItem[]  items displayed in the group

--- Notification element containing a message and optional annotation.
---@class NotificationItem
---@field key         NotificationKey  used to distinguish this item from others
---@field message     string    displayed message for the item
---@field annote      string?   optional title that accompanies the message
---@field style       string    style used to render the annote/title, if any
---@field hidden      boolean   whether this item should be shown
---@field expires_at  number    what time this item should be removed; math.huge means never
---@field data        any?      arbitrary data attached to notification item

--- Get the notification group indexed by group_key; create one if none exists.
---
---@param   configs     { [NotificationKey]: NotificationConfig }
---@param   groups      NotificationGroup[]
---@param   group_key   NotificationKey
---@return              NotificationGroup group
local function get_group(configs, groups, group_key)
  for _, group in ipairs(groups) do
    if group.key == group_key then
      return group
    end
  end

  -- Group not found; create it and insert it into list of active groups.

  ---@type NotificationGroup
  local group = {
    key = group_key,
    items = {},
    config = configs[group_key] or configs.default
  }
  table.insert(groups, group)
  return group
end

--- Search for an item with the given key among a notification group.
---
---@param group NotificationGroup
---@param key NotificationKey
---@return NotificationItem?
local function find_item(group, key)
  if key == nil then
    return nil
  end

  for _, item in ipairs(group.items) do
    if item.key == key then
      return item
    end
  end

  -- No item with key was found
  return nil
end

--- Obtain the style specified by the level parameter of a .update(),
--- reading from config if necessary.
---
---@param config  NotificationConfig
---@param level   number | string | nil
---@return        string?
local function style_from_level(config, level)
  if type(level) == "number" then
    if level == vim.log.levels.INFO and config.info_style then
      return config.info_style
    elseif level == vim.log.levels.WARN and config.warn_style then
      return config.warn_style
    elseif level == vim.log.levels.ERROR and config.error_style then
      return config.error_style
    elseif level == vim.log.levels.DEBUG and config.debug_style then
      return config.debug_style
    end
  else
    return level
  end
end

--- Obtain the annotation from the specified level of an .update() call.
---
--- TODO: config currently unused, but we should use it to configure the string.
---
---@param _config NotificationConfig
---@param level   number | string | nil
---@return string?
local function annote_from_level(_config, level)
  if type(level) == "number" then
    if level == vim.log.levels.INFO then
      return "INFO"
    elseif level == vim.log.levels.WARN then
      return "WARN"
    elseif level == vim.log.levels.ERROR then
      return "ERROR"
    elseif level == vim.log.levels.DEBUG then
      return "DEBUG"
    end
  else
    return nil
  end
end

--- Compute the expiry time based on the given TTL (from notify() options) and the default TTL (from config).
---@param ttl         number?
---@param default_ttl number?
---@return            number expiry_time
local function compute_expiry(now, ttl, default_ttl)
  if not ttl or ttl == 0 then
    return now + (default_ttl or 3)
  else
    return now + ttl
  end
end

--- Update the state of the notifications model.
---
--- The API of this function is based on that of vim.notify().
---
---@param now     number
---@param configs table<string, NotificationConfig>
---@param groups  NotificationGroup[]
---@param msg     string?
---@param level   NotificationLevel?
---@param opts    NotificationOptions?
function M.update(now, configs, groups, msg, level, opts)
  opts = opts or {}
  local group_key = opts.group ~= nil and opts.group or "default"
  local group = get_group(configs, groups, group_key)
  local item = find_item(group, opts.key)

  if item == nil then
    -- Item doesn't yet exist; create new item and to insert into the group
    if msg == nil then
      return
    end
    ---@type NotificationItem
    local new_item = {
      key = opts.key,
      message = msg,
      annote = opts.annote or annote_from_level(group.config, level),
      style = style_from_level(group.config, level) or group.config.annote_style or "Question",
      hidden = opts.hidden or false,
      expires_at = compute_expiry(now, opts.ttl, group.config.ttl),
      data = opts.data,
    }
    table.insert(group.items, new_item)
  else
    -- Item with the same key already exists; update it in place
    item.message = msg or item.message
    item.style = style_from_level(group.config, level) or item.style
    item.annote = opts.annote or annote_from_level(group.config, level) or item.annote
    item.hidden = opts.hidden or item.hidden
    item.expires_at = opts.ttl and compute_expiry(now, opts.ttl, group.config.ttl) or item.expires_at
    item.data = opts.data ~= nil and opts.data or item.data
  end
end

--- Prune out all items (and groups) for which the ttl has elapsed.
---
--- Updates each group in-place (i.e., removes items from them), but returns
--- a list of groups that still have items left.
---
---@param now number timestamp of current frame.
---@param groups NotificationGroup[]
---@return NotificationGroup[]
function M.tick(now, groups)
  local new_groups = {}
  for _, group in ipairs(groups) do
    local new_items = {}
    for _, item in ipairs(group.items) do
      if item.expires_at > now then
        table.insert(new_items, item)
      else
      end
    end
    if #group.items > 0 then
      group.items = new_items
      table.insert(new_groups, group)
    else
    end
  end
  return new_groups
end

return M
