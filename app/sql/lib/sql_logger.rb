module Volt
  module Sql
    module SqlLogger

      def log(msg)
        if ENV['LOG_SQL']
          Volt.logger.log_with_color(msg, :cyan)
        end
      end

    end
  end
end
