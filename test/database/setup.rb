require "active_record"

ActiveRecord::Base.establish_connection \
  adapter: "sqlite3", database: ":memory:"

migrations_path = File.expand_path("../dummy/db/migrate", __dir__)
ActiveRecord::MigrationContext.new(migrations_path).migrate
