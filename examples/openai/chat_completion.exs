# Example of basic chat completion with OpenAI provider
# Run with: mix run examples/openai/chat_completion.exs

# Example 1: Simple chat
IO.puts("\n--- Example 1: Simple Chat ---")
case Ai.Providers.OpenAI.chat("What is the capital of France?") do
  {:ok, response} -> IO.inspect(response, label: "Response")
  {:error, error} -> IO.inspect(error, label: "Error")
end

# Example 2: Chat with history
IO.puts("\n--- Example 2: Chat with History ---")
messages = [
  %{role: "system", content: "You are a helpful assistant specializing in geography."},
  %{role: "user", content: "What's the largest country by area?"},
  %{role: "assistant", content: "Russia is the largest country by total area."},
  %{role: "user", content: "What about by population?"}
]

case Ai.Providers.OpenAI.chat(messages, %{
  model: "gpt-3.5-turbo",
  temperature: 0.7
}) do
  {:ok, response} -> IO.inspect(response, label: "Response")
  {:error, error} -> IO.inspect(error, label: "Error")
end

# Example 3: Streaming chat
IO.puts("\n--- Example 3: Streaming Chat ---")
Ai.Providers.OpenAI.chat(
  "Tell me a short story about a programmer.",
  %{stream: true}
)
|> Stream.map(fn chunk ->
  chunk.choices
  |> Enum.map(& &1.delta.content)
  |> Enum.join("")
end)
|> Stream.each(&IO.write/1)
|> Stream.run()
