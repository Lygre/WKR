

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