extends RefCounted
class_name PremiumSongCatalog

const SONGS: Array[Dictionary] = [
	{
		"title": "Fade Into Forever",
		"artist": "Dj Iatneh",
		"file_name": "Fade Into Forever - Dj Iatneh",
		"chart_name": "Fade Into Forever",
		"song_id": "fade_into_forever",
		"product_id": "harmonic.fade_into_forever",
	},
	{
		"title": "Flowing Emotions",
		"artist": "Dj Iatneh",
		"file_name": "Flowing Emotions - Dj Iatneh",
		"chart_name": "Flowing Emotions",
		"song_id": "flowing_emotions",
		"product_id": "harmonic.flowing_emotions",
	},
	{
		"title": "Hold On To the Light",
		"artist": "Dj Iatneh",
		"file_name": "Hold On To the Light - Dj Iatneh",
		"chart_name": "Hold On To the Light",
		"song_id": "hold_on_to_the_light",
		"product_id": "harmonic.hold_on_to_the_light",
	},
	{
		"title": "I Found Your Name Inside A Notebook",
		"artist": "Dj Iatneh",
		"file_name": "I Found Your Name Inside A Notebook - Dj Iatneh",
		"chart_name": "I Found Your Name Inside A Notebook",
		"song_id": "i_found_your_name_inside_a_notebook",
		"product_id": "harmonic.found_your_name2",
	},
	{
		"title": "I Still Choose You",
		"artist": "Dj Iatneh",
		"file_name": "I Still Choose You - Dj Iatneh",
		"chart_name": "I Still Choose You",
		"song_id": "i_still_choose_you",
		"product_id": "harmonic.still_choose_you",
	},
	{
		"title": "Innerself v2",
		"artist": "Dj Iatneh",
		"file_name": "Innerself v2 - Dj Iatneh",
		"chart_name": "Innerself v2",
		"song_id": "innerself_v2",
		"product_id": "harmonic.innerself_v2",
	},
	{
		"title": "Lightwalk",
		"artist": "Dj Iatneh",
		"file_name": "Lightwalk - Dj Iatneh",
		"chart_name": "Lightwalk",
		"song_id": "lightwalk",
		"product_id": "harmonic.lightwalk2",
	},
	{
		"title": "Neon Horizon",
		"artist": "Dj Iatneh",
		"file_name": "Neon Horizon - Dj Iatneh",
		"chart_name": "Neon Horizon",
		"song_id": "neon_horizon",
		"product_id": "harmonic.neon_horizon",
	},
	{
		"title": "Open Skies",
		"artist": "Dj Iatneh",
		"file_name": "Open Skies - Dj Iatneh",
		"chart_name": "Open Skies",
		"song_id": "open_skies",
		"product_id": "harmonic.open_skies",
	},
	{
		"title": "Right Now",
		"artist": "Dj Iatneh",
		"file_name": "Right Now - Dj Iatneh",
		"chart_name": "Right Now",
		"song_id": "right_now",
		"product_id": "harmonic.right_now",
	},
	{
		"title": "Say It",
		"artist": "Dj Iatneh",
		"file_name": "Say It - Dj Iatneh",
		"chart_name": "Say It",
		"song_id": "say_it",
		"product_id": "harmonic.say_it",
	},
	{
		"title": "Skyline Motion",
		"artist": "Dj Iatneh",
		"file_name": "Skyline Motion - Dj Iatneh",
		"chart_name": "Skyline Motion",
		"song_id": "skyline_motion",
		"product_id": "harmonic.skyline_motion",
	},
	{
		"title": "Space Drift",
		"artist": "Dj Iatneh",
		"file_name": "Space Drift - Dj Iatneh",
		"chart_name": "Space Drift",
		"song_id": "space_drift",
		"product_id": "harmonic.space_drift",
	},
	{
		"title": "Sunny",
		"artist": "Dj Iatneh",
		"file_name": "Sunny - Dj Iatneh",
		"chart_name": "Sunny",
		"song_id": "sunny",
		"product_id": "harmonic.sunny",
	},
	{
		"title": "Tenacity",
		"artist": "Dj Iatneh",
		"file_name": "Tenacity - Dj Iatneh",
		"chart_name": "Tenacity",
		"song_id": "tenacity",
		"product_id": "harmonic.tenacity",
	},
	{
		"title": "We Were Infinite",
		"artist": "Dj Iatneh",
		"file_name": "We Were Infinite - Dj Iatneh",
		"chart_name": "We Were Infinite",
		"song_id": "we_were_infinite",
		"product_id": "harmonic.we_were_infinite",
	},
]


static func get_songs() -> Array[Dictionary]:
	return SONGS.duplicate(true)


static func get_product_ids() -> Array[String]:
	var ids: Array[String] = []
	for song in SONGS:
		ids.append(str(song.get("product_id", "")))
	return ids


static func get_by_product_id(product_id: String) -> Dictionary:
	for song in SONGS:
		if str(song.get("product_id", "")) == product_id:
			return song.duplicate(true)
	return {}


static func get_by_song_id(song_id: String) -> Dictionary:
	for song in SONGS:
		if str(song.get("song_id", "")) == song_id:
			return song.duplicate(true)
	return {}


static func is_premium_song(song_id: String) -> bool:
	return not get_by_song_id(song_id).is_empty()
