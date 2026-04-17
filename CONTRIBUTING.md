# Contributing to Perspective Cuts

This is a highly experimental project. I appreciate contributions but want to set expectations.

## Before You Start

This project is in active development. Things change fast. If you want to contribute, open an issue first so we can talk about it before you write code. I do not want anyone wasting their time on something that conflicts with where the project is heading.

## What I Need Help With

- **Action verification.** There are 180+ actions in the registry. Only 35 have been tested end-to-end. If you can test actions and report results, that is valuable.
- **The changeCase keyword conflict.** The word `case` is a parser keyword. The `changeCase` action cannot be used. This needs a parser fix.
- **Enum parameter discovery.** Some actions use enum dropdowns that need special serialization (integers instead of strings, like `useModel`). Finding and documenting these is useful.
- **New actions.** If Apple ships new actions or you find third party actions that need registry entries, submit them.

## How to Contribute

1. Fork the repo
2. Create a branch for your change
3. Make your changes
4. Test by compiling a shortcut that uses the affected action
5. Open a PR with a description of what you changed and how you tested it

## Code Style

- This is a Swift project. Follow Swift conventions.
- Keep it simple. The compiler is intentionally straightforward.
- Do not add dependencies unless absolutely necessary.

## Testing

There is no automated test suite yet. Testing means:

1. Write a `.perspective` file that uses the action or feature you changed
2. Compile it with `swift run perspective-cuts compile --sign your-test.perspective`
3. Import it into the Shortcuts app
4. Run it and confirm it works

The `Examples/full-test-suite.perspective` file tests 35 actions at once. You can add tests there.

## What I Will Not Accept

- Changes that add non-Apple dependencies or frameworks
- Changes that use third party signing tools
- Changes that break existing working actions without a fix
- PRs without testing

## AI Contributions Are Welcome

AI-generated contributions are welcome here. You do not need to apologize for your tooling.

We use AI on this project ourselves. The way we like to work is what we call partner coding. A human and an AI write code together, and a human reviews what comes out. If you have a basic understanding of what the code does and why, we are very happy to work with you on it. And honestly, even if you do not fully understand every line yet, we are still willing to review it with you. We believe in helping people learn how to code and in building a community around that, not gatekeeping based on how the keystrokes got typed.

No PRs will be closed here for being AI-assisted. Bring them.

## Questions

Open an issue. I will get back to you.
