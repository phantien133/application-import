class ApplicationService
  include Logs::ServiceLog

  class << self
    def call(*args, **kwargs)
      new(*args, **kwargs).call
    end
  end

  def call
    raise NotImplementedError, "#{self.class.name} must implement #call"
  end

  def service_id
    @service_id ||= "#{self.class.name}##{SecureRandom.uuid_v7}"
  end
end
