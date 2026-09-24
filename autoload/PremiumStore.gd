extends Node

const PremiumSongCatalog = preload("res://scripts/platform/PremiumSongCatalog.gd")

signal store_changed
signal purchase_completed(status: String, product_id: String, message: String)

const BILLING_SINGLETON := "HarmonicBilling"
const PREVIEW_SECONDS := 60.0

var _plugin: Object
var _setup_complete := false
var _store_available := false
var _loading_products := false
var _status_message := ""
var _products_by_id := {}
var _purchased_ids: Array[String] = []
var _preview_token := 0


func _ready() -> void:
	_purchased_ids = ProfileStore.get_purchased_premium_product_ids()
	if is_android_store_enabled():
		call_deferred("_setup_android_billing")


func is_android_store_enabled() -> bool:
	return OS.has_feature("android")


func is_store_available() -> bool:
	return _store_available


func is_loading_products() -> bool:
	return _loading_products


func get_status_message() -> String:
	return _status_message


func get_store_songs() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for song in PremiumSongCatalog.get_songs():
		var song_id: String = str(song.get("song_id", ""))
		var manifest_song: Dictionary = ContentRegistry.get_song(song_id)
		var merged: Dictionary = song.duplicate(true)
		for key_variant in manifest_song.keys():
			var key: String = str(key_variant)
			merged[key] = manifest_song[key_variant]
		rows.append(merged)
	return rows


func is_premium_song(song_id: String) -> bool:
	return PremiumSongCatalog.is_premium_song(song_id)


func is_song_playable(song_id: String) -> bool:
	if not is_android_store_enabled():
		return true
	if not is_premium_song(song_id):
		return true
	var song: Dictionary = PremiumSongCatalog.get_by_song_id(song_id)
	var product_id: String = str(song.get("product_id", ""))
	return _purchased_ids.has(product_id)


func get_song_badge(song_id: String) -> String:
	if not is_android_store_enabled() or not is_premium_song(song_id):
		return ""
	return "OWNED" if is_song_playable(song_id) else "PREMIUM"


func get_song_store_message(song_id: String) -> String:
	if is_song_playable(song_id):
		return ""
	var song: Dictionary = PremiumSongCatalog.get_by_song_id(song_id)
	return "Purchase %s in TRACK STORE to play it on Android." % str(song.get("title", "this track"))


func get_display_price(product_id: String) -> String:
	var product: Dictionary = (_products_by_id.get(product_id, {}) as Dictionary).duplicate(true)
	var formatted: String = str(product.get("formatted_price", ""))
	return formatted if not formatted.is_empty() else "BUY"


func is_purchased_product(product_id: String) -> bool:
	return _purchased_ids.has(product_id)


func purchase_product(product_id: String) -> Dictionary:
	if not is_android_store_enabled():
		return {"ok": false, "message": "Track Store is only available on Android."}
	if _plugin == null or not _store_available:
		return {"ok": false, "message": "Google Play Billing is not available yet."}
	_status_message = "Processing purchase..."
	emit_signal("store_changed")
	_plugin.purchaseProduct(product_id)
	return {"ok": true, "message": _status_message}


func restore_purchases() -> Dictionary:
	if not is_android_store_enabled():
		return {"ok": false, "message": "Track Store is only available on Android."}
	if _plugin == null or not _store_available:
		return {"ok": false, "message": "Google Play Billing is not available yet."}
	_status_message = "Restoring purchases..."
	emit_signal("store_changed")
	_plugin.restorePurchases()
	return {"ok": true, "message": _status_message}


func start_audio_preview(song_id: String) -> Dictionary:
	var song: Dictionary = ContentRegistry.get_song(song_id)
	var audio_path: String = str(song.get("audio_path", ""))
	if audio_path.is_empty():
		return {"ok": false, "message": "Audio preview is unavailable for this song."}
	stop_audio_preview()
	if not AudioSync.load_stream(audio_path):
		return {"ok": false, "message": "Failed to load preview audio."}
	AudioSync.play_from_start()
	_preview_token += 1
	var token := _preview_token
	get_tree().create_timer(PREVIEW_SECONDS).timeout.connect(func() -> void:
		if token == _preview_token:
			stop_audio_preview()
	)
	return {"ok": true, "message": "Playing 60-second audio preview."}


func stop_audio_preview() -> void:
	_preview_token += 1
	AudioSync.stop_playback()


func _setup_android_billing() -> void:
	if _plugin != null:
		return
	if not Engine.has_singleton(BILLING_SINGLETON):
		_status_message = "Store unavailable — billing plugin not found."
		emit_signal("store_changed")
		return
	_plugin = Engine.get_singleton(BILLING_SINGLETON)
	if not _plugin.billing_setup_finished.is_connected(_on_billing_setup_finished):
		_plugin.billing_setup_finished.connect(_on_billing_setup_finished)
	if not _plugin.products_loaded.is_connected(_on_products_loaded):
		_plugin.products_loaded.connect(_on_products_loaded)
	if not _plugin.entitlements_updated.is_connected(_on_entitlements_updated):
		_plugin.entitlements_updated.connect(_on_entitlements_updated)
	if not _plugin.purchase_finished.is_connected(_on_purchase_finished):
		_plugin.purchase_finished.connect(_on_purchase_finished)
	_loading_products = true
	_status_message = "Loading store..."
	emit_signal("store_changed")
	_plugin.startConnection()


func _query_products() -> void:
	if _plugin == null:
		return
	_loading_products = true
	_plugin.queryProducts(JSON.stringify(PremiumSongCatalog.get_product_ids()))
	emit_signal("store_changed")


func _on_billing_setup_finished(success: bool, message: String) -> void:
	_setup_complete = true
	_store_available = success
	_status_message = message
	if success:
		_query_products()
	else:
		_loading_products = false
	emit_signal("store_changed")


func _on_products_loaded(products_json: String) -> void:
	_loading_products = false
	_products_by_id.clear()
	var parsed: Variant = JSON.parse_string(products_json)
	if parsed is Array:
		for product_variant in parsed:
			if product_variant is Dictionary:
				var product: Dictionary = (product_variant as Dictionary).duplicate(true)
				_products_by_id[str(product.get("product_id", ""))] = product
	if _products_by_id.is_empty():
		_status_message = "Store unavailable — purchases disabled."
	else:
		_status_message = ""
	emit_signal("store_changed")


func _on_entitlements_updated(ids_json: String) -> void:
	var parsed: Variant = JSON.parse_string(ids_json)
	_purchased_ids.clear()
	if parsed is Array:
		for product_id_variant in parsed:
			_purchased_ids.append(str(product_id_variant))
	ProfileStore.set_purchased_premium_product_ids(_purchased_ids)
	emit_signal("store_changed")


func _on_purchase_finished(status: String, product_id: String, message: String) -> void:
	match status:
		"success":
			if not _purchased_ids.has(product_id):
				_purchased_ids.append(product_id)
				ProfileStore.set_purchased_premium_product_ids(_purchased_ids)
			_status_message = "Purchase successful!"
		"restored":
			_status_message = "Purchases restored."
		"cancelled":
			_status_message = "Purchase cancelled."
		"pending":
			_status_message = "Purchase pending."
		_:
			_status_message = message if not message.is_empty() else "Purchase failed."
	purchase_completed.emit(status, product_id, _status_message)
	emit_signal("store_changed")
