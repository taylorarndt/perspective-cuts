# Perspective Language Reference

Perspective is a text-based language for writing Apple Shortcuts. You write code, you compile it, and you get a shortcut you can import and run. No dragging blocks around. No clicking through menus. Just text.

I created this because I wanted an easy and accessible way to create shortcuts through code. The Shortcuts app is visual. It is drag and drop. That does not work for everyone. I wanted to write shortcuts the same way I write Swift code. In a text editor. With a compiler that handles the rest.

Here is the thing. If you know my stance on using Apple official channels, you know where this is going. Perspective Cuts is built in Swift. It uses Swift Package Manager. It runs on macOS. And it uses Apple's own `shortcuts sign` command to sign the output. That is the tool Apple ships with macOS for signing shortcut files. I am not using some third party signing service. I am not wrapping this in Electron or shipping it as a web app. This is a Mac tool for building Apple Shortcuts. Built the right way.

That does mean it only runs on macOS right now. The signing tool lives on Mac. That is where Apple put it. If Apple ever ships a signing tool on iOS, I will support that too. But I am not going to hack around it with unofficial signers. That is not how I do things.

Other tools existed for writing shortcuts as code. JellyCuts was the main one. But the actions were outdated. It did not support iOS 26 actions like Apple Intelligence, Private Cloud Compute, or the new Writing Tools. It did not support third party apps out of the box. And it was not being actively updated to keep up with what Apple was shipping. I wanted to provide a solution that was current, that supported every action Apple ships, and that could use any app installed on your Mac without having to register anything.

That is what Perspective Cuts is. You write `.perspective` files, you compile them, and you get signed `.shortcut` files that work on macOS, iOS, and iPadOS. 180 built-in actions. Any third party app on your Mac. ChatGPT, Drafts, Fantastical, Bear, Things, your own apps. If an app has Shortcuts actions, Perspective can use them. No configuration. No registration. Just write the code and compile.

## Getting Started

Here is a shortcut in Perspective. It asks for your name and says hello.

```
import Shortcuts
#color: blue
#icon: gear
#name: Say Hello

ask(prompt: "What is your name?") -> name
showResult(text: "Hello, \(name)!")
```

To compile and install it:

```bash
perspective-cuts compile --sign say-hello.perspective
open say-hello.shortcut
```

That is it. The Shortcuts app opens, you import it, and it works.

## How It Works

Every file starts with `import Shortcuts`. Then you have optional metadata lines that set the color, icon, and name. Then you write your actions.

Actions look like function calls. You pass labeled arguments and optionally capture the output with `->`.

```
getBattery() -> level
notification(body: "Battery is at \(level)%.", title: "Battery", sound: true)
```

Variables work automatically. When you write `-> level`, the compiler assigns a UUID to that action's output. When you reference `\(level)` later, it wires up the UUID reference in the shortcut plist. You don't think about any of that. You just write the code.

## Metadata

These go at the top of your file after the import.

`#color: purple` sets the icon background. Options: red, orange, yellow, green, teal, lightBlue, blue, darkBlue, purple, pink, darkPink, gray.

`#icon: compose` sets the icon glyph. Options: gear, compose, star, heart, bolt, globe, mic, music, play, camera, photo, film, mail, message, phone, clock, alarm, calendar, map, location, bookmark, tag, folder, doc, list, cart, bag, gift, lock, key, link, flag, bell, eye, hand, person, house, car, airplane, sun, moon, cloud, umbrella, flame, drop, leaf, paintbrush, pencil, scissors, wand, cube, download, upload, share, trash, magnifyingglass.

`#name: My Shortcut` sets the display name. Supports multiple words and apostrophes.

## Value Types

Strings use double quotes: `"hello world"`. They support `\n` for newlines and `\(variable)` for interpolation.

Numbers are just numbers: `42` or `3.14`. Whole numbers compile as integers.

Booleans are `true` or `false`.

## Control Flow

Perspective supports if/else, repeat loops, for-each loops, and menus. These compile to the exact same grouped control flow actions that the Shortcuts app uses.

```
repeat 5 {
    vibrate()
}
```

