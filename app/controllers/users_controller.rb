class UsersController < ApplicationController
  PERMITTED = %i[ email name age balance active phone role nickname label created_on last_login_at ].freeze
  DEFAULT_PER_PAGE = 25
  MAX_PER_PAGE = 100

  before_action :set_user, only: %i[ show update destroy ]

  def index
    page, per_page = pagination
    users = User.order(:id).offset((page - 1) * per_page).limit(per_page)

    with_meta(users, page:, per_page:, total: User.count)
  end

  def show
    @user
  end

  def create
    User.create!(user_params)
  end

  def update
    @user.update!(user_params)
    @user
  end

  def destroy
    @user.destroy!
    nil
  end

  private

  def set_user
    @user = User.find(params[:id])
  end

  # page >= 1, per_page within 1..MAX_PER_PAGE.
  def pagination
    page = [ params.fetch(:page, 1).to_i, 1 ].max
    [ page, params.fetch(:per_page, DEFAULT_PER_PAGE).to_i.clamp(1, MAX_PER_PAGE) ]
  end

  def user_params
    params.expect(user: PERMITTED)
  end
end
