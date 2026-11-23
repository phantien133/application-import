RSpec.describe ApplicationImport::Writers do
  let(:result) { ApplicationImport::Result.new }

  def definition(output)
    stub_const("WritersSpecUser", Class.new(ApplicationRecord))
    ApplicationImport::Definition.new(:users, { "columns" => { "email" => nil }, "output" => output })
  end

  def writer(output)
    described_class.for(definition(output), result:, on_failure: ->(_row) { :skip })
  end

  it "picks the writer for output.mode, bulk by default with a model and raw without" do
    expect([ writer({}), writer("model" => "WritersSpecUser"), writer("model" => "WritersSpecUser", "mode" => "save"),
      writer("model" => "WritersSpecUser", "mode" => "raw") ].map(&:class))
      .to eq([ ApplicationImport::Writers::Raw, ApplicationImport::Writers::Bulk, ApplicationImport::Writers::Save,
        ApplicationImport::Writers::Raw ])
  end

  it "has a writer for every output mode" do
    expect(described_class::WRITERS.keys.map(&:to_s)).to match_array(ApplicationImport::Constants::OUTPUT_MODES)
  end

  it "hands the result and logger to the writer" do
    logger = ActiveSupport::Logger.new(nil)
    writer = described_class.for(definition({}), result:, on_failure: ->(_row) { }, logger:)

    expect([ writer.result, writer.logger ]).to eq([ result, logger ])
  end
end
