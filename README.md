# AI SDK

⚠️ Project is under heavy development and not all methods are implemented yet.

An Elixir SDK for building AI-powered applications with streaming support and easy integration with various AI providers.

## Installation

The package can be installed by adding `ai_sdk` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ai_sdk, "~> 0.1.0"}
  ]
end
```

## Configuration

Set your OpenAI API key in your environment:

```bash
export OPENAI_API_KEY=your-api-key
```

Or in your `config/config.exs`:

```elixir
config :ai_sdk, :openai_api_key, "your-api-key"
```

## Usage

### Chat Models

```elixir
# Simple chat completion
{:ok, response} = Ai.Providers.OpenAI.chat("What is the capital of France?")

# Streaming chat completion
Ai.Providers.OpenAI.chat("Tell me a story", %{stream: true})
|> Stream.map(fn chunk -> 
  chunk.choices
  |> Enum.map(& &1.delta.content)
  |> Enum.join("")
end)
|> Stream.each(&IO.write/1)
|> Stream.run()

# Chat with history
messages = [
  %{role: "system", content: "You are a helpful assistant."},
  %{role: "user", content: "What's the weather like?"},
  %{role: "assistant", content: "I don't have access to real-time weather data."},
  %{role: "user", content: "What can you help me with then?"}
]

Ai.Providers.OpenAI.chat(messages, %{
  model: "gpt-4",
  temperature: 0.7
})

# Function calling
functions = [
  %{
    name: "get_weather",
    description: "Get the current weather in a location",
    parameters: %{
      type: "object",
      properties: %{
        location: %{
          type: "string",
          description: "The city and state, e.g., San Francisco, CA"
        }
      },
      required: ["location"]
    }
  }
]

Ai.Providers.OpenAI.chat("What's the weather in San Francisco?", %{
  functions: functions,
  function_call: "auto"
})
```

### Completion Models

```elixir
# Simple completion
{:ok, response} = Ai.Providers.OpenAI.completion("Complete this: The quick brown fox")

# Streaming completion
Ai.Providers.OpenAI.completion("Tell me a story", %{stream: true})
|> Stream.map(fn chunk -> 
  chunk.choices
  |> Enum.map(& &1.delta.content)
  |> Enum.join("")
end)
|> Stream.each(&IO.write/1)
|> Stream.run()

# Completion with options
options = %{
  model: "gpt-3.5-turbo-instruct",
  temperature: 0.7,
  max_tokens: 100,
  echo: true,
  suffix: "over the lazy dog"
}

Ai.Providers.OpenAI.completion("The quick brown fox", options)
```

### Configuration Options

#### Common Options
- `:model` - The model to use (default varies by endpoint)
- `:temperature` - Controls randomness (0-1)
- `:max_tokens` - Maximum tokens in the response
- `:top_p` - Controls diversity via nucleus sampling
- `:frequency_penalty` - Decreases likelihood of repeating tokens
- `:presence_penalty` - Increases likelihood of new topics
- `:stop` - Sequences where the API will stop generating
- `:stream` - Whether to stream the response

#### Chat-Specific Options
- `:functions` - List of functions the model may call
- `:function_call` - Controls function calling behavior

#### Completion-Specific Options
- `:echo` - Echo back the prompt in addition to the completion
- `:suffix` - Text to append to the completion
- `:logit_bias` - Modify likelihood of specific tokens

#### Stream Options
- `:chunk_timeout` - Timeout for receiving chunks (default: 10000ms)

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

