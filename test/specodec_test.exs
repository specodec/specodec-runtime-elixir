defmodule SpecodecTest do
  use ExUnit.Case
  doctest Specodec

  test "greets the world" do
    assert Specodec.hello() == :world
  end
end
