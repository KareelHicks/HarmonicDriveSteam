extends RefCounted
class_name RelayConfig

const DEFAULT_RELAY_BASE_URL := "https://outstanding-motivation-production-bbe4.up.railway.app"
const DEFAULT_REALTIME_BASE_URL := "wss://outstanding-motivation-production-bbe4.up.railway.app"
const DEFAULT_BASE_URL := "%s/api/v1" % DEFAULT_RELAY_BASE_URL


static func base_url() -> String:
	var configured: Variant = ProjectSettings.get_setting("harmonic_drive/relay/base_url", DEFAULT_BASE_URL)
	return str(configured).strip_edges().trim_suffix("/")


static func realtime_base_url() -> String:
	var configured: Variant = ProjectSettings.get_setting("harmonic_drive/relay/realtime_base_url", DEFAULT_REALTIME_BASE_URL)
	return str(configured).strip_edges().trim_suffix("/")


static func request_timeout_seconds() -> float:
	var configured: Variant = ProjectSettings.get_setting("harmonic_drive/relay/request_timeout_seconds", 20.0)
	return float(configured)


static func polling_interval_seconds() -> float:
	var configured: Variant = ProjectSettings.get_setting("harmonic_drive/relay/poll_interval_seconds", 3.0)
	return float(configured)


static func classic_default_difficulty() -> String:
	var configured: Variant = ProjectSettings.get_setting("harmonic_drive/relay/classic_default_difficulty", "Medium")
	return str(configured)
