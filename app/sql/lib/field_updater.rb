# The FieldUpdater class is responsible for adding or updating a field, either
# by calling sequel directly, or by generating a migration, then running it.
require 'sql/lib/sql_logger'

module Volt
  module Sql
    class FieldUpdater
      include SqlLogger

      def initialize(db, table_reconcile)
        @db = db
        @table_reconcile = table_reconcile
      end

      # Update a field (or create it)
      def update_field(model_class, table_name, db_field, column_name, klasses, opts)
        sequel_class, sequel_opts = Helper.column_type_and_options_for_sequel(klasses, opts)

        # Check if column exists
        if !db_field

          log("Add field #{column_name} to #{table_name}")
          # Column does not exist, add it.
          # Make sure klass matches
          @db.add_column(table_name, column_name, sequel_class, sequel_opts)
        else
          db_class, db_opts = @table_reconcile.sequel_class_and_opts_from_db(db_field)

          if db_class != sequel_class || db_opts != sequel_opts

            # Data type has changed, migrate
            up_code = []
            down_code = []

            # First remove the default values
            db_default = db_opts.delete(:default)
            sequel_default = sequel_opts.delete(:default)

            if db_default != sequel_default
              up_code << "if column_exists?(#{table_name.inspect}, #{column_name.inspect})\n  set_column_default #{table_name.inspect}, #{column_name.inspect}, #{sequel_default.inspect}\nend"
              down_code << "set_column_default #{table_name.inspect}, #{column_name.inspect}, #{db_default.inspect}"
            end

            if db_opts != sequel_opts
              # Fetch allow_null, keeping in mind it defaults to true
              db_null = db_opts.fetch(:allow_null, true)
              sequel_null = sequel_opts.fetch(:allow_null, true)

              if db_null != sequel_null
                # allow null changed
                if sequel_null
                  up_code << "if column_exists?(#{table_name.inspect}, #{column_name.inspect})\n  set_column_allow_null #{table_name.inspect}, #{column_name.inspect}\nend"
                  down_code << "set_column_not_null #{table_name.inspect}, #{column_name.inspect}"
                else
                  up_code << "if column_exists?(#{table_name.inspect}, #{column_name.inspect})\n  set_column_not_null #{table_name.inspect}, #{column_name.inspect}\nend"
                  down_code << "set_column_allow_null #{table_name.inspect}, #{column_name.inspect}"
                end

                db_opts.delete(:allow_null)
                sequel_opts.delete(:allow_null)
              end
            end


            if db_class != sequel_class || db_opts != sequel_opts
              up_code << "if column_exists?(#{table_name.inspect}, #{column_name.inspect})\n  set_column_type #{table_name.inspect}, #{column_name.inspect}, #{sequel_class}, #{sequel_opts.inspect}\nend"
              down_code << "set_column_type #{table_name.inspect}, #{column_name.inspect}, #{db_class}, #{db_opts.inspect}"
            end


            if up_code.present?
              generate_and_run("column_change_#{table_name.to_s.gsub('/', '_')}_#{column_name}", up_code.join("\n"), down_code.join("\n"))
            end

            # TODO: Improve message
            # raise "Data type changed, can not migrate field #{name} from #{db_field.inspect} to #{klass.inspect}"
          end
        end

      end


      def auto_migrate_field_rename(table_name, from_name, to_name)
        log("Rename #{from_name} to #{to_name} on table #{table_name}")

        name = "rename_#{table_name}_#{from_name}_to_#{to_name}"
        up_code = "if column_exists?(#{table_name.inspect}, #{from_name.inspect})\n  rename_column #{table_name.inspect}, #{from_name.inspect}, #{to_name.inspect}\nend"
        down_code = "rename_column #{table_name.inspect}, #{to_name.inspect}, #{from_name.inspect}"
        generate_and_run(name, up_code, down_code)
      end

      def auto_migrate_remove_field(table_name, column_name, db_field)
        log("Remove #{column_name} from table #{table_name}")

        name = "remove_#{table_name}_#{column_name}"
        up_code = "if column_exists?(#{table_name.inspect}, #{column_name.inspect})\n  drop_column #{table_name.inspect}, #{column_name.inspect}\nend"

        sequel_class, sequel_options = @table_reconcile.sequel_class_and_opts_from_db(db_field)
        down_code = "add_column #{table_name.inspect}, #{column_name.inspect}, #{sequel_class}, #{sequel_options.inspect}"
        generate_and_run(name, up_code, down_code)
      end

      # private
      def generate_and_run(name, up_code, down_code)
        puts "GAR: #{up_code.inspect}"
        path = Volt::Sql::MigrationGenerator.create_migration(name, up_code, down_code)

        Volt::MigrationRunner.new(@db).run_migration(path, :up)
      end

    end
  end
end
