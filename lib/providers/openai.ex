defmodule Ai.Providers.OpenAI do
  @behaviour Ai

  @base_url "https://api.openai.com/v1"
  @default_chat_model "gpt-3.5-turbo"
  @default_completion_model "gpt-3.5-turbo-instruct"
  @default_chunk_timeout 10_000

  @type api_function :: %{
          name: String.t(),
          description: String.t(),
          parameters: map()
        }

  @type function_callback :: (map() -> term())
  @type function_callbacks :: %{String.t() => function_callback()}

  @spec chat(
          String.t() | [Ai.message()],
          Ai.chat_options(),
          Ai.stream_options()
        ) :: Enumerable.t() | {:ok, Ai.response()} | {:error, term()}
  def chat(prompt, options \\ %{}, stream_options \\ %{}) do
    stream? = Map.get(options, :stream, false)

    if stream? do
      stream_chat(prompt, options, stream_options)
    else
      complete_chat(prompt, options)
    end
  end

  @spec completion(
          String.t(),
          Ai.completion_options(),
          Ai.stream_options()
        ) :: Enumerable.t() | {:ok, Ai.response()} | {:error, term()}
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

  @spec stream_chat(String.t() | [Ai.message()], Ai.chat_options(), Ai.stream_options()) ::
          Enumerable.t()
  defp stream_chat(prompt, options, stream_options) do
    model = Map.get(options, :model, @default_chat_model)
    chunk_timeout = Map.get(stream_options, :chunk_timeout, @default_chunk_timeout)

    body = prepare_stream_chat_body(model, prompt, options)
    handle_stream("#{@base_url}/chat/completions", body, chunk_timeout)
  end

  @spec stream_completion(String.t(), Ai.completion_options(), Ai.stream_options()) ::
          Enumerable.t()
  defp stream_completion(prompt, options, stream_options) do
    model = Map.get(options, :model, @default_completion_model)
    chunk_timeout = Map.get(stream_options, :chunk_timeout, @default_chunk_timeout)

    body = prepare_stream_completion_body(model, prompt, options)
    handle_stream("#{@base_url}/completions", body, chunk_timeout)
  end

  @spec prepare_stream_chat_body(String.t(), String.t() | [Ai.message()], map()) :: String.t()
  defp prepare_stream_chat_body(model, prompt, options) do
    %{
      model: model,
      messages: format_chat_prompt(prompt),
      stream: true,
      functions: Map.get(options, :functions),
      function_call: Map.get(options, :function_call)
    }
    |> Map.reject(fn {_, v} -> is_nil(v) end)
    |> Jason.encode!()
  end

  @spec prepare_stream_completion_body(String.t(), String.t(), map()) :: String.t()
  defp prepare_stream_completion_body(model, prompt, options) do
    %{
      model: model,
      prompt: prompt,
      stream: true,
      echo: Map.get(options, :echo, false),
      logit_bias: Map.get(options, :logit_bias, %{}),
      suffix: Map.get(options, :suffix, nil)
    }
    |> Jason.encode!()
  end

  @spec handle_stream(String.t(), String.t(), pos_integer()) :: Enumerable.t()
  defp handle_stream(url, body, chunk_timeout) do
    Req.post!(url,
      headers: headers(),
      body: body,
      receive_timeout: chunk_timeout,
      into: :self
    )
    |> Map.fetch!(:body)
    |> Stream.transform("", fn
      data, buffer when is_binary(data) ->
        {events, buffer} = ServerSentEvents.parse(buffer <> data)

        chunks =
          events
          |> Enum.map(&process_event/1)
          |> Enum.reject(&is_nil/1)
          |> Enum.map(&format_chunk/1)

        {chunks, buffer}

      :done, acc ->
        {:halt, acc}
    end)
  end

  @spec complete_chat(String.t() | [Ai.message()], Ai.chat_options()) ::
          {:ok, Ai.response()} | {:error, term()}
  defp complete_chat(prompt, options) do
    model = Map.get(options, :model, @default_chat_model)

    {api_functions, callbacks} =
      options
      |> Map.get(:functions, [])
      |> prepare_functions()

    body =
      prepare_chat_body(model, prompt, api_functions, options)
      |> Map.merge(prepare_request_body(options))
      |> Jason.encode!()

    url = "#{@base_url}/chat/completions"

    with {:ok, response} <- make_request(url, body),
         choice when not is_nil(choice) <- List.first(response["choices"]),
         true <- choice["finish_reason"] == "function_call" do
      execute_function_call(response, api_functions, callbacks)
    else
      _ -> make_request(url, body)
    end
  end

  @spec complete_completion(String.t(), Ai.completion_options()) ::
          {:ok, Ai.response()} | {:error, term()}
  defp complete_completion(prompt, options) do
    model = Map.get(options, :model, @default_completion_model)

    body =
      %{
        model: model,
        prompt: prompt,
        echo: Map.get(options, :echo, false),
        logit_bias: Map.get(options, :logit_bias, %{}),
        suffix: Map.get(options, :suffix, nil)
      }
      |> Map.merge(prepare_request_body(options))
      |> Jason.encode!()

    url = "#{@base_url}/completions"
    make_request(url, body)
  end

  @spec prepare_chat_body(String.t(), String.t() | [Ai.message()], [api_function()], map()) ::
          map()
  defp prepare_chat_body(model, prompt, api_functions, options) do
    body = %{
      model: model,
      messages: format_chat_prompt(prompt)
    }

    if Enum.empty?(api_functions) do
      body
    else
      body
      |> Map.put(:functions, api_functions)
      |> Map.put(:function_call, Map.get(options, :function_call))
    end
  end

  @spec prepare_request_body(map()) :: map()
  defp prepare_request_body(options) do
    options
    |> Map.take([
      :temperature,
      :max_tokens,
      :top_p,
      :frequency_penalty,
      :presence_penalty,
      :stop,
      :stream
    ])
    |> Map.reject(fn {_, v} -> is_nil(v) end)
  end

  @spec make_request(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  defp make_request(url, body) do
    case Req.post!(url, headers: headers(), body: body) do
      %{status: 200, body: body} ->
        {:ok, body}

      %{status: status, body: body} ->
        {:error, %{status: status, body: body}}
    end
  rescue
    e -> {:error, e}
  end

  @spec format_chat_prompt(String.t() | [Ai.message()]) :: [Ai.message()]
  defp format_chat_prompt(prompt) when is_binary(prompt) do
    [%{role: "user", content: prompt}]
  end

  defp format_chat_prompt(messages) when is_list(messages), do: messages

  @spec process_event(ServerSentEvents.event()) :: map() | nil
  defp process_event(%{data: "[DONE]"}), do: nil
  defp process_event(%{data: data}), do: parse_chunk(data)
  defp process_event(_), do: nil

  @spec parse_chunk(String.t()) :: map() | nil
  defp parse_chunk(content) do
    case Jason.decode(content, keys: :atoms) do
      {:ok, chunk} -> chunk
      {:error, _} -> nil
    end
  end

  @spec format_chunk(map()) :: Ai.chunk()
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

  @spec headers() :: [{String.t(), String.t()}]
  defp headers do
    [
      {"Content-Type", "application/json"},
      {"Authorization", "Bearer #{get_api_key!()}"}
    ]
  end

  @spec get_api_key!() :: String.t()
  defp get_api_key! do
    case Application.get_env(:ai_sdk, :openai_api_key) || System.get_env("OPENAI_API_KEY") do
      nil -> raise "OpenAI API key not found in config or environment variables"
      key -> key
    end
  end

  @spec prepare_functions([map()]) :: {[api_function()], function_callbacks()}
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

  @spec execute_function_call(map(), [api_function()], function_callbacks()) ::
          {:ok, Ai.response()} | {:error, term()}
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
