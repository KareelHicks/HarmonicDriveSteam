extends Node
class_name RelayAPIClient

const RelayConfig = preload("res://scripts/net/RelayConfig.gd")

signal request_failed(route: String, message: String)
signal raw_request_completed(route: String, payload: Dictionary)


func call_api(method: String, route: String, body: Dictionary = {}, bearer_token: String = "", callback: Callable = Callable()) -> void:
	var http := HTTPRequest.new()
	http.timeout = RelayConfig.request_timeout_seconds()
	add_child(http)
	var meta: Dictionary = {
		"route": route,
		"callback": callback,
		"http": http,
	}
	http.request_completed.connect(_on_request_completed.bind(meta), CONNECT_ONE_SHOT)
	var headers := PackedStringArray(["Content-Type: application/json"])
	if not bearer_token.is_empty():
		headers.append("Authorization: Bearer %s" % bearer_token)
	var request_method: int = HTTPClient.METHOD_GET if method.to_upper() == "GET" else HTTPClient.METHOD_POST
	var payload: String = "" if request_method == HTTPClient.METHOD_GET else JSON.stringify(body)
	var err: int = http.request("%s%s" % [RelayConfig.base_url(), route], headers, request_method, payload)
	if err != OK:
		http.queue_free()
		_fail(route, "Failed to dispatch relay request (%s)." % err, callback)


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, meta: Dictionary) -> void:
	var http: HTTPRequest = meta.get("http") as HTTPRequest
	if is_instance_valid(http):
		http.queue_free()
	var route: String = str(meta.get("route", ""))
	var callback: Callable = meta.get("callback") as Callable
	var decoded: String = body.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(decoded) if not decoded.is_empty() else {}
	if not (parsed is Dictionary):
		parsed = {"raw_body": decoded}
	var payload: Dictionary = (parsed as Dictionary).duplicate(true)
	raw_request_completed.emit(route, payload.duplicate(true))
	var success: bool = result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 300
	if success:
		if callback.is_valid():
			callback.call(true, payload, payload, {"route": route, "response_code": response_code})
		return
	var message: String = str(payload.get("message", payload.get("error", payload.get("raw_body", "Relay request failed."))))
	_fail(route, message, callback, {"route": route, "response_code": response_code, "raw_body": decoded})


func _fail(route: String, message: String, callback: Callable, meta: Dictionary = {}) -> void:
	request_failed.emit(route, message)
	if callback.is_valid():
		var failure_meta: Dictionary = {"route": route}
		for key_variant in meta.keys():
			failure_meta[str(key_variant)] = meta[key_variant]
		callback.call(false, {}, {"message": message}, failure_meta)
