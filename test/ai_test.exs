defmodule AiTest do
  use ExUnit.Case
  doctest Ai

  test "greets the world" do
    assert Ai.hello() == :world
  end
end
