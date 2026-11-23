RSpec.describe ApplicationImport::Readers::SkipLines do
  def filter(text, pattern: /\A#/, quote: '"', chunk: nil)
    skip = described_class.new(pattern, quote)
    pieces = chunk ? text.chars.each_slice(chunk).map(&:join) : [ text ]
    pieces.map { |piece| skip.filter(piece) }.join + skip.flush
  end

  it "blanks matching lines that start a record, keeping line numbers" do
    expect(filter("# export\nEmail,Name\n# note\na,b\n")).to eq("\nEmail,Name\n\na,b\n")
  end

  it "keeps a matching line inside a quoted value spanning lines" do
    expect(filter("Email,Note\na,\"first\n# not a comment\nlast\"\n# comment\n", pattern: /^#/))
      .to eq("Email,Note\na,\"first\n# not a comment\nlast\"\n\n")
  end

  it "drops comment lines with quote characters before they can break the parser" do
    expect(filter("# don't \"quote\nEmail\na\n")).to eq("\nEmail\na\n")
  end

  it "counts doubled quotes as even (RFC 4180 escaping)" do
    expect(filter("a,\"say \"\"hi\"\"\"\n# c\n")).to eq("a,\"say \"\"hi\"\"\"\n\n")
  end

  it "uses the configured quote character" do
    expect(filter("a,'x\n# in value\ny'\n# c\n", quote: "'")).to eq("a,'x\n# in value\ny'\n\n")
  end

  it "works across chunk boundaries" do
    text = "# export\nEmail,Name\na,\"x\n# in\"\n# c\nb,y"

    expect((1..5).map { |size| filter(text, chunk: size) }).to all(eq("\nEmail,Name\na,\"x\n# in\"\n\nb,y"))
  end

  it "filters a last line without line break on flush" do
    expect(filter("a\n# end")).to eq("a\n")
  end

  it "matches the line without its line break" do
    expect(filter("#\nx\n", pattern: /\A#\z/)).to eq("\nx\n")
  end
end
