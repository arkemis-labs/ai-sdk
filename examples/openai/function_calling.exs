# Example of function calling with OpenAI provider
# Run with: mix run examples/openai/function_calling.exs

defmodule WeatherService do
  def get_weather(location) do
    # Simulated weather data
    %{
      temperature: :rand.uniform(30) + 10,  # Random temp between 10-40°C
      conditions: Enum.random(["sunny", "cloudy", "rainy", "partly cloudy"]),
      location: location,
      timestamp: DateTime.utc_now() |> DateTime.to_string()
    }
  end
end

# Define available functions
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
    },
    callback: fn %{"location" => location} ->
      WeatherService.get_weather(location)
    end
  }
]

# Example 1: Basic weather query
IO.puts("\n--- Example 1: Basic Weather Query ---")
case Ai.Providers.OpenAI.chat(
  "What's the weather like in Tokyo right now?",
  %{functions: functions, function_call: "auto"}
) do
  {:ok, response} -> IO.inspect(response, label: "Response")
  {:error, error} -> IO.inspect(error, label: "Error")
end

# Example 2: Multiple locations query
IO.puts("\n--- Example 2: Multiple Locations Query ---")
case Ai.Providers.OpenAI.chat(
  "Compare the weather in New York and London.",
  %{functions: functions, function_call: "auto"}
) do
  {:ok, response} -> IO.inspect(response, label: "Response")
  {:error, error} -> IO.inspect(error, label: "Error")
end
