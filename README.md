# MakeupCure

A [Makeup](https://hex.pm/packages/makeup) lexer for the
[Cure](https://cure-lang.org) programming language.

## Supported Cure version

The lexer tracks the surface syntax of Cure as of
**v0.28.0** (see the Cure
[`CHANGELOG.md`](https://github.com/am-kantox/cure/blob/main/CHANGELOG.md)).
Features covered include:

- Container declarations: `mod`, `fn`, `rec`, `type`, `proto`, `impl`, `fsm`,
  `actor`, `sup`, `app`, `proof`.
- Control flow and pattern matching: `if`/`elif`/`else`/`then`, `match`/`when`,
  `for`/`in`, `try`/`catch`/`finally`, `throw`, `return`, `yield`, `end`.
- Dependent-type constructs: `assert_type`, `rewrite`, typed holes (`??`,
  `?name`), implicit arguments, predicate identifiers (`even?`, `is_empty?`).
- FSM / actor / supervisor / application lifecycle callbacks: `on_start`,
  `on_stop`, `on_transition`, `on_enter`, `on_exit`, `on_failure`,
  `on_timer`, `on_message`, `on_phase`.
- Operators: pipe `|>`, string concat `<>`, range `..` / `..=`, Melquiades
  send `<-|` (and its unicode alias `✉`), binary-comprehension generator
  `<-`, bitstring segment specifier `::`, augmented assignment
  `+=` / `-=` / `*=` / `/=`, FSM transitions `--event-->`.
- Literals: integers (including `0xFF`, `0b1010`, digit-grouped), floats,
  booleans, atoms, chars, strings with `#{...}` interpolation, regexes,
  maps `%{...}`, tuples `%[...]`, binaries `<<...>>`.
- Comments: plain `#`, single-line doc `##`, fenced multi-line `###...###`
  (the last two are highlighted as `:string_doc`).

## Installation

Add `makeup_cure` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:makeup_cure, "~> 0.2"}
  ]
end
```

The lexer will be automatically registered in Makeup for
the language name `"cure"` and the file extension `.cure`.

## Usage

Once installed, ExDoc and any other tool using Makeup will automatically
syntax-highlight Cure code blocks (tagged with `cure` as the language).

You can also use it directly:

```elixir
alias Makeup.Lexers.CureLexer
CureLexer.lex("fn add(a: Int, b: Int) -> Int = a + b")
```

## License

MIT—see [LICENSE](LICENSE) for details.
