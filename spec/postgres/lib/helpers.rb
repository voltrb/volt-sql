module Volt
  module Spec
    module Helpers

      def reconcile!
        # trigger the reconcile
        db_adaptor.db
      end

      def remove_model(klass)
        klass_name = klass.name.to_sym
        Volt::RootModels.remove_model_class(klass)
        Object.send(:remove_const, klass_name)
      end

      def indexes(table_name)
        Volt::Sql::Helper.normalized_indexes_from_table(db, table_name)
      end

    end
  end
end
