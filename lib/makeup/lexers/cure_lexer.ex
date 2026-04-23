defmodule Makeup.Lexers.CureLexer do
  @moduledoc """
  A `Makeup` lexer for the [Cure](https://cure-lang.org) programming language.

  Cure is a dependently-typed language for the BEAM with first-class finite
  state machines, typed supervision trees, OTP applications, SMT-backed
  verification, and propositional equality. Its syntax is indentation-
  significant, ML-influenced, and includes FSM transition literals, the
  Melquiades send operator, and Erlang-style bitstring segments.

  The tokeniser tracks the surface features of the language as of
  Cure v0.28.0. See the top of `cure/CHANGELOG.md` in the Cure
  repository for the authoritative reference.

  ## Registering the lexer

  The lexer is automatically registered on application start for the language
  name `"cure"` and the file extension `".cure"`.
  """

  import NimbleParsec
  import Makeup.Lexer.Combinators
  import Makeup.Lexer.Groups

  @behaviour Makeup.Lexer

  ###################################################################
  # Step 1: tokenize the input
  ###################################################################

  # -- Whitespace -------------------------------------------------------

  whitespace =
    ascii_string([?\r, ?\s, ?\n, ?\t], min: 1)
    |> token(:whitespace)

  any_char = utf8_char([]) |> token(:error)

  # -- Comments and doc comments ---------------------------------------
  #
  # Cure distinguishes three comment flavours:
  #
  #   #         plain line comment
  #   ##        single-line doc comment
  #   ###...### fenced multi-line doc comment (Cure v0.17.0+)
  #
  # Doc comments carry semantic weight (they are harvested by `cure doc`
  # and feed the website) and are highlighted as `:string_doc` to match
  # the convention used by makeup_elixir for `@doc` strings.

  line_body =
    repeat(
      lookahead_not(ascii_char([?\n]))
      |> utf8_string([], 1)
    )

  fenced_doc_body =
    repeat(
      lookahead_not(string("###"))
      |> utf8_string([], 1)
    )

  fenced_doc_comment =
    string("###")
    |> concat(fenced_doc_body)
    |> concat(string("###"))
    |> token(:string_doc)

  single_line_doc_comment =
    string("##")
    |> lookahead_not(string("#"))
    |> concat(line_body)
    |> token(:string_doc)

  inline_comment =
    string("#")
    |> lookahead_not(string("#"))
    |> concat(line_body)
    |> token(:comment_single)

  # -- Numbers ----------------------------------------------------------

  digits = ascii_string([?0..?9], min: 1)
  integer = digits |> repeat(string("_") |> concat(digits))

  number_bin =
    string("0b")
    |> concat(
      ascii_string([?0..?1], min: 1)
      |> repeat(string("_") |> concat(ascii_string([?0..?1], min: 1)))
    )
    |> token(:number_bin)

  number_hex =
    string("0x")
    |> concat(
      ascii_string([?0..?9, ?a..?f, ?A..?F], min: 1)
      |> repeat(string("_") |> concat(ascii_string([?0..?9, ?a..?f, ?A..?F], min: 1)))
    )
    |> token(:number_hex)

  float_scientific_notation_part =
    ascii_string([?e, ?E], 1)
    |> optional(ascii_string([?+, ?-], 1))
    |> concat(integer)

  number_float =
    integer
    |> string(".")
    |> concat(integer)
    |> optional(float_scientific_notation_part)
    |> token(:number_float)

  number_integer = token(integer, :number_integer)

  # -- Strings ----------------------------------------------------------

  unicode_char_in_string =
    string("\\u")
    |> ascii_string([?0..?9, ?a..?f, ?A..?F], 4)
    |> token(:string_escape)

  escaped_char =
    string("\\")
    |> utf8_string([], 1)
    |> token(:string_escape)

  interpolation =
    many_surrounded_by(
      parsec(:root_element),
      "\#{",
      "}",
      :string_interpol
    )

  combinators_inside_string = [
    unicode_char_in_string,
    escaped_char,
    interpolation
  ]

  double_quoted_string =
    string_like("\"", "\"", combinators_inside_string, :string)

  # -- Char literals ----------------------------------------------------

  escape_char_literal =
    string("?\\")
    |> utf8_string([], 1)
    |> token(:string_char)

  normal_char_literal =
    string("'")
    |> choice([
      string("\\") |> utf8_string([], 1),
      utf8_char(not: ?', not: ?\\)
    ])
    |> string("'")
    |> token(:string_char)

  # -- Atoms ------------------------------------------------------------

  atom_name =
    ascii_string([?a..?z, ?A..?Z, ?_], 1)
    |> optional(ascii_string([?a..?z, ?A..?Z, ?0..?9, ?_], min: 1))
    |> optional(utf8_char([??, ?!]))

  atom =
    string(":")
    |> concat(atom_name)
    |> token(:string_symbol)

  # -- Regex ------------------------------------------------------------

  regex_body =
    repeat(
      lookahead_not(string("/"))
      |> choice([
        string("\\/"),
        utf8_string([not: ?/], 1)
      ])
    )

  regex_flags = optional(ascii_string([?a..?z], min: 1))

  regex =
    string("~r/")
    |> concat(regex_body)
    |> concat(string("/"))
    |> concat(regex_flags)
    |> token(:string_regex)

  # -- Identifiers & keywords -------------------------------------------
  #
  # We tokenize all identifiers uniformly as :name and reclassify in
  # postprocess/2. An identifier may carry a single trailing `?`
  # (predicate convention, holes) or `!` (effect annotations, FSM hard
  # events) so `is_empty?`, `even?`, and `stop!` all lex as a single
  # `:name` token. The suffix is included in the token value so the
  # postprocessor can still spot keywords (`if`, `mod`, ...) without a
  # false match against `if?` or `mod!`.

  identifier_name =
    ascii_string([?a..?z, ?_], 1)
    |> optional(ascii_string([?a..?z, ?A..?Z, ?0..?9, ?_], min: 1))
    |> optional(ascii_string([??, ?!], 1))

  identifier =
    identifier_name
    |> lexeme()
    |> token(:name)

  # Module / type names start with an uppercase letter.
  module_name_part =
    ascii_string([?A..?Z], 1)
    |> optional(ascii_string([?a..?z, ?A..?Z, ?0..?9, ?_], min: 1))

  module_name =
    module_name_part
    |> concat(repeat(string(".") |> concat(module_name_part)))

  module = token(module_name, :name_class)

  # -- Typed holes ------------------------------------------------------
  #
  # `??` is the anonymous hole (`?_1`, `?_2`, ... after parsing).
  # `?name` is a named hole. Both show up in type-error reports and
  # in `cure synth` output. We highlight them as a pseudo-builtin
  # name so editors give them a distinct colour from ordinary
  # identifiers.

  hole_anon =
    string("??")
    |> token(:name_builtin_pseudo)

  hole_named =
    string("?")
    |> concat(
      ascii_string([?a..?z, ?A..?Z, ?_], 1)
      |> optional(ascii_string([?a..?z, ?A..?Z, ?0..?9, ?_], min: 1))
    )
    |> token(:name_builtin_pseudo)

  # -- Attributes -------------------------------------------------------

  attribute =
    string("@")
    |> concat(
      ascii_string([?a..?z, ?A..?Z, ?_], 1)
      |> optional(ascii_string([?a..?z, ?A..?Z, ?0..?9, ?_], min: 1))
    )
    |> token(:name_attribute)

  # -- Operators --------------------------------------------------------

  # FSM transition: --event--> is handled specially below. The Melquiades
  # operator (v0.25.0) has two surface forms: the ASCII `<-|` and the
  # unicode envelope `✉` (U+2709). `<-` is the binary-comprehension
  # generator arrow (v0.22.0) and `::` is the bitstring-segment specifier
  # (v0.20.0).

  operator_name =
    word_from_list(~W(
      <-| <- <> |> -> => ..= .. == != <= >=
      ++ -- ** :: += -= *= /=
    ))

  operator = token(operator_name, :operator)

  melquiades_unicode = token("✉", :operator)

  single_char_operator =
    word_from_list(~W(+ - * / % = < > | ^ ! &), :operator)

  # FSM transition open `--` followed by non-`>` (to distinguish from `-->`)
  fsm_transition_open =
    string("--")
    |> lookahead_not(string(">"))
    |> token(:operator)

  # FSM transition close `-->`
  fsm_transition_close =
    string("-->")
    |> token(:operator)

  # -- Punctuation & delimiters -----------------------------------------

  tuple_open = token("%[", :punctuation)
  map_open = token("%{", :punctuation)
  binary_open = token("<<", :punctuation)
  binary_close = token(">>", :punctuation)

  delimiters_punctuation =
    word_from_list(
      ~W"( ) [ ] { } , ; : .",
      :punctuation
    )

  # Delimiter group matching
  tuple_matched = many_surrounded_by(parsec(:root_element), "%[", "]")
  map_matched = many_surrounded_by(parsec(:root_element), "%{", "}")
  parens_matched = many_surrounded_by(parsec(:root_element), "(", ")")
  brackets_matched = many_surrounded_by(parsec(:root_element), "[", "]")
  braces_matched = many_surrounded_by(parsec(:root_element), "{", "}")
  binary_matched = many_surrounded_by(parsec(:root_element), "<<", ">>")

  delimiter_pairs = [
    tuple_matched,
    map_matched,
    parens_matched,
    brackets_matched,
    braces_matched,
    binary_matched
  ]

  # -- Root element combinator ------------------------------------------

  root_element_combinator =
    choice(
      [
        whitespace,
        # Comments - order matters: fenced ### before ## before plain #
        fenced_doc_comment,
        single_line_doc_comment,
        inline_comment,
        # Strings and interpolation
        double_quoted_string,
        # Regex (must come before ~ being treated as error)
        regex,
        # Char literal
        escape_char_literal,
        normal_char_literal,
        # Atoms (must come before : punctuation and :: operator)
        atom,
        # Attributes (@extern etc.)
        attribute,
        # Typed holes (?? before ?name, both before any stray `?` lands
        # in an identifier suffix)
        hole_anon,
        hole_named,
        # FSM transitions (must come before -- operator)
        fsm_transition_close,
        fsm_transition_open
      ] ++
        delimiter_pairs ++
        [
          # Multi-char operators (longest-first is handled by word_from_list)
          operator,
          # Melquiades unicode `✉`
          melquiades_unicode,
          # Numbers (hex and bin must come before plain integer)
          number_bin,
          number_hex,
          number_float,
          number_integer,
          # Module / type names
          module,
          # Single-char operators (after delimiters to avoid conflicts)
          single_char_operator,
          # Punctuation
          tuple_open,
          map_open,
          binary_open,
          binary_close,
          delimiters_punctuation,
          # Identifiers (catch-all for names)
          identifier,
          # If nothing matches, consume one char as error
          any_char
        ]
    )

  # Tag tokens with the language name for multi-language documents.
  @doc false
  def __as_cure_language__({ttype, meta, value}) do
    {ttype, Map.put(meta, :language, :cure), value}
  end

  ##############################################################################
  # Semi-public API: parsec entry points
  ##############################################################################

  @impl Makeup.Lexer
  defparsec(
    :root_element,
    root_element_combinator |> map({__MODULE__, :__as_cure_language__, []})
  )

  @impl Makeup.Lexer
  defparsec(
    :root,
    repeat(parsec(:root_element))
  )

  ###################################################################
  # Step 2: postprocess the list of tokens
  ###################################################################

  @declaration_keywords ~w(mod fn type proto impl fsm let rec local use as extern
                           actor sup app proof)
  @control_keywords ~w(if elif else then match when where for do in end
                       try catch finally throw return yield
                       assert_type rewrite with)
  @concurrency_keywords ~w(spawn send receive after)
  @fsm_callback_keywords ~w(on_start on_stop on_transition on_enter on_exit
                            on_failure on_timer on_message on_phase)
  @constant_keywords ~w(true false nil)
  @word_operators ~w(and or not)

  defp postprocess_helper([]), do: []

  # Reclassify identifiers that are keywords
  defp postprocess_helper([{:name, meta, value} | rest]) when value in @declaration_keywords do
    [{:keyword_declaration, meta, value} | postprocess_helper(rest)]
  end

  defp postprocess_helper([{:name, meta, value} | rest]) when value in @control_keywords do
    [{:keyword, meta, value} | postprocess_helper(rest)]
  end

  defp postprocess_helper([{:name, meta, value} | rest]) when value in @concurrency_keywords do
    [{:keyword, meta, value} | postprocess_helper(rest)]
  end

  defp postprocess_helper([{:name, meta, value} | rest]) when value in @fsm_callback_keywords do
    [{:keyword, meta, value} | postprocess_helper(rest)]
  end

  defp postprocess_helper([{:name, meta, value} | rest]) when value in @constant_keywords do
    [{:keyword_constant, meta, value} | postprocess_helper(rest)]
  end

  defp postprocess_helper([{:name, meta, value} | rest]) when value in @word_operators do
    [{:operator_word, meta, value} | postprocess_helper(rest)]
  end

  # Detect function names: identifier followed by `(`
  defp postprocess_helper([
         {:name, meta, value},
         {:punctuation, pmeta, "("} | rest
       ]) do
    [{:name_function, meta, value}, {:punctuation, pmeta, "("} | postprocess_helper(rest)]
  end

  # Pass everything else through
  defp postprocess_helper([token | rest]) do
    [token | postprocess_helper(rest)]
  end

  @impl Makeup.Lexer
  def postprocess(tokens, _opts \\ []) do
    postprocess_helper(tokens)
  end

  ###################################################################
  # Step 3: match groups (delimiters)
  ###################################################################

  @impl Makeup.Lexer
  defgroupmatcher(:match_groups,
    parentheses: [
      open: [[{:punctuation, %{language: :cure}, "("}]],
      close: [[{:punctuation, %{language: :cure}, ")"}]]
    ],
    brackets: [
      open: [[{:punctuation, %{language: :cure}, "["}]],
      close: [[{:punctuation, %{language: :cure}, "]"}]]
    ],
    braces: [
      open: [[{:punctuation, %{language: :cure}, "{"}]],
      close: [[{:punctuation, %{language: :cure}, "}"}]]
    ],
    tuple: [
      open: [[{:punctuation, %{language: :cure}, "%["}]],
      close: [[{:punctuation, %{language: :cure}, "]"}]]
    ],
    map: [
      open: [[{:punctuation, %{language: :cure}, "%{"}]],
      close: [[{:punctuation, %{language: :cure}, "}"}]]
    ],
    binary: [
      open: [
        [{:punctuation, %{language: :cure}, "<<"}]
      ],
      close: [
        [{:punctuation, %{language: :cure}, ">>"}]
      ]
    ]
  )

  ###################################################################
  # Public API
  ###################################################################

  @impl Makeup.Lexer
  def lex(string, opts \\ []) do
    {:ok, tokens, "", _, _, _} = root(string)

    tokens
    |> postprocess(opts)
    |> match_groups()
  end
end
