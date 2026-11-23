RSpec.describe ApplicationImport::Caster do
  subject(:caster) { described_class.new(definition, logger:) }

  let(:log) { StringIO.new }
  let(:logger) { ActiveSupport::Logger.new(log).tap { |l| l.formatter = ->(severity, _, _, msg) { "#{severity} #{msg}\n" } } }
  let(:definition) { ApplicationImport::Definition.new(:users, { "columns" => { "email" => nil } }) }

  def column(type, header: "Value", **options)
    ApplicationImport::Column.new(key: :value, headers: [ header ], type:, options:)
  end

  def cast(type, value, **options)
    caster.call(column(type, **options), value)
  end

  def invalid(type, value, **options)
    cast(type, value, **options)
    nil
  rescue described_class::Invalid => e
    e.message
  end

  it "returns nil for blank values of every type" do
    types = %i[ string integer decimal boolean date datetime ]

    expect(types.product([ nil, "", "  \t" ]).map { |type, value| cast(type, value) }).to all(be_nil)
  end

  describe "string" do
    it "keeps the value as read" do
      expect([ cast(:string, " Ann "), cast(:string, 12) ]).to eq([ " Ann ", "12" ])
    end
  end

  describe "integer" do
    it "parses base-10 integers, trimming spaces" do
      expect([ cast(:integer, "42"), cast(:integer, " -7 "), cast(:integer, "+3"), cast(:integer, "007"), cast(:integer, 5) ])
        .to eq([ 42, -7, 3, 7, 5 ])
    end

    it "rejects decimals, exponents, hex and text" do
      expect([ "1.5", "1e3", "0x1A", "abc", "1 2" ].map { |value| invalid(:integer, value) }).to all(eq("Value must be an integer"))
    end
  end

  describe "decimal" do
    it "parses numbers as BigDecimal" do
      expect([ cast(:decimal, "1.50"), cast(:decimal, " -2 "), cast(:decimal, "1e2"), cast(:decimal, 0.1) ])
        .to eq([ BigDecimal("1.5"), BigDecimal("-2"), BigDecimal(100), BigDecimal("0.1") ])
      expect(cast(:decimal, "3")).to be_a(BigDecimal)
    end

    it "rejects text" do
      expect([ "abc", "1.2.3", "1,5" ].map { |value| invalid(:decimal, value) }).to all(eq("Value must be a number"))
    end
  end

  describe "boolean" do
    it "maps true and false words case-insensitively" do
      expect(%w[ true T Yes y 1 ].map { |value| cast(:boolean, value) }).to all(be(true))
      expect(%w[ false F NO n 0 ].map { |value| cast(:boolean, value) }).to all(be(false))
      expect([ cast(:boolean, true), cast(:boolean, false) ]).to eq([ true, false ])
    end

    it "rejects other values" do
      expect([ "maybe", "2", "on" ].map { |value| invalid(:boolean, value) }).to all(eq("Value must be true or false"))
    end
  end

  describe "date" do
    context "with date_format" do
      it "parses values matching the format strictly" do
        expect(cast(:date, "01/02/2026", date_format: "%d/%m/%Y")).to eq(Date.new(2026, 2, 1))
      end

      it "rejects invalid dates, other formats and trailing characters" do
        expect([ "31/02/2026", "2026-02-01", "01/02/2026xyz", "01/02" ].map { |value| invalid(:date, value, date_format: "%d/%m/%Y") })
          .to all(eq("Value must be a date"))
      end

      it "does not warn" do
        cast(:date, "01/02/2026", date_format: "%d/%m/%Y")

        expect(log.string).to eq("")
      end
    end

    context "without date_format" do
      it "parses ISO 8601 without warning" do
        expect(cast(:date, "2026-02-01")).to eq(Date.new(2026, 2, 1))
        expect(log.string).to eq("")
      end

      it "parses other values leniently and warns once per column" do
        values = [ cast(:date, "1 Feb 2026"), cast(:date, "Feb 2 2026") ]

        expect(values).to eq([ Date.new(2026, 2, 1), Date.new(2026, 2, 2) ])
        expect(log.string.lines.size).to eq(1)
        expect(log.string).to include("WARN [ApplicationImport::Casters::DateCaster:users] column value (Value) has no date_format",
          "Date.parse", "set date_format")
      end

      it "warns again for another column" do
        caster.call(column(:date), "1 Feb 2026")
        caster.call(ApplicationImport::Column.new(key: :other, headers: [ "Other" ], type: :date, options: {}), "1 Feb 2026")

        expect(log.string.lines.size).to eq(2)
      end

      it "rejects what neither parser understands, and partial dates" do
        expect([ "abc", "2026-13-01", "1", "Feb 2", "10:30" ].map { |value| invalid(:date, value) }).to all(eq("Value must be a date"))
      end
    end

    it "keeps dates and converts times" do
      expect([ cast(:date, Date.new(2026, 1, 2)), cast(:date, Time.utc(2026, 1, 2, 23)) ]).to eq([ Date.new(2026, 1, 2) ] * 2)
    end
  end

  describe "datetime" do
    context "with date_format" do
      it "parses in Time.zone" do
        value = cast(:datetime, "01/02/2026 10:30", date_format: "%d/%m/%Y %H:%M")

        expect([ value, value.time_zone.name ]).to eq([ Time.zone.local(2026, 2, 1, 10, 30), Time.zone.name ])
      end

      it "rejects other formats and trailing characters" do
        expect([ "2026-02-01 10:30", "01/02/2026 10:30 pm" ].map { |value| invalid(:datetime, value, date_format: "%d/%m/%Y %H:%M") })
          .to all(eq("Value must be a date and time"))
      end
    end

    context "without date_format" do
      it "parses ISO 8601 without warning" do
        expect(cast(:datetime, "2026-02-01T10:30:00Z")).to eq(Time.utc(2026, 2, 1, 10, 30))
        expect(log.string).to eq("")
      end

      it "parses other values leniently and warns once" do
        expect([ cast(:datetime, "Feb 1 2026 10:30"), cast(:datetime, "1 Feb 2026") ])
          .to eq([ Time.zone.local(2026, 2, 1, 10, 30), Time.zone.local(2026, 2, 1) ])
        expect(log.string).to include("Time.zone.parse")
        expect(log.string.lines.size).to eq(1)
      end

      it "rejects unparseable values" do
        expect([ "abc", "nope 10", "10:30", "Feb 2 10:30" ].map { |value| invalid(:datetime, value) })
          .to all(eq("Value must be a date and time"))
      end
    end

    it "keeps times in the zone and converts dates" do
      expect([ cast(:datetime, Time.utc(2026, 1, 2, 3)), cast(:datetime, Date.new(2026, 1, 2)) ])
        .to eq([ Time.zone.local(2026, 1, 2, 3), Time.zone.local(2026, 1, 2) ])
    end
  end

  describe "caster selection" do
    it "has a built-in caster for every column type" do
      expect(described_class::BUILT_IN.keys.map(&:to_s)).to match_array(ApplicationImport::Constants::COLUMN_TYPES)
      expect(described_class::BUILT_IN.values.map(&:constantize)).to all(be < ApplicationImport::Casters::Base)
    end

    it "picks the built-in caster of the type, without dynamic dispatch on the type name" do
      expect([ described_class.caster_class(column(:integer)), described_class.caster_class(column(:datetime)) ])
        .to eq([ ApplicationImport::Casters::IntegerCaster, ApplicationImport::Casters::DatetimeCaster ])
    end

    it "rejects an unknown type instead of calling an arbitrary method" do
      [ :unknown, :class, :instance_eval, "integer" ].each do |type|
        expect { cast(type, "1") }.to raise_error(ApplicationImport::Errors::ConfigError, "column value: unknown type #{type.inspect}")
      end
    end

    it "builds one caster per column per run" do
      first = caster.caster_for(column(:date))

      expect(caster.caster_for(column(:date))).to be(first)
      expect(described_class.new(definition).caster_for(column(:date))).not_to be(first)
    end
  end

  describe "custom caster (column option caster)" do
    before do
      stub_const("PhoneCaster", Class.new(ApplicationImport::Casters::Base) do
        def call(value)
          digits = value.to_s.gsub(/\D/, "")
          (digits.length == 10) ? "+84#{digits[1..]}" : invalid!
        end

        def type_name
          "a phone number"
        end
      end)
    end

    it "is used instead of the built-in caster of the type" do
      expect(cast(:string, "090 123 4567", caster: PhoneCaster)).to eq("+84901234567")
    end

    it "reports invalid! with its type_name" do
      expect(invalid(:string, "123", caster: PhoneCaster, header: "Phone")).to eq("Phone must be a phone number")
    end

    it "turns ArgumentError / TypeError into invalid values" do
      stub_const("StrictCaster", Class.new(ApplicationImport::Casters::Base) { define_method(:call) { |value| Integer(value) } })

      expect(invalid(:integer, "x", caster: StrictCaster)).to eq("Value must be valid")
    end

    it "lets a custom message through" do
      stub_const("MessageCaster", Class.new(ApplicationImport::Casters::Base) { define_method(:call) { |_value| invalid!("nope") } })

      expect(invalid(:string, "x", caster: MessageCaster)).to eq("nope")
    end

    it "never sees blank values" do
      stub_const("LoudCaster", Class.new(ApplicationImport::Casters::Base) { define_method(:call) { |_value| raise "called" } })

      expect([ cast(:string, nil, caster: LoudCaster), cast(:string, " ", caster: LoudCaster) ]).to eq([ nil, nil ])
    end

    it "can subclass a built-in caster" do
      stub_const("VietBooleanCaster", Class.new(ApplicationImport::Casters::BooleanCaster) do
        const_set(:TRUE_VALUES, %w[ có c ].freeze)
        const_set(:FALSE_VALUES, %w[ không k ].freeze)
      end)

      expect([ cast(:boolean, "Có", caster: VietBooleanCaster), cast(:boolean, "không", caster: VietBooleanCaster),
        invalid(:boolean, "yes", caster: VietBooleanCaster) ]).to eq([ true, false, "Value must be true or false" ])
    end
  end

  it "names the column header in messages" do
    expect(invalid(:integer, "x", header: "Age")).to eq("Age must be an integer")
  end

  it "lets a caster that cannot be built raise as is (a bug, not an invalid value)" do
    stub_const("BrokenCaster", Class.new(ApplicationImport::Casters::Base) do
      def initialize(*)
        raise ArgumentError, "bad constructor"
      end
    end)

    expect { cast(:string, "x", caster: BrokenCaster) }.to raise_error(ArgumentError, "bad constructor")
  end
end
