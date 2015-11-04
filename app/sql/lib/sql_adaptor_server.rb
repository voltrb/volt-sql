require 'sequel'
require 'sequel/extensions/pg_json'
require 'sql/lib/where_call'
require 'fileutils'
require 'thread'
require 'sql/lib/migration'
require 'sql/lib/migration_generator'
require 'sql/lib/migration_runner'
require 'sql/lib/reconcile'
require 'sql/lib/sql_logger'
require 'sql/lib/helper'
require 'volt/utils/data_transformer'


module Volt
  class DataStore
    class SqlAdaptorServer < BaseAdaptorServer
      include Volt::Sql::SqlLogger

      attr_reader :sql_db, :adaptor_name

      # :reconcile_complete is set to true after the initial load and reconcile.
      # Any models created after this point will attempt to be auto-reconciled.
      # This is mainly used for specs.
      attr_reader :reconcile_complete


      def initialize(volt_app)
        @volt_app = volt_app
        @db_mutex = Mutex.new

        Sequel.default_timezone = :utc
        super

        # Add an invalidation callback when we add a new field.  This ensures
        # any fields added after the first db call (which triggers the
        # reconcile) will reconcile again.
        inv_reconcile = lambda { invalidate_reconcile! }
        Volt::Model.instance_eval do
          alias :__field__ :field

          define_singleton_method(:field) do |*args, &block|
            # Call original field
            result = __field__(*args, &block)
            inv_reconcile.call
            result
          end
        end

        @volt_app.on('boot') do
          # call ```db``` to reconcile
          @app_booted = true
          db
        end
      end

      # Set db_driver on public
      Volt.configure do |config|
        config.db_driver = 'sqlite'
      end

      # check if the database can be connected to.
      # @return Boolean
      def connected?
        return true
        begin
          db

          true
        rescue ::Sequel::ConnectionFailure => e
          false
        end
      end

      def db(skip_reconcile=false)
        if @db && @reconcile_complete
          return @db
        end

        @db_mutex.synchronize do
          unless @db
            begin
              @adaptor_name = connect_to_db

              @db.test_connection
            rescue Sequel::DatabaseConnectionError => e
              if e.message =~ /does not exist/
                create_missing_database
              else
                raise
              end

            rescue Sequel::AdapterNotFound => e
              missing_gem = e.message.match(/LoadError[:] cannot load such file -- ([^ ]+)$/)
              if missing_gem
                helpers = {
                  'postgres' => "gem 'pg', '~> 0.18.2'\ngem 'pg_json', '~> 0.1.29'",
                  'sqlite3'  => "gem 'sqlite3'",
                  'mysql2'   => "gem 'mysql2'"
                }

                adaptor_name = missing_gem[1]
                if (helper = helpers[adaptor_name])
                  helper = "\nMake sure you have the following in your gemfile:\n" + helper + "\n\n"
                else
                  helper = ''
                end
                raise NameError.new("LoadError: cannot load the #{adaptor_name} gem.#{helper}")
              else
                raise
              end
            end

            if @adaptor_name == 'postgres'
              @db.extension :pg_json
              # @db.extension :pg_json_ops
            end

            if ENV['LOG_SQL']
              @db.loggers << Volt.logger
            end
          end

          # Don't try to reconcile until the app is booted
          reconcile! if !skip_reconcile && @app_booted
        end

        @db
      end

      # Raw access to the sequel connection without auto-migrating.
      def raw_db
        @db
      end

      # @param - a string URI, or a Hash of options
      # @param - the adaptor name
      def connect_uri_or_options
        # check to see if a uri was specified
        conf = Volt.config

        uri = conf.db && conf.db.uri

        if uri
          adaptor = uri[/^([a-z]+)/]

          return uri, adaptor
        else
          adaptor = (conf.db && conf.db.adapter || 'sqlite').to_s
          if adaptor == 'sqlite'
            # Make sure we have a config/db folder
            FileUtils.mkdir_p('config/db')
          end

          data = Volt.config.db.to_h.symbolize_keys
          data[:database] ||= "config/db/#{Volt.env.to_s}.db"
          data[:adapter]  ||= adaptor

          return data, adaptor
        end
      end

      def connect_to_db
        uri_opts, adaptor = connect_uri_or_options

        @db = Sequel.connect(uri_opts)

        if adaptor == 'sqlite'
          @db.set_integer_booleans
        end

        adaptor
      end

      # In order to create the database, we have to connect first witout the
      # database.
      def create_missing_database
        @db.disconnect
        uri_opts, adaptor = connect_uri_or_options

        if uri_opts.is_a?(String)
          # A uri
          *uri_opts, db_name = uri_opts.split('/')
          uri_opts = uri_opts.join('/')
        else
          # Options hash
          db_name = uri_opts.delete(:database)
        end

        @db = Sequel.connect(uri_opts)

        # No database, try to create it
        log "Database does not exist, attempting to create database #{db_name}"
        @db.run("CREATE DATABASE #{db_name};")
        @db.disconnect
        @db = nil

        connect_to_db
      end

      def reconcile!
        unless @skip_reconcile
          Sql::Reconcile.new(self, @db).reconcile!
        end

        @reconcile_complete = true
      end

      # Mark that a model changed and we need to rerun reconcile next time the
      # db is accessed.
      def invalidate_reconcile!
        @reconcile_complete = false
      end

      # Used when creating a class that you don't want to reconcile after
      def skip_reconcile
        @skip_reconcile = true

        begin
          yield
        ensure
          @skip_reconcile = false
        end
      end

      # Called when the db gets reset (from specs usually)
      def reset!
        Sql::Reconcile.new(self, @db).reset!
      end

      def insert(collection, values)
        values = pack_values(collection, values)

        db.from(collection).insert(values)
      end

      def update(collection, values)
        values = pack_values(collection, values)

        # Find the original so we can update it
        table = db.from(collection)

        # TODO: we should move this to a real upsert
        begin
          table.insert(values)
          log(table.insert_sql(values))
        rescue Sequel::UniqueConstraintViolation => e
          # Already a record, update
          id = values[:id]
          log(table.where(id: id).update_sql(values))
          table.where(id: id).update(values)
        end

        nil
      end

      def query(collection, query)
        allowed_methods = %w(where where_with_block offset limit count)

        result = db.from(collection.to_sym)

        query.each do |query_part|
          method_name, *args = query_part

          unless allowed_methods.include?(method_name.to_s)
            fail "`#{method_name}` is not part of a valid query"
          end

          # Symbolize Keys
          args = args.map do |arg|
            if arg.is_a?(Hash)
              arg = self.class.nested_symbolize_keys(arg)
            end
            arg
          end

          if method_name == :where_with_block
            # Where calls with block are handled differently.  We have to replay
            # the query that was captured on the client with QueryIdentifier

            # Grab the AST that was generated from the block call on the client.
            block_ast = args.pop
            args = self.class.move_to_db_types(args)

            result = result.where(*args) do |ident|
              Sql::WhereCall.new(ident).call(block_ast)
            end
          else
            args = self.class.move_to_db_types(args)
            result = result.send(method_name, *args)
          end
        end

        if result.respond_to?(:all)
          log(result.sql)
          result = result.all.map do |hash|
            # Volt expects symbol keys
            hash.symbolize_keys
          end#.tap {|v| puts "QUERY: " + v.inspect }

          # Unpack extra values
          result = unpack_values!(result)
        end

        result
      end

      def delete(collection, query)
        query = self.class.move_to_db_types(query)
        db.from(collection).where(query).delete
      end

      # remove the collection entirely
      def drop_collection(collection)
        db.drop_collection(collection)
      end

      def drop_database
        RootModels.clear_temporary

        # Drop all tables
        db(true).drop_table(*db.tables)

        RootModels.model_classes.each do |model_klass|
          model_klass.reconciled = false
        end

        invalidate_reconcile!
      end


      def self.move_to_db_types(values)
        values = nested_symbolize_keys(values)

        values = Volt::DataTransformer.transform(values, false) do |value|
          if defined?(VoltTime) && value.is_a?(VoltTime)
            value.to_time
          elsif value.is_a?(Symbol)
            # Symbols get turned into strings
            value.to_s
          else
            value
          end
        end

        values
      end

      private

      def self.nested_symbolize_keys(values)
        DataTransformer.transform_keys(values) do |key|
          key.to_sym
        end
      end

      # Take the values and symbolize them, and also remove any values that
      # aren't going in fields and move them into extra.
      #
      # Then change VoltTime's to Time for Sequel
      def pack_values(collection, values)
        values = self.class.move_to_db_types(values)

        klass = Volt::Model.class_at_path([collection])
        # Find any fields in values that aren't defined with a ```field```,
        # and put them into extra.
        extra = {}
        values = values.select do |key, value|
          if klass.fields[key] || key == :id
            # field is defined, keep in values
            true
          else
            # field does not exist, move to extra
            extra[key] = value

            false
          end
        end

        # Copy the extras into the values
        values[:extra] = serialize(extra) if extra.present?

        # Volt.logger.info("Insert into #{collection}: #{values.inspect}")

        values
      end

      # Loop through the inputs array and change values in place to be unpacked.
      # Unpacking means moving the extra field out and into the main fields.
      #
      # Then transform Time to VoltTime
      def unpack_values!(inputs)
        values = inputs.each do |values|
          extra = values.delete(:extra)

          if extra
            extra = deserialize(extra)
            self.class.nested_symbolize_keys(extra.to_h).each_pair do |key, new_value|
              unless values[key]
                values[key] = new_value
              end
            end
          end
        end

        values = Volt::DataTransformer.transform(values) do |value|
          if defined?(VoltTime) && value.is_a?(Time)
            value = VoltTime.from_time(value)
          else
            value
          end
        end

        values
      end

    end


    # Specific adaptors for each database
    class PostgresAdaptorServer < SqlAdaptorServer
      def serialize(extra)
        Sequel.pg_json(extra)
      end

      def deserialize(extra)
        extra
      end
    end

    class SqliteAdaptorServer < SqlAdaptorServer
      def serialize(extra)
        JSON.dump(extra)
      end

      def deserialize(extra)
        JSON.parse(extra)
      end
    end

    class MysqlAdaptorServer < SqlAdaptorServer
    end
  end
end
