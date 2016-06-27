defmodule Braintree.XML do
  @moduledoc """
  Simplified XML handling module that only supports `dump` and `load`.
  """

  @doctype ~s|<?xml version="1.0" encoding="UTF-8" ?>|

  @type xml :: binary

  @xml_escape_entities [
    {~r/&/, "&amp;"},
    {~r/"/, "&quot;"},
    {~r/'/, "&apos;"},
    {~r/</, "&lt;"},
    {~r/>/, "&gt;"}
  ]

  import Braintree.Util, only: [hyphenate: 1, underscorize: 1]

  @doc ~S"""
  Converts a map into the equivalent XML representation.

  ## Examples

      iex> Braintree.XML.dump(%{a: %{b: 1, c: "Two & 3"}})
      ~s|<?xml version="1.0" encoding="UTF-8" ?>\n<a>\n<b>1</b>\n<c>Two &amp; 3</c>\n</a>|
  """
  @spec dump(Map.t) :: xml
  def dump(map) do
    generate([@doctype | Enum.into(escape_xml_entity(map), [])])
  end

  defp generate(term) when is_binary(term),
    do: term

  defp generate(term) when is_map(term),
    do: term |> Enum.into([]) |> generate

  defp generate(term) when is_list(term),
    do: term |> Enum.map(&generate/1) |> Enum.intersperse("\n") |> Enum.join

  defp generate({name, value}) when is_map(value),
    do: "<#{hyphenate(name)}>\n#{generate(value)}\n</#{hyphenate(name)}>"

  defp generate({name, value}) when is_list(value),
    do: generate({name, "\n#{generate(value)}\n"})

  defp generate({name, value}),
    do: "<#{hyphenate(name)}>#{value}</#{hyphenate(name)}>"

  defp escape_xml_entity(str) when is_binary(str) do
    @xml_escape_entities
    |> Enum.reduce(str, fn {regex, val}, str -> String.replace(str, regex, val) end)
  end

  defp escape_xml_entity(map) when is_map(map) do
    map
    |> Enum.reduce(%{}, fn {key, value}, m -> Map.put(m, key, escape_xml_entity(value)) end)
  end

  defp escape_xml_entity(list) when is_list(list) do
    list
    |> Enum.reduce([], fn value, l -> l ++ [escape_xml_entity(value)] end)
  end

  defp escape_xml_entity(other), do: other

  @doc ~S"""
  Converts an XML document, or fragment, into a map. Type annotation
  attributes are respected, but all other attributes are ignored.

  ## Examples

      iex> Braintree.XML.load("<a><b type='integer'>1</b><c>2</c></a>")
      %{"a" => %{"b" => 1, "c" => "2"}}
  """
  @spec load(xml) :: Map.t
  def load(""), do: %{}

  def load(xml) do
    {name, _, values} =
      xml
      |> :erlang.bitstring_to_list
      |> :xmerl_scan.string
      |> elem(0)
      |> parse

    %{name => transform(values)}
  end

  defp parse(elements) when is_list(elements),
    do: Enum.map(elements, &parse/1)

  defp parse({:xmlElement, name, _, _, _, _, _, attributes, elements, _, _, _}),
    do: {underscorize(name), parse(attributes), parse(elements)}

  defp parse({:xmlAttribute, name, _, _, _, _, _, _, value, _}),
    do: {name, to_string(value)}

  defp parse({:xmlText, _, _, _, value, _}) do
    value
    |> to_string
    |> String.strip
    |> List.wrap
    |> Enum.reject(&(&1 == ""))
    |> List.first
  end

  defp transform(elements) when is_list(elements) do
    if is_text_list?(elements) do
      Enum.join(elements, "")
    else
      Enum.into(without_nil(elements), %{}, &transform/1)
    end
  end

  defp transform({name, [type: "integer"], [value]}),
    do: {name, String.to_integer(value)}

  defp transform({name, [type: "array"], elements}),
    do: {name, Enum.map(without_nil(elements), &(elem(transform(&1), 1)))}

  defp transform({name, [type: "boolean"], [value]}),
    do: {name, value == "true"}

  defp transform({name, [nil: "true"], []}),
    do: {name, nil}

  defp transform({name, _, [value]}),
    do: {name, value}

  defp transform({name, _, []}),
    do: {name, ""}

  defp transform({name, _, values}),
    do: {name, transform(values)}

  defp without_nil(list),
    do: Enum.reject(list, &Kernel.==(&1, nil))

  defp is_text_list?([last]) when is_binary(last), do: true
  defp is_text_list?([hd|rest]) when is_binary(hd), do: is_text_list?(rest)
  defp is_text_list?(_), do: false
end
