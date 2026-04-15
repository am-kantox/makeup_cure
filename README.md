# MakeupCure

A [Makeup](https://hex.pm/packages/makeup) lexer for the
[Cure](https://github.com/Oeditus/cure) programming language.

## Installation

Add `makeup_cure` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:makeup_cure, "~> 0.1"}
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
