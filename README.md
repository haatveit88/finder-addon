# /Finder
**/Finder** is a World of Warcraft AddOn that lets you search for any item in the game, and show an item link for it.

[![Download Latest](https://img.shields.io/badge/dynamic/json.svg?label=download%20latest&url=https%3A%2F%2Fapi.github.com%2Frepos%2FHaatveit88%2Ffinder-addon%2Freleases%2Flatest&query=%24.assets[0].name&style=for-the-badge)](https://github.com/Haatveit88/finder-addon/releases/latest/download/Finder.zip)

# Installation
Installs like any WoW addon, if you are unsure of the process, these are the quick steps:

1. Download latest release (link above).
2. Unzip the .zip file anywhere, you should end up with a folder named `Finder`
3. Copy (or move) the `Finder` folder to your AddOns directory: `World of Warcraft\_VERSION_\Interface\AddOns`
4. MAKE SURE that the name of the folder is `Finder`, rename it if needed (for example, if you downloaded the GitHub source zip file, it will be named `finder-master` after extracting).

Replace `_VERSION_` with the version of WoW you are installing to, either `_classic_` or `_retail_`.

**/Finder** should be enabled by default, but double-check your addon list when you start the game.

On login, you should see a welcome message from **/Finder**, although it may get lost in the spam of other AddOn login messages!

Type `/finder` for a quick help message to get started. For more info, see the rest of this Readme.

# Usage
(Make sure you've *built your item cache first*, see [Cache](#cache) down below for how that works.)

Using **/Finder** is super easy, all you need to do is type
`/find <search term>` or `/search <search term>`, and the addon will spit out some search results in your chat window. These are just 2 different commands that do the same thing, use whichever seems more natural to you!

Right now, the addon won't print more than `20` results. Try narrowing down the search if you get that many.

In the future, this might be configurable, or somehow more interactive!

The `<search term>` can be anything you want, including spaces. The search term is NOT case-sensitive, everything is converted to lowercase.

Finally, the search is looking for an exact partial match - it does not account for mis-spellings.

For example:

`/search searing arrw` will NOT find [\[Bow of Searing Arrows\]](https://classic.wowhead.com/item=2825/bow-of-searing-arrows)

however

`/search searing arr` WILL find [\[Bow of Searing Arrows\]](https://classic.wowhead.com/item=2825/bow-of-searing-arrows)

Hopefully in the future I will add fuzzy searching, allowing for missing or mis-typed letters!

# Cache
Before you use **/Finder** for the first time, you have to build the item cache it uses for searching. This is simple, automatic, and happens in the background!
To strigger a cache rebuild, simply type:

`/finder rebuild`  (Notice the slash command here is `/finder`, not `/find`!)

**/Finder** will then request from the server and store information about every item in the game, one by one. This should take about 4 minutes by default (see [Config](#configuration)). The reason it takes a long time is because WoW servers will disconnect any client making too many requests per second, so it has to be done more slowly! The rebuild process will tell you when it's finished.

If the rebuild progress updates are annoying you, you can mute them using `/finder hush`, this will mute (or unmute) the messages for this particular rebuild. It will always tell you when it's done, regardless of mute status.

You can actually use `/find` or `/search` immediately, however until the rebuild is completed, the search results may be incomplete, or empty alltogether.

Finally, you can stop the current rebuild using `/finder stop/abort/cancel`. This will immediately stop the rebuild, leaving it partially complete. Unfortunately, for now, there's no way to resume it, and you have to start over to complete it. The addon will complain about an incomplete cache until you do a complete rebuild!

**Please note:** You absolutely *must* rebuild the cache after any major game updates, since these often add or remove items. The cache has no way to maintain itself, so you must remember to rebuild it after a big update (like a content patch). In the future, **/Finder** might be able to detect major updates, and slowly rebuild itself in the background. For now, that's on you!

# Configuration
**/Finder** allows some configuration options and various commands through the `/finder` command, however most features available are undocumented for now, sorry.
Here are a few:

* `/finder set <option> <value>` allows you to change some configuration options. Right now, only 3 options are exposed:
    * `<progressinterval> <2500>` - this sets how many item requests to complete, before posting a progress update message to the chat window.
    * `<speed> <slow>` - some presets for rebuild speed. Valid options are:
        * `glacial = 50 items/sec`
        * `slow = 100 items/sec`
        * `normal = 250 items/sec`
        * `fast = 500 items/sec`
        * `insane = 1000 items/sec` *Possible disconnect risk, massive frame drops!*
        * `custom = <custombatchsize>` *See below*
    * `<custombatchsize> <50>` - this sets how many item requests the rebuild process makes per second, *ONLY if you are using the "custom" speed option above*
    * The default speed is `slow`, becuase it has a very minor effect on game performance, and finishes relatively quickly (~250 seconds). Feel free to experiment. Faster speeds are potentially *much* faster, but your client *will* stutter once per second while doing it.
* `/finder wipe` allows you to wipe out the item cache. Pay attention to the messages, as you have to type this command TWICE in a row, to actually wipe the cache. This is to avoid accidents!
* `/finder wipesettings` - this will wipe out the per-character configuration options, such as `speed` and `progressinterval` (see above)
* `/finder status` - this will tell you whether **/Finder** believes its item cache is healthy or not. Emphasis on *believes*...
* `/finder <invalid command>` - any invalid command will just trigger the quick help message, just like typing `/finder`.

# Why / how?

**/Finder** builds a cache of *all items in the game* that it then uses for searching. This might sound excessive, however it is required because World of Warcraft does not actually offer a simple way to search / query the servers for an item, by its name. The game only allows direct queries about `itemID`'s, which are just numbers, and not very helpful. Therefore, to actually search the game for an item using its plain text item name, a database needs to be built from the ground up. And that's exactly what **/Finder** does when it `/finder rebuild`s the cache.

Right now, **/Finder** also stores the actual whole itemLink in the cache, so that it can be immediately posted when a search hit is made, in the future I might avoid this (and massively reduce the SavedVariable file size) since I don't think it's necessary, I just didn't want to write code to get the link on the fly.
