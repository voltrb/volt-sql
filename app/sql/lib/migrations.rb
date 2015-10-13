# The base class for migrations
module Volt
  class Migration
    def initialize(db)
      @db = db
    end

    def add_column(table_name, column_name, klasses, options={})
      sequel_type, sequel_options = Helper.column_type_and_options_for_sequel(klasses, options)
      @db.alter_table(table_name) do
        add_column(column_name, sequel_type, sequel_options)
      end
    end

    def rename_column(table_name, from, to, options={})
      # TODO: add options check
      @db.alter_table(table_name) do
        rename_column from, to
      end
    end

    def drop_column(table_name, column_name)
      @db.alter_table(table_name) do
        drop_column column_name
      end
    end

    def set_column_type(table_name, column_name, type, options={})
      @db.alter_table(table_name) do
        set_column_type(column_name, type, options)
      end
    end

    def set_column_allow_null(table_name, column_name)
      @db.alter_table(table_name) do
        set_column_allow_null(column_name)
      end
    end

    def set_column_not_null(table_name, column_name)
      @db.alter_table(table_name) do
        set_column_not_null(column_name)
      end
    end

  end
end
