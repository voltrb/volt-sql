# We can't use Volt::Model until after the reconcile step has happened, so
# these methods work directly with the database.

module Volt
  class MigrationRunner
    alias_method :__run__, :run

    def run(direction=:up, until_version=nil)
      # reconcile after run in production
      # if Volt.env.production?
      #   Volt.current_app.database.reconcile!
      # end

      __run__(direction, until_version)
    end

    def raw_db
      @raw_db ||= Volt.current_app.database.raw_db
    end

    def ensure_migration_versions_table
      if !raw_db.tables || !raw_db.tables.include?(:migration_versions)
        raw_db.create_table(:migration_versions) do
          primary_key :id
          Fixnum :version, unique: true
        end
      end
    end

    def add_version(version)
      raw_db[:migration_versions].insert(version: version)
    end

    def has_version?(version)
      raw_db.from(:migration_versions).where(version: version).count > 0
    end

    def remove_version(version)
      raw_db.from(:migration_versions).where(version: version).delete
    end

    def all_versions
      raw_db.from(:migration_versions).all.map {|v| v[:version] }
    end
  end
end
