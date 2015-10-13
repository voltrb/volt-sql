module Volt
  class DataStore
    class SqlAdaptorClient < BaseAdaptorClient
      data_store_methods :where, :offset, :skip, :order, :limit, :count

      module SqlArrayStore
        def skip(*args)
          add_query_part(:offset, *args)
        end

        def count
          cursor = add_query_part(:count)

          cursor.persistor.value
        end
      end

      # Due to the way define_method works, we need to remove the generated
      # methods from data_store_methods before we over-ride them.
      Volt::Persistors::ArrayStore.send(:remove_method, :skip)
      Volt::Persistors::ArrayStore.send(:remove_method, :count)

      # include sql's methods on ArrayStore
      Volt::Persistors::ArrayStore.send(:include, SqlArrayStore)

      module SqlArrayModel
        def dataset
          Volt::DataStore.fetch.db.from(collection_name)
        end
      end

      Volt::ArrayModel.send(:include, SqlArrayModel)

      def self.normalize_query(query)
        query = merge_finds_and_move_to_front(query)

        query = reject_order_zero(query)

        query
      end

      def self.merge_finds_and_move_to_front(query)
        # Map first parts to string
        query = query.map { |v| v[0] = v[0].to_s; v }
        # has_find = query.find { |v| v[0] == 'find' }

        # if has_find
        #   # merge any finds
        #   merged_find_query = {}
        #   query = query.reject do |query_part|
        #     if query_part[0] == 'find'
        #       # on a find, merge into finds
        #       find_query = query_part[1]
        #       merged_find_query.merge!(find_query) if find_query

        #       # reject
        #       true
        #     else
        #       false
        #     end
        #   end

        #   # Add finds to the front
        #   query.insert(0, ['find', merged_find_query])
        # else
        #   # No find was done, add it in the first position
        #   query.insert(0, ['find'])
        # end

        query
      end

      def self.reject_order_zero(query)
        query.reject do |query_part|
          query_part[0] == 'order' && query_part[1] == 0
        end
      end

    end
  end
end
