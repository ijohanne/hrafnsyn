defmodule Hrafnsyn.GeometryType do
  @moduledoc """
  Minimal Ecto type for PostGIS-backed Geo structs.
  """

  use Ecto.Type

  alias Geo.{
    GeometryCollection,
    LineString,
    LineStringZ,
    LineStringZM,
    MultiLineString,
    MultiLineStringZ,
    MultiPoint,
    MultiPointZ,
    MultiPolygon,
    MultiPolygonZ,
    Point,
    PointM,
    PointZ,
    PointZM,
    Polygon,
    PolygonZ
  }

  @geometries [
    Point,
    PointM,
    PointZ,
    PointZM,
    LineString,
    LineStringZ,
    LineStringZM,
    Polygon,
    PolygonZ,
    MultiPoint,
    MultiPointZ,
    MultiLineString,
    MultiLineStringZ,
    MultiPolygon,
    MultiPolygonZ,
    GeometryCollection
  ]

  @impl true
  def type, do: :geometry

  @impl true
  def cast(%struct{} = geometry) when struct in @geometries, do: {:ok, geometry}
  def cast(_value), do: :error

  @impl true
  def load(%struct{} = geometry) when struct in @geometries, do: {:ok, geometry}
  def load(_value), do: :error

  @impl true
  def dump(%struct{} = geometry) when struct in @geometries, do: {:ok, geometry}
  def dump(_value), do: :error

  @impl true
  def embed_as(_format), do: :self

  @impl true
  def equal?(left, right), do: left == right
end