```
getRSSFeed(url: "https://example.com/feed") -> items
for item in items {
    showResult(text: item)
}
```

```
menu "Pick one" {
    case "Option A" {
        showResult(text: "You picked A")
    }
    case "Option B" {
        showResult(text: "You picked B")
    }
}
```

## Apple Intelligence

This is where it gets interesting. The `useModel` action sends a prompt to Apple Intelligence. You can use the on-device model or Private Cloud Compute.

```
useModel(
    prompt: "Summarize this: \(content)",
    model: "Private Cloud Compute",
    resultType: "Automatic",
    followUp: false
) -> result
```

The model parameter accepts these values:

- `"Apple Intelligence"` or `"On-Device"` for the local model
- `"Private Cloud Compute"` for Apple's cloud model
- `"ChatGPT"` or `"Extension Model"` for OpenAI

The compiler maps these strings to integer values internally. That was a fun discovery. Apple's import process ignores the string. It needs integers. 0 for on-device, 1 for PCC, 2 for ChatGPT. We figured that out by trial and error.

## Third Party Apps

This is the feature I'm most proud of. You can use any installed app's Shortcuts actions directly. No registration. No configuration. Just use the full identifier as the action name.

```
com.openai.chat.AskIntent(prompt: "Explain quantum computing") -> answer
online.techopolis.PerspectiveAI.CreatePerspectiveConversationIntent(initialPrompt: "Hello") -> chat
com.flexibits.fantastical2.addevent(FantasticalEventSentence: "Meeting tomorrow at 3pm")
com.agiletortoise.Drafts4.addto(DraftsInput: "My new draft")
net.shinyfrog.bear-IOS.create(title: "My Note")
com.culturedcode.ThingsTouch.addtask(thingsTask: "Buy groceries")
```

When the compiler sees dots in an action name, it treats it as a raw identifier. Parameters pass through as-is. That is it.

To find what actions are available on your Mac:

```bash
perspective-cuts discover openai
perspective-cuts discover fantastical
perspective-cuts discover --third-party
```

The discover command reads the Shortcuts ToolKit database and shows every available action with its parameters.

## Translation

The translate action works with locale codes. We had a rough time figuring this one out. The issue was the input parameter needed to be a plain string, not wrapped in Apple's WFTextTokenString format. Once we fixed that, it worked perfectly.

```
translateText(input: "Good morning", language: "es_ES", from: "en_US") -> spanish
```

Available languages: ar_AE (Arabic), zh_CN (Chinese Simplified), zh_TW (Chinese Traditional), nl_NL (Dutch), en_GB (English UK), en_US (English US), fr_FR (French), de_DE (German), hi_IN (Hindi), id_ID (Indonesian), it_IT (Italian), ja_JP (Japanese), ko_KR (Korean), pl_PL (Polish), pt_BR (Portuguese), ru_RU (Russian), es_ES (Spanish), th_TH (Thai), tr_TR (Turkish), uk_UA (Ukrainian), vi_VN (Vietnamese).

## CLI Reference

```bash
# Compile to unsigned shortcut
perspective-cuts compile file.perspective

# Compile and sign for import
perspective-cuts compile --sign file.perspective

# Compile and install directly to Shortcuts database
perspective-cuts compile --install file.perspective

# List built-in actions
perspective-cuts actions

# Search actions
perspective-cuts actions weather

# Discover third party app actions
perspective-cuts discover openai
perspective-cuts discover --third-party

# Validate without compiling
perspective-cuts validate file.perspective
```

## Built-in Actions

167 verified actions organized by category. Parameters in parentheses are optional.

### Text and Data
- `text(text)` — Create text
- `showResult(text)` — Display result
- `alert(message, (title), (showCancel))` — Show alert
- `ask(prompt, (default))` — Ask for input
- `comment(text)` — Comment (no effect)
- `nothing()` — Do nothing
- `number(value)` — Create number
- `randomNumber((min), (max))` — Random number
- `calculate(operand, operation)` — Math operation
- `count(Input, (type))` — Count items or characters
- `list(items)` — Create list
- `getItemFromList(input, (specifier), (index))` — Get item by index
- `chooseFromList(input, (prompt), (selectMultiple))` — Choose from list
- `getItemName(input)` — Get item name
- `getItemType(input)` — Get item type
- `dictionary(items)` — Create dictionary
- `getDictionaryValue(input, key)` �� Get value by key
- `setDictionaryValue(key, value)` — Set value

