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

    test "## single-line doc comment is :string_doc" do
      assert [{:string_doc, _, _}] = lex_no_ws("## Attach to the next definition.")
    end

    test "### fenced multi-line doc comment is :string_doc" do
      source = """
      ###
      Multi-line docs land here.
      ###\
      """

      assert [{:string_doc, _, _}] = lex_no_ws(source)
    end

    test "single # followed immediately by non-# is still a plain comment" do
      assert [{:comment_single, _, _}] = lex_no_ws("#no space")
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

    test "actor, sup, app, proof are keyword_declarations (v0.19.0 / v0.25.0 / v0.26.0)" do
      for kw <- ~w(actor sup app proof) do
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

    test "end is a control keyword (v0.22.0)" do
      assert [:keyword] = token_types("end")
    end

    test "assert_type is a control keyword (v0.19.0)" do
      assert [:keyword] = token_types("assert_type")
    end

    test "rewrite is a control keyword (v0.17.0)" do
      assert [:keyword] = token_types("rewrite")
    end

    test "with is a control keyword (actor container)" do
      assert [:keyword] = token_types("with")
    end
  end

  describe "FSM / actor / sup / app lifecycle callbacks" do
    test "on_start, on_stop, on_transition, ... are keywords" do
      for kw <-
            ~w(on_start on_stop on_transition on_enter on_exit on_failure on_timer on_message on_phase) do
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

    test "predicate identifier with trailing ?" do
      assert [:name] = token_types("even?")
      assert [:name] = token_types("is_empty?")
    end

    test "bang identifier with trailing !" do
      assert [:name] = token_types("stop!")
      assert [:name] = token_types("emergency!")
    end

    test "predicate identifier followed by ( is a function name" do
      assert [:name_function, :punctuation] = token_types("even?(")
    end

    test "trailing ? does not swallow keyword (even?) / if? stays a name" do
      # `if?` and `mod!` should remain plain :name tokens because
      # they are not keywords themselves.
      assert [:name] = token_types("if?")
      assert [:name] = token_types("mod!")
    end
  end

  describe "typed holes" do
    test "?? is an anonymous hole (v0.17.0)" do
      assert [:name_builtin_pseudo] = token_types("??")
    end

    test "?name is a named hole" do
      assert [:name_builtin_pseudo] = token_types("?body")
      assert [:name_builtin_pseudo] = token_types("?goal1")
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
      for op <- ~w(+ - * / % = < > | ^) do
        assert [:operator] = token_types(op), "expected #{op} to be operator"
      end
    end

    test "Melquiades ASCII operator <-| (v0.25.0)" do
      assert [:operator] = token_types("<-|")
    end

    test "Melquiades unicode operator ✉ (v0.25.0)" do
      assert [:operator] = token_types("✉")
    end

    test "bitstring segment specifier :: (v0.20.0)" do
      assert [:operator] = token_types("::")
    end

    test "generator arrow <- (v0.22.0)" do
      assert [:operator] = token_types("<-")
    end

    test "augmented assignment +=, -=, *=, /=" do
      for op <- ~w(+= -= *= /=) do
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

  # -- Full expressions: v0.17.0+ surface ---------------------------------

  describe "actor / sup / app / proof containers" do
    test "actor declaration" do
      source = "actor Counter with 0"
      types = token_types(source)
      assert :keyword_declaration in types
      assert :name_class in types
      assert :number_integer in types
    end

    test "sup supervisor declaration" do
      source = "sup Forge.Root"
      types = token_types(source)
      assert [:keyword_declaration, :name_class] = types
    end

    test "app application declaration" do
      source = "app CureForge"
      types = token_types(source)
      assert [:keyword_declaration, :name_class] = types
    end

    test "proof container" do
      source = "proof ProofLaws"
      types = token_types(source)
      assert [:keyword_declaration, :name_class] = types
    end

    test "Melquiades send expression" do
      source = "pid <-| :ping"
      types = token_types(source)
      assert :name in types
      assert :operator in types
      assert :string_symbol in types
    end

    test "assert_type expression" do
      source = "assert_type 42 : Int"
      types = token_types(source)
      assert :keyword in types
      assert :number_integer in types
      assert :name_class in types
    end
  end

  describe "bitstring segment specifiers" do
    test "segment with ::size" do
      source = "<<len::16, payload::binary-size(len)>>"
      types = token_types(source)
      assert :punctuation in types
      assert :operator in types
      assert :number_integer in types
    end

    test "binary comprehension generator with <-" do
      source = "[b for <<b <- buf>>]"
      types = token_types(source)
      assert :keyword in types
      assert :operator in types
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

    test "actor with Melquiades send roundtrips" do
      source = """
      actor Counter with 0
        on_message
          (:inc, n) -> n + 1
          (:get, n) ->
            pid <-| %[:value, n]
            n
      """

      assert source ==
               source
               |> CureLexer.lex()
               |> Makeup.Lexer.unlex()
    end

    test "sup with children roundtrips" do
      source = """
      sup Forge.Root
        strategy  = :one_for_one
        intensity = 5
        children
          Metrics as metrics
          Logger  as logger  (restart: :permanent, shutdown: 2000)
      """

      assert source ==
               source
               |> CureLexer.lex()
               |> Makeup.Lexer.unlex()
    end

    test "fenced doc comment roundtrips" do
      source = """
      ###
      Binary comprehension generators.
      ###
      fn bytes_of(buf: Bitstring) -> List(Int) =
        [b for <<b <- buf>>]
      """

      assert source ==
               source
               |> CureLexer.lex()
               |> Makeup.Lexer.unlex()
    end
  end
end
