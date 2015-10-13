# Reopen the store class and tell it not to allow "on the fly" collections.
module Volt
  module Persistors
    class Store
      def on_the_fly_collections?
        false
      end
    end
  end
end