### Text Manipulation
- `replaceText(input, find, replace, (regex), (caseSensitive))` — Find and replace
- `matchText(pattern, text, (caseSensitive))` — Regex match
- `splitText(text, (separator), (customSeparator))` — Split text
- `combineText(text, (separator), (customSeparator))` — Join text
- `changeCase(text, case)` — Change case
- `correctSpelling(input)` — Correct spelling
- `detectLanguage(input)` — Detect language

### Translation
- `translateText(input, language, (from))` — Translate text (use locale codes)

### Web and URLs
- `downloadURL(url, (method), (headers), (bodyType), (body))` — HTTP request
- `getRSSFeed(url, (count))` — Get RSS feed items
- `getArticle(page)` — Extract article content
- `getWebPageContents(input)` — Get web page HTML
- `openURL(url)` — Open in Safari
- `url(url)` — Create URL
- `urlEncode(input, (mode))` — URL encode/decode
- `getLinks(input)` — Extract URLs from text
- `expandURL(input)` — Expand shortened URL
- `getURLHeaders(input)` — Get HTTP headers

### Apple Intelligence
- `useModel(prompt, (model), (resultType), (followUp))` — Prompt AI model
- `summarize(text, (summaryType))` — Summarize (Share Sheet only)
- `rewriteText(input, (tone))` — Rewrite text
- `proofread(input)` — Proofread text
- `createImage(description)` — Image Playground

### Date and Time
- `getCurrentDate()` — Current date/time
- `formatDate(date, (style), (format))` — Format date
- `adjustDate(date, duration, (unit))` — Add/subtract time
- `timeBetweenDates(input, (unit))` — Time between dates
- `getDates(input)` — Extract dates from text
- `wait(seconds)` — Wait

### Calendar and Reminders
- `addNewEvent(title, (startDate), (endDate), (calendar), (location), (notes))` — Create event
- `getUpcomingEvents()` — Get upcoming events
- `findCalendarEvents()` — Find events
- `removeEvents(input)` — Remove events
- `addReminder(title, (dueDate), (notes), (list))` — Create reminder
- `getUpcomingReminders()` — Get upcoming reminders
- `findReminders()` — Find reminders
- `removeReminders(input)` — Remove reminders

### Device
- `getBattery()` — Battery level
- `getDeviceDetail(detail)` — Device info
- `getIPAddress((source), (type))` — IP address
- `getWiFiNetwork()` — Wi-Fi info
- `getCurrentLocation()` — GPS location
- `getCurrentWeather()` — Weather (iOS only)
- `getWeatherForecast()` — Forecast
- `vibrate()` — Vibrate
- `flashlight()` — Toggle flashlight
- `setBrightness(level)` — Set brightness
- `setVolume(level)` — Set volume
- `playSound()` — Play sound

### Communication
- `sendMessage(message, (recipients))` — iMessage/SMS
- `sendEmail(to, (subject), (body))` — Email
- `notification(body, (title), (sound))` — Notification

### Files
- `getFile((SelectMultiple))` — Select file
- `saveFile(input, (path), (overwrite))` — Save file
- `createFolder(path)` — Create folder
- `deleteFiles(input)` — Delete files
- `renameFile(input, name)` — Rename
- `moveFile(input)` — Move file
- `getContentsOfFolder(folder)` — List folder contents
- `makeZip(input)` — Create ZIP
- `unzip(input)` — Extract ZIP

### Media
- `playMusic((music))` — Play music
- `pauseMusic()` — Pause
- `getCurrentSong()` — Current song
- `skipForward()` — Next track
- `skipBack()` — Previous track
- `takePhoto()` — Take photo
- `takeVideo()` — Record video
- `speakText(text, (rate), (pitch), (language), (wait))` — Text to speech
- `getLastScreenshot()` — Last screenshot

