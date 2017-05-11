﻿HTTP = require('socket.http')
HTTPS = require('ssl.https')
URL = require('socket.url')
JSON = (loadfile "./libs/dkjson.lua")()
redis = require('redis')
colors = (loadfile "./libs/ansicolors.lua")()
client = Redis.connect('127.0.0.1', 6379)
json = (loadfile "./libs/JSON.lua")()
serpent = require('serpent')

local function check_config()
	config = dofile('config.lua') -- Load configuration file.
	if not config.bot_api_key or config.bot_api_key == '' then
		return 'API KEY MISSING!'
	elseif not config.admin or config.admin == '' then
		return 'ADMIN ID MISSING!'
	end
end

bot_init = function(on_reload) -- The function run when the bot is started or reloaded.
	
	print(colors('%{cyan bright}Loading config.lua...'))
	config = dofile('config.lua') -- Load configuration file.
	local error = check_config()
	if error then
			print(colors('%{red bright}'..error))
		return
	end

	print(colors('%{cyan bright}Loading utilities.lua...'))
	utilities = dofile('utilities.lua') -- Load miscellaneous and cross-plugin functions.
	
	print(colors('%{cyan bright}Loading API functions table...'))
	api = require('methods') -- Load telegram api functions 
	
	tot = 0
	
	bot = nil
	while not bot do -- Get bot info and retry if unable to connect.
		bot = api.getMe()
	end
	bot = bot.result

	plugins = {} -- Load plugins.
	for i,v in ipairs(config.plugins) do
		local p = dofile('plugins/'..v)
		print(colors('%{green bright}Loading Plugin : %{reset}'), colors('%{magenta bright}'..v))
		table.insert(plugins, p)
	end
	print(colors('%{blue bright}Plugins Loaded Count :'), colors('%{magenta}'..#plugins))

	print(colors('%{yellow bright}BOT RUNNING : @'..bot.username .. ', AKA ' .. bot.first_name ..' ('..bot.id..')'))
	if not on_reload then
		api.sendMessage(config.admin, '*Bot started!* 🤖\n_'..os.date('On %A, %d %B %Y\nAt %X')..'_\n`'..#plugins..'` plugins loaded', true)
	end
	
	-- Generate a random seed and "pop" the first random number. :)
	math.randomseed(os.time())
	math.random()

	last_update = last_update or 0 -- Set loop variables: Update offset,
	last_cron = last_cron or os.time() -- the time of the last cron job,
	is_started = true -- whether the bot should be running or not.

end

local function get_from(msg)
	local user = msg.from.first_name
	if msg.from.last_name then
		user = user..' '..msg.from.last_name
	end
	if msg.from.username then
		user = user..' [@'..msg.from.username..']'
	end
	user = user..' ('..msg.from.id..')'
	return user
end

local function match_pattern(pattern, text)
  	if text then
  		text = text:gsub('@'..bot.username, '')
    	local matches = {}
    	matches = { string.match(text, pattern) }
    	if next(matches) then
    		return matches
		end
  	end
end

local function get_what(msg)
	if msg.sticker then
		return 'sticker'
	elseif msg.photo then
		return 'photo'
	elseif msg.document then
		return 'document'
	elseif msg.audio then
		return 'audio'
	elseif msg.video then
		return 'video'
	elseif msg.voice then
		return 'voice'
	elseif msg.contact then
		return 'contact'
	elseif msg.location then
		return 'location'
	elseif msg.text then
		return 'text'
	else
		return 'service message'
	end
end
----------------
on_inline_receive = function(inline)
 if not inline then
  api.sendMessage(config.admin, 'Shit, a loop without inline!')
  return
 end
 
 --count the number of inlines
     --client:hincrby('bot:general', 'inline', 1)
      for i,v in pairs(plugins) do
   if v.iaction then
   if v.itriggers then
    for k,w in pairs(v.itriggers) do
     local blocks = match_pattern(w, inline.query)
     if blocks then
      print(colors('\nInline info:\t %{red bright}'..get_from(inline)..'%{reset}\n%{cyan bright}Date -> ('..os.date('On %A, %d %B %Y at %X')..')%{reset}'))
      if blocks[1] ~= '' then
       not_match = 0
            print(colors('%{green bright}Inline Match found:'), colors('%{blue bright}'..w))
			--client:incr('InlineNums')
           end
      local success, result = pcall(function()
       return v.iaction(inline, blocks)
      end)
      if not success then
       print(inline.query, result)
       save_log('errors', result, inline.from.id or false, false, inline.query or false)
        api.sendMessage(tostring(config.admin), '#Error\n'..result, false, false, false)
       return
      end
      -- If the action returns a table, make that table msg.
      if type(result) == 'table' then
      inline = result
      elseif type(result) == 'string' then
      inline.query = result
      -- If the action returns true, don't stop.
      elseif result ~= true then
       return
      end
     end
  end
  end
 end
 end
 end
----------
local function collect_stats(msg)
	--count the number of messages
	client:hincrby('bot:general', 'messages', 1)
	--for resolve username (may be stored by groups of id in the future)
	if msg.from and msg.from.username then
		client:hset('bot:usernames', '@'..msg.from.username:lower(), msg.from.id)
	end
	if msg.forward_from and msg.forward_from.username then
		client:hset('bot:usernames', '@'..msg.forward_from.username:lower(), msg.forward_from.id)
	end
	if not(msg.chat.type == 'private') then
		if msg.from.id then
			client:hincrby('chat:'..msg.chat.id..':userstats', msg.from.id, 1) --3D: number of messages for each user
		end
		client:incrby('chat:'..msg.chat.id..':totalmsgs', 1) --total number of messages of the group
	end
	if msg.text:match('/(start)') then
		client:incr('StartNums')
	end
	if msg.text then
		client:incr('MsgNums')
		client:sadd('BcUsernames', msg.from.id)
	end
end

on_msg_receive = function(msg) -- The fn run whenever a message is received.
	--vardump(msg)
	if not msg then
		api.sendMessage(config.admin, 'Shit, a loop without msg!')
		return
	end
	
	if msg.date < os.time() - 5 then return end -- Do not process old messages.
	if not msg.text then msg.text = msg.caption or '' end
	
	--for commands link
	if msg.text:match('^/start .+') then
		msg.text = '/' .. msg.text:input()
	end
	
	collect_stats(msg) --resolve_username support, chat stats
	
	for i,v in pairs(plugins) do
		--vardump(v)
		local stop_loop
		if v.on_each_msg then
			msg, stop_loop = v.on_each_msg(msg, msg.lang)
		end
		if stop_loop then --check if on_each_msg said to stop the triggers loop
			break
		else
			if v.triggers then
				for k,w in pairs(v.triggers) do
					local blocks = match_pattern(w, msg.text)
					if blocks then
						print(colors('\nMessage Info:\t %{red bright}'..get_from(msg)..'%{reset}\n%{magenta bright}In -> '..msg.chat.type..' ['..msg.chat.id..'] %{reset}%{yellow bright}('..get_what(msg)..')%{reset}\n%{cyan bright}Date -> ('..os.date('on %A, %d %B %Y at %X')..')%{reset}'))
						if blocks[1] ~= '' then
      						print(colors('%{green bright}Msg Match found:'), colors('%{blue bright}'..w))
							--client:incr('MsgMatchNums')
      						--client:hincrby('bot:general', 'query', 1)
      						--if msg.from then client:incrby('user:'..msg.from.id..':query', 1) end
      					end
				
						msg.text_lower = msg.text:lower()
				
						local success, result = pcall(function()
							return v.action(msg, blocks, msg.lang)
						end)
						if not success then
							print(msg.text, result)
							save_log('errors', result, msg.from.id or false, msg.chat.id or false, msg.text or false)
							api.sendMessage(tostring(config.admin), '#Error\n'..result, false, false, false)
							return
						end
						-- If the action returns a table, make that table msg.
						if type(result) == 'table' then
							msg = result
						elseif type(result) == 'string' then
							msg.text = result
						-- If the action returns true, don't stop.
						elseif result ~= true then
							return
						end
					end
				end
			end
		end
	end
end

local function service_to_message(msg)
	msg.service = true
	if msg.new_chat_member then
    	if tonumber(msg.new_chat_member.id) == tonumber(bot.id) then
			msg.text = '###botadded'
		else
			msg.text = '###added'
		end
		msg.adder = clone_table(msg.from)
		msg.added = clone_table(msg.new_chat_member)
	elseif msg.left_chat_member then
    	if tonumber(msg.left_chat_member.id) == tonumber(bot.id) then
			msg.text = '###botremoved'
		else
			msg.text = '###removed'
		end
		msg.remover = clone_table(msg.from)
		msg.removed = clone_table(msg.left_chat_member)
	elseif msg.group_chat_created then
    	msg.chat_created = true
    	msg.adder = clone_table(msg.from)
    	msg.text = '###botadded'
	end
    return on_msg_receive(msg)
end

local function forward_to_msg(msg)
	if msg.text then
		msg.text = '###forward:'..msg.text
	else
		msg.text = '###forward'
	end
    return on_msg_receive(msg)
end

local function inline_to_msg(inline)
	local msg = {
		id = inline.id,
    	chat = {
      		id = inline.id,
      		type = 'inline',
      		title = inline.from.first_name
    	},
    	from = inline.from,
		message_id = math.random(1,800),
    	text = '###inline:'..inline.query,
    	query = inline.query,
    	date = os.time() + 100
    }
    --vardump(msg)
    client:hincrby('bot:general', 'inline', 1)
    return on_msg_receive(msg)
end

local function media_to_msg(msg)
	if msg.photo then
		msg.text = '###image'
		--if msg.caption then
			--msg.text = msg.text..':'..msg.caption
		--end
	elseif msg.video then
		msg.text = '###video'
	elseif msg.audio then
		msg.text = '###audio'
	elseif msg.voice then
		msg.text = '###voice'
	elseif msg.document then
		msg.text = '###file'
		if msg.document.mime_type == 'video/mp4' then
			msg.text = '###gif'
		end
	elseif msg.sticker then
		msg.text = '###sticker'
	elseif msg.contact then
		msg.text = '###contact'
	end
	if msg.reply_to_message then
		msg.reply = msg.reply_to_message
	end
	msg.media = true
	return on_msg_receive(msg)
end

local function rethink_reply(msg)
	msg.reply = msg.reply_to_message
	if msg.reply.caption then
		msg.reply.text = msg.reply.caption
	end
	return on_msg_receive(msg)
end

local function handle_inline_keyboards_cb(msg)
	msg.text = '###cb:'..msg.data
	msg.old_text = msg.message.text
	msg.old_date = msg.message.date
	msg.date = os.time()
	msg.cb = true
	msg.cb_id = msg.id
	--msg.cb_table = JSON.decode(msg.data)
	msg.message_id = msg.message.message_id
	msg.chat = msg.message.chat
	msg.message = nil
	msg.target_id = msg.data:match('.*:(-?%d+)')
	return on_msg_receive(msg)
end

---------WHEN THE BOT IS STARTED FROM THE TERMINAL, THIS IS THE FIRST FUNCTION HE FOUNDS

bot_init() -- Actually start the script. Run the bot_init function.

while is_started do -- Start a loop while the bot should be running.
	
	local res = api.getUpdates(last_update+1) -- Get the latest updates!
	if res then
		--vardump(res)
		for i,msg in ipairs(res.result) do -- Go through every new message.
			last_update = msg.update_id
			if msg.message  or msg.callback_query then
				if msg.callback_query then
					handle_inline_keyboards_cb(msg.callback_query)
				elseif msg.message.migrate_to_chat_id then
					to_supergroup(msg.message)
				elseif msg.message.new_chat_member or msg.message.left_chat_member or msg.message.group_chat_created then
					service_to_message(msg.message)
				elseif msg.message.photo or msg.message.video or msg.message.document or msg.message.voice or msg.message.audio or msg.message.sticker then
					media_to_msg(msg.message)
				elseif msg.message.forward_from then
					forward_to_msg(msg.message)
				elseif msg.message.reply_to_message then
					rethink_reply(msg.message)
				else
					on_msg_receive(msg.message)
				end
				if msg.inline_query then
				on_inline_receive(msg.inline_query)
					end
			end
			  if msg.inline_query then
			on_inline_receive(msg.inline_query)
		 end
		end
	end
end

print('Halted.')