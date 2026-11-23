RSpec.describe ApplicationImport::ColumnRules do
  def column(type = :string, header: "Name", **options)
    ApplicationImport::Column.new(key: :name, headers: [ header ], type:, options: { required: false, **options })
  end

  def errors(column, value)
    described_class.errors(column, value)
  end

  describe "required" do
    it "reports a nil value of a required column only" do
      expect([ errors(column(required: true), nil), errors(column, nil), errors(column(required: true), "x") ])
        .to eq([ [ [ :required, "Name is required" ] ], [], [] ])
    end

    it "skips every other rule for nil" do
      expect(errors(column(min_length: 2, inclusion: [ "a" ], format: /x/), nil)).to eq([])
    end
  end

  describe "lengths" do
    it "checks min_length and max_length on strings" do
      expect([ errors(column(min_length: 2), "a"), errors(column(max_length: 3), "abcd"), errors(column(min_length: 1, max_length: 3), "ab") ])
        .to eq([ [ [ :too_short, "Name is too short (minimum is 2 characters)" ] ],
          [ [ :too_long, "Name is too long (maximum is 3 characters)" ] ], [] ])
    end

    it "counts characters, not bytes" do
      expect(errors(column(max_length: 3), "Tên")).to eq([])
    end
  end

  describe "bounds" do
    it "checks min and max on numbers" do
      expect([ errors(column(:integer, min: 0), -1), errors(column(:integer, max: 150), 151), errors(column(:integer, min: 0, max: 5), 5) ])
        .to eq([ [ [ :too_small, "Name must be greater than or equal to 0" ] ],
          [ [ :too_big, "Name must be less than or equal to 150" ] ], [] ])
    end

    it "checks dates, times and decimals" do
      expect([ errors(column(:date, min: Date.new(2000, 1, 1)), Date.new(1999, 12, 31)).map(&:first),
        errors(column(:datetime, max: Time.utc(2026)), Time.utc(2026, 1, 2)).map(&:first),
        errors(column(:decimal, min: BigDecimal("0.5")), BigDecimal("0.4")).map(&:first) ])
        .to eq([ %i[ too_small ], %i[ too_big ], %i[ too_small ] ])
    end
  end

  describe "format" do
    it "matches the value as a string" do
      expect([ errors(column(format: /\A\d+\z/), "12"), errors(column(format: /\A\d+\z/), "1a") ])
        .to eq([ [], [ [ :invalid_format, "Name has an invalid format" ] ] ])
    end

    it "supports the email format" do
      email = column(format: URI::MailTo::EMAIL_REGEXP)

      expect([ errors(email, "a@x.io"), errors(email, "nope").map(&:first) ]).to eq([ [], %i[ invalid_format ] ])
    end
  end

  describe "inclusion" do
    it "compares values as strings" do
      expect([ errors(column(inclusion: %w[ admin member ]), "admin"), errors(column(:integer, inclusion: [ 1, 2 ]), 2),
        errors(column(inclusion: %w[ admin member ]), "guest") ])
        .to eq([ [], [], [ [ :not_included, "Name must be one of: admin, member" ] ] ])
    end
  end

  it "reports every failing rule" do
    expect(errors(column(max_length: 2, format: /\A\d+\z/, inclusion: [ "1" ]), "abc").map(&:first))
      .to eq(%i[ too_long invalid_format not_included ])
  end
end