### Clipboard and Sharing
- `setClipboard(input)` — Copy to clipboard
- `getClipboard()` — Get clipboard
- `shareSheet(input)` — Share sheet
- `airdrop(input)` — AirDrop
- `print(input)` — Print

### Encoding
- `base64Encode(input, (mode))` — Base64
- `hash(input, (type))` — Hash (MD5, SHA1, etc.)
- `richTextFromHTML(input)` — HTML to rich text
- `richTextFromMarkdown(input)` — Markdown to rich text
- `markdownFromRichText(input)` — Rich text to Markdown

### Toggles
- `setAirplaneMode(OnValue)` — Airplane mode
- `setBluetooth(OnValue)` — Bluetooth
- `setWiFi(OnValue)` — Wi-Fi
- `setCellularData(OnValue)` — Cellular
- `setDoNotDisturb(Enabled)` — DND
- `setLowPowerMode(OnValue)` — Low power

### Shortcuts
- `runShortcut(name, (input), (show))` — Run another shortcut
- `openApp(app)` — Open app
- `exitShortcut((result))` — Stop and output

### SSH
- `runSSHScript(script, host, (port), (user), (password))` — Run SSH command

## For AI Assistants

If you are an AI helping someone write Perspective code, here is what you need to know.

Every `.perspective` file starts with `import Shortcuts`. Metadata uses `#key: value` syntax. Actions are function calls with labeled parameters. Output capture uses `->`. String interpolation uses `\(variableName)`.

For Apple Intelligence, the model parameter must be one of: `"Apple Intelligence"`, `"On-Device"`, `"Private Cloud Compute"`, `"ChatGPT"`, `"Extension Model"`. The compiler handles the integer mapping.

For translate, use locale codes like `es_ES`, `fr_FR`, `ja_JP`. Always include the `from` parameter.

For third party apps, use the full identifier with dots: `com.openai.chat.AskIntent(prompt: "hello")`. Run `perspective-cuts discover <app>` to find identifiers and parameter names.

The `case` keyword is reserved. The `changeCase` action cannot be used until the parser is updated. Use `useModel` as a workaround.

Compile with `perspective-cuts compile --sign file.perspective`. Always use `--sign` for importable shortcuts.

## Tutorials

### Tutorial 1: Your First Shortcut

Create a file called `hello.perspective`:

```
import Shortcuts
#color: blue
#icon: star
#name: Hello World

text(text: "Hello from Perspective!") -> greeting
showResult(text: greeting)
```

Compile and import:

```bash
perspective-cuts compile --sign hello.perspective
open hello.shortcut
```

The Shortcuts app opens. Click Add Shortcut. Run it. You will see "Hello from Perspective!" on screen.

### Tutorial 2: AI-Powered Clipboard Rewriter

This one grabs whatever is on your clipboard, sends it to Private Cloud Compute, and puts the rewritten version back.

```
import Shortcuts
#color: teal
#icon: wand
#name: Rewrite Clipboard

getClipboard() -> clip
useModel(prompt: "Rewrite this to be clearer and more concise:\n\(clip)", model: "Private Cloud Compute", resultType: "Automatic", followUp: false) -> rewritten
setClipboard(input: rewritten)
notification(body: "Clipboard rewritten.", title: "Done", sound: true)
```

Copy some text. Run the shortcut. Paste. The text is rewritten by Apple Intelligence.

### Tutorial 3: RSS Feed Summarizer

This pulls your latest blog posts and summarizes them with Private Cloud Compute.

```
import Shortcuts
#color: purple
#icon: compose
#name: Feed Summarizer

getRSSFeed(url: "https://your-blog.com/feed", count: 5) -> items
useModel(prompt: "Summarize each article in 3 bullet points:\n\(items)", model: "Private Cloud Compute", resultType: "Automatic", followUp: false) -> summary
showResult(text: summary)
```

Replace the URL with your own RSS feed.

### Tutorial 4: Multi-Language Translator

Translate text into multiple languages at once.

