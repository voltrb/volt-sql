# A few pure functions for converting between volt types/options and sequel
# type/options

module Volt
  module Sql
    module Helper


      # This method takes in info from the db schema and returns the volt field
      # klass and options that would have been used to create it.
      #
      # @returns [Array of klasses, Hash of options]
      def self.klasses_and_options_from_db(db_field)
        klasses = []
        options = {}

        # merge values based on map (options key from db_key)
        {
          :text => :text,
          :size => :max_length,
          :nil  => :allow_null,
          :default => :ruby_default
        }.each_pair do |opts_key, db_key|
          options[opts_key] = db_field[db_key] if db_field.has_key?(db_key)
        end

        options.delete(:default) if options[:default] == nil

        db_type = db_field[:db_type].to_sym

        case db_field[:type]
        when :string
          klasses << String
        when :datetime
          klasses << VoltTime
        when :boolean
          klasses << Volt::Boolean
        when :float
          klasses << Float
        else
          case db_type
          when :text
          when :string
            klasses << String
          when :numeric
            klasses << Numeric
          when :integer
            klasses << Fixnum
          end
        end

        if klasses.size == 0
          raise "Could not match database type #{db_type} in #{db_field.inspect}"
        end

        # Default is to allow nil
        unless options[:nil] == false
          klasses << NilClass
        end
        options.delete(:nil)

        return klasses, options
      end


      # Takes in the klass and options specified on the model or an add_column
      # and returns the correct klass/options for add_column in sequel.
      def self.column_type_and_options_for_sequel(klasses, options)
        options = options.dup

        # Remove from start fields
        klasses ||= [String, NilClass]

        allow_nil = klasses.include?(NilClass)
        klasses = klasses.reject {|klass| klass == NilClass }

        if klasses.size > 1
          raise MultiTypeException, 'the sql adaptor only supports a single type (or NilClass) for each field.'
        end

        klass = klasses.first

        if options.has_key?(:nil)
          options[:allow_null] = options.delete(:nil)
        else
          options[:allow_null] = allow_nil
        end

        if klass == String
          # If no length restriction, make it text
          if options[:size]
            if options[:size] > 255
              # Make the field text
              options.delete(:size)
              options[:text] = true
            end
          else
            options[:text] = true
          end
        elsif klass == VoltTime
          klass = Time
        elsif klass == Volt::Boolean || klass == TrueClass || klass == FalseClass
          klass = TrueClass # what sequel uses for booleans
        end

        return klass, options
      end

      # When asking for indexes on a table, the deferrable option will show
      # as nil if it wasn't set, we remove this to normalize it to the volt
      # options.
      def self.normalized_indexes_from_table(db, table_name)
        db.indexes(table_name).map do |name, options|
          # Remove the deferrable that defaults to false (nil)
          options = options.reject {|key, value| key == :deferrable && !value }
          [name, options]
        end.to_h
      end
    end
  end
end
