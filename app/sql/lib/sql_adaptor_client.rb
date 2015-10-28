module Volt
  class DataStore
    class SqlAdaptorClient < BaseAdaptorClient
      data_store_methods :where, :offset, :skip, :order, :limit, :count, :includes

      module SqlArrayStore
        def skip(*args)
          add_query_part(:offset, *args)
        end

        # Count without arguments or a block makes its own query to the backend.
        # If you pass an arg or block, it will run ```all``` on the Cursor, then
        # run a normal ruby ```.count``` on it, passing the args.
        def count(*args, &block)
          if args || block
            @model.reactive_count(*args, &block)
          else
            cursor = add_query_part(:count)

            cursor.persistor.value
          end
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


      # In the volt query dsl (and sql), there's a lot of ways to express the
      # same query.  Its better for performance however if queries can be
      # uniquely identified.  To make that happen, we normalize queries.
      def self.normalize_query(query)
        # query = convert_wheres_to_block(query)
        query = merge_wheres_and_move_to_front(query)

        query = reject_offset_zero(query)

        query
      end

      # Where's can use either a hash arg, or a block.  If the where has a hash
      # arg, we convert it to block style, so it can be unified.
      def self.convert_wheres_to_block(query)
        wheres = []

        query.reject! do |query_part|
          if query_part[0] == 'where'
            wheres << query_part
            # reject
            true
          else
            # keep
            false
          end
        end
      end

      def self.merge_wheres_and_move_to_front(query)
        # Map first parts to string
        query = query.map { |v| v[0] = v[0].to_s; v }
        has_where = query.find { |v| v[0] == 'find' }

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

      def self.reject_offset_zero(query)
        query.reject do |query_part|
          query_part[0] == 'offset' && query_part[1] == 0
        end
      end

    end
  end
end