```
import Shortcuts
#color: green
#icon: globe
#name: Multi Translate

ask(prompt: "Enter text to translate") -> input
translateText(input: input, language: "es_ES", from: "en_US") -> spanish
translateText(input: input, language: "fr_FR", from: "en_US") -> french
translateText(input: input, language: "ja_JP", from: "en_US") -> japanese
showResult(text: "Spanish: \(spanish)\n\nFrench: \(french)\n\nJapanese: \(japanese)")
```

### Tutorial 5: Using Third Party Apps

Find what actions are available, then use them.

```bash
perspective-cuts discover --third-party
```

Pick an app and write a shortcut:

```
import Shortcuts
#color: darkBlue
#icon: message
#name: Ask AI

ask(prompt: "What do you want to know?") -> question
online.techopolis.PerspectiveAI.CreatePerspectiveConversationIntent(initialPrompt: question) -> answer
showResult(text: answer)
```

The full identifier is the action name. Parameters use the plist key names shown by the discover command.

### Tutorial 6: Morning Briefing

Combine multiple data sources and let AI summarize them.

```
import Shortcuts
#color: orange
#icon: sun
#name: Morning Briefing

getCurrentDate() -> today
getUpcomingEvents() -> events
getBattery() -> battery
useModel(prompt: "Give me a quick morning briefing.\n\nDate: \(today)\nEvents: \(events)\nBattery: \(battery)%", model: "Private Cloud Compute", resultType: "Automatic", followUp: false) -> briefing
showResult(text: briefing)
```

### Tutorial 7: API Request and Parse

Hit any API endpoint and work with the data. This grabs a random programming quote from GitHub.

```
import Shortcuts
#color: lightBlue
#icon: download
#name: Random Wisdom

downloadURL(url: "https://api.github.com/zen") -> wisdom
getCurrentDate() -> now
formatDate(date: now, style: "Medium") -> date
text(text: "\(date)\n\n\(wisdom)") -> result
setClipboard(input: result)
notification(body: "Wisdom copied to clipboard", title: "Daily Wisdom", sound: true)
```

The `downloadURL` action works with any URL. It returns the response body. For JSON APIs you can pass it to `getDictionaryValue` to extract specific fields.

### Tutorial 8: Battery Monitor with Notification

Check your battery and get a notification with the level. This is useful to run on a schedule through Shortcuts automations.

```
import Shortcuts
#color: red
#icon: bolt
#name: Battery Monitor

getBattery() -> level
getDeviceDetail(detail: "Device Name") -> device
notification(body: "\(device) is at \(level)%", title: "Battery Report", sound: true)
```

### Tutorial 9: Text Processing Pipeline

Chain multiple text operations together. This takes comma-separated input, splits it, joins with line breaks, and copies it.

```
import Shortcuts
#color: yellow
#icon: doc
#name: CSV to Lines

ask(prompt: "Enter comma-separated items") -> input
splitText(text: input, separator: "Custom", customSeparator: ",") -> items
combineText(text: items, separator: "Custom", customSeparator: "\n") -> lines
setClipboard(input: lines)
notification(body: "Converted and copied", title: "CSV to Lines", sound: true)
```

The `splitText` and `combineText` actions are the workhorses for text manipulation. When you set `separator` to `"Custom"`, you provide the actual separator in `customSeparator`. Other separator options include `"New Lines"` and `"Every Character"`.

### Tutorial 10: Encode and Hash

Work with encoding and hashing. Useful for developer tools and quick lookups.

```
import Shortcuts
#color: gray
#icon: lock
#name: Encode and Hash

ask(prompt: "Enter text to encode") -> input
base64Encode(input: input, mode: "Encode") -> b64
hash(input: input, type: "SHA256") -> sha
urlEncode(input: input, mode: "Encode") -> urlenc
showResult(text: "Base64: \(b64)\n\nSHA256: \(sha)\n\nURL Encoded: \(urlenc)")
```

The `hash` action supports MD5, SHA1, SHA256, and SHA512. The `base64Encode` action has two modes: `"Encode"` and `"Decode"`. The `urlEncode` action also has `"Encode"` and `"Decode"`.

### Tutorial 11: AI Word Definer

