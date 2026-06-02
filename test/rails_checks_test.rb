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
end
