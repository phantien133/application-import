# Renders what an action returns, so actions return data instead of calling
# render_success; errors are raised (ApplicationError subclasses or Rails errors) and
# rendered by ErrorHandling.
#
#   def show = @user                                  # 200 { data: <UserSerializer> }
#   def create = User.create!(user_params)            # 201 on create
#   def index = with_meta(users, page:, total:)       # 200 { data: [...], meta: {...} }
#   def destroy = @user.destroy! && nil               # nil -> 204, no body
#
# Serializer: the controller's `serialize_with SomeSerializer`, else <Model>Serializer
# inferred from the value (a record, a relation, an array of records), else the value
# is rendered as is (Hash, Array of plain values...). An action that renders itself
# (render / head) is left alone.
module AutoRender
  extend ActiveSupport::Concern
  include ApiResponse

  Payload = Data.define(:data, :meta, :status)

  included do
    class_attribute :auto_serializer, instance_accessor: false, default: nil
  end

  class_methods do
    def serialize_with(serializer)
      self.auto_serializer = serializer
    end
  end

  private

  # Replaces ActionController's implicit render (head :no_content when nothing was
  # rendered) with rendering the action's return value.
  def send_action(method_name, *args)
    value = send(method_name, *args)
    render_value(value) unless performed?
    value
  end

  def with_meta(data, status: nil, **meta)
    Payload.new(data:, meta: meta.presence, status:)
  end

  def render_value(value)
    return head(:no_content) if value.nil?

    payload = value.is_a?(Payload) ? value : Payload.new(data: value, meta: nil, status: nil)
    render_success(serialize(payload.data), status: payload.status || default_status, meta: payload.meta)
  end

  def default_status
    (action_name == "create") ? :created : :ok
  end

  def serialize(data)
    serializer = self.class.auto_serializer || serializer_for(data)
    serializer ? serializer.new(data).serializable_hash : data
  end

  def serializer_for(data)
    name = model_of(data)&.name
    serializer = name && "#{name}Serializer".safe_constantize
    serializer if serializer.is_a?(Class) && serializer < ApplicationSerializer
  end

  # A relation's model, the class of an array's first item, else the value's class.
  def model_of(data)
    return data.model if data.respond_to?(:model)

    data.is_a?(Array) ? data.first&.class : data.class
  end
end
