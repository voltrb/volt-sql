module Volt
  module Sql
    module SqlLogger

      def log(msg)
        Volt.logger.log_with_color(msg, :cyan)
      end

    end
  end
end
