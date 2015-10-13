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
          :nil  => :allow_null
        }.each_pair do |opts_key, db_key|
          options[opts_key] = db_field[db_key] if db_field.has_key?(db_key)
        end

        db_type = db_field[:db_type].to_sym

        case db_field[:type]
        when :string
          klasses << String
        when :datetime
          klasses << Time
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
        elsif klass == Volt::Boolean || klass == TrueClass || klass == FalseClass
          klass = TrueClass # what sequel uses for booleans
        end

        return klass, options
      end

    end
  end
end
