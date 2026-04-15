defmodule Makeup.Lexers.CureLexer.Application do
  @moduledoc false
  use Application

  alias Makeup.{Lexers.CureLexer, Registry}

  def start(_type, _args) do
    Registry.register_lexer(CureLexer,
      options: [],
      names: ["cure"],
      extensions: ["cure"]
    )

    Supervisor.start_link([], strategy: :one_for_one)
  end
end