Ask for a word and get a full definition from Private Cloud Compute.

```
import Shortcuts
#color: darkBlue
#icon: magnifyingglass
#name: Define Word

ask(prompt: "Enter a word to define") -> word
useModel(prompt: "Define '\(word)' in plain English. Give the definition, part of speech, and use it in a sentence.", model: "Private Cloud Compute", resultType: "Automatic", followUp: false) -> definition
showResult(text: definition)
```

This is a good example of how powerful the `useModel` action is. You can give it any prompt and it returns text. Combined with `ask` for user input, you can build interactive AI-powered tools.

### Tutorial 12: Network Info

Get your device's network details at a glance.

```
import Shortcuts
#color: teal
#icon: globe
#name: Network Info

getIPAddress() -> ip
getWiFiNetwork() -> wifi
getDeviceDetail(detail: "Device Name") -> device
showResult(text: "Device: \(device)\nIP: \(ip)\nWi-Fi: \(wifi)")
```

## Understanding Variables

This is important. In Perspective, variables are created when you capture an action's output with `->`. That is the only way to create them.

```
getBattery() -> level
```

This runs `getBattery()` and stores the result in `level`. Under the hood, the compiler assigns a UUID to this action and creates a `WFTextTokenString` reference with an `attachmentsByRange` entry pointing to that UUID. You don't need to know any of that. You just write `-> level` and reference it with `\(level)`.

Variables are available to all actions that come after them. There is no scoping. If you define `-> level` on line 5, you can use `\(level)` on line 50. The compiler tracks all UUIDs and wires them correctly.

You can also use variables as direct arguments without interpolation:

```
getBattery() -> level
showResult(text: level)
```

This passes the raw variable reference. When you use `\(level)` inside a string, it embeds the variable in an interpolated text token. Both work, but interpolation is more common because you usually want to combine variables with other text.

## Understanding Parameter Types

Not all parameters are created equal. This is one of the things we discovered during development. Some parameters need to be wrapped in Apple's `WFTextTokenString` format. Others need to be plain strings. And some need to be integers.

The compiler handles this automatically based on the parameter type in the registry:

- `string` — Wrapped in WFTextTokenString. This is the default. Variables work with interpolation.
- `plainString` — Sent as a plain string. Used for URLs, locale codes, and enum-like values.
- `enum` — Sent as a plain string. Used for dropdown values.
- `enumInt` — Mapped from a human-readable string to an integer. Used for useModel's model parameter.
- `boolean` — Sent as true/false.
- `number` — Sent as an integer or decimal.
- `variable` — Sent as a variable reference.

You don't need to think about this when writing shortcuts. The compiler knows what each parameter needs. But if you are adding new actions to the registry or debugging why a parameter is being ignored, this is what to check.

## Verified Test Results

35 actions tested end-to-end on macOS 26.4 (Apple M2). All compiled, signed, imported, and executed successfully.

Text: text, number, randomNumber, calculate, url, count, getItemName, getItemType
Text Manipulation: replaceText, splitText, combineText
Date: getCurrentDate, formatDate
Device: getBattery, getIPAddress, getDeviceDetail, getWiFiNetwork
Web: downloadURL, getRSSFeed, urlEncode
Clipboard: getClipboard, setClipboard
Encoding: base64Encode, hash
Calendar: getUpcomingEvents, getUpcomingReminders
Translation: translateText (Spanish, French, Japanese)
AI: useModel (Private Cloud Compute)
Communication: notification
Media: speakText
Shortcuts: wait, comment, nothing

Plus third party app actions via raw identifiers (Perspective Intelligence, ChatGPT).

## Known Limitations

- `changeCase` cannot be used because `case` is a parser keyword. Will be fixed.
- `getCurrentWeather` is iOS only. Does not work on macOS.
- Unlabeled arguments are silently dropped. Always use `label: value`.
- 13 legacy actions have unverified identifiers on macOS 26.
- Some third party apps require being logged in within the app for their actions to work.

## Credits

I built Perspective Cuts myself. The language, the compiler, the action registry, all of it. I used Claude Code throughout the process. If you have questions or want to contribute, reach out.
