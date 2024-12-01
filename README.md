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

### Streaming Completions

```elixir
prompt = "Tell me a story about a brave knight"

Ai.Providers.OpenAI.stream(prompt)
|> Stream.map(fn chunk -> 
  chunk.choices
  |> Enum.map(& &1.delta.content)
  |> Enum.join("")
end)
|> Stream.each(&IO.write/1)
|> Stream.run()
```

### Regular Completions

```elixir
prompt = "What is the capital of France?"

{:ok, response} = Ai.Providers.OpenAI.complete(prompt)
IO.puts(response.choices |> Enum.at(0) |> Map.get(:message) |> Map.get(:content))
```

### Chat Messages

You can also pass a list of messages for a chat-like interaction:

```elixir
messages = [
  %{role: "system", content: "You are a helpful assistant."},
  %{role: "user", content: "What's the weather like?"},
  %{role: "assistant", content: "I don't have access to real-time weather data."},
  %{role: "user", content: "What can you help me with then?"}
]

Ai.Providers.OpenAI.stream(messages)
|> Stream.map(fn chunk -> 
  chunk.choices
  |> Enum.map(& &1.delta.content)
  |> Enum.join("")
end)
|> Stream.each(&IO.write/1)
|> Stream.run()
```

### Configuration Options

You can pass various options to customize the completion:

```elixir
options = %{
  model: "gpt-4",
  temperature: 0.7,
  max_tokens: 100,
  top_p: 1,
  frequency_penalty: 0,
  presence_penalty: 0
}

Ai.Providers.OpenAI.complete("Your prompt", options)
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

