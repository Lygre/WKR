--[[Copyright © 2016, Hugh Broome, Sebastien Gomez
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of <addon name> nor the
      names of its contributors may be used to endorse or promote products
      derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL Hugh Broome BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.]]--

_addon.name     = 'HTMB'
_addon.author   = 'Lygre + Colway'
_addon.version  = '2.0.1'
_addon.commands = {'HTMB'}

require('tables')
require('strings')
require('luau')
require('pack')
require('lists')
require('logger')
require('sets')
files = require('files')
packets = require('packets')
require('chat')
res = require('resources')

-- packets to track
-- pv t i 0x032|0x034|0x055|0x065 o 0x016|0x05b|0x05c
-- pv l f both 0x032 0x034 0x055 0x065 0x016 0x05b 0x05c

function load_zones()

	local f = io.open(windower.addon_path..'data/zone_info.lua','r')
	local t = f:read("*all")
	t = assert(loadstring(t))()
	f:close()
	
	return t
end

function load_KIs()

	local f = io.open(windower.addon_path..'data/ki_info.lua','r')
	local t = f:read("*all")
	t = assert(loadstring(t))()
	f:close()
	
	return t
end

function load_NPCs()

	local f = io.open(windower.addon_path..'data/npc_info.lua','r')
	local t = f:read("*all")
	t = assert(loadstring(t))()
	f:close()
	
	return t
end

local zones = load_zones()
local key_items = load_KIs()
local npcs = load_NPCs()
local player = windower.ffxi.get_player()
local number_of_merits = 0
local current_zone = windower.ffxi.get_info().zone
local pkt = {}
local first_poke = true
local number_of_attempt = 1
local activate_by_addon = false
local activate_by_addon_npc = false
local usable_commands = {}
local ki_commands = {}
local current_ki_id = 0
local forced_update = false

windower.register_event('addon command', function(...)

	local args = T{...}
	local cmd = args[1]
	local lcmd = cmd:lower()
	
	if table.length(usable_commands) > 0 then
		for k,v in pairs(usable_commands) do
			if v['command_name']:contains(lcmd) and v['command_name']:contains(args[2]) then
				player = windower.ffxi.get_player()
				current_zone = windower.ffxi.get_info().zone
				pkt = validate()
				log('Checking data for BCNM in zone!')
				number_of_attempt = 1
				activate_by_addon = true
				current_ki_id = v['KI ID']
				poke_warp(current_zone,v['KI ID'])
				
			end
		end
	end
	if table.length(ki_commands) > 0 then 
		for k,v in pairs(ki_commands) do
			if v['command_name']:contains(lcmd) and v['command_name']:contains(args[2]) then
				player = windower.ffxi.get_player()
				current_zone = windower.ffxi.get_info().zone
				pkt = validate()
				log('Checking data for KI NPC in zone!')
				activate_by_addon_npc = true
				current_ki_id = v['KI ID']
				poke_npc(current_zone,v['KI ID'])
				
			end
		end
	end
	if lcmd == 'force' then
		warning('Force checking ki count AND battlefields in zone')
		current_zone = windower.ffxi.get_info().zone
		forced_update = true
		check_zone_for_battlefield()
		local packet = packets.new('outgoing', 0x061, {})
		packets.inject(packet)
		coroutine.sleep(2)
		find_missing_kis()
	end
end)

function validate()
	local me
	local result = {}
	for i,v in pairs(windower.ffxi.get_mob_array()) do
		if v['name'] == player.name then
			result['me'] = i
		end
	end
	return result 
end

-- now requires a valid zone number that exists in the zone_info.lua and also requires to be within range of the BCNM entrance
function poke_warp(zone_number,ki_id)

	local distance = 0
	if windower.ffxi.get_mob_by_index(zones[zone_number][ki_id]['0x05B']["Target Index"]) then
		distance = windower.ffxi.get_mob_by_index(zones[zone_number][ki_id]['0x05B']["Target Index"]).distance
		-- turn distance into yalms to match the distance addon
		distance = distance:sqrt()
		if distance > 0 and distance < 5 then
			local packet = packets.new('outgoing', 0x01A, {
				["Target"]=zones[zone_number][ki_id]['0x05B']["Target"],
				["Target Index"]=zones[zone_number][ki_id]['0x05B']["Target Index"],
				["Category"]=0,
				["Param"]=0,
				["_unknown1"]=0})
			first_poke = true
			notice('Attempting to entre BCNM, sending poke!')
			packets.inject(packet)
		else
			activate_by_addon = false
			error('You are too far away from the entrance!')
		end
	else
		activate_by_addon = false
		error('Cureently no information regarding High-Tier Mission Battlefields in this zone')
	end
