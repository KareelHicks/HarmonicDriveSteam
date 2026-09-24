# GodotSteam Server for GDExtension | Community Edition
An ecosystem of tools for [Godot Engine](https://godotengine.org) and [Valve's Steam](https://store.steampowered.com). For the Windows, Linux, and Mac platforms.


Additional Flavors
---
Standard Module | Standard Plug-ins | Server Module | Server Plug-ins | Examples
--- | --- | --- | --- | ---
[Godot 2.x](https://codeberg.org/godotsteam/godotsteam/src/branch/godot2) | [GDNative](https://codeberg.org/godotsteam/godotsteam/src/branch/gdnative) | [Server 3.x](https://codeberg.org/godotsteam/godotsteam-server/src/branch/godot3) | [GDNative](https://codeberg.org/godotsteam/godotsteam-server/src/branch/gdnative) | [Skillet](https://codeberg.org/godotsteam/skillet)
[Godot 3.x](https://codeberg.org/godotsteam/godotsteam/src/branch/godot3) | [GDExtension](https://codeberg.org/godotsteam/godotsteam/src/branch/gdextension) | [Server 4.x](https://codeberg.org/godotsteam/godotsteam-server/src/branch/godot4) | [GDExtension](https://codeberg.org/godotsteam/godotsteam-server/src/branch/gdextension) | [Skillet UGC Editor](https://codeberg.org/godotsteam/skillet/src/branch/ugc_editor)
[Godot 4.x](https://codeberg.org/godotsteam/godotsteam/src/branch/godot4) | --- | --- | --- | ---
[MultiplayerPeer](https://codeberg.org/godotsteam/multiplayerpeer)| --- | --- | --- | ---


Documentation
---
[Documentation is available here](https://godotsteam.com/). You can also check out the Search Help section inside Godot Engine. [To start, try checking out our tutorial on initializing Steam.](https://godotsteam.com/tutorials/initializing/) There are additional tutorials, with more in the works. You can also [check out additional Godot and Steam related videos, text, additional tools, plug-ins, etc. here.](https://godotsteam.com/resources/external/)

Feel free to chat with us about GodotSteam or ask for assistance on the [Stoat server](https://stt.gg/9DxQ3Dcd) or [IRC on Libera Chat](irc://irc.libera.chat/#godotsteam).


Donate
---
Pull-requests are the best way to help the project out but you can also donate through [Github Sponsors](https://github.com/sponsors/Gramps) or [LiberaPay](https://liberapay.com/godotsteam/donate)! [You can read more about donor perks here.](https://godotsteam.com/contribute/donations/)  [You can also view all our awesome donors here.](https://godotsteam.com/contribute/donors/)


Current Build
---
You can [download pre-compiled versions of this repo here](https://codeberg.org/godotsteam/godotsteam-server/releases).

**Version 4.9.1 Changes**

- Fixed: dock scripts for Godot 4.4.x to 4.5.x
- Fixed: Project Settings for internal callbacks using wrong path

[You can read more change-logs here](https://godotsteam.com/changelog/server_gdextension/).


Compatibility
---
While rare, sometimes Steamworks SDK updates will break compatilibity with older GodotSteam versions. Any compatability breaks are noted below. API files (dll, so, dylib) _should_ still work for older version.

Steamworks SDK Version | GodotSteam Server Version
---|---
1.63 or newer | 4.8 or newer
1.59 or newer | 4.2 to 4.7.2
1.58a or older | 4.1 or older

Versions of GodotSteam Server that have compatibility breaks introduced.

GodotSteam Server Version | Broken Compatibility
---|---
4.3| Networking identity system removed, replaced with Steam IDs
4.4 | sendMessages returns an Array
4.5.1 | getItemDefinitionProperty return a dictionary
4.7 | Variety of small break points, refer to [4.7 changelog for details](https://godotsteam.com/changelog/server_gdextension/)
4.8 | Windows projects using Steam SDK 1.63 are meant to work with Proton 11 or Experimental on Linux / Steam Deck.


Known Issues
---
- GDExtension for 4.4 is **not** compatible with 4.3.x or lower. Please check the versions you are using.
- Steam overlay will not work when running your game from the editor if you are using Forward+ as the renderer.  It does work with Compatibility though.  Your exported project will work perfectly fine in the Steam client, however.


Quick How-To
---
For complete instructions on how to build the GDExtension version of GodotSteam Server from scratch, [please refer to our documentation's 'How-To Modules' section.](https://godotsteam.com/howto/gdextension/) It will have the most up-to-date information.

Alternatively, you can just [download the pre-compiled versions in our Releases section](https://codeberg.org/godotsteam/godotsteam-server/releases) or [from the Godot Asset Library](https://godotengine.org/asset-library/asset/2218) and skip compiling it yourself!


Usage
---
Once the plug-in is added to your project, the Steam class should be available and ready to go. Enabling the plug-in in the ProjectSettings only affects the Steamworks dock and not the actual functionality.

Do not use the GDExtension version of GodotSteam Server with any of the module versions whether it be our pre-compiled versions or ones you compile.  They are not compatible with each other.

When exporting with the GDExtension version, please use the normal Godot Engine templates instead of our GodotSteam Server templates or you will have a lot of issues.


No LLM Policy / No "AI" Policy
---
No LLMs are allowed to be used for issues, patches, or pull-requests.  They will be closed or rejected and the submitter may be blocked from future submissions.


License
---
MIT license
