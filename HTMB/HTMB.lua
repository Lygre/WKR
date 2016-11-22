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

local zones = load_zones()
local key_items = load_KIs()
local player = windower.ffxi.get_player()
local current_zone = windower.ffxi.get_info().zone
local pkt = {}
local first_poke = true
local number_of_attempt = 1
local activate_by_addon = false
local unlock_commands = {}
local usable_commands = {}
local current_ki_id = 0

windower.register_event('addon command', function(...)

	local args = T{...}
	local cmd = args[1]
	args:remove(1)
	local lcmd = cmd:lower()
	
	if table.length(usable_commands) > 0 then 
		for k,v in pairs(usable_commands) do
			if v['command_name']:contains(lcmd) then
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
	else
		log('Commands have not been generated yet')
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
			log('Attempting to entre BCNM, sending poke!')
			packets.inject(packet)
		else
			activate_by_addon = false
			log('You are too far away from the entrance!')
		end
	else
		activate_by_addon = false
		log('Cureently no information regarding High-Tier Mission Battlefields in this zone')
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
			create_0x05C(current_zone,zones[current_zone][current_ki_id]['0x05C'][1])
		end
		
	elseif id == 0x065 then -- confirmation packet of available BCNM room
		if activate_by_addon == true then
			log('packet 0x065 received (Entry confirmation packet)')
			 -- parse the packet for its data
			packet = packets.parse('incoming', data)
			-- get the confirmation co-ordinates
			local x = packet['X'] 
			local z = packet['Z']
			local y = packet['Y']
			
			-- if unknow = 1 then room 1 is free, for farvour confirmation we check co-ordinates against ones we sent
			if packet['_unknown1'] == 1 and x == zones[current_zone][current_ki_id]['0x05C'][number_of_attempt]['X'] and y == zones[current_zone][current_ki_id]['0x05C'][number_of_attempt]['Y'] and z == zones[current_zone][current_ki_id]['0x05C'][number_of_attempt]['Z'] then
				log('Confirmed BCNM room 1 is open, waiting for 0x055 packet')
			else
			-- failed to entre room 1 so we cycle to room 2 then room 3
				log('BCNM Room ' .. number_of_attempt .. ' is full. Attempting next BCNM room!')
				number_of_attempt = number_of_attempt + 1
				if number_of_attempt < 4 then
					create_0x05C(current_zone,zones[current_zone][current_ki_id]['0x05C'][number_of_attempt])
				end
			end
		end
		
	elseif id == 0x055 then -- change in player KI data confirming entry
		if activate_by_addon == true then
			log('Confirmed entry to BCNM room ' .. number_of_attempt .. ' !')
			create_0x05B(current_zone,2,false)
			local packet = packets.new('outgoing', 0x016, {
				["Target Index"]=pkt['me'],
			})
			activate_by_addon = false
			delete_commands()
			number_of_attempt = 1
		end
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
	local packet = packets.new('outgoing', 0x05B)
		packet["Target"]=zones[zone_number][current_ki_id]['0x05B']["Target"]
		packet["Option Index"]=zones[zone_number][current_ki_id]['0x05B']["Option Index"][option_index]
		packet["_unknown1"]=zones[zone_number][current_ki_id]['0x05B']["_unknown1"]
		packet["Target Index"]=zones[zone_number][current_ki_id]['0x05B']["Target Index"]
		packet["Automated Message"]=message
		packet["_unknown2"]=0
		packet["Zone"]=zone_number
		packet["Menu ID"]=zones[zone_number][current_ki_id]['0x05B']["Menu ID"]
	packets.inject(packet)
end

-- function to request entry to BCNM bassed on the current zone id
function create_0x05C(zone_number,packet_table)
	local packet = packets.new('outgoing', 0x05C)
		packet["X"]= packet_table["X"]
		packet["Z"]= packet_table["Z"]
		packet["Y"]= packet_table["Y"]
		packet["Target ID"]=packet_table["Target ID"]
		packet["Target Index"]=packet_table["Target Index"]
		packet["_unknown1"]=packet_table["_unknown1"]
		packet["_unknown2"]=packet_table["_unknown2"]
		packet["_unknown3"]=packet_table["_unknown3"]
	packets.inject(packet)
end

-- event to track zone change and reset first time poke
windower.register_event('zone change',function(new_id,old_id)
	if first_poke and current_zone ~= new_id then
		first_poke = false
		activate_by_addon = false
		log('You have left the BCNM area!')
	end
	if zones[new_id] then
		log('You have entered a BCNM area.')
		coroutine.sleep(10)
		log('Checking potential battlefields!')
		local x = 1
		local ki_list = windower.ffxi.get_key_items()
		for k,v in pairs(zones[new_id]) do
			if k ~= nil and type(k) == 'number' then
				for i,d in pairs(ki_list) do
					if d == k then
						log('Found KI ' .. d)
						for j,e in pairs(key_items) do
							if j == k then
								for l,m in pairs(e['Zone ID']) do
									if l == new_id then 
										generate_commands(x,k)
										x = x + 1
									end
								end
							end
						end
					end
				end
			end	
		end
	else
		delete_commands()
	end
end)

function delete_commands()
	if table.length(usable_commands) > 0 then
		usable_commands = {}
		log('You have zoned, commands have been removed!')
	end
end

function generate_commands(number_of_command,ki_id)
	usable_commands[number_of_command] = {}
	usable_commands[number_of_command]['command_name'] = 'entre ' .. number_of_command
	usable_commands[number_of_command]['KI ID'] = ki_id
	log('Use command: \"'.. usable_commands[number_of_command]['command_name'] .. "\" to entre battlefield \"" .. key_items[ki_id]['KI Name'] .. "\"")
end