end

-- now requires a valid zone number that exists in the zone_info.lua and also requires to be within range of the BCNM entrance
function poke_npc(zone_number,ki_id)

	local distance = 0
	if windower.ffxi.get_mob_by_index(npcs[zone_number]['NPC Index']) then
		distance = windower.ffxi.get_mob_by_index(npcs[zone_number]['NPC Index']).distance
		-- turn distance into yalms to match the distance addon
		distance = distance:sqrt()
		if distance > 0 and distance < 5 then
			local packet = packets.new('outgoing', 0x01A, {
				["Target"]=npcs[zone_number]['NPC'],
				["Target Index"]=npcs[zone_number]['NPC Index'],
				["Category"]=0,
				["Param"]=0,
				["_unknown1"]=0})
			notice('Attempting to buy KI, sending poke!')
			packets.inject(packet)
		else
			activate_by_addon_npc = false
			error('You are too far away from the NPC!')
		end
	else
		activate_by_addon_npc = false
		error('Cureently no information regarding KI NPC\'s in this zone')
	end
end

-- parsing of relevant incoming packets to perform actions
windower.register_event('incoming chunk',function(id,data,modified,injected,blocked)
	
	if id == 0x034 or id == 0x032 then  -- original poke i.e. opening entry menu
		if activate_by_addon == true then
		
			log('packet 0x034 received (menu entry packet)')
			local packet = packets.new('outgoing', 0x016, {
				["Target Index"]=pkt['me'],
			})
			packets.inject(packet)
			--if first time poking the door send the assosiated junk 0x016 packets
			if first_poke then
				inject_anomylus_packets(current_zone)
			end
			
			-- send menu choice for VD 
			log('Sending first 0x05B packet (menu choice)')
			create_0x05B(current_zone,1,true)
			-- send entry request for BCNM room 1
			log('Sending 0x05C packet (Entry request for BCNM room 1)')
			create_0x05C(zones[current_zone][current_ki_id]['0x05C'][number_of_attempt])
			number_of_attempt = number_of_attempt + 1
			return true
			
		elseif activate_by_addon_npc == true then
		
			log('packet 0x034 received (menu entry packet for ki buying)')
			local packet = packets.new('outgoing', 0x016, {
				["Target Index"]=pkt['me'],
			})
			packets.inject(packet)
			-- itterate through ki id's for the option index associated
			for k, v in pairs(key_items[current_ki_id]) do
				if k ==  "Option Index" then
					if v[2] then
						log('Sending first 0x05B packet (switch page in menu)')
						create_0x05B_ki(current_zone,2,true,current_ki_id)
						log('Sending second 0x05B packet (menu choice)')
						create_0x05B_ki(current_zone,2,false,current_ki_id)
						return true
					else
						log('Sending first 0x05B packet (menu choice)')
						create_0x05B_ki(current_zone,1,false,current_ki_id)
						return true
					end		
				end
			end
			
		end
		
	elseif id == 0x065 then -- confirmation packet of available BCNM room
		if activate_by_addon == true then
			log('packet 0x065 received (Entry confirmation packet)')
			 -- parse the packet for its data
			local packet = packets.parse('incoming', data)			
			-- if unknow = 1 then room 1 is free, for farvour confirmation we check co-ordinates against ones we sent
			if packet['_unknown1'] == 1 then
				log('Confirmed BCNM room '.. (number_of_attempt - 1) ..' is open, waiting for 0x055 packet')
			else
			-- failed to entre room 1 so we cycle to room 2 then room 3
				log('BCNM Room ' .. number_of_attempt .. ' is full. Attempting next BCNM room!')
				if number_of_attempt < 4 then
					create_0x05C(zones[current_zone][current_ki_id]['0x05C'][(number_of_attempt - 1)])
					number_of_attempt = number_of_attempt + 1
				else
					error('All Rooms are full, sending 0x05B to exit.')
					create_0x05B(current_zone,3,false)
					local packet = packets.new('outgoing', 0x016, {
						["Target Index"]=pkt['me'],
					})
					packets.inject(packet)
					number_of_attempt = 1
					return true
				end
			end
			return true
		end
		
	elseif id == 0x055 then -- change in player KI data confirming entry
		if activate_by_addon == true then
			notice('Confirmed entry to BCNM room ' .. number_of_attempt .. ' !')
			create_0x05B(current_zone,2,false)
			local packet = packets.new('outgoing', 0x016, {
				["Target Index"]=pkt['me'],
			})
			packets.inject(packet)
			activate_by_addon = false
			delete_commands()
			number_of_attempt = 1
			pkt = {}
			return true
			
		elseif activate_by_addon_npc == true then
		
			local packet = packets.new('outgoing', 0x016, {
				["Target Index"]=pkt['me'],
			})
			packets.inject(packet)
			
			pkt = {}
			activate_by_addon_npc = false
			notice('KI \"' .. key_items[current_ki_id]['KI Name'] .. '\" has been baught!' )
			delete_ki_commands()
			
			coroutine.sleep(3)
			windower.send_command('htmb force')
			return true
			
		end
	elseif id == 0x63 and data:byte(5) == 2 and forced_update == true then
		number_of_merits = data:byte(11)%128
		log('Total merit update. Total: ' .. number_of_merits)
		forced_update = false
	end
end)

