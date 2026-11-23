RSpec.describe ApplicationImport::Casters::DateCaster do
  it "names the type" do
    expect(build_caster(type: :date).type_name).to eq("a date")
  end

  it "keeps dates and takes the date of times" do
    caster = build_caster(type: :date)

    expect([ caster.call(Date.new(2026, 1, 2)), caster.call(Time.utc(2026, 1, 2, 23, 59)), caster.call(Time.zone.local(2026, 1, 2)) ])
      .to eq([ Date.new(2026, 1, 2) ] * 3)
  end

  context "with date_format" do
    subject(:caster) { build_caster(type: :date, date_format: "%d/%m/%Y") }

    it "parses matching values, trimming spaces" do
      expect([ caster.call("01/02/2026"), caster.call(" 1/2/2026 ") ]).to eq([ Date.new(2026, 2, 1) ] * 2)
    end

    it "rejects values that do not match the whole format" do
      [ "2026-02-01", "01/02/2026xyz", "01/02", "01/02/2026 10:00", "abc" ].each do |value|
        expect { caster.call(value) }.to raise_error(ArgumentError)
      end
    end

    it "rejects impossible dates" do
      expect { caster.call("31/02/2026") }.to raise_error(ArgumentError)
    end

    it "never warns" do
      caster.call("01/02/2026")

      expect(caster_log.string).to eq("")
    end
  end

  context "without date_format" do
    subject(:caster) { build_caster(type: :date, header: "Joined") }

    it "parses ISO 8601 silently" do
      expect([ caster.call("2026-02-01"), caster.call("20260201") ]).to eq([ Date.new(2026, 2, 1) ] * 2)
      expect(caster_log.string).to eq("")
    end

    it "falls back to Date.parse for full dates and warns once" do
      expect([ caster.call("1 Feb 2026"), caster.call("February 2, 2026"), caster.call("2026/02/03") ])
        .to eq([ Date.new(2026, 2, 1), Date.new(2026, 2, 2), Date.new(2026, 2, 3) ])
      expect(caster_log.string.lines).to contain_exactly(a_string_including(
        "WARN [ApplicationImport::Casters::DateCaster:users] column value (Joined) has no date_format", "Date.parse"
      ))
    end

    it "rejects partial dates instead of filling them from today" do
      [ "Feb 2", "2026", "10:30", "1" ].each do |value|
        expect { caster.call(value) }.to raise_error(ArgumentError)
      end
    end

    it "rejects text and impossible dates" do
      [ "abc", "2026-13-01", "2026-02-30" ].each do |value|
        expect { caster.call(value) }.to raise_error(ArgumentError)
      end
    end
  end
end
