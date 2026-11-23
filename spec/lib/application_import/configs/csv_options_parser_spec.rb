RSpec.describe ApplicationImport::Configs::CsvOptionsParser do
  def parse(config)
    errors = []
    [ described_class.new(config, errors).parse, errors ]
  end

  it "returns no options for a missing section" do
    expect(parse(nil)).to eq([ {}, [] ])
  end

  it "parses every validated option" do
    options, errors = parse(
      "col_sep" => ";", "quote_char" => "'", "row_sep" => "\r\n",
      "liberal_parsing" => true, "strip" => "\t", "skip_lines" => '\A#', "max_field_size" => 100
    )

    expect(errors).to eq([])
    expect(options).to eq(col_sep: ";", quote_char: "'", row_sep: "\r\n", liberal_parsing: true, strip: "\t",
      skip_lines: /\A#/, max_field_size: 100)
  end

  it "keeps false values and drops nil ones" do
    expect(parse("liberal_parsing" => false, "strip" => false, "col_sep" => nil)).to eq([ { liberal_parsing: false, strip: false }, [] ])
  end

  it "reports invalid values" do
    _, errors = parse(
      "col_sep" => "", "quote_char" => 1, "liberal_parsing" => "yes", "strip" => "",
      "skip_lines" => "(", "max_field_size" => 0, "passthrough" => [ 1 ]
    )

    expect(errors).to contain_exactly(
      "file.csv.col_sep must be a non-empty string",
      "file.csv.quote_char must be one character",
      "file.csv.liberal_parsing must be true or false",
      "file.csv.strip must be true, false or a single character",
      a_string_starting_with("file.csv.skip_lines is not a valid regexp"),
      "file.csv.max_field_size must be an integer >= 1",
      "file.csv.passthrough must be a mapping"
    )
  end

  it "rejects strip strings of several characters (unsupported by the csv gem)" do
    expect(parse("strip" => " *").last).to eq([ "file.csv.strip must be true, false or a single character" ])
  end

  it "requires a one-character quote_char" do
    expect([ parse("quote_char" => "''").last, parse("quote_char" => "'").last ]).to eq([ [ "file.csv.quote_char must be one character" ], [] ])
  end

  it "requires col_sep, quote_char and row_sep to differ, defaults included" do
    expect([ parse("col_sep" => '"').last, parse("quote_char" => ",").last, parse("col_sep" => ";", "row_sep" => ";").last,
      parse("col_sep" => ";", "quote_char" => "'", "row_sep" => "|").last ])
      .to eq([ [ "file.csv col_sep and quote_char must differ (#{'"'.inspect})" ], [ 'file.csv col_sep and quote_char must differ (",")' ],
        [ 'file.csv col_sep and row_sep must differ (";")' ], [] ])
  end

  it "rejects a non-string skip_lines" do
    expect(parse("skip_lines" => 1).last).to eq([ "file.csv.skip_lines must be a regexp string" ])
  end

  it "rejects unknown keys, including CSV options it does not support" do
    options, errors = parse("encoding" => "UTF-8", "headers" => true, "col_sep" => ";")

    expect([ options, errors ]).to eq([ { col_sep: ";" }, [ "file.csv has unknown keys: encoding, headers" ] ])
  end

  it "rejects a non-mapping section" do
    expect(parse("x").last).to eq([ "file.csv must be a mapping" ])
  end

  it "rejects passthrough options the reader manages" do
    options, errors = parse("passthrough" => { "headers" => true, "skip_blanks" => true, "skip_lines" => "#", "nil_value" => "" })

    expect([ options, errors ]).to eq([ { passthrough: { nil_value: "" } },
      [ "file.csv.passthrough has options the reader manages: headers, skip_blanks, skip_lines" ] ])
  end

  describe "passthrough" do
    it "symbolizes keys and keeps values unvalidated" do
      options, errors = parse("passthrough" => { "nil_value" => "", "future_option" => { "a" => 1 }, "col_sep" => 5 })

      expect([ options, errors ]).to eq([ { passthrough: { nil_value: "", future_option: { a: 1 }, col_sep: 5 } }, [] ])
    end
  end
end
