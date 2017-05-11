local triggers = {
		'^/(start)$'
}
	
local action = function(msg, matches)
if matches[1] == 'start' then
api.sendMessage(msg.chat.id, "Hello :)", true)
end
end

return {
  action = action,
  triggers = triggers,
}
