extends Node
class_name MatchRealtimeClient

signal envelope_received(envelope: Dictionary)
signal connection_changed(active: bool)
signal error_raised(message: String)

var _socket := WebSocketPeer.new()
var _active := false


func connect_to_match(match_id: String, realtime_base_url: String, token: String) -> void:
	close_stream()
	if match_id.is_empty() or realtime_base_url.is_empty() or token.is_empty():
		error_raised.emit("Realtime connection parameters are incomplete.")
		return
	var url: String = "%s/api/v1/matches/%s/stream?token=%s" % [realtime_base_url.trim_suffix("/"), match_id.uri_encode(), token.uri_encode()]
	var err: int = _socket.connect_to_url(url)
	if err != OK:
		error_raised.emit("Failed to connect realtime stream (%s)." % err)
		return
	_active = true
	set_process(true)


func close_stream() -> void:
	if _socket.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		_socket.close()
	var was_active: bool = _active
	_active = false
	set_process(false)
	if was_active:
		connection_changed.emit(false)


func _process(_delta: float) -> void:
	if not _active:
		return
	_socket.poll()
	var ready_state: int = _socket.get_ready_state()
	if ready_state == WebSocketPeer.STATE_OPEN:
		connection_changed.emit(true)
		while _socket.get_available_packet_count() > 0:
			var payload_text: String = _socket.get_packet().get_string_from_utf8()
			var parsed: Variant = JSON.parse_string(payload_text)
			if parsed is Dictionary:
				envelope_received.emit((parsed as Dictionary).duplicate(true))
	elif ready_state == WebSocketPeer.STATE_CLOSING or ready_state == WebSocketPeer.STATE_CLOSED:
		var code: int = _socket.get_close_code()
		var reason: String = _socket.get_close_reason()
		close_stream()
		if code != -1 and code != 1000:
			error_raised.emit("Realtime connection closed (%s: %s)." % [code, reason])
