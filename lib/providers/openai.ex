defmodule Ai.Providers.OpenAI do
  @behaviour Ai

  @base_url "https://api.openai.com/v1"
  @default_model "gpt-3.5-turbo"
  @default_chunk_timeout 10_000

  @impl true
  def stream(prompt, options \\ %{}, stream_options \\ %{}) do
    model = Map.get(options, :model, @default_model)
    chunk_timeout = Map.get(stream_options, :chunk_timeout, @default_chunk_timeout)

    body =
      options
      |> Map.merge(%{
        model: model,
        messages: format_prompt(prompt),
        stream: true
      })
      |> Jason.encode!()

    request = Finch.build(:post, "#{@base_url}/chat/completions", headers(), body)

    Stream.resource(
      fn ->
        case Finch.request(request, AiFinch, receive_timeout: chunk_timeout) do
          {:ok, %{status: 200} = resp} ->
            {:ok, resp.body |> String.split("\n", trim: true)}

          {:ok, %{status: status}} ->
            {:error, "Unexpected status: #{status}"}

          {:error, error} ->
            {:error, error}
        end
      end,
      fn
        {:error, error} ->
          {:halt, error}

        {:ok, []} ->
          {:halt, :done}

        {:ok, [line | rest]} ->
          case process_line(line) do
            nil -> {[], {:ok, rest}}
            chunk -> {[format_chunk(chunk)], {:ok, rest}}
          end
      end,
      fn _ -> :ok end
    )
  end

  @impl true
  def complete(prompt, options \\ %{}) do
    model = Map.get(options, :model, @default_model)

    body =
      options
      |> Map.merge(%{
        model: model,
        messages: format_prompt(prompt)
      })
      |> Jason.encode!()

    request = Finch.build(:post, "#{@base_url}/chat/completions", headers(), body)

    case Finch.request(request, AiFinch) do
      {:ok, %Finch.Response{status: 200, body: body}} ->
        {:ok, Jason.decode!(body, keys: :atoms)}

      {:ok, %Finch.Response{status: status, body: body}} ->
        {:error, %{status: status, body: Jason.decode!(body)}}

      {:error, exception} ->
        {:error, exception}
    end
  end

  defp format_prompt(prompt) when is_binary(prompt) do
    [%{role: "user", content: prompt}]
  end

  defp format_prompt(messages) when is_list(messages), do: messages

  defp process_line(line) do
    case String.trim(line) do
      "data: [DONE]" -> nil
      "data: " <> content -> parse_chunk(content)
      _ -> nil
    end
  end

  defp parse_chunk(content) do
    case Jason.decode(content, keys: :atoms) do
      {:ok, chunk} -> chunk
      {:error, _} -> nil
    end
  end

  defp format_chunk(chunk) do
    %{
      id: chunk.id,
      model: chunk.model,
      choices:
        Enum.map(chunk.choices, fn choice ->
          %{
            index: choice.index,
            delta: %{
              content: choice.delta[:content] || "",
              role: choice.delta[:role],
              function_call: choice.delta[:function_call]
            },
            finish_reason: choice.finish_reason
          }
        end)
    }
  end

  defp headers do
    [
      {"Content-Type", "application/json"},
      {"Authorization", "Bearer #{get_api_key!()}"}
    ]
  end

  defp get_api_key! do
    case Application.get_env(:ai_sdk, :openai_api_key) || System.get_env("OPENAI_API_KEY") do
      nil -> raise "OpenAI API key not found in config or environment variables"
      key -> key
    end
  end
end
