# JSON serializers (app/serializers): ActiveSupport JSON backend, so values Alba does
# not format itself are encoded the same way as Rails' own `render json:`.
Alba.backend = :active_support
Alba.inflector = :active_support
