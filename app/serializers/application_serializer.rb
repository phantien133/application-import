# Base of the API serializers (Alba). Shared value formats, so every response
# writes the same kind of value the same way:
#   decimal  -> String with the column's scale ("1234.50"): no float rounding
#   date     -> "YYYY-MM-DD"
#   time     -> ISO 8601 in UTC with milliseconds ("2026-11-25T02:29:35.123Z")
# nil stays nil.
#
#   UserSerializer.new(user).serializable_hash   # Hash
#   UserSerializer.new(users).serializable_hash  # Array of Hashes
class ApplicationSerializer
  include Alba::Resource

  private

  def decimal(value, scale: 2)
    value && format("%.#{scale}f", value)
  end

  def date(value)
    value&.iso8601
  end

  def time(value)
    value&.utc&.iso8601(3)
  end
end
