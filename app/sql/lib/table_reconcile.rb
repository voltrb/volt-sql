# Table Reconcile is responsible for migrating a table from the database state
# to the model state.
require 'sql/lib/sql_logger'
require 'sql/lib/field_updater'
require 'sql/lib/index_updater'

module Volt
  module Sql
    class TableReconcile
      include SqlLogger

      attr_reader :field_updater

      def initialize(adaptor, db, model_class)
        @model_class = model_class
        @adaptor = adaptor
        @db = db
        @field_updater = FieldUpdater.new(@db, self)
      end

      def run
        table_name = @model_class.collection_name

        ensure_table(table_name)

        update_fields(@model_class, table_name)

        IndexUpdater.new(@db, @model_class, table_name)

        @model_class.reconciled = true
      end

      # Create an empty table if one does not exist
      def ensure_table(table_name)
        # Check if table exists
        if !@db.tables || !@db.tables.include?(table_name)
          log("Creating Table #{table_name}")
          adaptor_name = @adaptor.adaptor_name
          @db.create_table(table_name) do
            # guid id
            column :id, String, :unique => true, :null => false, :primary_key => true

            # When using underscore notation on a field that does not exist, the
            # data will be stored in extra.
            if adaptor_name == 'postgres'
              # Use jsonb
              column :extra, 'json'
            else
              column :extra, String
            end
          end
          # TODO: there's some issue with @db.schema and no clue why, but I
          # have to run this again to get .schema to work later.
          @db.tables
        end
      end


      def sequel_class_and_opts_from_db(db_field)
        vclasses, vopts = Helper.klasses_and_options_from_db(db_field)
        return Helper.column_type_and_options_for_sequel(vclasses, vopts)
      end

      # Pulls the db_fields out of sequel
      def db_fields_for_table(table_name)
        db_fields = {}
        result = @db.schema(table_name).each do |col|
          db_fields[col[0].to_sym] = col[1]
        end

        db_fields
      end

      def update_fields(model_class, table_name)
        if (fields = model_class.fields)
          db_fields = db_fields_for_table(table_name)

          db_fields.delete(:id)
          db_fields.delete(:extra)

          orphan_fields = db_fields.keys - fields.keys
          new_fields = fields.keys - db_fields.keys

          # If a single field was renamed, we can auto-migrate
          if (orphan_fields.size == 1 && new_fields.size == 1)
            from_name = orphan_fields[0]
            to_name = new_fields[0]
            @field_updater.auto_migrate_field_rename(table_name, from_name, to_name)

            # Move in start fields
            db_fields[to_name] = db_fields.delete(from_name)
          end

          if new_fields.size == 0 && orphan_fields.size > 0
            # one or more fields were removed
            orphan_fields.each do |field_name|
              @field_updater.auto_migrate_remove_field(table_name, field_name, db_fields[field_name])
            end
          end


          if orphan_fields.size == 0

            fields.each do |name, klass_and_opts|
              name = name.to_sym
              klasses, opts = klass_and_opts

              # Get the original state for the field
              db_field = db_fields.delete(name)

              @field_updater.update_field(model_class, table_name, db_field, name, klasses, opts)
            end

            # remove any fields we didn't see in the models
          end
        else
          # Either >1 orphaned fields, or more than one new fields
          raise "Could not auto migrate #{table_name}"
        end
      end
    end
  end
end
