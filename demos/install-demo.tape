Output demos/install.gif

Set Shell "zsh"
Set FontSize 16
Set Width 1000
Set Height 650
Set Theme "Dracula"
Set Padding 20
Set TypingSpeed 40ms

# Install steps (simulated — brew takes too long for recording)
Type `echo '$ brew tap taylorarndt/tap'`
Enter
Sleep 500ms
Type `echo '==> Tapping taylorarndt/tap'`
Enter
Type `echo 'Tapped 1 formula (14 files, 11KB).'`
Enter
Sleep 1.5s

Type `echo ''`
Enter
Type `echo '$ brew install perspective-cuts'`
Enter
Sleep 500ms
Type `echo '==> Installing perspective-cuts from taylorarndt/tap'`
Enter
Type `echo '==> swift build -c release --disable-sandbox'`
Enter
Type `printf '\xF0\x9F\x8D\xBA /opt/homebrew/Cellar/perspective-cuts/0.2.0: 7 files, 1.9MB\n'`
Enter
Sleep 2s

# Real commands
Type `echo ''`
Enter
Type "perspective-cuts --version"
Enter
Sleep 1.5s

Type `echo ''`
Enter
Type "perspective-cuts discover openai"
Enter
Sleep 3s

Type `echo ''`
Enter
Type "perspective-cuts detail com.openai.chat.AskIntent"
Enter
Sleep 4s

# Compile a shortcut
Type `echo ''`
Enter
Type `printf 'import Shortcuts\n#name: Hello World\ntext(text: "Hello from Perspective Cuts!") -> greeting\nshowResult(text: greeting)\n' > /tmp/demo.perspective && cat /tmp/demo.perspective`
Enter
Sleep 2s

Type `echo ''`
Enter
Type "perspective-cuts compile /tmp/demo.perspective -o /tmp/demo.shortcut"
Enter
Sleep 2s

Type "ls -lh /tmp/demo.shortcut"
Enter
Sleep 3s
