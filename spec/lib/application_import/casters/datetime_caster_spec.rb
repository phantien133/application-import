RSpec.describe ApplicationImport::Casters::DatetimeCaster do
  it "names the type" do
    expect(build_caster(type: :datetime).type_name).to eq("a date and time")
  end

  it "keeps times in Time.zone and converts dates to midnight" do
    caster = build_caster(type: :datetime)
    time = caster.call(Time.utc(2026, 1, 2, 3, 4))

    expect([ time, time.time_zone.name, caster.call(Date.new(2026, 1, 2)) ])
      .to eq([ Time.zone.local(2026, 1, 2, 3, 4), Time.zone.name, Time.zone.local(2026, 1, 2) ])
  end

  context "with date_format" do
    subject(:caster) { build_caster(type: :datetime, date_format: "%d/%m/%Y %H:%M") }

    it "parses matching values in Time.zone" do
      value = caster.call("01/02/2026 10:30")

      expect([ value, value.class ]).to eq([ Time.zone.local(2026, 2, 1, 10, 30), ActiveSupport::TimeWithZone ])
    end

    it "uses another Time.zone when set" do
      Time.use_zone("Asia/Ho_Chi_Minh") do
        expect(caster.call("01/02/2026 10:30").utc).to eq(Time.utc(2026, 2, 1, 3, 30))
      end
    end

    it "rejects values that do not match the whole format" do
      [ "2026-02-01 10:30", "01/02/2026", "01/02/2026 10:30 pm", "01/02/2026 25:00" ].each do |value|
        expect { caster.call(value) }.to raise_error(ArgumentError)
      end
    end
  end

  context "without date_format" do
    subject(:caster) { build_caster(type: :datetime, header: "Last login") }

    it "parses ISO 8601 silently, offsets included" do
      expect([ caster.call("2026-02-01T10:30:00Z"), caster.call("2026-02-01T17:30:00+07:00"), caster.call("2026-02-01") ])
        .to eq([ Time.utc(2026, 2, 1, 10, 30), Time.utc(2026, 2, 1, 10, 30), Time.zone.local(2026, 2, 1) ])
      expect(caster_log.string).to eq("")
    end

    it "falls back to Time.zone.parse for full dates and warns once" do
      expect([ caster.call("Feb 1 2026 10:30"), caster.call("1 Feb 2026") ])
        .to eq([ Time.zone.local(2026, 2, 1, 10, 30), Time.zone.local(2026, 2, 1) ])
      expect(caster_log.string.scan("Time.zone.parse").size).to eq(1)
    end

    it "rejects values without an explicit year, month and day" do
      [ "abc", "nope 10", "10:30", "Feb 2 10:30" ].each do |value|
        expect { caster.call(value) }.to raise_error(ArgumentError)
      end
    end
  end
end
