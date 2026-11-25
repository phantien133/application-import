# The ApplicationService contract: `.call(*args, **kwargs)` builds the service with the
# same arguments and returns its #call. Pass the arguments the service takes:
#
#   it_behaves_like "an application service", "file.csv", dry_run: true
#   it_behaves_like "an application service"                 # no arguments
RSpec.shared_examples "an application service" do |*args, **kwargs|
  it "is an ApplicationService" do
    expect(described_class).to be < ApplicationService
  end

  describe ".call" do
    it "builds the service with the given arguments and returns its #call" do
      service = instance_double(described_class, call: :result)
      expected = (args.empty? && kwargs.empty?) ? [ no_args ] : [ *args, kwargs.presence ].compact
      allow(described_class).to receive(:new).with(*expected).and_return(service)

      expect(described_class.call(*args, **kwargs)).to eq(:result)
    end
  end
end
