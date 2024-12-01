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

  @spec generate_text(String.t(), map()) :: {:ok, String.t()} | {:error, map()}
  def generate_text(prompt, options \\ %{}) do
    case chat(prompt, options) do
      {:ok, response} ->
        text = get_in(response, [:choices, Access.at(0), :message, :content])
        {:ok, text}

      error ->
        error
    end
  end

  @spec generate_structured(String.t(), map(), map()) :: {:ok, map()} | {:error, map()}
  def generate_structured(prompt, schema, options \\ %{}) do
    system_prompt = """
    You are a structured data extractor. Your response must be valid JSON that matches this schema:
    #{Jason.encode!(schema)}
    """

    messages = [
      %{role: "system", content: system_prompt},
      %{role: "user", content: prompt}
    ]

    case chat(messages, options) do
      {:ok, response} ->
        content = get_in(response, [:choices, Access.at(0), :message, :content])

        case Jason.decode(content) do
          {:ok, parsed} -> {:ok, parsed}
          {:error, _} -> {:error, %{error: "Failed to parse JSON response"}}
        end

      error ->
        error
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
        stream: true,
        functions: Map.get(options, :functions),
        function_call: Map.get(options, :function_call)
      })
      |> Map.reject(fn {_, v} -> is_nil(v) end)
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

    {api_functions, callbacks} =
      options
      |> Map.get(:functions, [])
      |> prepare_functions()

    body = %{
      model: model,
      messages: format_chat_prompt(prompt)
    }

    body =
      if Enum.empty?(api_functions) do
        body
      else
        body
        |> Map.put(:functions, api_functions)
        |> Map.put(:function_call, Map.get(options, :function_call))
      end

    body =
      body
      |> Map.merge(
        Map.take(options, [
          :temperature,
          :max_tokens,
          :top_p,
          :frequency_penalty,
          :presence_penalty,
          :stop,
          :stream
        ])
      )
      |> Map.reject(fn {_, v} -> is_nil(v) end)
      |> Jason.encode!()

    request = Finch.build(:post, "#{@base_url}/chat/completions", headers(), body)

    with {:ok, response} <- make_request(request),
         choice when not is_nil(choice) <- List.first(response.choices),
         true <- choice.finish_reason == "function_call" do
      execute_function_call(response, api_functions, callbacks)
    else
      _ -> make_request(request)
    end
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

  defp prepare_functions(functions) do
    functions
    |> Enum.map(fn function ->
      {callback, api_function} = Map.pop(function, :callback)
      {api_function, callback}
    end)
    |> Enum.reduce({[], %{}}, fn {api_function, callback}, {api_functions, callbacks} ->
      new_callbacks =
        if callback do
          Map.put(callbacks, api_function.name, callback)
        else
          callbacks
        end

      {[api_function | api_functions], new_callbacks}
    end)
  end

  defp execute_function_call(
         %{choices: [%{message: %{function_call: %{name: name, arguments: arguments}}} | _]} =
           response,
         functions,
         callbacks
       ) do
    case Map.get(callbacks, name) do
      nil ->
        {:ok, response}

      callback ->
        args = Jason.decode!(arguments)
        result = callback.(args)

        # Add function result to messages and make another API call
        messages = [
          # Include the assistant's function call
          %{
            role: "assistant",
            content: nil,
            function_call: %{
              name: name,
              arguments: arguments
            }
          },
          # Include the function response
          %{
            role: "function",
            name: name,
            content: Jason.encode!(result)
          }
        ]

        complete_chat(messages, %{
          model: response.model,
          functions: functions
        })
    end
  end

  defp execute_function_call(response, _functions, _callbacks), do: {:ok, response}
end
