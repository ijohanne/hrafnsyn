defmodule Hrafnsyn.CountryFlags do
  @moduledoc false

  @country_name_to_code %{
    "afghanistan" => "AF",
    "albania" => "AL",
    "algeria" => "DZ",
    "american samoa" => "AS",
    "andorra" => "AD",
    "angola" => "AO",
    "anguilla" => "AI",
    "antarctica" => "AQ",
    "antigua and barbuda" => "AG",
    "argentina" => "AR",
    "armenia" => "AM",
    "aruba" => "AW",
    "australia" => "AU",
    "austria" => "AT",
    "azerbaijan" => "AZ",
    "bahamas" => "BS",
    "bahrain" => "BH",
    "bangladesh" => "BD",
    "barbados" => "BB",
    "belarus" => "BY",
    "belgium" => "BE",
    "belize" => "BZ",
    "benin" => "BJ",
    "bermuda" => "BM",
    "bhutan" => "BT",
    "bolivia plurinational state of" => "BO",
    "bonaire sint eustatius and saba" => "BQ",
    "bosnia and herzegovina" => "BA",
    "botswana" => "BW",
    "bouvet island" => "BV",
    "brazil" => "BR",
    "british indian ocean territory" => "IO",
    "brunei darussalam" => "BN",
    "bulgaria" => "BG",
    "burkina faso" => "BF",
    "burundi" => "BI",
    "cambodia" => "KH",
    "cameroon" => "CM",
    "canada" => "CA",
    "cape verde" => "CV",
    "cayman islands" => "KY",
    "central african republic" => "CF",
    "chad" => "TD",
    "chile" => "CL",
    "china" => "CN",
    "christmas island" => "CX",
    "cocos keeling islands" => "CC",
    "colombia" => "CO",
    "comoros" => "KM",
    "congo" => "CG",
    "congo the democratic republic of the" => "CD",
    "cook islands" => "CK",
    "costa rica" => "CR",
    "croatia" => "HR",
    "cuba" => "CU",
    "curacao" => "CW",
    "cyprus" => "CY",
    "czech republic" => "CZ",
    "cote d ivoire" => "CI",
    "denmark" => "DK",
    "djibouti" => "DJ",
    "dominica" => "DM",
    "dominican republic" => "DO",
    "ecuador" => "EC",
    "egypt" => "EG",
    "el salvador" => "SV",
    "equatorial guinea" => "GQ",
    "eritrea" => "ER",
    "estonia" => "EE",
    "ethiopia" => "ET",
    "falkland islands malvinas" => "FK",
    "faroe islands" => "FO",
    "fiji" => "FJ",
    "finland" => "FI",
    "france" => "FR",
    "french guiana" => "GF",
    "french polynesia" => "PF",
    "french southern territories" => "TF",
    "gabon" => "GA",
    "gambia" => "GM",
    "georgia" => "GE",
    "germany" => "DE",
    "ghana" => "GH",
    "gibraltar" => "GI",
    "greece" => "GR",
    "greenland" => "GL",
    "grenada" => "GD",
    "guadeloupe" => "GP",
    "guam" => "GU",
    "guatemala" => "GT",
    "guernsey" => "GG",
    "guinea" => "GN",
    "guinea bissau" => "GW",
    "guyana" => "GY",
    "haiti" => "HT",
    "heard island and mcdonald islands" => "HM",
    "holy see vatican city state" => "VA",
    "honduras" => "HN",
    "hong kong" => "HK",
    "hungary" => "HU",
    "iceland" => "IS",
    "india" => "IN",
    "indonesia" => "ID",
    "iran islamic republic of" => "IR",
    "iraq" => "IQ",
    "ireland" => "IE",
    "isle of man" => "IM",
    "israel" => "IL",
    "italy" => "IT",
    "jamaica" => "JM",
    "japan" => "JP",
    "jersey" => "JE",
    "jordan" => "JO",
    "kazakhstan" => "KZ",
    "kenya" => "KE",
    "kiribati" => "KI",
    "korea democratic people s republic of" => "KP",
    "korea republic of" => "KR",
    "kuwait" => "KW",
    "kyrgyzstan" => "KG",
    "lao people s democratic republic" => "LA",
    "latvia" => "LV",
    "lebanon" => "LB",
    "lesotho" => "LS",
    "liberia" => "LR",
    "libya" => "LY",
    "liechtenstein" => "LI",
    "lithuania" => "LT",
    "luxembourg" => "LU",
    "macao" => "MO",
    "macedonia the former yugoslav republic of" => "MK",
    "madagascar" => "MG",
    "malawi" => "MW",
    "malaysia" => "MY",
    "maldives" => "MV",
    "mali" => "ML",
    "malta" => "MT",
    "marshall islands" => "MH",
    "martinique" => "MQ",
    "mauritania" => "MR",
    "mauritius" => "MU",
    "mayotte" => "YT",
    "mexico" => "MX",
    "micronesia federated states of" => "FM",
    "moldova republic of" => "MD",
    "monaco" => "MC",
    "mongolia" => "MN",
    "montenegro" => "ME",
    "montserrat" => "MS",
    "morocco" => "MA",
    "mozambique" => "MZ",
    "myanmar" => "MM",
    "namibia" => "NA",
    "nauru" => "NR",
    "nepal" => "NP",
    "netherlands" => "NL",
    "new caledonia" => "NC",
    "new zealand" => "NZ",
    "nicaragua" => "NI",
    "niger" => "NE",
    "nigeria" => "NG",
    "niue" => "NU",
    "norfolk island" => "NF",
    "northern mariana islands" => "MP",
    "norway" => "NO",
    "oman" => "OM",
    "pakistan" => "PK",
    "palau" => "PW",
    "palestinian territory occupied" => "PS",
    "panama" => "PA",
    "papua new guinea" => "PG",
    "paraguay" => "PY",
    "peru" => "PE",
    "philippines" => "PH",
    "pitcairn" => "PN",
    "poland" => "PL",
    "portugal" => "PT",
    "puerto rico" => "PR",
    "qatar" => "QA",
    "romania" => "RO",
    "russian federation" => "RU",
    "rwanda" => "RW",
    "reunion" => "RE",
    "saint barthelemy" => "BL",
    "saint helena ascension and tristan da cunha" => "SH",
    "saint kitts and nevis" => "KN",
    "saint lucia" => "LC",
    "saint martin french part" => "MF",
    "saint pierre and miquelon" => "PM",
    "saint vincent and the grenadines" => "VC",
    "samoa" => "WS",
    "san marino" => "SM",
    "sao tome and principe" => "ST",
    "saudi arabia" => "SA",
    "senegal" => "SN",
    "serbia" => "RS",
    "seychelles" => "SC",
    "sierra leone" => "SL",
    "singapore" => "SG",
    "sint maarten dutch part" => "SX",
    "slovakia" => "SK",
    "slovenia" => "SI",
    "solomon islands" => "SB",
    "somalia" => "SO",
    "south africa" => "ZA",
    "south georgia and the south sandwich islands" => "GS",
    "south sudan" => "SS",
    "spain" => "ES",
    "sri lanka" => "LK",
    "sudan" => "SD",
    "suriname" => "SR",
    "svalbard and jan mayen" => "SJ",
    "swaziland" => "SZ",
    "sweden" => "SE",
    "switzerland" => "CH",
    "syrian arab republic" => "SY",
    "taiwan province of china" => "TW",
    "tajikistan" => "TJ",
    "tanzania united republic of" => "TZ",
    "thailand" => "TH",
    "timor leste" => "TL",
    "togo" => "TG",
    "tokelau" => "TK",
    "tonga" => "TO",
    "trinidad and tobago" => "TT",
    "tunisia" => "TN",
    "turkey" => "TR",
    "turkmenistan" => "TM",
    "turks and caicos islands" => "TC",
    "tuvalu" => "TV",
    "uganda" => "UG",
    "ukraine" => "UA",
    "united arab emirates" => "AE",
    "united kingdom" => "GB",
    "united states" => "US",
    "united states minor outlying islands" => "UM",
    "uruguay" => "UY",
    "uzbekistan" => "UZ",
    "vanuatu" => "VU",
    "venezuela bolivarian republic of" => "VE",
    "viet nam" => "VN",
    "virgin islands british" => "VG",
    "virgin islands u s" => "VI",
    "wallis and futuna" => "WF",
    "western sahara" => "EH",
    "yemen" => "YE",
    "zambia" => "ZM",
    "zimbabwe" => "ZW",
    "aland islands" => "AX"
  }

  @country_aliases %{
    "bolivia" => "BO",
    "brunei" => "BN",
    "cabo verde" => "CV",
    "congo drc" => "CD",
    "congo kinshasa" => "CD",
    "congo republic" => "CG",
    "curacao" => "CW",
    "czechia" => "CZ",
    "eswatini" => "SZ",
    "holy see" => "VA",
    "iran" => "IR",
    "ivory coast" => "CI",
    "laos" => "LA",
    "macau" => "MO",
    "micronesia" => "FM",
    "moldova" => "MD",
    "north korea" => "KP",
    "north macedonia" => "MK",
    "palestine" => "PS",
    "russia" => "RU",
    "south korea" => "KR",
    "st barthelemy" => "BL",
    "st helena ascension and tristan da cunha" => "SH",
    "st kitts and nevis" => "KN",
    "st lucia" => "LC",
    "st martin" => "MF",
    "st pierre and miquelon" => "PM",
    "st vincent and the grenadines" => "VC",
    "syria" => "SY",
    "taiwan" => "TW",
    "tanzania" => "TZ",
    "the bahamas" => "BS",
    "the gambia" => "GM",
    "turkiye" => "TR",
    "u k" => "GB",
    "u s" => "US",
    "u s a" => "US",
    "uk" => "GB",
    "united states of america" => "US",
    "usa" => "US",
    "vatican city" => "VA",
    "venezuela" => "VE",
    "vietnam" => "VN"
  }

  @supported_country_codes @country_name_to_code
                           |> Map.values()
                           |> Kernel.++(Map.values(@country_aliases))
                           |> MapSet.new()

  @spec format(String.t() | nil) :: String.t() | nil
  def format(country) when is_binary(country) do
    trimmed = String.trim(country)

    cond do
      trimmed == "" ->
        nil

      code = country_code(trimmed) ->
        "#{flag_emoji(code)} #{code}"

      true ->
        trimmed
    end
  end

  def format(_), do: nil

  @spec country_code(String.t() | nil) :: String.t() | nil
  def country_code(country) when is_binary(country) do
    normalized = normalize_country_key(country)

    cond do
      normalized == "" ->
        nil

      valid_alpha2_code?(normalized) ->
        String.upcase(normalized)

      true ->
        Map.get(@country_aliases, normalized) || Map.get(@country_name_to_code, normalized)
    end
  end

  def country_code(_), do: nil

  defp normalize_country_key(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.replace("&", " and ")
    |> String.replace(~r/[^a-z0-9]+/u, " ")
    |> String.trim()
  end

  defp valid_alpha2_code?(value) do
    String.match?(value, ~r/^[a-z]{2}$/) and
      MapSet.member?(@supported_country_codes, String.upcase(value))
  end

  defp flag_emoji(code) do
    code
    |> String.to_charlist()
    |> Enum.map_join(&<<127_397 + &1::utf8>>)
  end
end
