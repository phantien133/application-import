# Declares boolean query / body params as private reader methods:
#
#   class UserImportsController < ApplicationController
#     boolean_param :dry_run                 # dry_run -> false when absent or blank
#     boolean_param :notify, default: true
#   end
#
# Strict, unlike ActiveModel's boolean cast (where any unknown value is true):
# true / 1 / yes / on and false / 0 / no / off (case-insensitive) only; anything else
# raises ClientError invalid_parameter (400) with the param name in details.
module BooleanParams
  extend ActiveSupport::Concern

  TRUE_VALUES = %w[ true 1 yes on ].freeze
  FALSE_VALUES = %w[ false 0 no off ].freeze

  class_methods do
    def boolean_param(*names, default: false)
      names.each do |name|
        define_method(name) { boolean_param_value(name, default) }
        private name
      end
    end
  end

  private

  def boolean_param_value(name, default)
    value = params[name]
    return default if value.blank?

    text = value.to_s.strip.downcase
    return true if TRUE_VALUES.include?(text)
    return false if FALSE_VALUES.include?(text)

    raise ClientError.new("#{name} must be true or false", code: :invalid_parameter, details: { param: name.to_s })
  end
end
