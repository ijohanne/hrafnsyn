defmodule Hrafnsyn.Aircraft.Metadata do
  @moduledoc false

  @full_alphabet "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
  @limited_alphabet "ABCDEFGHJKLMNPQRSTUVWXYZ"

  @country_name_overrides %{
    "Congo" => "Republic of the Congo",
    "Democratic People's Republic of Korea" => "North Korea",
    "Democratic Republic of the Congo" => "Congo DRC",
    "Iran, Islamic Republic of" => "Iran",
    "Lao People's Democratic Republic" => "Laos",
    "Libyan Arab Jamahiriya" => "Libya",
    "Micronesia, Federated States of" => "Micronesia",
    "Netherlands, Kingdom of the" => "Netherlands",
    "Republic of Korea" => "South Korea",
    "Republic of Moldova" => "Moldova",
    "Syrian Arab Republic" => "Syria",
    "The former Yugoslav Republic of Macedonia" => "North Macedonia",
    "United Republic of Tanzania" => "Tanzania",
    "Viet Nam" => "Vietnam"
  }

  @country_ranges [
    {0x700000, 0x700FFF, "Afghanistan"},
    {0x501000, 0x5013FF, "Albania"},
    {0x0A0000, 0x0A7FFF, "Algeria"},
    {0x090000, 0x090FFF, "Angola"},
    {0x0CA000, 0x0CA3FF, "Antigua and Barbuda"},
    {0xE00000, 0xE3FFFF, "Argentina"},
    {0x600000, 0x6003FF, "Armenia"},
    {0x7C0000, 0x7FFFFF, "Australia"},
    {0x440000, 0x447FFF, "Austria"},
    {0x600800, 0x600BFF, "Azerbaijan"},
    {0x0A8000, 0x0A8FFF, "Bahamas"},
    {0x894000, 0x894FFF, "Bahrain"},
    {0x702000, 0x702FFF, "Bangladesh"},
    {0x0AA000, 0x0AA3FF, "Barbados"},
    {0x510000, 0x5103FF, "Belarus"},
    {0x448000, 0x44FFFF, "Belgium"},
    {0x0AB000, 0x0AB3FF, "Belize"},
    {0x094000, 0x0943FF, "Benin"},
    {0x680000, 0x6803FF, "Bhutan"},
    {0xE94000, 0xE94FFF, "Bolivia"},
    {0x513000, 0x5133FF, "Bosnia and Herzegovina"},
    {0x030000, 0x0303FF, "Botswana"},
    {0xE40000, 0xE7FFFF, "Brazil"},
    {0x895000, 0x8953FF, "Brunei Darussalam"},
    {0x450000, 0x457FFF, "Bulgaria"},
    {0x09C000, 0x09CFFF, "Burkina Faso"},
    {0x032000, 0x032FFF, "Burundi"},
    {0x70E000, 0x70EFFF, "Cambodia"},
    {0x034000, 0x034FFF, "Cameroon"},
    {0xC00000, 0xC3FFFF, "Canada"},
    {0x096000, 0x0963FF, "Cape Verde"},
    {0x06C000, 0x06CFFF, "Central African Republic"},
    {0x084000, 0x084FFF, "Chad"},
    {0xE80000, 0xE80FFF, "Chile"},
    {0x780000, 0x7BFFFF, "China"},
    {0x0AC000, 0x0ACFFF, "Colombia"},
    {0x035000, 0x0353FF, "Comoros"},
    {0x036000, 0x036FFF, "Congo"},
    {0x901000, 0x9013FF, "Cook Islands"},
    {0x0AE000, 0x0AEFFF, "Costa Rica"},
    {0x038000, 0x038FFF, "Cote d'Ivoire"},
    {0x501C00, 0x501FFF, "Croatia"},
    {0x0B0000, 0x0B0FFF, "Cuba"},
    {0x4C8000, 0x4C83FF, "Cyprus"},
    {0x498000, 0x49FFFF, "Czech Republic"},
    {0x720000, 0x727FFF, "Democratic People's Republic of Korea"},
    {0x08C000, 0x08CFFF, "Democratic Republic of the Congo"},
    {0x458000, 0x45FFFF, "Denmark"},
    {0x098000, 0x0983FF, "Djibouti"},
    {0x0C4000, 0x0C4FFF, "Dominican Republic"},
    {0xE84000, 0xE84FFF, "Ecuador"},
    {0x010000, 0x017FFF, "Egypt"},
    {0x0B2000, 0x0B2FFF, "El Salvador"},
    {0x042000, 0x042FFF, "Equatorial Guinea"},
    {0x202000, 0x2023FF, "Eritrea"},
    {0x511000, 0x5113FF, "Estonia"},
    {0x040000, 0x040FFF, "Ethiopia"},
    {0xC88000, 0xC88FFF, "Fiji"},
    {0x460000, 0x467FFF, "Finland"},
    {0x380000, 0x3BFFFF, "France"},
    {0x03E000, 0x03EFFF, "Gabon"},
    {0x09A000, 0x09AFFF, "Gambia"},
    {0x514000, 0x5143FF, "Georgia"},
    {0x3C0000, 0x3FFFFF, "Germany"},
    {0x044000, 0x044FFF, "Ghana"},
    {0x468000, 0x46FFFF, "Greece"},
    {0x0CC000, 0x0CC3FF, "Grenada"},
    {0x0B4000, 0x0B4FFF, "Guatemala"},
    {0x046000, 0x046FFF, "Guinea"},
    {0x048000, 0x0483FF, "Guinea-Bissau"},
    {0x0B6000, 0x0B6FFF, "Guyana"},
    {0x0B8000, 0x0B8FFF, "Haiti"},
    {0x0BA000, 0x0BAFFF, "Honduras"},
    {0x470000, 0x477FFF, "Hungary"},
    {0x4CC000, 0x4CCFFF, "Iceland"},
    {0x800000, 0x83FFFF, "India"},
    {0x8A0000, 0x8A7FFF, "Indonesia"},
    {0x730000, 0x737FFF, "Iran, Islamic Republic of"},
    {0x728000, 0x72FFFF, "Iraq"},
    {0x4CA000, 0x4CAFFF, "Ireland"},
    {0x738000, 0x73FFFF, "Israel"},
    {0x300000, 0x33FFFF, "Italy"},
    {0x0BE000, 0x0BEFFF, "Jamaica"},
    {0x840000, 0x87FFFF, "Japan"},
    {0x740000, 0x747FFF, "Jordan"},
    {0x683000, 0x6833FF, "Kazakhstan"},
    {0x04C000, 0x04CFFF, "Kenya"},
    {0xC8E000, 0xC8E3FF, "Kiribati"},
    {0x706000, 0x706FFF, "Kuwait"},
    {0x601000, 0x6013FF, "Kyrgyzstan"},
    {0x708000, 0x708FFF, "Lao People's Democratic Republic"},
    {0x502C00, 0x502FFF, "Latvia"},
    {0x748000, 0x74FFFF, "Lebanon"},
    {0x04A000, 0x04A3FF, "Lesotho"},
    {0x050000, 0x050FFF, "Liberia"},
    {0x018000, 0x01FFFF, "Libyan Arab Jamahiriya"},
    {0x503C00, 0x503FFF, "Lithuania"},
    {0x4D0000, 0x4D03FF, "Luxembourg"},
    {0x054000, 0x054FFF, "Madagascar"},
    {0x058000, 0x058FFF, "Malawi"},
    {0x750000, 0x757FFF, "Malaysia"},
    {0x05A000, 0x05A3FF, "Maldives"},
    {0x05C000, 0x05CFFF, "Mali"},
    {0x4D2000, 0x4D23FF, "Malta"},
    {0x900000, 0x9003FF, "Marshall Islands"},
    {0x05E000, 0x05E3FF, "Mauritania"},
    {0x060000, 0x0603FF, "Mauritius"},
    {0x0D0000, 0x0D7FFF, "Mexico"},
    {0x681000, 0x6813FF, "Micronesia, Federated States of"},
    {0x4D4000, 0x4D43FF, "Monaco"},
    {0x682000, 0x6823FF, "Mongolia"},
    {0x516000, 0x5163FF, "Montenegro"},
    {0x020000, 0x027FFF, "Morocco"},
    {0x006000, 0x006FFF, "Mozambique"},
    {0x704000, 0x704FFF, "Myanmar"},
    {0x201000, 0x2013FF, "Namibia"},
    {0xC8A000, 0xC8A3FF, "Nauru"},
    {0x70A000, 0x70AFFF, "Nepal"},
    {0x480000, 0x487FFF, "Netherlands, Kingdom of the"},
    {0xC80000, 0xC87FFF, "New Zealand"},
    {0x0C0000, 0x0C0FFF, "Nicaragua"},
    {0x062000, 0x062FFF, "Niger"},
    {0x064000, 0x064FFF, "Nigeria"},
    {0x478000, 0x47FFFF, "Norway"},
    {0x70C000, 0x70C3FF, "Oman"},
    {0x760000, 0x767FFF, "Pakistan"},
    {0x684000, 0x6843FF, "Palau"},
    {0x0C2000, 0x0C2FFF, "Panama"},
    {0x898000, 0x898FFF, "Papua New Guinea"},
    {0xE88000, 0xE88FFF, "Paraguay"},
    {0xE8C000, 0xE8CFFF, "Peru"},
    {0x758000, 0x75FFFF, "Philippines"},
    {0x488000, 0x48FFFF, "Poland"},
    {0x490000, 0x497FFF, "Portugal"},
    {0x06A000, 0x06A3FF, "Qatar"},
    {0x718000, 0x71FFFF, "Republic of Korea"},
    {0x504C00, 0x504FFF, "Republic of Moldova"},
    {0x4A0000, 0x4A7FFF, "Romania"},
    {0x100000, 0x1FFFFF, "Russian Federation"},
    {0x06E000, 0x06EFFF, "Rwanda"},
    {0xC8C000, 0xC8C3FF, "Saint Lucia"},
    {0x0BC000, 0x0BC3FF, "Saint Vincent and the Grenadines"},
    {0x902000, 0x9023FF, "Samoa"},
    {0x500000, 0x5003FF, "San Marino"},
    {0x09E000, 0x09E3FF, "Sao Tome and Principe"},
    {0x710000, 0x717FFF, "Saudi Arabia"},
    {0x070000, 0x070FFF, "Senegal"},
    {0x4C0000, 0x4C7FFF, "Serbia"},
    {0x074000, 0x0743FF, "Seychelles"},
    {0x076000, 0x0763FF, "Sierra Leone"},
    {0x768000, 0x76FFFF, "Singapore"},
    {0x505C00, 0x505FFF, "Slovakia"},
    {0x506C00, 0x506FFF, "Slovenia"},
    {0x897000, 0x8973FF, "Solomon Islands"},
    {0x078000, 0x078FFF, "Somalia"},
    {0x008000, 0x00FFFF, "South Africa"},
    {0x340000, 0x37FFFF, "Spain"},
    {0x770000, 0x777FFF, "Sri Lanka"},
    {0x07C000, 0x07CFFF, "Sudan"},
    {0x0C8000, 0x0C8FFF, "Suriname"},
    {0x07A000, 0x07A3FF, "Swaziland"},
    {0x4A8000, 0x4AFFFF, "Sweden"},
    {0x4B0000, 0x4B7FFF, "Switzerland"},
    {0x778000, 0x77FFFF, "Syrian Arab Republic"},
    {0x515000, 0x5153FF, "Tajikistan"},
    {0x880000, 0x887FFF, "Thailand"},
    {0x512000, 0x5123FF, "The former Yugoslav Republic of Macedonia"},
    {0x088000, 0x088FFF, "Togo"},
    {0xC8D000, 0xC8D3FF, "Tonga"},
    {0x0C6000, 0x0C6FFF, "Trinidad and Tobago"},
    {0x028000, 0x02FFFF, "Tunisia"},
    {0x4B8000, 0x4BFFFF, "Turkey"},
    {0x601800, 0x601BFF, "Turkmenistan"},
    {0x068000, 0x068FFF, "Uganda"},
    {0x508000, 0x50FFFF, "Ukraine"},
    {0x896000, 0x896FFF, "United Arab Emirates"},
    {0x400000, 0x43FFFF, "United Kingdom"},
    {0x080000, 0x080FFF, "United Republic of Tanzania"},
    {0xA00000, 0xAFFFFF, "United States"},
    {0xE90000, 0xE90FFF, "Uruguay"},
    {0x507C00, 0x507FFF, "Uzbekistan"},
    {0xC90000, 0xC903FF, "Vanuatu"},
    {0x0D8000, 0x0DFFFF, "Venezuela"},
    {0x888000, 0x88FFFF, "Viet Nam"},
    {0x890000, 0x890FFF, "Yemen"},
    {0x08A000, 0x08AFFF, "Zambia"},
    {0x004000, 0x0043FF, "Zimbabwe"}
  ]

  @registration_stride_mappings [
    %{start: 0x008011, s1: 26 * 26, s2: 26, prefix: "ZS-"},
    %{start: 0x390000, s1: 1024, s2: 32, prefix: "F-G"},
    %{start: 0x398000, s1: 1024, s2: 32, prefix: "F-H"},
    %{start: 0x3C4421, s1: 1024, s2: 32, prefix: "D-A", first: "AAA", last: "OZZ"},
    %{start: 0x3C0001, s1: 26 * 26, s2: 26, prefix: "D-A", first: "PAA", last: "ZZZ"},
    %{start: 0x3C8421, s1: 1024, s2: 32, prefix: "D-B", first: "AAA", last: "OZZ"},
    %{start: 0x3C2001, s1: 26 * 26, s2: 26, prefix: "D-B", first: "PAA", last: "ZZZ"},
    %{start: 0x3CC000, s1: 26 * 26, s2: 26, prefix: "D-C"},
    %{start: 0x3D04A8, s1: 26 * 26, s2: 26, prefix: "D-E"},
    %{start: 0x3D4950, s1: 26 * 26, s2: 26, prefix: "D-F"},
    %{start: 0x3D8DF8, s1: 26 * 26, s2: 26, prefix: "D-G"},
    %{start: 0x3DD2A0, s1: 26 * 26, s2: 26, prefix: "D-H"},
    %{start: 0x3E1748, s1: 26 * 26, s2: 26, prefix: "D-I"},
    %{start: 0x448421, s1: 1024, s2: 32, prefix: "OO-"},
    %{start: 0x458421, s1: 1024, s2: 32, prefix: "OY-"},
    %{start: 0x460000, s1: 26 * 26, s2: 26, prefix: "OH-"},
    %{start: 0x468421, s1: 1024, s2: 32, prefix: "SX-"},
    %{start: 0x490421, s1: 1024, s2: 32, prefix: "CS-"},
    %{start: 0x4A0421, s1: 1024, s2: 32, prefix: "YR-"},
    %{start: 0x4B8421, s1: 1024, s2: 32, prefix: "TC-"},
    %{start: 0x740421, s1: 1024, s2: 32, prefix: "JY-"},
    %{start: 0x760421, s1: 1024, s2: 32, prefix: "AP-"},
    %{start: 0x768421, s1: 1024, s2: 32, prefix: "9V-"},
    %{start: 0x778421, s1: 1024, s2: 32, prefix: "YK-"},
    %{start: 0x7C0000, s1: 36 * 36, s2: 36, prefix: "VH-"},
    %{start: 0xC00001, s1: 26 * 26, s2: 26, prefix: "C-F"},
    %{start: 0xC044A9, s1: 26 * 26, s2: 26, prefix: "C-G"},
    %{start: 0xE01041, s1: 4096, s2: 64, prefix: "LV-"}
  ]

  @registration_numeric_mappings [
    %{start: 0x140000, first: 0, count: 100_000, template: "RA-00000"},
    %{start: 0x0B03E8, first: 1000, count: 1000, template: "CU-T0000"}
  ]

  @spec derive(String.t() | nil) :: %{country: String.t() | nil, registration: String.t() | nil}
  def derive(identity) when is_binary(identity) do
    case parse_hex(identity) do
      {:ok, hexid} ->
        %{
          country: country_from_hexid(hexid),
          registration: registration_from_hexid(hexid)
        }

      :error ->
        %{country: nil, registration: nil}
    end
  end

  def derive(_identity), do: %{country: nil, registration: nil}

  defp parse_hex(identity) do
    identity
    |> String.trim()
    |> String.upcase()
    |> Integer.parse(16)
    |> case do
      {hexid, ""} when hexid >= 0 and hexid <= 0xFFFFFF -> {:ok, hexid}
      _other -> :error
    end
  end

  defp country_from_hexid(hexid) do
    Enum.find_value(@country_ranges, fn {start_hexid, end_hexid, country} ->
      if hexid >= start_hexid and hexid <= end_hexid do
        Map.get(@country_name_overrides, country, country)
      end
    end)
  end

  defp registration_from_hexid(hexid) do
    n_number_registration(hexid) ||
      japan_registration(hexid) ||
      south_korea_registration(hexid) ||
      numeric_registration(hexid) ||
      stride_registration(hexid)
  end

  defp stride_registration(hexid) do
    Enum.find_value(@registration_stride_mappings, &stride_registration_from_mapping(&1, hexid))
  end

  defp stride_registration_from_mapping(mapping, hexid) do
    alphabet = Map.get(mapping, :alphabet, @full_alphabet)
    offset = suffix_offset(alphabet, Map.get(mapping, :first, "AAA"), mapping.s1, mapping.s2)
    end_hexid = stride_end(mapping, alphabet, offset)

    if hexid < mapping.start or hexid > end_hexid do
      nil
    else
      build_stride_registration(mapping, alphabet, hexid - mapping.start + offset)
    end
  end

  defp build_stride_registration(mapping, alphabet, offset) do
    first_index = div(offset, mapping.s1)
    remainder = rem(offset, mapping.s1)
    second_index = div(remainder, mapping.s2)
    third_index = rem(remainder, mapping.s2)

    with first_char when is_binary(first_char) <- String.at(alphabet, first_index),
         second_char when is_binary(second_char) <- String.at(alphabet, second_index),
         third_char when is_binary(third_char) <- String.at(alphabet, third_index) do
      mapping.prefix <> first_char <> second_char <> third_char
    else
      _other -> nil
    end
  end

  defp stride_end(mapping, alphabet, offset) do
    last =
      Map.get_lazy(mapping, :last, fn ->
        last_index = String.length(alphabet) - 1

        String.at(alphabet, last_index) <>
          String.at(alphabet, last_index) <> String.at(alphabet, last_index)
      end)

    mapping.start - offset + suffix_offset(alphabet, last, mapping.s1, mapping.s2)
  end

  defp suffix_offset(alphabet, suffix, s1, s2) do
    [first_char, second_char, third_char] = String.graphemes(suffix)

    first_index = alphabet_index(alphabet, first_char)
    second_index = alphabet_index(alphabet, second_char)
    third_index = alphabet_index(alphabet, third_char)

    first_index * s1 + second_index * s2 + third_index
  end

  defp alphabet_index(alphabet, char) do
    alphabet
    |> String.graphemes()
    |> Enum.find_index(&(&1 == char))
    |> Kernel.||(0)
  end

  defp numeric_registration(hexid) do
    Enum.find_value(@registration_numeric_mappings, fn mapping ->
      end_hexid = mapping.start + mapping.count - 1

      if hexid < mapping.start or hexid > end_hexid do
        nil
      else
        value = Integer.to_string(hexid - mapping.start + mapping.first)
        prefix_length = String.length(mapping.template) - String.length(value)
        String.slice(mapping.template, 0, prefix_length) <> value
      end
    end)
  end

  defp n_number_registration(hexid) do
    offset = hexid - 0xA00001

    if offset < 0 or offset >= 915_399 do
      nil
    else
      first_digit = div(offset, 101_711) + 1
      build_n_number("N#{first_digit}", rem(offset, 101_711))
    end
  end

  defp build_n_number(registration, offset) when offset <= 600,
    do: registration <> n_letters(offset)

  defp build_n_number(registration, offset) do
    offset = offset - 601
    second_digit = div(offset, 10_111)
    build_n_number_second(registration <> Integer.to_string(second_digit), rem(offset, 10_111))
  end

  defp build_n_number_second(registration, offset) when offset <= 600,
    do: registration <> n_letters(offset)

  defp build_n_number_second(registration, offset) do
    offset = offset - 601
    third_digit = div(offset, 951)
    build_n_number_third(registration <> Integer.to_string(third_digit), rem(offset, 951))
  end

  defp build_n_number_third(registration, offset) when offset <= 600,
    do: registration <> n_letters(offset)

  defp build_n_number_third(registration, offset) do
    offset = offset - 601
    fourth_digit = div(offset, 35)
    finish_n_number(registration <> Integer.to_string(fourth_digit), rem(offset, 35))
  end

  defp finish_n_number(registration, offset) when offset <= 24,
    do: registration <> n_letter(offset)

  defp finish_n_number(registration, offset),
    do: registration <> Integer.to_string(offset - 25)

  defp n_letters(0), do: ""

  defp n_letters(offset) do
    offset = offset - 1
    String.at(@limited_alphabet, div(offset, 25)) <> n_letter(rem(offset, 25))
  end

  defp n_letter(0), do: ""

  defp n_letter(offset) do
    offset = offset - 1
    String.at(@limited_alphabet, offset)
  end

  defp south_korea_registration(hexid) when hexid >= 0x71BA00 and hexid <= 0x71BF99 do
    ("HL" <> Integer.to_string(hexid - 0x71BA00 + 0x7200, 16)) |> String.upcase()
  end

  defp south_korea_registration(hexid) when hexid >= 0x71C000 and hexid <= 0x71C099 do
    ("HL" <> Integer.to_string(hexid - 0x71C000 + 0x8000, 16)) |> String.upcase()
  end

  defp south_korea_registration(hexid) when hexid >= 0x71C200 and hexid <= 0x71C299 do
    ("HL" <> Integer.to_string(hexid - 0x71C200 + 0x8200, 16)) |> String.upcase()
  end

  defp south_korea_registration(_hexid), do: nil

  defp japan_registration(hexid) do
    offset = hexid - 0x840000

    if offset < 0 or offset >= 229_840 do
      nil
    else
      first_digit = div(offset, 22_984)
      offset = rem(offset, 22_984)
      second_digit = div(offset, 916)
      offset = rem(offset, 916)
      registration = "JA#{first_digit}#{second_digit}"

      if offset < 340 do
        build_japan_numeric_registration(registration, offset)
      else
        build_japan_alpha_registration(registration, offset - 340)
      end
    end
  end

  defp build_japan_numeric_registration(registration, offset) do
    third_digit = div(offset, 34)
    remainder = rem(offset, 34)
    registration = registration <> Integer.to_string(third_digit)

    if remainder < 10 do
      registration <> Integer.to_string(remainder)
    else
      registration <> String.at(@limited_alphabet, remainder - 10)
    end
  end

  defp build_japan_alpha_registration(registration, offset) do
    third_letter = div(offset, 24)
    fourth_letter = rem(offset, 24)

    registration <>
      String.at(@limited_alphabet, third_letter) <>
      String.at(@limited_alphabet, fourth_letter)
  end
end
