require "active_record"

ActiveRecord::Base.establish_connection \
  adapter: "sqlite3", database: ":memory:", migrations_paths: File.expand_path("../dummy/db/migrate", __dir__)

ActiveRecord::Base.connection.migration_context.migrate
