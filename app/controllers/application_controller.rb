class ApplicationController < ActionController::API
  include ErrorHandling
  include AutoRender
  include BooleanParams
end
