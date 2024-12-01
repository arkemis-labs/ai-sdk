defmodule Ai do
  @moduledoc """
  AI is an Elixir SDK for building AI-powered applications.
  It provides streaming support and easy integration with various AI providers.
  """

  @type message :: %{
          role: String.t(),
          content: String.t(),
          name: String.t() | nil,
          function_call: map() | nil
        }

  @type common_options :: %{
          optional(:model) => String.t(),
          optional(:temperature) => float(),
          optional(:max_tokens) => pos_integer(),
          optional(:top_p) => float(),
          optional(:frequency_penalty) => float(),
          optional(:presence_penalty) => float(),
          optional(:stop) => String.t() | [String.t()],
          optional(:stream) => boolean()
        }

  @type chat_options ::
          common_options()
          | %{
              optional(:functions) => [map()],
              optional(:function_call) => String.t() | map()
            }

  @type completion_options ::
          common_options()
          | %{
              optional(:echo) => boolean(),
              optional(:suffix) => String.t(),
              optional(:logit_bias) => map()
            }

  @type stream_options :: %{
          optional(:chunk_timeout) => pos_integer()
        }

  @type chunk :: %{
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

  @type response :: %{
          id: String.t(),
          model: String.t(),
          choices: [map()],
          usage: map()
        }

  @type generate_text_options :: common_options()

  @type generate_structured_options :: common_options()

  @type json_schema :: map()

  @doc """
  Sends a chat request to the AI provider.
  Returns either a stream of chunks or a complete response depending on the :stream option.
  """
  @callback chat(
              prompt :: String.t() | [message()],
              chat_options(),
              stream_options()
            ) :: Enumerable.t() | {:ok, response()} | {:error, term()}

  @doc """
  Sends a completion request to the AI provider.
  Returns either a stream of chunks or a complete response depending on the :stream option.
  """
  @callback completion(
              prompt :: String.t(),
              completion_options(),
              stream_options()
            ) :: Enumerable.t() | {:ok, response()} | {:error, term()}

  @doc """
  Generates text using the AI provider.
  Returns just the generated text content without the full API response structure.
  """
  @callback generate_text(
              prompt :: String.t(),
              options :: generate_text_options()
            ) :: {:ok, String.t()} | {:error, term()}

  @doc """
  Generates structured data from text using the AI provider based on a provided JSON schema.
  Returns a parsed object that matches the schema structure.
  """
  @callback generate_structured(
              prompt :: String.t(),
              schema :: json_schema(),
              options :: generate_structured_options()
            ) :: {:ok, map()} | {:error, term()}
end