-- function to inject anomylous packets associated with first time click on BCNM
function inject_anomylus_packets(zone_number)
	
	for k,v in pairs(zones[zone_number][current_ki_id]['0x016']) do
		if v ~= nil and type(v) == 'number' then
			local packet = packets.new('outgoing', 0x016, {
				["Target Index"]=v,
			})
			packets.inject(packet)
		end	
	end

end

-- function to send menu choice bassed on zone id
function create_0x05B(zone_number,option_index,message)

	local info = zones[zone_number][current_ki_id]['0x05B']
	
	local packet = packets.new('outgoing', 0x05B)
		packet["Target"]=			info["Target"]
		packet["Option Index"]=		info["Option Index"][option_index]
		packet["_unknown1"]=		info["_unknown1"]
		packet["Target Index"]=		info["Target Index"]
		packet["Menu ID"]=			info["Menu ID"]
		packet["Zone"]=				zone_number
		packet["Automated Message"]=message
		packet["_unknown2"]=		0
	packets.inject(packet)
	
end

-- function to send menu choice to buy ki bassed on zone id
-- create_0x05B_ki(current_zone,j[1],true,current_ki_id)
function create_0x05B_ki(zone_number,option_index,message,ki_id)

	local info = npcs[zone_number]['0x05B']
	
	local packet = packets.new('outgoing', 0x05B)
		packet["Target"]=			info["Target"]
		packet["Option Index"]=		key_items[ki_id]["Option Index"][option_index]
		packet["_unknown1"]=		info["_unknown1"]
		packet["Target Index"]=		info["Target Index"]
		packet["Menu ID"]=			info["Menu ID"]
		packet["Zone"]=				zone_number
		packet["Automated Message"]=message
		packet["_unknown2"]=		0
	packets.inject(packet)
	
end

-- function to request entry to BCNM bassed on the current zone id
function create_0x05C(packet_table)

	local packet = packets.new('outgoing', 0x05C)
		packet["X"]= 			packet_table["X"]
		packet["Z"]=			packet_table["Z"]
		packet["Y"]= 			packet_table["Y"]
		packet["Target ID"]=	packet_table["Target ID"]
		packet["Target Index"]=	packet_table["Target Index"]
		packet["_unknown1"]=	packet_table["_unknown1"]
		packet["_unknown2"]=	packet_table["_unknown2"]
		packet["_unknown3"]=	packet_table["_unknown3"]
	packets.inject(packet)
	
end

