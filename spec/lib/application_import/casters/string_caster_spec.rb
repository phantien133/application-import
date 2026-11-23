RSpec.describe ApplicationImport::Casters::StringCaster do
  subject(:caster) { build_caster }

  it "keeps strings as read, spaces included" do
    expect([ caster.call("Ann"), caster.call(" Ann "), caster.call("Tên") ]).to eq([ "Ann", " Ann ", "Tên" ])
  end

  it "turns other values into strings" do
    expect([ caster.call(12), caster.call(1.5), caster.call(true), caster.call(:sym) ]).to eq(%w[ 12 1.5 true sym ])
  end

  it "names the type" do
    expect(caster.type_name).to eq("text")
  end
end
