# frozen_string_literal: true

require_relative "test_helper"

class RailsChecksTest < Minitest::Test
  def test_schema_parser_handles_inline_indexes_scoped_uniqueness_and_string_ids
    Dir.mktmpdir do |dir|
      write_minimal_rails_app(dir)
      FileUtils.mkdir_p(File.join(dir, "db"))
      File.write(File.join(dir, "db/schema.rb"), <<~RUBY)
        ActiveRecord::Schema[8.0].define(version: 2026_06_01_000001) do
          create_table "memberships", force: :cascade do |t|
            t.bigint "user_id"
            t.string "external_id"
            t.string "role"
            t.index ["user_id", "role"], name: "index_memberships_on_user_id_and_role", unique: true
            t.index ["user_id"], name: "index_memberships_on_user_id"
          end

          create_table "users", force: :cascade do |t|
            t.string "email"
          end

          add_index "users", "email", unique: true
        end
      RUBY
      FileUtils.mkdir_p(File.join(dir, "app/models"))
      File.write(File.join(dir, "app/models/membership.rb"), <<~RUBY)
        class Membership < ApplicationRecord
          validates :role,
            presence: true,
            uniqueness: { scope: :user_id }
        end
      RUBY
      File.write(File.join(dir, "app/models/user.rb"), <<~RUBY)
        class User < ApplicationRecord
          validates :email, uniqueness: true
        end
      RUBY

      result = scan_with_rails_checks(dir)

      database_findings = result.findings.select { |finding| finding.category == "database-integrity" }
      assert_empty database_findings.map(&:message)
    end
  end

  def test_percent_i_scoped_uniqueness_uses_composite_unique_index
    Dir.mktmpdir do |dir|
      write_minimal_rails_app(dir)
      FileUtils.mkdir_p(File.join(dir, "db"))
      File.write(File.join(dir, "db/schema.rb"), <<~RUBY)
        ActiveRecord::Schema[8.0].define(version: 2026_06_01_000001) do
          create_table "slugs", force: :cascade do |t|
            t.string "value"
            t.bigint "account_id"
            t.string "locale"
            t.index ["value", "account_id", "locale"], name: "index_slugs_uniqueness", unique: true
            t.index ["account_id"], name: "index_slugs_on_account_id"
          end
        end
      RUBY
      FileUtils.mkdir_p(File.join(dir, "app/models"))
      File.write(File.join(dir, "app/models/slug.rb"), <<~RUBY)
        class Slug < ApplicationRecord
          validates :value, uniqueness: { scope: %i[account_id locale] }
        end
      RUBY

      result = scan_with_rails_checks(dir)

      database_findings = result.findings.select { |finding| finding.category == "database-integrity" }
      assert_empty database_findings.map(&:message)
    end
  end

  def test_partial_unique_index_does_not_satisfy_unconditional_uniqueness_validation
    Dir.mktmpdir do |dir|
      write_minimal_rails_app(dir)
      FileUtils.mkdir_p(File.join(dir, "db"))
      File.write(File.join(dir, "db/schema.rb"), <<~RUBY)
        ActiveRecord::Schema[8.0].define(version: 2026_06_01_000001) do
          create_table "users", force: :cascade do |t|
            t.string "email"
            t.datetime "deleted_at"
            t.index ["email"], name: "index_users_on_email_active", unique: true, where: "deleted_at IS NULL"
          end
        end
      RUBY
      FileUtils.mkdir_p(File.join(dir, "app/models"))
      File.write(File.join(dir, "app/models/user.rb"), <<~RUBY)
        class User < ApplicationRecord
          validates :email, uniqueness: true
        end
      RUBY

      result = scan_with_rails_checks(dir)

      assert(result.findings.any? { |finding| finding.message.include?("users.email") })
    end
  end

  def test_string_foreign_key_is_reported_when_referenced_table_exists
    Dir.mktmpdir do |dir|
      write_minimal_rails_app(dir)
      FileUtils.mkdir_p(File.join(dir, "db"))
      File.write(File.join(dir, "db/schema.rb"), <<~RUBY)
        ActiveRecord::Schema[8.0].define(version: 2026_06_01_000001) do
          create_table "accounts", id: :string, force: :cascade do |t|
            t.string "name"
          end

          create_table "memberships", force: :cascade do |t|
            t.string "account_id"
          end
        end
      RUBY

      result = scan_with_rails_checks(dir)

      assert(result.findings.any? { |finding| finding.message == "memberships.account_id has no index" })
    end
  end

  def test_missing_bigint_foreign_key_index_is_still_reported
    Dir.mktmpdir do |dir|
      write_minimal_rails_app(dir)
      FileUtils.mkdir_p(File.join(dir, "db"))
      File.write(File.join(dir, "db/schema.rb"), <<~RUBY)
        ActiveRecord::Schema[8.0].define(version: 2026_06_01_000001) do
          create_table "posts", force: :cascade do |t|
            t.bigint "user_id"
          end
        end
      RUBY

      result = scan_with_rails_checks(dir)

      assert(result.findings.any? { |finding| finding.message == "posts.user_id has no index" })
    end
  end

  def test_resource_only_routes_and_private_controller_helpers_do_not_create_route_noise
    Dir.mktmpdir do |dir|
      write_minimal_rails_app(dir)
      File.write(File.join(dir, "config/routes.rb"), <<~RUBY)
        Rails.application.routes.draw do
          resources :posts, only: [:index]
          resources :comments,
            only: %i(index show)
          resources :photos,
            except: %w(destroy)
        end
      RUBY
      FileUtils.mkdir_p(File.join(dir, "app/controllers"))
      FileUtils.mkdir_p(File.join(dir, "app/views/posts"))
      File.write(File.join(dir, "app/controllers/posts_controller.rb"), <<~RUBY)
        class PostsController < ApplicationController
          def index
          end

          private

          def normalize_filter
          end
        end
      RUBY
      File.write(File.join(dir, "app/views/posts/index.html.erb"), "<h1>Posts</h1>")
      write_controller_with_actions(dir, "comments_controller.rb", "CommentsController", %w[index show])
      write_controller_with_actions(dir, "photos_controller.rb", "PhotosController", %w[index show new create edit update])

      result = scan_with_rails_checks(dir)

      route_messages = route_messages(result)
      assert_empty route_messages, route_messages.join("\n")
    end
  end

  def test_method_specific_private_declarations_do_not_hide_later_public_actions
    Dir.mktmpdir do |dir|
      write_minimal_rails_app(dir)
      File.write(File.join(dir, "config/routes.rb"), <<~RUBY)
        Rails.application.routes.draw do
          resources :posts, only: %i[index show]
        end
      RUBY
      FileUtils.mkdir_p(File.join(dir, "app/controllers"))
      FileUtils.mkdir_p(File.join(dir, "app/views/posts"))
      File.write(File.join(dir, "app/controllers/posts_controller.rb"), <<~RUBY)
        class PostsController < ApplicationController
          def index
          end

          def normalize_filter
          end
          private :normalize_filter

          def show
          end
        end
      RUBY
      File.write(File.join(dir, "app/views/posts/index.html.erb"), "<h1>Posts</h1>")
      File.write(File.join(dir, "app/views/posts/show.html.erb"), "<h1>Post</h1>")

      result = scan_with_rails_checks(dir)

      route_messages = route_messages(result)
      assert_empty route_messages, route_messages.join("\n")
    end
  end

  def test_control_flow_blocks_inside_namespaces_do_not_drop_module_context
    Dir.mktmpdir do |dir|
      write_minimal_rails_app(dir)
      File.write(File.join(dir, "config/routes.rb"), <<~RUBY)
        Rails.application.routes.draw do
          namespace :admin do
            if ENV["ADMIN_ROUTES"]
            end

            resources :posts, only: :index
          end
        end
      RUBY
      write_controller(dir, "admin/posts_controller.rb", "Admin::PostsController", "index")
      FileUtils.mkdir_p(File.join(dir, "app/views/admin/posts"))
      File.write(File.join(dir, "app/views/admin/posts/index.html.erb"), "<h1>Admin posts</h1>")

      result = scan_with_rails_checks(dir)

      route_messages = route_messages(result)
      assert_empty route_messages, route_messages.join("\n")
    end
  end

  def test_singular_resources_use_plural_controller_names
    Dir.mktmpdir do |dir|
      write_minimal_rails_app(dir)
      File.write(File.join(dir, "config/routes.rb"), <<~RUBY)
        Rails.application.routes.draw do
          resource :status, only: :show
          resource :person, only: :show
        end
      RUBY
      write_controller(dir, "statuses_controller.rb", "StatusesController", "show", body: "head :ok")
      write_controller(dir, "people_controller.rb", "PeopleController", "show", body: "head :ok")

      result = scan_with_rails_checks(dir)

      route_messages = route_messages(result)
      assert_empty route_messages, route_messages.join("\n")
    end
  end

  def test_namespace_and_scope_module_routes_resolve_controller_paths
    Dir.mktmpdir do |dir|
      write_minimal_rails_app(dir)
      File.write(File.join(dir, "config/routes.rb"), <<~RUBY)
        Rails.application.routes.draw do
          namespace :admin do
            resources :posts, only: %i[index]
            get "dashboard", to: "dashboards#show"
          end

          scope module: :nest do
            resources :routines, only: :show
          end

          scope module: :admin,
            path: "admin-extra" do
            resources :reports, only: :index
          end
        end
      RUBY
      write_controller(dir, "admin/posts_controller.rb", "Admin::PostsController", "index")
      write_controller(dir, "admin/dashboards_controller.rb", "Admin::DashboardsController", "show", body: "head :ok")
      write_controller(dir, "admin/reports_controller.rb", "Admin::ReportsController", "index")
      write_controller(dir, "nest/routines_controller.rb", "Nest::RoutinesController", "show", body: "head :ok")
      FileUtils.mkdir_p(File.join(dir, "app/views/admin/posts"))
      File.write(File.join(dir, "app/views/admin/posts/index.html.erb"), "<h1>Admin posts</h1>")
      FileUtils.mkdir_p(File.join(dir, "app/views/admin/reports"))
      File.write(File.join(dir, "app/views/admin/reports/index.html.erb"), "<h1>Admin reports</h1>")

      result = scan_with_rails_checks(dir)

      route_messages = route_messages(result)
      assert_empty route_messages, route_messages.join("\n")
    end
  end

  def test_devise_controller_inherited_actions_are_not_reported_as_missing
    Dir.mktmpdir do |dir|
      write_minimal_rails_app(dir)
      File.write(File.join(dir, "config/routes.rb"), <<~RUBY)
        Rails.application.routes.draw do
          get "/users/sign_in", to: "users/sessions#new"
          delete "/users/sign_out", to: "users/sessions#destroy"
        end
      RUBY
      FileUtils.mkdir_p(File.join(dir, "app/controllers/users"))
      File.write(File.join(dir, "app/controllers/users/sessions_controller.rb"), <<~RUBY)
        class Users::SessionsController < Devise::SessionsController
          private

          def after_sign_in_path_for(resource)
            root_path
          end
        end
      RUBY

      result = scan_with_rails_checks(dir)

      route_messages = route_messages(result)
      refute route_messages.any? { |message| message.include?("users/sessions#new") }, route_messages.join("\n")
      refute route_messages.any? { |message| message.include?("after_sign_in_path_for") }, route_messages.join("\n")
    end
  end

  def test_devise_controller_only_suppresses_actions_inherited_by_that_controller_type
    Dir.mktmpdir do |dir|
      write_minimal_rails_app(dir)
      File.write(File.join(dir, "config/routes.rb"), <<~RUBY)
        Rails.application.routes.draw do
          get "/users/session/edit", to: "users/sessions#edit"
        end
      RUBY
      FileUtils.mkdir_p(File.join(dir, "app/controllers/users"))
      File.write(File.join(dir, "app/controllers/users/sessions_controller.rb"), <<~RUBY)
        class Users::SessionsController < Devise::SessionsController
        end
      RUBY

      result = scan_with_rails_checks(dir)

      route_messages = route_messages(result)
      assert route_messages.any? { |message| message.include?("users/sessions#edit") }, route_messages.join("\n")
    end
  end

  private

  def write_minimal_rails_app(dir)
    FileUtils.mkdir_p(File.join(dir, "config"))
    File.write(File.join(dir, "config/application.rb"), "module TestApp; class Application; end; end")
    File.write(File.join(dir, "Gemfile"), "source \"https://rubygems.org\"\ngem \"rails\"\n")
  end

  def scan_with_rails_checks(dir)
    config = RailsDoctor::Config.new(
      project_root: dir,
      data: {
        "profiles" => {
          "fast" => {
            "adapters" => ["rails_checks"]
          }
        }
      }
    )
    RailsDoctor::Scanner.new(project_root: dir, config: config, env: test_env).run(profile: "fast")
  end

  def write_controller(dir, path, class_name, action, body: nil)
    target = File.join(dir, "app/controllers", path)
    FileUtils.mkdir_p(File.dirname(target))
    File.write(target, <<~RUBY)
      class #{class_name} < ApplicationController
        def #{action}
          #{body}
        end
      end
    RUBY
  end

  def write_controller_with_actions(dir, path, class_name, actions)
    target = File.join(dir, "app/controllers", path)
    FileUtils.mkdir_p(File.dirname(target))
    action_source = actions.map do |action|
      <<~RUBY
        def #{action}
          head :ok
        end
      RUBY
    end.join("\n")
    File.write(target, <<~RUBY)
      class #{class_name} < ApplicationController
      #{action_source}
      end
    RUBY
  end

  def route_messages(result)
    result.findings
      .select { |finding| %w[routing dead-code].include?(finding.category) }
      .map(&:message)
  end
end
