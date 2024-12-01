defmodule Ai.Providers.OpenAI do
  @behaviour Ai

  @base_url "https://api.openai.com/v1"
  @default_chat_model "gpt-3.5-turbo"
  @default_completion_model "gpt-3.5-turbo-instruct"
  @default_chunk_timeout 10_000

  @spec chat(binary() | maybe_improper_list()) ::
          ({:cont, any()} | {:halt, any()} | {:suspend, any()}, any() ->
             {:halted, any()} | {:suspended, any(), (any() -> any())})
          | {:error,
             %{
               optional(:__exception__) => true,
               optional(:__struct__) => atom(),
               optional(atom()) => any()
             }}
          | {:ok, any()}
  def chat(prompt, options \\ %{}, stream_options \\ %{}) do
    stream? = Map.get(options, :stream, false)

    if stream? do
      stream_chat(prompt, options, stream_options)
    else
      complete_chat(prompt, options)
    end
  end

  def completion(prompt, options \\ %{}, stream_options \\ %{}) do
    stream? = Map.get(options, :stream, false)

    if stream? do
      stream_completion(prompt, options, stream_options)
    else
      complete_completion(prompt, options)
    end
  end

  defp stream_chat(prompt, options, stream_options) do
    model = Map.get(options, :model, @default_chat_model)
    chunk_timeout = Map.get(stream_options, :chunk_timeout, @default_chunk_timeout)

    body =
      options
      |> Map.merge(%{
        model: model,
        messages: format_chat_prompt(prompt),
        stream: true
      })
      |> Jason.encode!()

    request = Finch.build(:post, "#{@base_url}/chat/completions", headers(), body)

    Stream.resource(
      fn -> start_stream(request, chunk_timeout) end,
      &process_stream/1,
      fn _ -> :ok end
    )
  end

  defp stream_completion(prompt, options, stream_options) do
    model = Map.get(options, :model, @default_completion_model)
    chunk_timeout = Map.get(stream_options, :chunk_timeout, @default_chunk_timeout)

    body =
      options
      |> Map.merge(%{
        model: model,
        prompt: prompt,
        stream: true,
        echo: Map.get(options, :echo, false),
        logit_bias: Map.get(options, :logit_bias, %{}),
        suffix: Map.get(options, :suffix, nil)
      })
      |> Jason.encode!()

    request = Finch.build(:post, "#{@base_url}/completions", headers(), body)

    Stream.resource(
      fn -> start_stream(request, chunk_timeout) end,
      &process_stream/1,
      fn _ -> :ok end
    )
  end

  defp complete_chat(prompt, options) do
    model = Map.get(options, :model, @default_chat_model)

    body =
      options
      |> Map.merge(%{
        model: model,
        messages: format_chat_prompt(prompt)
      })
      |> Jason.encode!()

    request = Finch.build(:post, "#{@base_url}/chat/completions", headers(), body)
    make_request(request)
  end

  defp complete_completion(prompt, options) do
    model = Map.get(options, :model, @default_completion_model)

    body =
      options
      |> Map.merge(%{
        model: model,
        prompt: prompt,
        echo: Map.get(options, :echo, false),
        logit_bias: Map.get(options, :logit_bias, %{}),
        suffix: Map.get(options, :suffix, nil)
      })
      |> Jason.encode!()

    request = Finch.build(:post, "#{@base_url}/completions", headers(), body)
    make_request(request)
  end

  defp start_stream(request, chunk_timeout) do
    case Finch.request(request, AiFinch, receive_timeout: chunk_timeout) do
      {:ok, %{status: 200} = resp} ->
        {:ok, resp.body |> String.split("\n", trim: true)}

      {:ok, %{status: status}} ->
        {:error, "Unexpected status: #{status}"}

      {:error, error} ->
        {:error, error}
    end
  end

  defp process_stream({:error, error}), do: {:halt, error}
  defp process_stream({:ok, []}), do: {:halt, :done}

  defp process_stream({:ok, [line | rest]}) do
    case process_line(line) do
      nil -> {[], {:ok, rest}}
      chunk -> {[format_chunk(chunk)], {:ok, rest}}
    end
  end

  defp make_request(request) do
    case Finch.request(request, AiFinch) do
      {:ok, %Finch.Response{status: 200, body: body}} ->
        {:ok, Jason.decode!(body, keys: :atoms)}

      {:ok, %Finch.Response{status: status, body: body}} ->
        {:error, %{status: status, body: Jason.decode!(body)}}

      {:error, exception} ->
        {:error, exception}
    end
  end

  defp format_chat_prompt(prompt) when is_binary(prompt) do
    [%{role: "user", content: prompt}]
  end

  defp format_chat_prompt(messages) when is_list(messages), do: messages

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
