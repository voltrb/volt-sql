require 'sql/lib/table_reconcile'
require 'uri'

module Volt
  # Add reconcile! directly to the model (on the server)
  class Model
    class_attribute :reconciled
  end

  class MultiTypeException < Exception

  end

  module Sql
    class Reconcile
      attr_reader :db
      def initialize(adaptor, db)
        @adaptor = adaptor
        @db = db
      end

      # reconcile takes the database from its current state to the state defined
      # in the model classes with the field helper
      def reconcile!
        table_reconciles = []
        Volt::RootModels.model_classes.each do |model_class|
          table_reconciles << TableReconcile.new(@adaptor, @db, model_class)
        end

        # Make any missing tables
        table_reconciles.each(&:ensure_table)

        # Make sure the migrations are up to date first.
        Volt::MigrationRunner.new(@db).run

        # After the migrations, reconcile tables
        table_reconciles.each(&:run)

        # After the initial reconcile!, we add a listener for any new models
        # created, so we can reconcile them (in specs mostly)
        reset!
        @@listener = RootModels.on('model_created') do |model_class|
          # We do a full invalidate and wait for the next db access, because the
          # model_created gets called before the class is actually fully defined.
          # (ruby inherited limitation)
          @adaptor.invalidate_reconcile!
        end
      end


      # Called to clear the listener
      def reset!
        if defined?(@@listener) && @@listener
          @@listener.remove
          @@listener = nil
        end
      end

    end
  end
end
