# The IndexUpdater looks at the current indexes on a table and those in the db
# and reconciles them.  Since indexes are immutable, this means dropping any
# that don't match and creating new ones.  (simple)  This also means we don't
# need any migrations.

require 'sql/lib/sql_logger'
require 'sql/lib/helper'

module Volt
  module Sql
    class IndexUpdater
      include SqlLogger

      def initialize(db, model_class, table_name)
        @db = db
        @table_name = table_name

        model_indexes = model_class.indexes
        db_indexes = Helper.normalized_indexes_from_table(@db, table_name)

        model_indexes.each_pair do |name, options|
          # See if we have a matching columns/options
          if db_indexes[name] == options
            # Matches, ignore it
            db_index.delete(name)
          else
            # Something changed, if a db_index for the name exists,
            # delete it, because the options changed
            if (db_opts = db_indexes[name])
              # Drop the index, drop it from the liast of db_indexes
              drop_index(name, db_opts)
              db_indexes.delete(name)
            end

            # Create the new index
            add_index(name, options)
          end
        end

        # drop any remaining db_indexes, because they are no longer defined in
        # the model
        db_indexes.each do |name, options|
          drop_index(name, options)
        end

        @db.indexes(table_name)
      end


      def drop_index(name, options)
        columns, options = columns_and_options(name, options)
        log("drop index on #{columns.inspect}, #{options.inspect}")

        @db.alter_table(@table_name) do
          drop_index(columns, options.select {|k,v| k == :name })
        end
      end

      def add_index(name, options)
        columns, options = columns_and_options(name, options)
        log("add index on #{columns.inspect}, #{options.inspect}")
        @db.alter_table(@table_name) do
          add_index(columns, options)
        end
      end

      private

      # Convert to the columns, options(with name) format used by sequel for
      # add_index/drop_index
      def columns_and_options(name, options)
        options = options.dup
        columns = options.delete(:columns)

        options[:name] = name

        return columns, options
      end

    end
  end
end
