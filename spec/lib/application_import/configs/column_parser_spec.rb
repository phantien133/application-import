RSpec.describe ApplicationImport::Configs::ColumnParser do
  let(:errors) { [] }

  def parse(config)
    described_class.new(config, errors).parse
  end

  def column(options, key: "email")
    parse({ key => options }).first
  end

  it "builds columns with defaults" do
    result = column(nil)

    expect([ result.key, result.headers, result.type, result.options ]).to eq([ :email, [ "email" ], :string, { required: false } ])
    expect(errors).to be_empty
  end

  it "uses header and aliases as accepted headers" do
    expect(column({ "header" => " Email ", "aliases" => [ "E-mail" ] }).headers).to eq([ "Email", "E-mail" ])
  end

  describe "header_pattern" do
    it "compiles one regexp or a list, case-insensitive" do
      expect([ column({ "header_pattern" => '\Ae-?mail' }).header_patterns, column({ "header_pattern" => [ "a", "b" ] }).header_patterns ])
        .to eq([ [ /\Ae-?mail/i ], [ /a/i, /b/i ] ])
      expect(errors).to be_empty
    end

    it "is absent by default" do
      expect([ column(nil).options.key?(:header_patterns), column(nil).header_patterns ]).to eq([ false, [] ])
    end

    it "reports invalid regexps and non-list values" do
      column({ "header_pattern" => [ "(" ] })
      column({ "header_pattern" => 1 })

      expect(errors).to match([ a_string_starting_with("columns.email.header_pattern is not a valid regexp"),
        "columns.email.header_pattern must be a non-empty list of names" ])
    end
  end

  describe "caster" do
    it "keeps the class name, absent by default" do
      expect([ column({ "caster" => "Imports::PhoneCaster" }).options[:caster], column(nil).options.key?(:caster) ])
        .to eq([ "Imports::PhoneCaster", false ])
    end

    it "rejects non class names" do
      column({ "caster" => 1 })

      expect(errors).to eq([ "columns.email.caster must be a class name" ])
    end
  end

  it "parses datetime bounds in Time.zone" do
    Time.use_zone("Asia/Tokyo") do
      expect(column({ "type" => "datetime", "min" => "2026-01-01T00:00:00" }).options[:min]).to eq(Time.zone.local(2026))
    end
  end

  describe "number separators" do
    it "keeps them on decimal and (thousands only) integer columns" do
      expect([ column({ "type" => "decimal", "decimal_separator" => ",", "thousands_separator" => "." }).options.slice(:decimal_separator, :thousands_separator),
        column({ "type" => "integer", "thousands_separator" => " " }).options[:thousands_separator] ])
        .to eq([ { decimal_separator: ",", thousands_separator: "." }, " " ])
      expect(errors).to be_empty
    end

    it "rejects them on other types and decimal_separator on integers" do
      column({ "type" => "integer", "decimal_separator" => "," })
      column({ "thousands_separator" => "." })

      expect(errors).to eq([ "columns.email.decimal_separator is not allowed on integer columns",
        "columns.email.thousands_separator is not allowed on string columns" ])
    end

    it "requires one non-digit character and different separators" do
      column({ "type" => "decimal", "decimal_separator" => "..", "thousands_separator" => "1" })
      column({ "type" => "decimal", "decimal_separator" => ",", "thousands_separator" => "," })

      expect(errors).to eq([
        "columns.email.decimal_separator must be one character other than a digit or a sign",
        "columns.email.thousands_separator must be one character other than a digit or a sign",
        "columns.email decimal_separator and thousands_separator must differ"
      ])
    end
  end

  it "requires at least one column" do
    expect([ parse(nil), parse({}) ]).to eq([ [], [] ])
    expect(errors).to eq([ "columns must define at least one column" ] * 2)
  end

  it "rejects non snake_case keys and unknown options" do
    column({ "max_lenght" => 3 }, key: "Email")

    expect(errors).to contain_exactly("columns.Email must be snake_case", "columns.Email has unknown keys: max_lenght")
  end

  it "rejects unknown types without type-dependent errors" do
    result = column({ "type" => "integr", "min" => 1 })

    expect(result.type).to eq(:string)
    expect(errors).to eq([ "columns.email.type must be one of string, integer, decimal, boolean, date, datetime" ])
  end

  it "rejects duplicated headers across columns" do
    parse({ "email" => { "header" => "Mail" }, "contact" => { "aliases" => [ "mail" ] } })

    expect(errors).to eq([ "columns header \"mail\" is used more than once" ])
  end

  describe "options" do
    it "keeps required and string lengths" do
      options = column({ "required" => true, "min_length" => 0, "max_length" => 255 }).options

      expect(options).to eq(required: true, min_length: 0, max_length: 255)
    end

    it "rejects invalid lengths" do
      column({ "min_length" => 5, "max_length" => 2, "required" => "yes" })

      expect(errors).to contain_exactly(
        "columns.email.min_length must not be greater than the maximum",
        "columns.email.required must be true or false"
      )
    end

    it "only allows lengths on string columns" do
      column({ "type" => "integer", "max_length" => 3 })

      expect(errors).to eq([ "columns.email.max_length is only allowed on string columns" ])
    end

    it "casts min/max with the column type" do
      expect([
        column({ "type" => "integer", "min" => 0, "max" => 10 }).options.values_at(:min, :max),
        column({ "type" => "decimal", "min" => 0.5 }).options[:min],
        column({ "type" => "date", "min" => "2020-01-01" }).options[:min],
        column({ "type" => "datetime", "max" => "2020-01-01T10:00:00Z" }).options[:max]
      ]).to eq([ [ 0, 10 ], BigDecimal("0.5"), Date.new(2020, 1, 1), Time.utc(2020, 1, 1, 10) ])
    end

    it "rejects invalid min/max" do
      column({ "type" => "integer", "min" => "1" })
      column({ "type" => "date", "min" => "01/01/2020" })
      column({ "type" => "integer", "min" => 5, "max" => 1 })
      column({ "min" => 1 })

      expect(errors).to eq([
        "columns.email.min must be an integer",
        "columns.email.min must be an ISO 8601 date",
        "columns.email.min must not be greater than the maximum",
        "columns.email.min is only allowed on integer, decimal, date and datetime columns"
      ])
    end

    it "compiles format" do
      expect([ column({ "format" => "email" }).options[:format], column({ "format" => '\A\d+\z' }).options[:format] ])
        .to eq([ URI::MailTo::EMAIL_REGEXP, /\A\d+\z/ ])
    end

    it "rejects an invalid format regexp" do
      column({ "format" => "[" })

      expect(errors.first).to start_with("columns.email.format is not a valid regexp")
    end

    it "keeps inclusion lists and date_format" do
      expect(column({ "inclusion" => [ "a", "b" ] }).options[:inclusion]).to eq([ "a", "b" ])
      expect(column({ "type" => "date", "date_format" => "%d/%m/%Y" }).options[:date_format]).to eq("%d/%m/%Y")
    end

    it "rejects invalid inclusion and date_format" do
      column({ "inclusion" => [] })
      column({ "date_format" => "%d/%m/%Y" })
      column({ "type" => "date", "date_format" => "" })

      expect(errors).to eq([
        "columns.email.inclusion must be a non-empty list",
        "columns.email.date_format is only allowed on date and datetime columns",
        "columns.email.date_format must be a strptime format string"
      ])
    end
  end
end
