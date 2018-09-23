# wtf.bash

Unified help for your shell (as long as your shell is bash).

## Installation

1. Run `bash --version` and make sure it's 4.0 or newer.
2. Configure your emulator to use a [Powerline font][font] 
   **or** set `HV_DISABLE` to `"true"` in your environment.
3. Clone this repo somewhere.
4. Add `. ~/somewhere/wtf.bash/wtf.bash` to your `.bashrc`.

[font]: https://github.com/powerline/fonts

## Usage

**`wtf`** unifies features from `type`, `which`, `help`, `whatis`, `apropos`, 
`declare` and other built-in ways to get information about your shell and its
environment. Inspect anything you'd expect---functions, commands, files---and
a few you might not---variables, shell builtins and keywords, even jobs managed
by the shell.

It has no dependencies (except bash 4.0 or newer), and comes with `HVDC`,
a blazing fast reimplementation of Powerline in &lt;200 lines of pure bash.
Which is to say, it's gorgeous:

<img src="https://raw.githubusercontent.com/zgracem/wtf.bash/master/screenshots/basic.png" width="640" height="470">

## Say hello

[zgm&#x40;inescapable&#x2e;org](mailto:zgm%40inescapable%2eorg)
