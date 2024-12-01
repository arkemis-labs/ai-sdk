defmodule Ai do
  @moduledoc """
  AI is an Elixir SDK for building AI-powered applications.
  It provides streaming support and easy integration with various AI providers.
  """

  @type completion_options :: %{
          optional(:model) => String.t(),
          optional(:temperature) => float(),
          optional(:max_tokens) => pos_integer(),
          optional(:top_p) => float(),
          optional(:frequency_penalty) => float(),
          optional(:presence_penalty) => float(),
          optional(:stop) => String.t() | [String.t()]
        }

  @type stream_options :: %{
          optional(:chunk_timeout) => pos_integer()
        }

  @type completion_chunk :: %{
          id: String.t(),
          model: String.t(),
          choices: [
            %{
              index: non_neg_integer(),
              delta: %{
                content: String.t(),
                role: String.t() | nil,
                function_call: map() | nil
              },
              finish_reason: String.t() | nil
            }
          ]
        }

  @doc """
  Streams a completion from the AI provider.
  Returns a stream of completion chunks.
  """
  @callback stream(
              prompt :: String.t() | [map()],
              completion_options(),
              stream_options()
            ) :: Enumerable.t()

  @doc """
  Completes a prompt with the AI provider.
  Returns the full completion response.
  """
  @callback complete(
              prompt :: String.t() | [map()],
              completion_options()
            ) :: {:ok, map()} | {:error, term()}
end