-- event to track zone change and reset first time poke
windower.register_event('zone change',function(new_id,old_id)
	if first_poke and current_zone ~= new_id then
		first_poke = false
		activate_by_addon = false
		log('You have left the BCNM area!')
	elseif zones[new_id] then
		log('You have zoned into a BCNM area.')
		coroutine.sleep(10)
		check_zone_for_battlefield()
	elseif npcs[new_id] then
		log('You have zoned into an area with a KI npc.')
		coroutine.sleep(10)
		notice("Checking for missing KI's!")
		forced_update = true
		find_missing_kis()
	else
		delete_commands()
	end
	
end)

function delete_commands()
	if table.length(usable_commands) > 0 then
		usable_commands = {}
		warning('You have zoned, commands have been removed!')
	end
end

function delete_ki_commands()
	if table.length(ki_commands) > 0 then
		ki_commands = {}
		warning('You have baught a KI, Reseting commands!')
	end
end

function generate_commands(number_of_command,ki_id)
	usable_commands[number_of_command] = {}
	usable_commands[number_of_command]['command_name'] = 'entre ' .. number_of_command
	usable_commands[number_of_command]['KI ID'] = ki_id
	notice('Use command: \"'.. usable_commands[number_of_command]['command_name'] .. "\" to entre battlefield \"" .. key_items[ki_id]['KI Name'] .. "\"")
end

function generate_ki_commands(number_of_command,ki_id)
	ki_commands[number_of_command] = {}
	ki_commands[number_of_command]['command_name'] = 'buy ' .. number_of_command
	ki_commands[number_of_command]['KI ID'] = ki_id
	notice('Use command: \"'.. ki_commands[number_of_command]['command_name'] .. "\" to buy KI \"" .. key_items[ki_id]['KI Name'] .. "\"")
end

function find_missing_kis()
	
	if npcs[current_zone] then
		local toons_kis = windower.ffxi.get_key_items()
		local matching_kis = {}
		local missing_kis = {}
		
		-- ki's you do have
		for i,d in pairs(toons_kis) do
			-- i = table index
			-- d = ki id
			-- ki's you need
			for k, v in pairs(key_items) do
				-- k = ki id
				-- v = table contents
				if d == k then
					table.insert(matching_kis, d)
				end
			end
		end
		if table.length(matching_kis) == 20 then
			notice('You already posess all High-tier mission battlefield KI\'s. Will not create commands.')
			return
		end
		for k, v in pairs(key_items) do
			-- k = ki id
			-- v = table contents
			if not table.contains(matching_kis, k) then
				table.insert(missing_kis, k)
				log('Found missing KI \"' .. key_items[k]['KI Name'] .. '\"')
			end
		end
		
		local buy_number = 1
		for k, v in pairs(missing_kis) do
			local ki = false
			if number_of_merits >= key_items[v]['Merit Cost'] then
				for i, j in pairs(key_items[v]) do
					if i == "Option Index" then
						generate_ki_commands(buy_number,v)
						buy_number = buy_number + 1
						ki = true
						break
					end
				end
				if ki == false then
					warning('Lack of packet information to buy KI: \"' .. key_items[v]['KI Name'] .. '\". Will not create command.')
				end
			else
				notice('You do not have enought merits to buy \"' .. key_items[v]['KI Name'] .. '\". Will not create command.')
			end
		end
	else
		error('You are not in a zone with an available KI NPC!')
	end
end

function check_zone_for_battlefield()
	if zones[current_zone] then
		log('Checking potential battlefields!')
		local toons_kis = windower.ffxi.get_key_items()
		local matching_kis = {}
		local current_zone_kis = {}
		-- ki's you do have
		for i,d in pairs(toons_kis) do
			-- i = table index
			-- d = ki id
			-- ki's you need
			for k, v in pairs(key_items) do
				-- k = ki id
				-- v = table contents
				if d == k then
					table.insert(matching_kis, d)
				end
			end
		end
		for k,v in pairs(zones[current_zone]) do
			if k ~= nil and type(k) == 'number' then
				-- k = ki id
				-- v = table contents
				if table.contains(matching_kis, k) then
					table.insert(current_zone_kis, k)
				end
			end
		end
		if table.length(current_zone_kis) == 0 then
			warning('You have no KI\'s for this zone.')
			return
		end
		for k, v in pairs(current_zone_kis) do
			generate_commands(k,v)
		end
	else
		error('Not in a BCNM zone!')
	end

end


