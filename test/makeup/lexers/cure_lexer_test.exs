defmodule Makeup.Lexers.CureLexerTest do
  use ExUnit.Case, async: true

  alias Makeup.Lexers.CureLexer

  defp lex_no_ws(string) do
    string
    |> CureLexer.lex()
    |> Enum.reject(fn {type, _, _} -> type == :whitespace end)
  end

  defp token_types(string) do
    string |> lex_no_ws() |> Enum.map(&elem(&1, 0))
  end

  # -- Comments -----------------------------------------------------------

  describe "comments" do
    test "single-line comment" do
      assert [{:comment_single, _, _value}] = lex_no_ws("# hello world")
    end

    test "comment preserves content" do
      [{:comment_single, _, value}] = lex_no_ws("# this is a comment")
      text = IO.iodata_to_binary(List.wrap(value))
      assert text =~ "this is a comment"
    end
  end

  # -- Keywords -----------------------------------------------------------

  describe "declaration keywords" do
    test "mod is a keyword_declaration" do
      assert [:keyword_declaration] = token_types("mod")
    end

    test "fn is a keyword_declaration" do
      assert [:keyword_declaration] = token_types("fn")
    end

    test "type is a keyword_declaration" do
      assert [:keyword_declaration] = token_types("type")
    end

    test "proto, impl, fsm are keyword_declarations" do
      for kw <- ~w(proto impl fsm let rec local use as extern) do
        assert [:keyword_declaration] = token_types(kw),
               "expected #{kw} to be keyword_declaration"
      end
    end
  end

  describe "control keywords" do
    test "if, else, then, match etc." do
      for kw <-
            ~w(if elif else then match when where for do in try catch finally throw return yield) do
        assert [:keyword] = token_types(kw), "expected #{kw} to be keyword"
      end
    end
  end

  describe "concurrency keywords" do
    test "spawn, send, receive, after" do
      for kw <- ~w(spawn send receive after) do
        assert [:keyword] = token_types(kw), "expected #{kw} to be keyword"
      end
    end
  end

  describe "constant keywords" do
    test "true, false, nil" do
      for kw <- ~w(true false nil) do
        assert [:keyword_constant] = token_types(kw), "expected #{kw} to be keyword_constant"
      end
    end
  end

  describe "word operators" do
    test "and, or, not" do
      for kw <- ~w(and or not) do
        assert [:operator_word] = token_types(kw), "expected #{kw} to be operator_word"
      end
    end
  end

  # -- Identifiers --------------------------------------------------------

  describe "identifiers" do
    test "lowercase identifier" do
      assert [:name] = token_types("foo")
    end

    test "underscore-prefixed identifier" do
      assert [:name] = token_types("_bar")
    end

    test "identifier with digits" do
      assert [:name] = token_types("x42")
    end
  end

  # -- Module names -------------------------------------------------------

  describe "module / type names" do
    test "simple module name" do
      assert [:name_class] = token_types("String")
    end

    test "dotted module name" do
      assert [:name_class] = token_types("Std.List")
    end

    test "deeply nested module" do
      assert [:name_class] = token_types("Std.Core.Map")
    end
  end

  # -- Function detection -------------------------------------------------

  describe "function names" do
    test "identifier followed by ( is a function name" do
      types = token_types("greet(")
      assert [:name_function, :punctuation] = types
    end

    test "keyword is not reclassified as function" do
      types = token_types("if(")
      assert [:keyword, :punctuation] = types
    end
  end

  # -- Numbers ------------------------------------------------------------

  describe "numbers" do
    test "integer" do
      assert [:number_integer] = token_types("42")
    end

    test "integer with underscores" do
      assert [:number_integer] = token_types("1_000_000")
    end

    test "hex integer" do
      assert [:number_hex] = token_types("0xFF")
    end

    test "binary integer" do
      assert [:number_bin] = token_types("0b1010")
    end

    test "float" do
      assert [:number_float] = token_types("3.14")
    end

    test "float with scientific notation" do
      assert [:number_float] = token_types("1.5e10")
    end
  end

  # -- Strings ------------------------------------------------------------

  describe "strings" do
    test "simple string" do
      tokens = lex_no_ws(~s("hello"))
      types = Enum.map(tokens, &elem(&1, 0))
      assert :string in types
    end

    test "string with escape" do
      tokens = lex_no_ws(~s("hello\\nworld"))
      types = Enum.map(tokens, &elem(&1, 0))
      assert :string_escape in types
    end

    test "string with interpolation" do
      tokens = lex_no_ws(~s("hello \#{name}"))
      types = Enum.map(tokens, &elem(&1, 0))
      assert :string_interpol in types
    end
  end

  # -- Char literals ------------------------------------------------------

  describe "char literals" do
    test "simple char" do
      assert [:string_char] = token_types("'a'")
    end

    test "escaped char" do
      assert [:string_char] = token_types("'\\n'")
    end
  end

  # -- Atoms --------------------------------------------------------------

  describe "atoms" do
    test "simple atom" do
      assert [:string_symbol] = token_types(":erlang")
    end

    test "atom with uppercase" do
      assert [:string_symbol] = token_types(":MyAtom")
    end
  end

  # -- Regex --------------------------------------------------------------

  describe "regex" do
    test "simple regex" do
      assert [:string_regex] = token_types("~r/pattern/")
    end

    test "regex with flags" do
      assert [:string_regex] = token_types("~r/pattern/gi")
    end
  end

  # -- Attributes ---------------------------------------------------------

  describe "attributes" do
    test "@extern" do
      assert [:name_attribute] = token_types("@extern")
    end

    test "arbitrary attribute" do
      assert [:name_attribute] = token_types("@doc")
    end
  end

  # -- Operators ----------------------------------------------------------

  describe "operators" do
    test "arrow ->" do
      assert [:operator] = token_types("->")
    end

    test "fat arrow =>" do
      assert [:operator] = token_types("=>")
    end

    test "pipe |>" do
      assert [:operator] = token_types("|>")
    end

    test "string concat <>" do
      assert [:operator] = token_types("<>")
    end

    test "comparison operators" do
      for op <- ~w(== != <= >=) do
        assert [:operator] = token_types(op), "expected #{op} to be operator"
      end
    end

    test "range operators" do
      assert [:operator] = token_types("..")
      assert [:operator] = token_types("..=")
    end

    test "single char operators" do
      for op <- ~w(+ - * / = < > | ^) do
        assert [:operator] = token_types(op), "expected #{op} to be operator"
      end
    end
  end

  # -- FSM transitions ----------------------------------------------------

  describe "FSM transitions" do
    test "transition close -->" do
      assert [:operator] = token_types("-->")
    end
  end

  # -- Punctuation --------------------------------------------------------

  describe "punctuation" do
    test "parentheses, brackets, braces" do
      for p <- ~w|( ) [ ] { } , ;| do
        assert [:punctuation] = token_types(p), "expected #{inspect(p)} to be punctuation"
      end
    end

    test "colon" do
      # standalone colon (not part of atom)
      tokens = lex_no_ws("x: Int")
      types = Enum.map(tokens, &elem(&1, 0))
      assert :punctuation in types
    end
  end

  # -- Full expressions ---------------------------------------------------

  describe "full expressions" do
    test "function definition" do
      source = "fn greet(name: String) -> String"
      types = token_types(source)

      assert :keyword_declaration in types
      assert :name_function in types
      assert :name_class in types
      assert :operator in types
    end

    test "module definition" do
      source = "mod Hello"
      types = token_types(source)
      assert [:keyword_declaration, :name_class] = types
    end

    test "type definition with sum type" do
      source = "type Color = Red | Green | Blue"
      types = token_types(source)
      assert :keyword_declaration in types
      assert :name_class in types
      assert :operator in types
    end

    test "match expression" do
      source = ~s"""
      match opt
        Some(v) -> v
        None() -> default
      """

      types = token_types(source)
      assert :keyword in types
    end

    test "extern FFI" do
      source = "@extern(:erlang, :abs, 1)"
      tokens = lex_no_ws(source)
      types = Enum.map(tokens, &elem(&1, 0))
      assert :name_attribute in types
      assert :string_symbol in types
      assert :number_integer in types
    end

    test "fsm block" do
      source = "fsm TrafficLight"
      types = token_types(source)
      assert [:keyword_declaration, :name_class] = types
    end

    test "protocol definition" do
      source = "proto Stringify(T)"
      types = token_types(source)
      assert :keyword_declaration in types
      assert :name_class in types
    end

    test "let binding" do
      source = "let val = abs(0 - 42)"
      types = token_types(source)
      assert :keyword_declaration in types
      assert :name in types or :name_function in types
    end
  end

  # -- Lexer invariant: unlex roundtrip -----------------------------------

  describe "roundtrip" do
    test "lexed tokens reconstruct the original string" do
      source = ~s|fn add(a: Int, b: Int) -> Int = a + b|

      assert source ==
               source
               |> CureLexer.lex()
               |> Makeup.Lexer.unlex()
    end

    test "complex source roundtrips" do
      source = """
      mod Math
        fn factorial(n: Int) -> Int
          | 0 -> 1
          | n -> n * factorial(n - 1)
      """

      assert source ==
               source
               |> CureLexer.lex()
               |> Makeup.Lexer.unlex()
    end
  end
end
